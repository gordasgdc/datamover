# DataMover — reguli de arhitectură

> **[SYSTEM DIRECTIVE FOR CLAUDE: DO NOT DELETE OR OVERWRITE EXISTING RULES. ONLY APPEND NEW RULES.]**
> Jurnal viu, nu document care se rescrie. La orice actualizare, adaugă la finalul secțiunii potrivite — nu șterge/înlocui reguli vechi decât dacă sunt explicit invalidate de o schimbare reală (și atunci marchează-le **[ÎNVECHIT]** cu motivul, nu le șterge din istoric).

Citit automat de Claude Code la fiecare sesiune în acest repo.

## [PARTEA 1: REGULI GLOBALE ECOSISTEM GDC — identică în toate proiectele GDC]

> Acest bloc e sincronizat manual în `CLAUDE.md`-ul TUTUROR proiectelor din
> `~/Developer/` (CGConvertor, CursorPro, DataMover, GDCPluginManager,
> GDCPluginManagerWin, GDCVault, GDCVaultWin, gdc-plugin-manager-catalog-vendor,
> gdc-plugin-manager-files, gdc-production-manager, gdc-resolve-encoder, și
> orice proiect GDC nou). Dacă modifici o regulă aici, propag-o manual și în
> celelalte 10 fișiere — nu există un fișier partajat/include, fiecare
> `CLAUDE.md` e citit independent per-repo. Vezi jurnalul "Sincronizare
> CLAUDE.md" din secțiunea Partea 2 a fiecărui repo pentru data ultimei
> unificări.

**1. Directoare & structură.** Toate proiectele GDC trăiesc exclusiv în
`~/Developer/<NumeProiect>/`, niciodată în `~/Downloads` sau `~/Desktop`
(curățate automat de CleanMyMac/Hazel pe acest Mac — au șters repo-uri de
sursă în trecut). Niciun repo nou nu se creează/clonează în afara
`~/Developer/`. Certificatele Apple (`.p12`/`.cer`) și orice cheie privată
(`.p8`/`.key`/`.pem`/`.mobileprovision`) stau EXCLUSIV în
`~/Developer/Certificates/` (folder în afara oricărui repo git) — niciodată
comise, indiferent de `.gitignore`.

**2. Securitate — zero secrete în git.** `.git/config` nu conține niciodată
un token în clar în URL-ul remote-ului (`https://user:TOKEN@github.com/...`)
— autentificare exclusiv prin `gh` (credential helper) sau SSH. Orice token
găsit expus se elimină din config imediat; revocarea efectivă din GitHub
Settings e un pas manual al lui Cristi (Claude nu poate revoca un token).
Un secret comis vreodată în istoricul git (verificat cu
`git log --all -p | grep` sau echivalent) trebuie semnalat explicit, nu doar
curățat din starea curentă.

**3. Licențiere & Donație (GDC Plugin Manager / Furnizor).** Toate
aplicațiile standalone GDC folosesc `LicenseCore`/`MachineID` (Ed25519,
aceeași cheie publică hardcodată în tot ecosistemul — copiată byte-for-byte,
NU printr-o dependință de pachet între repo-uri). Probă gratuită implicită:
**15 zile**. Activare manuală prin WhatsApp (ID de mașină pre-completat) →
cod generat din `GenerateSerialView.swift` (Furnizor, `gdcStandaloneProducts`
trebuie să includă `productID`-ul noii aplicații). Valoarea susținerii
aplicației se exprimă EXCLUSIV ca **donație** — sumă implicită de referință
**23 €** dacă nu există alt preț promoțional documentat pentru acea
aplicație — NICIODATĂ cu cuvintele „preț", „cumpără" sau „vânzare" (RO/EN/ES:
niciodată „price"/„buy"/"sale" nici în engleză/spaniolă). Formularea trebuie
să apară clar în: UI-ul aplicației (ecran/pop-up de licență), ghidul PDF, și
orice pagină web dedicată.

**[COMPLETARE 2026-08-26, închide o lacună de scop reală]** Interdicția de
mai sus se aplică ACUM și produselor din catalogul GDC Plugin Manager
(LUT/DCTL/PowerGrade vândute prin marketplace-ul gratuit) — găsit la audit
un card cu buton „Cumpără" și sume afișate brut („378,00 €"). Butonul
devine „Donează" peste tot (RO/EN/ES); suma documentată de furnizor pentru
acel produs (promoția specifică lui, nu neapărat 23 €) rămâne vizibilă, dar
NICIODATĂ lângă cuvântul „preț"/„cumpără"/„vânzare" — decizia anterioară de
scop (marketplace = "relație comercială diferită, nu se aplică") e
INVALIDATĂ explicit. Excepție: tabelele interne ale Furnizorului (ex.
`SalesHistoryView`, coloana „Preț" din registrul de vânzări al lui Cristi)
nu sunt UI orientat spre client — rămân neatinse.

**15. CRM Furnizor — set minim de funcționalități administrative
(2026-08-26).** Panoul de Clienți al Furnizorului (`SalesHistoryView.swift`)
nu rămâne un log rigid — trebuie să ofere: filtrare rapidă pe produs
(dropdown dinamic, nu hardcodat), export 1-click (clipboard sau fișier) al
email-urilor/HWID-urilor din selecția curentă (filtrată), copiere rapidă
per-câmp direct din tabel (fără să deschizi editarea), Licențiere în Masă
(paste o listă de email-uri/machine ID-uri → generează automat câte o
licență per linie, pentru un produs/durată alese o singură dată), și
editare liberă a duratei unei licențe deja generate (Zile/Luni/Ani/
Lifetime). Furnizorul arată versiunea curentă în UI, la fel ca orice
aplicație client — nu e scutit de Regula 7 doar pentru că e un instrument
intern.

**16. Design Web "Shift" — compact, fără spații goale (2026-08-26).**
Completare la Regula 12: paginile de prezentare NU doar adoptă paleta
amber/cupru — trebuie și dense/aerisite corect, nu găunoase. `min-height:
100svh` pe un hero cu conținut scurt lasă spațiu gol enorm pe orice ecran
mai mare — evită-l sau limitează-l (ex. `78svh`); padding-ul secțiunilor
(`section`) rămâne generos dar nu excesiv (60px, nu 90px+). Orice accent
vechi (verde/teal/albastru folosit ca accent PRIMAR, nu ca stare
semantică precum "verificat cu succes") se înlocuiește cu amber/cupru —
o variabilă CSS poate păstra alt NUME istoric (`--scope`, `--accent-copy`)
atât timp cât VALOAREA ei devine amber, ca să nu rescrii zeci de
apariții `var(--x)` din foaia de stil.

**4. Manager de Dependențe (Standard GDC, opt-in).** Aplicația de bază
rămâne lightweight — orice dependință externă opțională/grea (ex. FFmpeg
static) se descarcă LA CERERE, nu bundle-uită implicit dacă poate fi evitat.
Indicator global 🔴/🟢 vizibil în header/meniu: verde doar dacă TOATE
componentele obligatorii (non-opționale) sunt OK; componentele opționale
(ex. Homebrew pe Mac) nu blochează starea verde. Click pe indicator deschide
un panou dedicat ("Verificare & Dependențe Sistem") cu o listă modulară de
componente (model generic `DependencyItem` — id, nume, opțional/obligatoriu,
verificare headless, acțiune, niciodată câmpuri hardcodate per-dependință),
fiecare cu propriul status + buton de acțiune (descărcare automată a unui
binar static, sau copiere comandă de instalare). Verificarea rulează headless
la fiecare deschidere a panoului/meniului, actualizând starea instant.

**5. Instalare Autonomă.** Mac: `.pkg` semnat Developer ID Application +
Installer, notarizat, stapled, cu `pkgbuild --install-location "/"` și
payload la `Applications/<App>.app` — instalare DIRECTĂ în `/Applications`
la dublu-click, fără drag-and-drop manual (verificabil cu
`pkgutil --payload-files`). Windows: installer Inno Setup cu
`DefaultDirName={autopf}\GDC\<App>` (Program Files) sau varianta x86,
scurtături automate Desktop + Start Menu, dezinstalare nativă prin
"Apps & Features" (fără script separat necesar dacă Inno Setup o acoperă).

**6. Packaging Mac — arhivă cu STRICT 3 fișiere.** Orice
`<App>-Mac.zip` livrat clientului conține la rădăcină EXACT: (1)
executabilul/`.pkg`-ul semnat+notarizat+stapled, (2)
`Dezinstalare_<App>.command` (dezinstalare completă: procese, TCC dacă
relevant, `~/Library/Application Support`, `Caches`, `Preferences`,
`Saved Application State`, `Logs`, orice item Keychain scris de aplicație),
(3) `Instructiuni_Utilizare.pdf` (RO/EN/ES). NICIODATĂ hack-uri
`xattr -dr com.apple.quarantine` sau launchere `Instalare_*.command` —
pachetul stapled e acceptat nativ de Gatekeeper. Curățarea unei instalări
vechi se face în `installer/scripts/preinstall` (`pkgbuild --scripts`,
pkill + `rm -rf`), niciodată legat de quarantine.

**7. UI Standard — varianta "Shift".** Temă dark, profesională, inspirată de
paginile de Color din DaVinci Resolve (fundal `#14161A`/`#1A1D22`, accent
cald cupru/amber sau altă culoare distinctă per-aplicație, text `#EDEFF2`).
Număr de versiune vizibil în UI (About/Meniu/Settings/Footer), fără excepție.
Update Checker automat la lansare + verificare manuală, conectat la
`update.json`/GitHub Releases API, cu notificare atât banner discrét CÂT ȘI
pop-up modal (o singură dată per versiune nouă, stare de dismissal comună
între cele două) — un simplu banner nu e suficient. `mandatory: true` în
`update.json` ignoră dismissal-ul anterior.

**8. Documentație PDF — standard ultra-detaliat.** Orice
`Instructiuni_Utilizare.pdf` (RO/EN/ES) se redactează pentru un utilizator
complet începător, zero presupuneri, cu secțiunile relevante aplicației:
(a) Panoul de Dependențe — ce înseamnă 🔴/🟢, pas-cu-pas ce face userul la
roșu (unde dă clic, ce se deschide, ce buton apasă); (b) Homebrew (Mac,
dacă aplicabil) — pași la nivel de acțiune: copiază comanda din aplicație,
deschide Terminal (Spotlight, `⌘+Space`), lipește (`⌘+V`), Enter, apoi
explică parola de Mac cerută (invizibilă la tastare) + Enter din nou;
(c) Fluxul de utilizare + acțiuni post-proces — cum se adaugă
fișiere/date, ce face fiecare buton rezultat; (d) Licență & Donație — trial
gratuit explicit (zile), suma exactă ca donație (niciodată "preț"/"vânzare");
(e) Cum funcționează actualizarea automată — ce înseamnă pop-up-ul de
versiune nouă, ce face butonul „Actualizează acum" vs „Mai târziu", și că
instalarea noii versiuni rămâne un pas asistat (descărcare + reinstalare),
nu un update silențios în fundal.

**9. Checklist obligatoriu la FIECARE release** (păstrat identic cu
"DIRECTIVĂ PERMANENTĂ SUPREMĂ" din jurnalul fiecărui proiect — punctele
1-4 de acolo sunt subsumate integral de punctele 5-8 de mai sus). Site-ul
public al fiecărei aplicații trebuie să pointeze mereu la
`releases/latest/download/...` (HTTP 200 verificat, nu presupus), niciodată
un tag fix.

**10. Comunicare & jurnal.** Fiecare `CLAUDE.md` rămâne un jurnal
append-only (regulile vechi nu se șterg, doar se marchează
**[ÎNVECHIT]** cu motivul dacă sunt explicit invalidate). Răspunsurile
Claude rămân ultra-concise: fără explicații de proces, direct codul/
diff-ul/comenzile și statusul. La orice modificare de cod, comanda exactă
de rebuild local se include la finalul răspunsului.

**11. Sincronizare dinamică a Standardului Master (CONTINUOUS UPDATE,
2026-08-26).** Orice adăugare/modificare/optimizare a unei reguli globale
din ACEASTĂ Partea 1 — indiferent din ce proiect pornește — devine automat
noul Standard Master și TREBUIE propagată manual, în ACELAȘI commit sau
imediat următorul, în `CLAUDE.md`-ul tuturor celorlalte proiecte din
`~/Developer/` (nu doar notată "pentru mai târziu"). Orice aplicație NOUĂ
creată în `~/Developer/` primește Partea 1 (versiunea curentă, completă)
încă din primul `CLAUDE.md` scris pentru ea — nu se pornește niciodată de
la un fișier gol sau parțial. Regula 1 de mai sus ("Dacă modifici o regulă
aici, propag-o manual...") descrie mecanismul; aceasta îl declară
obligatoriu, nu opțional.

**12. Profil Utilizator/HWID în Sidebar, Sistem de Revocare Licențe &
Standard Design Web Mobile/Desktop "Shift" (2026-08-26).**
- **Profil Utilizator opțional, vizibil în sidebar-ul UI** (Mac + Windows,
  pe toate aplicațiile cu licențiere GDC): Nume (sau „Anonim" dacă nu e
  completat), Email, și Machine ID (HWID) — afișate clar, nu ascunse
  într-un submeniu. Portat din modulul Tracker existent (Mac,
  `AnalyticsClient.registerDevice` → Supabase `devices`) — Windows trebuie
  aliniat la aceeași infrastructură, nu una separată.
- **Revocare/blacklist de licențe, prin Supabase** (ACEEAȘI bază de date
  deja folosită de Tracker — niciun backend nou de construit). O licență
  Ed25519 rămâne verificată local (offline-first, nicio schimbare la
  activarea inițială), dar clientul verifică periodic + la lansare (dacă
  există conexiune) un tabel de revocări după `machineID`/serial. **Fail
  OPEN, nu fail closed**: fără conexiune la internet, o licență deja
  activată local CONTINUĂ să funcționeze (nu bricuim un user legitim offline)
  — revocarea se aplică abia la următoarea verificare online reușită.
  Furnizor capătă unelte de revocare instant + editare a perioadei de
  valabilitate a unei licențe existente deja generate.
- **Generare flexibilă de licențe** (Furnizor): selector explicit al
  duratei — Zile / Luni / Ani / Forever (Lifetime) / Valabil până la
  versiunea X — nu doar trial fix + activare permanentă binară.
- **Standard Design Web "Shift"** — orice pagină de prezentare/descărcare
  GDC (`gordas.dev` și paginile dedicate per-aplicație) adoptă design-ul
  dark, minimalist, accent amber/cupru consacrat de CG Convertor
  (`gordas.dev/cg-convertor`) — niciun accent verde vechi sau stil
  nealiniat. Toate paginile trebuie optimizate explicit pentru mobil
  (iOS Safari + Android Chrome), verificat vizual la lățimi de telefon,
  nu doar "responsive by CSS framework".

**13. Update Checker — specificație UX obligatorie (2026-08-26).** La
lansare, aplicația verifică `update.json`/GitHub Releases; dacă versiunea
locală e mai veche, arată un pop-up/modal Shift (nu doar bannerul discret
din Regula 7) cu: numărul noii versiuni, un rezumat scurt al noutăților
(Release Notes, dacă `update.json` le are — câmp opțional, degradează
elegant dacă lipsește), și DOUĂ butoane explicite — **„Actualizează acum"**
(deschide direct link-ul de descărcare a installer-ului/pachetului nou,
`releases/latest/download/...`, și arată userului că trebuie să
instaleze peste versiunea curentă + repornească aplicația — NU e un
self-update silențios, niciun helper nu înlocuiește bundle-ul/exe-ul în
fundal, vezi WARNING-ul deja existent din `UpdateChecker.swift`/`.cs`) și
**„Mai târziu"** (închide fereastra, aceeași stare de dismissal ca
bannerul). Popup-ul apare o singură dată per versiune nouă, cu excepția
`mandatory: true` (reapare la fiecare lansare). Ghidul PDF (Regula 8(e))
trebuie să explice acest flux exact.

**14. Versionare semantică obligatorie la FIECARE schimbare (2026-08-26).**
Orice modificare de cod livrată clientului — oricât de mică — incrementează
numărul de versiune, sincron în TOATE punctele care îl țin (Info.plist Mac,
`.csproj`/`installer.iss` Windows, `docs/update.json`, orice altă constantă
de versiune din acel repo). Format `MAJOR.MINOR.PATCH` (ex. `2.3.1`):
- **PATCH** (ultima cifră, `2.3.0`→`2.3.1`) — orice fix, ajustare, adăugare
  mică sau schimbare care nu rupe compatibilitatea. Cazul implicit, cel mai
  frecvent.
- **MINOR** (cifra din mijloc, `2.3.x`→`2.4.0`) — funcționalitate nouă
  vizibilă (ex. o fază/etapă întreagă ca Panoul de Dependențe sau Profilul
  HWID), fără schimbări radicale de arhitectură.
- **MAJOR** (prima cifră, `2.x.x`→`3.0.0`) — schimbare radicală: rebranding,
  redesign complet de UI, schimbare de arhitectură (ex. sistem nou de
  licențiere), sau orice prag pe care Cristi îl declară explicit "versiune
  majoră".
**De ce**: `UpdateChecker`/`.cs` compară STRICT numărul de versiune din
`update.json` cu cel instalat (`IsNewer`) — înlocuirea unui binar pe un
release existent, PE ACEEAȘI versiune, nu declanșează nicio notificare la
clienții deja instalați (bug real, găsit și reparat 2026-08-26: Windows
Shift UI + Faza 1/3/4 livrate silențios sub `v1.2.22`, fără niciun bump).
Un bump de versiune fără schimbare reală de cod e la fel de greșit ca
schimbarea de cod fără bump — cele două merg mereu împreună, în același
commit.

**17. Orice fișier descărcabil TREBUIE să poarte numărul versiunii în NUMELE
fișierului (2026-08-26).** Nu doar în interiorul aplicației (Regula 14) —
în numele fizic al pachetului: `DataMover-2.5.5.pkg`, nu `DataMover.pkg`;
`GDCPluginManagerSetup-1.2.8.exe`, nu `GDCPluginManagerSetup.exe`. Motiv
direct de la Cristi: probele/build-urile de test se acumulează local (în
`~/Downloads`, `/tmp`, trimise pentru testare) și devin de nerecunoscut
fără versiune în nume — "am o grămadă de descărcări și nu știu ce versiune
sunt, care, ce și cum sunt".
- **Excepție, NU o contrazicere**: mecanismul `releases/latest/download/
  <nume-stabil>` (site-ul, self-updater-ul) are nevoie STRUCTURAL de un
  nume care nu se schimbă niciodată între release-uri — vezi Regula
  Domeniului & Download. Copia asta stabilă (`DataMover.pkg`,
  `GDCPluginManager.pkg`) tot trebuie publicată, DAR ALĂTURI de copia
  versionată, niciodată singură. `build_installer.sh`/`build_app.sh` din
  fiecare repo produc deja ambele — regula asta cere doar ca ambele să
  ajungă mereu pe release, nu doar cea stabilă.
- **Orice fișier construit/descărcat/trimis lui Cristi în afara acestui
  mecanism** (build local de test, artefact de CI descărcat manual,
  fișier trimis prin `SendUserFile`, copie pusă în `/tmp` pentru
  verificare) TREBUIE redenumit explicit cu versiunea înainte de a fi
  oferit — niciodată livrat cu numele generic/stabil, care are sens doar
  ca țintă a unui link fix, nu ca fișier de sine stătător pe disc.

**18. Standard UX/Arhitectură obligatoriu pentru orice aplicație desktop
NOUĂ, de la primul release (2026-08-26).** Stabilit după MediaFlow Monitor
v1.3.0 — patru cerințe care nu mai sunt opționale pentru nicio aplicație
GDC viitoare (Mac și, unde tehnologia o permite, Windows):
- **Mutare automată în `/Applications` (Mac)** — la lansare, dacă bundle-ul
  rulează în afara `/Applications` sau `~/Applications` (tipic: extras
  direct din `.zip`/Downloads, sub App Translocation), aplicația arată un
  prompt nativ ("Doriți să mutați X în Aplicații?") și, la confirmare,
  copiază bundle-ul, relansează din noua locație și mută originalul la
  Coșul de gunoi. Vezi implementarea de referință `AppMover.swift`
  (MediaFlow Monitor) — fără dependință externă (PFMoveToApplicationsFolder
  nu are un port SPM întreținut), doar `NSAlert` + `FileManager`.
- **Fereastră principală redimensionabilă liber**, cu o dimensiune minimă
  de siguranță (`minSize`/`minWidth`+`minHeight`) sub care conținutul nu
  mai e lizibil — nu ferestre cu dimensiune fixă hardcodată.
- **Selector explicit de temă System/Dark/Light**, independent de setarea
  macOS/Windows — unii clienți vor Light chiar și noaptea, alții Dark
  permanent; NU e suficient să urmezi orbește `prefers-color-scheme`/tema
  sistemului. Persistat local (`UserDefaults`/Registry), aplicat imediat
  fără repornire. Vezi `AppTheme.swift`/`ThemeManager` (MediaFlow Monitor).
- **Protocolul de semnare, notarizare, auto-update și integrare GDC
  Manager rămâne cel deja documentat în Regulile 3, 5, 6, 13, 14, 17** —
  regula asta nu introduce un protocol nou, doar reconfirmă că orice
  aplicație nouă îl respectă de la prima versiune publicată, nu "adăugat
  ulterior quando there's time".

**19. Regulă Legală & Packaging (UE/Global) (2026-08-27).**
- **Pagini Web.** Orice landing page nouă sau actualizare de site publicată
  pe `gordas.dev` (sau pe orice site GDC, inclusiv paginile de proiect
  `gordasgdc.github.io/<repo>`) TREBUIE să conțină în footer link-uri către
  `https://gordas.dev/termeni` (Termeni și Condiții),
  `https://gordas.dev/confidentialitate` (Politică de Confidențialitate
  GDPR) și, unde e relevant, `https://gordas.dev/cookie` (Cookie-uri),
  plus o notă scurtă de statut: *"gordas.dev este o platformă administrată
  de dezvoltatori independenți. Aplicațiile și resursele sunt furnizate ca
  atare (AS IS), iar susținerea proiectului se bazează pe contribuții
  opționale de sprijin și donații."* Sursa canonică a acestor 3 pagini
  legale trăiește în `gdc-plugin-manager-catalog-vendor/docs/` — orice alt
  site GDC linkuiește către ele (absolut), nu le duplică.
- **Installere (.pkg macOS / .exe Windows).** Începând cu următoarele
  versiuni/build-uri (NU retroactiv — fără rebuild al aplicațiilor deja
  publicate doar pentru asta), scripturile de instalare
  (`build_installer.sh`/`productbuild` pe Mac, `installer.iss`/Inno Setup
  pe Windows) TREBUIE să includă un pas de acceptare a licenței (License
  Agreement/SLA), bazat pe un fișier `license.rtf`/`license.txt` cu un
  extras din Termeni și Condiții (statut de proiect independent,
  licențiere legată de Machine ID, natura de donație a susținerii,
  limitarea răspunderii "as is"). Utilizatorul trebuie să apese explicit
  "Agree"/"I accept" înainte ca instalarea să se finalizeze.

  **[COMPLETARE 2026-08-27] Consimțământ obligatoriu (Consent Gate), nu
  doar text afișat.** Nu e suficient ca licența să apară — pasul trebuie
  să blocheze efectiv avansarea fără acceptare explicită:
  - **macOS (`productbuild`/Distribution.xml).** Elementul `<license
    file="License.txt" mime-type="text/plain"/>` din `Distribution.xml`
    (deja folosit de `build_installer.sh` în `gdc-plugin-manager-catalog-vendor`
    și `gdc-vault-mac`) e SUFICIENT — pagina nativă de licență a
    installer-ului macOS oferă mereu doar "Agree"/"Disagree", iar
    "Continue" nu apare fără "Agree" apăsat; nu există flag care s-o
    ocolească. Regula practică: orice `Distribution.xml` nou generat
    TREBUIE să păstreze elementul `<license>` — omiterea lui (ex. un
    installer simplificat fără pas de licență) NU e acceptabilă.
  - **Windows (Inno Setup).** Secțiunea `[Setup]` din `installer.iss`
    TREBUIE să seteze `LicenseFile=license.txt` (sau `.rtf`) — Inno Setup
    arată atunci nativ o pagină cu opțiunile radio "I accept the
    agreement" / "I do not accept", cu butonul "Next" dezactivat până la
    alegerea explicită "I accept". (Dacă vreun installer Windows ar trece
    vreodată pe NSIS în loc de Inno Setup, echivalentul e
    `!insertmacro MUI_PAGE_LICENSE` cu `MUI_LICENSEPAGE_CHECKBOX` definit,
    pentru varianta cu bifă explicită.)
  - Fișierul `license.txt`/`.rtf` folosit la acest pas trebuie să conțină
    (măcar rezumat) cele 4 puncte cheie din Termeni: statut independent
    (non-comercial), licențiere Machine ID, natura de donație a
    susținerii, garanție "as is"/limitarea răspunderii — nu doar un MIT
    License generic.

**20. Self-Updater real — obligatoriu, niciodată deschidere de browser/
GitHub (2026-08-27).** Descoperit ca bug real, repetat, pe GDC Vault (Mac
și Windows): un simplu link `releases/latest/download/...` deschis în
browser NU e suficient — utilizatorul tot ajunge pe un tab de
browser/GitHub, ceea ce Cristi consideră inacceptabil ("clientul niciodată
nu trebuie să vadă GitHub"). Orice aplicație desktop GDC (Mac/Windows) cu
proces propriu de rulat TREBUIE să implementeze un Self-Updater REAL, nu
doar un link:
- **Mac.** Descarcă `.pkg`-ul cu `URLSession.download`, cu URL-ul citit
  direct din `assets[]` al ultimului release GitHub (nu hardcodat), apoi
  îl instalează printr-un script bash elevat cu `osascript ... with
  administrator privileges` (promptul NATIV de parolă admin macOS —
  NICIODATĂ `sudo` interactiv sau Terminal vizibil), care rulează
  `installer -pkg ... -target /` și relansează aplicația singur. Vezi
  implementarea de referință `SelfUpdater.swift` (DataMover,
  `gdc-plugin-manager-catalog-vendor`, `GDCVault`).
- **Windows.** Descarcă installer-ul (`.exe`) cu `HttpClient` direct pe
  disc, redenumit cu versiunea (Regula 17), apoi îl lansează
  (`Process.Start(UseShellExecute:true)`) — fereastra NATIVĂ Inno Setup
  apare, NICIODATĂ browserul. Aplicația curentă se închide
  (`Application.Current.Shutdown()`) înainte ca userul să ajungă la pasul
  de copiere din wizard; `[Run] ... Flags: nowait postinstall
  skipifsilent` din `installer.iss` relansează aplicația după instalare —
  nu e nevoie de `AppMutex`/`CloseApplications` suplimentar. Vezi
  `SelfUpdater.cs` (`GDCPluginManagerWin`, `GDCVaultWin`).
- O fereastră minimală de progres (`UpdateProgressWindow`, text + spinner
  indeterminat) e obligatorie cât timp durează descărcarea/instalarea —
  userul nu trebuie să creadă că aplicația a înghețat.
- **WARNING permanent**: pasul efectiv de instalare (promptul de parolă
  admin pe Mac, wizardul Inno pe Windows) NU poate fi verificat automat de
  Claude — cere interacțiune fizică reală cu fereastra de sistem.
  Verificarea automată se oprește la "fișierul s-a descărcat integru,
  HTTP 200" — instalarea + relansarea efectivă TREBUIE confirmată manual,
  o dată, de Cristi, înainte ca fluxul să fie declarat complet dovedit.
- **Excepție arhitecturală, nu o abatere**: aplicații FĂRĂ proces propriu
  de rulat (plugin-uri încărcate de o gazdă terță, ex. un IOPlugin
  DaVinci Resolve) nu pot avea un "self-updater" în acest sens — rămân la
  reinstalare manuală ghidată de PDF (Regula 8), fără relansare automată.
- **Regula 13 (Update Checker) rămâne valabilă pentru DETECTAREA
  versiunii noi** (pop-up, texte, dismissal) — doar acțiunea butonului
  principal se schimbă: NU mai deschide un link, cheamă Self-Updater-ul.

**Status acest repo (2026-08-27): IMPLEMENTAT.** `mac-native/Sources/DataMoverMac/SelfUpdater.swift` — prima implementare din ecosistem, confirmată manual de Cristi. Windows: verifică `core/updater.py` (varianta Python veche) - dacă a fost portat pe orice client nativ nou, aliniază-l la fel.


**21. Memory & I/O Performance — obligatoriu pentru orice aplicatie care
proceseaza date/fisiere/fluxuri mari (2026-08-27).** Descoperit ca bug real
pe DataMover: un transfer de 3 TB (SSD -> HDD) umplea RAM + swap pana la
eroarea nativa macOS "Your system has run out of application memory".
Cauza radacina reala pe Mac (Swift/DataMoverMac): bucla de citire/scriere
in bucati (`FileHandle.read(upToCount:)`) rula pe un thread de fundal FARA
`autoreleasepool` per iteratie — obiectele Objective-C (`NSData`) din
spatele fiecarui `Data` bridge-uit nu se eliberau decat la finalul
INTREGULUI job (GCD creeaza un autorelease pool per bloc dispatch-uit, nu
per iteratie de bucla), deci memoria temporara se acumula neintrerupt pe
toata durata copierii unui fisier urias sau a unui transfer intreg.
Regula, valabila pentru orice aplicatie GDC (Mac/Windows) care citeste,
scrie, copiaza sau proceseaza fisiere/fluxuri de retea/date mari:

- **Zero acumulare in memorie / streaming intai.** Interzisa incarcarea
  completa a unui fisier/array/raspuns de retea mare in RAM (fara
  `Data(contentsOf:)`, `file.read()` fara argument, `shutil.copy2` pe
  fisiere mari, liste Python/array-uri Swift care colecteaza TOATE
  intrarile unei scanari mari). Orice citire/scriere/procesare foloseste
  un buffer FIX, mic (8-32 MB implicit, configurabil - vezi mai jos), care
  se citeste, se scrie si se elibereaza pe rand.
- **Backpressure.** Daca rata de citire/procesare depaseste rata de
  scriere/iesire (SSD -> HDD, retea lenta etc.), cititorul TREBUIE sa se
  incetineasca (citire sincrona, secvential cu scrierea - fara buffer de
  "read-ahead" care ar acumula date nescrise in RAM), NU sa stocheze
  diferenta in memorie/swap. Daca aplicatia are un plafon de memorie
  configurat (vezi mai jos) si il depaseste, face o pauza scurta intre
  fisiere/blocuri pana cand memoria scade, in loc sa continue orbeste.
- **UI & State Throttling.** Interzisa pastrarea in starea aplicatiei
  (RAM) a TUTUROR obiectelor procesate pentru afisare — un istoric/log de
  sute de mii de intrari intr-un `tk.Text`/`NSTextView`/array `@Published`
  neplafonat e o scurgere de memorie reala, nu doar o "UI mare". UI-ul
  primeste doar: contoare agregate (fisiere procesate, bytes transferati,
  viteza curenta) si o fereastra plafonata cu ultimele N evenimente (ex.
  200 de linii) — restul, daca trebuie pastrat, se scrie INCREMENTAL pe
  disc (CSV/log file), nu se tine intr-o lista in memorie pana la final.
  La fel, un raport final (PDF/CSV) nu tine in RAM randul fiecarui fisier
  dintr-un transfer urias doar ca sa-l scrie o singura data la sfarsit -
  CSV-ul se scrie incremental, iar un PDF/raport vizual pastreaza doar un
  esantion plafonat (plus toate erorile).
- **Scanare/recursivitate fara memorie acumulata.** La enumerarea
  recursiva a unui folder mare, nu se construieste o lista/array cu TOATE
  intrarile deodata daca sursa poate avea sute de mii/milioane de fisiere
  — se foloseste un iterator/generator sau o scriere incrementala pe disc
  (manifest), citit apoi in loturi (batch de 500-1000), ca memoria de varf
  sa ramana plafonata indiferent de dimensiunea sursei.
- **Auto-Release & eliberare explicita in bucle mari.** Pe macOS/Swift,
  orice bucla `while`/`for` care citeste/scrie/proceseaza fisiere mari pe
  un thread de fundal (`DispatchQueue.global`) foloseste `autoreleasepool { }`
  EXPLICIT per iteratie — GCD NU dreneaza automat un pool intre iteratiile
  unei bucle sincrone in interiorul unui singur bloc dispatch-uit. Pe
  Python/alte platforme, echivalentul e eliberarea explicita a
  buffer-elor/resurselor unmanaged (context manageri `with`, `close()`
  explicit) - nu te baza pe garbage collection amanata pentru resurse care
  cresc proportional cu volumul de date procesat.
- **Resource Limits & configurabilitate.** Orice aplicatie care proceseaza
  volume mari de date expune in Setari: (a) dimensiunea buffer-ului de
  citire/scriere (ex. 4/8/16/32/64 MB, implicit 8 MB), si (b) un plafon
  orientativ de memorie a aplicatiei (ex. 512 MB / 1 GB / 2 GB / 4 GB /
  fara limita), peste care se aplica backpressure-ul descris mai sus.
  Plafonul e o limita ORIENTATIVA la nivel de proces (nu un cgroup impus
  de OS) - scopul e sa incetineasca sursa cand memoria creste anormal, nu
  sa garanteze un maxim absolut.
- **Implementare de referinta**: `DataMover` — `IOSettings.swift` +
  fix-ul de `autoreleasepool` din `copyFileCancelable`/`genericHash`
  (`OffloadEngine.swift`, Mac), si `core/io_settings.py` +
  `scan_files_streaming`/`iter_manifest_batches` + raport CSV incremental
  (`core/offload_engine.py`, Windows/Python). Orice aplicatie GDC noua sau
  modificata care atinge fisiere/fluxuri mari respecta acest standard de
  la urmatoarea ei actualizare, nu doar DataMover.

**Status acest repo (2026-08-27): IMPLEMENTAT — repo de origine.** Mac: `IOSettings.swift` + `autoreleasepool` in `copyFileCancelable`/`genericHash` (`OffloadEngine.swift`), CSV scris incremental, esantion plafonat pentru PDF, Setari I/O & Memorie in popover-ul de Setari. Windows/Python: `core/io_settings.py`, `scan_files_streaming`/`iter_manifest_batches` (scanare lazy pe disc, nu lista completa in RAM), raport CSV incremental, panou de jurnal plafonat la 2000 de linii (`ui/windows/app.py`), setari de buffer/RAM in optiuni.

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
