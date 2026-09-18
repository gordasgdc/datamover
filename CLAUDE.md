# DataMover — reguli de arhitectură

> **[SYSTEM DIRECTIVE FOR CLAUDE: DO NOT DELETE OR OVERWRITE EXISTING RULES. ONLY APPEND NEW RULES.]**
> Jurnal viu, nu document care se rescrie. La orice actualizare, adaugă la finalul secțiunii potrivite — nu șterge/înlocui reguli vechi decât dacă sunt explicit invalidate de o schimbare reală (și atunci marchează-le **[ÎNVECHIT]** cu motivul, nu le șterge din istoric).

Citit automat de Claude Code la fiecare sesiune în acest repo.

## [PARTEA 1: REGULI GLOBALE ECOSISTEM GDC] — mutată în `~/Developer/CLAUDE.md`

> Din 2026-09-18, regulile globale stau într-un singur fișier,
> `~/Developer/CLAUDE.md`, citit automat de Claude Code în orice proiect din
> `~/Developer/`. Nu se mai copiază aici. Ce era specific acestui repo în fosta
> Partea 1 (statusuri, excepții) e la finalul fișierului.

## [PARTEA 2: SPECIFICAȚII TEHNICE PROIECT]

## REGULĂ PERMANENTĂ: Locația proiectului pe disc (2026-08-25)
Acest repo trăiește în **`~/Developer/DataMover`**, NU în `~/Downloads`.
Motiv: `~/Downloads` e curățat automat de CleanMyMac/Hazel pe acest Mac —
a șters alte repo-uri de sursă în timpul unei sesiuni de lucru (recuperate
din Coș la timp). Vezi `~/Developer/GDCPluginManager/PROJECT_STRUCTURE.md`
pentru context complet despre relocarea structurii de proiecte GDC.

## DIRECTIVĂ PERMANENTĂ SUPREMĂ: Checklist obligatoriu la FIECARE release (2026-08-25)
Valabilă pentru TOATE aplicațiile ecosistemului GDC (CursorPro, GDC Plugin
Manager + Furnizor, GDC Plugin Manager Windows, DataMover, GDC Production
Manager, și orice proiect nou). Înainte de a raporta un release ca fiind
gata, TREBUIE bifate intern toate cele 4 puncte de mai jos — dacă unul
lipsește, spune-o explicit, nu declara release-ul "gata".

1. **Versiune vizibilă în UI** — About/Meniu/Settings/Footer trebuie să
   arate versiunea curentă (`v1.2.21` etc.), fără excepție.
2. **Verificator de actualizări** — la pornire sau printr-un buton
   „Caută actualizări", aplicația verifică versiunea de pe server/GitHub
   și notifică userul când există un release mai nou.
3. **Pachetul standard de release** — orice arhivă livrată clientului
   conține FĂRĂ EXCEPȚIE:
   - executabilul/installer-ul semnat + notarizat,
   - `Dezinstalare_[NumeAplicație].command` (dezinstalare completă:
     procese, permisiuni TCC, toate fișierele din `~/Library/`),
   - un ghid/PDF de instrucțiuni.
4. **Sincronizare site ↔ GitHub Releases** — linkurile de download de pe
   site trebuie să pointeze mereu la `releases/latest/download/...`
   (HTTP 200 verificat, nu presupus) și să menționeze numărul ultimei
   versiuni.

## Audit 2026-08-25 — găsit și reparat
- **Mac era semnat DOAR ad-hoc** (`TeamIdentifier=not set`), fără
  certificat Apple real — motiv pentru care exista un launcher cu
  `xattr -dr com.apple.quarantine`. Fix real (nu doar eliminarea
  hack-ului): `mac-native/codesigning/` copiat din `cursorpro-gdc`,
  `build_app.sh`/`build_installer.sh` semnează acum cu Developer ID
  Application/Installer + notarizează + staplează, dacă
  `APPLE_SIGN_IDENTITY_APP` e setat (vezi `~/.zshrc`, la fel ca celelalte
  repo-uri GDC). Job-ul `build-mac` din CI a fost eliminat — Mac se
  compilează LOCAL de-acum (certificatul e în Keychain local), Windows
  rămâne CI. Vezi `CHANGELOG.md` v2.5.1 pentru detalii complete.
- **Windows rulează încă pe codebase-ul Python vechi** (`main.py`,
  `core/`, `ui/windows/`), NU pe rescrierea nativă SwiftUI — rescrierea
  există doar pentru Mac (`mac-native/`). Portarea nativă pe Windows
  rămâne TODO real, nemenționat explicit până acum.
- `installer.iss` (Windows) și `docs/update.json` erau amândouă
  desincronizate de versiunea reală lansată (`2.4.0`/`2.3.2` vs `2.5.0`
  live) — sincronizate la `2.5.1`.
- Uninstaller Windows: Inno Setup generează unul automat (Add/Remove
  Programs) — deja conform, nu a fost nevoie de un script nou.

## Audit 2026-08-26 (2) — flux de release optimizat + auto-update Mac reparat

**1. `release.sh` (nou, rădăcina repo-ului) — un singur punct de intrare pentru un release complet.**
Motiv: fluxul documentat mai sus ("1. build local Mac, 2. push tag, 3. `gh release upload` manual") a fost urmat pas-cu-pas la lansarea `v2.5.3` — și a eșuat o dată în mijloc: `zsh -lc` (login shell) NU citește `~/.zshrc` (doar shell-urile INTERACTIVE îl citesc), deci `APPLE_SIGN_IDENTITY_APP` a ieșit nesetată și `build_installer.sh` a căzut TĂCUT pe semnare ad-hoc — exact regresia pe care auditul de mai sus o documentase deja ca reparată. A fost prinsă citind manual log-ul, înainte de upload — un flux automat trebuie s-o prindă singur.

`./release.sh <versiune> "<descriere>"` face, în ordine: (1) bump în cele patru locuri sincrone + verificare hard că toate patru chiar au ajuns la versiunea cerută; (2) build Mac cu `zsh -ic` (interactiv, nu login) ca să citească real `~/.zshrc`; (3) **verificare independentă cu `spctl`** că pachetul chiar e „Notarized Developer ID" — dacă nu, oprește tot, nu publică nimic nesemnat; (4) commit + push; (5) tag + push, așteaptă CI Windows; (6) urcă artefactele Mac deja verificate; (7) verificare finală că `releases/latest/download/...` și API-ul de update chiar rezolvă la tag-ul nou.

**WARNING**: NU s-a modificat `mac-native/codesigning/sign-and-notarize.sh` (modulul comun, copiat neschimbat în toate repo-urile GDC) — el cade intenționat tăcut pe nesemnat când certificatul nu există încă (bring-up timpuriu). Poarta de verificare stă în `release.sh`, specific acestui proiect, care știe că semnarea reală e deja obligatorie aici.

**2. Butonul de update Mac deschidea browserul în loc să descarce — reparat (`SelfUpdater.swift`, nou).**
Semnalat direct: *"Când apare actualizare și îi dai actualizare, mă trimite la GitHub... ar trebui să se descarce automat"*. Cauza: `UpdateChecker.presentResult` chema `NSWorkspace.shared.open(releasesPageURL)` — deschidea pagina web, nu descărca nimic. Windows (`core/updater.py`) avea deja o rețetă reală și funcțională de self-update (descarcă `.pkg`/`.exe`, instalează, relansează) — Mac-ul nativ (SwiftUI) nu o avea deloc.

Fix: `SelfUpdater.swift` portează 1:1 rețeta din `updater.py` — descarcă `.pkg`-ul (`URLSession.download`), apoi îl instalează prin promptul NATIV de parolă admin (`osascript ... with administrator privileges`, niciodată `sudo` interactiv sau Terminal), la fel ca elevarea OFX din `gdc-plugin-manager`. `UpdateChecker` citește acum asset-ul `.pkg` direct din răspunsul GitHub API (numele stabil `DataMover.pkg`, publicat de `release.sh` la fiecare lansare) — pagina web rămâne doar fallback, pentru un release incomplet.

Verificat end-to-end (script Swift separat, nu doar citire de cod): API-ul real → găsește `DataMover.pkg` → rezolvă URL-ul de download → **descarcă efectiv** fișierul cu aceeași funcție din `SelfUpdater` → fișierul primit e un `.pkg` valid (magic bytes `xar!`), dimensiune identică cu originalul.

**WARNING — ce NU s-a putut verifica automat**: pasul de instalare (promptul de parolă admin, `installer -pkg ... -target /`, relansarea aplicației) cere interacțiune fizică reală cu fereastra de sistem — Claude nu poate introduce o parolă. Verificat automat doar până la "pachetul e descărcat și integru pe disc". **Cristi trebuie să confirme manual, o singură dată, că instalarea + relansarea chiar funcționează**, înainte ca fluxul să fie considerat complet dovedit.

**[CONFIRMAT 2026-08-26, testat manual de Cristi pe mașina reală]** Fluxul complet a fost validat cap-coadă: instalat `v2.5.3` (fără fix), deschis „Caută actualizări" → a arătat corect vechiul buton „Descarcă" (comportament AȘTEPTAT — acel binar e compilat dinainte de fix, nu are cum să se comporte altfel). Apoi instalat `v2.5.4` (are `SelfUpdater`) peste el, s-a publicat `v2.5.5` doar ca țintă de test, verificat din aplicație: alerta a arătat corect „Descarcă și instalează", a descărcat, a cerut parola de administrator, a instalat și s-a relansat singură pe `v2.5.5`. **Fluxul e complet dovedit, nu doar verificat automat.**

**WARNING — implicație practică pentru anunțarea clienților**: self-update-ul NU se poate „auto-repara" pentru userii care au deja o versiune ≤ `2.5.3` instalată — acele binare pur și simplu nu conțin codul `SelfUpdater`, deci butonul lor din „Caută actualizări" va deschide mereu browserul, indiferent cât de nouă e versiunea de pe GitHub. E o problemă de bootstrap, nu un bug: fix-ul ajută abia din momentul în care cineva rulează un build care-l conține. Userii pe `2.5.4`+ nu mai au nevoie să viziteze site-ul — le ajunge „Caută actualizări" din aplicație.

**3. Site-ul (`docs/index.html`) verificat, deja corect — nimic de reparat.** `initDirectDownload()` folosește deja `releases/latest/download/...` cu detecție de platformă (nu link generic către pagina de Releases). Verificat live: ambele fișiere HTTP 200, rezolvă la `v2.5.3`.

## Etapa 2026-08-28 — Setari I/O granulare, Pauza/Reluare, deduplicare, Istoric extins, Profile de transfer (Mac)

Cerinta lui Cristi, dupa un build local de test facut chiar de el pe versiunea cu fix-ul de memorie (etapa anterioara): cinci functionalitati noi, aplicate momentan pe **Mac (mac-native/)** — Windows/Python (`core/`, `ui/windows/`) ramane la fix-ul de memorie din etapa precedenta, portarea acestor 5 puncte pe Windows e TODO real, nemenționat ca "gata" pana nu se face.

1. **Setari RAM & Buffer granulare + preset-uri + afisare live.** `IOSettings.chunkSizeChoicesMB` extins la `[1,2,4,8,16,32,64,128]` MB, `ramLimitChoicesMB` la `[0,512,1024,2048,4096,8192,16384,32768,65536]` MB (pana la 64 GB). `IOPerformancePreset.all` (Eco/Standard/High Performance/Extreme) seteaza simultan buffer+RAM dintr-un click, ramanand ajustabile manual dupa. Popover-ul de Setari arata acum aceste trepte (formatate "GB" peste 1024 MB, nu "65536 MB"), iar footer-ul, cat timp ruleaza un transfer, arata live "Buffer Alocat: X | Utilizat: Y" (`OffloadRunner.bufferAllocatedText`/`memoryUsedText`, actualizate la fiecare `advance()` din `IOSettings.currentResidentMemoryBytes()`).

2. **Deduplicare la pornire + "Completeaza/Reia".** Inainte de `start()`, `ContentView.attemptStart()` verifica prin `OffloadRunner.existingNonEmptyDestinations(destinations:folderName:)` daca folderul tinta exista deja NEVID la vreo destinatie (ignorand fisiere proprii de raport/checkpoint) — daca da, arata un `confirmationDialog` cu 3 optiuni: **Completeaza/Reia** (`resume: true` pe folderul existent), **Creeaza folder nou** (`OffloadRunner.freeFolderName` gaseste automat " (2)", " (3)"...), **Suprascrie complet** (`clearExistingFolders` sterge continutul, apoi porneste curat). "Completeaza/Reia" a fost intarit sa functioneze si FARA checkpoint (nu doar la o reluare normala dupa Anuleaza): `DestinationJob.run()`, cand `resume==true`, verifica acum fisierul de la destinatie inainte sa-l recopieze — daca marimea coincide cu sursa, il verifica prin hash (modelul de verificare ales) si il numara ca deja transferat corect daca se potriveste, altfel il recopiaza normal. Acopera exact cazul cerut: sistemul se inchide neasteptat FARA sa apuce sa scrie un checkpoint, la o noua pornire reluarea tot functioneaza corect prin verificare directa marime+hash.

3. **Pauza/Continua.** `PauseToken` (nou, in `OffloadEngine.swift`) — reversibil, spre deosebire de `CancelToken`: `DestinationJob.run()` verifica `pause.isPaused` INTRE fisiere (fisierul curent isi termina copierea/verificarea, nu se intrerupe la mijloc), blocand thread-ul job-ului cu `waitWhilePaused(cancel:)` pana la `resume()` sau Anulare. Buton nou in footer, langa Anuleaza, vizibil doar cat ruleaza un transfer (`OffloadRunner.togglePause()`).

4. **Istoric extins + deschidere directa.** `HistoryEntry` capata `sourcePaths`/`destinationPaths`/`destinationTargetPaths` (cai complete, nu doar nume scurte de afisare — `decodeIfPresent` pastreaza compatibilitatea cu istoricul salvat anterior, fara aceste campuri). `HistoryView` arata acum sursa si destinatia complete pe randuri separate, plus doua butoane noi per sesiune: "Deschide sursa"/"Deschide destinatia" (`NSWorkspace.selectFile(inFileViewerRootedAtPath:)`, deschide radacina REALA creata — `destinationPath + folderName`, nu discul intreg).

5. **Profile de transfer.** `TransferProfile` (nou, `TransferProfile.swift`) — struct Codable cu nume + cai sursa/destinatie + model de verificare + excluderi + buffer/RAM alese, persistat prin `TransferProfileStore` (JSON in Application Support, acelasi tipar ca `HistoryStore`). Sectiune noua in popover-ul de Setari: listeaza profilele salvate cu butoane Incarca/Sterge, plus un buton "+" care cere un nume si salveaza configuratia curenta completa (inclusiv treapta de buffer/RAM, nu doar cai/model ca "presetarile" vechi din Windows).

**Verificare**: `swift build` (debug) trece curat dupa fiecare pas de mai sus - fara erori de compilare. **Nu s-a facut inca un test manual real** al celor 5 fluxuri (Pauza efectiv opreste/reia copierea unui fisier mare, dialogul de duplicate apare corect la o destinatie cu fisiere existente, profilul salvat chiar se reincarca identic) — Cristi urmeaza sa le testeze pe build-ul local inainte de a cere un release semnat/notarizat.

**Rebuild local rapid** (fara semnare/notarizare, pentru testare): `cd mac-native && swift build && .build/debug/DataMoverMac`. **Build complet, .app impachetat** (semnat daca certificatul e in Keychain, altfel ad-hoc): `cd mac-native && ./build_app.sh`.

## Etapa 2026-08-28 (2) — Client Windows nou, WPF + Wpf.Ui (rescriere de la zero)

Cerinta explicita a lui Cristi, dupa ce a vazut design-ul mult mai modern
al variantei Mac (SwiftUI) fata de clientul Windows existent (Python/
Tkinter, "design cam foarte primitiv"): o rescriere completa a clientului
Windows, de la Python/Tkinter la **WPF (.NET 8) + Wpf.Ui** (Fluent Design),
acelasi tipar deja folosit de `GDCVaultWin`/`GDCPluginManagerWin` in
ecosistem. Discutat explicit cu Cristi: viteza de COPIERE nu se schimba
(ambele limbaje fac acelasi apel de sistem, disc-ul e limita reala) - ce
se castiga e responsivitate UI, memorie/pornire mai buna, consistenta cu
restul ecosistemului.

**Locatie**: `windows-native/` (nou, paralel cu `mac-native/`) - NU
inlocuieste inca `ui/windows/app.py`/`core/` (Python) - cele doua clienti
Windows coexista pana cand cel nou e testat real si confirmat de Cristi,
la fel cum s-a intamplat cu `mac-native/` vs `ui/mac/app.py` pe Mac.

**Structura** (2 proiecte, `dotnet build` verificat cu succes de pe Mac -
inclusiv compilare XAML->BAML reala, nu doar C#):
- `DataMover.Core` (`net8.0-windows`, `EnableWindowsTargeting`) - port 1:1
  al motorului Python/Swift: `Models/FileEntry.cs` (FileEntry/ReportRow/
  DestinationResult), `Services/OffloadEngine.cs` (CancelToken, PauseToken,
  FileScanner, DestinationJob - copiere in bucati configurabile,
  verificare MD5/SHA1/SHA256/SHA512/marime, checkpoint/reluare, raport CSV
  scris INCREMENTAL - Regula 21), `Services/IOSettings.cs` (trepte
  granulate identice cu Mac/Python + preset-uri Eco/Standard/High/Extreme +
  citire memorie proces via `Process.WorkingSet64`), `Services/
  HistoryStore.cs` + `Services/TransferProfileStore.cs` (JSON in
  `%AppData%\DataMover\`, acelasi tipar ca HistoryStore.swift/
  TransferProfile.swift), `Services/OffloadRunner.cs` (orchestrare
  paralela pe `Task.Run`, `INotifyPropertyChanged` pentru binding WPF -
  include deduplicarea date-independenta: `FindExistingFolderName`/
  `FolderHasRealFiles`/`FreeFolderName`/`ClearExistingFolders`, port 1:1 al
  fix-ului de pe Mac).
- `DataMover.Client` (`WinExe`, `Wpf.Ui` 3.0.5) - `MainWindow.xaml`
  (`ui:FluentWindow` + `ui:TitleBar` OBLIGATORIU - fara el fereastra ramane
  fixa, bug deja documentat pe GDCVaultWin; layout in 3 coloane Surse |
  centru (proiect/card, optiuni, I/O & Memorie cu preset-uri, profile,
  feed de activitate stil terminal) | Destinatii, footer cu progres/
  Start/Pauza/Anuleaza/Istoric), `DuplicateDialog.xaml` (Reia/Folder nou/
  Suprascrie - port 1:1 al dialogului Mac), `HistoryWindow.xaml` (istoric
  extins cu deschidere directa in Explorer per sursa/destinatie).

**Ce e deja functional** (cele 5 cerinte din etapele anterioare, acum si
pe Windows, in noul client): setari I/O granulare + preset-uri + afisare
live Buffer Alocat/Utilizat; deduplicare la Start cu cele 3 optiuni;
Pauza/Continua fara pierdere de progres; istoric extins cu deschidere
Explorer; profile de transfer complete (cai + model + buffer/RAM).

**TODO real, NU e gata de distribuit inca** (spus explicit, nu ascuns):
1. **Niciun test real pe Windows** - doar `dotnet build` de pe Mac (verifica
   C# + XAML->BAML, NU comportamentul la runtime: drag-uri, ferestre,
   dialoguri native Windows).
2. **Licentiere lipsa** - LicenseCore/MachineID (Regula 3) nu a fost inca
   portat in acest client nou; ruleaza momentan fara gating de licenta.
3. **Self-Updater lipsa** (Regula 20) - de portat dupa modelul
   `SelfUpdater.cs` din GDCVaultWin/GDCPluginManagerWin.
4. **Fara installer Inno Setup** inca pentru acest client nou (cel vechi,
   Python/PyInstaller, ramane `installer.iss` existent - un installer nou
   trebuie scris separat pentru output-ul `dotnet publish` al acestui
   proiect, dupa modelul GDCVaultWin).
5. **Fara raport PDF** - CSV-ul e complet (streaming, Regula 21), dar
   echivalentul `pdf_report.py`/`writePDFReport` (Mac) nu a fost portat -
   ar necesita o biblioteca PDF pentru .NET (ex. QuestPDF) sau generare
   manuala prin `System.Printing`/`System.Windows.Documents`.
6. **Fara drag&drop de discuri** ca pe Mac (grid cu tile-uri de volume,
   drag manual peste Surse/Destinatii) - v1 foloseste simplu "Adauga
   sursa/destinatie..." cu `OpenFolderDialog`, ca varianta Python veche.
7. **Versiune sincronizata la 2.6.0** in `.csproj` (Regula 14) - dar acest
   client NU e inca livrat clientilor, deci Regula 17 (nume cu versiune)
   nu se aplica pana la primul release real al lui.

**Nu declara acest client "gata" pana cand Cristi nu-l testeaza REAL pe o
masina Windows** - vezi WARNING-ul standard din Regula 20/celelalte etape:
Claude nu poate verifica interactiuni native Windows de pe Mac.

## Etapa 2026-08-28 (3) — 3 bug-uri reale gasite la primul test pe Windows real (Parallels)

Primul test real al clientului WPF (`windows-native/`) pe Windows (Parallels,
nu doar `dotnet build` de pe Mac) - confirmat FUNCTIONAL end-to-end
(11 fisiere OK, verificat cu screenshot-uri reale). Cristi a gasit 3
lipsuri, toate reparate in aceeasi sesiune:

1. **Fara "Deschide destinatia" la final.** Buton nou in footer
   (`OpenDestinationButton`), aparut doar dupa un transfer finalizat -
   plus un checkbox "Deschide automat destinatia la final"
   (`AutoOpenDestCheck`), la fel ca `autoOpenDestFolder` (Mac). Detectat
   prin tranzitia `IsRunning: true -> false` in `RefreshUiFromRunner`.
2. **Fara drag&drop din Explorer.** `AllowDrop="True"` + `DragOver`/`Drop`
   pe panourile SURSE/DESTINATII (atat pe `ui:CardExpander` cat si pe
   `ui:ListView` din interior, ca dropul sa functioneze oriunde in caseta,
   nu doar exact pe lista). Destinatiile accepta doar foldere (nu fisiere
   individuale, spre deosebire de surse).
3. **Fara detectare de discuri/carduri.** Lipsea complet echivalentul
   grid-ului de discuri de pe Mac (`VolumeInfo.swift`) - Windows nu arata
   NIMIC. Panou nou "DISCURI DETECTATE" (sus, full-width, `DriveInfo.
   GetDrives()` filtrat pe `IsReady`), reimprospatat automat la 4 secunde
   (`_drivesTimer`), cu buton "+ Sursa"/"+ Destinatie" per disc.

Verificat: `dotnet build` curat (C# + XAML->BAML) dupa toate cele 3
fix-uri. Ramane de retestat REAL pe Windows (Parallels) inainte de a
declara aceasta etapa completa - vezi WARNING standard.

**[CONFIRMAT 2026-08-28]** Retestat de Cristi pe Windows real: cele 3
fix-uri de mai sus functioneaza. Drag&drop a parut initial tot nefunctional
- cauza reala gasita: Cristi rula `dotnet run` dintr-un PowerShell
**elevat** ("Run as Administrator"), in timp ce Explorer.exe (sursa
drag-ului) rula ca user normal - Windows blocheaza silentios drag&drop
intre procese cu nivele de integritate/privilegii diferite (UIPI). Fix:
niciunul in cod - doar rulat din PowerShell normal. **Regula practica
noua**: orice test manual de drag&drop pe Windows trebuie facut dintr-un
terminal NEelevat, altfel pare bug de cod cand nu e.

## Etapa 2026-08-28 (4) — Raport PDF, iconite reale de disc, Versiune/Update/Self-Updater, Profil+Licentiere+Supabase, Panou dependinte, layout responsiv (Windows WPF)

Cerinta lui Cristi dupa retestarea de mai sus, in doua runde: (1) raport
PDF lipsa + iconite de disc "ca in Windows"; (2) dupa observatia ca
lipsesc complet versiune/update/auto-update/profil-HWID-email/indicator
dependinte, a ales explicit sa implementez toate patru deodata.

**1. Raport PDF (`DataMover.Core/Services/PdfReport.cs`, nou).** Lipsea
complet in clientul WPF (CSV/JSON existau, PDF nu fusese portat - vezi
TODO din etapa (2)). Foloseste **QuestPDF** (licenta Community, gratuita
pentru acest proiect - .NET nu are un echivalent nativ al `reportlab`).
Port al `pdf_report.py`: antet cu destinatie/folder/model verificare/
durata, sumar OK/Sarite/Probleme, tabel cu esantionul plafonat
(`_sampleRows`, `PdfSampleLimit=500`, Regula 21 - toate erorile incluse
oricum), nota de trunchiere daca esantionul nu acopera tot transferul.
`DestinationJob.Run()` cheama `WritePdf()` dupa inchiderea CSV-ului;
esec de generare PDF nu opreste transferul (doar logheaza in activitate).

**2. Iconite REALE de disc (`ShellIcon.cs`, nou, `DataMover.Client`).**
Cerut explicit: "sa apara imaginea, iconitele, simbolurile de la hard
disk-uri, asa cum sunt prezentate in Windows" - nu o iconita desenata de
noi, ci EXACT cea pe care o arata Explorer. `SHGetFileInfo` (Shell32,
P/Invoke) + `Imaging.CreateBitmapSourceFromHIcon` (fara dependinta
System.Drawing). `DriveTile.IconSource` nou, populat in `RefreshDrives()`,
afisat in tile-ul din panoul "DISCURI DETECTATE".

**3. Versiune vizibila + Update Checker + Self-Updater.** Lipseau
COMPLET pe acest client (semnalat de Cristi: "aici nu vad numarul de
versiune, update, auto update, actualizari"). `DataMover.Core/Services/
UpdateChecker.cs` (nou) - citeste `docs/update.json` (ACELASI fisier
folosit de Mac/Python, nu un API GitHub separat - vezi
`core/update_config.py`), compara versiunea, expune
`AvailableVersion`/`Changes`/`Mandatory`. `MainWindow` arata acum
`VersionText` in footer si verifica automat la lansare (`respectDismissal:
true`) + manual din footer/Profil (`respectDismissal: false`).

**WARNING arhitectural, NU o omisiune**: clientul WPF inca NU are
installer Inno Setup (TODO separat, nemodificat), deci self-update-ul nu
poate folosi reteta "descarca .exe, lanseaza-l" ca GDCVaultWin.
`SelfUpdater.cs` (nou, `DataMover.Client`) porteaza in schimb reteta deja
functionala din `core/updater.py` (clientul Python vechi): descarca o
arhiva `.zip`, extrage `DataMover.exe`, si il inlocuieste pe cel curent
printr-un script `.bat` auxiliar care asteapta (in bucla) ca procesul
curent sa elibereze fisierul, apoi relanseaza aplicatia. Citeste un camp
JSON NOU, optional, `download_url.windows_wpf` din `update.json` - campul
`windows` existent tinteste inca arhiva clientului Python vechi si NU
trebuie folosit pentru acest client (l-ar inlocui cu binarul gresit).
**`docs/update.json` NU are inca acest camp populat** (nicio arhiva reala
a clientului WPF nu exista pana la primul release al lui) - codul
detecteaza asta si arata un mesaj explicit ("arhiva nu e inca disponibila
la acest link") in loc sa descarce ceva gresit. **De facut la primul
release real al clientului WPF**: `release.sh` (sau un flux nou) trebuie
sa publice o arhiva `DataMover-WPF-Windows.zip` si sa completeze acest
camp in `update.json`.

**4. Profil Utilizator/HWID + Licentiere Ed25519 + Revocare Supabase.**
Portate 1:1 din `GDCVaultWin` (namespace ajustat la `DataMover.Core.
Services`, acelasi proiect Supabase - Regula 12): `LicenseCore.cs`
(validare seriale Ed25519, aceeasi cheie publica a ecosistemului),
`MachineID.cs` (WMI `Win32_ComputerSystemProduct.UUID`), `LicenseManager.cs`
(`ProductId="gdc-datamover"` - **acelasi ID ca `LicenseManager.swift`
Mac**, `TrialDurationDays=15`, **fara gating dur pe Start - la fel ca Mac**,
vezi mai jos), `SupabaseConfig.cs`/`AnalyticsClient.cs`/`RevocationCheck.cs`
(fail-open)/`UserProfileStore.cs` (Nume/Email/MachineID persistate local).
UI nou: `ProfileWindow.xaml(.cs)` (fereastra separata, deschisa din
butonul "Profil" din footer) - arata status licenta/proba, camp de
activare cod + link WhatsApp (`wa.me/34643109970`, acelasi numar ca restul
ecosistemului), editare Nume/Email cu buton Salveaza (trimite telemetrie
catre Supabase doar daca Numele nu e gol).

**[GASIT LA AUDIT, NU REPARAT INCA - flag de paritate]** DataMover Mac
(`LicenseManager.swift`) NU are inca infrastructura Supabase de Profil/
Revocare (Regula 12) - doar trial+activare Ed25519 locala, 100% offline.
Windows WPF e acum INAINTEA lui Mac la acest capitol - de aliniat Mac la
aceeasi infrastructura la o viitoare etapa, nu invers.

**5. Panou dependinte 🔴/🟢.** DataMover nu are dependinte externe grele
(spre deosebire de CGConvertor/FFmpeg) - indicatorul din `ProfileWindow`
e simplificat la un rand static verde ("Toate componentele necesare sunt
prezente (.NET 8 runtime inclus)"), pastrat totusi vizibil pentru
consecventa cu Regula 4 din restul ecosistemului, nu ca panou complet
modular `DependencyItem` (nejustificat aici - nimic de verificat headless).

**6. Layout responsiv (raportat de Cristi: "sa nu se urce una peste
alta... sa fie destul de responsiv casutele").** Toate randurile
orizontale din coloana centrala (`MainWindow.xaml` - Proiect/Card,
Model verificare, Excluderi, preset-uri I/O, Buffer/RAM, Profile de
transfer) convertite din `StackPanel Orientation="Horizontal"` in
`WrapPanel` - la o fereastra ingusta, campurile trec pe randul urmator in
loc sa se taie sau sa iasa din card. Footer-ul (progres/status/butoane)
rescris pe 3 randuri SEPARATE (status text, apoi un `WrapPanel` de butoane
aliniat dreapta) in loc de un `Grid` cu 2 coloane fixe - butoanele noi
(Actualizari, Profil, langa Istoric/Pauza/Anuleaza/Start) nu mai risca sa
iasa din marginea ferestrei la `MinWidth=900`.

**Versiune** `windows-native/DataMover.Client.csproj` → `2.7.0` (MINOR -
patru functionalitati noi vizibile). Nu s-a atins `docs/update.json`
(versiunea publica 2.6.0 ramane a clientilor Mac/Python existenti - acest
client WPF nu e inca livrat, vezi TODO installer).

**Verificat**: `dotnet build` (Core + Client, C# + XAML→BAML) - 0 erori,
0 avertismente. **Nu s-a testat inca real pe Windows** fluxul de
Activare/Profil/Update/PDF - urmeaza confirmarea lui Cristi.

**[CONFIRMAT 2026-08-28]** Cristi a testat real pe Windows - PDF-ul nu
aparea deloc. Diagnosticat prin fisierul `offload_report_PDF_EROARE.txt`
(adaugat ca fallback in acelasi commit al fix-ului): `QuestPDF` nu are
build nativ pentru **win-arm64** - Cristi ruleaza Windows in Parallels pe
Mac Apple Silicon, deci host-ul e ARM64, iar proiectul (implicit "Any
CPU") rula procesul ca win-arm64. QuestPDF cere explicit "Platform target
= x64 sau x86, nu Any CPU" - Windows 11 ARM ruleaza un proces x64 prin
emulatie nativa a OS-ului. Fix: `<PlatformTarget>x64</PlatformTarget>` in
`DataMover.Client.csproj`. **Regula practica noua**: orice pachet NuGet
cu dependinte native (Skia, etc.) intr-un proiect WPF trebuie testat cu
`PlatformTarget` explicit, niciodata "Any CPU" implicit - un host ARM64
(Parallels pe Mac, sau un Windows on ARM real) altfel pica silentios pe
orice librarie fara build arm64.

## Etapa 2026-08-28 (5) — Installer Inno Setup + CI pentru clientul WPF (pregatire pentru primul release real)

Cerinta lui Cristi ("se poate publica") - dupa ce a vazut clientul WPF
functional (drive-uri, drag&drop, PDF, profil/licentiere), a ales explicit
sa PREGATIM intai installer-ul inainte de orice release public (nu
publicare directa fara pachet propriu). Inchide TODO #4 din etapa (2).

1. **`windows-native/installer.iss` (nou)** - Inno Setup, port al
   `installer.iss` din radacina (clientul Python vechi), dar SEPARAT -
   cei doi clienti Windows coexista, fiecare cu propriul installer.
   `LicenseFile=License.txt` inclus de la ÎNCEPUT (Regula 19, Consent
   Gate - obligatoriu pentru orice installer NOU, nu opt-in).
   `[UninstallDelete]` acopera `%LocalAppData%\DataMover` SI
   `%AppData%\DataMover` (LicenseManager/UserProfileStore scriu in primul,
   HistoryStore/TransferProfileStore/UpdateChecker dismissal in al doilea).
2. **`windows-native/License.txt` (nou)** - NU un MIT License generic
   (interzis explicit de completarea 2026-08-27 a Regulii 19) - text
   propriu cu cele 4 puncte cerute: statut independent, licentiere
   Machine ID, natura de donatie, garantie "as is"/limitare raspundere.
3. **Iconita** - `windows-native/DataMover.Client/app.ico` (copiat din
   `DataMover.ico` existent la radacina repo, acelasi folosit de clientul
   Python) + `<ApplicationIcon>` in `.csproj`.
4. **`.github/workflows/build-windows-wpf.yml` (nou)** - CI separat,
   ruleaza doar cand se modifica `windows-native/**` (path filter, ca sa
   nu dubleze build-ul la fiecare push care nu-l atinge): `dotnet publish
   -r win-x64 --self-contained` + compilare Inno Setup + arhiva
   `DataMover-WPF-Windows.zip` ca artefact descarcabil (verificare
   continua, NU e inca folosit pentru un release real).
5. **`release.yml`** - job nou `build-windows-wpf` (aceeasi reteta ca (4),
   ruleaza la push de tag), inclus in `needs` al `create-release` -
   arhiva `DataMover-WPF-Windows.zip` se ataseaza acum AUTOMAT la orice
   release viitor, alaturi de Mac si de clientul Python vechi.
6. **`release.sh`** - extins sa bumpe si sincronizeze ACUM 6 locuri (nu 4):
   adaugat `windows-native/DataMover.Client/DataMover.Client.csproj` si
   `windows-native/installer.iss`, cu aceeasi verificare HARD ca toate sa
   ajunga la versiunea ceruta. `docs/update.json` capata campul nou
   `download_url.windows_wpf` (URL stabil `releases/latest/download/
   DataMover-WPF-Windows.zip`, Regula 17 - campul `windows` existent
   ramane neatins, tinteste tot clientul Python). Verificarea finala HTTP
   include acum si `DataMover-WPF-Windows.zip`.

**Verificat**: `dotnet publish -r win-x64 --self-contained` ruleaza cu
succes DE PE MAC (`EnableWindowsTargeting`) - produce `DataMover.exe` +
264 fisiere in `publish/`, verificat manual. `bash -n release.sh` -
sintaxa OK. `dotnet build` (Debug) - 0 erori dupa toate schimbarile.
**NU verificat inca**: compilarea REALA a `installer.iss` cu Inno Setup
(necesita Windows - se va confirma la prima rulare CI/release real),
si fluxul complet `release.sh` (necesita un release real, nu doar
pregatire - urmeaza cand Cristi confirma ca vrea sa apese "publica").

**[CONFIRMAT 2026-08-28] Publicat `v2.7.0` — primul release cu 3 artefacte
(Mac + Windows Python + Windows WPF).** `release.sh` a cazut o data in
Pasul 2 pe ACEEASI eroare de permisiuni documentata deja mai jos in acest
fisier (`dist/DataMover.app` ramas `root:wheel` dintr-un build anterior
cu `sudo`) - Cristi a rulat manual `sudo rm -rf mac-native/dist`, apoi
`release.sh` a rulat curat pana la capat (Mac semnat+notarizat+stapled,
CI Windows x2 verde, toate 3 artefactele HTTP 200 pe tag-ul corect).
**Regula practica confirmata**: aceasta eroare de permisiuni tinde sa
reapara oricand cineva a rulat vreodata un build Mac cu `sudo` - de
verificat `ls -la mac-native/dist` INAINTE de a rula `release.sh`, nu
doar dupa ce pica.

## Etapa 2026-08-28 (6) — 2 probleme reale gasite dupa primul release v2.7.0

1. **Site-ul (`docs/index.html`) dadea clientul Windows VECHI (Python).**
   Cristi a descarcat de pe `gordas.dev/datamover` si a primit designul
   vechi ("imi da versiunea veche") - cauza REALA, nu cache: butonul
   Windows din `initDirectDownload()` tintea `DataMover-Windows.zip`
   (clientul Python), niciodata schimbat catre clientul WPF nou. Fix,
   confirmat explicit de Cristi: `FILES.win` -> `DataMover-WPF-Windows.zip`.
   **Clientul Python vechi ramane publicat pe fiecare release** (nu
   sters, nu oprit din CI) - doar nu mai e ce ofera site-ul implicit;
   ramane accesibil manual din pagina de Releases GitHub. `docs/
   update.json` campul `"windows"` (folosit de self-update-ul clientului
   Python INSTALAT deja la userii vechi) **NU s-a atins** - schimbarea
   lui ar fi facut update checker-ul vechi sa incerce sa se auto-inlocuiasca
   cu binarul WPF, flux netestat si periculos pentru useri existenti.
2. **Mismatch real de 7 vs 15 zile proba, intre Mac si Windows.**
   `LicenseManager.swift` (Mac) foloseste explicit `trialDurationDays = 7`
   (nu 15, valoarea implicita din Regula 3 a ecosistemului) - `LicenseManager.cs`
   (Windows, scris in aceasta sesiune) fusese copiat gresit cu 15. Fixat
   la 7, cu comentariu explicit sa nu se mai repete confuzia.
3. **Mac nu avea panou de Profil vizibil** (Cristi: "nu vad... numele de
   la client, email, ID-ul masinii, plus acces sa-si vada serialul").
   Adaugat `profileSection` (nou) in popover-ul de Setari
   (`ContentView.swift`): Nume/Email optionale (`@AppStorage`, LOCALE -
   Mac nu are inca infrastructura Supabase portata pe Windows in aceasta
   sesiune, ramane flag de paritate), Machine ID cu buton Copiaza, si
   **codul de licenta salvat** cu buton Copiaza (`LicenseManager.
   savedLicenseCode`, nou - citeste fisierul deja salvat, nu revalideaza
   nimic). Daca nu exista cod salvat, un link "Activeaza…" deschide
   `ActivationSheet` direct din Setari.

**Verificat**: `swift build` (Mac) - 0 erori. `dotnet build` (Windows,
fix trial) - 0 erori.

**[CONFIRMAT 2026-08-28] Publicat `v2.7.1`** - cele 3 fix-uri de mai sus
live. `release.sh` a cazut o a doua oara pe ACEEASI eroare de `dist/`
root-owned (vezi Regula 23, adaugata chiar din acest motiv) - Cristi a
rulat manual `sudo rm -rf mac-native/dist`, apoi scriptul a rulat curat:
Mac semnat+notarizat+stapled (`spctl`: Notarized Developer ID), CI
`build-windows-wpf` verde, toate 3 artefactele (`DataMover-Mac.zip`,
`DataMover-Windows.zip`, `DataMover-WPF-Windows.zip`) HTTP 200 pe tag-ul
`v2.7.1`, API-ul de update confirmat pe `v2.7.1`. Release:
https://github.com/gordasgdc/datamover/releases/tag/v2.7.1

## Etapa 2026-08-30 — Destinatie secundara Cloud, powered by Rclone (paritate Mac/Windows, v2.8.0)

Cerinta explicita a lui Cristi, dupa ce Master Control Studio Pro a capatat
un Cloud Manager complet (Rclone): "vreau sa copiez ceva, dar in acelasi
timp sa il si urc direct pe unul dintre serviciile facute cu Rclone". Nu a
fost nevoie de nicio "legatura" intre cele doua aplicatii - `rclone` tine
toate conturile intr-un singur `rclone.conf` GLOBAL (`~/.config/rclone/`
Mac, `%AppData%\rclone\` Windows), ne-izolat per aplicatie, deci orice cont
configurat prin Cloud Manager e deja vizibil aici, doar de folosit acelasi
binar.

**Implementare (ambele platforme, port 1:1):**
- `CloudSyncService.swift`/`.cs` (nou) - `isAvailable()`/`listRemotes()`
  (`rclone listremotes`, PATH augmentat pe Mac cu `/opt/homebrew/bin`, PATH
  proaspat din Registry pe Windows - acelasi fix deja documentat in
  MacMasterControlPro/Win pentru exact aceeasi problema), `uploadFile()`
  (`rclone copyto` fisier->fisier, nu re-scaneaza tot folderul remote la
  fiecare fisier - Regula 21).
- `CloudUploadQueue` (nou, `@unchecked Sendable`/thread-safe) - o coada
  SERIALA de upload-uri per `DestinationJob`, ca sa nu multiplice procese
  `rclone` in paralel (memorie/banda) - "in acelasi timp" inseamna in
  fundal fata de copierea locala, nu neaparat N procese simultane pe
  aceeasi destinatie.
- `DestinationJob` (`OffloadEngine.swift`/`.cs`) - dupa fiecare fisier
  copiat local cu succes (status OK/SARIT, NICIODATA la NEPOTRIVIRE/EROARE),
  enqueue catre coada Cloud. La finalul job-ului, `waitUntilDrained()`
  inainte de raportul final - altfel raportul ar aparea "complet" cat timp
  inca se mai urca fisiere in fundal.
- UI (`ContentView.swift` / `MainWindow.xaml(.cs)`) - sectiune noua in
  popover-ul/popup-ul de Setari: dropdown cu conturile deja configurate +
  camp opțional de subfolder, ascunse daca `rclone` nu e instalat (mesaj
  explicit de indrumare catre Master Control Studio Pro › Dependente, in
  loc de dropdown gol care ar esua tacut la prima incercare).
- `TransferProfile`/`TransferProfileStore` - salveaza acum si alegerea
  Cloud; campurile noi sunt `Optional`/au valoare implicita, deci profilele
  salvate INAINTE de aceasta versiune raman valide (decodare `nil`/"").

**Verificat**: `swift build` (Mac) si `dotnet build` (Windows.Client, de pe
Mac) - 0 erori, 0 avertismente, ambele platforme. **Nu s-a testat inca
real** un upload efectiv catre un cont Cloud real (necesita un cont
configurat + o rulare completa pe fiecare platforma) - Cristi urmeaza sa
confirme manual dupa publicarea versiunii.

## Etapa 2026-08-30 (2) — Plafon de 2 GB per transfer in versiunea de proba (paritate Mac/Windows, v2.9.0)

Cerinta explicita a lui Cristi, raportata de testerii lui: proba de 7 zile
se ocoleste trivial - dezinstalare, folosire, reinstalare, proba noua, la
nesfarsit. Solutia ceruta explicit NU e o reparare a persistentei
trial-ului (ar necesita ancorare server-side pe Machine ID, mult mai
complex), ci un plafon de dimensiune per transfer in versiunea neactivata:
**2 GB maxim**, suficient pentru testare, insuficient pentru folosire
productiva reala.

**Descoperire importanta la implementare**: pe ambele platforme, comentariul
existent din `LicenseManager.cs` ("DECIZIE DE PRODUS (identica cu Mac): NU
exista niciun gating dur pe Start") era literalmente adevarat verificat -
`isUnlocked`/`IsUnlocked` (calculat din `isLicensed || isTrialActive`) NU
era folosit NICAIERI in `ContentView.swift`/`MainWindow.xaml.cs` pentru a
bloca ceva. Aplicatia functiona identic de proba SAU licentiata, mereu -
singurul lucru vizibil era un banner "X zile ramase", niciodata aplicat ca
restrictie reala. Plafonul de 2 GB e prima restrictie functionala introdusa
vreodata pe acest produs.

**De ce plafonul e legat de `isLicensed`, NU de `isTrialActive`**: un
plafon calculat din zilele de proba ramase ar fi fost ocolit de EXACT
acelasi abuz semnalat (dezinstalare -> reinstalare -> contor de zile
resetat -> plafon "ridicat" din nou). Legat strict de `isLicensed`
(activare cu cod Ed25519 valid), dezinstalarea/reinstalarea repetata nu
schimba nimic - doar o licenta reala scoate plafonul.

**Implementare (ambele platforme, port 1:1):**
- `LicenseManager.swift`/`.cs` - `trialMaxTransferBytes`/
  `TrialMaxTransferBytes = 2 GB` (constanta).
- `OffloadRunner.start()`/`.Start()` - dupa ce lista de fisiere e
  construita (inainte de a porni orice job), daca `!isLicensed`, suma
  TOTALA a dimensiunilor (nu per fisier - altfel usor de ocolit trimitand
  multe fisiere mici) e comparata cu plafonul; daca-l depaseste,
  transferul NU porneste (`isRunning` ramane `false`), iar
  `trialLimitExceededBytes`/`TrialLimitExceededBytes` retine dimensiunea
  pentru UI.
- UI: Mac arata un `.alert` cu buton "Activeaza licenta" (deschide
  `ActivationSheet`); Windows arata un `MessageBox` cu acelasi mesaj,
  OK deschide `ProfileWindow` (unde se introduce codul).

**Verificat**: `swift build` (Mac) si `dotnet build` (Windows.Client, de pe
Mac) - 0 erori. **Nu s-a testat inca real** un transfer efectiv peste 2 GB
in versiune neactivata pe fiecare platforma - Cristi urmeaza sa confirme
manual ca dialogul apare si blocheaza corect Start-ul.

## Etapa 2026-08-30 (3) — Upload Cloud lent, cauza reala + fix (v2.10.1)

Raportat direct de Cristi, dupa primul test real cu rclone activat: "mi se
pare exagerat de mult ca dureaza transferul". Cauza REALA, gasita in cod
(nu presupusa): `CloudUploadQueue.enqueue()` pornea un proces `rclone
copyto` NOU, complet separat, pentru FIECARE fisier terminat local, unul
dupa altul (coada seriala) - la multe fisiere, overhead-ul de
pornire+autentificare al fiecarui proces domina timpul, nu banda reala.

**Fix (ambele platforme, port 1:1)**: `CloudSyncService.uploadBatch()`
(inlocuieste `uploadFile`/`copyto`) - `rclone copy <localRoot> remote:
--files-from -` (lista de cai pe stdin), cu
`--transfers 8 --checkers 16 --drive-chunk-size 64M --fast-list`.
`CloudUploadQueue` acumuleaza acum fisierele intr-un LOT (25 fisiere sau 3
secunde de la primul fisier neurcat, ce vine primul), golit printr-un
SINGUR proces `rclone` per lot - rclone insusi paralelizeaza transferurile
din lot, in loc de un proces per fisier.

**Descoperire separata, mult mai mare ca impact**: masurat direct
(`nettop` pe procesul `rclone` activ) ca viteza REALA pe conexiunea lui
Cristi (confirmata cu `networkQuality -s`: 753 Mbps upload) era totusi
doar ~2.5 Mbit/s pe un singur fisier mare - net sub capacitatea reala.
Cauza: Google limiteaza agresiv clientul OAuth PARTAJAT al rclone-ului
(acelasi ID pentru toti utilizatorii rclone din lume), independent de
batching. Fix REAL: client OAuth propriu (Google Cloud Console, Desktop
app) - configurat manual pe remote-ul de test (`rclone config update
<remote> client_id ... client_secret ...` + `rclone config reconnect`),
masurat direct: **~18x mai rapid** (2.5 Mbit/s -> ~47 Mbit/s, acelasi cont,
acelasi fisier). Acest client OAuth propriu a fost apoi EMBEDDED direct in
`MacMasterControlPro` (nu in DataMover - vezi CLAUDE.md-ul acelui repo,
`GDCOAuthClients`), ca orice cont Google Drive nou adaugat prin Cloud
Manager sa-l foloseasca automat, fara ca clientul final sa treaca prin
Google Cloud Console. DataMover beneficiaza indirect - remote-urile sunt
partajate prin acelasi `rclone.conf` global (Regula de arhitectura Cloud,
Etapa 2026-08-30).

**Pagina web** (`docs/index.html`) - prețul fix (23 €) scos din tot textul
(RO/EN/ES) - suma exacta apare doar in aplicatie, la Activare (Regula 27,
pret dinamic) - decizie separata a lui Cristi: paginile web NU mai trebuie
sincronizate manual la fiecare schimbare de pret/oferta.

**Verificat**: `swift build` (Mac) si `dotnet build` (Windows.Core +
Windows.Client, de pe Mac) - 0 erori pe toate. Testat REAL, live, de
Cristi: batching-ul confirmat activ (`ps`/`pgrep` arata comanda `rclone`
noua cu flag-urile corecte), viteza masurata live cu `nettop` a crescut de
la ~2.5 Mbit/s la ~27 Mbit/s pe transferul lui real (dupa configurarea
clientului OAuth propriu) - **confirmat funcțional, nu doar compilat**.

## Etapa 2026-09-03 — Flux profesional de offload, inspirat de ShotPut Pro (v2.11.0, paritate completa Mac/Windows)

Cerinta lui Cristi, cu ShotPut Pro (liderul international al categoriei) ca
reper: *"ce putem imbunatati noi in Data Mover ca sa fie mai eficient si mai
profesional... fiecare sa fie independent una de alta, dar sa aiba acelasi
scop"* — apoi, la lista de 9 propuneri prioritizate: **"le vreau pe toate"**.
Toate cele 9 au fost implementate pe AMBELE platforme in aceeasi versiune
(nu s-a folosit clauza de independenta Mac/Windows — nu a fost nevoie, nicio
functie n-a fost blocata tehnic pe vreo platforma).

### P1 — obligatorii pentru intrarea intr-un flux de post-productie

**1. MHL (Media Hash List) v1.1** — `MHLWriter.swift` / `MhlWriter.cs`.
Fisier XML scris langa datele copiate, in radacina folderului de destinatie,
cu cai RELATIVE (ca mutarea folderului sa nu-l invalideze). Citit de
Silverstack, YoYotta, ShotPut Pro, Resolve. **Fara el, un card descarcat cu
DataMover nu putea intra intr-un flux profesional** — CSV/PDF sunt rapoarte
pentru OM, MHL e pentru MASINA.
- Doar `md5`/`sha1`/`xxhash64be` sunt in schema MHL 1.1 — la SHA-256/512
  transferul si rapoartele raman complete, doar MHL-ul nu se scrie (cu mesaj
  explicit in feed, nu tacere).
- Se scrie DOAR pentru fisierele cu status OK/SARIT (verificate). Un MHL e o
  certificare; un fisier nesigur in el ar certifica date corupte.
- **Memorie (Regula 21)**: intrarile se scriu incremental intr-un `.part`;
  la `close()` se compune fisierul final. Motivul pentru care corpul nu
  poate merge direct in fisierul final: `<creatorinfo>` sta obligatoriu
  PRIMUL in schema si contine `<finishdate>`, cunoscut abia la sfarsit.
- Caile din MHL folosesc mereu `/` (normalizate pe Windows) — altfel un MHL
  scris pe Windows n-ar putea fi verificat pe Mac.

**2. xxHash64 (XXH64, seed 0)** — `XXHash64.swift` / `XxHash64.cs`, ambele
implementari PROPRII, fara nicio dependinta externa (pe Windows: intentionat
NU pachetul `System.IO.Hashing` — un restore NuGet esuat in CI ar bloca
release-ul pentru un algoritm de 100 de linii). Devenit **modelul implicit**
de verificare (era MD5), ca la ShotPut/Silverstack.
- **VALIDARE OBLIGATORIE, facuta**: ambele implementari au fost verificate
  byte-for-byte fata de implementarea de referinta (`python-xxhash`) pe 8
  vectori (0, 1, 3, 31, 32, 33, 256, 1800 octeti) x 3 dimensiuni de bucata
  (7 / 32 / 1.000.000) = 24 de combinatii per platforma, toate identice, si
  identice intre Mac si Windows. Cazurile 31/32/33 acopera exact granita
  stripe-ului de 32 de octeti, unde o implementare gresita de streaming
  trece testul pe fisiere mici si esueaza pe cele mari.
- **Daca se mai atinge vreodata cod de hashing aici**: re-ruleaza acea
  validare inainte de release. Un hash gresit nu da eroare — da un MHL
  care certifica fals, descoperit luni mai tarziu, in post.

**3. Reincercare automata a fisierelor esuate** — pas separat, la finalul
transferului, INAINTE de scrierea rapoartelor (rapoartele trebuie sa arate
starea finala). Fisierul partial de la destinatie se STERGE inainte de
recopiere (`allowSkipExisting: false`), altfel logica "exista deja, verific
doar" l-ar putea considera bun. Recuperarile apar EXPLICIT in rezumat si in
rapoarte (`OK (reincercat)`) — userul trebuie sa stie ca transferul a avut
rateuri tranzitorii chiar daca s-a terminat bine (indiciu de cablu/card/disc
in curs de a ceda).
- Refactor necesar: bucla per-fisier a fost extrasa in `processOne`/
  `ProcessOne`, folosita IDENTIC de ambele treceri — altfel cele doua cai
  ar diverge in timp si un fisier recuperat ar fi verificat altfel decat
  unul copiat din prima.

**4. Verificare de spatiu liber INAINTE de primul octet copiat.** Un card de
512 GB pornit catre un disc cu 80 GB liberi copia ore intregi si esua la
mijloc. Acum transferul nu porneste; userul vede cifrele reale si poate
forta (`ignoreSpaceWarning`). La o RELUARE se scad fisierele deja prezente
cu aceeasi dimensiune — altfel o reluare la 90% ar fi blocata cerand spatiu
pentru date deja copiate. Marja: 1% din transfer, minim 100 MB (rapoartele
se scriu tot acolo, la final). Mac:
`volumeAvailableCapacityForImportantUsage` (corect pe APFS, tine cont de
snapshot-uri purjabile), nu `systemFreeSize`.

### P2 — flux de lucru

**5. Coada de carduri** (`QueueItem`) — carduri descarcate unul dupa altul,
fiecare in PROPRIUL folder (spre deosebire de mai multe surse adaugate
simultan, care merg toate in acelasi folder). In coada, reluarea e implicit
ACTIVA si dialogul de duplicate e ocolit: modul nesupravegheat nu poate
astepta un raspuns. O ANULARE opreste toata coada (daca userul a apasat
Anuleaza, nu vrea sa porneasca imediat cardul urmator).

**6. Pornire automata la introducerea unui card** — cardul intra direct in
coada si porneste singur. Conditii obligatorii: exista cel putin o
destinatie aleasa, si prima trecere de polling stabileste doar baseline-ul
(altfel orice card deja conectat la pornirea aplicatiei ar declansa fals o
descarcare).

**7. Sablon liber pentru numele folderelor** — `NamingTemplate.swift`/`.cs`,
tokeni `{data} {ora} {proiect} {card} {camera} {operator}`, cu
PREVIZUALIZARE LIVE in Setari (un sablon gresit descoperit dupa 2 TB copiati
nu se mai poate corecta fara mutare manuala). Sablonul implicit produce
EXACT numele vechi, deci nimeni nu e afectat daca nu-l schimba.
- **Consecinta arhitecturala**: `findExistingFolderName` nu mai poate cauta
  dupa sufixul hardcodat `_Proiect_Card`. Cauta acum "miezul stabil" al
  sablonului (`stableCore` = tot, mai putin tokenii de data/ora) —
  generalizarea corecta a fix-ului din 2026-08-28 (transfer care trece peste
  miezul noptii).

### P3 — profesionalism vizibil

**8. Recunoasterea structurii de card** — `CameraCardDetector.swift`/`.cs`:
RED (`.RDM`), ARRI (`.ARI`/`AVID`), Sony XDCAM (`XDROOT`) si XAVC
(`PRIVATE/M4ROOT`), Panasonic AVCHD (`PRIVATE/AVCHD`) si P2 (`CONTENTS`),
Blackmagic (`.braw`), Canon (`DCIM`+`MISC`), DCIM generic. **Ordinea
verificarilor conteaza** — structurile specifice INAINTEA lui `DCIM`, pe
care il are si un telefon. Pur informativ, nu blocheaza niciodata
transferul. Avertizeaza la: card gol, fisiere de 0 octeti (clipuri
incomplete), si — cel mai valoros — `parentLooksLikeCard`, cazul in care
userul a selectat un SUBFOLDER al cardului in loc de radacina si ar pierde
metadatele.

**9. Rapoarte brandate + raport HTML** — `ProductionMeta` (Proiect, Client,
Card, Camera, Operator/DIT, Note, Logo) alimenteaza ACELEASI campuri si in
sablonul de denumire, si in antetul PDF, si in HTML. Campurile goale NU
apar deloc (un raport cu "Client: —" arata neterminat). Logo-ul se
INCORPOREAZA in HTML ca data URI (plafonat la 3 MB) — un `<img src="fisier">`
ar functiona doar cat timp raportul sta langa imaginea originala, exact ce
nu se intampla cand e trimis pe email.

**10. Ejectare automata + notificare de sistem.** Ejectarea se face DOAR
daca transferul s-a terminat fara nicio eroare — un card cu probleme nu se
scoate niciodata automat (s-ar putea sa mai fie nevoie de o reluare de pe
el; scoaterea l-ar transforma dintr-o problema reparabila in pierdere de
material).
- **Diferenta reala Mac/Windows**: Mac are `NSWorkspace.unmountAndEjectDevice`.
  Windows NU are un echivalent simplu si sigur din .NET fara P/Invoke pe
  handle-uri de volum — folosim utilitarul nativ `mountvol /P`, care cere
  drepturi de Administrator. Cand nu le are, esecul e RAPORTAT in feed, nu
  ascuns: userul trebuie sa stie ca mai are de scos cardul manual, nu sa
  creada ca s-a facut.
- Notificarea: `UNUserNotificationCenter` (Mac). `Bundle.main.bundleIdentifier`
  se verifica explicit inainte — `UNUserNotificationCenter.current()` arunca
  o exceptie FATALA intr-un proces fara bundle id (rulare din linia de
  comanda), si ar fi crapat aplicatia exact la final de transfer.

### Decizii transversale

- **Feed-ul de activitate nu se mai goleste la start** (doar se adauga un
  separator `──── Transfer nou: <folder> ────`). Motiv: avertismentele
  detectorului de carduri apar INAINTE de start si tocmai ele trebuie sa
  ramana vizibile in timpul transferului. Plafonul de 200 de linii ramane.
- **Windows: `AppSettings`** (`%AppData%\DataMover\settings.json`) —
  echivalentul `@AppStorage` de pe Mac, acelasi tipar ca `ThemeSettings`.
  Notele de filmare sunt SINGURELE nepersistate: o nota veche aparuta in
  raportul de maine ar fi o informatie gresita intr-un document de predare.
- **Verificat**: `swift build` (Mac, 0 erori) + `dotnet build` pe
  `DataMover.Core` (0 erori, 0 warning-uri). Clientul WPF (net8.0-windows)
  nu se poate compila pe Mac — verificat de CI la release.

## Etapa 2026-09-06 — Thumbnail real per fișier în raportul HTML (v2.11.3, paritate Mac/Windows)

Cerință directă a lui Cristi, în timp ce testa fix-ul de comparație
metadate al CGConvertor: *"nici în aplicația Data Mover nu îmi apar aceste
thumbnail-uri în generarea rapoartelor... arată foarte pro și dă o senzație
foarte plăcută"*. Raportul HTML (`HTMLReport`/`HtmlReport`, alături de CSV
și PDF) arăta doar text — nume, mărime, hash-uri, status — fără nicio
previzualizare vizuală a conținutului copiat.

**Descoperire la implementare, nu presupusă**: `ReportRow` (ambele
platforme) NU avea calea reală a fișierului la destinație — doar hash-uri
și numele relativ. Coloanele „Sursă"/„Destinație" din raportul HTML arătau
de fapt hash-uri trunchiate, nu căi — nume derutant, păstrat neschimbat
aici (schimbarea lor ar fi scop separat, nemenționat de Cristi). A fost
nevoie de un câmp nou, `destPath`/`DestPath`, adăugat la toate cele 4
puncte unde se construiește un `ReportRow` (bucla principală + pasul de
reîncercare), pe ambele platforme.

**Mac**: `QuickLookThumbnailing` (framework de sistem, ZERO dependință
nouă — DataMover rămâne fără FFmpeg/librării grele, spre deosebire de
CGConvertor). `thumbnailDataURI(path:)` (nou, `ProductionMeta.swift`)
cere o reprezentare de 160×90 prin `QLThumbnailGenerator.shared.
generateBestRepresentation` (API asincron, blocat scurt cu un
`DispatchSemaphore` — `writeReports` rulează deja pe fundal, Regula 21),
convertită la JPEG (`NSBitmapImageRep`, compresie 0.6) și embedată ca
data URI, cu plafon de așteptare de 3s per fișier (un fișier corupt/blocat
nu trebuie să înghețe generarea raportului).

**Windows**: fără echivalent direct al QuickLook — `ThumbnailExtractor.cs`
(nou, `DataMover.Core`) folosește COM-ul nativ al Shell-ului,
`IShellItemImageFactory::GetImage` (ACELAȘI mecanism din spatele
previzualizărilor "Large icons" din Explorer — o previzualizare REALĂ a
conținutului, nu iconița generică de tip fișier ca la `ShellIcon.cs`,
folosit doar pentru iconițe de disc). `HBITMAP` → `System.Drawing.Bitmap`
→ JPEG (pachet nou, `System.Drawing.Common` — funcțional doar pe Windows,
`net8.0-windows` deja țintă exclusivă a acestui proiect).

**Verificat REAL, nu doar citire de cod (Mac)**: harness standalone
(`ReportRowShim.swift` + `ProductionMeta.swift` + `main.swift`, compilat cu
`swiftc -framework AppKit -framework QuickLookThumbnailing`) — un clip
`.mp4` real generat cu ffmpeg, `HTMLReport.write(...)` apelat cu
`destPath` către el, HTML-ul rezultat conține efectiv `class="thumb"` +
`data:image/jpeg;base64` — thumbnail-ul chiar s-a extras din cadrul
video, nu doar cod care compilează.

**Verificat parțial (Windows)**: `dotnet build` (Core + Client, de pe
Mac) — 0 erori, 0 avertismente. **Extragerea COM efectivă (`SHCreateItemFromParsingName`/
`IShellItemImageFactory`) NU a putut fi testată** — necesită Windows real
(interop COM nu rulează sub `EnableWindowsTargeting` pe Mac). Cristi
trebuie să confirme manual, la următorul transfer real pe Windows, că
thumbnail-urile chiar apar în `offload_report_*.html`.

Versiune 2.11.2 → 2.11.3 (PATCH — adăugare vizibilă la o funcție
existentă, fără schimbare de arhitectură, Regula 14) — sincronizată în
`Info.plist` (Mac, + `CFBundleVersion` 22→23), `DataMover.Client.csproj`,
`installer.iss`, `docs/update.json`.

## Etapa 2026-09-06 (5) — Buton "Ghid" in clientul Windows (v2.11.4)

Audit ecosistem (cerut de Cristi): clientul WPF nu avea NICIUN acces la
ghidul PDF, desi `docs/guides/DataMover_Ghid_RO.pdf`/EN/ES exista deja de
la etapa "Ghiduri PDF rescrise complet" (v2.11.2) - erau generate, dar
niciodata bundle-uite/deschise din clientul Windows.

**Fix**: `DataMover.Client.csproj` - 3 PDF-uri adaugate ca `Content`
(`CopyToOutputDirectory=PreserveNewest`), langa exe la publish. Buton nou
"Ghid" (`MainWindow.xaml`, langa "Actualizari") -> `OnShowGuideClicked`
(`MainWindow.xaml.cs`, port 1:1 al `GuidePDF.swift` Mac) - `Process.Start`
cu `UseShellExecute=true`, deschide `DataMover_Ghid_RO.pdf` (clientul WPF
e RO-only azi, fara selector de limba - EN/ES raman bundle-uite pentru
cand se adauga unul, Regula 30).

**Verificat**: `dotnet build` (Core+Client) - 0 erori, 0 avertismente,
XAML->BAML compilat real (validarea `ui:SymbolIcon QuestionCircle24` s-ar
fi stricat la compilare daca numele simbolului era gresit).

Versiune 2.11.3 -> 2.11.4 (PATCH), sincronizata in toate cele 4 puncte
(Info.plist Mac, docs/update.json, DataMover.Client.csproj, installer.iss)
desi schimbarea e doar pe Windows - Regula 14, acelasi tipar deja folosit
in acest repo la fiecare bump anterior.

## Etapa 2026-09-06 (6) — Etichete gresite in raportul HTML (v2.11.5)

Coloanele "Sursa"/"Destinatie" din tabelul raportului HTML
(`ProductionMeta.swift` Mac, `ProductionMeta.cs` Windows) afisau de fapt
`srcHash`/`dstHash` (valori de verificare truncheate), nu cai de fisiere -
`row.file` (prima coloana) e deja calea relativa afisata, iar o cale
COMPLETA nu era retinuta separat in `ReportRow` pentru a fi afisata acolo.
Redenumite "Hash sursa"/"Hash destinatie" pe ambele platforme, cu comentariu
explicativ langa antetul tabelului.

Versiune 2.11.4 -> 2.11.5 (PATCH), sincronizata in toate cele 4 puncte.
Verificat: `swift build` (Mac) si `dotnet build` (Windows.Core) - 0 erori
pe ambele.

## Etapa 2026-09-06 (7) — M1: Motor "citire unică, scriere multiplă" (FanOutCopier) + Faza 2: integrare în orchestrator (v2.12.0)

Cerere directă a lui Cristi (context extern: analiză de arhitectură
Data Mover vs. Silverstack/OffShoot) — verdict confirmat: ADAPTĂM, NU
RESCRIEM. Bug real găsit prin citire directă a codului (nu presupus):
`DestinationJob` (Mac)/`DestinationJob` (Windows) rula câte un job SEPARAT
per destinație, fiecare citind sursa complet pentru copiere, apoi DIN NOU
pentru `srcHash` la verificare — cu 2 destinații, cardul se citea efectiv
de 4 ori (2× copiere + 2× verificare surse), plus 2 citiri ale
destinațiilor pentru `dstHash`.

**M1 — motor nou, izolat** (`FanOutCopier.swift`/`FanOutCopier.cs`, ambele
platforme): UN thread de citire din sursă, distribuie fiecare bucată (8MB,
configurabil) către N cozi mărginite (ring buffer, adâncime 3) — Swift:
`BoundedChunkQueue` (`NSCondition`); Windows: `BlockingCollection<T>`
(nativ .NET). Hash-ul sursei se calculează O SINGURĂ DATĂ din bucățile
citite; hash-ul fiecărei destinații se calculează LA SCRIERE (nu prin
recitire de pe disc). Backpressure real: o destinație lentă umple propria
coadă, thread-ul de citire se blochează, viteza de pe card se aliniază la
cea mai lentă destinație. Eșec izolat pe destinație — nu blochează
celelalte, nu agață thread-ul de citire.

**Verificat REAL, nu presupus** (fișier 37MB `/dev/urandom`, hash de
referință calculat INDEPENDENT de motor — `shasum -a 256`/`SHA256.Create()`
direct pe fișierele de pe disc): hash identic pe Swift, .NET, și referința
externă (`add31de32a1466de...`), pe toate trei. `bytesRead == mărimea
reală` confirmă o singură trecere. Test de eșec parțial (director
inexistent ca a doua destinație): prima destinație reușește, a doua
raportează eroare clar, 0.025s, fără blocaj.

**Faza 2 — integrare în orchestrator** (`DestinationContext.swift`/`.cs`,
noi, înlocuiesc `DestinationJob`): bucla de orchestrare INVERSATĂ — de la
"N job-uri, fiecare iterează toate fișierele" la "o buclă pe fișiere,
fiecare cu fan-out către N destinații". `DestinationContext` păstrează
DOAR bookkeeping-ul per destinație (CSV, MHL, checkpoint, contoare, coadă
Cloud) — FĂRĂ propria buclă de copiere. Checkpoint-ul rămâne per
destinație (pot diferi — o destinație poate avea deja progres dintr-o
rulare întreruptă, alta nu). Clasificare per fișier/destinație în 3
categorii: `alreadyDone` (checkpoint), `existingSameSize` (verificare fără
recopiere — hash-ul sursei calculat o singură dată și reutilizat pentru
toate destinațiile din acest bucket), `needsCopy` (trece prin
`FanOutCopier`, doar către destinațiile care au nevoie efectiv). Reîncercarea
automată e unificată similar — o singură citire per fișier reîncercat,
fan-out doar către destinațiile care au eșuat efectiv la acel fișier
(destinații diferite pot eșua la fișiere diferite).

**Verificat**: `swift build` (Mac) — 0 erori, 0 avertismente (după
`@unchecked Sendable` pe `DestinationContext`, același tipar deja folosit
de `CancelToken`/`PauseToken`). `dotnet build` (Core + Client, de pe Mac)
— 0 erori, 0 avertismente pe ambele. **Rămas de verificat REAL, pe un
card real** — cerut explicit de Cristi să sară peste un test intermediar
izolat suplimentar și să treacă direct la validare cap-coadă pe date
reale, per noua regulă de livrare pe etape (build+urcare+confirmare
înainte de următoarea fază).

Versiune 2.11.5 → 2.12.0 (MINOR — schimbare reală de arhitectură a
motorului, fără schimbare de UI/funcționalitate vizibilă pentru
utilizator, Regula 14).

## Etapa 2026-09-06 (8) — M2: Flush fizic pe disc (v2.13.0)

Continuare directă a M1 (confirmat funcțional pe card real de Cristi).
Cerință: fiecare fișier confirmat "OK" trebuie să fie FIZIC pe disc, nu
doar în cache-ul OS — altfel scoaterea cardului/SSD-ului imediat după
100% poate lăsa date corupte.

**Mac** (`FanOutCopier.swift`, `physicalFlush(_:)` nou): `fcntl(fd,
F_FULLFSYNC)` — documentat oficial Apple ca fiind necesar peste `fsync()`
simplu (multe controllere raportează "scris" imediat ce ajunge în cache-ul
electric propriu, înainte de celulele flash reale). Degradare controlată:
`ENOTSUP` (unele volume SMB/NFS/exFAT vechi) cade pe `fsync()` simplu, NU
tratat ca eroare; orice ALTĂ eroare oprește DOAR acea destinație.

**Windows** (`FanOutCopier.cs`): `FileStream.Flush(true)` — documentat
oficial Microsoft să apeleze `FlushFileBuffers` la nivel de OS, fără
P/Invoke necesar (mai simplu decât propunerea inițială cu apel nativ direct).

**Curățare conexă (Regula 30)**: `copyFileCancelable` (Mac) — confirmat cu
grep pe tot modulul că nimic nu-l mai apelă de la M1 (motorul real e acum
`FanOutCopier`) — șters, cu nota istorică a bug-ului de crash pe care-l
documenta păstrată ca comentariu (aceeași lecție se aplică deja motorului nou).

**Verificat REAL, nu presupus** (ambele platforme, harness izolat cu
fișier real 5MB, pe filesystem-ul real de pe disc): copiere + flush fără
nicio eroare, hash confirmat corect pe ambele. Build: `swift build` — 0
erori/avertismente; `dotnet build` (Core) — 0 erori/avertismente.

Versiune 2.12.0 → 2.13.0 (MINOR — funcționalitate de siguranță nouă,
fără schimbare de UI, Regula 14).

## Etapa 2026-09-06 (9) — M4: Metadate video + Raport DIT PDF (v2.14.0)

Continuare M1/M2 (confirmate funcționale pe date reale de Cristi). Cerere:
port `MediaInspector` (CGConvertor) pentru metadate video (Timecode, FPS,
Rezoluție, Codec, Cameră/Reel, Audio Channels) + thumbnail-uri + status
Pass/Fail MHL în raportul PDF.

**Decizie de arhitectură conștientă, comunicată explicit**: CGConvertor
folosește `ffprobe` (are deja `ffmpeg` bundle-uit pentru transcodare).
DataMover NU are `ffmpeg` — motor de extragere DIFERIT pe fiecare
platformă, ambele fără nicio dependință nouă:

**Mac** (`MediaInspector.swift`, nou) — `AVFoundation` (framework de
sistem): rezoluție, fps, codec video/audio, durată, canale audio — toate
directe din track-uri. **Timecode**: track QuickTime dedicat (`tmcd`),
citit prin `AVAssetReader` — bug real găsit la testare (nu presupus):
primul eșantion al track-ului e un marker gol "edit boundary"
(`dataBuffer=nil`), nu timecode-ul real; fix: continuă până la primul
eșantion cu date efective. **Camera/Reel**: best-effort din metadatele
QuickTime comune — funcționează pentru camere care le scriu acolo (multe
prosumer Sony/Canon/Panasonic), NU pentru formate proprietare (Sony rtmd
binar, RED) — ar cere portul complet al `SonyMetadata.swift`
(CGConvertor), scop separat, nemenționat ca gata.

**Windows** (`MediaInspector.cs`, nou) — parser MP4/ISO-BMFF PROPRIU
(zero dependință): citește direct structura de "boxes" (`moov/trak/mdia/
mdhd/minf/stbl/stsd/stts`) pentru rezoluție/codec/durată/fps/canale audio.
**2 bug-uri reale de offset găsite la testare** (nu presupuse) — formula
`SampleEntry` (box header + reserved[6] + data_reference_index[2] = 16
octeți) fusese omisă din calculul poziției `width`/`height` (Video) și
`channelcount` (Audio) — corectat, verificat cu 2 fișiere reale diverse
(ProRes/.mov 1920×1080@25fps/2ch, H.264/.mp4 1280×720@30fps/1ch), ambele
exacte. Timecode/Camera/Reel NEACOPERITE pe Windows (spus explicit, TODO
real — ar cere parsarea track-ului `tmcd` separat).

**Thumbnail-uri**: Mac — `QLThumbnailGenerator` (deja folosit pentru
raportul HTML, extras acum ca sursă comună). Windows — `ThumbnailExtractor.cs`
(deja exista pentru raportul HTML, v2.11.3) — extins cu o metodă nouă
(`ThumbnailJpegBytes`) care întoarce octeți JPEG bruți, pentru QuestPDF.

**Raport PDF redesenat** (ambele platforme): rânduri "DIT" — thumbnail +
nume fișier + bulină/etichetă Pass/Fail colorată (verde=OK, roșu=eroare/
nepotrivire, gri=sărit) + linie de metadate (mărime · rezoluție · fps ·
codec · timecode dacă există · canale audio) + eroarea, dacă există.
Extragerea rulează DOAR la generarea raportului (eșantionul deja
plafonat, max. 500 fișiere), NICIODATĂ în timpul copierii — motorul de
transfer (`FanOutCopier`) rămâne complet neatins, zero latență nouă pe
calea critică de I/O.

**Verificat REAL, nu presupus** (ambele platforme): metadate extrase din
fișiere video reale generate cu `ffmpeg` (folosit DOAR pentru testare,
nu devine dependință a aplicației), comparate cu valorile reale știute
(rezoluție/fps/canale audio/durată/timecode) — toate exacte. PDF generat
și verificat VIZUAL (randat la PNG) pe ambele platforme — layout corect,
metadate afișate, status colorat corect. `swift build` — 0 erori/
avertismente (în afară de deprecări API sincron AVFoundation, alegere
deliberată — refactorul la variantele async ar afecta întreg lanțul
sincron `finalize()`/`writePDFReport`, disproporționat pentru acest
milestone). `dotnet build` (Core + Client) — 0 erori/avertismente.

Versiune 2.13.0 → 2.14.0 (MINOR — funcționalitate nouă vizibilă, fără
schimbare de arhitectură a motorului de transfer, Regula 14).

## Etapa 2026-09-06 (10) — Retragerea build-ului Windows vechi (Python/PyInstaller) + Semnare Self-Signed pentru clientul WPF

**Decizie explicită a lui Cristi**: clientul Windows WPF (`windows-native/`,
subiectul întregii sesiuni recente M1-M4 — FanOutCopier, physical flush,
MediaInspector, DIT PDF) devine SINGURUL client Windows livrat. Job-ul CI
vechi (`build-windows`, Python/PyInstaller — cel care compila `main.py`/
`tray_monitor.py` cu PyInstaller și `installer.iss` de la rădăcină) e
RETRAS din `release.yml` — nu se mai livrează niciun artefact Windows
Python la niciun release viitor.

**Ce s-a șters exact:**
- Job-ul `build-windows` din `.github/workflows/release.yml` (compilare
  PyInstaller + Inno Setup + arhivare `DataMover-Windows.zip`), inclus în
  `needs` al `create-release` — acum `needs: [build-windows-wpf]`. Pasul
  de download al artefactului vechi (`windows-build`) eliminat din
  `create-release`.
- `.github/workflows/build-windows.yml` (workflow separat, `push` pe
  `main` — construia ACELAȘI job, independent de release, doar pentru
  verificare continuă) — șters complet, fișierul nu mai există.
- `installer.iss` de la rădăcina repo-ului — CONFIRMAT (grep pe tot
  repo-ul) că era referit EXCLUSIV de cele două workflow-uri de mai sus și
  de `release.sh` (doar pentru bump de versiune sincron) — nimic altceva
  îl folosea, sigur de șters.

**Ce NU s-a atins, și de ce (ambiguu/riscant, per instrucțiune explicită
de a nu ghici):** `main.py`, `core/` (tot backend-ul: `offload_engine.py`,
`pdf_report.py`, `license_core.py`, etc.), `ui/` (INCLUSIV `ui/mac/app.py`
— clientul Python Mac, separat de `ui/windows/app.py`), `setup.py`,
`tray_monitor.py`, `DataMover.ico` — acest cod sursă e PARTAJAT, nu
exclusiv build-ului Windows retras. Confirmat direct din fișiere: `main.py`
alege explicit `ui/mac/app.py` pe `sys.platform == "darwin"`, iar
scripturile de lansare locală (`Porneste DataMover.command`,
`Porneste DataMover (Windows).bat`, `build_and_sign.sh` cu `py2app`,
`Lanseaza_DataMover.command`) rulează/împachetează acest cod independent
de CI, pe ambele platforme — ștergerea lui ar fi distrus și clientul
Python Mac de rezervă/local, scop nemenționat de Cristi. Rămâne cod viu
pe disc, dar nu mai e construit/livrat de niciun CI pentru Windows.
`docs/guides/*.pdf` (RO/EN/ES) și scripturile lor de generare (`docs/guides/
generate_guides.py` etc.) nu s-au atins — sunt folosite ȘI de clientul WPF
(buton "Ghid", v2.11.4).

**Semnare Self-Signed adăugată** (Regula 34, Partea 1) — DOAR în
`build-windows-wpf.yml` și în job-ul `build-windows-wpf` din `release.yml`:
`mac-native/codesigning/sign-windows.ps1` + `generate-self-signed-cert.ps1`
+ `README-windows.md` (noi, alături de fișierele Mac deja existente în
același folder, neatinse). Doi pași de semnare per workflow (exe WPF
publicat + `DataMoverSetup.exe` final), condiționați de
`env.HAS_WIN_SELFSIGN` (derivat din `secrets.WIN_SELFSIGN_PFX_BASE64` la
nivel de JOB — `secrets` nu e permis direct într-un `if:` de pas). Fără
secrete încărcate încă în acest repo, CI-ul continuă nesemnat, fără nicio
eroare — Cristi trebuie să reîncarce `.pfx`-ul comun GDC (dacă există deja
din CGConvertor) ca secrete în `DataMover`, pas descris în
`README-windows.md`.

**Verificat**: `actionlint .github/workflows/release.yml
.github/workflows/build-windows-wpf.yml` → 0 erori. `python3 -c "import
yaml; yaml.safe_load(...)"` pe ambele → OK. `git log --all --format="%B" |
grep -c "Co-Authored-By: Claude"` → 0 (Regula 32, verificat înainte de
commit). **Nu s-a rulat un release real** — job-ul retras/modificat nu a
fost declanșat printr-un tag nou în această sesiune, doar validare
statică a workflow-urilor.

## Etapa 2026-09-11 — v2.14.2 publicat cu semnare Windows activa

**Bug real gasit la primul build de semnare (v2.14.1, esuat)**: pasul de
semnare tintea `windows-native\publish\DataMover.Client.exe`, dar
`AssemblyName` din `.csproj` e `DataMover` - executabilul publicat real se
numeste `DataMover.exe`. Calea fusese presupusa din numele PROIECTULUI, nu
citita din `AssemblyName`. CI-ul a picat corect ("nu exista - nimic de
semnat"), nu a produs un binar nesemnat tacut. Corectat in AMBELE workflow-uri
(`release.yml` + `build-windows-wpf.yml`).

Tag-ul v2.14.1 a fost abandonat (nu produsese niciun release), s-a mers pe
v2.14.2 - un tag deja publicat nu se muta.

**Lectie generala**: la portarea semnarii pe un repo nou, calea tintei se
citeste din `AssemblyName`/output-ul real de build, nu se deduce din numele
proiectului.

**TODO paritate Mac**: pachetul Mac pentru 2.14.2 se construieste local
(`cd mac-native && ./build_installer.sh`) si se ataseaza manual la release.
`docs/update.json` a fost lasat INTENTIONAT la 2.14.0 - are un singur camp
`version` comun ambelor platforme, deci un bump acum ar fi trimis userii Mac
spre un release fara pachet Mac (404). Se bump-eaza dupa ce Mac-ul e urcat.

## Etapa 2026-09-19 — v2.15.1: AppMover cu App Translocation (Mac)

- `AppMover.swift` portat din GDC Firewall (Regula 40): locația se judecă
  după original (`SecTranslocateCreateOriginalPathForURL`), copia din
  `/Applications` primește carantina FĂRĂ bitul 0x0080 (carantina rămâne),
  o instalare deja izolată se repară pe loc (doar atributul + repornire) —
  niciodată copiere peste sine sau copia instalată la Coș. `~/Applications`
  rămâne acceptat (Regula 18). Față de referință: carantina se ia din
  original; după copiere se verifică că bitul a dispărut (altfel eroare, nu
  buclă); izolată fără bit = nu repornește (fără buclă).
- `DiagnosticLog.swift` nou (Regula 39) → `~/Library/Logs/DataMover.log` +
  unified log; `scripts/logs.sh`; dezinstalatorul șterge și logul.
- Apelul AppMover mutat din `DataMoverMacApp.init` pe `NSApplication.didFinishLaunchingNotification`:
  în `init` NSApp poate lipsi (vezi comentariul din `ThemeManager.applyNow`).
- Textele alertelor trec prin `L.t("appMover.*")` (RO/EN/ES).
- Versiune comună: Info.plist, `core/update_config.py`, `.csproj`, `installer.iss` la 2.15.1;
  `docs/update.json` rămâne 2.15.0 până la `release.sh`. Windows fără schimbări de cod.
- Test live 2026-09-19, macOS 26.6.2, Mac de dezvoltare (SIP dezactivat):
  build notarizat + stapled, zip cu carantină `0083;…;Safari`, dezarhivat cu
  Archive Utility, pornit din `~/Downloads`. Verificat: izolare detectată, apelul din `didFinishLaunching` funcționează, calea admin (copia root din .pkg înlocuită după parola introdusă de Cristi), carantină `0043`, original la Coș, repornit neizolat; reparare pe loc (`00c3` → `0043`, fără buclă).
- Neverificat: nimic în plus față de SIP. Cu SIP activ (Regula 42) — calea nu folosește
  nimic dependent de SIP, dar n-a rulat pe un astfel de Mac.
- Nepublicat: `update.json`/release rămân pentru scriptul de release.

### Completări specifice acestui repo, mutate din fosta Partea 1 (2026-09-18)

Păstrate verbatim. Regula generală la care se referă fiecare e în
`~/Developer/CLAUDE.md`.

**Regula 20:**

**Status acest repo (2026-08-27): IMPLEMENTAT.** `mac-native/Sources/DataMoverMac/SelfUpdater.swift` — prima implementare din ecosistem, confirmată manual de Cristi. Windows: verifică `core/updater.py` (varianta Python veche) - dacă a fost portat pe orice client nativ nou, aliniază-l la fel.

**Regula 21:**

**Status acest repo (2026-08-27): IMPLEMENTAT — repo de origine.** Mac: `IOSettings.swift` + `autoreleasepool` in `copyFileCancelable`/`genericHash` (`OffloadEngine.swift`), CSV scris incremental, esantion plafonat pentru PDF, Setari I/O & Memorie in popover-ul de Setari. Windows/Python: `core/io_settings.py`, `scan_files_streaming`/`iter_manifest_batches` (scanare lazy pe disc, nu lista completa in RAM), raport CSV incremental, panou de jurnal plafonat la 2000 de linii (`ui/windows/app.py`), setari de buffer/RAM in optiuni.

**Regula 34:**

- **Certificatul e COMUN tuturor aplicațiilor GDC** — secrete numite
  IDENTIC (`WIN_SELFSIGN_PFX_BASE64`/`WIN_SELFSIGN_PFX_PASSWORD`) în
  fiecare repo, același `.pfx` reîncărcat, NU regenerat per proiect — un
  colaborator care a importat deja `.cer`-ul o dată (ex. la CGConvertor)
  rămâne de încredere pentru orice altă aplicație GDC semnată cu același
  certificat, fără reimport.
- **Aplicare**: la fiecare build de release/actualizare Windows, pe orice
  aplicație din `~/Developer/` care produce un `.exe`/installer Windows —
  aplicată incremental, la următoarea atingere reală a fiecărui repo
  (Regula 11), nu retroactiv peste tot dintr-o sesiune dedicată.
- **Implementare de referință**: CGConvertor (`codesigning/sign-windows.ps1`
  + `.github/workflows/build-windows.yml`, 2026-09-06).

**Status acest repo (2026-09-06): IMPLEMENTAT.** `mac-native/codesigning/
sign-windows.ps1` + `generate-self-signed-cert.ps1` + `README-windows.md`
(nou, alături de fișierele Mac deja existente în același folder — nu
suprascrise). Cei doi pași de semnare (exe WPF + installer final Inno
Setup) adăugați DOAR în `build-windows-wpf.yml` și în job-ul
`build-windows-wpf` din `release.yml` (job-ul vechi `build-windows` nu mai
există — vezi retragerea de mai jos, secțiunea Partea 2). Secretele
(`WIN_SELFSIGN_PFX_BASE64`/`WIN_SELFSIGN_PFX_PASSWORD`) NU sunt încă
încărcate în acest repo — Cristi trebuie să ruleze pasul 2 din
`README-windows.md` (reîncărcarea `.pfx`-ului comun GDC, dacă există deja
din CGConvertor) înainte ca semnarea reală să înceapă să funcționeze; până
atunci, CI-ul continuă nesemnat, fără nicio eroare.
