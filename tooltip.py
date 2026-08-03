"""
tooltip.py
----------
Iconite "?" cu tooltip explicativ, pentru setarile mai complexe din
DataMover (model de securitate, excluderi, "sari peste identice").
Fara dependinte externe - foloseste doar tkinter.

Tooltip-ul apare atat la hover (trecere cu mouse-ul), cat si la click
(util pe ecrane tactile sau pentru cei care prefera click). Ramane
deschis pana muti mouse-ul de pe iconita SAU mai dai click o data.

Utilizare:

    from tooltip import add_help_icon

    add_help_icon(
        frame_opts, row=0, column=3,
        text="MD5 e rapid si e standardul industriei...\n"
             "SHA-256/512 sunt mai lente dar mai sigure."
    )
"""

import tkinter as tk
from tkinter import ttk


class ToolTip:
    """Ataseaza un tooltip unui widget (de obicei o iconita '?')."""

    def __init__(self, widget, text, wraplength=320):
        self.widget = widget
        self.text = text
        self.wraplength = wraplength
        self.tip_window = None
        self._locked_open = False  # True daca a fost deschis prin click

        widget.bind("<Enter>", self._on_enter)
        widget.bind("<Leave>", self._on_leave)
        widget.bind("<Button-1>", self._on_click)

    def _on_enter(self, _event=None):
        self._show()

    def _on_leave(self, _event=None):
        if not self._locked_open:
            self._hide()

    def _on_click(self, _event=None):
        if self.tip_window is not None:
            self._locked_open = False
            self._hide()
        else:
            self._locked_open = True
            self._show()

    def _show(self):
        if self.tip_window is not None:
            return
        try:
            x = self.widget.winfo_rootx() + 18
            y = self.widget.winfo_rooty() + self.widget.winfo_height() + 4
        except Exception:
            return

        tw = tk.Toplevel(self.widget)
        self.tip_window = tw
        tw.wm_overrideredirect(True)
        try:
            tw.wm_attributes("-topmost", True)
        except Exception:
            pass
        tw.wm_geometry(f"+{x}+{y}")

        frame = tk.Frame(tw, background="#333333", borderwidth=1, relief="solid")
        frame.pack()
        label = tk.Label(
            frame, text=self.text, justify="left", background="#333333",
            foreground="#ffffff", wraplength=self.wraplength,
            padx=8, pady=6, font=("TkDefaultFont", 10),
        )
        label.pack()

    def _hide(self):
        if self.tip_window is not None:
            try:
                self.tip_window.destroy()
            except Exception:
                pass
            self.tip_window = None


def add_help_icon(parent, row, column, text, sticky="w", padx=4, pady=0, columnspan=1):
    """Creeaza o iconita '?' folosind grid() in 'parent', la (row, column),
    cu un ToolTip atasat, si returneaza label-ul (util daca vrei sa-l
    recolorezi pentru dark mode). Instanta ToolTip e expusa la
    icon.dm_tooltip, ca sa poti actualiza textul mai tarziu (ex. la
    schimbarea limbii interfetei) fara sa recreezi iconita."""
    icon = tk.Label(
        parent, text=" ? ", font=("TkDefaultFont", 9, "bold"),
        background="#dddddd", foreground="#333333",
        relief="raised", borderwidth=1, cursor="question_arrow",
    )
    icon.grid(row=row, column=column, sticky=sticky, padx=padx, pady=pady, columnspan=columnspan)
    icon.dm_tooltip = ToolTip(icon, text)
    return icon


def add_help_icon_packed(parent, text, side="left", padx=4, pady=0):
    """Varianta cu pack() in loc de grid(), pentru randuri construite cu pack().
    La fel ca add_help_icon, expune ToolTip-ul la icon.dm_tooltip."""
    icon = tk.Label(
        parent, text=" ? ", font=("TkDefaultFont", 9, "bold"),
        background="#dddddd", foreground="#333333",
        relief="raised", borderwidth=1, cursor="question_arrow",
    )
    icon.pack(side=side, padx=padx, pady=pady)
    icon.dm_tooltip = ToolTip(icon, text)
    return icon
