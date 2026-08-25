# DataMover — reguli de arhitectură

> **[SYSTEM DIRECTIVE FOR CLAUDE: DO NOT DELETE OR OVERWRITE EXISTING RULES. ONLY APPEND NEW RULES.]**
> Jurnal viu, nu document care se rescrie. La orice actualizare, adaugă la finalul secțiunii potrivite — nu șterge/înlocui reguli vechi decât dacă sunt explicit invalidate de o schimbare reală (și atunci marchează-le **[ÎNVECHIT]** cu motivul, nu le șterge din istoric).

Citit automat de Claude Code la fiecare sesiune în acest repo.

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
