import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case ro, en, es
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .ro: return "Română"
        case .en: return "English"
        case .es: return "Español"
        }
    }
}

/// Tiny in-app translation table, independent of system locale — acelasi
/// tipar RO-implicit / EN / ES folosit si in CursorPro GDC. Persistat prin
/// UserDefaults, ca alegerea sa ramana intre lansari.
enum L {
    static var current: AppLanguage {
        get {
            if let raw = UserDefaults.standard.string(forKey: "datamover_lang"),
               let lang = AppLanguage(rawValue: raw) {
                return lang
            }
            return .ro
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "datamover_lang") }
    }

    static func t(_ key: String) -> String {
        table[key]?[current] ?? table[key]?[.ro] ?? key
    }

    fileprivate static let table: [String: [AppLanguage: String]] = [
        "prefs.language": [.ro: "Limba", .en: "Language", .es: "Idioma"],

        // MARK: - Trial bar
        "trial.daysLeft": [.ro: "Proba gratuita — %d zile ramase", .en: "Free trial — %d days left", .es: "Prueba gratuita — %d días restantes"],
        "trial.activate": [.ro: "Activeaza licenta", .en: "Activate license", .es: "Activar licencia"],

        // MARK: - Meta bar (Proiect/Card)
        "meta.project": [.ro: "Proiect", .en: "Project", .es: "Proyecto"],
        "meta.card": [.ro: "Card", .en: "Card", .es: "Tarjeta"],

        // MARK: - Sources
        "sources.title": [.ro: "SURSE", .en: "SOURCES", .es: "ORÍGENES"],
        "sources.dropHint": [.ro: "Trage fisiere\nsau foldere aici", .en: "Drag files\nor folders here", .es: "Arrastra archivos\no carpetas aquí"],
        "sources.empty": [.ro: "Nicio sursa adaugata", .en: "No sources added", .es: "Sin orígenes añadidos"],

        // MARK: - Disks
        "disks.title": [.ro: "Discuri", .en: "Disks", .es: "Discos"],
        "disks.iconSize": [.ro: "Marime iconite", .en: "Icon size", .es: "Tamaño de iconos"],

        // MARK: - Destinations
        "dest.title": [.ro: "DESTINATII", .en: "DESTINATIONS", .es: "DESTINOS"],
        "dest.dropHint": [.ro: "Trage un disc din Discuri,\nsau un folder din Finder", .en: "Drag a disk from Disks,\nor a folder from Finder", .es: "Arrastra un disco desde Discos,\no una carpeta desde Finder"],

        // MARK: - Footer
        "footer.needSourcesDest": [.ro: "Adauga surse si destinatii ca sa pornesti", .en: "Add sources and destinations to start", .es: "Añade orígenes y destinos para empezar"],
        "footer.summary": [.ro: "%d surse -> %d destinatie(i)", .en: "%d sources -> %d destination(s)", .es: "%d orígenes -> %d destino(s)"],
        "footer.cancel": [.ro: "Anuleaza", .en: "Cancel", .es: "Cancelar"],
        "footer.start": [.ro: "Start", .en: "Start", .es: "Iniciar"],
        "footer.copying": [.ro: "Se copiaza...", .en: "Copying...", .es: "Copiando..."],
        "footer.cancelled": [.ro: "Anulat.", .en: "Cancelled.", .es: "Cancelado."],
        "footer.finished": [.ro: "Finalizat", .en: "Finished", .es: "Terminado"],
        "footer.problems": [.ro: "probleme", .en: "problems", .es: "problemas"],
        "footer.noFiles": [.ro: "Nu am gasit niciun fisier de copiat.", .en: "No files found to copy.", .es: "No se encontraron archivos para copiar."],
        "status.ready": [.ro: "Gata de pornire", .en: "Ready to start", .es: "Listo para empezar"],
        "status.cancelling": [.ro: "Se anuleaza...", .en: "Cancelling...", .es: "Cancelando..."],
        "footer.filesWord": [.ro: "fisiere", .en: "files", .es: "archivos"],

        // MARK: - Settings popover
        "settings.title": [.ro: "Setari copiere", .en: "Copy settings", .es: "Ajustes de copia"],
        "settings.verificationModel": [.ro: "Model de verificare", .en: "Verification model", .es: "Modelo de verificación"],
        "settings.exclusions": [.ro: "Excluderi (nume exact sau .extensie, separate prin virgula)", .en: "Exclusions (exact name or .extension, comma-separated)", .es: "Exclusiones (nombre exacto o .extensión, separadas por comas)"],
        "settings.resume": [.ro: "Reia automat dintr-un checkpoint existent", .en: "Resume automatically from an existing checkpoint", .es: "Reanudar automáticamente desde un punto de control"],
        "settings.openLastReport": [.ro: "Deschide ultimul raport in Finder", .en: "Open last report in Finder", .es: "Abrir el último informe en Finder"],

        "verif.md5": [.ro: "MD5 (rapid)", .en: "MD5 (fast)", .es: "MD5 (rápido)"],
        "verif.sha1": [.ro: "SHA-1 (echilibrat)", .en: "SHA-1 (balanced)", .es: "SHA-1 (equilibrado)"],
        "verif.sha256": [.ro: "SHA-256 (recomandat pentru arhivare)", .en: "SHA-256 (recommended for archiving)", .es: "SHA-256 (recomendado para archivo)"],
        "verif.sha512": [.ro: "SHA-512 (maxim de siguranta)", .en: "SHA-512 (maximum safety)", .es: "SHA-512 (máxima seguridad)"],
        "verif.sizeOnly": [.ro: "Doar dimensiune (rapid, mai putin sigur)", .en: "Size only (fast, less safe)", .es: "Solo tamaño (rápido, menos seguro)"],

        // MARK: - History
        "history.title": [.ro: "Istoric copieri", .en: "Copy history", .es: "Historial de copias"],
        "history.empty": [.ro: "Nicio copiere efectuata inca.", .en: "No copy jobs yet.", .es: "Aún no se ha copiado nada."],
        "history.ok": [.ro: "OK", .en: "OK", .es: "OK"],
        "history.skipped": [.ro: "Sarite", .en: "Skipped", .es: "Omitidos"],
        "history.failed": [.ro: "Esuate", .en: "Failed", .es: "Fallidos"],

        // MARK: - Activation sheet
        "activation.title": [.ro: "Activare DataMover", .en: "Activate DataMover", .es: "Activar DataMover"],
        "activation.machineID": [.ro: "ID calculator (trimite-mi asta):", .en: "Computer ID (send me this):", .es: "ID del ordenador (envíamelo):"],
        "activation.copy": [.ro: "Copiaza", .en: "Copy", .es: "Copiar"],
        "activation.copied": [.ro: "Copiat!", .en: "Copied!", .es: "¡Copiado!"],
        "activation.codePlaceholder": [.ro: "Cod licenta", .en: "License code", .es: "Código de licencia"],
        "activation.donation": [.ro: "Cei 23 € sunt o donatie, nu un pret de lista — ma ajuta sa acopar costurile de dezvoltare si sa continui sa intretin si imbunatatesc aplicatia.",
                                 .en: "The 23 € is a donation, not a list price — it helps me cover development costs and keep maintaining and improving the app.",
                                 .es: "Los 23 € son una donación, no un precio de lista — me ayudan a cubrir los costes de desarrollo y a seguir manteniendo y mejorando la aplicación."],
        "activation.whatsapp": [.ro: "Contacteaza-ma pe WhatsApp pentru cumparare/suport", .en: "Contact me on WhatsApp to buy / for support", .es: "Contáctame por WhatsApp para comprar / soporte"],
        "activation.cancel": [.ro: "Anuleaza", .en: "Cancel", .es: "Cancelar"],
        "activation.activate": [.ro: "Activeaza", .en: "Activate", .es: "Activar"],

        // MARK: - License errors
        "license.error.malformed": [.ro: "Format de cod invalid.", .en: "Invalid code format.", .es: "Formato de código no válido."],
        "license.error.badSignature": [.ro: "Cod serial invalid — semnatura nu se potriveste.", .en: "Invalid serial code — signature mismatch.", .es: "Código de serie no válido — la firma no coincide."],
        "license.error.wrongProduct": [.ro: "Acest cod e pentru alt produs.", .en: "This code is for a different product.", .es: "Este código es para otro producto."],
        "license.error.wrongMachine": [.ro: "Acest cod e activat pentru alt calculator.", .en: "This code is activated for a different computer.", .es: "Este código está activado para otro ordenador."],
        "license.error.expired": [.ro: "Codul serial a expirat.", .en: "The serial code has expired.", .es: "El código de serie ha caducado."],

        // MARK: - App menu / About
        "menu.about": [.ro: "Despre DataMover", .en: "About DataMover", .es: "Acerca de DataMover"],
        "menu.checkForUpdates": [.ro: "Verifica actualizari...", .en: "Check for Updates...", .es: "Buscar actualizaciones..."],
        "menu.help": [.ro: "Ghid de utilizare DataMover", .en: "DataMover User Guide", .es: "Guía de uso de DataMover"],
        "menu.whatsapp": [.ro: "Contact WhatsApp", .en: "WhatsApp Contact", .es: "Contacto WhatsApp"],
        "about.credits": [.ro: "Dezvoltat de GDC — dumitrugdc@gmail.com", .en: "Developed by GDC — dumitrugdc@gmail.com", .es: "Desarrollado por GDC — dumitrugdc@gmail.com"],
        "about.rights": [.ro: "Toate drepturile rezervate.", .en: "All rights reserved.", .es: "Todos los derechos reservados."],

        // MARK: - Update checker
        "update.upToDate.title": [.ro: "Esti la zi", .en: "You're up to date", .es: "Estás al día"],
        "update.upToDate.body": [.ro: "Ai deja ultima versiune (%@).", .en: "You already have the latest version (%@).", .es: "Ya tienes la última versión (%@)."],
        "update.available.title": [.ro: "Versiune noua disponibila", .en: "New version available", .es: "Nueva versión disponible"],
        "update.available.body": [.ro: "Versiunea %@ este disponibila (ai %@).", .en: "Version %@ is available (you have %@).", .es: "La versión %@ está disponible (tienes %@)."],
        "update.download": [.ro: "Descarca", .en: "Download", .es: "Descargar"],
        "update.later": [.ro: "Mai tarziu", .en: "Later", .es: "Más tarde"],
        "update.error.title": [.ro: "Verificare actualizari", .en: "Check for Updates", .es: "Buscar actualizaciones"],
        "update.error.body": [.ro: "Nu am putut verifica versiunea — incearca mai tarziu.", .en: "Couldn't check the version — try again later.", .es: "No se pudo comprobar la versión — inténtalo más tarde."],

        // MARK: - Help window
        "help.windowTitle": [.ro: "Ghid de utilizare DataMover", .en: "DataMover User Guide", .es: "Guía de uso de DataMover"],
        "help.step1.title": [.ro: "1. Adauga surse", .en: "1. Add sources", .es: "1. Añade orígenes"],
        "help.step1.body": [.ro: "Trage fisiere sau foldere din Finder in coloana SURSE (stanga), sau apasa in zona punctata pentru a alege manual.",
                             .en: "Drag files or folders from Finder into the SOURCES column (left), or click the dashed area to choose manually.",
                             .es: "Arrastra archivos o carpetas desde Finder a la columna ORÍGENES (izquierda), o pulsa en el área punteada para elegir manualmente."],
        "help.step2.title": [.ro: "2. Alege discul sau folderul de destinatie", .en: "2. Choose the destination disk or folder", .es: "2. Elige el disco o carpeta de destino"],
        "help.step2.body": [.ro: "In coloana centrala Discuri apar discurile montate — trage un disc peste coloana DESTINATII (dreapta). Poti trage si un folder direct din Finder peste DESTINATII, ca sa salvezi exact in acel folder, nu neaparat pe radacina unui disc.",
                             .en: "The center Disks column shows mounted disks — drag a disk onto the DESTINATIONS column (right). You can also drag a folder straight from Finder onto DESTINATIONS to save exactly into that folder, not necessarily the root of a whole disk.",
                             .es: "La columna central Discos muestra los discos montados — arrastra un disco a la columna DESTINOS (derecha). También puedes arrastrar una carpeta directamente desde Finder a DESTINOS para guardar exactamente en esa carpeta, no necesariamente en la raíz de un disco."],
        "help.step3.title": [.ro: "3. Denumeste proiectul/cardul (optional)", .en: "3. Name the project/card (optional)", .es: "3. Nombra el proyecto/tarjeta (opcional)"],
        "help.step3.body": [.ro: "Completeaza campurile Proiect si Card de sus — folderul creat la destinatie va avea numele \"AAAA-LL-ZZ_Proiect_Card\". Daca le lasi goale, se folosesc \"Proiect\"/\"Card\".",
                             .en: "Fill in the Project and Card fields above — the folder created at the destination will be named \"YYYY-MM-DD_Project_Card\". If left empty, \"Project\"/\"Card\" are used.",
                             .es: "Rellena los campos Proyecto y Tarjeta de arriba — la carpeta creada en el destino se llamará \"AAAA-MM-DD_Proyecto_Tarjeta\". Si los dejas vacíos, se usan \"Proyecto\"/\"Tarjeta\"."],
        "help.step4.title": [.ro: "4. Setari de copiere", .en: "4. Copy settings", .es: "4. Ajustes de copia"],
        "help.step4.body": [.ro: "Apasa pe butonul rotund cu roata dintata din dreapta jos pentru a alege modelul de verificare (MD5/SHA1/SHA256/SHA512/doar marime), pentru a adauga excluderi (nume sau extensii separate prin virgula) si pentru a activa reluarea automata dintr-un checkpoint existent.",
                             .en: "Tap the round gear button in the bottom right to choose the verification model (MD5/SHA1/SHA256/SHA512/size only), add exclusions (names or extensions, comma-separated), and enable automatic resume from an existing checkpoint.",
                             .es: "Pulsa el botón redondo de engranaje abajo a la derecha para elegir el modelo de verificación (MD5/SHA1/SHA256/SHA512/solo tamaño), añadir exclusiones (nombres o extensiones separados por comas) y activar la reanudación automática desde un punto de control."],
        "help.step5.title": [.ro: "5. Start", .en: "5. Start", .es: "5. Iniciar"],
        "help.step5.body": [.ro: "Apasa Start. Bara de progres si viteza de transfer apar in partea de jos. Poti apasa Anuleaza oricand — la o reluare ulterioara, fisierele deja copiate si verificate sunt sarite automat daca ai lasat activata reluarea.",
                             .en: "Press Start. The progress bar and transfer speed appear at the bottom. You can press Cancel anytime — on a later resume, already-copied and verified files are skipped automatically if resume is enabled.",
                             .es: "Pulsa Iniciar. La barra de progreso y la velocidad de transferencia aparecen abajo. Puedes pulsar Cancelar en cualquier momento — al reanudar más tarde, los archivos ya copiados y verificados se omiten automáticamente si la reanudación está activada."],
        "help.step6.title": [.ro: "6. Raport si istoric", .en: "6. Report and history", .es: "6. Informe e historial"],
        "help.step6.body": [.ro: "La final se scrie un raport CSV si un raport PDF in folderul de destinatie, cu starea fiecarui fisier (OK/sarit/eroare). Apasa butonul cu ceas din footer pentru istoricul tuturor copierilor anterioare (data, proiect/card, surse, destinatii, cate fisiere OK/sarite/esuate).",
                             .en: "At the end a CSV report and a PDF report are written to the destination folder, with each file's status (OK/skipped/error). Tap the clock button in the footer for the history of all previous copy jobs (date, project/card, sources, destinations, OK/skipped/failed counts).",
                             .es: "Al final se escribe un informe CSV y un informe PDF en la carpeta de destino, con el estado de cada archivo (OK/omitido/error). Pulsa el botón de reloj en el pie para ver el historial de todas las copias anteriores (fecha, proyecto/tarjeta, orígenes, destinos, recuentos OK/omitidos/fallidos)."],
        "help.step7.title": [.ro: "7. Licenta", .en: "7. License", .es: "7. Licencia"],
        "help.step7.body": [.ro: "Ai 7 zile de proba gratuita. Apasa \"Activeaza licenta\" din bara de sus oricand in perioada de proba (sau dupa) ca sa introduci codul primit dupa achizitie — sau ca sa ma contactezi direct pe WhatsApp pentru cumparare/suport.",
                             .en: "You get a 7-day free trial. Tap \"Activate license\" in the top bar anytime during (or after) the trial to enter the code you received after purchase — or to contact me directly on WhatsApp to buy or get support.",
                             .es: "Tienes 7 días de prueba gratuita. Pulsa \"Activar licencia\" en la barra superior en cualquier momento durante (o después de) la prueba para introducir el código recibido tras la compra — o para contactarme directamente por WhatsApp para comprar o soporte."],

        "history.clearAll": [.ro: "Sterge tot", .en: "Clear all", .es: "Borrar todo"],
        "history.clearAllConfirm": [.ro: "Stergi tot istoricul copierilor? Nu se poate anula.", .en: "Delete the whole copy history? This can't be undone.", .es: "¿Borrar todo el historial de copias? No se puede deshacer."],
    ]
}

/// Wrapper observabil peste L.current — orice view care il tine ca
/// @ObservedObject se re-randeaza automat cand limba se schimba, indiferent
/// din ce fereastra (activare, setari) a fost schimbata. Fara asta, doua
/// @State locale separate (unul in ContentView, unul in ActivationSheet)
/// nu se sincronizau vizual intre ele.
final class LanguageStore: ObservableObject {
    static let shared = LanguageStore()
    @Published var lang: AppLanguage = L.current {
        didSet { L.current = lang }
    }
    private init() {}
}
