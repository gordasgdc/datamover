"""
ui/mac/app.py — UI nativ macOS, 3 coloane (Sources / Disks / Destinations),
inspirat ShotPut Pro / Silverstack.

Foloseste ACELASI core.offload_engine.DestinationJob ca ui/windows/app.py —
threading + coada de log + counters partajate, identic la nivel de
motor de copiere/verificare. Simplificat fata de Windows pentru v1:
fara nume proiect/card, fara excluderi editabile din UI, fara reluare
din checkpoint (resume=False) — de adaugat cand se decide UX-ul exact.

Ruleaza standalone pentru preview: python3 -m ui.mac.app
"""
import os
import sys
import threading
import queue
import subprocess
import tkinter as tk
from datetime import datetime

from core import offload_engine
from core.offload_engine import (
    list_all_files, get_free_space_bytes, format_size,
    DestinationJob, DEFAULT_VERIFICATION_MODEL, log_master,
)
from core import activation

try:
    from tkinterdnd2 import DND_FILES, TkinterDnD
    _BASE_CLASS = TkinterDnD.Tk
    _HAS_DND = True
except ImportError:
    _BASE_CLASS = tk.Tk
    _HAS_DND = False

# Paleta — dark mode nativ, aceeasi familie de culori ca screenshot-ul
# de referinta (fundal aproape negru, accent verde pentru status "ok").
BG = "#161616"
BG_PANEL = "#1c1c1c"
BG_CARD = "#232323"
FG = "#e6e6e6"
FG_MUTED = "#9a9a9a"
ACCENT_GREEN = "#34c759"
BORDER_DASHED = "#4a4a4a"


class Column(tk.Frame):
    """O coloana cu titlu (SOURCES / Disks / DESTINATIONS) + continut."""

    def __init__(self, parent, title, **kw):
        super().__init__(parent, bg=BG_PANEL, **kw)
        lbl = tk.Label(self, text=title, bg=BG_PANEL, fg=FG_MUTED,
                        font=("SF Pro Text", 11, "bold"))
        lbl.pack(pady=(14, 8))
        self.body = tk.Frame(self, bg=BG_PANEL)
        self.body.pack(fill="both", expand=True, padx=10)


class DiskTile(tk.Frame):
    """O pictograma-card pentru un volum montat: nume, spatiu, status.

    Suporta drag manual (tkinter n-are drag&drop intern intre widget-uri
    proprii, doar cu surse externe ca tkinterdnd2) — ButtonPress incepe
    tragerea, B1-Motion muta o eticheta "fantoma" care urmareste cursorul,
    ButtonRelease anunta parintele unde s-a lasat, ca sa decida daca a
    picat peste coloana DESTINATIONS."""

    def __init__(self, parent, path, on_drag_start=None, on_drag_motion=None,
                 on_drag_end=None, **kw):
        super().__init__(parent, bg=BG_CARD, **kw)
        self.path = path
        name = os.path.basename(path.rstrip("/\\")) or path

        try:
            free = offload_engine.get_free_space_bytes(path)
            free_txt = offload_engine.format_size(free)
        except Exception:
            free_txt = "—"

        icon = tk.Label(self, text="\U0001F5B4", bg=BG_CARD, fg=FG,
                         font=("SF Pro Display", 28))
        icon.pack(pady=(10, 2))

        status = tk.Label(self, text="●", bg=BG_CARD, fg=ACCENT_GREEN,
                           font=("SF Pro Text", 9))
        status.place(relx=0.82, rely=0.05)

        name_lbl = tk.Label(self, text=name, bg=BG_CARD, fg=FG,
                             font=("SF Pro Text", 10, "bold"))
        name_lbl.pack()
        free_lbl = tk.Label(self, text=free_txt, bg=BG_CARD, fg=FG_MUTED,
                             font=("SF Pro Text", 9))
        free_lbl.pack(pady=(0, 10))

        if on_drag_start:
            for w in (self, icon, status, name_lbl, free_lbl):
                w.bind("<ButtonPress-1>", lambda e: on_drag_start(path, e))
                w.bind("<B1-Motion>", lambda e: on_drag_motion(path, e))
                w.bind("<ButtonRelease-1>", lambda e: on_drag_end(path, e))


class MacApp(_BASE_CLASS):
    def __init__(self, trial_days_remaining=None):
        super().__init__()
        self.title("DataMover")
        self.configure(bg=BG)
        self.geometry("1100x620")
        self.minsize(820, 480)

        self.trial_days_remaining = trial_days_remaining

        # stare sesiune de offload (identica ca rol cu ui/windows/app.py)
        self.running = False
        self.log_queue = queue.Queue()
        self.progress_counter = [0]
        self.bytes_counter = [0]
        self.copy_counter = [0]
        self.verify_counter = [0]
        self.progress_lock = threading.Lock()
        self.total_units = 0
        self.start_time = None
        self.cancel_event = None
        self.jobs = []
        self._job_threads = []

        self._build_header()
        self._build_footer()   # packat inainte de root, ca sa-si rezerve spatiul jos
        self._build_layout()
        self._refresh_volumes()
        self.after(150, self._poll_log_queue)

    # ------------------------------------------------------------------
    def _build_header(self):
        """Bara subtire de sus — vizibila DOAR in timpul probei gratuite
        (zile ramase + buton de activare oricand, ca pe Windows). Odata
        activata licenta, bara dispare complet din interfata."""
        if self.trial_days_remaining is None:
            return

        header = tk.Frame(self, bg=BG_PANEL, height=34)
        header.pack(fill="x", side="top")
        header.pack_propagate(False)

        self.trial_label = tk.Label(
            header, bg=BG_PANEL, fg=FG_MUTED, font=("SF Pro Text", 10),
            text=f"Proba gratuita — {self.trial_days_remaining} zile ramase")
        self.trial_label.pack(side="left", padx=14)

        self.activate_btn = tk.Label(
            header, text="Activeaza licenta", bg=BG_PANEL, fg=ACCENT_GREEN,
            font=("SF Pro Text", 10, "bold"), cursor="pointinghand")
        self.activate_btn.pack(side="right", padx=14)
        self.activate_btn.bind("<Button-1>", lambda e: self._open_activation_dialog())

    def _open_activation_dialog(self):
        activated = activation.open_activation_dialog(self)
        if activated:
            self.trial_days_remaining = None
            self.trial_label.master.destroy()  # ascunde toata bara de proba

    # ------------------------------------------------------------------
    def _build_footer(self):
        """Bara de jos — progres global + Start/Anuleaza, vizibila permanent."""
        footer = tk.Frame(self, bg=BG_PANEL, height=64)
        footer.pack(fill="x", side="bottom")
        footer.pack_propagate(False)

        left = tk.Frame(footer, bg=BG_PANEL)
        left.pack(side="left", fill="both", expand=True, padx=14, pady=10)

        self.progress_label = tk.Label(left, text="Gata de pornire", bg=BG_PANEL,
                                        fg=FG, font=("SF Pro Text", 10))
        self.progress_label.pack(anchor="w")

        bar_row = tk.Frame(left, bg=BG_PANEL)
        bar_row.pack(fill="x", pady=(4, 0))
        self.progress_canvas = tk.Canvas(bar_row, bg=BG_CARD, height=6,
                                          highlightthickness=0)
        self.progress_canvas.pack(fill="x", expand=True, side="left")
        self.speed_label = tk.Label(bar_row, text="", bg=BG_PANEL, fg=FG_MUTED,
                                     font=("SF Pro Text", 9))
        self.speed_label.pack(side="left", padx=(10, 0))

        btn_frame = tk.Frame(footer, bg=BG_PANEL)
        btn_frame.pack(side="right", padx=14)

        self.cancel_btn = tk.Label(btn_frame, text="Anuleaza", bg=BG_PANEL,
                                    fg=FG_MUTED, font=("SF Pro Text", 10),
                                    cursor="pointinghand")
        self.cancel_btn.pack(side="left", padx=(0, 16))
        self.cancel_btn.bind("<Button-1>", lambda e: self._cancel_offload())

        self.start_btn = tk.Label(btn_frame, text="  Start  ", bg=ACCENT_GREEN,
                                   fg="#0a0a0a", font=("SF Pro Text", 10, "bold"),
                                   cursor="pointinghand")
        self.start_btn.pack(side="left")
        self.start_btn.bind("<Button-1>", lambda e: self._start_offload())

    def _set_progress_pct(self, pct):
        self.progress_canvas.delete("bar")
        width = self.progress_canvas.winfo_width() or 1
        self.progress_canvas.create_rectangle(
            0, 0, width * pct / 100, 6, fill=ACCENT_GREEN, width=0, tags="bar")

    # ------------------------------------------------------------------
    def _build_layout(self):
        root = tk.Frame(self, bg=BG)
        root.pack(fill="both", expand=True)
        root.columnconfigure(1, weight=1)
        root.rowconfigure(0, weight=1)

        # --- Stanga: SOURCES (drop zone + lista surselor adaugate) -------
        self.col_sources = Column(root, "SOURCES", width=220)
        self.col_sources.grid(row=0, column=0, sticky="ns")
        self.col_sources.grid_propagate(False)

        # zona de drop, mereu vizibila, la inaltime fixa — poti adauga
        # surse noi oricand, chiar daca lista de mai jos e deja plina
        self.drop_zone = tk.Frame(self.col_sources.body, bg=BG_PANEL,
                                   highlightbackground=BORDER_DASHED,
                                   highlightthickness=2, height=90)
        self.drop_zone.pack(fill="x", pady=(10, 6))
        self.drop_zone.pack_propagate(False)
        tk.Label(self.drop_zone, text="Trage fisiere\nsau foldere aici",
                 bg=BG_PANEL, fg=FG_MUTED, font=("SF Pro Text", 10),
                 justify="center").place(relx=0.5, rely=0.5, anchor="center")

        if _HAS_DND:
            self.drop_zone.drop_target_register(DND_FILES)
            self.drop_zone.dnd_bind("<<Drop>>", self._on_drop_sources)

        # lista surselor adaugate pana acum (fisiere/foldere), fiecare cu
        # un buton de eliminare — sub zona de drop, ocupa restul coloanei
        self.sources_list = tk.Frame(self.col_sources.body, bg=BG_PANEL)
        self.sources_list.pack(fill="both", expand=True)
        self.source_paths = []
        self._sources_empty_label = tk.Label(
            self.sources_list, text="Nicio sursa adaugata", bg=BG_PANEL,
            fg=FG_MUTED, font=("SF Pro Text", 9))
        self._sources_empty_label.pack(pady=10)

        # --- Centru: Disks (grid) -----------------------------------------
        self.col_disks = Column(root, "Disks")
        self.col_disks.grid(row=0, column=1, sticky="nsew")
        self.disks_grid = tk.Frame(self.col_disks.body, bg=BG_PANEL)
        self.disks_grid.pack(fill="both", expand=True)

        # --- Dreapta: DESTINATIONS -----------------------------------------
        self.col_dest = Column(root, "DESTINATIONS", width=220)
        self.col_dest.grid(row=0, column=2, sticky="ns")
        self.col_dest.grid_propagate(False)
        self.dest_list = tk.Frame(self.col_dest.body, bg=BG_PANEL)
        self.dest_list.pack(fill="both", expand=True, pady=10)
        self._dest_placeholder = tk.Label(
            self.dest_list, text="Trage un disc aici\nca destinatie",
            bg=BG_PANEL, fg=FG_MUTED, font=("SF Pro Text", 10), justify="center")
        self._dest_placeholder.pack(expand=True)

        self.destination_paths = []
        self._drag_path = None
        self._drag_ghost = None

    # ------------------------------------------------------------------
    def _refresh_volumes(self):
        for w in self.disks_grid.winfo_children():
            w.destroy()

        volumes = offload_engine.list_mounted_volumes()
        cols = 4
        for i, path in enumerate(volumes):
            tile = DiskTile(self.disks_grid, path,
                             on_drag_start=self._drag_start,
                             on_drag_motion=self._drag_motion,
                             on_drag_end=self._drag_end,
                             width=140, height=140)
            tile.grid(row=i // cols, column=i % cols, padx=10, pady=10)
            tile.grid_propagate(False)

        # reincearca periodic (echivalent "auto-detect" din engine)
        self.after(4000, self._refresh_volumes)

    # ---- drag&drop disc -> DESTINATIONS --------------------------------
    def _drag_start(self, path, event):
        self._drag_path = path
        ghost = tk.Toplevel(self)
        ghost.overrideredirect(True)
        try:
            ghost.attributes("-topmost", True)
            ghost.attributes("-alpha", 0.88)
        except tk.TclError:
            pass
        name = os.path.basename(path.rstrip("/\\")) or path
        tk.Label(ghost, text=name, bg=ACCENT_GREEN, fg="#0a0a0a",
                 font=("SF Pro Text", 9, "bold"), padx=8, pady=4).pack()
        ghost.geometry(f"+{event.x_root + 12}+{event.y_root + 12}")
        self._drag_ghost = ghost

    def _drag_motion(self, path, event):
        if self._drag_ghost is not None:
            self._drag_ghost.geometry(f"+{event.x_root + 12}+{event.y_root + 12}")

    def _drag_end(self, path, event):
        if self._drag_ghost is not None:
            self._drag_ghost.destroy()
            self._drag_ghost = None
        self._drag_path = None

        x0 = self.dest_list.winfo_rootx()
        y0 = self.dest_list.winfo_rooty()
        x1 = x0 + self.dest_list.winfo_width()
        y1 = y0 + self.dest_list.winfo_height()
        if x0 <= event.x_root <= x1 and y0 <= event.y_root <= y1:
            self._add_destination(path)

    def _add_destination(self, path):
        if path in self.destination_paths:
            return
        self.destination_paths.append(path)
        self._render_destinations()

    def _remove_destination(self, path):
        if path in self.destination_paths:
            self.destination_paths.remove(path)
            self._render_destinations()

    def _render_destinations(self):
        for w in self.dest_list.winfo_children():
            w.destroy()

        if not self.destination_paths:
            self._dest_placeholder = tk.Label(
                self.dest_list, text="Trage un disc aici\nca destinatie",
                bg=BG_PANEL, fg=FG_MUTED, font=("SF Pro Text", 10), justify="center")
            self._dest_placeholder.pack(expand=True)
            return

        for path in self.destination_paths:
            row = tk.Frame(self.dest_list, bg=BG_CARD)
            row.pack(fill="x", pady=2)
            name = os.path.basename(path.rstrip("/\\")) or path
            tk.Label(row, text=f"\U0001F5B4 {name}", bg=BG_CARD, fg=FG,
                      font=("SF Pro Text", 9), anchor="w").pack(
                side="left", fill="x", expand=True, padx=(6, 0), pady=4)
            remove = tk.Label(row, text="✕", bg=BG_CARD, fg=FG_MUTED,
                               font=("SF Pro Text", 9), cursor="pointinghand")
            remove.pack(side="right", padx=6)
            remove.bind("<Button-1>", lambda e, p=path: self._remove_destination(p))

    def _on_drop_sources(self, event):
        # event.data poate contine mai multe path-uri, separate si posibil
        # incadrate cu acolade (tkinterdnd2 standard) — splitlist le separa
        # corect indiferent de asta.
        for path in self.tk.splitlist(event.data):
            self._add_source(path)

    def _add_source(self, path):
        if path in self.source_paths or not os.path.exists(path):
            return
        self.source_paths.append(path)
        self._render_sources()

    def _remove_source(self, path):
        if path in self.source_paths:
            self.source_paths.remove(path)
            self._render_sources()

    def _render_sources(self):
        for w in self.sources_list.winfo_children():
            w.destroy()

        if not self.source_paths:
            self._sources_empty_label = tk.Label(
                self.sources_list, text="Nicio sursa adaugata", bg=BG_PANEL,
                fg=FG_MUTED, font=("SF Pro Text", 9))
            self._sources_empty_label.pack(pady=10)
            return

        for path in self.source_paths:
            row = tk.Frame(self.sources_list, bg=BG_CARD)
            row.pack(fill="x", pady=2)
            name = os.path.basename(path.rstrip("/")) or path
            icon = "\U0001F4C1" if os.path.isdir(path) else "\U0001F4C4"
            tk.Label(row, text=f"{icon} {name}", bg=BG_CARD, fg=FG,
                     font=("SF Pro Text", 9), anchor="w").pack(
                side="left", fill="x", expand=True, padx=(6, 0), pady=4)
            remove = tk.Label(row, text="✕", bg=BG_CARD, fg=FG_MUTED,
                               font=("SF Pro Text", 9), cursor="pointinghand")
            remove.pack(side="right", padx=6)
            remove.bind("<Button-1>", lambda e, p=path: self._remove_source(p))

    # ---- Start / Anuleaza / progres (acelasi motor ca ui/windows/app.py) --
    def _start_offload(self):
        if self.running:
            return
        if not self.source_paths:
            self._show_error("Adauga cel putin o sursa (drag&drop in coloana Sources).")
            return
        if not self.destination_paths:
            self._show_error("Adauga cel putin o destinatie (trage un disc peste DESTINATIONS).")
            return

        files = []
        for src in self.source_paths:
            if os.path.isdir(src):
                files.extend(list_all_files(src))
            elif os.path.isfile(src):
                size = os.path.getsize(src)
                files.append((src, os.path.basename(src), size))
        if not files:
            self._show_error("Nu am gasit niciun fisier de copiat in sursele adaugate.")
            return

        total_size = sum(size for _f, _r, size in files)
        folder_name = datetime.now().strftime("%Y-%m-%d_%H%M%S")

        log_master(
            f"Sesiune offload (mac UI) pornita -> {len(self.source_paths)} surse, "
            f"{len(files)} fisiere, {len(self.destination_paths)} destinatie(i)"
        )

        self.progress_counter = [0]
        self.bytes_counter = [0]
        self.copy_counter = [0]
        self.verify_counter = [0]
        self.total_units = len(files) * len(self.destination_paths)
        self.running = True
        self.start_time = datetime.now()
        self.progress_label.config(text="Se pregateste...")
        self.speed_label.config(text="")
        self.start_btn.config(state="disabled")
        self.cancel_event = threading.Event()

        self.jobs = [
            DestinationJob(
                dest, folder_name, files, self.log_queue,
                self.progress_counter, self.bytes_counter, self.progress_lock,
                cancel_event=self.cancel_event,
                verification_model=DEFAULT_VERIFICATION_MODEL,
                copy_counter=self.copy_counter, verify_counter=self.verify_counter,
                resume=False, source_root=None,
            )
            for dest in self.destination_paths
        ]
        self._job_threads = []
        for job in self.jobs:
            t = threading.Thread(target=job.run, daemon=True)
            t.start()
            self._job_threads.append(t)

    def _cancel_offload(self):
        if self.running and self.cancel_event is not None:
            self.cancel_event.set()
            self.progress_label.config(text="Se anuleaza...")

    def _show_error(self, message):
        # tk.messagebox ar cere un import suplimentar la nivel de modul —
        # pentru schelet, un dialog minimal e suficient.
        from tkinter import messagebox
        messagebox.showerror("DataMover", message)

    def _poll_log_queue(self):
        try:
            while True:
                self.log_queue.get_nowait()  # log-ul detaliat nu are inca panou in mac UI
        except queue.Empty:
            pass

        if self.running and self.total_units > 0:
            with self.progress_lock:
                done = self.progress_counter[0]
                bytes_done = self.bytes_counter[0]

            pct = int(done * 100 / self.total_units)
            self._set_progress_pct(pct)
            self.progress_label.config(text=f"{pct}% ({done}/{self.total_units} fisiere)")

            if self.start_time:
                elapsed = (datetime.now() - self.start_time).total_seconds()
                if elapsed > 0:
                    self.speed_label.config(text=f"{format_size(bytes_done / elapsed)}/s")

            all_threads_stopped = bool(self._job_threads) and not any(
                t.is_alive() for t in self._job_threads)
            if done >= self.total_units or all_threads_stopped:
                self._finish_session()

        self.after(150, self._poll_log_queue)

    def _finish_session(self):
        self.running = False
        self.start_btn.config(state="normal")
        self.progress_label.config(text="Finalizat.")
        try:
            if sys.platform == "darwin":
                subprocess.Popen(["afplay", "/System/Library/Sounds/Glass.aiff"],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass


def run():
    trial_days_remaining = activation.require_license()
    app = MacApp(trial_days_remaining=trial_days_remaining)
    app.mainloop()


if __name__ == "__main__":
    run()
