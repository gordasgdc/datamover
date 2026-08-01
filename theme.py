"""
theme.py
--------
Tema intunecata (dark mode) pentru ShotPut Lite. Fara dependinte externe.

ttk foloseste un sistem de "style" global (nu culori per-widget), deci
schimbam paleta printr-un ttk.Style unificat. Widget-urile clasice tk
(Listbox, Text) NU respecta ttk.Style si trebuie colorate manual - de
aceea aplicatia principala trebuie sa-si tina o lista de asemenea
widget-uri ("tk_widgets_to_theme") si sa le paseze la apply_theme().

Utilizare tipica in main.py:

    import theme
    ...
    self.style = ttk.Style(self)
    self.dark_mode_var = tk.BooleanVar(value=self.settings.get("dark_mode", False))
    ...
    theme.apply_theme(self, self.style, self.dark_mode_var.get(),
                       tk_widgets=[self.log_text, self.dest_listbox])
"""

LIGHT = {
    "bg": "#f0f0f0",
    "fg": "#000000",
    "entry_bg": "#ffffff",
    "entry_fg": "#000000",
    "select_bg": "#3daee9",
    "select_fg": "#ffffff",
    "button_bg": "#e1e1e1",
    "trough": "#d9d9d9",
    "border": "#b5b5b5",
    "muted": "#777777",
}

DARK = {
    "bg": "#1e1e1e",
    "fg": "#e8e8e8",
    "entry_bg": "#2d2d2d",
    "entry_fg": "#e8e8e8",
    "select_bg": "#3a6ea5",
    "select_fg": "#ffffff",
    "button_bg": "#3a3a3a",
    "trough": "#333333",
    "border": "#4a4a4a",
    "muted": "#a0a0a0",
}


def _configure_ttk_style(style, palette):
    """Configureaza un ttk.Style cu tema 'clam', singura care permite
    control suficient asupra culorilor de fundal pe majoritatea platformelor
    (tema implicita pe Mac/Windows ignora unele culori de fundal)."""
    try:
        style.theme_use("clam")
    except Exception:
        pass

    style.configure(".", background=palette["bg"], foreground=palette["fg"],
                     fieldbackground=palette["entry_bg"])
    style.configure("TFrame", background=palette["bg"])
    style.configure("TLabelframe", background=palette["bg"], foreground=palette["fg"])
    style.configure("TLabelframe.Label", background=palette["bg"], foreground=palette["fg"])
    style.configure("TLabel", background=palette["bg"], foreground=palette["fg"])
    style.configure("TCheckbutton", background=palette["bg"], foreground=palette["fg"])
    style.map("TCheckbutton", background=[("active", palette["bg"])])
    style.configure("TButton", background=palette["button_bg"], foreground=palette["fg"],
                     bordercolor=palette["border"])
    style.map("TButton",
              background=[("active", palette["select_bg"]), ("disabled", palette["bg"])],
              foreground=[("disabled", palette["muted"])])
    style.configure("TEntry", fieldbackground=palette["entry_bg"], foreground=palette["entry_fg"],
                     insertcolor=palette["fg"])
    style.configure("TCombobox", fieldbackground=palette["entry_bg"], foreground=palette["entry_fg"],
                     background=palette["button_bg"])
    style.map("TCombobox", fieldbackground=[("readonly", palette["entry_bg"])],
              foreground=[("readonly", palette["entry_fg"])])
    style.configure("Horizontal.TProgressbar", background=palette["select_bg"],
                     troughcolor=palette["trough"], bordercolor=palette["border"])
    style.configure("TScrollbar", background=palette["button_bg"], troughcolor=palette["trough"])
    style.configure("Muted.TLabel", background=palette["bg"], foreground=palette["muted"])


def apply_theme(root, style, dark, tk_widgets=None, muted_labels=None):
    """Aplica tema (dark=True/False) pe fereastra principala.

    root: fereastra principala (Tk / TkinterDnD.Tk)
    style: instanta ttk.Style asociata cu root
    tk_widgets: lista de widget-uri tk clasice (Text, Listbox) de colorat manual
    muted_labels: lista de ttk.Label care foloseau foreground gri deschis
                  (hint-uri) - sunt recolorate cu style "Muted.TLabel"
    """
    palette = DARK if dark else LIGHT
    _configure_ttk_style(style, palette)
    root.configure(background=palette["bg"])

    for widget in (tk_widgets or []):
        try:
            widget.configure(
                background=palette["entry_bg"],
                foreground=palette["fg"],
                insertbackground=palette["fg"],
                selectbackground=palette["select_bg"],
                selectforeground=palette["select_fg"],
                highlightbackground=palette["border"],
                highlightcolor=palette["border"],
            )
        except Exception:
            # unele widget-uri (ex. Listbox pe anumite platforme) nu accepta
            # toate optiunile de mai sus - ignoram silentios optiunile invalide
            for opt, val in {
                "background": palette["entry_bg"], "foreground": palette["fg"],
            }.items():
                try:
                    widget.configure(**{opt: val})
                except Exception:
                    pass

    for label in (muted_labels or []):
        try:
            label.configure(style="Muted.TLabel")
        except Exception:
            pass
