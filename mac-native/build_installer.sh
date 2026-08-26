#!/usr/bin/env bash
# Builds DataMover.app fresh (semnat + notarizat, daca certificatul e
# configurat — vezi build_app.sh), apoi il impacheteaza intr-un .pkg
# installer semnat cu Developer ID Installer + notarizat + stapled.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
PKG_ID="dev.gordas.datamover.installer"
APP_NAME="DataMover.app"
DIST_DIR="dist"
PAYLOAD_ROOT="$DIST_DIR/payload"
COMPONENT_PKG="$DIST_DIR/DataMover-component.pkg"
FINAL_PKG="$DIST_DIR/DataMover-$VERSION.pkg"

echo "==> Building app…"
./build_app.sh

rm -rf "$PAYLOAD_ROOT" "$COMPONENT_PKG" "$DIST_DIR/Distribution.xml" "$DIST_DIR/License.txt"
mkdir -p "$PAYLOAD_ROOT/Applications"
cp -R "$DIST_DIR/$APP_NAME" "$PAYLOAD_ROOT/Applications/$APP_NAME"

echo "==> Building component package…"
# --scripts: preinstall CURATA doar o instalare veche ramasa (pkill +
# rm -rf /Applications/DataMover.app). NU contine niciun hack de
# Gatekeeper/quarantine - pachetul e semnat + notarizat + stapled mai jos.
pkgbuild \
    --root "$PAYLOAD_ROOT" \
    --identifier "$PKG_ID" \
    --version "$VERSION" \
    --install-location "/" \
    --scripts "installer/scripts" \
    "$COMPONENT_PKG"

echo "==> Writing distribution definition…"
cat > "$DIST_DIR/Distribution.xml" << EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="1">
    <title>DataMover $VERSION</title>
    <license file="License.txt" mime-type="text/plain"/>
    <options customize="never" require-scripts="false" rootVolumeOnly="true"/>
    <domains enable_localSystem="true"/>
    <choices-outline>
        <line choice="default">
            <line choice="$PKG_ID"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="$PKG_ID" visible="false">
        <pkg-ref id="$PKG_ID"/>
    </choice>
    <pkg-ref id="$PKG_ID" version="$VERSION" onConclusion="none">DataMover-component.pkg</pkg-ref>
</installer-gui-script>
EOF

cp installer/License.txt "$DIST_DIR/License.txt"

echo "==> Building final installer package…"
productbuild \
    --distribution "$DIST_DIR/Distribution.xml" \
    --package-path "$DIST_DIR" \
    --resources "$DIST_DIR" \
    "$FINAL_PKG"

rm -rf "$PAYLOAD_ROOT" "$COMPONENT_PKG"

# Semnare + notarizare a .pkg-ului final, daca certificatul Installer e
# configurat (vezi codesigning/README.md) - altfel ramane nesemnat.
./codesigning/sign-and-notarize.sh pkg "$FINAL_PKG"

# A version-agnostic copy too — the landing page always links to this
# stable filename (releases/latest/download/DataMover.pkg).
cp "$FINAL_PKG" "$DIST_DIR/DataMover.pkg"

echo "==> Copying uninstaller (Dezinstalare_DataMover.command)…"
cp "Dezinstalare_DataMover.command" "$DIST_DIR/Dezinstalare_DataMover.command"
chmod +x "$DIST_DIR/Dezinstalare_DataMover.command"

echo "==> Building DataMover-Mac.zip (pkg + uninstaller + ghid)…"
ZIP_STAGE="$DIST_DIR/zip_stage"
rm -rf "$ZIP_STAGE"
mkdir -p "$ZIP_STAGE"
cp "$DIST_DIR/DataMover.pkg" "$ZIP_STAGE/"
cp "$DIST_DIR/Dezinstalare_DataMover.command" "$ZIP_STAGE/"
chmod +x "$ZIP_STAGE/Dezinstalare_DataMover.command"
# AUDIT 2026-08-26 (CLAUDE.md Partea 1, Regula 8/5): ghidul livrat era
# doar RO - EN/ES existau ca fisiere separate in docs/guides/ dar nu erau
# niciodata unite in arhiva finala. Unificate cu pypdf (acelasi tipar ca
# gdc-production-manager, vezi CLAUDE.md de acolo), RO->EN->ES intr-un
# singur PDF, ca sa respecte "3 fisiere strict" + multilingv.
python3 -c "
from pypdf import PdfWriter
w = PdfWriter()
for f in ['../docs/guides/DataMover_Ghid_RO.pdf', '../docs/guides/DataMover_Guide_EN.pdf', '../docs/guides/DataMover_Guia_ES.pdf']:
    w.append(f)
w.write('$ZIP_STAGE/Ghid-de-Utilizare.pdf')
" 2>/dev/null || cp "../docs/guides/DataMover_Ghid_RO.pdf" "$ZIP_STAGE/Ghid-de-Utilizare.pdf" 2>/dev/null || true
( cd "$ZIP_STAGE" && zip -q -r -y "../DataMover-Mac.zip" . )
rm -rf "$ZIP_STAGE"

echo "==> Done: $FINAL_PKG"
echo "==> Also: $DIST_DIR/DataMover.pkg, $DIST_DIR/Dezinstalare_DataMover.command, $DIST_DIR/DataMover-Mac.zip"
echo "    Upload DataMover-Mac.zip to the GitHub release (that's what the website links to)."
