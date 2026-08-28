"""
config.py
---------
Salveaza si incarca automat setarile utilizatorului (proiect, card,
destinatii, excluderi, tema) intr-un fisier JSON simplu in directorul
home, astfel incat aplicatia sa retina preferintele intre sesiuni.

NOTA (redenumire ShotPut Lite -> DataMover): fisierul de config s-a mutat
de la ~/.shotputlite_config.json la ~/.datamover_config.json. La prima
rulare dupa actualizare, daca fisierul vechi exista si cel nou nu, il
migram automat o singura data, ca utilizatorii sa nu-si piarda setarile
salvate anterior (destinatii, proiect, card etc.).
"""

import os
import json
import shutil

CONFIG_PATH = os.path.expanduser("~/.datamover_config.json")
_OLD_CONFIG_PATH = os.path.expanduser("~/.shotputlite_config.json")
HISTORY_PATH = os.path.expanduser("~/.datamover_history.json")
HISTORY_MAX_ENTRIES = 200  # nu lasam fisierul de istoric sa creasca la nesfarsit

DEFAULTS = {
    "project": "",
    "card": "",
    "destinations": [],
    "exclusions": ".DS_Store, .tmp, Thumbs.db",
    "skip_existing_identical": False,
    "verification_model": "md5",
    "dark_mode": False,
    "eject_after": False,
    "language": "ro",
    # Presetari: nume -> {"destinations": [...], "verification_model": "md5",
    # "exclusions": "..."} - combinatii salvate de destinatii + optiuni de
    # copiere, reutilizabile fara sa retastezi de fiecare data. NU includ
    # proiect/card (astea se schimba la fiecare card filmat, nu au ce cauta
    # intr-o presetare reutilizabila).
    "presets": {},
    # Setari I/O & Memorie (2026-08-27) - vezi core/io_settings.py.
    # chunk_size_mb: dimensiunea buffer-ului de citire/scriere per fisier
    # (8MB implicit - potrivit si pentru HDD, si pentru SSD; userul poate
    # urca la 64MB pe NVMe). ram_limit_mb: prag orientativ de memorie a
    # procesului peste care aplicatia face pauza intre fisiere (backpressure)
    # in loc sa lase RAM/swap sa creasca nestapanit - 0 = fara limita.
    "chunk_size_mb": 8,
    "ram_limit_mb": 1024,
}


def _migrate_old_config_if_needed():
    if not os.path.isfile(CONFIG_PATH) and os.path.isfile(_OLD_CONFIG_PATH):
        try:
            shutil.copyfile(_OLD_CONFIG_PATH, CONFIG_PATH)
        except Exception:
            pass  # migrarea e un bonus, nu trebuie sa opreasca aplicatia


def load_config():
    _migrate_old_config_if_needed()
    if os.path.isfile(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
            merged = dict(DEFAULTS)
            merged.update(data)
            return merged
        except Exception:
            return dict(DEFAULTS)
    return dict(DEFAULTS)


def save_config(data):
    try:
        with open(CONFIG_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception:
        pass  # salvarea setarilor este un bonus, nu trebuie sa opreasca aplicatia


def load_history():
    """Intoarce lista de sesiuni de offload trecute (cele mai recente
    primele), sau [] daca nu exista inca istoric / e corupt."""
    if not os.path.isfile(HISTORY_PATH):
        return []
    try:
        with open(HISTORY_PATH, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    except Exception:
        return []


def append_history_entry(entry):
    """Adauga o sesiune noua in istoric (la inceput - cele mai recente
    primele), pastrand cel mult HISTORY_MAX_ENTRIES. Best-effort, ca si
    save_config - nu trebuie sa opreasca aplicatia daca esueaza."""
    history = load_history()
    history.insert(0, entry)
    history = history[:HISTORY_MAX_ENTRIES]
    try:
        with open(HISTORY_PATH, "w", encoding="utf-8") as f:
            json.dump(history, f, ensure_ascii=False, indent=2)
    except Exception:
        pass
