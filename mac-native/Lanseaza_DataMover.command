#!/bin/bash
# Lanseaza_DataMover.command
# Wrapper de lansare: (1) muta DataMover.app in /Applications daca inca
# nu ruleaza de acolo, (2) elimina carantina Gatekeeper si re-semneaza
# ad-hoc, (3) il deschide. Ruleaza o singura data, la prima lansare, in
# loc de "muta manual in Applications" + "Right-click -> Open".
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

if [ ! -d "${APP_PATH}" ]; then
    echo "Eroare: nu am gasit DataMover.app (cautat in Aplicatie/ si in ${DIR})."
    read -p "Apasa Enter pentru a inchide..."
    exit 1
fi

INSTALLED_PATH="/Applications/DataMover.app"

# PITFALL FIXED 2026-08-24 (bug critic raportat inainte de release): pana
# acum userul trebuia sa mute manual DataMover.app in /Applications (pas
# din README, usor de sarit) — altfel aplicatia ramanea si rula direct
# din Downloads/arhiva descarcata. E singurul pas care lipsea fata de
# comportamentul standard macOS al unui .dmg cu "drag to Applications".
# Aici il automatizam: daca APP_PATH nu e deja /Applications/DataMover.app,
# cerem confirmare printr-un dialog nativ si mutam noi inainte de lansare.
if [[ "${APP_PATH}" != "${INSTALLED_PATH}" ]]; then
    echo "==> DataMover nu ruleaza din /Applications."
    RESPONSE=$(osascript <<'APPLESCRIPT' 2>/dev/null
button returned of (display dialog "DataMover trebuie mutat in folderul Applications ca sa functioneze corect (la fel ca orice aplicatie Mac standard). Il mut acum?" buttons {"Nu acum", "Muta in Applications"} default button "Muta in Applications" with icon note with title "DataMover")
APPLESCRIPT
)
    if [[ "${RESPONSE}" == "Muta in Applications" ]]; then
        echo "==> Mut ${APP_PATH} -> ${INSTALLED_PATH}..."

        # O versiune anterioara instalata deja acolo se inlocuieste curat
        # (userul tocmai a confirmat mutarea, deci si inlocuirea e asteptata).
        if [ -d "${INSTALLED_PATH}" ]; then
            rm -rf "${INSTALLED_PATH}" 2>/dev/null
        fi

        # 'ditto' pastreaza atribute/semnatura mai fidel decat 'cp -R'.
        # Daca /Applications nu e inscriptibil de userul curent (cont
        # non-admin, rar), cerem o singura data privilegii admin printr-un
        # dialog nativ — fara sa punem userul sa deschida Terminal manual.
        if ! ditto "${APP_PATH}" "${INSTALLED_PATH}" 2>/dev/null; then
            echo "==> /Applications necesita privilegii admin — cer confirmare..."
            osascript -e "do shell script \"rm -rf '${INSTALLED_PATH}' 2>/dev/null; ditto '${APP_PATH}' '${INSTALLED_PATH}'\" with administrator privileges" 2>/dev/null
        fi

        if [ -d "${INSTALLED_PATH}" ]; then
            # Curatam originalul (Downloads/arhiva extrasa) DOAR daca era o
            # copie locala pe care o putem sterge — nu lasam doua copii
            # din care userul ar putea porni din nou pe cea veche.
            if [ -w "$(dirname "${APP_PATH}")" ]; then
                rm -rf "${APP_PATH}"
            fi
            APP_PATH="${INSTALLED_PATH}"
        else
            echo "AVERTISMENT: mutarea in /Applications a esuat — pornesc din locatia curenta."
        fi
    fi
fi

echo "==> Pregatesc DataMover.app pentru lansare..."
xattr -dr com.apple.quarantine "${APP_PATH}" 2>/dev/null
if ! codesign --verify "${APP_PATH}" 2>/dev/null; then
    codesign --force --deep --sign - "${APP_PATH}" 2>/dev/null
fi
open "${APP_PATH}"
sleep 1
osascript -e 'tell application "Terminal" to close front window' 2>/dev/null &
