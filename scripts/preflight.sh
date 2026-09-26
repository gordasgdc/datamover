#!/bin/bash
# preflight.sh — verificare rapidă, reutilizabilă, înainte de commit/release.
# Nu scrie nimic în afara folderelor de build și nu atinge volume reale.
#
#   scripts/preflight.sh            build + teste + versiuni + localizare
#   scripts/preflight.sh --online   + linkurile publice (doar HEAD, read-only)
#   scripts/preflight.sh --quick    fără build Windows
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
FAIL=0
ok()   { echo "  ✓ $*"; }
bad()  { echo "  ✗ $*"; FAIL=$((FAIL+1)); }
warn() { echo "  ! $*"; }
ONLINE=0; QUICK=0
for a in "$@"; do case $a in --online) ONLINE=1;; --quick) QUICK=1;; esac; done

echo "== Versiuni (Regula 14)"
V_PLIST=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" mac-native/Info.plist)
V_CSPROJ=$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' windows-native/DataMover.Client/DataMover.Client.csproj | head -1)
V_ISS=$(sed -n 's/^#define MyAppVersion "\(.*\)"/\1/p' windows-native/installer.iss)
V_JSON=$(python3 -c 'import json;print(json.load(open("docs/update.json"))["version"])')
V_LOG=$(grep -m1 -oE "^## v?[0-9]+\.[0-9]+\.[0-9]+" CHANGELOG.md | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
echo "    Info.plist=$V_PLIST csproj=$V_CSPROJ installer.iss=$V_ISS CHANGELOG=$V_LOG update.json=$V_JSON"
[ "$V_PLIST" = "$V_CSPROJ" ] && [ "$V_PLIST" = "$V_ISS" ] && ok "cod sincronizat ($V_PLIST)" || bad "versiuni diferite în cod"
[ "$V_PLIST" = "$V_LOG" ] && ok "CHANGELOG are intrarea $V_PLIST" || bad "CHANGELOG nu începe cu $V_PLIST (Regula 25)"
if [ "$V_JSON" = "$V_PLIST" ]; then ok "update.json anunță versiunea din cod"
else warn "update.json anunță $V_JSON — se actualizează DOAR la publicare (Regula 35)"; fi

echo "== Siguranță git"
if git log --all --format=%B | grep -qi "Co-Authored-By: Claude"; then bad "atribuire Claude în istoric (Regula 32)"; else ok "fără atribuire Claude"; fi
git ls-files | grep -Eq '\.(p12|p8|pem|key|mobileprovision|pfx)$' && bad "chei/certificate urmărite de git" || ok "nicio cheie în git"
git ls-files --error-unmatch PROJECT_STATE.md >/dev/null 2>&1 && bad "PROJECT_STATE.md e comis (repo public)" || ok "PROJECT_STATE.md doar local"

echo "== macOS: build + teste"
( cd mac-native && swift build 2>&1 | grep -E "error:" ) && bad "swift build" || ok "swift build (debug)"
TEST_OUT=$(cd mac-native && swift test 2>&1)
if echo "$TEST_OUT" | grep -q "with 0 failures"; then
    ok "$(echo "$TEST_OUT" | grep -E 'Executed [0-9]+ tests' | tail -1 | sed 's/^[[:space:]]*//')"
else
    bad "swift test"; echo "$TEST_OUT" | grep -E "error|failed" | head -20
fi

echo "== Localizare (RO/EN/ES)"
python3 - <<'PY' && ok "chei complete, specificatori identici" || bad "localizare incompletă"
import re, glob, sys
src = "mac-native/Sources/DataMoverMac/"
tables = open(src + "Localization.swift").read() + open(src + "LocalizationExtra.swift").read()
entries = re.findall(r'^\s*"([^"]+)":\s*\[(.*?)\],?\s*$', tables, re.M | re.S)
defined = {k for k, _ in entries}
bad = []
for k, body in entries:
    langs = dict(re.findall(r'\.(ro|en|es):\s*"((?:[^"\\]|\\.)*)"', body))
    if set(langs) != {"ro", "en", "es"}: bad.append(f"{k}: lipsește o limbă")
    specs = {l: sorted(re.findall(r'%[@d]', v)) for l, v in langs.items()}
    if len({tuple(s) for s in specs.values()}) > 1: bad.append(f"{k}: specificatori diferiți")
used = set()
for f in glob.glob(src + "**/*.swift", recursive=True):
    used |= set(re.findall(r'L\.t\("([^"\\]+)"\)', open(f).read()))
missing = sorted(u for u in used - defined if "\\(" not in u)
bad += [f"{m}: folosită, nedefinită" for m in missing]
for b in bad: print("    " + b)
sys.exit(1 if bad else 0)
PY

if [ $QUICK -eq 0 ] && command -v dotnet >/dev/null; then
    echo "== Windows: build (cross, fără XAML runtime) + verificări motor"
    OUT=$(mktemp -d)
    dotnet build windows-native/DataMover.Client/DataMover.Client.csproj -c Release -o "$OUT" 2>&1 | grep -q " 0 Error" \
        && ok "dotnet build DataMover.Client" || bad "dotnet build DataMover.Client"
    rm -rf "$OUT"
    ( cd windows-native/DataMover.CoreChecks && dotnet run -c Release 2>&1 | tail -1 | grep -q "TOATE" ) \
        && ok "verificări FanOutCopier (C#)" || bad "verificări FanOutCopier (C#)"
fi

if [ $ONLINE -eq 1 ]; then
    echo "== Linkuri publice (HEAD, read-only)"
    for u in $(python3 -c 'import json;print(" ".join(json.load(open("docs/update.json"))["download_url"].values()))') \
             $(grep -oE 'https://github.com/gordasgdc/datamover/releases/latest/download/[^"]+' docs/index.html | sort -u); do
        c=$(curl -sIL -o /dev/null -w "%{http_code}" "$u")
        [ "$c" = "200" ] && ok "$c $u" || bad "$c $u"
    done
fi

echo
[ $FAIL -eq 0 ] && echo "PREFLIGHT OK" || echo "PREFLIGHT: $FAIL problemă(e)"
exit $FAIL
