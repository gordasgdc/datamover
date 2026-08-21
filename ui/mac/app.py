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
    """O pictograma-card pentru un volum montat: nume, spatiu, status."""

    def __init__(self, parent, path, on_click=None, **kw):
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

        tk.Label(self, text=name, bg=BG_CARD, fg=FG,
                 font=("SF Pro Text", 10, "bold")).pack()
        tk.Label(self, text=free_txt, bg=BG_CARD, fg=FG_MUTED,
                 font=("SF Pro Text", 9)).pack(pady=(0, 10))

        if on_click:
            for w in (self, icon, status):
                w.bind("<Button-1>", lambda e: on_click(path))


class MacApp(_BASE_CLASS):
    def __init__(self):
        super().__init__()
        self.title("DataMover")
        self.configure(bg=BG)
        self.geometry("1100x620")
        self.minsize(820, 480)

        self._build_layout()
        self._refresh_volumes()

    # ------------------------------------------------------------------
    def _build_layout(self):
        root = tk.Frame(self, bg=BG)
        root.pack(fill="both", expand=True)
        root.columnconfigure(1, weight=1)
        root.rowconfigure(0, weight=1)

        # --- Stanga: SOURCES (drop zone) ---------------------------------
        self.col_sources = Column(root, "SOURCES", width=220)
        self.col_sources.grid(row=0, column=0, sticky="ns")
        self.col_sources.grid_propagate(False)

        self.drop_zone = tk.Frame(self.col_sources.body, bg=BG_PANEL,
                                   highlightbackground=BORDER_DASHED,
                                   highlightthickness=2)
        self.drop_zone.pack(fill="both", expand=True, pady=10)
        tk.Label(self.drop_zone, text="Trage fisiere\nsau foldere aici",
                 bg=BG_PANEL, fg=FG_MUTED, font=("SF Pro Text", 10),
                 justify="center").place(relx=0.5, rely=0.5, anchor="center")

        if _HAS_DND:
            self.drop_zone.drop_target_register(DND_FILES)
            self.drop_zone.dnd_bind("<<Drop>>", self._on_drop_sources)

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

        self.selected_destinations = []

    # ------------------------------------------------------------------
    def _refresh_volumes(self):
        for w in self.disks_grid.winfo_children():
            w.destroy()

        volumes = offload_engine.list_mounted_volumes()
        cols = 4
        for i, path in enumerate(volumes):
            tile = DiskTile(self.disks_grid, path, on_click=self._on_disk_click,
                             width=140, height=140)
            tile.grid(row=i // cols, column=i % cols, padx=10, pady=10)
            tile.grid_propagate(False)

        # reincearca periodic (echivalent "auto-detect" din engine)
        self.after(4000, self._refresh_volumes)

    def _on_disk_click(self, path):
        # click pe un disc din centru -> il adaugam ca destinatie (provizoriu;
        # varianta finala probabil drag&drop direct in coloana DESTINATIONS)
        if path in self.selected_destinations:
            return
        self.selected_destinations.append(path)
        self._dest_placeholder.pack_forget()
        row = tk.Label(self.dest_list, text=os.path.basename(path.rstrip("/\\")),
                        bg=BG_CARD, fg=FG, font=("SF Pro Text", 10), anchor="w")
        row.pack(fill="x", pady=3)

    def _on_drop_sources(self, event):
        # event.data poate contine mai multe path-uri, separate si posibil
        # incadrate cu acolade — parsare minimala pentru schelet.
        raw = self.tk.splitlist(event.data)
        for path in raw:
            print("Sursa adaugata:", path)  # TODO: adauga in lista reala de surse


def run():
    app = MacApp()
    app.mainloop()


if __name__ == "__main__":
    run()
