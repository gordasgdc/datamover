#!/bin/bash
# Lanseaza_DataMover.command
# Wrapper de lansare: elimina carantina Gatekeeper si re-semneaza ad-hoc
# DataMover.app local, apoi il deschide. Ruleaza o singura data, la prima
# lansare, in loc de Right-click -> Open manual.
#
# In arhiva de distributie, DataMover.app sta intr-un subfolder "Aplicatie/"
# — asta e singurul fisier vizibil in radacina, ca sa nu existe confuzie
# despre pe ce sa apese cineva. Fallback pe acelasi folder pentru rulare
# locala directa din dist/ (build_app.sh nu creeaza subfolderul).

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
if [ -d "${DIR}/Aplicatie/DataMover.app" ]; then
    APP_PATH="${DIR}/Aplicatie/DataMover.app"
else
    APP_PATH="${DIR}/DataMover.app"
fi

if [ -d "${APP_PATH}" ]; then
    echo "==> Pregatesc DataMover.app pentru prima lansare..."
    xattr -dr com.apple.quarantine "${APP_PATH}" 2>/dev/null
    codesign --force --deep --sign - "${APP_PATH}" 2>/dev/null
    open "${APP_PATH}"
    sleep 1
    osascript -e 'tell application "Terminal" to close front window' 2>/dev/null &
else
    echo "Eroare: nu am gasit DataMover.app (cautat in Aplicatie/ si in ${DIR})."
    read -p "Apasa Enter pentru a inchide..."
fi
