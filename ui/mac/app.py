"""
ui/mac/app.py — schelet UI nativ macOS, 3 coloane (Sources / Disks /
Destinations), inspirat ShotPut Pro / Silverstack.

NEFINALIZAT: doar layout + enumerare reala de volume montate (prin
core.offload_engine.list_mounted_volumes) si drag&drop de fisiere in
Sources (tkinterdnd2). Butoanele de start/verificare/rapoarte NU sunt
inca legate de core.offload_engine — de facut cand se decide fluxul
exact (copiere imediata la drop pe destinatie, sau selectie + buton
"Start", ca in Windows).

Ruleaza standalone pentru preview: python3 -m ui.mac.app
"""
import os
import tkinter as tk

from core import offload_engine
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

        self._build_header()
        self._build_layout()
        self._refresh_volumes()

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


def run():
    trial_days_remaining = activation.require_license()
    app = MacApp(trial_days_remaining=trial_days_remaining)
    app.mainloop()


if __name__ == "__main__":
    run()
