"""
activation.py — dialog de activare pentru DataMover, localizat (RO/EN/ES),
folosind preferinta de limba deja salvata in config.py.

Integrare in main.py:

    import activation
    if __name__ == "__main__":
        activation.require_license()
        app = DataMoverApp()
        app.mainloop()
"""

import sys
import tkinter as tk
from tkinter import ttk, messagebox

import config as cfg
import license_validator
import machine_id

TEXTS = {
    "ro": {
        "title": "Activare DataMover",
        "heading": "Activează DataMover",
        "sub": "Introdu codul serial primit la achiziție.",
        "machine_label": "ID mașină (trimite-mi asta dacă nu ai încă un cod):",
        "code_label": "Cod serial:",
        "activate": "Activează",
        "quit": "Ieși",
        "empty_error": "Introdu un cod serial.",
        "success_title": "Activat",
        "success_msg": "DataMover a fost activat cu succes.",
    },
    "en": {
        "title": "Activate DataMover",
        "heading": "Activate DataMover",
        "sub": "Enter the serial code you received at purchase.",
        "machine_label": "Machine ID (send me this if you don't have a code yet):",
        "code_label": "Serial code:",
        "activate": "Activate",
        "quit": "Quit",
        "empty_error": "Enter a serial code.",
        "success_title": "Activated",
        "success_msg": "DataMover was activated successfully.",
    },
    "es": {
        "title": "Activar DataMover",
        "heading": "Activar DataMover",
        "sub": "Introduce el código de serie recibido en la compra.",
        "machine_label": "ID de máquina (envíamelo si aún no tienes un código):",
        "code_label": "Código de serie:",
        "activate": "Activar",
        "quit": "Salir",
        "empty_error": "Introduce un código de serie.",
        "success_title": "Activado",
        "success_msg": "DataMover se activó correctamente.",
    },
}


def _current_language():
    try:
        config = cfg.load_config()
        lang = config.get("language", "ro")
        return lang if lang in TEXTS else "ro"
    except Exception:
        return "ro"


def _make_button(parent, text, command, bg, fg, hover_bg):
    """Buton 'fals', construit dintr-un Label cu clic — pe macOS, tk.Button
    (si uneori chiar ttk.Button) poate ignora complet culorile personalizate,
    randand nativ, fara text vizibil pe unele combinatii de sistem. Un Label
    cu binding de clic nu are aceasta problema — culorile se aplica mereu,
    garantat, indiferent de platforma."""
    lbl = tk.Label(parent, text=text, bg=bg, fg=fg, padx=14, pady=7,
                    font=("", 11), cursor="hand2")
    lbl.bind("<Button-1>", lambda e: command())
    lbl.bind("<Enter>", lambda e: lbl.configure(bg=hover_bg))
    lbl.bind("<Leave>", lambda e: lbl.configure(bg=bg))
    return lbl


class ActivationDialog(tk.Tk):
    def __init__(self):
        super().__init__()
        self.t = TEXTS[_current_language()]
        self.title(self.t["title"])
        self.geometry("520x420")
        self.resizable(False, False)
        self.activated = False

        style = ttk.Style(self)
        try:
            style.theme_use("clam")
        except tk.TclError:
            pass

        self._build_ui()
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    def _build_ui(self):
        body = ttk.Frame(self, padding=24)
        body.pack(fill="both", expand=True)

        ttk.Label(body, text=self.t["heading"], font=("", 15, "bold")).pack(anchor="w")
        ttk.Label(body, text=self.t["sub"], foreground="#666").pack(anchor="w", pady=(2, 16))

        ttk.Label(body, text=self.t["machine_label"], foreground="#555",
                  wraplength=440, justify="left").pack(anchor="w")
        machine_id_value = machine_id.get_machine_id_display()
        id_row = ttk.Frame(body)
        id_row.pack(fill="x", pady=(4, 16))
        id_entry = ttk.Entry(id_row)
        id_entry.insert(0, machine_id_value)
        id_entry.configure(state="readonly")
        id_entry.pack(side="left", fill="x", expand=True)
        _make_button(id_row, "Copiaza", lambda: self._copy_to_clipboard(machine_id_value),
                     bg="#555555", fg="white", hover_bg="#444444").pack(side="left", padx=(6, 0))

        ttk.Label(body, text=self.t["code_label"]).pack(anchor="w")
        self.entry = tk.Text(body, height=4, wrap="char", font=("Courier", 10))
        self.entry.pack(fill="x", pady=(4, 12))
        self.entry.focus_set()

        def paste_into_entry(_event=None):
            try:
                clip = self.clipboard_get()
            except tk.TclError:
                return "break"
            self.entry.delete("1.0", "end")
            self.entry.insert("1.0", clip.strip())
            return "break"

        # legare explicita, nu ne bazam doar pe binding-ul implicit Tk —
        # pe unele Mac-uri Cmd+V nu ajunge corect la widget-ul de tip Text
        self.entry.bind("<Command-v>", paste_into_entry)
        self.entry.bind("<Control-v>", paste_into_entry)  # variante de tastatura non-Mac

        paste_menu = tk.Menu(self.entry, tearoff=0)
        paste_menu.add_command(label="Lipeste (Paste)", command=paste_into_entry)

        def show_context_menu(event):
            paste_menu.tk_popup(event.x_root, event.y_root)
            return "break"

        self.entry.bind("<Button-2>", show_context_menu)   # clic dreapta (Mac, unele mouse-uri)
        self.entry.bind("<Button-3>", show_context_menu)   # clic dreapta (standard)
        self.entry.bind("<Control-Button-1>", show_context_menu)  # ctrl+clic (trackpad Mac fara buton drept)

        self.status_var = tk.StringVar(value="")
        ttk.Label(body, textvariable=self.status_var, foreground="#C43D30",
                  wraplength=440, justify="left").pack(anchor="w", pady=(0, 12))

        btn_row = ttk.Frame(body)
        btn_row.pack(fill="x")
        _make_button(btn_row, self.t["activate"], self._try_activate,
                     bg="#2E7D32", fg="white", hover_bg="#256428").pack(side="left")
        _make_button(btn_row, self.t["quit"], self._on_close,
                     bg="#555555", fg="white", hover_bg="#444444").pack(side="left", padx=(8, 0))

    def _copy_to_clipboard(self, text):
        self.clipboard_clear()
        self.clipboard_append(text)

    def _try_activate(self):
        serial = self.entry.get("1.0", "end").strip()
        if not serial:
            self.status_var.set(self.t["empty_error"])
            return

        result = license_validator.check(serial)
        if result.valid:
            license_validator.save_license(serial)
            self.activated = True
            messagebox.showinfo(self.t["success_title"], self.t["success_msg"])
            self.destroy()
        else:
            self.status_var.set(result.error or "—")

    def _on_close(self):
        self.activated = False
        self.destroy()


def require_license():
    saved = license_validator.load_saved_license()
    if saved and saved.valid:
        return

    dialog = ActivationDialog()
    dialog.mainloop()

    if not dialog.activated:
        sys.exit(0)
