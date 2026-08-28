"""
io_settings.py
---------------
Setari configurabile de I/O si memorie pentru offload_engine.py, plus
utilitare de citire a memoriei curente a procesului (fara dependinte
externe - doar stdlib, ca sa nu adauge greutate aplicatiei de baza,
vezi Regula 4 din CLAUDE.md).

Motiv (2026-08-27): raportat un caz real de "Your system has run out of
application memory" / swap la maxim, la un transfer de 3 TB pe Windows.
Aceste setari permit userului sa aleaga un buffer mai mic (mai putina
memorie de varf, potrivit pentru masini modeste) sau mai mare (viteza mai
buna pe NVMe), plus un prag de memorie peste care aplicatia face o pauza
scurta intre fisiere (backpressure) inainte sa continue.
"""

import os
import platform
import time

from . import config as _config

MIN_CHUNK_SIZE_MB = 1
MAX_CHUNK_SIZE_MB = 64
DEFAULT_CHUNK_SIZE_MB = 8

# Optiuni oferite in UI (Regula "Size-ul Buffer-ului de Copiere" din cerere).
CHUNK_SIZE_CHOICES_MB = [4, 8, 16, 32, 64]

# 0 = fara limita (comportament vechi). Optiuni oferite in UI.
RAM_LIMIT_CHOICES_MB = [0, 512, 1024, 2048, 4096]


def get_chunk_size_bytes(cfg=None):
    """Citeste chunk_size_mb din config (sau dintr-un dict deja incarcat,
    ca sa nu recitim fisierul de pe disc de zeci de mii de ori pe secunda)
    si il satureaza in intervalul sigur [1, 64] MB."""
    cfg = cfg if cfg is not None else _config.load_config()
    try:
        mb = int(cfg.get("chunk_size_mb", DEFAULT_CHUNK_SIZE_MB))
    except (TypeError, ValueError):
        mb = DEFAULT_CHUNK_SIZE_MB
    mb = max(MIN_CHUNK_SIZE_MB, min(MAX_CHUNK_SIZE_MB, mb))
    return mb * 1024 * 1024


def get_ram_limit_bytes(cfg=None):
    """0 (sau lipsa) = fara limita configurata de user."""
    cfg = cfg if cfg is not None else _config.load_config()
    try:
        mb = int(cfg.get("ram_limit_mb", 0))
    except (TypeError, ValueError):
        mb = 0
    return mb * 1024 * 1024 if mb > 0 else 0


def current_process_memory_bytes():
    """Memoria rezidenta (RSS) a procesului curent, in bytes - folosita
    pentru controlul de backpressure. Intoarce None daca nu poate fi
    determinata (nu trebuie sa opreasca aplicatia, doar dezactiveaza
    verificarea de RAM pentru sesiunea curenta)."""
    system = platform.system()
    try:
        if system == "Windows":
            import ctypes
            from ctypes import wintypes

            class PROCESS_MEMORY_COUNTERS(ctypes.Structure):
                _fields_ = [
                    ("cb", wintypes.DWORD),
                    ("PageFaultCount", wintypes.DWORD),
                    ("PeakWorkingSetSize", ctypes.c_size_t),
                    ("WorkingSetSize", ctypes.c_size_t),
                    ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
                    ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
                    ("PagefileUsage", ctypes.c_size_t),
                    ("PeakPagefileUsage", ctypes.c_size_t),
                ]

            counters = PROCESS_MEMORY_COUNTERS()
            counters.cb = ctypes.sizeof(PROCESS_MEMORY_COUNTERS)
            handle = ctypes.windll.kernel32.GetCurrentProcess()
            ok = ctypes.windll.psapi.GetProcessMemoryInfo(
                handle, ctypes.byref(counters), counters.cb
            )
            if not ok:
                return None
            return int(counters.WorkingSetSize)
        else:
            import resource
            usage = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
            # ru_maxrss e in KB pe Linux, in bytes pe macOS - normalizam.
            return usage * 1024 if system != "Darwin" else usage
    except Exception:
        return None


def wait_if_over_ram_limit(cancel_event=None, log_fn=None, cfg=None,
                             check_interval_s=0.5, max_wait_s=30.0):
    """Backpressure simplu: daca procesul depaseste ram_limit_mb
    configurat, face o pauza scurta (verificand cancel_event/anulare intre
    timpi) inainte sa lase copierea sa continue cu urmatorul fisier -
    previne acumularea nestapanita in RAM/swap cand scrierea (HDD) e mai
    lenta decat citirea (SSD). E o limita ORIENTATIVA la nivel de proces
    (nu impusa de OS ca un cgroup) - scopul e sa incetineasca sursa cand
    memoria creste anormal, nu sa garanteze un plafon dur."""
    limit = get_ram_limit_bytes(cfg)
    if limit <= 0:
        return
    used = current_process_memory_bytes()
    if used is None or used <= limit:
        return

    waited = 0.0
    warned = False
    while used is not None and used > limit and waited < max_wait_s:
        if cancel_event is not None and cancel_event.is_set():
            return
        if not warned and log_fn is not None:
            log_fn(
                f"ATENTIE: memoria aplicatiei ({used // (1024 * 1024)} MB) a "
                f"depasit limita setata ({limit // (1024 * 1024)} MB) - se "
                f"asteapta putin inainte de urmatorul fisier (backpressure)."
            )
            warned = True
        time.sleep(check_interval_s)
        waited += check_interval_s
        used = current_process_memory_bytes()
