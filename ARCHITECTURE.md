# DataMover — arhitectură și contracte de integritate

Sursa de adevăr pentru produs: **aplicația macOS nativă** (`mac-native/`,
SwiftUI) și **clientul Windows** (`windows-native/`, WPF/.NET 8). Codul Python
(`core/`, `ui/`, `main.py`) e varianta veche; nu mai e livrat ca aplicație
principală și nu definește comportamentul.

## Straturi (macOS)

| Strat | Unde | Ce conține |
|---|---|---|
| Domain | `Domain/TransferDomain.swift` | Faze, adâncimea verificării, verdicte per destinație și global, fișiere parțiale. Pur, fără I/O. |
| Transfer Core | `FanOutCopier.swift`, `OffloadEngine.swift` (scanare, hash, checkpoint) | Citire unică a sursei, scriere în N destinații, hash în flux, flush fizic, confirmare atomică. |
| Workflow | `Workflow/Preflight.swift`, `Workflow/JobSettings.swift`, `OffloadRunner` | Verificări înainte de pornire, setările jobului, orchestrare, reîncercare. |
| Per destinație | `DestinationContext.swift` | Contoare, CSV, MHL, checkpoint, rapoarte — independente pentru fiecare destinație. |
| Reporting | `MHLWriter.swift`, `HTMLReport`, `writePDFReport` | CSV incremental, PDF/HTML cu eșantion plafonat, MHL. |
| Design System | `DesignSystem/DMTheme.swift` | Culori semantice light/dark, tipografie, spațiere, componente de stare. |
| Features/UI | `Features/Prepare`, `Features/Transfer`, `Features/Settings`, `ContentView.swift` | Pregătire, monitor, rezultat, jurnal, Settings. |
| Infrastructure | `LicenseManager`, `UpdateChecker`, `SelfUpdater`, `CloudSyncService`, `DiagnosticLog` | Licență, actualizări, cloud, jurnal pe disc. |

`OffloadEngine.swift` și `ContentView.swift` rămân mari; extragerea continuă
progresiv, numai cu teste care acoperă partea mutată.

## Contractul de copiere (Mac și Windows)

1. Sursa se deschide **doar pentru citire**. Nimic din aplicație nu scrie,
   mută sau șterge în sursă.
2. Fiecare fișier se scrie în `.<nume>.dmpart`, lângă destinația finală.
3. După ultima bucată: **flush fizic** (`F_FULLFSYNC` pe macOS, cu `fsync`
   ca rezervă doar la `ENOTSUP`; `FlushFileBuffers` pe Windows).
4. Fișierul e **confirmat** doar dacă: octeții scriși = octeții citiți =
   mărimea de la scanare, sursa nu și-a schimbat mărimea/data în timpul
   citirii, iar checksum-ul destinației = checksum-ul sursei (în afară de
   modul „doar mărime”).
5. Doar un fișier confirmat primește numele final, prin `rename` atomic
   (care înlocuiește un eventual fișier vechi). Pe macOS urmează flush pe
   folderul părinte.
6. Orice altceva (nepotrivire, eroare, anulare) șterge parțialul; un fișier
   final preexistent rămâne neatins.
7. O destinație care eșuează nu oprește și nu blochează celelalte.

## Niveluri de verificare (niciodată amestecate în rapoarte)

| Nivel | Ce dovedește |
|---|---|
| Doar mărime | Numărul de octeți scriși coincide. Nu detectează conținut corupt. |
| Checksum în flux (implicit) | Octeții primiți de sistemul de fișiere al destinației sunt identici cu cei citiți din sursă (același flux, hash calculat la scriere). |
| Checksum + recitire (opțional) | În plus, destinația se recitește de pe disc, ocolind cache-ul (`F_NOCACHE`), după flush. |

Un fișier existent deja la destinație, cu aceeași mărime, e recitit și
comparat cu sursa înainte de a fi considerat „deja existent”.

## Reluare și checkpoint

- `offload_checkpoint.json` se scrie atomic (tmp + flush + `rename`).
- La reluare e acceptat doar dacă are același folder și același model de
  verificare; un fișier corupt e respins, cu motivul în jurnal.
- Un fișier marcat „ok” în checkpoint trebuie să existe încă, cu mărimea
  sursei; altfel se recopiază.

## Verdicte

Per destinație: verificat · verificat cu avertismente (au existat
reîncercări reușite) · neconfirmat · anulat. Global: succes · succes cu
avertismente · eșec parțial · eșec · anulat. O singură destinație
neconfirmată exclude „succes”. Ejectarea automată a cardului cere succes
(cu sau fără avertismente) la toate destinațiile.

## Preflight

`Preflight.check` compară căile **canonice** (symlink-uri rezolvate, pe
componente, nu pe text): blochează destinația = sursa, destinația în sursă,
sursa în destinație, destinații duplicate sau imbricate, căi lipsă, fără
drept de scriere; avertizează la destinație pe același volum cu sursa și la
sursă symlink. Rulează în interfață (înainte de Start) și din nou în
`OffloadRunner.start`.

## Verificare

```bash
scripts/preflight.sh            # versiuni, git, build + teste Mac, localizare, build Windows + verificări C#
scripts/preflight.sh --online   # plus linkurile publice (doar cereri HEAD)
```

Testele (`mac-native/Tests`, `windows-native/DataMover.CoreChecks`) rulează
exclusiv în directoare temporare.

## Ce NU e acoperit încă

- Disc plin real (testat doar un eșec de scriere pe folder doar-citire).
- Sleep al sistemului și deconectare fizică a unui disc în mijlocul unui
  fișier — tratate de cod (eroare per destinație), nesimulate în teste.
- Interfața Windows nu are încă panourile noi (pregătire, monitor per
  destinație, rezultat); are motorul și verdictul noi.
