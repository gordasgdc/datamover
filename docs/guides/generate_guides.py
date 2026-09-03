#!/usr/bin/env python3
"""Genereaza cele 3 ghiduri PDF (RO/EN/ES) pentru DataMover.

Ruleaza cu:  pip install reportlab pillow && python3 generate_guides.py

Structura, dupa refacerea din 2026-09-03:
  _engine.py  - compunerea PDF-ului (coperta, cuprins cu numere de pagina,
                casete de accent, pasi numerotati, tabele de optiuni)
  ghid_ro.py / ghid_en.py / ghid_es.py - continutul, per limba

Continutul e separat de motor tocmai ca o schimbare de text sa nu poata
strica asezarea in pagina, si invers.
"""
import _engine
from ghid_ro import RO
from ghid_en import EN
from ghid_es import ES

if __name__ == "__main__":
    _engine.build("ro", "DataMover_Ghid_RO.pdf", RO)
    _engine.build("en", "DataMover_Guide_EN.pdf", EN)
    _engine.build("es", "DataMover_Guia_ES.pdf", ES)
