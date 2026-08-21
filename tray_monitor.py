#!/usr/bin/env python3
"""
tray_monitor.py
----------------
Modul "Monitorizare" pentru DataMover: ruleaza in fundal (iconita in
system tray pe Windows / menu bar pe macOS), detecteaza automat cand
apare un card/drive nou montat, si porneste automat un offload folosind
ULTIMELE setari salvate (din ~/.datamover_config.json), catre toate
destinatiile salvate. Trimite notificare nativa la final.

Necesita o dependinta suplimentara (spre deosebire de restul aplicatiei):

    pip install pystray pillow

('pystray' deseneaza iconita din tray/menu bar pe Mac si Windows;
'Pillow' e folosit doar ca sa genereze o iconita simpla din cod, fara sa
mai avem nevoie de un fisier .png separat.) Daca oricare din cele doua
lipseste, modulul afiseaza un mesaj clar in consola si iese - restul
aplicatiei (DataMover normal, cu fereastra) nu e afectat deloc.

Rulare:
    python3 tray_monitor.py

Iesire: click-dreapta (Windows) sau click (Mac) pe iconita din tray -> "Iesire".
"""

import os
import sys
import time
import threading
import queue

from core import config as cfg
from core.offload_engine import (
    list_all_files, list_mounted_volumes, get_free_space_bytes,
    send_notification, DestinationJob, VERIFICATION_MODELS,
    DEFAULT_VERIFICATION_MODEL,
)
from datetime import datetime

POLL_INTERVAL_SECONDS = 4


def _check_dependencies():
    missing = []
    try:
        import pystray  # noqa: F401
    except ImportError:
        missing.append("pystray")
    try:
        from PIL import Image  # noqa: F401
    except ImportError:
        missing.append("pillow")
    return missing


def _make_icon_image(busy=False):
    from PIL import Image, ImageDraw
    size = 64
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    color = (230, 150, 30, 255) if busy else (60, 130, 200, 255)
    draw.ellipse((4, 4, size - 4, size - 4), fill=color)
    draw.rectangle((18, 26, 46, 44), fill=(255, 255, 255, 255))
    draw.polygon([(18, 26), (32, 14), (46, 26)], fill=(255, 255, 255, 255))
    return img


class OffloadMonitor:
    """Detecteaza volume noi si porneste offload automat cu ultimele setari."""

    def __init__(self, on_status_change=None):
        self.on_status_change = on_status_change or (lambda *_: None)
        self._known_volumes = set(list_mounted_volumes())
        self._stop_event = threading.Event()
        self._busy = False

    def stop(self):
        self._stop_event.set()

    def run_loop(self):
        while not self._stop_event.is_set():
            try:
                self._poll_once()
            except Exception as e:
                print(f"[monitor] eroare la verificare volume: {e}")
            self._stop_event.wait(POLL_INTERVAL_SECONDS)

    def _poll_once(self):
        current = set(list_mounted_volumes())
        new_volumes = current - self._known_volumes
        self._known_volumes = current
        if not new_volumes or self._busy:
            return
        for volume in new_volumes:
            self._start_offload_for(volume)

    def _start_offload_for(self, source):
        settings = cfg.load_config()
        destinations = settings.get("destinations", [])
        if not destinations:
            print(f"[monitor] Card detectat ({source}) dar nu exista destinatii "
                  f"salvate - deschide DataMover normal si configureaza-le o data.")
            return

        self._busy = True
        self.on_status_change(True)
        print(f"[monitor] Card/drive nou detectat: {source} -> pornesc offload automat...")
        send_notification("DataMover", f"Card detectat ({os.path.basename(source)}) - pornesc offload-ul automat.")

        try:
            project = settings.get("project", "").strip() or "Proiect"
            card = settings.get("card", "").strip() or "Card"
            date_str = datetime.now().strftime("%Y-%m-%d")
            folder_name = f"{date_str}_{project}_{card}".replace(" ", "_")
            exclusions = [p.strip() for p in settings.get("exclusions", "").split(",") if p.strip()]
            verification_model = settings.get("verification_model", DEFAULT_VERIFICATION_MODEL)
            skip_existing = settings.get("skip_existing_identical", False)

            files = list_all_files(source, exclusions=exclusions)
            if not files:
                print("[monitor] Nu am gasit fisiere relevante pe volumul detectat - anulez.")
                return

            log_queue = queue.Queue()
            progress_counter = [0]
            bytes_counter = [0]
            lock = threading.Lock()
            cancel_event = threading.Event()

            jobs = [
                DestinationJob(
                    dest, folder_name, files, log_queue,
                    progress_counter, bytes_counter, lock,
                    skip_existing_identical=skip_existing,
                    cancel_event=cancel_event,
                    verification_model=verification_model,
                )
                for dest in destinations
            ]
            threads = [threading.Thread(target=job.run, daemon=True) for job in jobs]
            for t in threads:
                t.start()
            for t in threads:
                t.join()

            total_ok = sum(j.ok_count for j in jobs)
            total_fail = sum(j.fail_count for j in jobs)
            send_notification(
                "DataMover",
                f"Offload automat complet ({os.path.basename(source)}): "
                f"{total_ok} OK, {total_fail} probleme pe {len(jobs)} destinatie(i).",
            )
            print(f"[monitor] Offload complet pentru {source}: {total_ok} OK, {total_fail} probleme.")
        finally:
            self._busy = False
            self.on_status_change(False)


def main():
    missing = _check_dependencies()
    if missing:
        print("Modul 'Monitorizare' necesita biblioteci suplimentare care lipsesc:")
        print(f"    pip install {' '.join(missing)}")
        print("Restul aplicatiei DataMover functioneaza normal fara acest modul.")
        sys.exit(1)

    import pystray
    from PIL import Image  # noqa: F401

    monitor = OffloadMonitor()
    icon_holder = {}

    def on_status_change(busy):
        icon = icon_holder.get("icon")
        if icon is not None:
            icon.icon = _make_icon_image(busy=busy)
            icon.title = "DataMover - copiere in curs..." if busy else "DataMover - monitorizare activa"

    monitor.on_status_change = on_status_change

    def on_quit(icon, _item):
        monitor.stop()
        icon.stop()

    def on_open_settings(_icon, _item):
        # Deschide aplicatia normala (cu fereastra) intr-un proces separat,
        # ca sa nu amestecam doua bucle Tkinter/pystray in acelasi proces.
        import subprocess
        script_dir = os.path.dirname(os.path.abspath(__file__))
        main_py = os.path.join(script_dir, "main.py")
        subprocess.Popen([sys.executable, main_py])

    menu = pystray.Menu(
        pystray.MenuItem("DataMover - Monitorizare activa", None, enabled=False),
        pystray.MenuItem("Deschide setarile...", on_open_settings),
        pystray.MenuItem("Iesire", on_quit),
    )

    icon = pystray.Icon("datamover-monitor", _make_icon_image(busy=False),
                         "DataMover - monitorizare activa", menu)
    icon_holder["icon"] = icon

    monitor_thread = threading.Thread(target=monitor.run_loop, daemon=True)
    monitor_thread.start()

    print("[monitor] Modul Monitorizare pornit. Astept carduri/drive-uri noi...")
    icon.run()  # blocheaza thread-ul principal (necesar pe macOS)


if __name__ == "__main__":
    main()
