"""
offload_engine.py
------------------
Logica de baza pentru DataMover: scanare surse, copiere cu verificare
(mai multe modele de securitate posibile), excludere fisiere/extensii,
verificare spatiu liber, detectare automata a volumelor/drive-urilor
montate (macOS si Windows), suport pentru anulare in timpul copierii,
progres separat copiere/verificare, progres per destinatie (viteza
curenta) si checkpoint pentru reluare automata la erori.

Fara dependinte externe obligatorii (doar librarie standard Python).
Notificarile native folosesc optional libraria "plyer" (cross-platform);
daca lipseste, notificarile sunt pur si simplu omise, fara sa afecteze
restul aplicatiei.
"""

import os
import csv
import json
import time
import shutil
import string
import tempfile
import hashlib
import platform
import subprocess
from datetime import datetime

from . import checkpoint as ckpt
from . import io_settings

CHUNK_SIZE = io_settings.DEFAULT_CHUNK_SIZE_MB * 1024 * 1024  # fallback, vezi io_settings.get_chunk_size_bytes()

# Numarul de fisiere pastrate ca "esantion" pentru raportul PDF (Regula
# "Log-uri si Stare UI" din cerere - nu tinem in memorie randul fiecarui
# fisier dintr-un transfer de sute de mii de fisiere doar ca sa-l desenam
# intr-un PDF pe care oricum nimeni nu-l citeste rand cu rand pana la
# capat). CSV-ul de langa el ramane complet, scris incremental pe disc -
# el e sursa de adevar completa, nu PDF-ul.
PDF_SAMPLE_LIMIT = 500

# Cate fisiere sunt grupate intr-un "lot" la scanare/iterare lazy - vezi
# scan_files_streaming/iter_manifest_batches. Tine memoria plafonata
# indiferent daca sursa are 1.000 sau 2.000.000 de fisiere.
SCAN_BATCH_SIZE = 1000


class _OffloadCancelled(Exception):
    """Ridicata intern cand cancel_event e setat in timpul copierii sau
    hash-uirii unui singur fisier - permite intreruperea in mijlocul unui
    fisier urias (clip video de zeci de GB), nu doar intre fisiere."""
    pass


def _copy_file_cancelable(src, dst, cancel_event, chunk_size=CHUNK_SIZE):
    """Copiaza src -> dst in bucati de chunk_size (configurabil din
    Setari I/O & Memorie - vezi io_settings.py), verificand cancel_event
    intre bucati - spre deosebire de un singur shutil.copy2() blocant,
    asta face ca butonul Anuleaza sa opreasca efectiv copierea unui
    fisier urias in cateva secunde, nu abia dupa ce acel fisier termina
    (care, pentru un clip video de zeci de GB pe un drive lent, poate
    insemna minute intregi in care Anuleaza pare sa nu faca nimic).

    Streaming real: niciodata mai mult de un singur "chunk_size" din
    fisier in memorie deodata (nu shutil.copy2/fsrc.read() fara argument,
    care ar incarca tot fisierul). Citirea urmatorului bloc asteapta
    mereu scrierea celui curent (acelasi thread, secvential) - asta
    ofera backpressure natural intre citire (SSD rapid) si scriere (HDD
    lent): nu exista niciun buffer de "read-ahead" care sa acumuleze date
    nescrise inca in RAM."""
    try:
        with open(src, "rb") as fsrc, open(dst, "wb") as fdst:
            while True:
                if cancel_event is not None and cancel_event.is_set():
                    raise _OffloadCancelled()
                chunk = fsrc.read(chunk_size)
                if not chunk:
                    break
                fdst.write(chunk)
    except _OffloadCancelled:
        # nu lasam un fisier partial, pe jumatate copiat, care ar putea fi
        # confundat mai tarziu cu unul complet
        try:
            if os.path.exists(dst):
                os.remove(dst)
        except OSError:
            pass
        raise
    shutil.copystat(src, dst)  # pastreaza data modificarii etc., ca shutil.copy2


def format_size(num_bytes):
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if num_bytes < 1024.0:
            return f"{num_bytes:.1f} {unit}"
        num_bytes /= 1024.0
    return f"{num_bytes:.1f} PB"


DEFAULT_EXCLUSIONS = [
    ".DS_Store", "Thumbs.db", "desktop.ini", ".tmp",
    ".Trashes", ".Spotlight-V100", ".fseventsd", "System Volume Information",
]

# Modele de securitate disponibile pentru verificarea fisierelor copiate.
# Cheia e valoarea interna folosita in cod; "label" e ce vede utilizatorul,
# "hashlib_name" e None pentru modul care nu foloseste checksum.
VERIFICATION_MODELS = {
    "size_only": {
        "label": "Doar dimensiune fisier (fara checksum - cel mai rapid, mai putin sigur)",
        "hashlib_name": None,
    },
    "md5": {
        "label": "MD5 (rapid - standard in industrie)",
        "hashlib_name": "md5",
    },
    "sha1": {
        "label": "SHA-1 (echilibrat - putin mai sigur decat MD5)",
        "hashlib_name": "sha1",
    },
    "sha256": {
        "label": "SHA-256 (sigur - recomandat pentru arhivare pe termen lung)",
        "hashlib_name": "sha256",
    },
    "sha512": {
        "label": "SHA-512 (maxim de siguranta - cel mai lent)",
        "hashlib_name": "sha512",
    },
}

DEFAULT_VERIFICATION_MODEL = "md5"


def hash_of_file(path, hashlib_name, cancel_event=None, chunk_size=CHUNK_SIZE):
    """Calculeaza hash-ul unui fisier folosind algoritmul specificat (md5, sha1,
    sha256, sha512...). Returneaza hexdigest-ul. Daca se da un cancel_event
    si e setat in timpul hash-uirii (poate dura la fel de mult ca si
    copierea, pe fisiere mari), ridica _OffloadCancelled."""
    h = hashlib.new(hashlib_name)
    with open(path, "rb") as f:
        while True:
            if cancel_event is not None and cancel_event.is_set():
                raise _OffloadCancelled()
            chunk = f.read(chunk_size)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def _is_excluded(filename, exclusions):
    """Verifica daca un fisier trebuie exclus, dupa nume exact sau extensie."""
    if filename.startswith("."):
        # fisiere ascunse de sistem - excluse implicit
        return True
    lower = filename.lower()
    for pattern in exclusions:
        pattern = pattern.strip().lower()
        if not pattern:
            continue
        if pattern.startswith("."):
            if lower.endswith(pattern):
                return True
        elif lower == pattern:
            return True
    return False


def list_all_files(root, exclusions=None):
    """Returneaza lista de (full_path, relative_path, size) pentru fisierele din root,
    excluzand fisierele ascunse de sistem si orice e in lista de excluderi."""
    if exclusions is None:
        exclusions = DEFAULT_EXCLUSIONS
    files = []
    for dirpath, _dirnames, filenames in os.walk(root):
        for fn in filenames:
            if _is_excluded(fn, exclusions):
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, root)
            try:
                size = os.path.getsize(full)
            except OSError:
                size = 0
            files.append((full, rel, size))
    return files


def scan_files_streaming(root, exclusions=None):
    """Varianta "lazy" a list_all_files: parcurge sursa cu os.walk ca si
    inainte, dar NU construieste o lista Python cu toate fisierele in
    memorie (poate fi sute de mii/milioane de intrari la 3+ TB) - scrie
    fiecare intrare direct pe disc, intr-un fisier manifest temporar
    (JSON Lines: un rand = un fisier), pastrand in memorie doar
    numaratorile agregate.

    Returneaza (total_files, total_bytes, manifest_path). Apelantul e
    responsabil sa stearga manifest_path cand nu mai are nevoie de el
    (vezi DestinationJob.run / cleanup_manifest)."""
    if exclusions is None:
        exclusions = DEFAULT_EXCLUSIONS
    fd, manifest_path = tempfile.mkstemp(prefix="datamover_scan_", suffix=".jsonl")
    total_files = 0
    total_bytes = 0
    with os.fdopen(fd, "w", encoding="utf-8") as manifest:
        for dirpath, _dirnames, filenames in os.walk(root):
            for fn in filenames:
                if _is_excluded(fn, exclusions):
                    continue
                full = os.path.join(dirpath, fn)
                rel = os.path.relpath(full, root)
                try:
                    size = os.path.getsize(full)
                except OSError:
                    size = 0
                manifest.write(json.dumps({"rel": rel, "size": size}) + "\n")
                total_files += 1
                total_bytes += size
    return total_files, total_bytes, manifest_path


def iter_manifest_batches(manifest_path, source_root, batch_size=SCAN_BATCH_SIZE):
    """Genereaza loturi (liste) de cel mult batch_size tupluri
    (full_path, rel_path, size), citind manifestul scris de
    scan_files_streaming rand cu rand - memoria folosita ramane
    plafonata la marimea unui singur lot, indiferent cate fisiere are
    sursa in total (cerinta "Scanare & Recursivitate fara Memorie
    Acumulata")."""
    batch = []
    with open(manifest_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            entry = json.loads(line)
            rel = entry["rel"]
            full = os.path.join(source_root, rel)
            batch.append((full, rel, entry["size"]))
            if len(batch) >= batch_size:
                yield batch
                batch = []
    if batch:
        yield batch


def cleanup_manifest(manifest_path):
    """Sterge fisierul manifest temporar - best-effort, nu trebuie sa
    opreasca aplicatia daca esueaza (ex. deja sters)."""
    try:
        if manifest_path and os.path.isfile(manifest_path):
            os.remove(manifest_path)
    except OSError:
        pass


def get_free_space_bytes(path):
    """Spatiul liber (in bytes) disponibil pe volumul unde se afla path."""
    try:
        usage = shutil.disk_usage(path)
        return usage.free
    except OSError:
        return None


def list_mounted_volumes():
    """Detecteaza automat volumele/drive-urile montate (carduri, drive-uri
    externe), functionand atat pe macOS cat si pe Windows.

    - macOS: citeste continutul /Volumes
    - Windows: verifica literele de drive disponibile (A: - Z:)
    - Alte sisteme (Linux): incearca /media/<user> si /mnt

    Returneaza o lista de path-uri absolute (poate fi goala daca nu
    detecteaza nimic sau daca sistemul nu e recunoscut)."""
    system = platform.system()
    result = []

    if system == "Darwin":
        volumes_dir = "/Volumes"
        if os.path.isdir(volumes_dir):
            try:
                for name in sorted(os.listdir(volumes_dir)):
                    full = os.path.join(volumes_dir, name)
                    if os.path.isdir(full):
                        result.append(full)
            except OSError:
                pass
    elif system == "Windows":
        try:
            import ctypes
            bitmask = ctypes.windll.kernel32.GetLogicalDrives()
            for i, letter in enumerate(string.ascii_uppercase):
                if bitmask & (1 << i):
                    drive = f"{letter}:\\"
                    if os.path.exists(drive):
                        # excludem C:\ (de obicei discul de sistem) din lista,
                        # ca sa evidentiem in special drive-urile externe/carduri
                        if letter != "C":
                            result.append(drive)
        except Exception:
            pass
    else:
        # Linux si alte sisteme: incercam locatiile uzuale de montare
        for base in (f"/media/{os.environ.get('USER', '')}", "/media", "/mnt"):
            if base and os.path.isdir(base):
                try:
                    for name in sorted(os.listdir(base)):
                        full = os.path.join(base, name)
                        if os.path.isdir(full):
                            result.append(full)
                except OSError:
                    pass

    return result


def log_master(message, log_file="offload_master.log"):
    """Scrie un mesaj intr-un jurnal centralizat, in folderul aplicatiei.
    Util pentru istoric/depanare pe termen lung (cine, cand, ce offload-uri
    s-au facut) - separat de rapoartele CSV/PDF per destinatie. Scrierea e
    best-effort: daca esueaza (folder needscriptibil etc.) nu opreste
    aplicatia."""
    try:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        log_path = os.path.join(script_dir, log_file)
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(f"[{timestamp}] {message}\n")
    except Exception:
        pass  # Nu lasa aplicatia sa se opreasca daca logarea esueaza


def send_notification(title, message):
    """Trimite o notificare nativa (Notification Center pe macOS, Toast pe
    Windows) folosind libraria optionala 'plyer'. Nu face nimic (silentios)
    daca 'plyer' lipseste sau notificarea esueaza dintr-un motiv oarecare -
    notificarile sunt un bonus, nu trebuie sa opreasca aplicatia."""
    try:
        from plyer import notification
        notification.notify(title=title, message=message, timeout=6)
        return
    except Exception:
        pass

    # rezerva pentru macOS daca 'plyer' lipseste: folosim osascript direct
    if platform.system() == "Darwin":
        try:
            script = f'display notification "{message}" with title "{title}" sound name "Glass"'
            subprocess.run(["osascript", "-e", script], check=False,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
        except Exception:
            pass


class CancelledError(Exception):
    pass


class DestinationJob:
    """Gestioneaza copierea + verificarea pentru o singura destinatie.

    Progres:
    - progress_counter / bytes_counter (partajate global intre toate
      destinatiile, ca inainte) tin bara de progres GLOBALA.
    - copy_counter / verify_counter (idem, partajate global, optionale)
      permit separarea vizuala "Copiere: X% | Verificare: Y%" in UI.
    - files_done / bytes_done / current_speed_bps / phase_text sunt
      atribute LOCALE ale job-ului (nu necesita lock strict - sunt scrise
      doar de thread-ul acestui job si citite periodic de UI pentru bara
      de progres PROPRIE a acestei destinatii).

    Checkpoint / reluare:
    - resume=True: la pornire, citeste offload_checkpoint.json din
      target_root (daca exista) si sare peste fisierele deja "ok"/"sarit".
    - checkpoint-ul e rescris pe disc periodic (nu la fiecare fisier, ca
      sa nu incetineasca offload-uri cu multe mii de fisiere).
    """

    def __init__(self, dest_root, folder_name, files, log_queue,
                 progress_counter, bytes_counter, progress_lock,
                 skip_existing_identical=False, cancel_event=None,
                 verification_model=DEFAULT_VERIFICATION_MODEL,
                 copy_counter=None, verify_counter=None,
                 resume=False, source_root=None,
                 checkpoint_interval_files=10, checkpoint_interval_seconds=5.0,
                 manifest_path=None, total_files=None, total_bytes=None,
                 chunk_size=None, io_cfg=None, pause_event=None):
        self.dest_root = dest_root
        self.folder_name = folder_name
        # Mod "clasic": lista completa in memorie (folosit de UI-uri mai
        # vechi/scanari mici). Mod "lazy" (recomandat pentru transferuri
        # mari): manifest_path != None - vezi scan_files_streaming() /
        # iter_manifest_batches() - fisierele sunt citite de pe disc, in
        # loturi de SCAN_BATCH_SIZE, niciodata toate deodata in RAM.
        self.files = files  # list of (full_path, rel_path, size) sau None
        self.manifest_path = manifest_path
        self.log_queue = log_queue
        self.progress_counter = progress_counter
        self.bytes_counter = bytes_counter
        self.progress_lock = progress_lock
        self.skip_existing_identical = skip_existing_identical
        self.cancel_event = cancel_event
        # Pauza (2026-08-28) - threading.Event partajat, la fel ca
        # cancel_event, dar reversibil: set() = pauza, clear() = continua.
        # Vezi Mac PauseToken (OffloadEngine.swift) - acelasi comportament,
        # verificat INTRE fisiere, nu opreste un fisier la mijloc.
        self.pause_event = pause_event
        self.verification_model = verification_model
        self.hashlib_name = VERIFICATION_MODELS.get(
            verification_model, VERIFICATION_MODELS[DEFAULT_VERIFICATION_MODEL]
        )["hashlib_name"]

        # progres global separat copiere/verificare (optional)
        self.copy_counter = copy_counter
        self.verify_counter = verify_counter

        # checkpoint / reluare
        self.resume = resume
        self.source_root = source_root
        self.checkpoint_interval_files = checkpoint_interval_files
        self.checkpoint_interval_seconds = checkpoint_interval_seconds
        self._files_status = {}  # rel_path -> "ok"/"sarit"/"fail"
        self._files_since_checkpoint = 0
        self._last_checkpoint_time = 0.0

        # Setari I/O & Memorie (buffer configurabil + prag RAM pentru
        # backpressure) - vezi io_settings.py si Regula globala "Memory &
        # I/O Performance" din CLAUDE.md.
        self._io_cfg = io_cfg
        self.chunk_size = chunk_size if chunk_size is not None else io_settings.get_chunk_size_bytes(io_cfg)

        # progres LOCAL, per-destinatie (citit de UI pentru bara proprie).
        # In modul lazy, total_files/total_bytes vin deja calculate de
        # scan_files_streaming (care le-a numarat in timp ce scria
        # manifestul) - NU mai recalculam din `files`, care e None.
        if files is not None:
            self.total_files = len(files)
            self.total_bytes = sum(size for _f, _r, size in files)
        else:
            self.total_files = total_files or 0
            self.total_bytes = total_bytes or 0
        self.files_done = 0
        self.bytes_done = 0
        self.current_speed_bps = 0.0
        self.phase_text = "In asteptare..."
        self._job_start_time = None
        self._last_speed_sample_time = None
        self._last_speed_sample_bytes = 0

        # Raport: CSV-ul e scris INCREMENTAL pe disc (vezi _open_csv_writer/
        # _log_row) - nu tinem randul fiecarui fisier in memorie pana la
        # final. Pentru PDF (care oricum nu poate afisa lizibil sute de mii
        # de randuri) pastram doar un esantion plafonat - toate erorile/
        # nepotrivirile plus o mostra din restul, vezi PDF_SAMPLE_LIMIT.
        self._pdf_sample_rows = []
        self._csv_file = None
        self._csv_writer = None
        self.ok_count = 0
        self.skip_count = 0
        self.fail_count = 0
        self.cancelled = False
        self.report_csv_path = None
        self.report_pdf_path = None
        self.started_at = None
        self.finished_at = None

    # ---------------- verificare ----------------

    def _verify_pair(self, full_src, dest_path, size):
        """Verifica sursa vs destinatie conform modelului de securitate ales.
        Returneaza (identice: bool, src_repr: str, dst_repr: str) unde
        src_repr/dst_repr sunt fie hash-uri, fie reprezentari de marime,
        folosite pentru raport."""
        if self.hashlib_name is None:
            # model "doar dimensiune" - nu se calculeaza checksum
            dst_size = os.path.getsize(dest_path) if os.path.isfile(dest_path) else -1
            same = (dst_size == size)
            return same, f"marime={size}", f"marime={dst_size}"
        src_hash = hash_of_file(full_src, self.hashlib_name, self.cancel_event, self.chunk_size)
        dst_hash = hash_of_file(dest_path, self.hashlib_name, self.cancel_event, self.chunk_size)
        return src_hash == dst_hash, src_hash, dst_hash

    # ---------------- checkpoint ----------------

    def _load_resume_state(self, target_root):
        """Incarca checkpoint-ul existent (daca exista) si returneaza setul
        de rel_path deja terminate cu succes (ok/sarit), care vor fi omise."""
        data = ckpt.load_checkpoint(target_root)
        if not data:
            return set()
        self._files_status = dict(data.get("files", {}))
        already_done = {rel for rel, status in self._files_status.items()
                         if status in ("ok", "sarit")}
        if already_done:
            self.log_queue.put(
                f"[{os.path.basename(self.dest_root)}] Reluare: "
                f"{len(already_done)} fisiere deja verificate corect vor fi sarite."
            )
        return already_done

    def _maybe_write_checkpoint(self, force=False):
        self._files_since_checkpoint += 1
        now = time.time()
        due_by_count = self._files_since_checkpoint >= self.checkpoint_interval_files
        due_by_time = (now - self._last_checkpoint_time) >= self.checkpoint_interval_seconds
        if not (force or due_by_count or due_by_time):
            return
        target_root = os.path.join(self.dest_root, self.folder_name)
        ckpt.save_checkpoint(
            target_root, self.source_root, self.folder_name,
            self.verification_model, self._files_status, completed=force,
            total_files=self.total_files,
        )
        self._files_since_checkpoint = 0
        self._last_checkpoint_time = now

    # ---------------- rulare principala ----------------

    def _iter_source_files(self):
        """Sursa unica a listei de fisiere de procesat, indiferent de mod:
        lista clasica in memorie (self.files) sau manifest lazy pe disc
        (self.manifest_path) - citit in loturi de SCAN_BATCH_SIZE, ca sa nu
        tina niciodata toata sursa in RAM deodata (vezi scan_files_streaming)."""
        if self.files is not None:
            for entry in self.files:
                yield entry
        elif self.manifest_path is not None:
            for batch in iter_manifest_batches(self.manifest_path, self.source_root):
                for entry in batch:
                    yield entry

    def run(self):
        self.started_at = datetime.now()
        self._job_start_time = time.time()
        self._last_speed_sample_time = self._job_start_time
        target_root = os.path.join(self.dest_root, self.folder_name)
        os.makedirs(target_root, exist_ok=True)

        already_done = self._load_resume_state(target_root) if self.resume else set()
        self._open_csv_writer(target_root)

        log_master(
            f"Offload pornit -> destinatie={self.dest_root}, folder={self.folder_name}, "
            f"fisiere={self.total_files}, model_verificare={self.verification_model}, "
            f"buffer={self.chunk_size // (1024 * 1024)}MB"
            f"{' (reluare)' if self.resume else ''}"
        )

        for full_src, rel_path, size in self._iter_source_files():
            if self.cancel_event is not None and self.cancel_event.is_set():
                self.cancelled = True
                break

            # Pauza: blocheaza AICI, INTRE fisiere - fisierul anterior s-a
            # terminat deja, deci nu se pierde niciun progres facut pana la
            # apasarea Pauza. Verificam periodic cancel_event ca sa nu
            # ramanem blocati definitiv daca userul anuleaza cat e pe pauza.
            if self.pause_event is not None and self.pause_event.is_set():
                self.log_queue.put(f"[{os.path.basename(self.dest_root)}] Pauza — transferul e oprit temporar.")
                while self.pause_event.is_set():
                    if self.cancel_event is not None and self.cancel_event.is_set():
                        break
                    time.sleep(0.2)
                if self.cancel_event is not None and self.cancel_event.is_set():
                    self.cancelled = True
                    break
                self.log_queue.put(f"[{os.path.basename(self.dest_root)}] Reluat din pauza.")

            # Backpressure: daca memoria procesului a depasit limita
            # configurata (Setari I/O & Memorie), asteapta putin inainte
            # sa continue - previne acumularea nestapanita in RAM/swap
            # cand scrierea (ex. HDD) e mai lenta decat citirea (ex. SSD).
            io_settings.wait_if_over_ram_limit(
                cancel_event=self.cancel_event,
                log_fn=self.log_queue.put,
                cfg=self._io_cfg,
            )

            if rel_path in already_done:
                # deja confirmat corect la o rulare anterioara - nu recopiem,
                # dar il numaram la progres ca sa bara de progres fie corecta
                self.skip_count += 1
                self.phase_text = f"Sarit (deja verificat): {rel_path}"
                self._advance(size, phase="skip")
                continue

            dest_path = os.path.join(target_root, rel_path)
            os.makedirs(os.path.dirname(dest_path), exist_ok=True)

            status = "OK"
            src_repr = ""
            dst_repr = ""
            error_msg = ""

            try:
                # "Completeaza/Reia" (2026-08-28): la o reluare (resume),
                # verificam AUTOMAT fisierele deja existente la destinatie
                # prin marime+hash, chiar daca userul n-a bifat separat
                # "Sari peste identice" - altfel reluarea recopia orbeste
                # tot ce nu era in checkpoint.json (ex. o inchidere bruscasa
                # de sistem, fara sa apuce sa scrie checkpoint-ul).
                if ((self.skip_existing_identical or self.resume) and os.path.isfile(dest_path)
                        and os.path.getsize(dest_path) == size):
                    self.phase_text = f"Verificare: {rel_path}"
                    same, src_repr, dst_repr = self._verify_pair(full_src, dest_path, size)
                    self._bump_verify_counter()
                    if same:
                        status = "SARIT (identic)"
                        self.skip_count += 1
                        self._files_status[rel_path] = "sarit"
                        self._log_row(rel_path, size, src_repr, dst_repr, status, "")
                        self._advance(size, phase="verify")
                        self._maybe_write_checkpoint()
                        continue

                # faza 1: copiere
                self.phase_text = f"Copiere: {rel_path}"
                _copy_file_cancelable(full_src, dest_path, self.cancel_event, self.chunk_size)
                self._bump_copy_counter()

                # faza 2: verificare (separata vizual de copiere)
                self.phase_text = f"Verificare: {rel_path}"
                same, src_repr, dst_repr = self._verify_pair(full_src, dest_path, size)
                self._bump_verify_counter()
                if not same:
                    status = "NEPOTRIVIRE"
            except _OffloadCancelled:
                self.cancelled = True
                break
            except Exception as e:
                status = "EROARE"
                error_msg = str(e)

            if status == "OK":
                self.ok_count += 1
                self._files_status[rel_path] = "ok"
            elif status.startswith("SARIT"):
                self.skip_count += 1
                self._files_status[rel_path] = "sarit"
            else:
                self.fail_count += 1
                self._files_status[rel_path] = "fail"

            self._log_row(rel_path, size, src_repr, dst_repr, status, error_msg)
            if status in ("EROARE", "NEPOTRIVIRE"):
                log_master(f"EROARE offload -> destinatie={self.dest_root}, fisier={rel_path}, "
                            f"status={status}, detalii={error_msg}")
            self._advance(size, phase="done")

            # verificare periodica a spatiului liber ramas pe aceasta destinatie
            if self.files_done % 10 == 0:
                free_space = get_free_space_bytes(target_root)
                if free_space is not None and free_space < 1024 * 1024 * 1024:  # < 1GB
                    self.log_queue.put(
                        f"[{os.path.basename(self.dest_root)}] ATENTIE: mai putin de 1GB "
                        f"liber ramas pe aceasta destinatie ({format_size(free_space)})."
                    )

            self._maybe_write_checkpoint()

        self.finished_at = datetime.now()
        self._write_reports(target_root)
        self._maybe_write_checkpoint(force=not self.cancelled)

        if self.cancelled:
            self.phase_text = "Anulat"
            self.log_queue.put(f"=== ANULAT: {self.dest_root} - oprit de utilizator. "
                                f"(poti relua mai tarziu doar fisierele ramase)")
            log_master(f"Offload ANULAT -> destinatie={self.dest_root}, "
                        f"OK={self.ok_count}, sarite={self.skip_count}, probleme={self.fail_count}")
        else:
            self.phase_text = "Complet"
            self.log_queue.put(
                f"=== Terminat: {self.dest_root} -> {self.ok_count} OK, "
                f"{self.skip_count} sarite, {self.fail_count} probleme."
            )
            log_master(f"Offload finalizat -> destinatie={self.dest_root}, "
                        f"OK={self.ok_count}, sarite={self.skip_count}, probleme={self.fail_count}")
            send_notification(
                "DataMover",
                f"Destinatie finalizata: {os.path.basename(self.dest_root)} "
                f"({self.ok_count} OK, {self.fail_count} probleme)"
            )

    # ---------------- helper-e progres ----------------

    def _bump_copy_counter(self):
        if self.copy_counter is not None:
            with self.progress_lock:
                self.copy_counter[0] += 1

    def _bump_verify_counter(self):
        if self.verify_counter is not None:
            with self.progress_lock:
                self.verify_counter[0] += 1

    def _open_csv_writer(self, target_root):
        """Deschide CSV-ul de raport O SINGURA DATA, la inceputul run(), si
        il tine deschis pe toata durata copierii - fiecare rand se scrie
        IMEDIAT (_log_row), nu se acumuleaza intr-o lista Python pana la
        final (regula "Log-uri si Stare UI": nu tinem in RAM istoricul
        complet al unui transfer de sute de mii de fisiere)."""
        timestamp = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        self._report_timestamp = timestamp
        csv_path = os.path.join(target_root, f"offload_report_{timestamp}.csv")
        try:
            self._csv_file = open(csv_path, "w", newline="", encoding="utf-8")
            self._csv_writer = csv.DictWriter(
                self._csv_file,
                fieldnames=["fisier", "marime_bytes", "verificare_sursa",
                            "verificare_destinatie", "status", "eroare"],
            )
            self._csv_writer.writeheader()
            self.report_csv_path = csv_path
        except Exception as e:
            self._csv_file = None
            self._csv_writer = None
            self.log_queue.put(f"[EROARE] Nu am putut deschide CSV in {target_root}: {e}")

    def _log_row(self, rel_path, size, src_repr, dst_repr, status, error_msg):
        row = {
            "fisier": rel_path,
            "marime_bytes": size,
            "verificare_sursa": src_repr,
            "verificare_destinatie": dst_repr,
            "status": status,
            "eroare": error_msg,
        }
        if self._csv_writer is not None:
            try:
                self._csv_writer.writerow(row)
            except Exception:
                pass  # un rand de raport pierdut nu trebuie sa opreasca offload-ul

        # Esantion plafonat pentru PDF (Regula PDF_SAMPLE_LIMIT): pastram
        # TOATE erorile/nepotrivirile (sunt putine si important de vazut),
        # plus primele PDF_SAMPLE_LIMIT randuri OK/SARIT ca proba - restul
        # ramane doar in CSV, care e complet.
        is_problem = status in ("EROARE", "NEPOTRIVIRE")
        if is_problem or len(self._pdf_sample_rows) < PDF_SAMPLE_LIMIT:
            self._pdf_sample_rows.append(row)

        line = f"[{os.path.basename(self.dest_root)}] {rel_path} -> {status}"
        self.log_queue.put(line)

    def _advance(self, size, phase="done"):
        # progres global (partajat intre toate destinatiile)
        with self.progress_lock:
            self.progress_counter[0] += 1
            self.bytes_counter[0] += size

        # progres local (per-destinatie, pentru bara proprie + viteza)
        self.files_done += 1
        self.bytes_done += size
        now = time.time()
        elapsed_since_sample = now - (self._last_speed_sample_time or now)
        if elapsed_since_sample >= 0.5:
            delta_bytes = self.bytes_done - self._last_speed_sample_bytes
            self.current_speed_bps = delta_bytes / elapsed_since_sample if elapsed_since_sample > 0 else 0.0
            self._last_speed_sample_time = now
            self._last_speed_sample_bytes = self.bytes_done

    def _write_reports(self, target_root):
        # CSV-ul a fost scris incremental pe tot parcursul run() - aici doar
        # il inchidem (flush pe disc garantat).
        if self._csv_file is not None:
            try:
                self._csv_file.close()
            except Exception:
                pass
            self._csv_file = None
            self._csv_writer = None

        model_label = VERIFICATION_MODELS.get(
            self.verification_model, VERIFICATION_MODELS[DEFAULT_VERIFICATION_MODEL]
        )["label"]
        timestamp = getattr(self, "_report_timestamp", datetime.now().strftime("%Y-%m-%d_%H-%M-%S"))

        truncated = len(self._pdf_sample_rows) < (self.ok_count + self.skip_count + self.fail_count)
        try:
            from .pdf_report import generate_pdf_report
            pdf_path = os.path.join(target_root, f"offload_report_{timestamp}.pdf")
            generate_pdf_report(
                output_path=pdf_path,
                destination=self.dest_root,
                folder_name=self.folder_name,
                rows=self._pdf_sample_rows,
                started_at=self.started_at,
                finished_at=self.finished_at,
                ok_count=self.ok_count,
                skip_count=self.skip_count,
                fail_count=self.fail_count,
                cancelled=self.cancelled,
                verification_label=model_label,
                truncated_note=(
                    f"Lista completa ({self.ok_count + self.skip_count + self.fail_count} fisiere) "
                    "e in CSV-ul alaturat - PDF-ul arata toate problemele plus un esantion."
                ) if truncated else None,
            )
            self.report_pdf_path = pdf_path
        except Exception as e:
            self.log_queue.put(f"[EROARE] Nu am putut scrie PDF in {target_root}: {e}")
