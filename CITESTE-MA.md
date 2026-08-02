# ShotPut Lite — Ghid detaliat

Acest fișier conține instrucțiunile complete de instalare, compilare,
publicare și utilizare. Pentru un rezumat rapid și link-urile de
descărcare, vezi [README.md](README.md).

## Funcții

- **Iconiță personalizată** — inclusă pentru `.app` (Mac) și `.exe` (Windows), generată automat la compilare
- **Drag-and-drop** — tragi direct folderul sursă (cardul) peste aplicație, la fel și pentru destinații (poți trage mai multe foldere deodată); butoanele "Alege manual..." rămân disponibile ca alternativă
- **Copiere simultană** către oricâte destinații (drive extern, NAS, folder local etc.)
- **Model de securitate selectabil** — MD5 (rapid, standard), SHA-1, SHA-256, SHA-512 (maxim de siguranță) sau doar verificare de dimensiune (cel mai rapid, fără checksum)
- **Verificare** pentru fiecare fișier, conform modelului ales
- **Progres separat "Copiere" / "Verificare"** — vezi exact în ce fază e fiecare destinație
- **Bare de progres individuale per destinație** — procent și viteză (MB/s) proprii, plus buton 📂 pentru a deschide direct folderul rezultat al fiecărei destinații
- **Denumire automată a folderului** de destinație: `Data_Proiect_Card` (ex: `2026-07-21_NuntaAna_CardA`)
- **Rapoarte CSV + PDF** per destinație, cu status colorat (OK / Nepotrivire / Eroare / Sărit) și sumar, denumite cu data și ora exactă (`offload_report_2026-07-21_14-32-05.csv`)
- **Log centralizat** (`offload_master.log`, în folderul aplicației) — un istoric text, pe termen lung, al tuturor sesiunilor de offload (pornire, finalizare, erori) — util pentru audit, separat de rapoartele per destinație
- **Notificări native** (Notification Center pe macOS, Toast pe Windows)
- **Detectare automată a cardurilor/drive-urilor montate**, cu buton de reîmprospătare
- **Excludere fișiere/extensii** personalizabilă
- **Verificare spațiu liber** înainte de start, și periodic (la fiecare 10 fișiere) în timpul copierii — te avertizează în jurnal dacă a mai rămas sub 1GB liber pe o destinație
- **Buton de anulare** — poți opri copierea în siguranță în orice moment
- **"Sări peste fișiere identice"** — la re-rulări, nu recopiază ce e deja verificat corect
- **Reluare automată la erori** — checkpoint salvat pe disc, continui exact de unde ai rămas
- **Tema întunecată (dark mode)** — comutabilă din interfață, salvată automat
- **Tooltip-uri explicative** — iconițe "?" lângă setările mai complexe
- **Modul Monitorizare** — rulează în fundal (system tray / menu bar), detectează automat un card nou și pornește offload-ul cu ultimele setări salvate
- **Ejectare automată a cardului sursă** după finalizare (doar pe Mac, opțional, doar dacă nu au existat erori)
- **Scurtături de tastatură**: `Ctrl/Cmd+O` alege sursa, `Ctrl/Cmd+D` adaugă destinație, `Ctrl/Cmd+Enter` începe offload-ul, `Ctrl/Cmd+Q` închide aplicația
- **Fereastră "Despre..."** — creditele autorului, cu linkuri
- **Setările se salvează automat** (proiect, card, destinații, excluderi, model de verificare, temă, ejectare card) — nu mai retastezi de fiecare dată

## Structura fișierelor

```
ShotPutLite/
├── main.py                                 <- interfata grafica
├── offload_engine.py                       <- logica de copiere/verificare/scanare
├── pdf_report.py                            <- generarea rapoartelor PDF
├── config.py                                <- salvarea automata a setarilor
├── theme.py                                 <- tema intunecata/luminoasa
├── tooltip.py                               <- iconite "?" cu tooltip-uri explicative
├── checkpoint.py                            <- checkpoint pentru reluare automata la erori
├── tray_monitor.py                          <- modul Monitorizare (system tray / menu bar)
├── update_config.py                         <- versiune si configurari pentru self-update
├── updater.py                                <- logica de self-update (verificare/descarcare/instalare)
├── Porneste ShotPut Lite.command            <- lansator pentru Mac (dublu-click)
├── Porneste ShotPut Lite (Windows).bat      <- lansator pentru Windows (dublu-click)
├── setup.py                                 <- optional, pentru pachetare .app (Mac)
├── ShotPutLite.icns                         <- iconita gata de folosit pentru Mac
├── ShotPutLite.ico                          <- iconita gata de folosit pentru Windows
├── icon_master.png                          <- iconita la rezolutie mare (referinta/arhiva)
├── docs/index.html                          <- pagina web de prezentare (GitHub Pages)
├── docs/update.json                         <- fisierul citit de aplicatie pentru self-update
├── LICENSE                                   <- licenta MIT
├── .github/workflows/build-windows.yml      <- compileaza .exe automat in cloud, la fiecare push
├── .github/workflows/build-mac.yml          <- compileaza .app automat in cloud, la fiecare push
├── .github/workflows/release.yml            <- publica Release oficial (Mac+Windows+Sursa), la fiecare tag
├── offload_master.log                       <- (generat automat la prima rulare) jurnal centralizat
└── README.md / CITESTE-MA.md                <- prezentare rapida / acest ghid detaliat
```

Toate fișierele `.py` trebuie să rămână împreună, în același folder,
indiferent de sistemul de operare.

---

## Instalare pe Mac

**Cerințe:**

- macOS (orice versiune recentă)
- Python 3 (majoritatea Mac-urilor moderne îl au deja; altfel:
<https://www.python.org/downloads/macos/>)
- Dacă la pornire apare eroare legată de "tkinter": `brew install python-tk`

**Pornire (din sursă):**

1. Copiază tot folderul `ShotPutLite` pe Mac.
2. Dublu-click pe **"Porneste ShotPut Lite.command"**.
   - Dacă macOS blochează fișierul: click-dreapta pe fișier → Open →
     confirmă "Open" în fereastra de avertizare. Se face o singură dată.
3. La prima rulare, aplicația își creează automat un mediu Python izolat
   (`.venv`) și instalează acolo `reportlab`, `tkinterdnd2` și `plyer` —
   fără să atingă Python-ul de sistem.
4. Se deschide fereastra aplicației.

**Modul Monitorizare** necesită în plus `pystray` și `pillow`:
```
pip install pystray pillow
python3 tray_monitor.py
```
Build-urile compilate (`.app`/`.pkg`) includ deja un executabil însoțitor
("ShotPut Lite Monitor") pentru asta — vezi butonul "Pornește modul
Monitorizare..." din aplicație.

### Opțional: compilare automată în cloud (GitHub Actions)

`py2app`/`PyInstaller` construiesc doar pentru sistemul pe care rulează,
deci nu poți crea un `.exe` direct de pe Mac local — dar poți folosi
GitHub Actions, care compilează automat pentru ambele sisteme, în cloud,
gratuit. Fișierele de configurare (`.github/workflows/*.yml`) sunt deja
incluse în acest folder.

**Pași (de pe Mac, din Terminal):**

```bash
cd ShotPutLite
git init
git add .
git commit -m "Prima versiune ShotPut Lite"
git branch -M main
git remote add origin https://github.com/NUMELE_TAU/NUMELE_REPO.git
git push -u origin main
```

De îndată ce faci `git push`, GitHub compilează automat, în paralel,
`.app`-ul pentru Mac și `.exe`-ul pentru Windows. Urmărește progresul în
tab-ul **"Actions"** al repo-ului (~2-3 minute), apoi descarcă rezultatele
de la secțiunea **"Artifacts"** a rulării terminate.

De fiecare dată când modifici codul și faci `git push` din nou, se
generează automat o versiune nouă — nu trebuie să repeți pașii de mai sus.

### Alternativ: `.app` pentru Mac, local, fără cloud

```bash
cd ShotPutLite
python3 -m venv .venv-build
source .venv-build/bin/activate
pip install py2app pyinstaller reportlab tkinterdnd2 plyer pystray pillow
python3 setup.py py2app
pyinstaller --onefile --name "ShotPut Lite Monitor" tray_monitor.py
deactivate
```

Rezultatul apare în `dist/ShotPut Lite.app` (și `dist/ShotPut Lite
Monitor` pentru modulul de monitorizare). Le poți muta pe amândouă în
`/Applications`.

### Varianta `.pkg` (instalator, cu curățare automată de carantină)

Build-ul din cloud (workflow-ul de Release) produce automat un instalator
`ShotPut-Lite-Mac-Installer.pkg` — dublu-click deschide fereastra clasică
de instalare macOS, care copiază aplicația (și modulul de Monitorizare) în
`/Applications` și rulează automat un script ce curăță orice steag de
carantină de pe ele.

**De reținut:** `.pkg`-ul nu elimină avertismentul inițial de la
Gatekeeper — la prima deschidere a instalatorului însuși tot apare
mesajul "de la un dezvoltator neidentificat" (aceeași aprobare descrisă
mai jos, dar făcută o singură dată, pe instalator). Ce câștigi cu
`.pkg`-ul: instalare automată în `/Applications`, și — odată instalat —
aplicația nu mai cere niciodată nicio aprobare ulterioară.

Singurul mod de a elimina complet avertismentul inițial (inclusiv pe
instalator) e semnarea + notarizarea cu un cont Apple Developer plătit
($99/an).

### Aprobarea `.app`-ului nesemnat (o singură dată per Mac)

**Metoda 1:** Click-dreapta pe `ShotPut Lite.app` → **"Open"** → în
avertisment, apasă **"Open"**.

**Metoda 2:** System Settings → Privacy & Security → derulează jos →
buton **"Open Anyway"** lângă mesajul despre `ShotPut Lite.app`.

**Metoda 3 (Terminal):**
```bash
xattr -cr "/Applications/ShotPut Lite.app"
```

---

## Instalare pe Windows

**Cerințe:**

- Windows 10 sau 11
- Python 3, de pe <https://www.python.org/downloads/windows/>
  - Bifează **"Add python.exe to PATH"** la instalare.

**Pornire (din sursă):**

1. Copiază tot folderul `ShotPutLite` pe calculator.
2. Dublu-click pe **"Porneste ShotPut Lite (Windows).bat"**.
   - Dacă SmartScreen avertizează: "More info" → "Run anyway".
3. La prima rulare, aplicația își creează automat un mediu Python izolat
   (`.venv`) și instalează dependințele necesare.
4. Se deschide fereastra aplicației.

### Note specifice Windows

- Discul `C:\` e exclus automat din lista de volume detectate.
- Notificările folosesc Windows Toast Notifications.
- Opțiunea de ejectare automată a cardului e disponibilă **doar pe Mac** — pe Windows, ejectarea în siguranță a unui drive extern necesită API-uri
  suplimentare (nu e implementată încă).

### Opțional: compilare `.exe`, local, fără cloud

```
cd ShotPutLite
python -m venv .venv-build
.venv-build\Scripts\activate
pip install pyinstaller reportlab tkinterdnd2 plyer pystray pillow
pyinstaller --onefile --windowed --name "ShotPut Lite" --icon=ShotPutLite.ico main.py
pyinstaller --onefile --windowed --name "ShotPut Lite Monitor" --icon=ShotPutLite.ico tray_monitor.py
deactivate
```

Rezultatul apare în `dist\ShotPut Lite.exe` și `dist\ShotPut Lite
Monitor.exe`.

---

## Publicare oficială (GitHub Releases — Mac + Windows + Sursă)

```bash
cd ShotPutLite
git tag v1.0.0
git push origin v1.0.0
```

Declanșează automat build-ul pentru ambele platforme, apoi creează o
pagină de Release la `https://github.com/gordasgdc/shotput-lite/releases`, cu:

- `ShotPut-Lite-Mac.zip` — `ShotPut Lite.app` + `ShotPut Lite Monitor`
- `ShotPut-Lite-Mac-Installer.pkg` — instalator recomandat
- `ShotPut-Lite-Windows.zip` — `ShotPut Lite.exe` + `ShotPut Lite Monitor.exe`
- **Source code (zip / tar.gz)** — generate automat de GitHub

Pentru o versiune nouă, repeți doar cu alt număr de tag:
```bash
git add .
git commit -m "Descrierea modificarilor"
git push
git tag v1.0.1
git push origin v1.0.1
```

Dacă greșești un tag și vrei să-l refaci:
```bash
git tag -d v1.0.0
git push origin :refs/tags/v1.0.0
```

---

## Cum îl folosești

1. **Sursa** — tragi folderul cardului peste câmpul de sursă, alegi din
   "Volume detectate automat", sau apeși "Alege manual..." (`Ctrl/Cmd+O`).

2. **Nume proiect / Etichetă card** — ex: `NuntaAna` / `CardA` → folderul
   rezultat: `2026-07-21_NuntaAna_CardA`.

3. **Opțiuni de copiere** — model de securitate (iconițele "?" explică
   fiecare opțiune), listă de excluderi, "Sări peste fișiere identice",
   și (doar pe Mac) "Ejectează cardul sursă după finalizare".

4. **Destinații** — tragi unul sau mai multe foldere, sau apeși "Adaugă
   destinație..." (`Ctrl/Cmd+D`). Copiere simultană, cu bară de progres +
   viteză proprie pentru fiecare, plus buton 📂 pentru a deschide direct
   folderul rezultat.

5. **"Începe offload-ul"** (`Ctrl/Cmd+Enter`). Avertizare automată dacă
   spațiul liber pare insuficient, verificat din nou periodic în timpul
   copierii.

6. Jurnalul arată status per fișier, plus progres separat
   "Copiere"/"Verificare". Poți apăsa "Anulează" oricând.

7. Dacă offload-ul a fost întrerupt, butonul "Reia ultima copiere
   neterminată..." continuă exact de unde ai rămas.

8. La final: notificare nativă, rapoarte CSV + PDF cu timestamp exact în
   fiecare folder de destinație, și o intrare nouă în `offload_master.log` (istoric centralizat, pentru audit).

9. **Modul Monitorizare** — pornește aplicația în fundal (tray/menu bar),
   detectând automat carduri noi și pornind offload-ul cu ultimele setări.

10. **"Despre..."** — creditele autorului, cu linkuri către GitHub,
    Facebook și YouTube.

`Ctrl/Cmd+Q` închide aplicația din orice moment.

## Actualizări automate

ShotPut Lite poate verifica și instala automat versiuni noi, direct din
aplicație — **doar în versiunea compilată** (`.app`/`.exe`). Dacă rulezi
din sursă (`python3 main.py`), aplicația verifică versiunea la fel, dar
nu instalează automat — din siguranță, ca să nu riște să suprascrie
interpretul Python de pe disc. În acest caz, actualizezi manual cu `git
pull` (vezi mai sus).

### Cum funcționează

1. Apasă butonul **"🔍 Verifică actualizări"** din bara de sus
2. Aplicația citește un fișier JSON mic, găzduit static, care anunță cea
   mai recentă versiune disponibilă
3. Dacă există o versiune nouă, ești întrebat dacă vrei să actualizezi
4. **Pe Windows**: se descarcă `.zip`-ul, se extrage, iar un script
   auxiliar așteaptă ca aplicația să se închidă, apoi înlocuiește
   `.exe`-ul curent și repornește aplicația automat
5. **Pe Mac**: se descarcă `.pkg`-ul oficial și se instalează folosind
   fereastra **nativă** macOS de parolă administrator (aceeași pe care o
   vezi la orice instalator obișnuit) — nu se deschide Terminal
6. Aplicația se repornește cu versiunea nouă

### Fișierul de actualizare (`update.json`)

Aplicația verifică:
```
https://gordasgdc.github.io/shotput-lite/update.json
```

Găzduit din folderul `docs/` al acestui repo, prin GitHub Pages (Settings
→ Pages → Source: branch `main`, folder `/docs`).

**IMPORTANT — la fiecare versiune nouă publicată, trebuie actualizate
manual DOUĂ locuri**, pe lângă tag-ul de Release:

1. `update_config.py` → `APP_VERSION = "X.Y.Z"` (sursa unică de adevăr —
   `setup.py` o citește automat de aici, deci **nu** mai trebuie
   modificată separat)
2. `docs/update.json` → câmpurile `"version"`, `"changes"`,
   `"release_date"`

Dacă uiți să actualizezi `docs/update.json`, aplicația va continua să
raporteze "ai deja ultima versiune" chiar dacă ai publicat un Release nou
pe GitHub — cele două lucruri sunt independente.

### Depanare

Dacă actualizarea eșuează:
- Verifică conexiunea la internet
- Pe Mac, pentru instalarea `.pkg`, ai nevoie de parola de administrator
  a Mac-ului respectiv (nu de un cont Apple Developer sau altceva)
- Pe Windows, antivirusul poate bloca temporar scriptul auxiliar de
  actualizare — permite-i excepție dacă se întâmplă asta
- Dacă rulezi din sursă (`python3 main.py`), actualizarea automată e
  dezactivată intenționat — vezi mai sus

## Pentru echipă

Distribuie folderul `ShotPutLite` fiecărui membru — Mac sau Windows,
fiecare folosește lansatorul potrivit sistemului lui. Fără licențe sau
activări — rulează local, fără cont, fără internet (cu excepția
instalării unice a dependințelor).
