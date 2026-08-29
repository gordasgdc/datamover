import AppKit

/// Verifică dacă aplicația rulează din afara `/Applications` (ex. direct din
/// `mac-native/dist/`, un `.zip` dezarhivat în Downloads) și oferă un prompt
/// nativ de mutare — port 1:1 al `AppMover.swift` din MediaFlow Monitor
/// (Regula 18, Partea 1 din CLAUDE.md).
///
/// [2026-08-29] Adăugat aici DUPĂ ce lipsa lui a produs confuzie reală:
/// DataMover.app se acumula în `mac-native/dist/` (build local) ȘI în
/// `~/Downloads/DataMover-Mac/Aplicatie/` (arhivă descărcată de pe site),
/// niciodată mutat efectiv în `/Applications` — Cristi ajungea mereu să
/// lanseze una din cele două copii vechi, fără să știe care rulează.
enum AppMover {

    /// Apelat o singură dată, la lansare, înainte de orice altă inițializare vizuală.
    static func promptIfNeeded() {
        guard !isInApplicationsFolder() else { return }
        guard !isRunningFromXcodeOrTests() else { return }

        let alert = NSAlert()
        alert.messageText = "Mutare în Aplicații?"
        alert.informativeText = "DataMover rulează în afara folderului Aplicații. Pentru stabilitate (actualizări automate, permisiuni corecte), se recomandă mutarea în /Applications."
        alert.addButton(withTitle: "Mută în Aplicații")
        alert.addButton(withTitle: "Nu acum")
        alert.alertStyle = .informational

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        move()
    }

    private static func isInApplicationsFolder() -> Bool {
        let path = Bundle.main.bundlePath
        let userApps = ("~/Applications" as NSString).expandingTildeInPath
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApps)
    }

    private static func isRunningFromXcodeOrTests() -> Bool {
        let path = Bundle.main.bundlePath
        return path.contains("/DerivedData/") || path.contains("/.build/") || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static func move() {
        let fm = FileManager.default
        let source = URL(fileURLWithPath: Bundle.main.bundlePath)
        let destinationDir = URL(fileURLWithPath: "/Applications")
        let destination = destinationDir.appendingPathComponent(source.lastPathComponent)

        do {
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: source, to: destination)

            // Relansează din noua locație, apoi închide instanța curentă.
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = [destination.path]
            try task.run()

            try? fm.trashItem(at: source, resultingItemURL: nil)
            NSApp.terminate(nil)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Mutare eșuată"
            alert.informativeText = "Nu am putut muta aplicația automat (\(error.localizedDescription)). Mut-o manual în /Applications din Finder — dacă folderul sursă cere permisiuni de administrator, poate fi nevoie de un `sudo rm -rf` manual pe folderul vechi întâi."
            alert.alertStyle = .warning
            alert.runModal()
        }
    }
}
