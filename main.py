#!/usr/bin/env python3
"""
DataMover
---------
Aplicatie personala/echipa pentru offload verificat de fisiere media,
inspirata de instrumentele profesionale de offload: copiere catre mai multe destinatii simultan,
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
import tempfile
import webbrowser
from datetime import datetime

APP_NAME = "DataMover"
AUTHOR_NAME = "Cristi Gordas"
AUTHOR_LINKS = [
    ("GitHub", "https://github.com/gordasgdc/datamover"),
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
    VERIFICATION_MODELS, DEFAULT_VERIFICATION_MODEL, log_master,
)
import config as cfg
import theme
from tooltip import add_help_icon
import checkpoint as ckpt
import update_config
import updater
import activation
from translations import get_text


def format_size(num_bytes):
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if num_bytes < 1024.0:
            return f"{num_bytes:.1f} {unit}"
        num_bytes /= 1024.0
    return f"{num_bytes:.1f} PB"


SUPPORTED_LANGUAGES = ["ro", "en", "es"]
LANGUAGE_LABELS = {"ro": "RO", "en": "EN", "es": "ES"}


class DataMoverApp(_BASE_CLASS):
    def __init__(self, trial_days_remaining=None):
        super().__init__()
        self.title("DataMover")
        self.geometry("960x840")
        self.minsize(820, 680)
        self.trial_days_remaining = trial_days_remaining

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
        self.eject_after_var = tk.BooleanVar(value=self.settings.get("eject_after", False))
        self.language_var = tk.StringVar(
            value=self.settings.get("language", "ro") if self.settings.get("language") in SUPPORTED_LANGUAGES else "ro"
        )

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

        # Structuri pentru retextare dinamica la schimbarea limbii (fara sa
        # distrugem/reconstruim widget-urile - doar le actualizam .config(text=))
        self._i18n_widgets = {}   # widget -> cheie de traducere (Label/Button/Checkbutton/LabelFrame)
        self._i18n_tooltips = {}  # icon "?" -> cheie de traducere

        # Scurtaturi de tastatura (functioneaza atat pe Mac cat si pe Windows)
        self.bind_all('<Control-o>', lambda e: self._choose_source())
        self.bind_all('<Command-o>', lambda e: self._choose_source())
        self.bind_all('<Control-d>', lambda e: self._add_destination())
        self.bind_all('<Command-d>', lambda e: self._add_destination())
        self.bind_all('<Control-Return>', lambda e: self._start_offload())
        self.bind_all('<Command-Return>', lambda e: self._start_offload())
        self.bind_all('<Control-q>', lambda e: self._on_close())
        self.bind_all('<Command-q>', lambda e: self._on_close())

        self._build_ui()
        self._build_help_menu()
        self._refresh_volumes()
        for d in self.destinations:
            self.dest_listbox.insert("end", d)

        self._apply_current_theme()
        self._check_resumable_checkpoints(silent=True)

        self.after(150, self._poll_log_queue)
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    # ---------------- Traduceri (i18n) ----------------

    def t(self, key, **kwargs):
        return get_text(self.language_var.get(), key, **kwargs)

    def _reg(self, widget, key, **kwargs):
        """Inregistreaza un widget pentru retextare automata la schimbarea
        limbii, si ii seteaza textul curent."""
        widget.config(text=self.t(key, **kwargs))
        self._i18n_widgets[widget] = (key, kwargs)
        return widget

    def _reg_tooltip(self, icon, key):
        icon.dm_tooltip.text = self.t(key)
        self._i18n_tooltips[icon] = key
        return icon

    # ---------------- UI ----------------

    def _build_ui(self):
        pad = {"padx": 12, "pady": 8}

        # Bara de sus: tema + limba + Despre + actualizari + monitorizare
        top_row = ttk.Frame(self)
        top_row.pack(fill="x", padx=10, pady=(8, 0))
        self._reg(ttk.Checkbutton(
            top_row, variable=self.dark_mode_var, command=self._on_toggle_dark_mode,
        ), "dark_mode").pack(side="left")
        self._reg(ttk.Button(
            top_row, command=self._show_about_dialog
        ), "about").pack(side="left", padx=(12, 0))
        self._reg(ttk.Button(
            top_row, command=self._check_for_updates
        ), "check_updates").pack(side="left", padx=(12, 0))

        if self.trial_days_remaining is not None:
            trial_label = ttk.Label(
                top_row, style="Muted.TLabel",
                text=self.t("trial_badge", days=self.trial_days_remaining),
            )
            trial_label.pack(side="left", padx=(12, 0))
            self._muted_labels.append(trial_label)

        lang_frame = ttk.Frame(top_row)
        lang_frame.pack(side="left", padx=(12, 0))
        ttk.Label(lang_frame, text="🌐").pack(side="left")
        self.lang_combo = ttk.Combobox(
            lang_frame, state="readonly", width=4,
            values=[LANGUAGE_LABELS[lg] for lg in SUPPORTED_LANGUAGES],
        )
        self.lang_combo.set(LANGUAGE_LABELS[self.language_var.get()])
        self.lang_combo.pack(side="left", padx=4)
        self.lang_combo.bind("<<ComboboxSelected>>", self._on_language_selected)

        self._reg(ttk.Button(
            top_row, command=self._start_monitor_mode
        ), "start_monitor").pack(side="right")
        self.resume_btn = self._reg(ttk.Button(
            top_row, command=self._show_resume_dialog, state="disabled",
        ), "resume")
        self.resume_btn.pack(side="right", padx=(0, 8))

        # Sursa
        self.frame_src = self._reg(ttk.LabelFrame(self), "source_label")
        self.frame_src.pack(fill="x", **pad)

        row1 = ttk.Frame(self.frame_src)
        row1.pack(fill="x", padx=8, pady=(8, 4))
        self._reg(ttk.Label(row1), "source_volumes").pack(side="left")
        self.volume_combo = ttk.Combobox(row1, state="readonly", width=40)
        self.volume_combo.pack(side="left", padx=8)
        self.volume_combo.bind("<<ComboboxSelected>>", self._on_volume_selected)
        self._reg(ttk.Button(row1, command=self._refresh_volumes), "source_refresh").pack(side="left")

        row2 = ttk.Frame(self.frame_src)
        row2.pack(fill="x", padx=8, pady=(0, 4))
        self.source_entry = ttk.Entry(row2, textvariable=self.source_var)
        self.source_entry.pack(side="left", fill="x", expand=True)
        self._reg(ttk.Button(row2, command=self._choose_source), "source_manual").pack(side="left", padx=8)

        self.hint_src_label = ttk.Label(self.frame_src, style="Muted.TLabel")
        self._reg(self.hint_src_label, "source_dnd" if _DND_AVAILABLE else "source_dnd_unavailable")
        self.hint_src_label.pack(anchor="w", padx=8, pady=(0, 8))
        self._muted_labels.append(self.hint_src_label)

        if _DND_AVAILABLE:
            self.source_entry.drop_target_register(DND_FILES)
            self.source_entry.dnd_bind("<<Drop>>", self._on_source_drop)
            self.frame_src.drop_target_register(DND_FILES)
            self.frame_src.dnd_bind("<<Drop>>", self._on_source_drop)

        # Proiect / Card
        self.frame_meta = self._reg(ttk.LabelFrame(self), "meta_label")
        self.frame_meta.pack(fill="x", **pad)
        self._reg(ttk.Label(self.frame_meta), "meta_project").grid(row=0, column=0, padx=8, pady=6, sticky="e")
        ttk.Entry(self.frame_meta, textvariable=self.project_var, width=25).grid(row=0, column=1, padx=8, pady=6, sticky="w")
        self._reg(ttk.Label(self.frame_meta), "meta_card").grid(row=0, column=2, padx=8, pady=6, sticky="e")
        ttk.Entry(self.frame_meta, textvariable=self.card_var, width=20).grid(row=0, column=3, padx=8, pady=6, sticky="w")

        # Excluderi + optiuni
        self.frame_opts = self._reg(ttk.LabelFrame(self), "opts_label")
        self.frame_opts.pack(fill="x", **pad)

        self._reg(ttk.Label(self.frame_opts), "opts_security").grid(
            row=0, column=0, padx=8, pady=6, sticky="e")
        self.verification_combo = ttk.Combobox(self.frame_opts, state="readonly", width=56)
        self._refresh_verification_combo()
        self.verification_combo.grid(row=0, column=1, padx=8, pady=6, sticky="w")
        self.verification_combo.bind("<<ComboboxSelected>>", self._on_verification_selected)
        self.verification_help_icon = add_help_icon(self.frame_opts, row=0, column=2, text="")
        self._reg_tooltip(self.verification_help_icon, "tooltip_verification")

        self._reg(ttk.Label(self.frame_opts), "opts_exclusions").grid(
            row=1, column=0, padx=8, pady=6, sticky="w")
        ttk.Entry(self.frame_opts, textvariable=self.exclusions_var, width=48).grid(
            row=1, column=1, padx=8, pady=6, sticky="w")
        self.exclusions_help_icon = add_help_icon(self.frame_opts, row=1, column=2, text="")
        self._reg_tooltip(self.exclusions_help_icon, "tooltip_exclusions")

        skip_row = ttk.Frame(self.frame_opts)
        skip_row.grid(row=2, column=0, columnspan=3, padx=8, pady=(0, 6), sticky="w")
        self._reg(ttk.Checkbutton(
            skip_row, variable=self.skip_existing_var
        ), "opts_skip").pack(side="left")
        from tooltip import add_help_icon_packed
        self.skip_help_icon = add_help_icon_packed(skip_row, "")
        self._reg_tooltip(self.skip_help_icon, "tooltip_skip")

        if sys.platform == "darwin":
            eject_row = ttk.Frame(self.frame_opts)
            eject_row.grid(row=3, column=0, columnspan=3, padx=8, pady=(0, 6), sticky="w")
            self._reg(ttk.Checkbutton(
                eject_row, variable=self.eject_after_var,
            ), "opts_eject").pack(side="left")

        # Destinatii
        self.frame_dest = self._reg(ttk.LabelFrame(self), "dest_label")
        self.frame_dest.pack(fill="both", expand=False, **pad)

        list_frame = ttk.Frame(self.frame_dest)
        list_frame.pack(fill="both", expand=True, padx=8, pady=8)
        self.dest_listbox = tk.Listbox(list_frame, height=4)
        self.dest_listbox.pack(side="left", fill="both", expand=True)
        scrollbar = ttk.Scrollbar(list_frame, orient="vertical", command=self.dest_listbox.yview)
        scrollbar.pack(side="left", fill="y")
        self.dest_listbox.config(yscrollcommand=scrollbar.set)
        self._tk_themed_widgets.append(self.dest_listbox)

        btn_frame = ttk.Frame(self.frame_dest)
        btn_frame.pack(fill="x", padx=8, pady=(0, 4))
        self._reg(ttk.Button(btn_frame, command=self._add_destination), "dest_add").pack(side="left")
        self._reg(ttk.Button(btn_frame, command=self._remove_destination), "dest_remove").pack(side="left", padx=8)

        self.hint_dest_label = ttk.Label(self.frame_dest, style="Muted.TLabel")
        self._reg(self.hint_dest_label, "dest_dnd" if _DND_AVAILABLE else "dest_dnd_unavailable")
        self.hint_dest_label.pack(anchor="w", padx=8, pady=(0, 8))
        self._muted_labels.append(self.hint_dest_label)

        if _DND_AVAILABLE:
            self.dest_listbox.drop_target_register(DND_FILES)
            self.dest_listbox.dnd_bind("<<Drop>>", self._on_dest_drop)
            self.frame_dest.drop_target_register(DND_FILES)
            self.frame_dest.dnd_bind("<<Drop>>", self._on_dest_drop)

        # Progres global + separat copiere/verificare
        self.frame_progress = self._reg(ttk.LabelFrame(self), "progress_global")
        self.frame_progress.pack(fill="x", **pad)

        self.progress = ttk.Progressbar(self.frame_progress, orient="horizontal", mode="determinate")
        self.progress.pack(fill="x", padx=8, pady=(8, 0))

        info_row = ttk.Frame(self.frame_progress)
        info_row.pack(fill="x", padx=8, pady=(4, 2))
        self.progress_label = self._reg(ttk.Label(info_row), "progress_inactive")
        self.progress_label.pack(side="left")
        self.speed_label = ttk.Label(info_row, text="")
        self.speed_label.pack(side="right")

        phase_row = ttk.Frame(self.frame_progress)
        phase_row.pack(fill="x", padx=8, pady=(0, 8))
        self.phase_label = ttk.Label(phase_row, text=self._phase_text(0, 0))
        self.phase_label.pack(side="left")

        # Progres per destinatie (randurile se creeaza dinamic la start)
        self.frame_dest_progress = self._reg(ttk.LabelFrame(self), "progress_per_dest")
        self.frame_dest_progress.pack(fill="both", expand=False, **pad)
        self.dest_progress_container = ttk.Frame(self.frame_dest_progress)
        self.dest_progress_container.pack(fill="both", expand=True, padx=8, pady=8)
        self.dest_progress_placeholder = self._reg(
            ttk.Label(self.dest_progress_container, style="Muted.TLabel"), "progress_placeholder"
        )
        self.dest_progress_placeholder.pack(anchor="w")
        self._muted_labels.append(self.dest_progress_placeholder)

        # Butoane start/anuleaza
        action_row = ttk.Frame(self)
        action_row.pack(pady=(0, 6))
        self.start_btn = self._reg(
            ttk.Button(action_row, command=self._start_offload, style="Accent.TButton"), "action_start"
        )
        self.start_btn.pack(side="left", padx=6)
        self.cancel_btn = self._reg(
            ttk.Button(action_row, command=self._cancel_offload, state="disabled"), "action_cancel"
        )
        self.cancel_btn.pack(side="left", padx=6)

        # Log
        self.frame_log = self._reg(ttk.LabelFrame(self), "log_label")
        self.frame_log.pack(fill="both", expand=True, **pad)
        self.log_text = tk.Text(self.frame_log, height=10, state="disabled", wrap="word")
        self.log_text.pack(fill="both", expand=True, padx=8, pady=8)
        self._tk_themed_widgets.append(self.log_text)

    def _phase_text(self, copy_pct, verify_pct):
        return f"{self.t('progress_copy')}: {copy_pct}% | {self.t('progress_verify')}: {verify_pct}%"

    def _refresh_verification_combo(self):
        """(Re)construieste lista de modele de verificare in limba curenta,
        pastrand selectia curenta (dupa cheia interna, ex. 'md5', nu dupa
        eticheta afisata, care se schimba odata cu limba)."""
        key_to_translation_key = {
            "size_only": "verification_size_only", "md5": "verification_md5",
            "sha1": "verification_sha1", "sha256": "verification_sha256",
            "sha512": "verification_sha512",
        }
        self.verification_labels = {}
        display_values = []
        for model_key in VERIFICATION_MODELS.keys():
            translation_key = key_to_translation_key.get(model_key)
            label = self.t(translation_key) if translation_key else VERIFICATION_MODELS[model_key]["label"]
            self.verification_labels[label] = model_key
            display_values.append(label)

        self.verification_combo["values"] = display_values
        current_key = self.verification_model_var.get()
        for label, model_key in self.verification_labels.items():
            if model_key == current_key:
                self.verification_combo.set(label)
                break
        else:
            if display_values:
                self.verification_combo.set(display_values[0])

    # ---------------- Tema (dark mode) ----------------

    def _apply_current_theme(self):
        theme.apply_theme(
            self, self.style, self.dark_mode_var.get(),
            tk_widgets=self._tk_themed_widgets, muted_labels=self._muted_labels,
        )
        self._configure_log_tags()

    def _configure_log_tags(self):
        """Coloreaza vizual liniile din jurnal dupa continut (fara sa
        schimbe formatul liniilor scrise de offload_engine.py) - verde
        pentru OK, rosu pentru erori/nepotriviri, galben pentru sarite,
        bold pentru liniile de rezumat ('>>>' / '===')."""
        palette = theme.DARK if self.dark_mode_var.get() else theme.LIGHT
        self.log_text.tag_configure("log_ok", foreground=palette["success"])
        self.log_text.tag_configure("log_err", foreground=palette["error"])
        self.log_text.tag_configure("log_warn", foreground=palette["warn"])
        self.log_text.tag_configure("log_summary", font=("", 10, "bold"))

    def _on_toggle_dark_mode(self):
        self._apply_current_theme()
        self._save_settings()

    def _on_language_selected(self, _event=None):
        label = self.lang_combo.get()
        for code, lbl in LANGUAGE_LABELS.items():
            if lbl == label:
                self.language_var.set(code)
                break
        self._apply_language()
        self._save_settings()

    def _apply_language(self):
        """Retexteaza toate widget-urile inregistrate (fara sa le distruga
        sau reconstruiasca), in limba curenta. Nu afecteaza liniile deja
        scrise in jurnal, nici mesajele generate de offload_engine.py (care
        raman intentionat in romana - vezi nota din antetul acestui fisier)."""
        for widget, (key, kwargs) in self._i18n_widgets.items():
            widget.config(text=self.t(key, **kwargs))
        for icon, key in self._i18n_tooltips.items():
            icon.dm_tooltip.text = self.t(key)

        self._refresh_verification_combo()

        if not self.running:
            self.progress_label.config(text=self.t("progress_inactive"))
        self.phase_label.config(text=self._phase_text(0, 0) if not self.running else self.phase_label.cget("text"))

        if not self.jobs:
            self.dest_progress_placeholder.config(text=self.t("progress_placeholder"))

        self._build_help_menu()

    def _build_help_menu(self):
        """Inlocuieste meniul nativ 'Help' (care pe Mac apare implicit cu
        mesajul generic 'Help isn't available...') cu unul functional.
        Tk recunoaste numele special 'help' pentru un Menu de pe Mac si il
        leaga automat de intrarea din bara de sus a ecranului - pe Windows,
        acelasi cod adauga pur si simplu o bara de meniu mica, cu 'Help' ca
        singurul meniu, ceva util in plus, nu un inlocuitor de nimic."""
        menubar = tk.Menu(self)
        self.config(menu=menubar)

        help_menu = tk.Menu(menubar, name="help", tearoff=False)
        menubar.add_cascade(label=self.t("help_menu"), menu=help_menu)
        help_menu.add_command(label=self.t("help_guide"), command=self._open_help_guide)
        help_menu.add_command(label=self.t("help_about"), command=self._show_about_dialog)

    def _open_help_guide(self):
        webbrowser.open("https://github.com/gordasgdc/datamover/blob/main/CITESTE-MA.md")

    def _show_about_dialog(self):
        palette = theme.DARK if self.dark_mode_var.get() else theme.LIGHT

        win = tk.Toplevel(self)
        win.title(self.t("about_title"))
        win.resizable(False, False)
        win.configure(background=palette["bg"])
        win.transient(self)

        frame = tk.Frame(win, background=palette["bg"], padx=28, pady=22)
        frame.pack()

        tk.Label(
            frame, text=APP_NAME, font=("TkDefaultFont", 17, "bold"),
            background=palette["bg"], foreground=palette["fg"],
        ).pack(pady=(0, 2))
        tk.Label(
            frame, text=self.t("about_version", version=update_config.APP_VERSION),
            background=palette["bg"], foreground=palette["muted"],
        ).pack(pady=(0, 4))
        tk.Label(
            frame, text=self.t("about_description"),
            background=palette["bg"], foreground=palette["muted"],
            wraplength=320, justify="center",
        ).pack(pady=(0, 16))

        tk.Label(
            frame, text=self.t("about_creator", name=AUTHOR_NAME), font=("TkDefaultFont", 11, "bold"),
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

        ttk.Button(frame, text=self.t("about_close"), command=win.destroy).pack(pady=(18, 0))

        win.update_idletasks()
        x = self.winfo_rootx() + (self.winfo_width() - win.winfo_width()) // 2
        y = self.winfo_rooty() + (self.winfo_height() - win.winfo_height()) // 2
        win.geometry(f"+{max(x, 0)}+{max(y, 0)}")
        win.grab_set()

    # ---------------- Actualizari automate (self-update) ----------------

    def _check_for_updates(self):
        self._append_log("Se verifica actualizari...")
        threading.Thread(target=self._check_for_updates_thread, daemon=True).start()

    def _check_for_updates_thread(self):
        result = updater.check_for_updates(
            update_config.APP_VERSION, update_config.APP_VERSION_URL,
            timeout=update_config.UPDATE_CHECK_TIMEOUT,
        )

        if result.get("error"):
            self.after(0, lambda: self._append_log(f"Verificare actualizari: {result['error']}"))
            return

        if not result.get("available"):
            self.after(0, lambda: self._append_log("Ai deja cea mai recenta versiune."))
            self.after(0, lambda: messagebox.showinfo(
                APP_NAME, self.t("msg_no_update", version=update_config.APP_VERSION)
            ))
            return

        self.after(0, lambda: self._prompt_update(
            result["version"], result.get("changes", ""),
            result.get("download_url", {}), result.get("mandatory", False),
        ))

    def _prompt_update(self, version, changes, download_url, mandatory):
        is_frozen = getattr(sys, "frozen", False)

        if not is_frozen:
            # Rulare din sursa (python3 main.py) - actualizarea automata e
            # dezactivata din siguranta (vezi updater.py). Doar informam.
            messagebox.showinfo(
                self.t("msg_update_available_title"),
                self.t("msg_update_source_only", version=version,
                       current=update_config.APP_VERSION, changes=changes),
            )
            return

        msg = self.t("msg_update_available", version=version, changes=changes)
        if mandatory:
            msg = self.t("msg_update_mandatory") + msg

        if not messagebox.askyesno(self.t("msg_update_available_title"), msg):
            return

        threading.Thread(target=self._perform_update_thread, args=(download_url,), daemon=True).start()

    def _perform_update_thread(self, download_url):
        temp_dir = None
        try:
            self.after(0, lambda: self._append_log("Se descarca actualizarea..."))
            temp_dir = tempfile.mkdtemp(prefix="datamover_update_")

            archive_path, error = updater.download_update(
                download_url, temp_dir,
                retry_count=update_config.DOWNLOAD_RETRY_COUNT,
                timeout=update_config.DOWNLOAD_TIMEOUT,
            )
            if error:
                self.after(0, lambda: messagebox.showerror(
                    self.t("msg_error_title"), self.t("msg_update_download_error", error=error)))
                return
            self.after(0, lambda: self._append_log("Descarcare completa."))

            if sys.platform == "win32":
                extract_dir = updater.extract_archive(archive_path, temp_dir)
                self.after(0, lambda: self._append_log("Fisiere extrase."))
                success, error = updater.perform_update_windows(extract_dir, temp_dir)
            else:
                # Pe Mac descarcam direct un .pkg (nu se extrage - se instaleaza direct)
                success, error = updater.perform_update_mac(archive_path, temp_dir)

            if not success:
                self.after(0, lambda: messagebox.showerror(
                    self.t("msg_error_title"), self.t("msg_update_install_error", error=error)))
                return

            if sys.platform == "win32":
                note = "Actualizarea se instaleaza... Aplicatia se va inchide si reporni automat."
            else:
                note = ("Actualizarea se instaleaza... macOS iti va cere parola de administrator. "
                        "Aplicatia se va inchide si reporni automat.")
            self.after(0, lambda: self._append_log(note))
            self.after(0, self._save_settings)
            self.after(1200, self.destroy)

        except Exception as e:
            self.after(0, lambda: messagebox.showerror(self.t("msg_error_title"), str(e)))
            if temp_dir:
                updater.cleanup_update(temp_dir)

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
        path = filedialog.askdirectory(title=self.t("source_manual"))
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
            messagebox.showwarning(self.t("msg_warning_title"), self.t("msg_drop_source_only"))
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
            messagebox.showwarning(self.t("msg_warning_title"), self.t("msg_drop_dest_only"))

    # ---------------- Destinatii ----------------

    def _add_destination(self):
        path = filedialog.askdirectory(title=self.t("dest_add"))
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
        start = self.log_text.index("end-1c")
        self.log_text.insert("end", text + "\n")
        tag = self._log_line_tag(text)
        if tag:
            self.log_text.tag_add(tag, start, self.log_text.index("end-1c"))
        self.log_text.see("end")
        self.log_text.config(state="disabled")

    @staticmethod
    def _log_line_tag(text):
        """Alege tag-ul de culoare pentru o linie de jurnal, doar pe baza
        continutului deja scris de offload_engine.py (fara sa-i schimbam
        formatul) - vezi status-urile posibile in offload_engine._log_row."""
        if text.startswith(">>>") or text.startswith("==="):
            return "log_summary"
        if "EROARE" in text or "NEPOTRIVIRE" in text:
            return "log_err"
        if "SARIT" in text or "ATENTIE" in text:
            return "log_warn"
        if text.endswith("-> OK"):
            return "log_ok"
        return None

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

    def _play_finish_sound(self):
        """Sunet scurt la finalul unei sesiuni de offload - fara dependinte
        externe noi, foloseste doar sunetele native ale sistemului."""
        try:
            if sys.platform == "darwin":
                subprocess.Popen(["afplay", "/System/Library/Sounds/Glass.aiff"],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            elif sys.platform == "win32":
                import winsound
                winsound.MessageBeep(winsound.MB_ICONASTERISK)
            else:
                self.bell()
        except Exception:
            try:
                self.bell()
            except Exception:
                pass

    def _finish_session(self):
        self.running = False
        self.start_btn.config(state="normal")
        self.cancel_btn.config(state="disabled")
        self.progress_label.config(style="TLabel")
        self._play_finish_sound()

        any_cancelled = any(j.cancelled for j in self.jobs)
        total_ok = sum(j.ok_count for j in self.jobs)
        total_fail = sum(j.fail_count for j in self.jobs)
        total_skip = sum(j.skip_count for j in self.jobs)

        log_master(
            f"Sesiune offload {'ANULATA' if any_cancelled else 'finalizata'} -> "
            f"OK={total_ok}, sarite={total_skip}, probleme={total_fail}, "
            f"destinatii={len(self.jobs)}"
        )

        if any_cancelled:
            self._append_log(">>> Sesiune anulata de utilizator. Poti relua mai tarziu doar "
                              "fisierele ramase cu butonul 'Reia ultima copiere neterminata...'.")
            send_notification(APP_NAME, self.t("msg_offload_cancelled"))
            messagebox.showwarning(self.t("msg_offload_cancelled_title"), self.t("msg_offload_cancelled"))
        else:
            self._append_log(
                f">>> Toate destinatiile au fost finalizate. Total: {total_ok} OK, "
                f"{total_skip} sarite, {total_fail} probleme."
            )
            send_notification(
                APP_NAME,
                f"Offload complet: {total_ok} OK, {total_fail} probleme pe "
                f"{len(self.jobs)} destinatie(i)."
            )
            if total_fail > 0:
                messagebox.showwarning(
                    self.t("msg_offload_cancelled_title"),
                    self.t("msg_offload_complete_problems", count=total_fail),
                )
            else:
                messagebox.showinfo(self.t("msg_offload_cancelled_title"), self.t("msg_offload_complete_ok"))

            self._maybe_eject_source()

        self._check_resumable_checkpoints(silent=True)

    def _maybe_eject_source(self):
        if not self.eject_after_var.get() or sys.platform != "darwin":
            return

        total_fail = sum(j.fail_count for j in self.jobs)
        if total_fail > 0:
            self._append_log(
                ">>> Cardul NU a fost ejectat automat, deoarece au existat probleme la copiere. "
                "Verifica jurnalul/rapoartele inainte sa scoti cardul manual."
            )
            return

        source_path = self.source_var.get().strip()
        if not source_path or not os.path.isdir(source_path):
            return
        try:
            volume_name = os.path.basename(source_path.rstrip("/"))
            result = subprocess.run(["diskutil", "eject", source_path], capture_output=True, text=True)
            if result.returncode == 0:
                self._append_log(f">>> Cardul '{volume_name}' a fost ejectat automat.")
                log_master(f"Card ejectat automat -> {source_path}")
            else:
                self._append_log(f">>> Nu am putut ejecta cardul '{volume_name}': {result.stderr.strip()}")
        except Exception as e:
            self._append_log(f">>> Nu am putut ejecta cardul: {e}")

    # ---------------- Progres per destinatie ----------------

    def _build_dest_progress_rows(self):
        """Construieste un "card" vizual per destinatie (fundal usor ridicat,
        bordura, icon de status) - nu doar un rand plat de widget-uri."""
        for child in self.dest_progress_container.winfo_children():
            child.destroy()
        self.dest_progress_rows = {}

        for dest in self.destinations:
            card = ttk.Frame(self.dest_progress_container, style="Card.TFrame",
                              relief="solid", borderwidth=1, padding=(12, 10))
            card.pack(fill="x", pady=4)

            top_row = ttk.Frame(card, style="Card.TFrame")
            top_row.pack(fill="x")

            status_label = ttk.Label(top_row, text="○", style="CardWait.TLabel", width=2)
            status_label.pack(side="left")

            name_label = ttk.Label(top_row, text=os.path.basename(dest.rstrip("/\\")) or dest,
                                    style="Card.TLabel", font=("", 11, "bold"))
            name_label.pack(side="left", padx=(2, 0))

            open_btn = ttk.Button(top_row, text="📂", width=2, command=lambda d=dest: self._open_destination(d))
            open_btn.pack(side="right")

            speed_label = ttk.Label(top_row, text="", style="CardMuted.TLabel", anchor="e")
            speed_label.pack(side="right", padx=(0, 8))

            bar = ttk.Progressbar(card, orient="horizontal", mode="determinate")
            bar.pack(fill="x", pady=(8, 4))

            bottom_row = ttk.Frame(card, style="Card.TFrame")
            bottom_row.pack(fill="x")

            pct_label = ttk.Label(bottom_row, text="0%", style="Card.TLabel", font=("", 11, "bold"))
            pct_label.pack(side="left")

            phase_label = ttk.Label(bottom_row, text="In asteptare...", style="CardMuted.TLabel", anchor="w")
            phase_label.pack(side="left", fill="x", expand=True, padx=(8, 0))

            self.dest_progress_rows[dest] = {
                "bar": bar, "pct": pct_label, "speed": speed_label, "phase": phase_label,
                "status": status_label,
            }

    def _open_destination(self, dest):
        """Deschide in Finder/Explorer folderul exact creat pentru offload
        (dest/folder_name), nu doar radacina destinatiei - daca job-ul
        corespunzator nu mai exista (nu s-a pornit inca niciun offload),
        deschide macar radacina destinatiei."""
        target = dest
        for job in self.jobs:
            if job.dest_root == dest:
                candidate = os.path.join(job.dest_root, job.folder_name)
                if os.path.isdir(candidate):
                    target = candidate
                break

        if not os.path.isdir(target):
            messagebox.showerror(self.t("msg_error_title"), f"Folderul {target} nu exista.")
            return
        try:
            if sys.platform == "darwin":
                subprocess.run(["open", target])
            elif sys.platform == "win32":
                subprocess.run(["explorer", target])
            else:
                subprocess.run(["xdg-open", target])
        except Exception as e:
            messagebox.showerror(self.t("msg_error_title"), f"Nu am putut deschide folderul: {e}")

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

            if job.cancelled:
                row["status"].config(text="■", style="CardErr.TLabel")
            elif job.total_files > 0 and job.files_done >= total:
                if job.fail_count > 0:
                    row["status"].config(text="✗", style="CardErr.TLabel")
                else:
                    row["status"].config(text="✓", style="CardOk.TLabel")
            elif job.files_done > 0:
                row["status"].config(text="●", style="CardRun.TLabel")
            else:
                row["status"].config(text="○", style="CardWait.TLabel")

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
            messagebox.showinfo(self.t("msg_resume_none_title"), self.t("msg_resume_none"))
            return
        details = "\n".join(f"- {dest} ({folder_name}): {remaining} fisiere ramase"
                             for dest, folder_name, _root, remaining in found)
        proceed = messagebox.askyesno(
            self.t("msg_resume_title"), self.t("msg_resume_details", details=details)
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
            "eject_after": self.eject_after_var.get(),
        })

    def _start_offload(self, resume=False):
        source = self.source_var.get().strip()
        if not source or not os.path.isdir(source):
            messagebox.showerror(self.t("msg_error_title"), self.t("msg_source_error"))
            return
        if not self.destinations:
            messagebox.showerror(self.t("msg_error_title"), self.t("msg_dest_error"))
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
            messagebox.showwarning(self.t("msg_warning_title"), self.t("msg_no_files"))
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
                self.t("msg_space_warning_title"),
                self.t("msg_space_warning", details="\n".join(insufficient)),
            )
            if not proceed:
                return

        self._append_log(
            f"Am gasit {len(files)} fisiere ({format_size(total_size)}). "
            f"Se incepe copierea catre {len(self.destinations)} destinatie(i)"
            f"{' (reluare din checkpoint)' if resume else ''}..."
        )

        self._save_settings()
        log_master(
            f"Sesiune offload pornita -> sursa={source}, fisiere={len(files)}, "
            f"destinatii={len(self.destinations)}{' (reluare)' if resume else ''}"
        )

        self.progress_counter = [0]
        self.bytes_counter = [0]
        self.copy_counter = [0]
        self.verify_counter = [0]
        self.total_units = len(files) * len(self.destinations)
        self.total_bytes = total_size * len(self.destinations)
        self.running = True
        self.start_time = datetime.now()
        self.progress["value"] = 0
        self.progress_label.config(text=self.t("progress_preparing"), style="BigPercent.TLabel")
        self.speed_label.config(text="")
        self.phase_label.config(text=self._phase_text(0, 0))
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
            confirmed = messagebox.askyesno(self.t("action_cancel"), self.t("msg_confirm_cancel"))
            if confirmed:
                self.cancel_event.set()
                self._append_log(">>> Se anuleaza... (fisierul curent se termina de copiat, apoi se opreste)")
                self.cancel_btn.config(state="disabled")

    # ---------------- Modul Monitorizare ----------------

    def _find_companion_monitor_executable(self):
        """Cand aplicatia ruleaza COMPILATA (.app pe Mac / .exe pe Windows), tray_monitor.py
        nu mai exista ca script Python de rulat cu 'python3' - e compilat separat, ca un
        executabil insotitor numit 'DataMover Monitor' (Mac) / 'DataMover Monitor.exe'
        (Windows), livrat in ACELASI folder/zip cu aplicatia principala. Aceasta functie il
        cauta in locurile unde ar trebui sa fie, relativ la executabilul curent."""
        exe_dir = os.path.dirname(sys.executable)

        if sys.platform == "darwin":
            # sys.executable e in interiorul bundle-ului: .../DataMover.app/Contents/MacOS/...
            # Monitorul e livrat ca fisier separat, ALATURI de .app (nu in interiorul lui),
            # deci urcam 3 niveluri ca sa iesim din bundle.
            app_bundle_dir = os.path.abspath(os.path.join(exe_dir, "..", "..", ".."))
            candidates = [os.path.join(app_bundle_dir, "DataMover Monitor")]
        else:
            candidates = [os.path.join(exe_dir, "DataMover Monitor.exe")]

        for path in candidates:
            if os.path.isfile(path):
                return path
        return None

    def _start_monitor_mode(self):
        if not self.destinations:
            messagebox.showwarning(self.t("msg_warning_title"), self.t("msg_monitor_no_dest"))
            return
        self._save_settings()

        is_frozen = getattr(sys, "frozen", False)

        if is_frozen:
            monitor_exe = self._find_companion_monitor_executable()
            if not monitor_exe:
                messagebox.showerror(self.t("msg_error_title"), self.t("msg_monitor_missing_exe"))
                return
            try:
                if sys.platform != "darwin":
                    # necesar pe Windows ca sa nu se deschida si o fereastra neagra de consola
                    creationflags = subprocess.CREATE_NO_WINDOW if hasattr(subprocess, "CREATE_NO_WINDOW") else 0
                    subprocess.Popen([monitor_exe], creationflags=creationflags)
                else:
                    subprocess.Popen([monitor_exe])
            except Exception as e:
                messagebox.showerror(self.t("msg_error_title"), self.t("msg_monitor_error", error=e))
                return
        else:
            # rulare din sursa (python3 main.py) - pornim scriptul direct
            script_dir = os.path.dirname(os.path.abspath(__file__))
            monitor_py = os.path.join(script_dir, "tray_monitor.py")
            if not os.path.isfile(monitor_py):
                messagebox.showerror(self.t("msg_error_title"), "Nu gasesc tray_monitor.py in acelasi folder cu main.py.")
                return
            try:
                subprocess.Popen([sys.executable, monitor_py])
            except Exception as e:
                messagebox.showerror(self.t("msg_error_title"), self.t("msg_monitor_error", error=e))
                return

        messagebox.showinfo(self.t("msg_monitor_ready_title"), self.t("msg_monitor_ready"))

    # ---------------- Inchidere ----------------

    def _on_close(self):
        if self.running:
            if not messagebox.askyesno(self.t("action_cancel"), self.t("msg_confirm_exit")):
                return
            self.cancel_event.set()
        self._save_settings()
        self.destroy()


def _fix_windows_dpi_scaling():
    """Pe Windows, o aplicatie care nu se declara "DPI-aware" e scalata de
    Windows insusi ca un bitmap (presupunand 96 DPI) - pe monitoare cu
    scalare non-100% (foarte comun pe laptopuri Full HD, ex. 125%/150%),
    asta produce text neclar si dimensiuni gresite fata de restul
    ecranului. Declararea explicita, INAINTE sa se creeze orice fereastra
    Tk, lasa Windows sa randeze aplicatia la rezolutia nativa corecta."""
    if sys.platform != "win32":
        return
    try:
        import ctypes
        ctypes.windll.shcore.SetProcessDpiAwareness(1)  # PROCESS_SYSTEM_DPI_AWARE
    except Exception:
        try:
            import ctypes
            ctypes.windll.user32.SetProcessDPIAware()  # fallback, Windows mai vechi
        except Exception:
            pass


if __name__ == "__main__":
    _fix_windows_dpi_scaling()
    trial_days_remaining = activation.require_license()
    app = DataMoverApp(trial_days_remaining=trial_days_remaining)
    app.mainloop()
