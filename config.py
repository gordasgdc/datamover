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
