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
                     files_status, completed=False):
    """Scrie checkpoint-ul pe disc. files_status: dict rel_path -> status str
    ('ok', 'sarit', 'fail'). Scrierea e best-effort: daca esueaza (disc plin,
    destinatie deconectata brusc etc.) nu opreste copierea."""
    path = checkpoint_path_for(target_root)
    payload = {
        "source": source,
        "folder_name": folder_name,
        "verification_model": verification_model,
        "completed": completed,
        "files": files_status,
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
    Returneaza (exista_checkpoint_neterminat: bool, cate_ramase: int)."""
    data = load_checkpoint(target_root)
    if not data or data.get("completed"):
        return False, 0
    files = data.get("files", {})
    remaining = sum(1 for status in files.values() if status not in ("ok", "sarit"))
    # daca dictionarul e gol sau toate sunt ok, nu mai e nimic de reluat
    return (not data.get("completed")) and (remaining > 0 or True), remaining


def delete_checkpoint(target_root):
    path = checkpoint_path_for(target_root)
    try:
        if os.path.isfile(path):
            os.remove(path)
    except Exception:
        pass
