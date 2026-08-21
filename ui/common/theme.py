"""
theme.py
--------
Tema intunecata (dark mode) pentru DataMover. Fara dependinte externe.

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
    # Adaugiri pentru "polish" vizual: accent (buton principal, procent mare,
    # bife de succes), card-uri per destinatie, si culori de status in jurnal.
    # Aliniat cu SwiftUI ".green" (sistemul de culori Apple) folosit pe
    # DataMover Mac (ContentView.swift), ca cele doua platforme sa arate
    # cat mai la fel - #34C759 e verdele exact folosit de Apple in light mode.
    "accent": "#34c759",
    "accent_hover": "#248a3d",
    "accent_fg": "#ffffff",
    "card_bg": "#e6e6e6",
    "success": "#34c759",
    "error": "#c0392b",
    "warn": "#a86a00",
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
    # #30d158 e verdele exact folosit de Apple in dark mode (SwiftUI ".green"
    # se adapteaza automat light/dark, aici il fixam manual pe Windows).
    "accent": "#30d158",
    "accent_hover": "#28b64a",
    "accent_fg": "#08120d",
    "card_bg": "#282828",
    "success": "#30d158",
    "error": "#e0685e",
    "warn": "#d9a441",
}


DEFAULT_FONT_SIZE = 11  # marit de la implicitul Tk (~9pt) - cerut explicit,
                         # text/butoane greu de citit pe ecrane Full HD


def _bump_default_fonts(size=DEFAULT_FONT_SIZE):
    """Mareste fonturile "numite" ale Tk (TkDefaultFont, TkTextFont, etc.) -
    astea sunt folosite automat de ORICE widget care nu-si seteaza propriul
    font, atat ttk (Button, Label, Entry...) cat si tk clasic (Text,
    Listbox, Menu) - un singur loc care mareste tot textul din aplicatie,
    nu doar widget-urile ttk."""
    import tkinter.font as tkfont
    for name in ("TkDefaultFont", "TkTextFont", "TkMenuFont", "TkHeadingFont", "TkCaptionFont"):
        try:
            tkfont.nametofont(name).configure(size=size)
        except Exception:
            pass


def _configure_ttk_style(style, palette):
    """Configureaza un ttk.Style cu tema 'clam', singura care permite
    control suficient asupra culorilor de fundal pe majoritatea platformelor
    (tema implicita pe Mac/Windows ignora unele culori de fundal)."""
    try:
        style.theme_use("clam")
    except Exception:
        pass

    _bump_default_fonts()

    style.configure(".", background=palette["bg"], foreground=palette["fg"],
                     fieldbackground=palette["entry_bg"], font=("", DEFAULT_FONT_SIZE))
    style.configure("TFrame", background=palette["bg"])
    # Sectiunile (Surse/Meta/Optiuni/Destinatii/Progres) capata o bordura
    # subtire, bine definita, in loc de reliful implicit "groove" al Tk
    # (invechit vizual) - apropiat de cardurile rotunjite de pe Mac, in
    # limitele a ce ttk poate face fara rescrierea layout-ului pe canvas.
    style.configure("TLabelframe", background=palette["bg"], foreground=palette["fg"],
                     relief="solid", borderwidth=1, bordercolor=palette["border"])
    style.configure("TLabelframe.Label", background=palette["bg"], foreground=palette["fg"],
                     font=("", DEFAULT_FONT_SIZE + 1, "bold"))
    style.configure("TLabel", background=palette["bg"], foreground=palette["fg"])
    style.configure("TCheckbutton", background=palette["bg"], foreground=palette["fg"])
    style.map("TCheckbutton", background=[("active", palette["bg"])])
    # relief="flat" - butoanele beveled implicite ale Tk arata invechit
    # (stil Windows 95); flat + bordura subtire e mai aproape de aspectul
    # butoanelor native macOS/moderne Windows 11.
    style.configure("TButton", background=palette["button_bg"], foreground=palette["fg"],
                     bordercolor=palette["border"], relief="flat", padding=(12, 7))
    style.map("TButton",
              background=[("active", palette["select_bg"]), ("disabled", palette["bg"])],
              foreground=[("disabled", palette["muted"])])
    style.configure("TEntry", fieldbackground=palette["entry_bg"], foreground=palette["entry_fg"],
                     insertcolor=palette["fg"], padding=(4, 4))
    style.configure("TCombobox", fieldbackground=palette["entry_bg"], foreground=palette["entry_fg"],
                     background=palette["button_bg"])
    style.map("TCombobox", fieldbackground=[("readonly", palette["entry_bg"])],
              foreground=[("readonly", palette["entry_fg"])])
    style.configure("Horizontal.TProgressbar", background=palette["select_bg"],
                     troughcolor=palette["trough"], bordercolor=palette["border"])
    style.configure("TScrollbar", background=palette["button_bg"], troughcolor=palette["trough"])
    style.configure("Muted.TLabel", background=palette["bg"], foreground=palette["muted"])

    # ── Buton principal (Start offload), scos in evidenta cu accent-ul ──
    style.configure("Accent.TButton", background=palette["accent"], foreground=palette["accent_fg"],
                     bordercolor=palette["accent"], relief="flat", font=("", 13, "bold"), padding=(22, 12))
    style.map("Accent.TButton",
              background=[("active", palette["accent_hover"]), ("disabled", palette["button_bg"])],
              foreground=[("disabled", palette["muted"])])

    # ── Procent mare in "Progres global" ──
    style.configure("BigPercent.TLabel", background=palette["bg"], foreground=palette["accent"],
                     font=("", 22, "bold"))

    # ── "Carduri" per destinatie (frame cu fundal usor ridicat) ──
    style.configure("Card.TFrame", background=palette["card_bg"])
    style.configure("Card.TLabel", background=palette["card_bg"], foreground=palette["fg"])
    style.configure("CardMuted.TLabel", background=palette["card_bg"], foreground=palette["muted"])
    style.configure("CardOk.TLabel", background=palette["card_bg"], foreground=palette["success"],
                     font=("", 12, "bold"))
    style.configure("CardErr.TLabel", background=palette["card_bg"], foreground=palette["error"],
                     font=("", 12, "bold"))
    style.configure("CardWait.TLabel", background=palette["card_bg"], foreground=palette["muted"],
                     font=("", 12, "bold"))
    style.configure("CardRun.TLabel", background=palette["card_bg"], foreground=palette["select_bg"],
                     font=("", 12, "bold"))


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
