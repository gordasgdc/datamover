import AppKit

/// Descarca si instaleaza automat un update de aplicatie, fara sa mai
/// treaca prin browser/pagina de GitHub.
///
/// ARCHITECTURE NOTE (2026-08-26): pana acum, "Descarca" din alerta de
/// update chema `NSWorkspace.shared.open(releasesPageURL)` — asta deschidea
/// pagina web github.com/.../releases/latest in browser, nu descarca nimic.
/// Cristi a semnalat exact asta: "ma trimite la GitHub... ar trebui sa se
/// descarce automat". Fix-ul de aici PORTEAZA 1:1 reteta deja verificata
/// (si presupusa functionala) din `core/updater.py` (folosita de
/// clientul Windows/vechiul client Python): descarca .pkg-ul, apoi il
/// instaleaza prin promptul NATIV de parola admin macOS
/// (`do shell script ... with administrator privileges`) — NICIODATA
/// `sudo` interactiv fara TTY (s-ar bloca) si NICIODATA fara sa deschidem
/// Terminal. Acelasi pattern folosit si in gdc-plugin-manager pentru
/// elevarea de permisiuni OFX.
///
/// WARNING: pasul de instalare (promptul de parola admin) NU poate fi
/// verificat automat de Claude — cere interactiune fizica reala a userului
/// cu fereastra de sistem. Ce s-a verificat automat: descarcarea (URL
/// valid, HTTP 200, fisier scris integral pe disc) si scriptul generat
/// (sintaxa bash valida). Instalarea efectiva TREBUIE confirmata manual,
/// o data, de Cristi, inainte sa consideram fluxul complet dovedit.
enum SelfUpdater {

    enum UpdateError: LocalizedError {
        case downloadFailed(String)
        case installScriptFailed(String)

        var errorDescription: String? {
            switch self {
            case .downloadFailed(let detail): return "Descărcarea a eșuat: \(detail)"
            case .installScriptFailed(let detail): return "Nu am putut porni instalarea: \(detail)"
            }
        }
    }

    /// Descarca `pkgURL` si porneste instalarea, cu feedback vizual minim
    /// (fereastra de progres AppKit — vezi UpdateProgressWindow). La succes,
    /// aplicatia curenta se inchide singura: scriptul de instalare o
    /// relanseaza dupa ce termina, exact ca in `perform_update_mac` din
    /// Python.
    @MainActor
    static func downloadAndInstall(pkgURL: URL, version: String) async {
        let progress = UpdateProgressWindow(version: version)
        progress.show()

        do {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("datamover-update-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let pkgPath = tempDir.appendingPathComponent("DataMover-\(version).pkg")

            progress.setStatus(L.t("update.downloading"))
            try await download(from: pkgURL, to: pkgPath)

            progress.setStatus(L.t("update.installing"))
            try runInstaller(pkgPath: pkgPath, tempDir: tempDir)

            // Scriptul de instalare (pornit mai sus, ruleaza independent sub
            // osascript) se ocupa de tot ce urmeaza: instalare + relansare.
            // Instanta curenta nu mai are ce astepta — se poate inchide.
            progress.close()
            NSApp.terminate(nil)
        } catch {
            progress.close()
            presentFailure(error, fallbackURL: releasesPageURLForFallback)
        }
    }

    // MARK: - Descarcare

    /// Descarca fisierul de la `url` direct pe disc la `destination`.
    /// Pachetele DataMover sunt mici (sute de KB) — nu justifica progres
    /// granular pe octeti, doar starea "se descarcă" / "se instalează".
    private static func download(from url: URL, to destination: URL) async throws {
        let (tempLocation, response): (URL, URLResponse)
        do {
            (tempLocation, response) = try await URLSession.shared.download(from: url)
        } catch {
            throw UpdateError.downloadFailed(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw UpdateError.downloadFailed("HTTP \(code)")
        }
        // `URLSession.download` scrie deja fisierul complet pe disc intr-o
        // locatie temporara proprie — il mutam la calea noastra finala.
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempLocation, to: destination)
    }

    // MARK: - Instalare

    /// Genereaza si porneste (fara sa astepte) scriptul de instalare,
    /// elevat printr-un singur prompt nativ de parola admin.
    ///
    /// Port 1:1 al `perform_update_mac` din core/updater.py: `installer -pkg
    /// ... -target /` scrie logul intr-un fisier (nu avem cum sa citim
    /// stdout-ul unui proces pornit sub `with administrator privileges` in
    /// timp real), apoi relanseaza aplicatia si curata folderul temporar.
    private static func runInstaller(pkgPath: URL, tempDir: URL) throws {
        let logPath = tempDir.appendingPathComponent("datamover_update.log")
        let scriptPath = tempDir.appendingPathComponent("datamover_update.sh")

        let scriptContent = """
        #!/bin/bash
        exec > "\(logPath.path)" 2>&1
        sleep 2
        echo "Instalez actualizarea..."
        installer -pkg "\(pkgPath.path)" -target /
        status=$?
        if [ $status -ne 0 ]; then
            echo "Instalarea a esuat (cod $status)."
            exit $status
        fi
        echo "Pornesc aplicatia actualizata..."
        open -a "DataMover"
        rm -rf "\(tempDir.path)"
        """
        do {
            try scriptContent.write(to: scriptPath, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)
        } catch {
            throw UpdateError.installScriptFailed(error.localizedDescription)
        }

        // Acelasi pattern de elevare ca in gdc-plugin-manager (InstallManager
        // pentru OFX): `osascript ... with administrator privileges`
        // declanseaza promptul NATIV macOS de parola, fara Terminal si fara
        // `sudo` interactiv (care s-ar bloca, fara TTY).
        let escapedPath = scriptPath.path.replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escapedPath)\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        do {
            try process.run()
        } catch {
            throw UpdateError.installScriptFailed(error.localizedDescription)
        }
        // Fire-and-forget INTENTIONAT: promptul de parola e modal la nivel
        // de SISTEM (nu de aplicatia noastra), iar `installer` + relansarea
        // mai dureaza cateva secunde dupa ce userul introduce parola —
        // exact la fel ca in Python, nu blocam UI-ul asteptand procesul.
    }

    // MARK: - Eroare

    private static let releasesPageURLForFallback = URL(string: "https://github.com/gordasgdc/datamover/releases/latest")!

    @MainActor
    private static func presentFailure(_ error: Error, fallbackURL: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L.t("update.installFailed.title")
        alert.informativeText = String(format: L.t("update.installFailed.body"), error.localizedDescription)
        alert.addButton(withTitle: L.t("update.installFailed.openPage"))
        alert.addButton(withTitle: "OK")
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(fallbackURL)
        }
    }
}

/// Fereastra minimala de progres (AppKit, nu SwiftUI) — se potriveste
/// stilului `UpdateChecker`, declansat din meniu, fara acces convenabil la
/// o ierarhie SwiftUI in acel moment. Doar text + un spinner indeterminat:
/// pachetele DataMover sunt prea mici ca sa merite o bara de progres reala.
@MainActor
final class UpdateProgressWindow {
    private let window: NSWindow
    private let statusLabel: NSTextField
    private let spinner: NSProgressIndicator

    init(version: String) {
        let contentRect = NSRect(x: 0, y: 0, width: 360, height: 110)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = String(format: L.t("update.available.title"))
        window.isReleasedWhenClosed = false
        window.center()

        let container = NSView(frame: contentRect)

        let titleLabel = NSTextField(labelWithString: "DataMover \(version)")
        titleLabel.font = .boldSystemFont(ofSize: 13)
        titleLabel.frame = NSRect(x: 20, y: 70, width: 320, height: 20)
        container.addSubview(titleLabel)

        statusLabel = NSTextField(labelWithString: "")
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2
        statusLabel.frame = NSRect(x: 20, y: 30, width: 320, height: 34)
        container.addSubview(statusLabel)

        spinner = NSProgressIndicator(frame: NSRect(x: 20, y: 12, width: 320, height: 6))
        spinner.style = .bar
        spinner.isIndeterminate = true
        spinner.startAnimation(nil)
        container.addSubview(spinner)

        window.contentView = container
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    func close() {
        spinner.stopAnimation(nil)
        window.close()
    }
}
