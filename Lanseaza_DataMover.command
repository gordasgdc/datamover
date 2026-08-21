#!/bin/bash
# Lanseaza_DataMover.command — dublu-click pentru a porni DataMover
# fara avertismentele Gatekeeper ("Developer cannot be verified" /
# "App is damaged and can't be opened"), care apar pentru ca aplicatia
# nu e semnata cu un cont Apple Developer Program platit.
#
# Pune acest fisier IN ACELASI FOLDER cu DataMover.app inainte sa il
# trimiti mai departe (arhiva zip trebuie facuta cu 'ditto', nu cu
# Finder -> Compress, ca sa pastreze permisiunile corect).
cd "$(dirname "$0")"

APP_NAME="DataMover.app"

if [ ! -d "$APP_NAME" ]; then
    echo "EROARE: nu gasesc \"$APP_NAME\" in acest folder."
    echo "Pastreaza acest fisier langa $APP_NAME, nu il muta separat."
    read -p "Apasa Enter pentru a inchide..."
    exit 1
fi

echo "Pregatesc $APP_NAME pentru rulare..."

# Scoate carantina pusa de macOS la descarcare din browser/AirDrop —
# principala cauza a erorilor Gatekeeper. Ruleaza silentios daca nu
# exista deja (fisierul poate sa nu fie in carantina la rulari ulterioare).
xattr -dr com.apple.quarantine "$APP_NAME" 2>/dev/null

# Daca semnatura nu (mai) e valida (ex. copiere prin alt canal decat
# ditto, care poate rupe semnatura), o reaplicam ad-hoc local ca sa
# porneasca curat, fara sa cerem userului comenzi in Terminal.
if ! codesign --verify "$APP_NAME" 2>/dev/null; then
    echo "Semnatura lipsa/invalida — aplic semnatura locala..."
    codesign --force --deep --sign - "$APP_NAME" 2>/dev/null
fi

echo "Pornesc $APP_NAME..."
open "$APP_NAME"
