# codesigning/ — semnare Windows (Self-Signed, testare internă)

Vezi `README.md` din același folder pentru semnarea Mac (Developer ID +
notarizare) — acest document acoperă DOAR partea Windows, adăugată
2026-09-06 (CLAUDE.md, Regula 34), la retragerea build-ului Windows vechi
(Python/PyInstaller) — clientul WPF (`windows-native/`) a rămas singurul
client Windows activ.

## De ce Self-Signed, și ce NU rezolvă

Un certificat self-signed **nu elimină avertismentul SmartScreen/"Unknown
publisher"** pentru publicul larg — doar un certificat real de la o CA
publică (cu reputație acumulată) sau un certificat EV fac asta. Self-signed
e util STRICT pentru:
- testare internă (buildurile pe care le rulează Cristi însuși),
- distribuire către un cerc restrâns de colaboratori care importă manual
  certificatul public (`.cer`) în Trusted Root o singură dată.

La lansarea comercială publică, planul e Azure Trusted Signing sau un
certificat EV (HSM cloud) — vezi CLAUDE.md Regula 34 pentru context complet.

## Certificatul e COMUN tuturor aplicațiilor GDC

Secretele CI se numesc IDENTIC în fiecare repo (`WIN_SELFSIGN_PFX_BASE64`/
`WIN_SELFSIGN_PFX_PASSWORD`) — dacă certificatul a fost deja generat pentru
alt proiect (ex. CGConvertor), **nu genera unul nou aici** — reîncarcă
ACELAȘI `.pfx` ca secrete în acest repo (pasul 2 de mai jos), ca
utilizatorii/colaboratorii care au importat deja `.cer`-ul în Trusted Root
să rămână de încredere și pentru binarele DataMover, fără un al doilea import.

## Setup unic (o dată, făcut DIRECT de Cristi pe Windows real)

Certificatul (privat, cu cheie) nu trece niciodată prin conversația cu
Claude — la fel ca orice altă parolă/cheie din ecosistem.

1. Pe Windows real (Parallels e suficient), deschide PowerShell **ca
   Administrator** și rulează (DOAR dacă nu există deja certificatul comun
   GDC dintr-un alt repo):
   ```powershell
   .\mac-native\codesigning\generate-self-signed-cert.ps1
   ```
   Scriptul cere o parolă nouă (pentru `.pfx`) și produce două fișiere:
   - `gdc-selfsign.pfx` — **PRIVAT**, nu se distribuie, nu se comite în git.
   - `gdc-selfsign.cer` — **PUBLIC**, se distribuie colaboratorilor.

2. Încarcă `.pfx`-ul ca secrete GitHub Actions — comenzile exacte sunt
   afișate la finalul scriptului (necesită `gh` CLI autentificat pe acea
   mașină):
   ```powershell
   gh secret set WIN_SELFSIGN_PFX_BASE64 --repo gordasgdc/DataMover --body $b64
   gh secret set WIN_SELFSIGN_PFX_PASSWORD --repo gordasgdc/DataMover
   ```

3. Șterge `.pfx`-ul local imediat după (`Remove-Item gdc-selfsign.pfx -Force`)
   — rămâne doar în secretele CI, criptate.

4. Distribuie `gdc-selfsign.cer` colaboratorilor (dacă nu l-au primit deja
   de la alt proiect GDC). Pe fiecare mașină a lor, o singură dată:
   dublu-click → **Install Certificate** → **Local Machine** → "Place all
   certificates in the following store" → **Trusted Root Certification
   Authorities**.

Odată făcuți pașii 1-4, **fiecare build viitor din CI**
(`.github/workflows/build-windows-wpf.yml`, la push de tag) semnează
automat `.exe`-ul clientului WPF și installer-ul final cu ACELAȘI
certificat — colaboratorii nu mai trebuie să reimporte nimic la
versiunile următoare.

## Ce face CI-ul automat (`.github/workflows/build-windows-wpf.yml`)

- Dacă secretele NU sunt setate: build-ul continuă **nesemnat**, exact ca
  până acum — nicio eroare, nicio schimbare de comportament.
- Dacă secretele SUNT setate: după ce `DataMover.Client.exe` (dotnet
  publish) și installer-ul final (Inno Setup) există, ambele sunt semnate
  cu `signtool.exe` (localizat dinamic din Windows Kits, cu timestamp),
  apoi verificate cu `Get-AuthenticodeSignature` — confirmă DOAR că
  semnătura a fost atașată corect, fără să ceară lanț de încredere complet
  (asta ar eșua mereu pe un runner CI proaspăt, care nu are certificatul
  în Trusted Root — normal pentru self-signed, nu un bug). Un eșec real de
  semnare (fișier fără nicio semnătură) tot oprește build-ul (CI roșu).

## Regenerarea certificatului (dacă expiră sau e compromis)

Rulează din nou `generate-self-signed-cert.ps1` (dintr-un repo GDC), apoi
reîncarcă secretele în TOATE repo-urile ecosistemului care folosesc acest
certificat comun (pasul 2 de mai sus îi suprascrie pe cei vechi în fiecare)
— dar **toți colaboratorii trebuie să reimporte noul `.cer`**, altfel văd
din nou avertismentul pentru versiunile semnate cu noul certificat. Evită
regenerarea inutilă — de asta scriptul folosește o valabilitate de 5 ani.
