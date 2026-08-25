# Changelog — DataMover

Format: fiecare intrare listează versiunea, platformele afectate, și — pentru
funcționalități noi — dacă are paritate completă Mac/Windows sau e "doar pe
o platformă, portare pe cealaltă e TODO".

## v2.5.1 (2026-08-25)
**Mac** — schimbare majoră, urmare a auditului "Directivă Permanentă Supremă":
- **Semnare + notarizare Apple reală** pentru prima dată (`mac-native/codesigning/`, copiat din `cursorpro-gdc`) — anterior era semnat DOAR ad-hoc (`TeamIdentifier=not set`), motiv pentru care launcherul avea nevoie de `xattr -dr com.apple.quarantine` ca să treacă de Gatekeeper.
- Eliminat launcherul `Instaleaza_DataMover.command` (hack de quarantine) — înlocuit cu un `.pkg` semnat+notarizat+stapled, care trece nativ de Gatekeeper.
- Adăugat `Dezinstalare_DataMover.command`, inclus automat în fiecare `DataMover-Mac.zip`.
- Curățare de versiune veche mutată în `installer/scripts/preinstall` (fără hack-uri).
- Versiune vizibilă acum în UI (`metaBar`, lângă butonul de Help) — lipsea complet înainte.
- Job-ul `build-mac` din `.github/workflows/release.yml` ELIMINAT — Mac se compilează local de-acum (certificatul e în Keychain-ul local, nu în secretele CI), la fel ca `gdc-plugin-manager`/`cursorpro-gdc`.

**Windows** — TODO paritate reală (rulează încă pe codebase-ul Python vechi, nu pe rescrierea nativă):
- `installer.iss` era rămas la `2.4.0` deconectat de release-urile reale (`v2.5.0` includea deja Mac-ul nou) — sincronizat acum la `2.5.1`.
- Uninstaller: Inno Setup generează automat unul complet (Add/Remove Programs) — verificat prezent (`UninstallDisplayIcon` în `installer.iss`), nu a fost nevoie de un script separat.
- `docs/update.json` era rămas la `2.3.2` (3 versiuni în urmă) — sincronizat la `2.5.1`, URL-uri de download corectate.

## Anterior (2026-08-13 – 2026-08-24)
Vezi `REFACTOR_PLAN.md` și `git log` pentru istoricul rescrierii native Mac
(SwiftUI, înlocuind treptat aplicația Python/tkinter) și evoluția motorului
de copiere/verificare (`core/offload_engine.py`).
