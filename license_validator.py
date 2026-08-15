"""
license_validator.py — verificare cod serial pentru DataMover.
ACEST FIȘIER se distribuie cu aplicația. Conține doar cheia PUBLICĂ —
sigur de distribuit, nu compromite nimic.
"""

import os
import license_core
import machine_id

# ─────────────────────────────────────────────────────────────────────
# INLOCUIESTE cu cheia TA publica, generata de keygen.py
# (din gdc-license-system).
PUBLIC_KEY_B64 = "I1h23MNMRbOhc0ObKJrfa3oFHKA9w+SzbNrroAIy8hs="

PRODUCT_ID = "gdc-datamover"
# ─────────────────────────────────────────────────────────────────────


def check(serial):
    current_machine_id = machine_id.get_machine_id_display()
    return license_core.validate_serial_compact(PUBLIC_KEY_B64, serial, PRODUCT_ID, machine_id_b32=current_machine_id)


def _license_file_path():
    return os.path.expanduser(f"~/.{PRODUCT_ID}_license")


def save_license(serial):
    with open(_license_file_path(), "w") as f:
        f.write(serial.strip())


def load_saved_license():
    path = _license_file_path()
    if not os.path.isfile(path):
        return None
    with open(path) as f:
        serial = f.read().strip()
    if not serial:
        return None
    return check(serial)
