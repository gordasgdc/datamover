#!/bin/bash
# Teste pe volume REALE, dar temporare și izolate: două imagini de disc create
# în $TMPDIR, montate fără să apară în Finder, demontate și șterse la final
# (și la eroare). Nu atinge niciun disc existent.
#   APFS ~20 MB  -> disc plin în timpul copierii / spațiu insuficient la pornire
#   exFAT 200 MB -> sistemul de fișiere tipic al cardurilor
set -euo pipefail
cd "$(dirname "$0")/../mac-native"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/dm-volumes.XXXXXX")
MOUNTS=()
cleanup() {
    for m in "${MOUNTS[@]:-}"; do [ -n "$m" ] && hdiutil detach "$m" -force -quiet 2>/dev/null || true; done
    rm -rf "$WORK"
}
trap cleanup EXIT
mk() { # nume, marime, fs
    hdiutil create -quiet -size "$2" -fs "$3" -volname "$1" -layout NONE "$WORK/$1.dmg" >/dev/null
    local mp="$WORK/mnt-$1"; mkdir -p "$mp"
    hdiutil attach -quiet -nobrowse -noautoopen -mountpoint "$mp" "$WORK/$1.dmg"
    MOUNTS+=("$mp"); LAST="$mp"
}
mk DMSMALL 20m APFS; SMALL="$LAST"
mk DMEXFAT 200m ExFAT; EXFAT="$LAST"
echo "Volume temporare: $SMALL (APFS) · $EXFAT (exFAT)"
DM_SMALL_VOL="$SMALL" DM_EXFAT_VOL="$EXFAT" swift test --filter VolumeFaultTests 2>&1 | grep -E "Test Case .*(passed|failed|skipped)|error:|Executed" | sed 's/^/  /'
