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

import os
import sys
import time
import urllib.parse
import webbrowser
import tkinter as tk
from tkinter import ttk, messagebox

from . import config as cfg
from . import license_validator
from . import machine_id

# Perioada de proba gratuita, completa functionala, pentru cine nu are inca
# un cod de activare - porneste automat la prima lansare, local, fara server
# (vezi _trial_days_remaining mai jos).
TRIAL_DAYS = 7

WHATSAPP_PHONE = "34643109970"

TEXTS = {
    "ro": {
        "title": "Activare DataMover",
        "heading": "Activează DataMover",
        "sub": "Introdu codul serial primit la achiziție.",
        "sub_trial_expired": "Perioada ta de probă de {days} zile s-a încheiat. Introdu codul serial ca să continui.",
        "machine_label": "ID mașină (trimite-mi asta dacă nu ai încă un cod):",
        "code_label": "Cod serial:",
        "activate": "Activează",
        "quit": "Ieși",
        "empty_error": "Introdu un cod serial.",
        "success_title": "Activat",
        "success_msg": "DataMover a fost activat cu succes.",
        "trial_ending_title": "Proba se apropie de final",
        "trial_ending_msg": "Mai ai {days} {days_word} din perioada de probă gratuită. Scrie-mi pe WhatsApp (+34 643 10 99 70) cand esti gata sa activezi.",
        "trial_day": "zi",
        "trial_days": "zile",
        "whatsapp_btn": "💬 Scrie-mi pe WhatsApp",
        "whatsapp_prefill": "Salut! Vreau sa activez DataMover. ID masina: {id}",
    },
    "en": {
        "title": "Activate DataMover",
        "heading": "Activate DataMover",
        "sub": "Enter the serial code you received at purchase.",
        "sub_trial_expired": "Your {days}-day trial has ended. Enter your serial code to continue.",
        "machine_label": "Machine ID (send me this if you don't have a code yet):",
        "code_label": "Serial code:",
        "activate": "Activate",
        "quit": "Quit",
        "empty_error": "Enter a serial code.",
        "success_title": "Activated",
        "success_msg": "DataMover was activated successfully.",
        "trial_ending_title": "Trial ending soon",
        "trial_ending_msg": "You have {days} {days_word} left in your free trial. Message me on WhatsApp (+34 643 10 99 70) when you're ready to activate.",
        "trial_day": "day",
        "trial_days": "days",
        "whatsapp_btn": "💬 Message me on WhatsApp",
        "whatsapp_prefill": "Hi! I'd like to activate DataMover. Machine ID: {id}",
    },
    "es": {
        "title": "Activar DataMover",
        "heading": "Activar DataMover",
        "sub": "Introduce el código de serie recibido en la compra.",
        "sub_trial_expired": "Tu prueba de {days} días ha terminado. Introduce tu código de serie para continuar.",
        "machine_label": "ID de máquina (envíamelo si aún no tienes un código):",
        "code_label": "Código de serie:",
        "activate": "Activar",
        "quit": "Salir",
        "empty_error": "Introduce un código de serie.",
        "success_title": "Activado",
        "success_msg": "DataMover se activó correctamente.",
        "trial_ending_title": "La prueba casi termina",
        "trial_ending_msg": "Te quedan {days} {days_word} de prueba gratuita. Escríbeme por WhatsApp (+34 643 10 99 70) cuando quieras activar.",
        "trial_day": "día",
        "trial_days": "días",
        "whatsapp_btn": "💬 Escríbeme por WhatsApp",
        "whatsapp_prefill": "Hola! Quiero activar DataMover. ID de máquina: {id}",
    },
}


def _current_language():
    try:
        config = cfg.load_config()
        lang = config.get("language", "ro")
        return lang if lang in TEXTS else "ro"
    except Exception:
        return "ro"


def _trial_file_path():
    return os.path.expanduser(f"~/.{license_validator.PRODUCT_ID}_trial")


def _trial_days_remaining():
    """Porneste automat perioada de proba la prima lansare (scrie data
    curenta intr-un fisier local, separat de fisierul licentei reale) si
    intoarce cate zile mai raman din ea - un numar <= 0 inseamna ca proba
    a expirat. Fara server, fara nicio legatura cu codul de activare real."""
    path = _trial_file_path()
    if not os.path.isfile(path):
        try:
            with open(path, "w") as f:
                f.write(str(int(time.time())))
        except OSError:
            pass  # daca nu putem scrie fisierul, tratam ca proba pornita acum
        return float(TRIAL_DAYS)

    try:
        with open(path) as f:
            started_at = int(f.read().strip())
    except (ValueError, OSError):
        started_at = int(time.time())

    elapsed_days = (time.time() - started_at) / 86400
    return TRIAL_DAYS - elapsed_days


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


class ActivationDialog(tk.Toplevel):
    """Fereastra propriu-zisa de activare — mereu un Toplevel (niciodata
    o a doua radacina tk.Tk()), ca sa poata fi deschisa in siguranta atat
    inainte sa existe fereastra principala (vezi require_license(), care
    ii da o radacina ascunsa, creata special) cat si din interiorul
    aplicatiei deja pornite (vezi open_activation_dialog(), care ii da
    fereastra principala reala ca parinte) — doua bucle tk.Tk().mainloop()
    simultane ar putea bloca aplicatia sau ar da erori Tcl greu de
    diagnosticat."""

    def __init__(self, master, trial_expired=False):
        super().__init__(master)
        self.t = TEXTS[_current_language()]
        self.trial_expired = trial_expired
        self.title(self.t["title"])
        self.geometry("520x470")
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

        sub_text = self.t["sub_trial_expired"].format(days=TRIAL_DAYS) if self.trial_expired else self.t["sub"]
        ttk.Label(body, text=self.t["heading"], font=("", 15, "bold")).pack(anchor="w")
        ttk.Label(body, text=sub_text, foreground="#666", wraplength=460, justify="left").pack(anchor="w", pady=(2, 16))

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

        _make_button(body, self.t["whatsapp_btn"], lambda: self._open_whatsapp(machine_id_value),
                     bg="#25D366", fg="white", hover_bg="#1EBE5A").pack(anchor="w", pady=(0, 16))

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

    def _open_whatsapp(self, machine_id_value):
        message = self.t["whatsapp_prefill"].format(id=machine_id_value)
        url = f"https://wa.me/{WHATSAPP_PHONE}?text={urllib.parse.quote(message)}"
        webbrowser.open(url)

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


def _show_trial_ending_notice(days_remaining):
    lang = _current_language()
    t = TEXTS[lang]
    days_int = max(1, int(days_remaining + 0.999))  # rotunjire in sus - "mai ai 1 zi", nu "0 zile"
    day_word = t["trial_day"] if days_int == 1 else t["trial_days"]
    root = tk.Tk()
    root.withdraw()
    messagebox.showinfo(
        t["trial_ending_title"],
        t["trial_ending_msg"].format(days=days_int, days_word=day_word),
    )
    root.destroy()


def _run_modal(dialog, parent):
    """Blocheaza pana se inchide dialogul, fara sa porneasca o a doua
    bucla tk.Tk().mainloop() — grab_set() + wait_window() e modul corect
    Tkinter de a face un Toplevel modal peste o fereastra parinte deja
    existenta si activa."""
    dialog.grab_set()
    dialog.transient(parent)
    parent.wait_window(dialog)


def open_activation_dialog(parent):
    """Deschide dialogul de activare la cerere, oricand in timpul probei
    gratuite (nu doar dupa ce expira) - apelata dintr-un buton din
    fereastra principala, cu fereastra principala insasi ca `parent`.
    Spre deosebire de require_license(), NU inchide aplicatia daca
    utilizatorul renunta fara sa activeze - doar inchide dialogul si lasa
    proba sa continue normal.

    Intoarce True daca activarea a reusit, altfel False."""
    dialog = ActivationDialog(parent, trial_expired=False)
    _run_modal(dialog, parent)
    return dialog.activated


def require_license():
    """Verifica licenta inaintea pornirii aplicatiei, INAINTE sa existe
    fereastra principala — de-aia isi creeaza singura o radacina Tk
    proprie, ascunsa, doar cat timp e nevoie de ea. Intoarce:
    - None daca aplicatia are un cod de activare valid (nu ruleaza pe proba)
    - un numar de zile ramase din proba gratuita (>=0), altfel

    Nu returneaza deloc daca utilizatorul iese fara sa activeze - aplicatia
    se inchide (sys.exit), la fel ca inainte de introducerea probei."""
    saved = license_validator.load_saved_license()
    if saved and saved.valid:
        return None

    remaining = _trial_days_remaining()
    if remaining > 0:
        if remaining <= 2:
            _show_trial_ending_notice(remaining)
        return max(0, int(remaining))

    root = tk.Tk()
    root.withdraw()
    dialog = ActivationDialog(root, trial_expired=True)
    _run_modal(dialog, root)
    activated = dialog.activated
    root.destroy()

    if not activated:
        sys.exit(0)
    return None
