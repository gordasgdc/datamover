#!/usr/bin/env bash
# release.sh — orchestreaza un release complet (Mac + Windows) dintr-o
# singura comanda:
#
#   ./release.sh 2.5.4 "Descrierea schimbarilor pentru update.json"
#
# ARCHITECTURE NOTE — de ce exista scriptul asta acum si nu inainte:
# fluxul documentat in CLAUDE.md ("1. build local Mac, 2. push tag pt. CI
# Windows, 3. gh release upload manual pt. Mac") a fost urmat manual, pas
# cu pas, la lansarea 2.5.3 — si a esuat o data in mijlocul procesului:
# `zsh -lc` (login shell) nu citeste ~/.zshrc (doar shell-urile
# INTERACTIVE il citesc), asa ca APPLE_SIGN_IDENTITY_APP a iesit nesetata,
# iar build_installer.sh a cazut TACUT pe semnare ad-hoc — exact
# regresia pe care auditul din CLAUDE.md o documentase deja ca reparata
# ("TeamIdentifier=not set"). Diferenta fata de atunci: a fost prinsa
# citind manual log-ul, inainte de upload. Un flux automat trebuie sa
# prinda asta SINGUR, nu prin citire atenta de om — de-aici Pasul 3 de
# mai jos, care verifica REZULTATUL (`spctl`), nu promisiunea scriptului
# de semnare.
#
# WARNING: NU modifica `mac-native/codesigning/sign-and-notarize.sh` ca
# sa faca verificarea asta. E un modul COMUN, copiat neschimbat in toate
# repo-urile GDC (vezi comentariul lui) — cade INTENTIONAT tacut pe
# nesemnat cand certificatul nu exista inca (bring-up timpuriu, inainte
# de abonamentul Apple Developer). Poarta de verificare trebuie sa stea
# AICI, la nivel de orchestrare specifica DataMover, care STIE ca
# semnarea reala e deja obligatorie pentru acest proiect (per audit).
#
# WARNING: acest script NU muta build-ul Mac in CI. Certificatul Developer
# ID traieste doar in Keychain-ul local (asa a fost ales explicit, vezi
# audit-ul din CLAUDE.md) — exportarea lui ca secret CI (.p12 + parola) e
# o decizie de securitate care iti apartine tie, nu ceva de facut automat.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?Usage: ./release.sh <versiune, ex. 2.5.4> \"<descriere schimbari>\"}"
CHANGES="${2:?Usage: ./release.sh <versiune, ex. 2.5.4> \"<descriere schimbari>\"}"
TAG="v$VERSION"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "EROARE: versiunea trebuie sa fie X.Y.Z (ex. 2.5.4), am primit: $VERSION" >&2
    exit 1
fi

echo "════════════════════════════════════════════════════════════════"
echo " Release DataMover $TAG"
echo "════════════════════════════════════════════════════════════════"

# ── Pas 0: repo curat, tag-ul nu exista deja ────────────────────────────
if [ -n "$(git status --porcelain)" ]; then
    echo "EROARE: ai modificari necomise. Comite sau stash-uieste inainte de release." >&2
    git status --short >&2
    exit 1
fi
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "EROARE: tag-ul $TAG exista deja." >&2
    exit 1
fi

# ── Pas 1: bump in cele PATRU locuri sincrone ───────────────────────────
# Aceleasi patru locuri gasite si sincronizate manual la 2.5.3 — vezi
# CHANGELOG.md v2.5.2 (core/update_config.py ramasese blocat 5 zile la o
# versiune veche, exact pentru ca update-ul asta se face de obicei manual
# si se uita un loc).
echo "==> [1/6] Bump versiune in Info.plist, installer.iss, docs/update.json, core/update_config.py, windows-native…"

OLD_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" mac-native/Info.plist)
NEW_BUILD=$((OLD_BUILD + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" mac-native/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" mac-native/Info.plist

sed -i '' -E "s/#define MyAppVersion \"[0-9]+\.[0-9]+\.[0-9]+\"/#define MyAppVersion \"$VERSION\"/" installer.iss

# windows-native (client WPF nou) - propriul .csproj + installer.iss,
# ACUM sincronizate cu release-ul principal (2026-08-28: primul release
# care publica si acest client - vezi CLAUDE.md).
sed -i '' -E "s/<Version>[0-9]+\.[0-9]+\.[0-9]+<\/Version>/<Version>$VERSION<\/Version>/" windows-native/DataMover.Client/DataMover.Client.csproj
sed -i '' -E "s/#define MyAppVersion \"[0-9]+\.[0-9]+\.[0-9]+\"/#define MyAppVersion \"$VERSION\"/" windows-native/installer.iss

python3 - "$VERSION" "$CHANGES" <<'PY'
import json, sys, collections, datetime
version, changes = sys.argv[1], sys.argv[2]
p = "docs/update.json"
d = json.load(open(p), object_pairs_hook=collections.OrderedDict)
d["version"] = version
d["release_date"] = datetime.date.today().isoformat()
d["changes"] = changes
# Client WPF nou (2026-08-28) - acum publicat de release.sh ca artefact
# real (DataMover-WPF-Windows.zip), vezi build-windows-wpf in release.yml.
# Campul "windows" ramane pt. clientul Python vechi (coexista).
d["download_url"]["windows_wpf"] = "https://github.com/gordasgdc/datamover/releases/latest/download/DataMover-WPF-Windows.zip"
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
open(p, "a").write("\n")
PY

sed -i '' -E "s/APP_VERSION = \"[0-9]+\.[0-9]+\.[0-9]+\"/APP_VERSION = \"$VERSION\"/" core/update_config.py

# Verificare HARD: toate patru trebuie sa fie EXACT versiunea ceruta,
# altfel oprim aici — un release cu un loc ramas in urma repeta exact
# bug-ul din CHANGELOG v2.5.2 (self-update etern "disponibil").
FOUND_PLIST=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" mac-native/Info.plist)
FOUND_ISS=$(grep -oE 'MyAppVersion "[0-9.]+"' installer.iss | grep -oE '[0-9.]+')
FOUND_JSON=$(python3 -c "import json;print(json.load(open('docs/update.json'))['version'])")
FOUND_PY=$(grep -oE 'APP_VERSION = "[0-9.]+"' core/update_config.py | grep -oE '[0-9.]+')
FOUND_WPF_CSPROJ=$(grep -oE '<Version>[0-9.]+</Version>' windows-native/DataMover.Client/DataMover.Client.csproj | grep -oE '[0-9.]+')
FOUND_WPF_ISS=$(grep -oE 'MyAppVersion "[0-9.]+"' windows-native/installer.iss | grep -oE '[0-9.]+')
for pair in "Info.plist:$FOUND_PLIST" "installer.iss:$FOUND_ISS" "update.json:$FOUND_JSON" "update_config.py:$FOUND_PY" "windows-native/DataMover.Client.csproj:$FOUND_WPF_CSPROJ" "windows-native/installer.iss:$FOUND_WPF_ISS"; do
    name="${pair%%:*}"; found="${pair##*:}"
    if [ "$found" != "$VERSION" ]; then
        echo "EROARE: $name a ramas la $found, nu $VERSION — bump esuat." >&2
        exit 1
    fi
    echo "    $name -> $found  OK"
done

# ── Pas 2: build + semnare + notarizare Mac, LOCAL (shell interactiv) ───
# `zsh -ic` (NU `-lc`): doar shell-urile interactive citesc ~/.zshrc, unde
# stau APPLE_SIGN_IDENTITY_APP/INSTALLER. Vezi ARCHITECTURE NOTE de sus.
echo "==> [2/6] Compilez, semnez si notarizez Mac (poate dura pana la 15 min)…"
( cd mac-native && zsh -ic "./build_installer.sh" )

# ── Pas 3: VERIFICARE REALA a semnarii — nu ne bazam pe output-ul scriptului ──
# Asta e poarta care a lipsit la 2.5.3: scriptul de semnare poate cadea
# tacut pe ad-hoc daca identitatea nu s-a citit din mediu, iar exit code-ul
# ramane 0 oricum (e un fallback intentionat pt. alte repo-uri, vezi
# WARNING de sus). Singura dovada de incredere e `spctl`, care intreaba
# efectiv Gatekeeper/Apple, nu scriptul nostru.
echo "==> [3/6] Verific INDEPENDENT ca pachetul Mac e semnat + notarizat (spctl)…"
PKG_PATH="mac-native/dist/DataMover-$VERSION.pkg"
if [ ! -f "$PKG_PATH" ]; then
    echo "EROARE: $PKG_PATH nu exista dupa build." >&2
    exit 1
fi
SPCTL_OUT=$(spctl -a -vvv -t install "$PKG_PATH" 2>&1) || true
echo "$SPCTL_OUT"
if ! echo "$SPCTL_OUT" | grep -q "source=Notarized Developer ID"; then
    echo "" >&2
    echo "OPRIT: $PKG_PATH NU e semnat+notarizat de Apple (spctl nu a" >&2
    echo "confirmat 'Notarized Developer ID'). Nu public un build nesemnat." >&2
    echo "Verifica manual: APPLE_SIGN_IDENTITY_APP e in ~/.zshrc si Keychain-ul" >&2
    echo "are certificatele 'Developer ID Application/Installer'." >&2
    exit 1
fi
echo "    OK — Gatekeeper confirma: semnat si notarizat."

# ── Pas 4: commit versiune + push (main) ────────────────────────────────
echo "==> [4/6] Commit + push bump de versiune…"
git add mac-native/Info.plist installer.iss docs/update.json core/update_config.py \
    windows-native/DataMover.Client/DataMover.Client.csproj windows-native/installer.iss
git commit -q -m "Versiune $VERSION

$CHANGES

Bump automat prin release.sh in cele patru locuri sincrone, cu
verificare ca toate patru chiar au ajuns la $VERSION inainte de a
continua."
git push origin main

# ── Pas 5: tag + push -> declanseaza CI Windows + creeaza release-ul ────
echo "==> [5/6] Tag $TAG + push -> asteapt CI Windows…"
git tag "$TAG"
git push origin "$TAG"

# Asteptam sa APARA run-ul workflow-ului de release pentru acest tag
# (poate dura cateva secunde dupa push pana GitHub il porneste).
RUN_ID=""
for i in $(seq 1 15); do
    RUN_ID=$(gh run list --workflow="Release DataMover (Mac + Windows)" --json databaseId,headBranch -q \
        ".[] | select(.headBranch==\"$TAG\") | .databaseId" 2>/dev/null | head -1)
    [ -n "$RUN_ID" ] && break
    sleep 4
done
if [ -z "$RUN_ID" ]; then
    echo "EROARE: nu am gasit run-ul de CI pentru $TAG dupa 60s. Verifica manual:" >&2
    echo "  gh run list --workflow=\"Release DataMover (Mac + Windows)\"" >&2
    exit 1
fi
echo "    Run CI: $RUN_ID — astept sa termine…"

for i in $(seq 1 40); do
    STATUS=$(gh run view "$RUN_ID" --json status,conclusion -q '.status + " " + (.conclusion // "-")')
    echo "    [$i] $STATUS"
    case "$STATUS" in
        "completed success") break ;;
        completed*)
            echo "EROARE: CI-ul Windows a esuat ($STATUS). Vezi: gh run view $RUN_ID --log-failed" >&2
            exit 1
            ;;
    esac
    sleep 15
done

# ── Pas 6: atasez artefactele Mac deja verificate la release-ul creat ───
echo "==> [6/6] Urc artefactele Mac semnate pe release-ul $TAG…"
gh release upload "$TAG" \
    "mac-native/dist/DataMover-$VERSION.pkg" \
    "mac-native/dist/DataMover.pkg" \
    "mac-native/dist/DataMover-Mac.zip" \
    "mac-native/dist/Dezinstalare_DataMover.command" \
    --clobber

echo ""
echo "════════════════════════════════════════════════════════════════"
echo " Verificare finala (releases/latest/download + API de update)"
echo "════════════════════════════════════════════════════════════════"
FAILED=0
for f in DataMover-Mac.zip DataMover-Windows.zip DataMover-WPF-Windows.zip; do
    CODE=$(curl -sIL -o /dev/null -w '%{http_code}' "https://github.com/gordasgdc/datamover/releases/latest/download/$f")
    RESOLVED_TAG=$(curl -sI "https://github.com/gordasgdc/datamover/releases/latest/download/$f" \
        | grep -i '^location:' | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+" | head -1)
    printf "  %-24s HTTP %s  tag=%s\n" "$f" "$CODE" "${RESOLVED_TAG:-?}"
    [ "$CODE" = "200" ] && [ "$RESOLVED_TAG" = "$TAG" ] || FAILED=1
done
API_TAG=$(curl -s https://api.github.com/repos/gordasgdc/datamover/releases/latest | python3 -c "import json,sys;print(json.load(sys.stdin)['tag_name'])")
echo "  API-ul de update (UpdateChecker.swift) vede: $API_TAG"
[ "$API_TAG" = "$TAG" ] || FAILED=1

if [ "$FAILED" = "1" ]; then
    echo "" >&2
    echo "AVERTISMENT: cel putin o verificare finala nu se potriveste. Nu" >&2
    echo "declara release-ul gata fara sa investighezi diferenta de mai sus." >&2
    exit 1
fi

echo ""
echo "Release $TAG complet: https://github.com/gordasgdc/datamover/releases/tag/$TAG"
