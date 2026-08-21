#!/usr/bin/env python3
"""
DataMover — punct de intrare unic. Alege interfata dupa sistemul de
operare: ui/mac/app.py pe macOS, ui/windows/app.py pe Windows (si orice
alt OS, ca fallback — interfata "Windows" e de fapt cea originala,
cross-platform, doar redenumita dupa noua structura ui/mac + ui/windows).

Backend-ul (core/) e comun ambelor interfete si ramane neschimbat.

Ruleaza cu: python3 main.py
"""
import sys


def main():
    if sys.platform == "darwin":
        from ui.mac.app import run
    else:
        from ui.windows.app import run
    run()


if __name__ == "__main__":
    main()
