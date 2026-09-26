// generate-guides.swift — ghidurile de utilizare DataMover (RO/EN/ES), A4, generate local.
//
//   swift docs/guides/generate-guides.swift            # scrie docs/guides/DataMover_{Ghid_RO,Guide_EN,Guia_ES}.pdf
//
// Regula 38: PDF-ul se produce din cod (CoreText/CoreGraphics), iar verificarea o face
// scriptul însuși (PDFKit): pagini, secțiuni în cuprins, text care nu încape, imagini
// lipsă, cuvinte interzise. Scriptul tipărește doar un rezumat; iese cu 1 la orice problemă.
// Aceleași secțiuni, în aceeași ordine, în toate trei limbile.
import AppKit
import CoreText
import PDFKit

let version = CommandLine.arguments.dropFirst().first ?? "2.16.3"
let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

// MARK: - Model de conținut

enum B {
    case p(String)                 // paragraf; **text** = îngroșat
    case bullets([String])
    case steps([String])
    case note(String)              // informație
    case warn(String)              // avertisment
    case img(String, String)       // fișier din img/, legendă
    case table([[String]])         // primul rând = antet
}
struct Sec { let title: String; let blocks: [B] }
struct Guide {
    let file: String, lang: String, title: String, subtitle: String, toc: String, page: String, forVersion: String
    let sections: [Sec]
}

// MARK: - Conținut

let ro = Guide(file: "DataMover_Ghid_RO.pdf", lang: "ro", title: "DataMover — Ghid de utilizare",
    subtitle: "Offload verificat pentru producția video: sursă → verificare → copii independente",
    toc: "Cuprins", page: "Pagina %d din %d", forVersion: "Pentru DataMover %@ · macOS și Windows",
    sections: [
    Sec(title: "Ce face DataMover", blocks: [
        .p("DataMover copiază materialul de pe un card sau dintr-un folder simultan pe mai multe discuri independente. Sursa se citește **o singură dată**, iar fiecare copie este comparată cu sursa prin checksum înainte de a primi numele final."),
        .bullets(["**Sursă** — cardul camerei sau un folder.", "**Verificare** — checksum-ul fiecărei copii trebuie să fie identic cu cel al sursei.", "**Copii independente** — două sau mai multe discuri, fiecare cu rezultatul și rapoartele lui."]),
        .warn("Nu formata cardul până când fiecare destinație are verdictul **Verificat**. DataMover reduce riscul la copiere, dar nu îl elimină."),
    ]),
    Sec(title: "Instalare pe macOS", blocks: [
        .p("Cerințe: macOS 14 sau mai nou, pe un Mac cu Apple Silicon. Pachetul este semnat Developer ID și notarizat de Apple, deci Gatekeeper îl deschide fără pași suplimentari."),
        .steps(["Descarcă **DataMover.dmg** de pe gordas.dev/datamover.", "Deschide fișierul DMG. În fereastră găsești pachetul **DataMover-x.y.z.pkg** și acest ghid.", "Fă dublu-clic pe pachet și urmează pașii. Acceptă acordul de licență.", "Când ți se cere, introdu parola de administrator a Mac-ului (literele nu apar pe ecran — e normal), apoi apasă Enter.", "Pornește DataMover din folderul **Aplicații**."]),
    ]),
    Sec(title: "Instalare pe Windows", blocks: [
        .p("Cerințe: Windows 11, 64 de biți (x64). Pe calculatoarele ARM64, aplicația rulează prin emularea x64 a sistemului."),
        .steps(["Descarcă **DataMover-WPF-Windows.zip** și extrage arhiva.", "Rulează **DataMoverSetup.exe** și acceptă acordul de licență.", "Aplicația se instalează în Program Files, cu scurtătură în meniul Start. Scurtătura pe Desktop este opțională, bifată de tine în asistent."]),
        .warn("Installerul Windows are o semnătură **self-signed**, nu un certificat comercial. Windows SmartScreen poate afișa „Windows a protejat PC-ul” sau „Editor necunoscut”. Dacă ai descărcat fișierul de pe gordas.dev, apasă **Mai multe informații** → **Rulați oricum**."),
        .p("Dezinstalarea se face din **Setări → Aplicații**. Ea șterge și setările DataMover, licența locală și jurnalele de diagnostic; datele altor aplicații GDC rămân neatinse."),
    ]),
    Sec(title: "Actualizări", blocks: [
        .p("La pornire, DataMover verifică dacă există o versiune nouă și îți arată numărul versiunii și noutățile. Verificarea se poate face și manual, din aplicație."),
        .bullets(["**macOS** — **Descarcă și instalează** descarcă pachetul, verifică versiunea și semnătura, îți cere parola de administrator și repornește aplicația. **Mai târziu** amână aceeași versiune.", "**Windows** — în fereastra „Actualizare disponibilă”, **Da** descarcă installerul și deschide asistentul de instalare; aplicația se închide și pornește din nou după instalare. **Nu** amână actualizarea.", "Actualizarea nu se instalează niciodată în fundal, fără acordul tău."]),
    ]),
    Sec(title: "Pregătirea offloadului", blocks: [
        .p("Completează **Proiectul** și **Cardul** în bara de sus. Din ele se formează numele folderului creat pe fiecare destinație (de exemplu 2026-09-26_PROIECT_A001)."),
        .bullets(["**Sursa** — trage cardul sau folderul în zona Sursă, folosește butonul de adăugare sau alege-l din lista de dispozitive.", "**Destinațiile** — adaugă cel puțin o copie; pentru siguranță, folosește două discuri diferite. Pe macOS, trage un disc în „+ încă o copie” sau alege rolul din meniul dispozitivului; pe Windows, apasă **Copie** sub dispozitiv.", "**Verificarea** — implicit xxHash64 (rapid). Poți alege MD5, SHA-1, SHA-256, SHA-512 sau „doar dimensiune” în Setări."]),
        .img("mac-prepare.jpg", "macOS, pregătire: sursa, cele două copii și avertismentele dinainte de pornire."),
    ]),
    Sec(title: "Verificările dinainte de pornire", blocks: [
        .p("Înainte de pornire, aplicația verifică traseul. Problemele **blocante** dezactivează butonul de pornire; **avertismentele** nu blochează, dar merită citite înainte de formatarea cardului."),
        .table([["Situație", "Tip"], ["Destinația se află în sursă (sau invers)", "Blocant"], ["Aceeași destinație aleasă de două ori, destinații imbricate", "Blocant"], ["Cale lipsă sau fără drept de scriere, coliziuni de nume", "Blocant"], ["Copia ar sta pe același disc cu sursa", "Avertisment"], ["Spațiu insuficient la o destinație", "Avertisment, cu confirmare"], ["Structură neobișnuită a cardului (ex. fișiere de 0 octeți)", "Avertisment"]]),
    ]),
    Sec(title: "Transferul și verificarea", blocks: [
        .p("Apasă **Pornește transferul**. Sursa se citește o singură dată și se scrie în paralel pe toate copiile. Fiecare fișier este scris întâi cu extensia temporară **.dmpart** și primește numele final doar după flush pe disc și după ce checksum-ul copiei se potrivește cu sursa."),
        .bullets(["Progresul se afișează separat pentru fiecare destinație; cifrele sunt măsurate, nu estimate.", "Poți pune transferul pe **Pauză** sau îl poți **Anula**.", "Dacă un disc se deconectează, problema apare doar la destinația lui; celelalte copii continuă.", "Un fișier modificat pe card în timpul copierii este marcat neconfirmat."]),
        .img("mac-transfer.jpg", "macOS, transfer în curs: progres măsurat pe fiecare copie."),
        .img("win-transfer.jpg", "Windows, transfer în curs: aceeași logică, interfață proprie Windows."),
    ]),
    Sec(title: "Rezultatul", blocks: [
        .p("La final vezi un singur verdict, fără ambiguitate, și câte un rezultat pentru fiecare destinație."),
        .table([["Verdict", "Ce înseamnă"], ["Verificat", "Fiecare fișier a trecut verificarea aleasă la fiecare destinație."], ["Verificat, cu avertismente", "Totul este confirmat, dar unele fișiere au reușit abia la reîncercare. Verifică cablul, cardul și discurile."], ["Eșec parțial", "Cel puțin o destinație are fișiere neconfirmate. Nu formata cardul."], ["Eșec", "Nicio destinație nu are o copie completă confirmată."], ["Anulat", "Transferul a fost oprit; fișierele confirmate se păstrează."]]),
        .img("mac-result.jpg", "macOS, rezultat: fiecare copie confirmată separat, cu rapoartele ei."),
        .note("Ejectarea automată a cardului (opțională, în Setări) se face doar când fiecare destinație are o copie confirmată."),
    ]),
    Sec(title: "Rapoartele de livrare", blocks: [
        .p("În folderul creat pe fiecare destinație, DataMover scrie:"),
        .bullets(["**PDF și HTML** — raportul de livrare: verdictul destinației, rezumatul (fișiere, date confirmate, durată, verificare), proiectul, cardul, operatorul și lista fișierelor cu checksum și status. HTML-ul se deschide în orice browser și se poate tipări pe A4.", "**CSV** — lista completă, câte un rând pe fișier (coloanele: fișier, mărime, verificare sursă, verificare destinație, status, eroare). Este în UTF-8 cu marcaj, ca diacriticele să fie citite corect.", "**MHL** — lista de hash-uri pentru lanțul de custodie din post-producție. Se generează doar cu xxHash64, MD5 sau SHA-1, singurii algoritmi acceptați de standardul MHL.", "**offload_checkpoint.json** — folosit la reluare."]),
        .img("report-pdf.jpg", "Prima pagină a raportului PDF (date de test)."),
        .note("Pentru transferuri foarte mari, PDF-ul și HTML-ul arată toate problemele plus un eșantion; lista completă este în CSV."),
    ]),
    Sec(title: "Reluarea unui transfer", blocks: [
        .p("Dacă un transfer a fost întrerupt, pornește-l din nou cu aceeași sursă și aceleași destinații. Cu opțiunea **Reia automat dintr-un checkpoint existent** (activă implicit), DataMover recitește sursa și copia pentru fișierele deja confirmate: ele trebuie să dea checksum-ul salvat la confirmare, altfel se recopiază."),
        .bullets(["Numele, mărimea sau data nu sunt niciodată suficiente pentru a sări un fișier.", "Un checkpoint făcut cu alt algoritm sau pentru alt folder este ignorat.", "În modul „doar dimensiune”, reluarea recopiază tot."]),
        .warn("Reluarea a fost testată după întreruperi simulate. Comportamentul după o pană de curent reală sau un disc scos fizic nu a fost verificat încă — după un asemenea incident, verifică rezultatul final."),
    ]),
    Sec(title: "Setări și limbă", blocks: [
        .p("**macOS** — meniul DataMover → Setări, cu taburile General, Verificare, Rapoarte, Performanță, Cloud, Cont și Diagnostic. În General alegi limba (română, engleză, spaniolă) și aspectul (Sistem, Luminos, Întunecat), plus deschiderea automată a destinației, ejectarea cardului și pornirea automată la introducerea unui card."),
        .img("mac-settings.jpg", "macOS, Setări → General."),
        .p("**Windows** — butonul **Setări** din bara de sus: verificare, MHL, reîncercarea automată, profilul de performanță, logo pentru rapoarte și tema. Interfața Windows este în română."),
    ]),
    Sec(title: "Diagnostic", blocks: [
        .p("DataMover ține un jurnal tehnic local. Nu se trimite nimic automat. Dacă ai o problemă, exportă diagnosticul și trimite-ne fișierul ZIP."),
        .bullets(["**macOS** — Ajutor → Exportă diagnosticul… (sau Setări → Diagnostic).", "**Windows** — butonul **Diagnostic** din partea de jos → Exportă diagnosticul.", "Exportul conține jurnalele, versiunea și rezumatul ultimului transfer. Căile și numele fișierelor sunt înlocuite cu coduri; nu conține fișiere media, parole sau coduri de licență."]),
    ]),
    Sec(title: "Diferențe între macOS și Windows", blocks: [
        .p("Ambele aplicații respectă aceleași reguli de copiere și produc aceleași tipuri de rapoarte, cu aceleași informații. Interfețele sunt native și diferă:"),
        .table([["", "macOS", "Windows"], ["Limba interfeței", "Română, engleză, spaniolă", "Română"], ["Limba rapoartelor", "Limba aplicației", "Limba Windows (ro/en/es), altfel română"], ["Semnare", "Developer ID, notarizat Apple", "Self-signed (SmartScreen poate avertiza)"], ["Actualizare", "Instalare automată, cu parola", "Asistentul de instalare Windows"], ["Ghid din aplicație", "Ajutor, în limba aplicației", "Butonul Ghid, în română"]]),
    ]),
    Sec(title: "Probă și activare", blocks: [
        .bullets(["**7 zile** complet funcțional, fără cont și fără card.", "După perioada de probă, versiunea neactivată copiază cel mult **2 GB** per transfer.", "Activarea este legată de ID-ul calculatorului și se obține printr-o **donație** pentru dezvoltare; suma curentă apare în aplicație. Deschide Profil → Activează și trimite-ne ID-ul calculatorului pe WhatsApp."]),
    ]),
    Sec(title: "Limite cunoscute", blocks: [
        .p("Scenariile de mai jos nu au fost încă verificate. Nu le considera acoperite până nu sunt testate în mediul tău:"),
        .bullets(["pană de curent sau oprire bruscă reală în timpul copierii;", "card sau disc scos fizic în timpul transferului;", "destinații de rețea (SMB) și discuri exFAT pe Windows;", "disc plin real pe Windows;", "navigare doar din tastatură și cititor de ecran pe Windows."]),
    ]),
])

let en = Guide(file: "DataMover_Guide_EN.pdf", lang: "en", title: "DataMover — User guide",
    subtitle: "Verified offload for video production: source → verification → independent copies",
    toc: "Contents", page: "Page %d of %d", forVersion: "For DataMover %@ · macOS and Windows",
    sections: [
    Sec(title: "What DataMover does", blocks: [
        .p("DataMover copies footage from a card or folder to several independent drives at the same time. The source is read **once**, and every copy is compared with the source by checksum before it gets its final name."),
        .bullets(["**Source** — the camera card or a folder.", "**Verification** — each copy's checksum must match the source's.", "**Independent copies** — two or more drives, each with its own result and reports."]),
        .warn("Do not format the card until every destination shows **Verified**. DataMover lowers the risk of copying; it does not remove it."),
    ]),
    Sec(title: "Installing on macOS", blocks: [
        .p("Requirements: macOS 14 or later on an Apple Silicon Mac. The package is Developer ID signed and notarized by Apple, so Gatekeeper opens it without extra steps."),
        .steps(["Download **DataMover.dmg** from gordas.dev/datamover.", "Open the DMG. The window contains the **DataMover-x.y.z.pkg** package and this guide.", "Double-click the package and follow the steps. Accept the license agreement.", "When asked, enter your Mac's administrator password (the characters are not shown — this is normal), then press Enter.", "Launch DataMover from the **Applications** folder."]),
    ]),
    Sec(title: "Installing on Windows", blocks: [
        .p("Requirements: Windows 11, 64-bit (x64). On ARM64 computers the app runs through the system's x64 emulation."),
        .steps(["Download **DataMover-WPF-Windows.zip** and extract it.", "Run **DataMoverSetup.exe** and accept the license agreement.", "The app is installed in Program Files with a Start menu shortcut. The Desktop shortcut is optional; you tick it in the wizard."]),
        .warn("The Windows installer has a **self-signed** signature, not a commercial certificate. Windows SmartScreen may show “Windows protected your PC” or “Unknown publisher”. If you downloaded the file from gordas.dev, click **More info** → **Run anyway**."),
        .p("Uninstall from **Settings → Apps**. This also removes DataMover's settings, local license and diagnostic logs; data of other GDC apps is left untouched."),
    ]),
    Sec(title: "Updates", blocks: [
        .p("At launch, DataMover checks for a new version and shows you the version number and what's new. You can also check manually from the app."),
        .bullets(["**macOS** — **Download & Install** downloads the package, checks its version and signature, asks for your administrator password and restarts the app. **Later** postpones that version.", "**Windows** — in the “Actualizare disponibilă” (update available) window, **Yes** downloads the installer and opens the setup wizard; the app closes and starts again after installation. **No** postpones the update.", "An update is never installed in the background without your consent."]),
    ]),
    Sec(title: "Preparing an offload", blocks: [
        .p("Fill in **Project** and **Card** in the top bar. They form the name of the folder created on each destination (for example 2026-09-26_PROJECT_A001)."),
        .bullets(["**Source** — drag the card or folder onto the Source area, use the add button, or pick it from the device list.", "**Destinations** — add at least one copy; for safety, use two different drives. On macOS, drag a drive onto “+ another copy” or choose its role from the device menu; on Windows, click **Copy** under the device.", "**Verification** — xxHash64 by default (fast). You can choose MD5, SHA-1, SHA-256, SHA-512 or “size only” in Settings."]),
        .img("mac-prepare.jpg", "macOS, preparation: the source, both copies and the warnings before start (interface in Romanian)."),
    ]),
    Sec(title: "Checks before you start", blocks: [
        .p("Before you start, the app checks the route. **Blocking** problems disable the start button; **warnings** don't block, but are worth reading before you format the card."),
        .table([["Situation", "Type"], ["Destination inside the source (or the other way round)", "Blocking"], ["The same destination picked twice, nested destinations", "Blocking"], ["Missing path or no write permission, name collisions", "Blocking"], ["A copy would sit on the same drive as the source", "Warning"], ["Not enough space at a destination", "Warning, with confirmation"], ["Unusual card structure (e.g. 0-byte files)", "Warning"]]),
    ]),
    Sec(title: "Transfer and verification", blocks: [
        .p("Click **Start transfer**. The source is read once and written to every copy in parallel. Each file is written first with the temporary **.dmpart** extension and gets its final name only after the flush to disk and after the copy's checksum matches the source."),
        .bullets(["Progress is shown for each destination; the figures are measured, not estimated.", "You can **Pause** or **Cancel** the transfer.", "If a drive disconnects, the problem shows up only for its destination; the other copies carry on.", "A file that changes on the card during the copy is marked unconfirmed."]),
        .img("mac-transfer.jpg", "macOS, transfer in progress: measured progress for each copy."),
        .img("win-transfer.jpg", "Windows, transfer in progress: the same logic in a native Windows interface."),
    ]),
    Sec(title: "The result", blocks: [
        .p("At the end you get one unambiguous verdict and a result for each destination."),
        .table([["Verdict", "Meaning"], ["Verified", "Every file passed the selected verification at every destination."], ["Verified, with warnings", "Everything is confirmed, but some files only succeeded on retry. Check the cable, card and drives."], ["Partial failure", "At least one destination has unconfirmed files. Do not format the card."], ["Failure", "No destination has a complete confirmed copy."], ["Cancelled", "The transfer was stopped; confirmed files are kept."]]),
        .img("mac-result.jpg", "macOS, result: each copy confirmed on its own, with its reports."),
        .note("Automatic card ejection (optional, in Settings) happens only when every destination has a confirmed copy."),
    ]),
    Sec(title: "Delivery reports", blocks: [
        .p("In the folder created on each destination, DataMover writes:"),
        .bullets(["**PDF and HTML** — the delivery report: the destination's verdict, a summary (files, data confirmed, duration, verification), project, card, operator and the file list with checksum and status. The HTML opens in any browser and prints on A4.", "**CSV** — the full list, one row per file (columns: file, size, source check, destination check, status, error). It is UTF-8 with a byte-order mark so accented characters read correctly.", "**MHL** — the hash list for the post-production chain of custody. It is generated only with xxHash64, MD5 or SHA-1, the algorithms the MHL standard accepts.", "**offload_checkpoint.json** — used when resuming."]),
        .img("report-pdf.jpg", "First page of the PDF report (test data, in Romanian)."),
        .note("For very large transfers, the PDF and HTML show every problem plus a sample; the full list is in the CSV."),
    ]),
    Sec(title: "Resuming a transfer", blocks: [
        .p("If a transfer was interrupted, start it again with the same source and destinations. With **Resume automatically from an existing checkpoint** (on by default), DataMover re-reads the source and the copy of every file already confirmed: they must match the checksum saved at confirmation, otherwise the file is copied again."),
        .bullets(["A name, size or date alone is never enough to skip a file.", "A checkpoint made with another algorithm or for another folder is ignored.", "In “size only” mode, resuming copies everything again."]),
        .warn("Resuming has been tested after simulated interruptions. Behaviour after a real power cut or a physically removed drive has not been verified yet — after such an incident, check the final result."),
    ]),
    Sec(title: "Settings and language", blocks: [
        .p("**macOS** — DataMover menu → Settings, with the General, Verification, Reports, Performance, Cloud, Account and Diagnostics tabs. In General you choose the language (Romanian, English, Spanish) and the appearance (System, Light, Dark), plus opening the destination, ejecting the card and starting automatically when a card is inserted."),
        .img("mac-settings.jpg", "macOS, Settings → General (interface in Romanian)."),
        .p("**Windows** — the **Settings** button in the top bar: verification, MHL, automatic retry, performance profile, report logo and theme. The Windows interface is in Romanian."),
    ]),
    Sec(title: "Diagnostics", blocks: [
        .p("DataMover keeps a local technical log. Nothing is sent automatically. If you have a problem, export the diagnostics and send us the ZIP file."),
        .bullets(["**macOS** — Help → Export diagnostics… (or Settings → Diagnostics).", "**Windows** — the **Diagnostic** button at the bottom → Export diagnostics.", "The export contains the logs, the version and a summary of the last transfer. Paths and file names are replaced with codes; it contains no media files, passwords or license codes."]),
    ]),
    Sec(title: "Differences between macOS and Windows", blocks: [
        .p("Both apps follow the same copy rules and produce the same kinds of reports with the same information. The interfaces are native and differ:"),
        .table([["", "macOS", "Windows"], ["Interface language", "Romanian, English, Spanish", "Romanian"], ["Report language", "The app's language", "Windows language (ro/en/es), else Romanian"], ["Signing", "Developer ID, notarized by Apple", "Self-signed (SmartScreen may warn)"], ["Updating", "Automatic install, with password", "The Windows setup wizard"], ["In-app guide", "Help, in the app's language", "Guide button, in Romanian"]]),
    ]),
    Sec(title: "Trial and activation", blocks: [
        .bullets(["**7 days** fully functional, no account, no card.", "After the trial, the unactivated version copies at most **2 GB** per transfer.", "Activation is tied to your computer's ID and comes with a development **donation**; the current amount is shown in the app. Open Profile → Activate and send us your computer ID on WhatsApp."]),
    ]),
    Sec(title: "Known limits", blocks: [
        .p("The scenarios below have not been verified yet. Don't consider them covered until you have tested them in your setup:"),
        .bullets(["a real power cut or hard shutdown during a copy;", "a card or drive physically removed during a transfer;", "network destinations (SMB) and exFAT drives on Windows;", "a real full disk on Windows;", "keyboard-only navigation and screen readers on Windows."]),
    ]),
])

let es = Guide(file: "DataMover_Guia_ES.pdf", lang: "es", title: "DataMover — Guía de uso",
    subtitle: "Offload verificado para producción de vídeo: origen → verificación → copias independientes",
    toc: "Índice", page: "Página %d de %d", forVersion: "Para DataMover %@ · macOS y Windows",
    sections: [
    Sec(title: "Qué hace DataMover", blocks: [
        .p("DataMover copia el material de una tarjeta o carpeta a varios discos independientes al mismo tiempo. El origen se lee **una sola vez**, y cada copia se compara con el origen por checksum antes de recibir su nombre final."),
        .bullets(["**Origen** — la tarjeta de la cámara o una carpeta.", "**Verificación** — el checksum de cada copia debe coincidir con el del origen.", "**Copias independientes** — dos o más discos, cada uno con su resultado y sus informes."]),
        .warn("No formatees la tarjeta hasta que todos los destinos muestren **Verificado**. DataMover reduce el riesgo al copiar; no lo elimina."),
    ]),
    Sec(title: "Instalación en macOS", blocks: [
        .p("Requisitos: macOS 14 o posterior, en un Mac con Apple Silicon. El paquete está firmado con Developer ID y notarizado por Apple, así que Gatekeeper lo abre sin pasos adicionales."),
        .steps(["Descarga **DataMover.dmg** desde gordas.dev/datamover.", "Abre el DMG. En la ventana están el paquete **DataMover-x.y.z.pkg** y esta guía.", "Haz doble clic en el paquete y sigue los pasos. Acepta el acuerdo de licencia.", "Cuando se te pida, introduce la contraseña de administrador del Mac (los caracteres no se ven — es normal) y pulsa Intro.", "Abre DataMover desde la carpeta **Aplicaciones**."]),
    ]),
    Sec(title: "Instalación en Windows", blocks: [
        .p("Requisitos: Windows 11, 64 bits (x64). En equipos ARM64, la aplicación funciona mediante la emulación x64 del sistema."),
        .steps(["Descarga **DataMover-WPF-Windows.zip** y extrae el archivo.", "Ejecuta **DataMoverSetup.exe** y acepta el acuerdo de licencia.", "La aplicación se instala en Archivos de programa, con acceso directo en el menú Inicio. El acceso directo en el Escritorio es opcional; lo marcas en el asistente."]),
        .warn("El instalador de Windows tiene una firma **autofirmada**, no un certificado comercial. Windows SmartScreen puede mostrar “Windows protegió su PC” o “Editor desconocido”. Si descargaste el archivo desde gordas.dev, pulsa **Más información** → **Ejecutar de todas formas**."),
        .p("Se desinstala desde **Configuración → Aplicaciones**. También elimina los ajustes de DataMover, la licencia local y los registros de diagnóstico; los datos de otras aplicaciones GDC no se tocan."),
    ]),
    Sec(title: "Actualizaciones", blocks: [
        .p("Al iniciarse, DataMover comprueba si hay una versión nueva y te muestra el número de versión y las novedades. También puedes comprobarlo manualmente desde la aplicación."),
        .bullets(["**macOS** — **Descargar e instalar** descarga el paquete, comprueba su versión y su firma, pide la contraseña de administrador y reinicia la aplicación. **Más tarde** pospone esa versión.", "**Windows** — en la ventana “Actualizare disponibilă” (actualización disponible), **Sí** descarga el instalador y abre el asistente; la aplicación se cierra y vuelve a abrirse tras la instalación. **No** pospone la actualización.", "Una actualización nunca se instala en segundo plano sin tu consentimiento."]),
    ]),
    Sec(title: "Preparar un offload", blocks: [
        .p("Rellena **Proyecto** y **Tarjeta** en la barra superior. Con ellos se forma el nombre de la carpeta creada en cada destino (por ejemplo 2026-09-26_PROYECTO_A001)."),
        .bullets(["**Origen** — arrastra la tarjeta o carpeta a la zona Origen, usa el botón de añadir o elígela en la lista de dispositivos.", "**Destinos** — añade al menos una copia; por seguridad, usa dos discos distintos. En macOS, arrastra un disco a “+ otra copia” o elige su función en el menú del dispositivo; en Windows, pulsa **Copia** bajo el dispositivo.", "**Verificación** — xxHash64 por defecto (rápido). En Ajustes puedes elegir MD5, SHA-1, SHA-256, SHA-512 o “solo tamaño”."]),
        .img("mac-prepare.jpg", "macOS, preparación: el origen, las dos copias y los avisos antes de empezar (interfaz en rumano)."),
    ]),
    Sec(title: "Comprobaciones antes de empezar", blocks: [
        .p("Antes de empezar, la aplicación revisa la ruta. Los problemas **bloqueantes** desactivan el botón de inicio; los **avisos** no bloquean, pero conviene leerlos antes de formatear la tarjeta."),
        .table([["Situación", "Tipo"], ["El destino está dentro del origen (o al revés)", "Bloqueante"], ["El mismo destino elegido dos veces, destinos anidados", "Bloqueante"], ["Ruta inexistente o sin permiso de escritura, colisiones de nombres", "Bloqueante"], ["Una copia quedaría en el mismo disco que el origen", "Aviso"], ["Espacio insuficiente en un destino", "Aviso, con confirmación"], ["Estructura inusual de la tarjeta (p. ej. archivos de 0 bytes)", "Aviso"]]),
    ]),
    Sec(title: "Transferencia y verificación", blocks: [
        .p("Pulsa **Iniciar transferencia**. El origen se lee una sola vez y se escribe en paralelo en todas las copias. Cada archivo se escribe primero con la extensión temporal **.dmpart** y recibe su nombre final solo tras el flush a disco y cuando el checksum de la copia coincide con el origen."),
        .bullets(["El progreso se muestra para cada destino; las cifras son medidas, no estimadas.", "Puedes **Pausar** o **Cancelar** la transferencia.", "Si un disco se desconecta, el problema aparece solo en su destino; las demás copias continúan.", "Un archivo que cambia en la tarjeta durante la copia se marca como no confirmado."]),
        .img("mac-transfer.jpg", "macOS, transferencia en curso: progreso medido en cada copia."),
        .img("win-transfer.jpg", "Windows, transferencia en curso: la misma lógica en una interfaz nativa de Windows."),
    ]),
    Sec(title: "El resultado", blocks: [
        .p("Al terminar ves un único veredicto, sin ambigüedad, y un resultado para cada destino."),
        .table([["Veredicto", "Significado"], ["Verificado", "Cada archivo superó la verificación elegida en cada destino."], ["Verificado, con avisos", "Todo está confirmado, pero algunos archivos solo tras reintentar. Revisa el cable, la tarjeta y los discos."], ["Fallo parcial", "Al menos un destino tiene archivos sin confirmar. No formatees la tarjeta."], ["Fallo", "Ningún destino tiene una copia completa confirmada."], ["Cancelado", "La transferencia se detuvo; los archivos confirmados se conservan."]]),
        .img("mac-result.jpg", "macOS, resultado: cada copia confirmada por separado, con sus informes."),
        .note("La expulsión automática de la tarjeta (opcional, en Ajustes) solo ocurre cuando todos los destinos tienen una copia confirmada."),
    ]),
    Sec(title: "Informes de entrega", blocks: [
        .p("En la carpeta creada en cada destino, DataMover escribe:"),
        .bullets(["**PDF y HTML** — el informe de entrega: el veredicto del destino, un resumen (archivos, datos confirmados, duración, verificación), proyecto, tarjeta, operador y la lista de archivos con checksum y estado. El HTML se abre en cualquier navegador y se imprime en A4.", "**CSV** — la lista completa, una fila por archivo (columnas: archivo, tamaño, verificación de origen, verificación de destino, estado, error). Está en UTF-8 con marca, para que los acentos se lean bien.", "**MHL** — la lista de hashes para la cadena de custodia de postproducción. Solo se genera con xxHash64, MD5 o SHA-1, los algoritmos que admite el estándar MHL.", "**offload_checkpoint.json** — se usa al reanudar."]),
        .img("report-pdf.jpg", "Primera página del informe PDF (datos de prueba, en rumano)."),
        .note("En transferencias muy grandes, el PDF y el HTML muestran todos los problemas y una muestra; la lista completa está en el CSV."),
    ]),
    Sec(title: "Reanudar una transferencia", blocks: [
        .p("Si una transferencia se interrumpió, iníciala de nuevo con el mismo origen y los mismos destinos. Con **Reanudar automáticamente desde un punto de control** (activado por defecto), DataMover vuelve a leer el origen y la copia de cada archivo ya confirmado: deben coincidir con el checksum guardado al confirmar; si no, el archivo se copia otra vez."),
        .bullets(["El nombre, el tamaño o la fecha nunca bastan para saltar un archivo.", "Un checkpoint hecho con otro algoritmo o para otra carpeta se ignora.", "En modo “solo tamaño”, la reanudación vuelve a copiarlo todo."]),
        .warn("La reanudación se ha probado tras interrupciones simuladas. El comportamiento tras un corte de corriente real o un disco extraído físicamente aún no se ha verificado — después de un incidente así, revisa el resultado final."),
    ]),
    Sec(title: "Ajustes e idioma", blocks: [
        .p("**macOS** — menú DataMover → Ajustes, con las pestañas General, Verificación, Informes, Rendimiento, Nube, Cuenta y Diagnóstico. En General eliges el idioma (rumano, inglés, español) y el aspecto (Sistema, Claro, Oscuro), además de abrir el destino, expulsar la tarjeta e iniciar automáticamente al insertar una tarjeta."),
        .img("mac-settings.jpg", "macOS, Ajustes → General (interfaz en rumano)."),
        .p("**Windows** — el botón **Setări** (Ajustes) de la barra superior: verificación, MHL, reintento automático, perfil de rendimiento, logotipo de los informes y tema. La interfaz de Windows está en rumano."),
    ]),
    Sec(title: "Diagnóstico", blocks: [
        .p("DataMover guarda un registro técnico local. No se envía nada automáticamente. Si tienes un problema, exporta el diagnóstico y envíanos el archivo ZIP."),
        .bullets(["**macOS** — Ayuda → Exportar diagnóstico… (o Ajustes → Diagnóstico).", "**Windows** — el botón **Diagnostic** de la parte inferior → Exportar diagnóstico.", "La exportación contiene los registros, la versión y un resumen de la última transferencia. Las rutas y los nombres de archivo se sustituyen por códigos; no contiene archivos multimedia, contraseñas ni códigos de licencia."]),
    ]),
    Sec(title: "Diferencias entre macOS y Windows", blocks: [
        .p("Las dos aplicaciones siguen las mismas reglas de copia y generan los mismos tipos de informes con la misma información. Las interfaces son nativas y difieren:"),
        .table([["", "macOS", "Windows"], ["Idioma de la interfaz", "Rumano, inglés, español", "Rumano"], ["Idioma de los informes", "El de la aplicación", "El de Windows (ro/en/es); si no, rumano"], ["Firma", "Developer ID, notarizado por Apple", "Autofirmada (SmartScreen puede avisar)"], ["Actualización", "Instalación automática, con contraseña", "El asistente de instalación de Windows"], ["Guía en la aplicación", "Ayuda, en el idioma de la aplicación", "Botón Ghid, en rumano"]]),
    ]),
    Sec(title: "Prueba y activación", blocks: [
        .bullets(["**7 días** totalmente funcional, sin cuenta y sin tarjeta.", "Tras la prueba, la versión sin activar copia como máximo **2 GB** por transferencia.", "La activación está ligada al ID del ordenador y se obtiene con una **donación** para el desarrollo; el importe actual aparece en la aplicación. Abre Perfil → Activar y envíanos el ID del ordenador por WhatsApp."]),
    ]),
    Sec(title: "Límites conocidos", blocks: [
        .p("Los escenarios siguientes aún no se han verificado. No los consideres cubiertos hasta probarlos en tu entorno:"),
        .bullets(["un corte de corriente o apagado brusco real durante la copia;", "una tarjeta o disco extraído físicamente durante la transferencia;", "destinos de red (SMB) y discos exFAT en Windows;", "un disco lleno real en Windows;", "navegación solo con teclado y lectores de pantalla en Windows."]),
    ]),
])

// MARK: - Tipografie și culori (aceeași paletă ca raportul de livrare)

let ink = NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1)
let dim = NSColor(srgbRed: 0.36, green: 0.39, blue: 0.44, alpha: 1)
let rule = NSColor(srgbRed: 0.84, green: 0.85, blue: 0.87, alpha: 1)
let band = NSColor(srgbRed: 0.965, green: 0.97, blue: 0.975, alpha: 1)
let amber = NSColor(srgbRed: 0.72, green: 0.41, blue: 0.12, alpha: 1)
let warnC = NSColor(srgbRed: 0.60, green: 0.38, blue: 0.0, alpha: 1)
let bg = NSColor(srgbRed: 0.078, green: 0.086, blue: 0.10, alpha: 1)

func font(_ size: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont { NSFont.systemFont(ofSize: size, weight: w) }

/// Text cu **îngroșări**.
func rich(_ s: String, _ size: CGFloat, color: NSColor = ink, weight: NSFont.Weight = .regular, align: NSTextAlignment = .left, spacing: CGFloat = 2.5) -> NSAttributedString {
    let p = NSMutableParagraphStyle(); p.lineSpacing = spacing; p.alignment = align; p.lineBreakMode = .byWordWrapping
    let out = NSMutableAttributedString()
    for (i, part) in s.components(separatedBy: "**").enumerated() {
        out.append(NSAttributedString(string: part, attributes: [.font: font(size, i % 2 == 1 ? .semibold : weight), .foregroundColor: color, .paragraphStyle: p]))
    }
    return out
}
func textHeight(_ a: NSAttributedString, _ w: CGFloat) -> CGFloat {
    let fs = CTFramesetterCreateWithAttributedString(a)
    return ceil(CTFramesetterSuggestFrameSizeWithConstraints(fs, CFRange(), nil, CGSize(width: w, height: .greatestFiniteMagnitude), nil).height)
}
var overflow: [String] = []
@discardableResult
func draw(_ a: NSAttributedString, _ ctx: CGContext, x: CGFloat, top: CGFloat, w: CGFloat) -> CGFloat {
    let h = textHeight(a, w)
    let fs = CTFramesetterCreateWithAttributedString(a)
    let frame = CTFramesetterCreateFrame(fs, CFRange(), CGPath(rect: CGRect(x: x, y: top - h - 1, width: w, height: h + 2), transform: nil), nil)
    if CTFrameGetVisibleStringRange(frame).length < a.length { overflow.append(String(a.string.prefix(40))) }
    CTFrameDraw(frame, ctx)
    return h
}
func loadImage(_ name: String) -> CGImage? {
    guard let d = try? Data(contentsOf: dir.appendingPathComponent("img/\(name)")) as CFData,
          let src = CGImageSourceCreateWithData(d, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

// MARK: - Layout (două treceri: întâi paginile, apoi desenul cu cuprinsul corect)

let W: CGFloat = 595, H: CGFloat = 842, M: CGFloat = 54
let CW = W - 2 * M, topY = H - M - 34, bottomY = M + 30

struct Placed { let page: Int; let top: CGFloat; let height: CGFloat; let draw: (CGContext, CGFloat) -> Void }

func build(_ g: Guide) -> (pages: Int, problems: [String]) {
    var problems: [String] = []
    var items: [Placed] = []
    var sectionPage: [Int] = []
    var page = 3, y = topY   // 1 = copertă, 2 = cuprins
    func place(_ h: CGFloat, keepWith next: CGFloat = 0, _ d: @escaping (CGContext, CGFloat) -> Void) {
        if y - h - next < bottomY && y < topY - 1 { page += 1; y = topY }
        if h > topY - bottomY { problems.append("bloc prea înalt pe pagina \(page)") }
        items.append(Placed(page: page, top: y, height: h, draw: d)); y -= h
    }
    for (si, sec) in g.sections.enumerated() {
        let head = rich("\(si + 1)  \(sec.title)", 16, weight: .semibold)
        let hh = textHeight(head, CW) + 8
        if si > 0 { y -= 18 }
        place(hh + 10, keepWith: 60) { ctx, top in
            ctx.setFillColor(amber.cgColor); ctx.fill(CGRect(x: M, y: top - 4, width: 22, height: 2.5))
            draw(head, ctx, x: M, top: top - 10, w: CW)
        }
        sectionPage.append(items.last!.page)
        for b in sec.blocks {
            switch b {
            case .p(let s):
                let a = rich(s, 10.5); let h = textHeight(a, CW)
                place(h + 9) { ctx, top in draw(a, ctx, x: M, top: top, w: CW) }
            case .bullets(let list), .steps(let list):
                var isStep = false; if case .steps = b { isStep = true }
                for (i, s) in list.enumerated() {
                    let a = rich(s, 10.5); let h = textHeight(a, CW - 22)
                    let mark = rich(isStep ? "\(i + 1)." : "—", 10.5, color: amber, weight: .semibold)
                    place(h + 6) { ctx, top in draw(mark, ctx, x: M + 2, top: top, w: 20); draw(a, ctx, x: M + 22, top: top, w: CW - 22) }
                }
                y -= 4
            case .note(let s), .warn(let s):
                var isWarn = false; if case .warn = b { isWarn = true }
                let label = rich(isWarn ? "!" : "i", 13, color: isWarn ? warnC : amber, weight: .bold, align: .center)
                let a = rich(s, 10); let h = textHeight(a, CW - 44) + 18
                place(h + 10) { ctx, top in
                    ctx.setFillColor(band.cgColor); ctx.fill(CGRect(x: M, y: top - h, width: CW, height: h))
                    ctx.setFillColor((isWarn ? warnC : amber).cgColor); ctx.fill(CGRect(x: M, y: top - h, width: 3, height: h))
                    draw(label, ctx, x: M + 8, top: top - 7, w: 20); draw(a, ctx, x: M + 32, top: top - 9, w: CW - 44)
                }
            case .img(let name, let cap):
                guard let img = loadImage(name) else { problems.append("imagine lipsă: \(name)"); continue }
                var w = CW, h = CW * CGFloat(img.height) / CGFloat(img.width)
                let maxH: CGFloat = 300
                if h > maxH { h = maxH; w = h * CGFloat(img.width) / CGFloat(img.height) }
                let c = rich(cap, 8.5, color: dim); let ch = textHeight(c, CW)
                place(h + ch + 20) { ctx, top in
                    let r = CGRect(x: M + (CW - w) / 2, y: top - h - 4, width: w, height: h)
                    ctx.draw(img, in: r)
                    ctx.setStrokeColor(rule.cgColor); ctx.setLineWidth(0.6); ctx.stroke(r)
                    draw(c, ctx, x: M, top: top - h - 10, w: CW)
                }
            case .table(let rows):
                let cols = rows[0].count
                let widths: [CGFloat] = cols == 2 ? [CW * 0.42, CW * 0.58] : [CW * 0.26, CW * 0.37, CW * 0.37]
                for (ri, row) in rows.enumerated() {
                    let cells = row.map { rich($0, ri == 0 ? 8.5 : 9.5, color: ri == 0 ? dim : ink, weight: ri == 0 ? .semibold : .regular) }
                    let h = zip(cells, widths).map { textHeight($0, $1 - 12) }.max()! + 10
                    place(h) { ctx, top in
                        if ri == 0 { ctx.setFillColor(band.cgColor); ctx.fill(CGRect(x: M, y: top - h, width: CW, height: h)) }
                        var x = M
                        for (a, w) in zip(cells, widths) { draw(a, ctx, x: x + 6, top: top - 5, w: w - 12); x += w }
                        ctx.setStrokeColor((ri == 0 ? ink : rule).cgColor); ctx.setLineWidth(ri == 0 ? 0.9 : 0.5)
                        ctx.move(to: CGPoint(x: M, y: top - h)); ctx.addLine(to: CGPoint(x: M + CW, y: top - h)); ctx.strokePath()
                    }
                }
                y -= 8
            }
        }
    }
    let total = page

    // Desen
    let url = dir.appendingPathComponent(g.file)
    var box = CGRect(x: 0, y: 0, width: W, height: H)
    let info: [CFString: Any] = [kCGPDFContextTitle: g.title, kCGPDFContextCreator: "DataMover \(version)", kCGPDFContextAuthor: "GDC · gordas.dev"]
    guard let ctx = CGContext(url as CFURL, mediaBox: &box, info as CFDictionary) else { return (0, ["nu pot crea \(g.file)"]) }

    func mark(_ ctx: CGContext, x: CGFloat, top: CGFloat, size: CGFloat, color: NSColor, node: NSColor, line: CGFloat) {
        let s = size / 724
        func pt(_ px: CGFloat, _ py: CGFloat) -> CGPoint { CGPoint(x: x + (px - 150) * s, y: top - (py - 150) * s) }
        let p = CGMutablePath()
        p.move(to: pt(232, 512)); p.addLine(to: pt(430, 512)); p.addCurve(to: pt(598, 392), control1: pt(505, 512), control2: pt(520, 392)); p.addLine(to: pt(792, 392))
        p.move(to: pt(430, 512)); p.addCurve(to: pt(598, 632), control1: pt(505, 512), control2: pt(520, 632)); p.addLine(to: pt(792, 632))
        ctx.addPath(p); ctx.setStrokeColor(color.cgColor); ctx.setLineWidth(line); ctx.setLineCap(.round); ctx.strokePath()
        let c = pt(430, 512), r = 40 * s
        ctx.setFillColor(node.cgColor); ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    }
    func chrome(_ n: Int) {
        mark(ctx, x: M, top: H - M + 8, size: 18, color: amber, node: ink, line: 2)
        draw(rich("DataMover", 9.5, weight: .semibold), ctx, x: M + 24, top: H - M + 5, w: 120)
        draw(rich(g.title.components(separatedBy: " — ").last ?? g.title, 8, color: dim, align: .right), ctx, x: W - M - 260, top: H - M + 4, w: 260)
        ctx.setStrokeColor(ink.cgColor); ctx.setLineWidth(1); ctx.move(to: CGPoint(x: M, y: H - M - 16)); ctx.addLine(to: CGPoint(x: W - M, y: H - M - 16)); ctx.strokePath()
        ctx.setStrokeColor(rule.cgColor); ctx.setLineWidth(0.6); ctx.move(to: CGPoint(x: M, y: M + 16)); ctx.addLine(to: CGPoint(x: W - M, y: M + 16)); ctx.strokePath()
        draw(rich("gordas.dev/datamover · DataMover \(version)", 7.5, color: dim), ctx, x: M, top: M + 10, w: 300)
        draw(rich(String(format: g.page, n, total), 7.5, color: dim, weight: .semibold, align: .right), ctx, x: W - M - 150, top: M + 10, w: 150)
    }

    // 1. Copertă
    ctx.beginPDFPage(nil)
    ctx.setFillColor(bg.cgColor); ctx.fill(box)
    mark(ctx, x: M - 6, top: H - 150, size: 150, color: amber, node: NSColor(srgbRed: 0.93, green: 0.94, blue: 0.95, alpha: 1), line: 14)
    let light = NSColor(srgbRed: 0.93, green: 0.94, blue: 0.95, alpha: 1), lightDim = NSColor(srgbRed: 0.62, green: 0.66, blue: 0.71, alpha: 1)
    var cy = H - 360
    cy -= draw(rich("DataMover", 40, color: light, weight: .bold), ctx, x: M, top: cy, w: CW) + 6
    cy -= draw(rich(g.title.components(separatedBy: " — ").last ?? "", 22, color: NSColor(srgbRed: 0.93, green: 0.60, blue: 0.32, alpha: 1), weight: .semibold), ctx, x: M, top: cy, w: CW) + 18
    cy -= draw(rich(g.subtitle, 12, color: lightDim), ctx, x: M, top: cy, w: CW * 0.8) + 30
    draw(rich(String(format: g.forVersion, version), 10, color: lightDim, weight: .medium), ctx, x: M, top: M + 60, w: CW)
    draw(rich("gordas.dev/datamover", 10, color: lightDim), ctx, x: M, top: M + 44, w: CW)
    ctx.endPDFPage()

    // 2. Cuprins
    ctx.beginPDFPage(nil); chrome(2)
    var ty = topY - 6
    ty -= draw(rich(g.toc, 20, weight: .semibold), ctx, x: M, top: ty, w: CW) + 18
    for (i, sec) in g.sections.enumerated() {
        let t = rich("\(i + 1)   \(sec.title)", 11); let pn = rich(String(sectionPage[i]), 11, color: dim, align: .right)
        draw(t, ctx, x: M, top: ty, w: CW - 40); draw(pn, ctx, x: W - M - 40, top: ty, w: 40)
        ty -= 22
        ctx.setStrokeColor(rule.cgColor); ctx.setLineWidth(0.4); ctx.move(to: CGPoint(x: M, y: ty + 7)); ctx.addLine(to: CGPoint(x: W - M, y: ty + 7)); ctx.strokePath()
    }
    ctx.endPDFPage()

    // 3+. Conținut
    for p in 3...total {
        ctx.beginPDFPage(nil); chrome(p)
        for it in items where it.page == p { it.draw(ctx, it.top) }
        ctx.endPDFPage()
    }
    ctx.closePDF()
    return (total, problems)
}

// MARK: - Generare + verificare

var failed = false
let banned = ["preț", "pret", "cumpără", "vânzare", "price", "buy", "precio", "comprar", "venta"]
for g in [ro, en, es] {
    overflow = []
    let (pages, problems) = build(g)
    guard let doc = PDFDocument(url: dir.appendingPathComponent(g.file)) else { print("✗ \(g.file): nu se poate deschide"); failed = true; continue }
    let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
    var issues = problems + overflow.map { "text tăiat: \($0)…" }
    for s in g.sections where !text.contains(s.title) { issues.append("secțiune lipsă: \(s.title)") }
    let words = Set(text.lowercased().components(separatedBy: CharacterSet.letters.inverted))
    for w in banned where words.contains(w) { issues.append("cuvânt interzis: \(w)") }
    if doc.pageCount != pages { issues.append("pagini \(doc.pageCount) ≠ \(pages)") }
    let size = (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(g.file).path)[.size] as? Int) ?? 0
    print("\(issues.isEmpty ? "✓" : "✗") \(g.file): \(doc.pageCount) pagini, \(g.sections.count) secțiuni, \(size / 1024) KB\(issues.isEmpty ? "" : " — " + issues.joined(separator: "; "))")
    if !issues.isEmpty { failed = true }
}
if [ro, en, es].map({ $0.sections.count }) != Array(repeating: ro.sections.count, count: 3) { print("✗ numărul de secțiuni diferă între limbi"); failed = true }
exit(failed ? 1 : 0)
