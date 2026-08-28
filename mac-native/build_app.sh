#!/bin/bash
# build_app.sh — compileaza DataMoverMac in release si il impacheteaza
# intr-un .app bundle (cu Info.plist), semnat cu Developer ID Application
# + notarizat daca certificatul e configurat pe acest Mac (vezi
# codesigning/README.md), altfel cade pe semnare ad-hoc. Rularea binarului
# brut din .build/release/ direct (fara bundle) poate cauza probleme de
# focus tastatura in TextField-uri, ca nu exista un proces de aplicatie
# "regular" corect inregistrat la WindowServer — .app bundle-ul rezolva asta.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="DataMover"
BIN_NAME="DataMoverMac"

echo "==> Compilez ($BIN_NAME, release)..."
swift build -c release

APP_PATH="dist/$APP_NAME.app"

# GARDA (2026-08-28, bug real repetat de 3 ori in aceeasi sesiune):
# "dist/" ramane ocazional detinut de root dupa un build anterior (cauza
# exacta neconfirmata - posibil o instalare locala de test cu
# `sudo installer -pkg ... -target /` care a atins accidental acest
# folder, sau un artefact dintr-un rulaj anterior sub alt utilizator) -
# `rm -rf` esueaza tacut, partial, cu o gramada de "Permission denied"
# greu de gasit in mijlocul unui log lung de build. Verificam explicit
# INAINTE, cu un mesaj clar si actionabil, in loc sa lasam `rm -rf` sa
# esueze cu zeci de linii criptice.
if [ -d "dist" ] && ! [ -w "dist" ] || find dist -maxdepth 2 -user root -print -quit 2>/dev/null | grep -q .; then
    echo "" >&2
    echo "EROARE: 'dist/' contine fisiere detinute de root (dintr-un build" >&2
    echo "anterior). Ruleaza o data, manual, in Terminal:" >&2
    echo "" >&2
    echo "    sudo rm -rf $(pwd)/dist" >&2
    echo "" >&2
    echo "apoi reincearca build-ul FARA sudo." >&2
    exit 1
fi
rm -rf "dist"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

cp ".build/release/$BIN_NAME" "$APP_PATH/Contents/MacOS/$BIN_NAME"
cp "Info.plist" "$APP_PATH/Contents/Info.plist"
cp "AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"

echo "==> Curat atributele extinse..."
xattr -cr "$APP_PATH"

# Semnare reala (Developer ID Application) + notarizare, daca certificatul
# e configurat pe acest Mac (vezi codesigning/README.md) - altfel cade pe
# semnare ad-hoc, ca inainte (Gatekeeper va bloca la prima deschidere,
# necesita xattr/click-dreapta -> Open pana se configureaza certificatul).
if [ -n "${APPLE_SIGN_IDENTITY_APP:-}" ]; then
    ./codesigning/sign-and-notarize.sh app "$APP_PATH"
else
    echo "==> [codesigning] APPLE_SIGN_IDENTITY_APP nesetata - semnez ad-hoc (nesemnat oficial)."
    codesign --force --deep --sign - "$APP_PATH"
fi
codesign --verify --verbose "$APP_PATH"

echo ""
echo "==> Gata: $APP_PATH"
echo "    Deschide-l cu: open \"$APP_PATH\""
