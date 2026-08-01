"""
config.py
---------
Salveaza si incarca automat setarile utilizatorului (proiect, card,
destinatii, excluderi, tema) intr-un fisier JSON simplu in directorul
home, astfel incat aplicatia sa retina preferintele intre sesiuni.
"""

import os
import json

CONFIG_PATH = os.path.expanduser("~/.shotputlite_config.json")

DEFAULTS = {
    "project": "",
    "card": "",
    "destinations": [],
    "exclusions": ".DS_Store, .tmp, Thumbs.db",
    "skip_existing_identical": False,
    "verification_model": "md5",
    "dark_mode": False,
}


def load_config():
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
