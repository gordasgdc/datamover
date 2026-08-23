# DataMover pentru Android (PWA + TWA)

Aplicatia Android **nu** e un cod separat: e chiar site-ul `gordas.dev/datamover/`,
transformat in PWA si impachetat intr-un APK prin TWA (Trusted Web Activity).
Consecinta practica: **orice modificare pe site apare in aplicatie fara APK nou.**
APK-ul se reconstruieste doar cand schimbi numele, iconita sau permisiunile.

## Fisiere si rolul lor

| Fisier | Rol |
|---|---|
| `docs/manifest.webmanifest` | numele, iconitele, culorile, scurtaturile aplicatiei |
| `docs/sw.js` | service worker: offline + cache + notificari |
| `docs/offline.html` | pagina afisata cand nu e retea |
| `docs/icons/` | iconite 192/512 + varianta *maskable* pentru Android |
| `docs/.well-known/assetlinks.json` | dovada ca APK-ul si domeniul iti apartin |
| `twa/twa-manifest.json` | configuratia APK-ului (bubblewrap) |
| `twa/build-apk.sh` | scriptul care construieste si semneaza APK-ul |

> La fiecare modificare de pagina, **incrementeaza `CACHE_VERSION` din `docs/sw.js`**.
> Altfel utilizatorii raman cu versiunea veche din cache.

## Build APK

```bash
bash twa/build-apk.sh
```

Cerinte: JDK 17 (`brew install --cask temurin@17`) si Node. Prima rulare descarca
Android SDK (~500 MB). Rezultatul: `twa/app-release-signed.apk`.

## Semnare (keystore) — partea ireversibila

Scriptul creeaza `twa/android.keystore` la prima rulare si il refoloseste dupa.

- **Fa-i backup imediat** (password manager + un al doilea loc, offline).
- Salveaza si parola keystore-ului, si parola cheii, si alias-ul (`datamover`).
- `twa/.gitignore` il tine in afara repo-ului — nu forta niciodata `git add`.
- **Daca pierzi keystore-ul**, utilizatorii care au deja aplicatia nu mai pot
  face update: Android refuza un APK semnat cu alta cheie. Singura solutie ar fi
  un nou `packageId` si reinstalare manuala de catre toti.

## Digital Asset Links (fara bara de browser)

Fara acest pas, aplicatia se deschide cu bara de URL Chrome deasupra.

`assetlinks.json` se verifica pe **radacina originii**, nu pe subcale. Fisierul
generat in `docs/.well-known/assetlinks.json` trebuie copiat in repo-ul care
serveste radacina `gordas.dev`, ca sa fie accesibil la:

```
https://gordas.dev/.well-known/assetlinks.json
```

Verificare:

```bash
curl -s https://gordas.dev/.well-known/assetlinks.json
```

Amprenta SHA-256 din fisier trebuie sa fie exact cea a keystore-ului tau
(scriptul o completeaza automat). Daca ai folosit alt keystore, o citesti cu:

```bash
keytool -list -v -keystore twa/android.keystore -alias datamover | grep SHA256
```

Pe GitHub Pages, folderele care incep cu punct sunt ignorate de Jekyll — de aceea
exista `docs/.nojekyll`. Repo-ul care serveste radacina domeniului are nevoie de
acelasi fisier.

## Instalare pe telefon (Android 13, 14, 15+)

APK-ul nu vine din Play Store, deci sistemul cere o permisiune explicita:

1. Descarca APK-ul de pe site (Chrome → "Descarca oricum").
2. Deschide fisierul din notificare sau din **Fisiere → Descarcari**.
3. Android afiseaza "Din motive de securitate nu poti instala..." →
   **Setari** → activeaza **Permite din aceasta sursa** pentru Chrome/Fisiere.
4. Inapoi → **Instaleaza**. Play Protect poate afisa un avertisment pentru o
   aplicatie necunoscuta → **Instaleaza oricum**.
5. Pe Android 13+, permisiunea de notificari se cere separat, la prima pornire.

Alternativa fara APK: din Chrome, meniul ⋮ → **Adauga la ecranul principal**.
Instaleaza acelasi PWA, fara pasii de securitate de mai sus.

## Notificari (plugin nou, LUT/DCTL, workshop)

`docs/sw.js` are deja handler-ele `push` si `notificationclick`. Ca sa functioneze
mai lipsesc doua lucruri, care se fac cand ai continut de anuntat:

1. **Backend**: Firebase Cloud Messaging (gratuit) sau orice server web-push cu chei VAPID.
2. **Abonare in pagina**: `Notification.requestPermission()` urmat de
   `registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey })`,
   cu trimiterea subscriptiei catre backend.

Formatul asteptat de service worker pentru payload:

```json
{ "title": "Plugin nou", "body": "GDC Film Look v2 e disponibil", "url": "/datamover/#functii", "tag": "plugin-nou" }
```

## Checklist la fiecare release

- [ ] `CACHE_VERSION` incrementat in `docs/sw.js`
- [ ] site-ul urcat si testat in Chrome mobil (instalabil = fara erori in DevTools → Application)
- [ ] APK reconstruit **doar** daca s-au schimbat nume/iconite/scurtaturi
- [ ] `appVersionName` + `appVersionCode` crescute in `twa/twa-manifest.json` inainte de build
- [ ] keystore-ul e in backup, nu in git
