"""
machine_id.py — ID de masina, in Python, folosind ACEEASI metoda ca
partea C++ din gdc-resolve-encoder (IOPlatformUUID pe Mac, hash SHA-512
trunchiat la 6 octeti, Base32) — rezultatul e identic pentru aceeasi
masina, indiferent de care produs GDC il cere.
"""

import hashlib
import subprocess
import sys


def _raw_machine_id():
    if sys.platform == "darwin":
        try:
            result = subprocess.run(
                ["ioreg", "-rd1", "-c", "IOPlatformExpertDevice"],
                capture_output=True, text=True, timeout=5,
            )
            for line in result.stdout.splitlines():
                if "IOPlatformUUID" in line:
                    return line.split("=")[-1].strip().strip('"')
        except Exception:
            pass
        return "mac-machine-id-unavailable"

    elif sys.platform.startswith("win"):
        try:
            result = subprocess.run(
                ["reg", "query", r"HKLM\SOFTWARE\Microsoft\Cryptography", "/v", "MachineGuid"],
                capture_output=True, text=True, timeout=5,
            )
            for line in result.stdout.splitlines():
                if "MachineGuid" in line:
                    return line.split()[-1].strip()
        except Exception:
            pass
        return "windows-machine-id-unavailable"

    else:
        try:
            with open("/etc/machine-id") as f:
                return f.read().strip()
        except Exception:
            return "linux-machine-id-unavailable"


def get_machine_id_display():
    """Intoarce ID-ul de masina, ca string Base32 scurt, lizibil —
    identic ca format (si, pe aceeasi masina, identic ca valoare) cu
    get_machine_id_display() din C++ (gdc-resolve-encoder)."""
    import base64
    raw = _raw_machine_id()
    digest = hashlib.sha512(raw.encode("utf-8")).digest()[:6]
    return base64.b32encode(digest).decode("ascii").rstrip("=")
