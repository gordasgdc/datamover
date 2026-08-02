#!/usr/bin/env python3
"""
ShotPut Lite
------------
Aplicatie personala/echipa pentru offload verificat de fisiere media,
inspirata de ShotPut Pro: copiere catre mai multe destinatii simultan,
verificare (MD5/SHA-1/SHA-256/SHA-512/doar-dimensiune, la alegere),
denumire automata de foldere, rapoarte CSV + PDF, notificari native
(macOS si Windows), detectare automata a cardurilor/drive-urilor
montate, excludere de fisiere/extensii, verificare spatiu liber si
anulare in timpul rularii. Functioneaza pe macOS si Windows.

Adaugiri:
- Tema intunecata (dark mode), comutabila din interfata, salvata in config.
- Tooltip-uri explicative (iconite "?") langa setarile mai complexe.
- Progres separat "Copiere" / "Verificare" pentru fiecare fisier.
- Bare de progres individuale per destinatie, cu viteza curenta (MB/s).
- Reluare automata la erori, folosind un checkpoint salvat pe disc.
- Buton pentru pornirea modulului "Monitorizare" (system tray / menu bar).

Ruleaza cu: python3 main.py
Dependinte externe: reportlab (rapoarte PDF), tkinterdnd2 (drag-and-drop),
plyer (notificari, optional). Modulul de monitorizare (tray_monitor.py)
necesita in plus pystray + pillow, DOAR daca il folosesti.
"""

import os
import sys
import subprocess
import threading
import queue
import webbrowser
from datetime import datetime

APP_NAME = "ShotPut Lite"
AUTHOR_NAME = "Cristi Gordas"
AUTHOR_LINKS = [
    ("GitHub", "https://github.com/gordasgdc/shotput-lite"),
    ("Facebook", "https://web.facebook.com/cristiGDC"),
    ("YouTube", "https://www.youtube.com/@cristigordas"),
]

import tkinter as tk
from tkinter import ttk, filedialog, messagebox

try:
    from tkinterdnd2 import TkinterDnD, DND_FILES
    _DND_AVAILABLE = True
    _BASE_CLASS = TkinterDnD.Tk
except ImportError:
    _DND_AVAILABLE = False
    DND_FILES = None
    _BASE_CLASS = tk.Tk

from offload_engine import (
    list_all_files, list_mounted_volumes, get_free_space_bytes,
    send_notification, DestinationJob, DEFAULT_EXCLUSIONS,
    VERIFICATION_MODELS, DEFAULT_VERIFICATION_MODEL,
)
import config as cfg
import theme
from tooltip import add_help_icon
import checkpoint as ckpt


def format_size(num_bytes):
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if num_bytes < 1024.0:
            return f"{num_bytes:.1f} {unit}"
        num_bytes /= 1024.0
    return f"{num_bytes:.1f} PB"


HELP_TEXTS = {
    "verification_model": (
        "Modelul de securitate stabileste cum se verifica fiecare fisier dupa copiere:\n\n"
        "- Doar dimensiune: cel mai rapid, dar nu detecteaza coruperi subtile ale datelor.\n"
        "- MD5: rapid, standard in industrie (ShotPut Pro il foloseste implicit).\n"
        "- SHA-1: putin mai lent, ceva mai sigur decat MD5.\n"
        "- SHA-256: recomandat pentru arhivare pe termen lung.\n"
        "- SHA-512: maxim de siguranta, dar cel mai lent."
    ),
    "exclusions": (
        "Lista de fisiere/extensii care NU vor fi copiate, separate prin virgula.\n\n"
        "Poti folosi nume exacte (ex: Thumbs.db) sau extensii (ex: .tmp, .wav).\n"
        "Fisierele ascunse de sistem (care incep cu punct) sunt excluse automat, "
        "indiferent de aceasta lista."
    ),
    "skip_existing": (
        "Daca e bifat, la o re-rulare peste acelasi folder de destinatie, fisierele "
        "deja copiate SI verificate corect nu mai sunt recopiate - doar re-verificate "
        "rapid (dimensiune identica) sau sarite. Util cand o copiere a fost intrerupta "
        "si vrei sa completezi restul fara sa iei totul de la capat."
    ),
}


class ShotPutLiteApp(_BASE_CLASS):
    def __init__(self):
        super().__init__()
        self.title("ShotPut Lite")
        self.geometry("880x760")
        self.minsize(760, 620)

        self.settings = cfg.load_config()

        self.source_var = tk.StringVar()
        self.project_var = tk.StringVar(value=self.settings.get("project", ""))
        self.card_var = tk.StringVar(value=self.settings.get("card", ""))
        self.exclusions_var = tk.StringVar(value=self.settings.get("exclusions", ", ".join(DEFAULT_EXCLUSIONS)))
        self.skip_existing_var = tk.BooleanVar(value=self.settings.get("skip_existing_identical", False))
        self.verification_model_var = tk.StringVar(
            value=self.settings.get("verification_model", DEFAULT_VERIFICATION_MODEL)
        )
        self.dark_mode_var = tk.BooleanVar(value=self.settings.get("dark_mode", False))

        self.destinations = list(self.settings.get("destinations", []))

        self.log_queue = queue.Queue()
        self.progress_counter = [0]
        self.bytes_counter = [0]
        self.copy_counter = [0]
        self.verify_counter = [0]
        self.progress_lock = threading.Lock()
        self.total_units = 0
        self.total_bytes = 0
        self.running = False
        self.cancel_event = threading.Event()
        self.jobs = []
        self.start_time = None
        self.dest_progress_rows = {}  # dest_path -> dict cu widget-uri (bar/labels)

        self.style = ttk.Style(self)
        self._tk_themed_widgets = []   # widget-uri tk clasice (Text, Listbox) de recolorat
        self._muted_labels = []        # ttk.Label-uri gri deschis (hint-uri)

        self._build_ui()
        self._refresh_volumes()
        for d in self.destinations:
            self.dest_listbox.insert("end", d)

        self._apply_current_theme()
        self._check_resumable_checkpoints(silent=True)

        self.after(150, self._poll_log_queue)
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    # ---------------- UI ----------------

    def _build_ui(self):
        pad = {"padx": 10, "pady": 6}

        # Bara de sus: tema + modul monitorizare
        top_row = ttk.Frame(self)
        top_row.pack(fill="x", padx=10, pady=(8, 0))
        ttk.Checkbutton(
            top_row, text="Tema intunecata", variable=self.dark_mode_var,
            command=self._on_toggle_dark_mode,
        ).pack(side="left")
        ttk.Button(
            top_row, text="Despre...", command=self._show_about_dialog
        ).pack(side="left", padx=(12, 0))
        ttk.Button(
            top_row, text="Porneste modul Monitorizare...", command=self._start_monitor_mode
        ).pack(side="right")
        self.resume_btn = ttk.Button(
            top_row, text="Reia ultima copiere neterminata...", command=self._show_resume_dialog,
            state="disabled",
        )
        self.resume_btn.pack(side="right", padx=(0, 8))

        # Sursa
        frame_src = ttk.LabelFrame(self, text="Sursa (card / drive de offload)")
        frame_src.pack(fill="x", **pad)

        row1 = ttk.Frame(frame_src)
        row1.pack(fill="x", padx=8, pady=(8, 4))
        ttk.Label(row1, text="Volume detectate automat:").pack(side="left")
        self.volume_combo = ttk.Combobox(row1, state="readonly", width=40)
        self.volume_combo.pack(side="left", padx=8)
        self.volume_combo.bind("<<ComboboxSelected>>", self._on_volume_selected)
        ttk.Button(row1, text="Reimprospateaza", command=self._refresh_volumes).pack(side="left")

        row2 = ttk.Frame(frame_src)
        row2.pack(fill="x", padx=8, pady=(0, 4))
        self.source_entry = ttk.Entry(row2, textvariable=self.source_var)
        self.source_entry.pack(side="left", fill="x", expand=True)
        ttk.Button(row2, text="Alege manual...", command=self._choose_source).pack(side="left", padx=8)

        dnd_hint_src = "(sau trage un folder aici din Finder)" if _DND_AVAILABLE else \
            "(drag-and-drop indisponibil - vezi CITESTE-MA.md pentru activare)"
        hint_src_label = ttk.Label(frame_src, text=dnd_hint_src, style="Muted.TLabel")
        hint_src_label.pack(anchor="w", padx=8, pady=(0, 8))
        self._muted_labels.append(hint_src_label)

        if _DND_AVAILABLE:
            self.source_entry.drop_target_register(DND_FILES)
            self.source_entry.dnd_bind("<<Drop>>", self._on_source_drop)
            frame_src.drop_target_register(DND_FILES)
            frame_src.dnd_bind("<<Drop>>", self._on_source_drop)

        # Proiect / Card
        frame_meta = ttk.LabelFrame(self, text="Denumire automata folder (Data_Proiect_Card)")
        frame_meta.pack(fill="x", **pad)
        ttk.Label(frame_meta, text="Nume proiect:").grid(row=0, column=0, padx=8, pady=6, sticky="e")
        ttk.Entry(frame_meta, textvariable=self.project_var, width=25).grid(row=0, column=1, padx=8, pady=6, sticky="w")
        ttk.Label(frame_meta, text="Eticheta card:").grid(row=0, column=2, padx=8, pady=6, sticky="e")
        ttk.Entry(frame_meta, textvariable=self.card_var, width=20).grid(row=0, column=3, padx=8, pady=6, sticky="w")

        # Excluderi + optiuni
        frame_opts = ttk.LabelFrame(self, text="Optiuni de copiere")
        frame_opts.pack(fill="x", **pad)

        ttk.Label(frame_opts, text="Model de securitate (verificare):").grid(
            row=0, column=0, padx=8, pady=6, sticky="e")
        self.verification_labels = {v["label"]: k for k, v in VERIFICATION_MODELS.items()}
        self.verification_combo = ttk.Combobox(
            frame_opts, state="readonly", width=56,
            values=[v["label"] for v in VERIFICATION_MODELS.values()]
        )
        current_label = VERIFICATION_MODELS.get(
            self.verification_model_var.get(), VERIFICATION_MODELS[DEFAULT_VERIFICATION_MODEL]
        )["label"]
        self.verification_combo.set(current_label)
        self.verification_combo.grid(row=0, column=1, padx=8, pady=6, sticky="w")
        self.verification_combo.bind("<<ComboboxSelected>>", self._on_verification_selected)
        add_help_icon(frame_opts, row=0, column=2, text=HELP_TEXTS["verification_model"])

        ttk.Label(frame_opts, text="Exclude fisiere/extensii (separate prin virgula):").grid(
            row=1, column=0, padx=8, pady=6, sticky="w")
        ttk.Entry(frame_opts, textvariable=self.exclusions_var, width=48).grid(
            row=1, column=1, padx=8, pady=6, sticky="w")
        add_help_icon(frame_opts, row=1, column=2, text=HELP_TEXTS["exclusions"])

        skip_row = ttk.Frame(frame_opts)
        skip_row.grid(row=2, column=0, columnspan=3, padx=8, pady=(0, 6), sticky="w")
        ttk.Checkbutton(
            skip_row, text="Sari peste fisiere deja identice la destinatie (economiseste timp la re-rulari)",
            variable=self.skip_existing_var
        ).pack(side="left")
        from tooltip import add_help_icon_packed
        add_help_icon_packed(skip_row, HELP_TEXTS["skip_existing"])

        # Destinatii
        frame_dest = ttk.LabelFrame(self, text="Destinatii (poti adauga oricate, copiere simultana)")
        frame_dest.pack(fill="both", expand=False, **pad)

        list_frame = ttk.Frame(frame_dest)
        list_frame.pack(fill="both", expand=True, padx=8, pady=8)
        self.dest_listbox = tk.Listbox(list_frame, height=4)
        self.dest_listbox.pack(side="left", fill="both", expand=True)
        scrollbar = ttk.Scrollbar(list_frame, orient="vertical", command=self.dest_listbox.yview)
        scrollbar.pack(side="left", fill="y")
        self.dest_listbox.config(yscrollcommand=scrollbar.set)
        self._tk_themed_widgets.append(self.dest_listbox)

        btn_frame = ttk.Frame(frame_dest)
        btn_frame.pack(fill="x", padx=8, pady=(0, 4))
        ttk.Button(btn_frame, text="Adauga destinatie...", command=self._add_destination).pack(side="left")
        ttk.Button(btn_frame, text="Sterge selectia", command=self._remove_destination).pack(side="left", padx=8)

        dnd_hint_dest = "(sau trage unul sau mai multe foldere aici din Finder)" if _DND_AVAILABLE else \
            "(drag-and-drop indisponibil - vezi CITESTE-MA.md pentru activare)"
        hint_dest_label = ttk.Label(frame_dest, text=dnd_hint_dest, style="Muted.TLabel")
        hint_dest_label.pack(anchor="w", padx=8, pady=(0, 8))
        self._muted_labels.append(hint_dest_label)

        if _DND_AVAILABLE:
            self.dest_listbox.drop_target_register(DND_FILES)
            self.dest_listbox.dnd_bind("<<Drop>>", self._on_dest_drop)
            frame_dest.drop_target_register(DND_FILES)
            frame_dest.dnd_bind("<<Drop>>", self._on_dest_drop)

        # Progres global + separat copiere/verificare
        frame_progress = ttk.LabelFrame(self, text="Progres global")
        frame_progress.pack(fill="x", **pad)

        self.progress = ttk.Progressbar(frame_progress, orient="horizontal", mode="determinate")
        self.progress.pack(fill="x", padx=8, pady=(8, 0))

        info_row = ttk.Frame(frame_progress)
        info_row.pack(fill="x", padx=8, pady=(4, 2))
        self.progress_label = ttk.Label(info_row, text="Inactiv")
        self.progress_label.pack(side="left")
        self.speed_label = ttk.Label(info_row, text="")
        self.speed_label.pack(side="right")

        phase_row = ttk.Frame(frame_progress)
        phase_row.pack(fill="x", padx=8, pady=(0, 8))
        self.phase_label = ttk.Label(phase_row, text="Copiere: 0% | Verificare: 0%")
        self.phase_label.pack(side="left")

        # Progres per destinatie (randurile se creeaza dinamic la start)
        self.frame_dest_progress = ttk.LabelFrame(self, text="Progres per destinatie")
        self.frame_dest_progress.pack(fill="both", expand=False, **pad)
        self.dest_progress_container = ttk.Frame(self.frame_dest_progress)
        self.dest_progress_container.pack(fill="both", expand=True, padx=8, pady=8)
        self.dest_progress_placeholder = ttk.Label(
            self.dest_progress_container, text="(apar aici cand incepe o copiere)", style="Muted.TLabel"
        )
        self.dest_progress_placeholder.pack(anchor="w")
        self._muted_labels.append(self.dest_progress_placeholder)

        # Butoane start/anuleaza
        action_row = ttk.Frame(self)
        action_row.pack(pady=(0, 6))
        self.start_btn = ttk.Button(action_row, text="Incepe offload-ul", command=self._start_offload)
        self.start_btn.pack(side="left", padx=6)
        self.cancel_btn = ttk.Button(action_row, text="Anuleaza", command=self._cancel_offload, state="disabled")
        self.cancel_btn.pack(side="left", padx=6)

        # Log
        frame_log = ttk.LabelFrame(self, text="Jurnal")
        frame_log.pack(fill="both", expand=True, **pad)
        self.log_text = tk.Text(frame_log, height=10, state="disabled", wrap="word")
        self.log_text.pack(fill="both", expand=True, padx=8, pady=8)
        self._tk_themed_widgets.append(self.log_text)

    # ---------------- Tema (dark mode) ----------------

    def _apply_current_theme(self):
        theme.apply_theme(
            self, self.style, self.dark_mode_var.get(),
            tk_widgets=self._tk_themed_widgets, muted_labels=self._muted_labels,
        )

    def _on_toggle_dark_mode(self):
        self._apply_current_theme()
        self._save_settings()

    def _show_about_dialog(self):
        palette = theme.DARK if self.dark_mode_var.get() else theme.LIGHT

        win = tk.Toplevel(self)
        win.title(f"Despre {APP_NAME}")
        win.resizable(False, False)
        win.configure(background=palette["bg"])
        win.transient(self)

        frame = tk.Frame(win, background=palette["bg"], padx=28, pady=22)
        frame.pack()

        tk.Label(
            frame, text=APP_NAME, font=("TkDefaultFont", 17, "bold"),
            background=palette["bg"], foreground=palette["fg"],
        ).pack(pady=(0, 4))
        tk.Label(
            frame, text="Offload verificat de fisiere media, pentru Mac si Windows.",
            background=palette["bg"], foreground=palette["muted"],
            wraplength=320, justify="center",
        ).pack(pady=(0, 16))

        tk.Label(
            frame, text=f"Creat de {AUTHOR_NAME}", font=("TkDefaultFont", 11, "bold"),
            background=palette["bg"], foreground=palette["fg"],
        ).pack(pady=(0, 10))

        for label_text, url in AUTHOR_LINKS:
            link = tk.Label(
                frame, text=label_text, font=("TkDefaultFont", 10, "underline"),
                background=palette["bg"], foreground=palette["select_bg"], cursor="hand2",
            )
            link.pack(pady=2)
            link.bind("<Button-1>", lambda _e, u=url: webbrowser.open(u))
            link.bind("<Enter>", lambda _e, w=link: w.configure(foreground=palette["fg"]))
            link.bind("<Leave>", lambda _e, w=link: w.configure(foreground=palette["select_bg"]))

        ttk.Button(frame, text="Inchide", command=win.destroy).pack(pady=(18, 0))

        win.update_idletasks()
        x = self.winfo_rootx() + (self.winfo_width() - win.winfo_width()) // 2
        y = self.winfo_rooty() + (self.winfo_height() - win.winfo_height()) // 2
        win.geometry(f"+{max(x, 0)}+{max(y, 0)}")
        win.grab_set()

    # ---------------- Volume / sursa ----------------

    def _refresh_volumes(self):
        volumes = list_mounted_volumes()
        self.volume_combo["values"] = volumes
        if volumes:
            self._append_log(f"Volume detectate: {len(volumes)} ({', '.join(os.path.basename(v) for v in volumes)})")
        else:
            self._append_log("Nu am detectat volume/drive-uri montate automat "
                              "(sau niciun card/drive extern nu e conectat). Poti alege manual sursa.")

    def _on_volume_selected(self, _event):
        self.source_var.set(self.volume_combo.get())

    def _on_verification_selected(self, _event):
        label = self.verification_combo.get()
        key = self.verification_labels.get(label, DEFAULT_VERIFICATION_MODEL)
        self.verification_model_var.set(key)

    def _choose_source(self):
        path = filedialog.askdirectory(title="Alege folderul sursa (cardul sau drive-ul)")
        if path:
            self.source_var.set(path)

    def _parse_dropped_paths(self, raw_data):
        """Finder trimite caile ca lista in format Tcl; foloseste tk.splitlist,
        care stie sa gestioneze corect caile cu spatii (acolade) sau ghilimele."""
        try:
            paths = self.tk.splitlist(raw_data)
        except Exception:
            paths = [raw_data]
        return [p for p in paths if p]

    def _on_source_drop(self, event):
        paths = self._parse_dropped_paths(event.data)
        if not paths:
            return
        folders = [p for p in paths if os.path.isdir(p)]
        if not folders:
            messagebox.showwarning("Atentie", "Te rog trage un folder (nu un fisier individual).")
            return
        if len(folders) > 1:
            self._append_log(f"Ai tras {len(folders)} foldere - folosesc doar primul ca sursa: {folders[0]}")
        self.source_var.set(folders[0])
        self._append_log(f"Sursa setata prin drag-and-drop: {folders[0]}")

    def _on_dest_drop(self, event):
        paths = self._parse_dropped_paths(event.data)
        if not paths:
            return
        added = 0
        for p in paths:
            if os.path.isdir(p) and p not in self.destinations:
                self.destinations.append(p)
                self.dest_listbox.insert("end", p)
                added += 1
            elif not os.path.isdir(p):
                self._append_log(f"Ignorat (nu e folder): {p}")
        if added:
            self._append_log(f"Adaugate {added} destinatie(i) prin drag-and-drop.")
        else:
            messagebox.showwarning("Atentie", "Te rog trage unul sau mai multe foldere (nu fisiere individuale).")

    # ---------------- Destinatii ----------------

    def _add_destination(self):
        path = filedialog.askdirectory(title="Alege un folder destinatie")
        if path and path not in self.destinations:
            self.destinations.append(path)
            self.dest_listbox.insert("end", path)

    def _remove_destination(self):
        sel = list(self.dest_listbox.curselection())
        for idx in reversed(sel):
            self.dest_listbox.delete(idx)
            del self.destinations[idx]

    # ---------------- Log / progres ----------------

    def _append_log(self, text):
        self.log_text.config(state="normal")
        self.log_text.insert("end", text + "\n")
        self.log_text.see("end")
        self.log_text.config(state="disabled")

    def _poll_log_queue(self):
        try:
            while True:
                line = self.log_queue.get_nowait()
                self._append_log(line)
        except queue.Empty:
            pass

        if self.running and self.total_units > 0:
            with self.progress_lock:
                done = self.progress_counter[0]
                bytes_done = self.bytes_counter[0]
                copy_done = self.copy_counter[0]
                verify_done = self.verify_counter[0]

            pct = int(done * 100 / self.total_units)
            self.progress["value"] = pct
            self.progress_label.config(text=f"{pct}% ({done}/{self.total_units} fisiere)")

            copy_pct = int(copy_done * 100 / self.total_units) if self.total_units else 0
            verify_pct = int(verify_done * 100 / self.total_units) if self.total_units else 0
            self.phase_label.config(text=f"Copiere: {copy_pct}% | Verificare: {verify_pct}%")

            if self.start_time:
                elapsed = (datetime.now() - self.start_time).total_seconds()
                if elapsed > 0:
                    speed = bytes_done / elapsed
                    self.speed_label.config(text=f"{format_size(speed)}/s")

            self._update_dest_progress_rows()

            if done >= self.total_units:
                self._finish_session()

        self.after(150, self._poll_log_queue)

    def _finish_session(self):
        self.running = False
        self.start_btn.config(state="normal")
        self.cancel_btn.config(state="disabled")

        any_cancelled = any(j.cancelled for j in self.jobs)
        total_ok = sum(j.ok_count for j in self.jobs)
        total_fail = sum(j.fail_count for j in self.jobs)
        total_skip = sum(j.skip_count for j in self.jobs)

        if any_cancelled:
            self._append_log(">>> Sesiune anulata de utilizator. Poti relua mai tarziu doar "
                              "fisierele ramase cu butonul 'Reia ultima copiere neterminata...'.")
            send_notification("ShotPut Lite", "Offload anulat de utilizator.")
            messagebox.showwarning("ShotPut Lite", "Offload-ul a fost anulat.")
        else:
            self._append_log(
                f">>> Toate destinatiile au fost finalizate. Total: {total_ok} OK, "
                f"{total_skip} sarite, {total_fail} probleme."
            )
            send_notification(
                "ShotPut Lite",
                f"Offload complet: {total_ok} OK, {total_fail} probleme pe "
                f"{len(self.jobs)} destinatie(i)."
            )
            if total_fail > 0:
                messagebox.showwarning(
                    "ShotPut Lite",
                    f"Offload complet, dar cu {total_fail} probleme. Verifica jurnalul si rapoartele PDF/CSV.\n\n"
                    f"Poti folosi 'Reia ultima copiere neterminata...' ca sa reincerci doar fisierele cu probleme."
                )
            else:
                messagebox.showinfo("ShotPut Lite", "Offload complet, toate fisierele verificate cu succes.")

        self._check_resumable_checkpoints(silent=True)

    # ---------------- Progres per destinatie ----------------

    def _build_dest_progress_rows(self):
        for child in self.dest_progress_container.winfo_children():
            child.destroy()
        self.dest_progress_rows = {}

        for dest in self.destinations:
            row = ttk.Frame(self.dest_progress_container)
            row.pack(fill="x", pady=3)

            name_label = ttk.Label(row, text=os.path.basename(dest.rstrip("/\\")) or dest, width=22, anchor="w")
            name_label.pack(side="left")

            bar = ttk.Progressbar(row, orient="horizontal", mode="determinate", length=260)
            bar.pack(side="left", padx=8)

            pct_label = ttk.Label(row, text="0%", width=6)
            pct_label.pack(side="left")

            speed_label = ttk.Label(row, text="", width=14, anchor="e")
            speed_label.pack(side="left")

            phase_label = ttk.Label(row, text="In asteptare...", style="Muted.TLabel", anchor="w")
            phase_label.pack(side="left", fill="x", expand=True, padx=(8, 0))
            self._muted_labels.append(phase_label)

            self.dest_progress_rows[dest] = {
                "bar": bar, "pct": pct_label, "speed": speed_label, "phase": phase_label,
            }

    def _update_dest_progress_rows(self):
        for job in self.jobs:
            row = self.dest_progress_rows.get(job.dest_root)
            if not row:
                continue
            total = job.total_files or 1
            pct = int(job.files_done * 100 / total)
            row["bar"]["value"] = pct
            row["pct"].config(text=f"{pct}%")
            row["speed"].config(text=f"{format_size(job.current_speed_bps)}/s" if job.current_speed_bps else "")
            row["phase"].config(text=job.phase_text)

    # ---------------- Checkpoint / reluare ----------------

    def _expected_target_roots(self):
        """Calculeaza target_root-urile probabile (dest/folder_name) pe baza
        setarilor curente de proiect/card, pentru fiecare destinatie salvata."""
        project = self.project_var.get().strip() or "Proiect"
        card = self.card_var.get().strip() or "Card"
        roots = []
        # cautam checkpoint-uri din ultimele cateva zile (data se schimba zilnic)
        from datetime import timedelta
        for days_back in range(0, 3):
            date_str = (datetime.now() - timedelta(days=days_back)).strftime("%Y-%m-%d")
            folder_name = f"{date_str}_{project}_{card}".replace(" ", "_")
            for dest in self.destinations:
                roots.append((dest, folder_name, os.path.join(dest, folder_name)))
        return roots

    def _check_resumable_checkpoints(self, silent=False):
        found = []
        for dest, folder_name, target_root in self._expected_target_roots():
            resumable, remaining = ckpt.resumable_status(target_root)
            if resumable and remaining > 0:
                found.append((dest, folder_name, target_root, remaining))
        if found:
            self.resume_btn.config(state="normal")
            if not silent:
                self._append_log(f"Am gasit {len(found)} destinatie(i) cu o copiere neterminata.")
        else:
            self.resume_btn.config(state="disabled")
        self._resumable_found = found
        return found

    def _show_resume_dialog(self):
        found = self._check_resumable_checkpoints(silent=True)
        if not found:
            messagebox.showinfo("Reluare", "Nu am gasit nicio copiere neterminata pentru "
                                            "proiectul/cardul curent.")
            return
        details = "\n".join(f"- {dest} ({folder_name}): {remaining} fisiere ramase"
                             for dest, folder_name, _root, remaining in found)
        proceed = messagebox.askyesno(
            "Reia copierea",
            f"Am gasit urmatoarele copieri neterminate:\n\n{details}\n\n"
            f"Vrei sa incepi offload-ul acum, reluand automat de unde a ramas "
            f"(fisierele deja verificate corect NU vor fi recopiate)?"
        )
        if proceed:
            self._start_offload(resume=True)

    # ---------------- Logica principala ----------------

    def _parse_exclusions(self):
        raw = self.exclusions_var.get()
        return [p.strip() for p in raw.split(",") if p.strip()]

    def _save_settings(self):
        cfg.save_config({
            "project": self.project_var.get().strip(),
            "card": self.card_var.get().strip(),
            "destinations": self.destinations,
            "exclusions": self.exclusions_var.get(),
            "skip_existing_identical": self.skip_existing_var.get(),
            "verification_model": self.verification_model_var.get(),
            "dark_mode": self.dark_mode_var.get(),
        })

    def _start_offload(self, resume=False):
        source = self.source_var.get().strip()
        if not source or not os.path.isdir(source):
            messagebox.showerror("Eroare", "Alege un folder sursa valid.")
            return
        if not self.destinations:
            messagebox.showerror("Eroare", "Adauga cel putin o destinatie.")
            return

        project = self.project_var.get().strip() or "Proiect"
        card = self.card_var.get().strip() or "Card"
        date_str = datetime.now().strftime("%Y-%m-%d")
        folder_name = f"{date_str}_{project}_{card}".replace(" ", "_")

        exclusions = self._parse_exclusions()
        current_label = VERIFICATION_MODELS.get(
            self.verification_model_var.get(), VERIFICATION_MODELS[DEFAULT_VERIFICATION_MODEL]
        )["label"]
        self._append_log(f"Model de verificare folosit: {current_label}")
        self._append_log(f"Se scaneaza sursa: {source} ...")

        files = list_all_files(source, exclusions=exclusions)
        if not files:
            messagebox.showwarning("Atentie", "Nu am gasit niciun fisier relevant in sursa selectata "
                                               "(sau toate au fost excluse).")
            return

        total_size = sum(size for _f, _r, size in files)

        # verificare spatiu liber pe fiecare destinatie
        insufficient = []
        for dest in self.destinations:
            free = get_free_space_bytes(dest)
            if free is not None and free < total_size:
                insufficient.append(f"{dest} (liber: {format_size(free)}, necesar: {format_size(total_size)})")
        if insufficient:
            proceed = messagebox.askyesno(
                "Spatiu insuficient",
                "Spatiu liber insuficient pe urmatoarele destinatii:\n\n" +
                "\n".join(insufficient) +
                "\n\nVrei sa continui oricum?"
            )
            if not proceed:
                return

        self._append_log(
            f"Am gasit {len(files)} fisiere ({format_size(total_size)}). "
            f"Se incepe copierea catre {len(self.destinations)} destinatie(i)"
            f"{' (reluare din checkpoint)' if resume else ''}..."
        )

        self._save_settings()

        self.progress_counter = [0]
        self.bytes_counter = [0]
        self.copy_counter = [0]
        self.verify_counter = [0]
        self.total_units = len(files) * len(self.destinations)
        self.total_bytes = total_size * len(self.destinations)
        self.running = True
        self.start_time = datetime.now()
        self.progress["value"] = 0
        self.progress_label.config(text="Se pregateste...")
        self.speed_label.config(text="")
        self.phase_label.config(text="Copiere: 0% | Verificare: 0%")
        self.start_btn.config(state="disabled")
        self.cancel_btn.config(state="normal")
        self.cancel_event = threading.Event()

        self._build_dest_progress_rows()

        self.jobs = [
            DestinationJob(
                dest, folder_name, files, self.log_queue,
                self.progress_counter, self.bytes_counter, self.progress_lock,
                skip_existing_identical=self.skip_existing_var.get(),
                cancel_event=self.cancel_event,
                verification_model=self.verification_model_var.get(),
                copy_counter=self.copy_counter, verify_counter=self.verify_counter,
                resume=resume, source_root=source,
            )
            for dest in self.destinations
        ]
        for job in self.jobs:
            t = threading.Thread(target=job.run, daemon=True)
            t.start()

    def _cancel_offload(self):
        if self.running:
            confirmed = messagebox.askyesno("Anuleaza", "Sigur vrei sa anulezi offload-ul in curs?")
            if confirmed:
                self.cancel_event.set()
                self._append_log(">>> Se anuleaza... (fisierul curent se termina de copiat, apoi se opreste)")
                self.cancel_btn.config(state="disabled")

    # ---------------- Modul Monitorizare ----------------

    def _find_companion_monitor_executable(self):
        """Cand aplicatia ruleaza COMPILATA (.app pe Mac / .exe pe Windows), tray_monitor.py
        nu mai exista ca script Python de rulat cu 'python3' - e compilat separat, ca un
        executabil insotitor numit 'ShotPut Lite Monitor' (Mac) / 'ShotPut Lite Monitor.exe'
        (Windows), livrat in ACELASI folder/zip cu aplicatia principala. Aceasta functie il
        cauta in locurile unde ar trebui sa fie, relativ la executabilul curent."""
        exe_dir = os.path.dirname(sys.executable)

        if sys.platform == "darwin":
            # sys.executable e in interiorul bundle-ului: .../ShotPut Lite.app/Contents/MacOS/...
            # Monitorul e livrat ca fisier separat, ALATURI de .app (nu in interiorul lui),
            # deci urcam 3 niveluri ca sa iesim din bundle.
            app_bundle_dir = os.path.abspath(os.path.join(exe_dir, "..", "..", ".."))
            candidates = [os.path.join(app_bundle_dir, "ShotPut Lite Monitor")]
        else:
            candidates = [os.path.join(exe_dir, "ShotPut Lite Monitor.exe")]

        for path in candidates:
            if os.path.isfile(path):
                return path
        return None

    def _start_monitor_mode(self):
        if not self.destinations:
            messagebox.showwarning(
                "Atentie",
                "Modul Monitorizare foloseste ultimele destinatii SALVATE. "
                "Adauga cel putin o destinatie si porneste un offload manual o data, "
                "apoi incearca din nou."
            )
            return
        self._save_settings()

        is_frozen = getattr(sys, "frozen", False)

        if is_frozen:
            monitor_exe = self._find_companion_monitor_executable()
            if not monitor_exe:
                messagebox.showerror(
                    "Eroare",
                    "Nu gasesc executabilul 'ShotPut Lite Monitor' langa aplicatie.\n\n"
                    "Verifica sa fi extras TOT continutul arhivei descarcate (.zip) - "
                    "aplicatia principala si 'ShotPut Lite Monitor' trebuie sa ramana "
                    "in acelasi folder, nu doar aplicatia mutata separat."
                )
                return
            try:
                if sys.platform != "darwin":
                    # necesar pe Windows ca sa nu se deschida si o fereastra neagra de consola
                    creationflags = subprocess.CREATE_NO_WINDOW if hasattr(subprocess, "CREATE_NO_WINDOW") else 0
                    subprocess.Popen([monitor_exe], creationflags=creationflags)
                else:
                    subprocess.Popen([monitor_exe])
            except Exception as e:
                messagebox.showerror("Eroare", f"Nu am putut porni modul Monitorizare: {e}")
                return
        else:
            # rulare din sursa (python3 main.py) - pornim scriptul direct
            script_dir = os.path.dirname(os.path.abspath(__file__))
            monitor_py = os.path.join(script_dir, "tray_monitor.py")
            if not os.path.isfile(monitor_py):
                messagebox.showerror("Eroare", "Nu gasesc tray_monitor.py in acelasi folder cu main.py.")
                return
            try:
                subprocess.Popen([sys.executable, monitor_py])
            except Exception as e:
                messagebox.showerror("Eroare", f"Nu am putut porni modul Monitorizare: {e}")
                return

        messagebox.showinfo(
            "Modul Monitorizare",
            "Modulul de monitorizare a fost pornit intr-un proces separat "
            "(iconita in system tray / menu bar). Poti inchide aceasta fereastra - "
            "monitorizarea continua sa ruleze in fundal."
        )

    # ---------------- Inchidere ----------------

    def _on_close(self):
        if self.running:
            if not messagebox.askyesno(
                "Iesire", "Un offload este in curs. Sigur vrei sa inchizi aplicatia? "
                          "Copierea in desfasurare va fi intrerupta."
            ):
                return
            self.cancel_event.set()
        self._save_settings()
        self.destroy()


if __name__ == "__main__":
    app = ShotPutLiteApp()
    app.mainloop()
