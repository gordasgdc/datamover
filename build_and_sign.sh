#!/bin/bash
# build_and_sign.sh — build local + semnare ad-hoc, pentru distribuție
# internă (colegi) fara cont Apple Developer Program platit ($99/an) si
# fara niciun pas manual de configurare (nu e nevoie sa creezi vreun
# certificat in Keychain). Rezultatul tot declanseaza avertismentul
# Gatekeeper la prima deschidere directa a .app-ului (asta cere
# notarizare reala Apple, care are nevoie de cont platit) - dar
# semnatura ad-hoc + xattr -cr elimina eroarea grava "App is damaged
# and can't be opened", care apare la aplicatii nesemnate deloc.
# Impreuna cu Lanseaza_DataMover.command (care scoate si carantina),
# colegii nu mai vad nici avertismentul.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DataMover"

echo "==> Compilez $APP_NAME.app (py2app)..."
rm -rf build dist
python3 setup.py py2app

APP_PATH="dist/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
    echo "EROARE: $APP_PATH nu a fost generat." >&2
    exit 1
fi

echo "==> Curat atributele extinse (xattr -cr)..."
xattr -cr "$APP_PATH"

echo "==> Semnez ad-hoc (fara cont Apple Developer)..."
codesign --force --deep --sign - "$APP_PATH"

echo "==> Verific semnatura..."
codesign --verify --verbose "$APP_PATH"

echo ""
echo "==> Gata: $APP_PATH"
echo "    Pune-l intr-un folder impreuna cu Lanseaza_DataMover.command"
echo "    inainte sa il trimiti colegilor (arhiveaza cu 'ditto', nu cu"
echo "    Finder/'Compress', ca sa pastrezi permisiunile Mac corect)."
