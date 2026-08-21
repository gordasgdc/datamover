# DataMover

[🇷🇴 Română](README.md) | [🇬🇧 English](README.en.md) | [🇪🇸 Español](README.es.md)

**Offload verificat pentru echipele de producție video**

<!-- Cand ai un video demo, inlocuieste VIDEO_ID cu ID-ul real de YouTube:
[![Video Demo](https://img.youtube.com/vi/VIDEO_ID/0.jpg)](https://youtu.be/VIDEO_ID) -->

## 📸 Capturi de ecran

UI nativ macOS (SwiftUI) — surse, discuri și destinații într-un singur layout pe 3 coloane:

| Fereastra principală | Setări de copiere |
|-----------------------|--------------------|
| ![Fereastra principala](docs/img/mac-ui-main.png) | ![Setari copiere](docs/img/mac-ui-settings.png) |

| Istoric copieri | Ghid de utilizare integrat |
|------------------|------------------------------|
| ![Istoric](docs/img/mac-ui-history.png) | ![Ghid](docs/img/mac-ui-help.png) |

## ✅ Funcționalități

- 📂 Copiere simultană către **oricâte destinații** (drive-uri externe, NAS, foldere locale)
- 🔒 **Verificare integritate** la alegere: MD5, SHA-1, SHA-256, SHA-512 sau doar dimensiune
- 🌙 **Temă întunecată** — perfectă pentru lucru noaptea
- 📊 **Rapoarte profesionale** CSV + PDF (tabel), cu status colorat (OK / Nepotrivire / Eroare) și timestamp exact
- 🔄 **Reluare automată** la erori (checkpoint) — continuă de unde a rămas
- 🕐 **Istoric copieri** — vizualizare și ștergere individuală/completă (Mac)
- 🖥️ **Mod Monitorizare** în system tray — detectează automat cardurile introduse (Windows)
- 📈 **Bare de progres per destinație** cu viteză curentă (MB/s) și buton de deschidere rapidă a folderului
- 💡 **Tooltip-uri/ghid explicativ** pentru toate setările complexe
- ⌨️ **Scurtături de tastatură** pentru acțiunile principale
- 📝 **Log centralizat** pentru audit pe termen lung
- 🚀 **Copiere paralelă** — toate destinațiile se completează simultan
- 🏷️ **Denumire automată** a folderelor: `Data_Proiect_Card`
- 🌍 **Localizare completă** RO/EN/ES
- 🔌 **Suport** pentru macOS (UI nativ SwiftUI, Apple Silicon + Intel) și Windows 10/11
- 🗑️ **Excluderi personalizabile** — poți exclude fișiere sau extensii

## 🚀 Download

Descarcă ultima versiune de la [Releases](https://github.com/gordasgdc/datamover/releases)

| Platformă | Fișier | Descriere |
|-----------|--------|-----------|
| **Mac** | `DataMover-Mac.zip` | `DataMover.app` nativ (SwiftUI) + ghidurile PDF (RO/EN/ES) |
| **Windows** | `DataMover-Windows.zip` | `DataMover.exe` + ghidurile PDF (RO/EN/ES) |

## 📖 Instalare rapidă

### Mac
1. Descarcă `DataMover-Mac.zip` și extrage
2. Mută `DataMover.app` în `/Applications` (drag & drop)
3. La prima rulare, click-dreapta pe aplicație → `Open` → confirmă (se face o singură dată, e semnată ad-hoc, fără cont Apple Developer plătit)

### Windows
1. Descarcă `DataMover-Windows.zip` și extrage conținutul
2. Rulează `DataMover.exe`
3. Dacă SmartScreen avertizează, apasă "More info" → "Run anyway"

## 📝 Documentație completă

Vezi [CITESTE-MA.md](CITESTE-MA.md) pentru instrucțiuni detaliate de instalare, compilare, publicare de versiuni noi și depanare.

## 👤 Creat de

**Cristi Gordas** (@gordasgdc)

- 🌐 [GitHub](https://github.com/gordasgdc/datamover)
- 📘 [Facebook](https://web.facebook.com/cristiGDC)
- 🎥 [YouTube](https://www.youtube.com/@cristigordas)

Aceleași linkuri sunt disponibile și direct din aplicație, din fereastra **"Despre..."** din colțul din stânga-sus.

## 🙏 Susține proiectul

Dacă această aplicație ți-a fost utilă:
- ⭐ Dă un **Star** pe GitHub
- 🔗 **Distribuie** colegilor din industrie
- 💬 **Lasă un feedback** sau o sugestie

## 📄 Licență

Acest proiect este distribuit sub [Licența MIT](LICENSE).
