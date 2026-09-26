# Jurnale și diagnostic — DataMover

DataMover ține un jurnal tehnic local, doar pe calculatorul tău. Nu se trimite
nimic automat nicăieri. Dacă ai o problemă, îți putem cere un singur fișier:
**exportul de diagnostic**.

## Cum trimiți un diagnostic (pas cu pas)

**macOS**
1. Deschide DataMover.
2. În bara de meniu de sus: **Ajutor → Exportă diagnosticul…**
   (sau **DataMover → Setări… → Diagnostic → Exportă diagnosticul**).
3. Se deschide Finder cu un fișier `DataMover-diagnostic-….zip` selectat.
4. Trimite acel fișier (email sau WhatsApp).

**Windows**
1. Deschide DataMover.
2. Jos, apasă butonul **Diagnostic**.
3. Alege **Exportă diagnosticul (căi anonimizate)**.
4. Se deschide Explorer cu fișierul `.zip` selectat. Trimite-l.

## Ce conține exportul — și ce nu

Conține: jurnalele tehnice, versiunea aplicației și a sistemului, setările
relevante pentru copiere (algoritm de verificare, reîncercare, MHL) și
rezumatul ultimului transfer (număr de fișiere, verdict).

**Nu** conține: fișierele tale media, parole, coduri de licență, adrese de
email, token-uri. Numele folderelor și ale fișierelor sunt înlocuite cu coduri
(`<cale#a1b2c3>.mov`) — păstrăm doar extensia, ca să înțelegem tipul fișierului.
Doar dacă alegi explicit varianta „cu căile fișierelor”, acestea rămân vizibile.

## ID-ul de sesiune și ID-ul de job

La fiecare pornire, aplicația primește un **ID de sesiune** (8 caractere); fiecare
transfer primește un **ID de job**. Le vezi la rezultatul transferului și în
meniul Diagnostic. Dacă ne scrii, spune-ne ID-ul — găsim imediat locul exact
din jurnal.

## Unde sunt jurnalele

| Sistem  | Folder |
|---------|--------|
| macOS   | `~/Library/Logs/DataMover/` (fișierul `datamover.jsonl`) |
| Windows | `%LOCALAPPDATA%\GDC\DataMover\Logs\` (fișierul `datamover.jsonl`) |

Exporturile se salvează în subfolderul `Exports`. Jurnalele se rotesc singure
(5 fișiere × 5 MB) și cele mai vechi de 14 zile se șterg automat, deci nu cresc
la nesfârșit.

## Jurnal detaliat (doar la cerere)

Dacă îți cerem, activează **Jurnal detaliat (până la repornire)** (Setări →
Diagnostic pe macOS, butonul Diagnostic pe Windows), reprodu problema, apoi
exportă diagnosticul. La următoarea pornire, jurnalul revine la nivelul normal.

## Pentru suport tehnic: citire din Terminal

```bash
# macOS — ultimele evenimente, lizibil
tail -n 50 ~/Library/Logs/DataMover/datamover.jsonl | python3 -m json.tool --json-lines
# doar erorile
grep '"level":"error"' ~/Library/Logs/DataMover/datamover.jsonl
```

```powershell
# Windows (PowerShell)
Get-Content "$env:LOCALAPPDATA\GDC\DataMover\Logs\datamover.jsonl" -Tail 50 | ConvertFrom-Json
```

Fiecare linie are: ora (UTC), nivel, componentă, eveniment, versiune, sistem,
ID sesiune și, după caz, ID job și ID destinație.
