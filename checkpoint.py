"""
checkpoint.py
-------------
Salveaza/incarca starea unei copieri (per destinatie) intr-un fisier
'offload_checkpoint.json', scris chiar in interiorul folderului de
destinatie creat (ex: 2026-07-21_NuntaAna_CardA/offload_checkpoint.json).
La reluare, offload_engine.DestinationJob citeste acest fisier si sare
peste fisierele deja marcate "ok"/"sarit", reincercand doar restul.

Format:
{
  "source": "...",
  "folder_name": "...",
  "verification_model": "md5",
  "completed": false,
  "files": {
      "subfolder/DSC001.jpg": "ok",
      "subfolder/DSC002.jpg": "fail"
  }
}
"""

import os
import json

CHECKPOINT_FILENAME = "offload_checkpoint.json"


def checkpoint_path_for(target_root):
    return os.path.join(target_root, CHECKPOINT_FILENAME)


def load_checkpoint(target_root):
    """Returneaza dict-ul checkpoint sau None daca nu exista / e corupt."""
    path = checkpoint_path_for(target_root)
    if not os.path.isfile(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if "files" not in data:
            return None
        return data
    except Exception:
        return None


def save_checkpoint(target_root, source, folder_name, verification_model,
                     files_status, completed=False, total_files=None):
    """Scrie checkpoint-ul pe disc. files_status: dict rel_path -> status str
    ('ok', 'sarit', 'fail'). Scrierea e best-effort: daca esueaza (disc plin,
    destinatie deconectata brusc etc.) nu opreste copierea.

    total_files: numarul TOTAL de fisiere din sesiune (nu doar cate au fost
    deja incercate) - necesar ca resumable_status() sa poata calcula corect
    cate raman de facut, inclusiv cele la care nu s-a ajuns inca (ex. dupa
    o anulare timpurie, inainte sa fi fost incercate)."""
    path = checkpoint_path_for(target_root)
    payload = {
        "source": source,
        "folder_name": folder_name,
        "verification_model": verification_model,
        "completed": completed,
        "files": files_status,
        "total_files": total_files,
    }
    try:
        tmp_path = path + ".tmp"
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
        os.replace(tmp_path, path)
        return True
    except Exception:
        return False


def resumable_status(target_root):
    """Verifica rapid daca exista un checkpoint neterminat intr-un target_root.
    Returneaza (exista_checkpoint_neterminat: bool, cate_ramase: int).

    "Ramase" = total_files - (cate au status ok/sarit) - include deci si
    fisierele la care nu s-a ajuns inca (anulare timpurie), nu doar cele
    incercate si esuate. Pentru checkpoint-uri vechi, scrise inainte sa
    existe campul total_files, cadem inapoi pe vechea logica (doar cele
    esuate explicit) - mai putin precisa, dar tot mai buna decat nimic."""
    data = load_checkpoint(target_root)
    if not data or data.get("completed"):
        return False, 0
    files = data.get("files", {})
    total_files = data.get("total_files")
    done_count = sum(1 for status in files.values() if status in ("ok", "sarit"))
    if total_files is not None:
        remaining = max(0, total_files - done_count)
    else:
        remaining = sum(1 for status in files.values() if status not in ("ok", "sarit"))
    # un checkpoint necompletat inseamna intotdeauna ceva de reluat - chiar
    # daca "remaining" (doar diagnostic/afisaj) ar iesi 0 dintr-un motiv
    # neprevazut, tot lasam butonul de reluare disponibil
    return True, remaining


def delete_checkpoint(target_root):
    path = checkpoint_path_for(target_root)
    try:
        if os.path.isfile(path):
            os.remove(path)
    except Exception:
        pass
