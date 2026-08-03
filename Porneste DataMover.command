#!/bin/bash
# Porneste DataMover - dublu-click pe acest fisier pe Mac
cd "$(dirname "$0")"

VENV_DIR=".venv"

# Prima rulare: cream un mediu Python izolat (venv), separat de Python-ul
# de sistem, ca sa evitam erorile de tip "externally-managed-environment"
# aparute pe Mac-urile cu Python instalat prin Homebrew.
if [ ! -d "$VENV_DIR" ]; then
    echo "Prima rulare: se pregateste mediul aplicatiei (dureaza cateva secunde)..."
    python3 -m venv "$VENV_DIR"
    if [ $? -ne 0 ]; then
        echo ""
        echo "EROARE: nu am putut crea mediul Python (venv)."
        echo "Verifica daca Python 3 este instalat corect (python3 --version)."
        read -p "Apasa Enter pentru a inchide..."
        exit 1
    fi
    "$VENV_DIR/bin/pip" install --upgrade pip --quiet
    "$VENV_DIR/bin/pip" install reportlab tkinterdnd2 --quiet
    if [ $? -ne 0 ]; then
        echo ""
        echo "AVERTISMENT: nu am putut instala toate dependintele (rapoartele PDF"
        echo "si/sau drag-and-drop-ul pot sa nu functioneze, dar restul aplicatiei"
        echo "merge normal). Verifica conexiunea la internet si incearca din nou"
        echo "data viitoare (sterge folderul .venv si reporneste)."
        read -p "Apasa Enter pentru a continua..."
    fi
fi

"$VENV_DIR/bin/python3" main.py
