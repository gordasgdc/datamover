#!/bin/bash
# design-audit.sh — gardă „ratchet” pentru design system-ul Mac (DesignSystem/DMTheme.swift).
# Numără valorile vizuale LITERALE per fișier (culori, mărimi de font, spațieri,
# raze, opacități, lățimi fixe). Regula:
#   - fișier NOU (absent din baseline) → 0 literale permise;
#   - fișier vechi → numărul nu are voie să crească față de baseline.
# Baseline: scripts/design-audit-baseline.txt (datoria veche, explicită).
# Scade → `scripts/design-audit.sh --update` fixează noul prag (niciodată în sus fără motiv).
# DesignSystem/ e exclus: acolo trăiesc valorile tokenurilor.
set -uo pipefail
cd "$(dirname "$0")/.."
SRC=mac-native/Sources/DataMoverMac
BASE=scripts/design-audit-baseline.txt
RX='\.system\(size: [0-9][0-9.]*|Color\((red|white|srgbRed|hue):|NSColor\((white|srgbRed|red|calibratedRed):|\bColor\.(red|orange|green|blue|yellow|purple|pink|black|white|gray)\b|foregroundStyle\(\.(green|orange|red|blue|black|white)\)|\.opacity\(0?\.[0-9]+\)|\.padding\((\.[a-zA-Z]+, )?[0-9][0-9.]*\)|spacing: [1-9][0-9.]*|cornerRadius: ?[0-9][0-9.]*|\.frame\((minWidth|maxWidth|width|height|minHeight|idealWidth): [0-9][0-9.]*'
count() { grep -oE "$RX" "$1" 2>/dev/null | wc -l | tr -d ' '; }
FAIL=0; NEW=""; TOTAL=0
while IFS= read -r f; do
    rel=${f#"$SRC/"}
    n=$(count "$f"); TOTAL=$((TOTAL+n))
    [ "$n" -gt 0 ] && NEW+="$rel $n"$'\n'
    b=$(awk -v k="$rel" '$1==k {print $2}' "$BASE" 2>/dev/null)
    if [ -z "$b" ]; then
        if [ "$n" -gt 0 ]; then echo "✗ $rel: $n literale într-un fișier fără datorie în baseline — folosește DM.*"; FAIL=1; fi
    elif [ "$n" -gt "$b" ]; then
        echo "✗ $rel: $n > baseline $b — folosește DM.* în codul nou"; FAIL=1
    elif [ "$n" -lt "$b" ]; then
        echo "↓ $rel: $n < baseline $b (rulează --update ca să fixezi progresul)"
    fi
done < <(find "$SRC" -name '*.swift' -not -path '*/DesignSystem/*' | sort)
BTOTAL=$(awk '{s+=$2} END {print s+0}' "$BASE" 2>/dev/null)
echo "literale vizuale în afara DesignSystem: $TOTAL (baseline $BTOTAL)"
if [ "${1:-}" = "--update" ]; then printf "%s" "$NEW" > "$BASE"; echo "baseline actualizat"; exit 0; fi
exit $FAIL
