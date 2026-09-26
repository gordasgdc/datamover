# Windows: migrarea clienților vechi (Python) către aplicația WPF

## Problema (blocaj de distribuție, nerezolvat)

Clienții Windows cu aplicația veche (Python, ≤ 2.14.0) citesc cheia
`download_url.windows` din `update.json` → `releases/latest/download/DataMover-Windows.zip`.
Ultimul release care conține acest fișier e `v2.14.0`; de atunci linkul dă **404**,
deci clienții vechi primesc „actualizare disponibilă” și apoi o eroare de descărcare.

Updater-ul vechi (`core/updater.py`) face un singur lucru: caută **exact**
`DataMover.exe` în arhivă, îl copiază **peste** executabilul care rulează și îl
pornește. Nu rulează installere, nu păstrează o copie a versiunii vechi.

## Ce NU facem

Nu îndreptăm cheia `windows` spre arhiva WPF (`DataMoverSetup.exe`): updater-ul vechi
n-ar găsi `DataMover.exe` (eroare), sau — dacă am redenumi — ar suprascrie aplicația
veche cu un installer pornit din locul greșit, fără cale de întoarcere.

## Arhitectura propusă: „punte” de migrare

Un `DataMover-Windows.zip` publicat la fiecare release, care conține un singur
`DataMover.exe` mic — **asistentul de migrare** — compatibil cu updater-ul vechi:

1. Updater-ul vechi îl copiază peste aplicația veche și îl pornește (ca azi).
2. Asistentul arată o fereastră: „DataMover s-a mutat într-o aplicație nouă”, cu
   **Instalează acum** / **Mai târziu**.
3. **Instalează acum**: descarcă `DataMoverSetup-<v>.exe` (din `download_url.windows_wpf`,
   arhiva versionată), verifică semnătura Authenticode și versiunea, pornește
   wizardul nativ Inno Setup (niciodată browserul, Regula 20). Setările și istoricul
   vechi nu sunt atinse.
4. La pornirile următoare, dacă aplicația WPF e instalată (cheia de dezinstalare Inno),
   asistentul o pornește direct și se închide — scurtăturile vechi continuă să meargă.
5. **Revenire (rollback)**: butonul „Revino la versiunea veche” descarcă
   `DataMover-Windows.zip` de la tag-ul fix `v2.14.0` (ultimul Python publicat),
   verifică SHA-256 față de valoarea fixată în asistent și reface `DataMover.exe`
   în același loc, prin același mecanism .bat ca updater-ul vechi.

## Condiții înainte de publicare (toate obligatorii)

- Test local în VM cu o instalare veche reală: `DataMover.exe` 2.14.0 descărcat
  din release-ul `v2.14.0`, rulat dintr-un folder de test, actualizat prin
  updater-ul lui, apoi: migrare → WPF pornește; rollback → 2.14.0 pornește.
- Installerul WPF construit și semnat (CI — Inno Setup nu e în VM-ul de test).
- `update.json`: cheia `windows` rămâne, conținutul arhivei se schimbă (Regula 35:
  niciun câmp eliminat); `version` = minimul dintre platforme.

## Stare (2026-09-26)

Arhitectură decisă, **neimplementată**: testul cu o instalare veche reală și
installerul semnat nu sunt încă disponibile local. Blocajul rămâne documentat;
nu se publică nimic pentru Windows până nu trece testul de mai sus.
