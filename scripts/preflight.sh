#!/bin/bash
# preflight.sh — verificare rapidă, reutilizabilă, înainte de commit/release.
# Nu scrie nimic în afara folderelor de build/temporare și nu atinge volume reale.
#
#   scripts/preflight.sh            versiuni, git, build+teste Mac (debug+release),
#                                   localizare, design audit, build Windows + verificări C#
#   scripts/preflight.sh --online   + linkurile publice (doar HEAD, read-only)
#   scripts/preflight.sh --quick    fără release Mac și fără Windows
#   scripts/preflight.sh --volumes  + teste pe volume temporare (disc plin, exFAT)
#   scripts/preflight.sh --vm       + verificări Windows reale în VM Parallels (dacă rulează)
#
# Fiecare pas e judecat după EXIT CODE-UL comenzii originale (nu după grep).
# Ieșirea completă a unui pas eșuat rămâne în $LOG_DIR și coada ei e afișată.
# Test al scriptului însuși: DM_PREFLIGHT_SIMULATE_FAIL=<nume-pas> forțează
# eșecul acelui pas (ex. swift-build) ca să dovedească statusul nenul.
set -uo pipefail
cd "$(dirname "$0")/.."
FAIL=0
LOG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dm-preflight.XXXXXX")
ok()   { echo "  ✓ $*"; }
bad()  { echo "  ✗ $*"; FAIL=$((FAIL+1)); }
warn() { echo "  ! $*"; }
ONLINE=0; QUICK=0; VOLUMES=0; VM=0
for a in "$@"; do case $a in --online) ONLINE=1;; --quick) QUICK=1;; --volumes) VOLUMES=1;; --vm) VM=1;; esac; done

# step <nume> <descriere> <comandă...> — rulează comanda, judecă exit code-ul.
step() {
    local name=$1 desc=$2; shift 2
    local log="$LOG_DIR/$name.log" rc
    if [ "${DM_PREFLIGHT_SIMULATE_FAIL:-}" = "$name" ]; then
        echo "eșec simulat (DM_PREFLIGHT_SIMULATE_FAIL=$name)" > "$log"; rc=97
    else
        "$@" > "$log" 2>&1; rc=$?
    fi
    if [ $rc -eq 0 ]; then ok "$desc"
    else
        bad "$desc (exit $rc) — log: $log"
        grep -E "error:|Error |failed|✗|eșec" "$log" | head -15 | sed 's/^/      /'
        tail -5 "$log" | sed 's/^/      | /'
    fi
    return $rc
}

echo "== Versiuni (Regula 14)"
V_PLIST=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" mac-native/Info.plist)
V_CSPROJ=$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' windows-native/DataMover.Client/DataMover.Client.csproj | head -1)
V_ISS=$(sed -n 's/^#define MyAppVersion "\(.*\)"/\1/p' windows-native/installer.iss)
V_PY=$(sed -n 's/^APP_VERSION = "\([^"]*\)".*/\1/p' core/update_config.py)
V_JSON=$(python3 -c 'import json;print(json.load(open("docs/update.json"))["version"])')
V_LOG=$(grep -m1 -oE "^## v?[0-9]+\.[0-9]+\.[0-9]+" CHANGELOG.md | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
echo "    Info.plist=$V_PLIST csproj=$V_CSPROJ iss=$V_ISS python=$V_PY CHANGELOG=$V_LOG update.json=$V_JSON"
if [ "$V_PLIST" = "$V_CSPROJ" ] && [ "$V_PLIST" = "$V_ISS" ] && [ "$V_PLIST" = "$V_PY" ]; then ok "cod sincronizat ($V_PLIST)"; else bad "versiuni diferite în cod"; fi
if [ "$V_PLIST" = "$V_LOG" ]; then ok "CHANGELOG are intrarea $V_PLIST"; else bad "CHANGELOG nu începe cu $V_PLIST (Regula 25)"; fi
if [ "$V_JSON" = "$V_PLIST" ]; then ok "update.json anunță versiunea din cod"
else warn "update.json anunță $V_JSON — se actualizează DOAR la publicare (Regula 35)"; fi

echo "== Siguranță git"
if git log --all --format=%B | grep -qi "Co-Authored-By: Claude"; then bad "atribuire Claude în istoric (Regula 32)"; else ok "fără atribuire Claude"; fi
if git ls-files | grep -Eq '\.(p12|p8|pem|key|mobileprovision|pfx)$'; then bad "chei/certificate urmărite de git"; else ok "nicio cheie în git"; fi
if git ls-files --error-unmatch PROJECT_STATE.md >/dev/null 2>&1; then bad "PROJECT_STATE.md e comis (repo public)"; else ok "PROJECT_STATE.md doar local"; fi
if git ls-files | grep -Eq '(^|/)(design-review|\.build|obj)/|/bin/(Release|Debug|uitest)/'; then bad "builduri/capturi urmărite de git"; else ok "fără builduri/capturi în git"; fi
step diff-check "git diff --check (lucru curent + commiturile ramurii față de main)" \
    bash -c 'git diff --check HEAD && { ! git rev-parse -q --verify main >/dev/null || git diff --check "$(git merge-base main HEAD)" HEAD; }'

echo "== macOS"
step swift-build "swift build (debug)" bash -c "cd mac-native && swift build"
step swift-test "swift test" bash -c "cd mac-native && swift test"
[ -f "$LOG_DIR/swift-test.log" ] && grep -E "Executed [0-9]+ tests" "$LOG_DIR/swift-test.log" | tail -1 | sed 's/^[[:space:]]*/      /'
[ $QUICK -eq 0 ] && step swift-release "swift build -c release" bash -c "cd mac-native && swift build -c release"

echo "== Localizare (RO/EN/ES) și design"
step l10n "localizare: chei complete, specificatori identici" python3 scripts/check-l10n.py
step design-audit "design audit (fără datorie nouă față de baseline)" scripts/design-audit.sh

if [ $QUICK -eq 0 ]; then
    echo "== Windows"
    if command -v dotnet >/dev/null; then
        OUT=$(mktemp -d)
        step dotnet-build "dotnet build DataMover.Client (cross, fără rulare XAML)" \
            dotnet build windows-native/DataMover.Client/DataMover.Client.csproj -c Release -o "$OUT"
        rm -rf "$OUT"
        step dotnet-checks "verificări C# (motor, checkpoint, diagnostic, preflight, medii)" \
            dotnet run -c Release --project windows-native/DataMover.CoreChecks/DataMover.CoreChecks.csproj
        [ -f "$LOG_DIR/dotnet-checks.log" ] && tail -1 "$LOG_DIR/dotnet-checks.log" | sed 's/^/      /'
    else
        bad "dotnet lipsește — build Windows neverificat"
    fi
fi

if [ "${VOLUMES:-0}" -eq 1 ]; then
    echo "== Volume temporare (imagini de disc, șterse la final)"
    step volumes "disc plin + spațiu insuficient + exFAT" scripts/volume-fault-tests.sh
fi

if [ "${VM:-0}" -eq 1 ]; then
    echo "== Windows real (VM Parallels, fără interfață)"
    VMNAME="${DM_VM_NAME:-Windows 11 (1)}"
    if prlctl list 2>/dev/null | grep -q "running.*$VMNAME"; then
        WC="$HOME/Documents/dm-winchecks-preflight"
        rm -rf "$WC"
        step winchecks-publish "publicare WinChecks (win-x64)" dotnet publish windows-native/DataMover.WinChecks -c Release -r win-x64 --self-contained true -p:EnableWindowsTargeting=true -o "$WC"
        step winchecks "NTFS real: 2 copii, reluare, coliziuni, unitate lipsă, junction, Unicode, cale lungă, export" \
            prlctl exec "$VMNAME" --current-user cmd /c "Z:\\Documents\\dm-winchecks-preflight\\DataMover.WinChecks.exe"
        [ -f "$WC/winchecks-result.txt" ] && tail -1 "$WC/winchecks-result.txt" | sed 's/^/      /'
        rm -rf "$WC"
    else
        warn "VM '$VMNAME' nu rulează — verificările Windows reale nu s-au făcut"
    fi
fi

if [ $ONLINE -eq 1 ]; then
    echo "== Linkuri publice (HEAD, read-only)"
    # Cheia `windows` (updater Python vechi) e un BLOCAJ DE DISTRIBUȚIE cunoscut
    # cât timp dă 404 — raportată ca eșec, nu ascunsă (vezi PROJECT_STATE.md).
    while IFS=$'\t' read -r key u; do
        c=$(curl -sIL -o /dev/null -w "%{http_code}" "$u")
        if [ "$c" = "200" ]; then ok "$c [$key] $u"; else bad "$c [$key] $u"; fi
    done < <(python3 -c 'import json
for k,v in json.load(open("docs/update.json"))["download_url"].items(): print(f"{k}\t{v}")')
    for u in $(grep -oE 'https://github.com/gordasgdc/datamover/releases/latest/download/[^"]+' docs/index.html | sort -u); do
        c=$(curl -sIL -o /dev/null -w "%{http_code}" "$u")
        if [ "$c" = "200" ]; then ok "$c [site] $u"; else bad "$c [site] $u"; fi
    done
else
    warn "linkurile publice nu au fost verificate (rulează cu --online)"
fi

echo
echo "Loguri: $LOG_DIR"
if [ $FAIL -eq 0 ]; then echo "PREFLIGHT OK"; else echo "PREFLIGHT: $FAIL problemă(e)"; fi
[ $FAIL -eq 0 ]
