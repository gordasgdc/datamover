# DataMover — arhitectură și contracte de integritate

Sursa de adevăr pentru produs: **aplicația macOS nativă** (`mac-native/`,
SwiftUI) și **clientul Windows** (`windows-native/`, WPF/.NET 8). Codul Python
(`core/`, `ui/`, `main.py`) e varianta veche; nu mai e livrat ca aplicație
principală și nu definește comportamentul.

## Straturi (macOS)

| Strat | Unde | Ce conține |
|---|---|---|
| Domain | `Domain/TransferDomain.swift` | Faze, nivelul verificării, verdicte per destinație și global, fișiere parțiale. Pur, fără I/O. |
| Transfer Core | `FanOutCopier.swift`, `TransferCore/Durability.swift`, `TransferCore/Checkpoint.swift`, scanare/hash în `OffloadEngine.swift` | Citire unică a sursei, scriere în N destinații, hash în flux, flush, confirmare atomică, identitatea sursei. |
| Workflow | `Workflow/Preflight.swift`, `Workflow/JobSettings.swift`, `OffloadRunner` | Verificări înainte de pornire, setările jobului, orchestrare, reîncercare. |
| Per destinație | `DestinationContext.swift` | Contoare, CSV, MHL, checkpoint, rapoarte — independente pentru fiecare destinație. |
| Reporting | `MHLWriter.swift`, `HTMLReport`, `writePDFReport` | CSV incremental, PDF/HTML cu eșantion plafonat, MHL. |
| Design System | `DesignSystem/DMTheme.swift`, `DesignSystem/DesignGallery.swift` (DEBUG) | Culori semantice light/dark, tipografie, spațiere, layout, stări tipizate, galerie. |
| Features/UI | `Features/Prepare`, `Features/Transfer`, `Features/Settings`, `ContentView.swift` | Pregătire, monitor, rezultat, jurnal, Settings. |
| Infrastructure | `LicenseManager`, `UpdateChecker`, `SelfUpdater`, `CloudSyncService`, `DiagnosticLog` | Licență, actualizări, cloud, jurnal pe disc. |

`OffloadEngine.swift` și `ContentView.swift` rămân mari; extragerea continuă
progresiv, numai cu teste care acoperă partea mutată.

## Contractul de copiere

1. Sursa se deschide **doar pentru citire**. Nimic din aplicație nu scrie,
   mută sau șterge în sursă.
2. Fiecare fișier se scrie în `.<nume>.dmpart`, lângă destinația finală.
3. După ultima bucată: **flush obligatoriu** (politica de mai jos).
4. Fișierul e **confirmat** doar dacă: octeții scriși = octeții citiți =
   mărimea de la scanare, sursa nu și-a schimbat mărimea/data în timpul
   citirii, iar checksum-ul destinației = checksum-ul sursei (în afară de
   modul „doar număr de octeți”).
5. Doar un fișier confirmat primește numele final, prin înlocuire atomică
   (`rename(2)` pe macOS; `MoveFileEx` cu `REPLACE_EXISTING|WRITE_THROUGH`
   pe Windows).
6. Orice altceva (nepotrivire, eroare, anulare) șterge parțialul; un fișier
   final preexistent rămâne neatins.
7. O destinație care eșuează își golește coada și nu blochează cititorul
   sau celelalte destinații (test determinist pe ambele platforme).

## Politica de flush (ce se garantează, realist)

| Pas | macOS | Windows | La eșec |
|---|---|---|---|
| Fișier de date | `F_FULLFSYNC`; doar dacă volumul îl refuză ca nesuportat (`ENOTSUP`/`EINVAL`/`ENOTTY`) → `fsync` | `FileStream.Flush(true)` (`FlushFileBuffers`) | Fișier **neconfirmat**, errno păstrat. O eroare reală a `F_FULLFSYNC` nu cade pe `fsync`. |
| Folder după redenumire | `F_FULLFSYNC`/`fsync` pe folder, **obligatoriu unde e acceptat**; „nesuportat” e consemnat în jurnal | redenumire write-through | Fișier raportat **neconfirmat** (conținutul e scris, persistența numelui nu e dovedită). |
| Checkpoint | temp + flush + `rename` | temp + `Flush(true)` + `MoveFileEx` write-through | **Best-effort, consemnat**: checkpoint-ul e o optimizare, nu o dovadă. |

`F_FULLFSYNC` cere dispozitivului să-și golească cache-ul; dacă firmware-ul
respectă cererea nu poate fi verificat din aplicație. `fsync` (rezerva) nu
cere asta. Nivelul obținut efectiv e scris în jurnal per destinație.

## Niveluri de verificare (niciodată amestecate în rapoarte)

| Nivel | Ce se verifică |
|---|---|
| Doar număr de octeți | Octeții scriși = octeții citiți. Nu detectează conținut diferit. |
| Checksum în flux (implicit) | Sursa și fiecare copie, calculate din aceleași date, în momentul scrierii. Confirmă că datele trimise spre fiecare destinație sunt identice cu cele citite. |
| Checksum în flux + recitire | În plus, fiecare copie se recitește separat prin sistemul de fișiere, cu `F_NOCACHE` cerut, și se compară cu sursa. Paginile deja în memorie sau cache-ul intern al discului pot servi totuși citirea; dacă volumul refuză `F_NOCACHE`, jurnalul o spune. Nu e o dovadă a mediului fizic. |

Rapoartele (PDF/HTML) poartă algoritmul **și** nivelul. Un fișier existent
deja la destinație, cu aceeași mărime, e recitit și comparat cu sursa
înainte de a fi considerat „deja existent”.

## Reluare și checkpoint (schema 3, ambele platforme)

- Checkpoint-ul conține identitatea sursei (căi canonice, volum, SHA-256
  peste „cale · mărime · mtime”, nr. fișiere), amprenta „mărime:mtime” și
  **dovada per fișier confirmat**: checksum-ul sursei și al destinației,
  cu verdictul `checksum` (sau `size` în modul „doar octeți”).
- Metadata poate doar **respinge** rapid: schemă veche (1–2), fișier
  corupt, alt folder, alt algoritm, altă identitate, stări necunoscute,
  checksum absent sau malformat → checkpoint ignorat, motiv în jurnal.
- Metadata **nu acordă niciodată** verdictul. La reluare, un fișier prezent
  la destinație cu mărimea sursei e recitit: sursa curentă trebuie să dea
  checksum-ul salvat (dacă există dovadă validă), iar destinația recitită
  trebuie să dea același checksum. Orice diferență → recopiere prin
  `.dmpart`, cu motivul consemnat.
- Modul „doar octeți” nu are dovadă de conținut: la reluare totul se
  recopiază.
- Costul: reluarea citește sursa și destinația fișierelor deja copiate (nu
  le rescrie). E prețul verdictului byte-safe.

## Verdicte

Per destinație: verificat · verificat cu avertismente (reîncercări
reușite) · neconfirmat · anulat. Global: succes · succes cu avertismente ·
eșec parțial · eșec · anulat. O singură destinație neconfirmată exclude
„succes”. Ejectarea automată cere succes la toate destinațiile.

## Preflight

`Preflight.check` compară căile **canonice** (symlink-uri rezolvate, pe
componente): blochează destinația = sursa, destinația în sursă, sursa în
destinație, destinații duplicate sau imbricate, căi lipsă sau fără drept de
scriere; avertizează la destinație pe același volum cu sursa și la sursă
symlink. Rulează în interfață și din nou în `OffloadRunner.start`.

## Verificare

```bash
scripts/preflight.sh            # versiuni, git, diff --check, build+teste Mac (debug+release),
                                # localizare, design audit, build Windows + verificări C#
scripts/preflight.sh --online   # plus linkurile publice (HEAD); 404 = eșec, nu avertisment
scripts/design-audit.sh         # ratchet: literale vizuale ≤ baseline, 0 în fișiere noi
```

Testele (`mac-native/Tests`, `windows-native/DataMover.CoreChecks`) rulează
exclusiv în directoare temporare, cu date sintetice.

## Ce NU e acoperit încă

- Disc plin real, sleep, scoaterea fizică a unui disc în timpul scrierii:
  simulate doar prin erori injectate (writer care eșuează, flush care
  eșuează), nu pe hardware.
- Windows: logica de checkpoint e verificată la nivel de politică
  (`CheckpointStore`, `RevalidationPolicy`), nu printr-un transfer complet
  (`OffloadRunner` depinde de WPF/QuestPDF). Interfața Windows nu are
  panourile noi și nu a fost verificată vizual.
