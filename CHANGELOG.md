# Changelog — DataMover

## v2.11.0 — Flux profesional de offload, la nivel de platou (2026-09-03, paritate completă Mac/Windows)
Cea mai mare adăugare de la rescrierea nativă. Toate funcțiile de mai jos
există identic pe Mac și pe Windows.

**Predare către post-producție**
- **Fișier MHL (Media Hash List)** scris automat lângă datele copiate —
  certificatul de integritate pe care îl citesc Silverstack, YoYotta,
  ShotPut Pro, DaVinci Resolve și casele de post. Luni mai târziu, oricine
  poate re-verifica automat că fiecare fișier de pe NAS/LTO e bit-identic
  cu ce a ieșit din cameră în ziua filmării. Se poate opri din Setări.
- **Rapoarte brandate** — logo-ul firmei, Client, Cameră, Operator/DIT și
  Note de filmare apar în antetul raportului PDF. Câmpurile necompletate nu
  apar deloc.
- **Raport HTML nou**, alături de CSV și PDF: se deschide în orice browser,
  pe orice telefon, și poate fi trimis pe WhatsApp/email fără să-și piardă
  formatarea.

**Viteză și siguranță**
- **Verificare xxHash64** — noul model implicit, același folosit de
  ofloaderele profesionale. Aceeași siguranță practică la detectarea
  coruperii de date ca MD5, dar de câteva ori mai rapid: pe un card de
  sute de GB, verificarea e etapa care durează, nu copierea. MD5, SHA-1,
  SHA-256 și SHA-512 rămân disponibile.
- **Reîncercare automată a fișierelor eșuate**, la finalul transferului.
  Majoritatea eșecurilor de pe platou sunt trecătoare (card mișcat în
  cititor, cablu atins, disc extern adormit) — până acum rămâneau erori
  definitive în raport și trebuia reluat manual tot transferul. Fișierele
  recuperate apar explicit în rezumat, ca să știi că transferul a avut
  probleme, chiar dacă s-a terminat bine.
- **Verificare de spațiu liber înainte de start.** Un card de 512 GB
  pornit către un disc cu 80 GB liberi copia liniștit ore întregi și eșua
  abia la mijloc. Acum transferul nu mai pornește: vezi de cât spațiu e
  nevoie, cât e liber, și poți continua oricum dacă vrei.

**Flux de lucru nesupravegheat**
- **Coadă de carduri** — pui mai multe carduri la rând și se descarcă unul
  după altul, fiecare în propriul folder. La finalul unei zile cu 3 camere
  nu mai stai lângă laptop să pornești manual fiecare card.
- **Pornire automată la introducerea unui card** (opțional): cardul intră
  direct în coadă și descărcarea începe singură.
- **Ejectare automată a cardului la final** (opțional) — doar dacă
  transferul s-a terminat fără nicio eroare. Un card cu probleme nu se
  scoate niciodată automat.
- **Notificare de sistem la final**, pe lângă sunet — rămâne în Centrul de
  notificări până o citești, chiar dacă erai în altă cameră.

**Organizare**
- **Șablon liber pentru numele folderelor**, cu previzualizare live:
  `{data} {ora} {proiect} {card} {camera} {operator}`. Șablonul implicit
  produce exact numele de până acum, deci nimic nu se schimbă dacă nu vrei.
- **Recunoașterea cardurilor de cameră** — RED, ARRI, Sony XAVC/XDCAM,
  Panasonic P2/AVCHD, Canon, Blackmagic BRAW, carduri DCIM. Aplicația îți
  spune ce card a recunoscut și câte clipuri are, te avertizează dacă
  găsește fișiere de 0 octeți (clipuri incomplete) și — cel mai important —
  dacă ai selectat din greșeală un subfolder al cardului în loc de cardul
  întreg, caz în care s-ar pierde metadatele.


## v2.10.1 — Upload Cloud mult mai rapid (2026-08-30, paritate Mac/Windows)
Cerință reală, raportată de Cristi ("mi se pare exagerat de mult că durează
transferul"): urcarea Cloud (v2.8.0) pornea un proces `rclone` nou, separat,
pentru FIECARE fișier — overhead-ul de pornire domina timpul la multe
fișiere mici. Rescris: fișierele se acumulează într-un lot (25 fișiere sau
3 secunde, ce vine primul) și se urcă printr-un SINGUR proces
`rclone copy --files-from -`, cu flag-uri de performanță
(`--transfers 8 --checkers 16 --drive-chunk-size 64M --fast-list`).
- Măsurat direct: pe Google Drive, viteza per-fișier a crescut și mai mult
  (**~18x**) după configurarea unui client OAuth propriu pentru Google
  Drive în Master Control Studio Pro (vezi CHANGELOG-ul acelui repo) — cei
  doi factori (batching + client propriu) sunt independenți, ambii ajută.
- Pagina web (`docs/index.html`) — prețul fix (23 €) scos din text; suma
  exactă (poate include oferte temporare) apare doar în aplicație, la
  Activare, conform standardului de preț dinamic (Regula 27).

Format: fiecare intrare listează versiunea, platformele afectate, și — pentru
funcționalități noi — dacă are paritate completă Mac/Windows sau e "doar pe
o platformă, portare pe cealaltă e TODO".

## v2.10.0 — Mac: preț dinamic (Pricing Manager), fără recompilare (2026-08-30)
Cerință arhitecturală: o ofertă (Black Friday, Crăciun) necesita până acum
recompilarea + republicarea aplicației doar ca să schimbi o cifră. Acum
`ActivationSheet` citește prețul din `pricing.json` (publicat prin noul
panou „Prețuri & Oferte" din Furnizor, `gdc-plugin-manager-catalog-vendor`)
în loc de o valoare hardcodată:
- Preț de bază + program de oferte cu interval de timp, afișate automat
  („🔥 Black Friday -35%" + preț tăiat), cu countdown live opțional.
- Mesajul WhatsApp pre-completat folosește prețul curent, nu unul fix.
- **Fail-open**: fără conexiune, revine la prețul hardcodat din cod —
  niciodată un ecran gol/eronat.
- Windows (DataMover WPF) rămâne TODO pentru acest pilot — vezi Regula 27
  (CLAUDE.md) pentru planul de propagare pe restul ecosistemului.

## v2.9.0 — Plafon de 2 GB per transfer în versiunea de probă (2026-08-30, paritate Mac/Windows)
Cerință explicită a lui Cristi: testerii dezinstalează/reinstalează
aplicația repetat ca să resetez proba de 7 zile și să o folosească la
nesfârșit. Plafonul e legat STRICT de `isLicensed`/`IsLicensed`, nu de
zilele de probă rămase — dezinstalarea/reinstalarea resetează contorul de
zile, dar NU ridică niciodată plafonul; doar o licență activată reală o
face.
- Orice transfer a cărui dimensiune totală depășește 2 GB e blocat ÎNAINTE
  de a porni copierea (nu doar avertizat) dacă aplicația nu e licențiată —
  apare un dialog cu buton „Activează licența".
- Verificarea e pe dimensiunea TOTALĂ a transferului (suma tuturor
  fișierelor), nu per fișier — nu poate fi ocolită trimițând multe fișiere
  mici.
- **Găsit la implementare**: până acum, pe ambele platforme, nu exista
  NICIUN gating real după expirarea probei — `isUnlocked`/`IsUnlocked` era
  calculat dar nefolosit nicăieri pentru a bloca ceva; Start-ul funcționa
  identic indiferent de starea licenței. Plafonul de 2 GB e prima
  restricție reală introdusă vreodată în acest sens.

## v2.8.1 — Mac: diagnostic real pentru PDF-ul de raport lipsă (2026-08-30)
Raportat de Cristi: `offload_checkpoint.json` și CSV-ul se creau normal,
dar PDF-ul de raport lipsea complet, fără nicio indicație. Cauza: spre
deosebire de Windows (are deja fallback `offload_report_PDF_EROARE.txt`
din v2.7.0), Mac-ul înghițea tăcut orice eșec al `CGDataConsumer`/
`CGContext` (motive posibile: folder de destinație deconectat între timp,
disc plin, cale invalidă). Acum: motivul exact apare în feed-ul de
activitate ȘI într-un fișier `offload_report_PDF_EROARE.txt` lângă CSV,
la fel ca pe Windows — dacă problema reapare, mesajul spune direct de ce.

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
