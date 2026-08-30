# Changelog — DataMover

Format: fiecare intrare listează versiunea, platformele afectate, și — pentru
funcționalități noi — dacă are paritate completă Mac/Windows sau e "doar pe
o platformă, portare pe cealaltă e TODO".

## v2.8.0 — Destinație secundară Cloud, powered by Rclone (2026-08-30, paritate Mac/Windows)
Cerință explicită a lui Cristi: copierea locală (SSD/HDD/card) poate acum
urca simultan fiecare fișier și pe un cont Cloud, fără nicio "legătură"
separată de configurat — `rclone` ține toate conturile într-un singur
`rclone.conf` global, deja partajat cu Cloud Manager-ul din Master Control
Studio Pro (Mac/Windows).
- **Setări › Destinație secundară Cloud**: dropdown cu conturile deja
  configurate (`rclone listremotes`) + subfolder opțional pe cont.
  "Dezactivat" implicit — comportamentul existent rămâne neschimbat dacă
  nu se alege niciun cont.
- Fiecare fișier copiat local cu succes (OK/SARIT) se urcă automat, în
  fundal, imediat după verificare, printr-o coadă SERIALĂ per destinație
  (`CloudUploadQueue`) — evită mai multe procese `rclone` concurente pe
  aceeași bandă de rețea (Regula 21). Progresul apare linie cu linie în
  feed-ul de activitate deja existent.
- Profilele de transfer salvează acum și alegerea Cloud (cont + subfolder).
- Dacă `rclone` nu e instalat, secțiunea arată un avertisment cu
  îndrumare către Master Control Studio Pro (Dependențe), în loc de un
  dropdown gol care ar eșua tăcut.
- Implementare: `CloudSyncService.swift`/`.cs` (nou, ambele platforme),
  extins în `OffloadEngine.swift`/`.cs` (`DestinationJob.cloudUploadQueue`)
  și `TransferProfile`/`TransferProfileStore`.

## v2.7.2 — Windows WPF (2026-08-29)
- Fix: titlul ferestrei arăta static "DataMover 2.6.0" (neschimbat de la
  Etapa 2026-08-28 (2)), deși aplicația era deja la 2.7.1 — acum citește
  versiunea reală din `UpdateChecker.CurrentVersion`.
- Nou: selector Sistem/Luminos/Întunecat (Regula 18, lipsea complet pe
  Windows) — `ThemeSettings.cs`, persistat în `%AppData%\DataMover\theme.json`,
  aplicat instant prin `Wpf.Ui.Appearance.ApplicationThemeManager`, expus
  în fereastra Profil (secțiune nouă "Aspect").
- Fix: 2 fundaluri hardcodate `#1C1C1C` (tile-uri disc, panou dependințe)
  rămâneau negre și pe tema Luminos — înlocuite cu resursa de temă
  `ControlFillColorDefaultBrush`.
- Nou: panoul "Optiuni de copiere"/"I/O & Memorie"/"Profile de transfer"
  (mereu desfășurate, ocupau tot centrul ferestrei) consolidate într-un
  singur buton "Setări copiere" cu popover, parity vizual cu gear-icon-ul
  Mac v2.7.1.
- Nou: Manager Modular de Dependințe (Regula 4) — panoul static "toate
  prezente" din fereastra Profil e acum o listă reală (`SystemDependencyChecker.cs`),
  cu prima dependință verificată headless: Visual C++ Redistributable
  (necesar de SkiaSharp/QuestPDF pentru raportul PDF al transferurilor) —
  🔴 dacă lipsește, cu buton "Instalează" direct spre link-ul oficial
  Microsoft, plus buton "Reverifică". Punct roșu global lângă butonul
  Profil din footer.

## v2.5.5 (2026-08-26)
Versiune de test, fără schimbări funcționale — publicată doar ca țintă pentru validarea manuală a self-updater-ului nou din v2.5.4 (vezi mai jos). Confirmat: instalare + relansare automată, funcționează cap-coadă pe mașina reală.

## v2.5.4 (2026-08-26)
**Mac** — butonul de update descărca acum efectiv, în loc să deschidă browserul:
- Pana acum, "Descarcă" din alerta de update deschidea `github.com/.../releases/latest` în browser — userul trebuia să găsească singur fișierul și să-l instaleze manual. Windows (`core/updater.py`) avea deja o rețetă reală de self-update — portată acum 1:1 pe Mac (`SelfUpdater.swift`, nou): descarcă `.pkg`-ul, îl instalează prin promptul NATIV de parolă admin (`osascript ... with administrator privileges`), apoi aplicația se relansează singură.
- `release.sh` (nou, rădăcina repo-ului) — un singur punct de intrare pentru un release complet Mac+Windows, cu verificare independentă (`spctl`) că pachetul chiar e semnat+notarizat înainte de publicare, nu doar promisiunea scriptului de semnare.
- Site-ul (`docs/index.html`) verificat, era deja corect — link-uri directe de download, cu detecție de platformă.

## v2.5.3 (2026-08-26)
**Mac** — reparat un crash real, reprodus dintr-un raport de crash trimis:
- `copyFileCancelable` (motorul de copiere la offload) folosea `FileHandle.readData(ofLength:)`/`.write(_:)`, API-uri Objective-C legacy — la o eroare reală de I/O (card SD deconectat în mijlocul copierii, disc extern scos, disc plin, permisiune refuzată) acestea ridică o excepție Objective-C necapturabilă cu `do/catch` din Swift, în loc să arunce o eroare normală. Rezultat: `abort()`, toată aplicația moare, nu doar fișierul care a eșuat.
- Fix: `FileHandle.read(upToCount:)`/`.write(contentsOf:)`, variantele *throwing* (macOS 10.15.4+), în ambele locuri afectate (copiere + hash de verificare). Verificat prin reproducerea separată a aceluiași crash cu API-ul vechi, apoi confirmat că API-ul nou capturează aceeași eroare normal.

## v2.5.2 (2026-08-26)
**Windows** — fix bug real: `APP_VERSION` din `core/update_config.py` (sursa unică pentru versiunea raportată de aplicație pe Windows) era blocat la `2.3.2` din 21 august, deși release-urile publicate ajunseseră la `2.5.1` — exe-ul arăta mereu versiunea greșită în About și semnala etern "update disponibil", chiar și pe cel mai nou build descărcat.

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
