# DataMover

Offload verificat pentru producție video: cardul este citit o singură dată, iar
materialul este copiat simultan pe mai multe discuri independente. Fiecare fișier
primește numele final abia după ce checksum-ul copiei se potrivește cu sursa.

**Descărcare și prezentare: [gordas.dev/datamover](https://gordas.dev/datamover/)** · versiunea curentă **2.17.1**

![DataMover pe macOS, în timpul unui transfer](docs/img/2.16/mac-transfer-dark-ro.webp)

## Ce face

- Citește sursa o singură dată și scrie în paralel pe toate destinațiile (discuri externe, RAID, NAS, foldere).
- Contract de copiere pentru fiecare fișier și fiecare copie: scriere → flush pe disc → recitire și verificare. Un fișier neverificat nu apare niciodată sub numele final.
- Verificare implicită cu xxHash64; la alegere MD5, SHA-1, SHA-256 sau SHA-512.
- Reluare după întrerupere: fișierele deja confirmate nu se recopiază, iar cele incomplete se curăță.
- Rapoarte de livrare pentru fiecare destinație: PDF, HTML, CSV și MHL, cu verdict (verificat, cu avertismente, neconfirmat, anulat).
- Interfață în română, engleză și spaniolă, pe macOS și pe Windows.

![DataMover pe Windows, în timpul unui transfer](docs/img/2.16/win-dark-1240-transfer.webp)

## Platforme și cerințe

- **macOS 14 sau mai nou, Apple Silicon.** Pachet semnat Developer ID și notarizat de Apple.
- **Windows 11, 64 de biți (x64).** Pe Windows 11 ARM64 rulează prin emularea x64 a sistemului.

## Instalare

**macOS.** Descarcă `DataMover.dmg` de pe [gordas.dev/datamover](https://gordas.dev/datamover/), deschide-l și rulează instalatorul `.pkg`. Aplicația se instalează în `/Applications`.

**Windows.** Descarcă `DataMover-WPF-Windows.zip`, extrage arhiva și rulează `DataMoverSetup.exe`. Aplicația se instalează în Program Files, cu scurtături.

> Installerul Windows are deocamdată o semnătură self-signed, nu un certificat comercial Authenticode. SmartScreen poate afișa „Windows a protejat PC-ul” sau „Editor necunoscut”. Dacă ai descărcat fișierul de pe gordas.dev, alege **Mai multe informații → Rulați oricum**.

## Probă și activare

- 7 zile complet funcțional, fără cont.
- Fără activare, după perioada de probă fiecare transfer este limitat la 2 GB.
- Activarea folosește un cod personal, legat de ID-ul calculatorului, obținut printr-o donație pentru dezvoltare. Detalii în aplicație și pe [gordas.dev/datamover](https://gordas.dev/datamover/).

## Diagnostic

Jurnalul tehnic rămâne local, pe calculatorul tău; nimic nu se trimite automat. Pentru suport, aplicația poate crea un export de diagnostic, cu căile și datele personale redactate, pe care îl trimiți doar dacă vrei.

## Pentru dezvoltatori

- [CITESTE-MA.md](CITESTE-MA.md) — compilare, publicare, depanare
- [ARCHITECTURE.md](ARCHITECTURE.md) · [RELIABILITY.md](RELIABILITY.md) · [CHANGELOG.md](CHANGELOG.md)
- [support/JURNALE_SI_DIAGNOSTIC.md](support/JURNALE_SI_DIAGNOSTIC.md)

Limba: **Română** · [English](README.en.md) · [Español](README.es.md)

## Licență

Cod sursă sub [licența MIT](LICENSE). Autor: Cristi Gordaș.
