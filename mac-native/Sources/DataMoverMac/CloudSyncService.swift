import Foundation

/// Destinatie secundara Cloud, powered by Rclone (2026-08-30) - cerinta
/// explicita a lui Cristi: "vreau sa copiez ceva, dar in acelasi timp sa
/// il si urc direct pe unul dintre serviciile facute cu Rclone". `rclone`
/// tine toate conturile intr-un singur `rclone.conf` GLOBAL, ne-izolat per
/// aplicatie - orice cont configurat prin Cloud Manager-ul din Master
/// Control Studio Pro e deja vizibil aici, fara nicio "legatura" de facut
/// intre cele doua aplicatii, doar de folosit acelasi binar `rclone`.
enum CloudSyncService {
    /// PATH augmentat, identic cu fix-ul din Master Control Studio Pro
    /// (`Shell.augmentedPath`) - un `.app` lansat din Finder/Dock mosteneste
    /// un PATH minim, fara `/opt/homebrew/bin` (unde Homebrew instaleaza
    /// rclone), altfel `Process` nu gaseste binarul deloc.
    static var augmentedPath: String {
        let current = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        return "/opt/homebrew/bin:/usr/local/bin:" + current
    }

    private static func makeProcess(_ args: [String]) -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["rclone"] + args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = augmentedPath
        p.environment = env
        return p
    }

    /// True daca `rclone` e gasibil pe PATH-ul augmentat - folosit sa
    /// ascundem sectiunea "Destinatie Cloud" daca dependinta lipseste, in
    /// loc sa aratam un picker gol care ar esua tacut la prima incercare.
    static func isAvailable() -> Bool {
        let p = makeProcess(["version"])
        p.standardOutput = Pipe(); p.standardError = Pipe()
        do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
    }

    /// Numele conturilor configurate (`rclone listremotes`), fara ":" final -
    /// EXACT aceleasi conturi vizibile in Cloud Manager-ul din Master
    /// Control Studio Pro, pentru ca ambele citesc acelasi `rclone.conf`.
    static func listRemotes() -> [String] {
        let p = makeProcess(["listremotes"])
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do {
            try p.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            guard let text = String(data: data, encoding: .utf8) else { return [] }
            return text.split(separator: "\n").map { $0.hasSuffix(":") ? String($0.dropLast()) : String($0) }
        } catch {
            return []
        }
    }

    /// Urca UN singur fisier deja copiat local catre `remote:remoteFolder/relPath`,
    /// pastrand structura de subfoldere (relPath poate contine "/"). Ruleaza
    /// `rclone copyto` (fisier -> fisier, nu folder -> folder) ca sa nu
    /// re-scaneze tot folderul de destinatie la fiecare fisier - cerinta
    /// Regulii 21 (fara operatii care cresc cu volumul deja transferat).
    /// `onLine` primeste progresul linie-cu-linie (stdout+stderr combinate),
    /// pentru feed-ul de activitate deja existent din DestinationJob.
    @discardableResult
    static func uploadFile(localPath: String, remote: String, remoteFolder: String,
                            relPath: String, onLine: @escaping (String) -> Void) -> Bool {
        let cleanFolder = remoteFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let remoteTarget = cleanFolder.isEmpty ? "\(remote):\(relPath)" : "\(remote):\(cleanFolder)/\(relPath)"
        let p = makeProcess(["copyto", localPath, remoteTarget, "--stats=1s", "-v"])
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        out.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(separator: "\n") where !line.isEmpty {
                onLine(String(line))
            }
        }
        do {
            try p.run()
            p.waitUntilExit()
            out.fileHandleForReading.readabilityHandler = nil
            return p.terminationStatus == 0
        } catch {
            out.fileHandleForReading.readabilityHandler = nil
            onLine("Cloud: eroare pornire rclone — \(error.localizedDescription)")
            return false
        }
    }
}

/// Coada SERIALA de upload-uri Cloud, una per DestinationJob (2026-08-30).
/// Motiv: mai multe procese `rclone` in paralel (cate unul per fisier
/// terminat local) ar concura pentru aceeasi banda de retea si ar creste
/// memoria/CPU nestapanit pe un transfer de mii de fisiere mici - o coada
/// seriala uploadeaza in fundal, fara sa blocheze bucla de copiere locala
/// (raspunde cerintei "in acelasi timp"), dar fara sa multiplice procese.
final class CloudUploadQueue: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.gdc.datamover.clouduploads", qos: .utility)
    private let remote: String
    private let remoteFolder: String
    private let onLine: (String) -> Void

    init(remote: String, remoteFolder: String, onLine: @escaping (String) -> Void) {
        self.remote = remote
        self.remoteFolder = remoteFolder
        self.onLine = onLine
    }

    func enqueue(localPath: String, relPath: String) {
        queue.async { [remote, remoteFolder, onLine] in
            onLine("Cloud: urcare \(relPath) → \(remote):\(remoteFolder.isEmpty ? "" : remoteFolder + "/")\(relPath)…")
            let ok = CloudSyncService.uploadFile(localPath: localPath, remote: remote,
                                                  remoteFolder: remoteFolder, relPath: relPath, onLine: onLine)
            onLine(ok ? "Cloud: ✔ \(relPath) urcat cu succes." : "Cloud: ✘ \(relPath) — urcarea a eșuat.")
        }
    }

    /// Blocheaza pana cand toate upload-urile deja puse in coada s-au
    /// terminat - apelat la finalul unui job, ca raportul final sa nu
    /// arate "gata" cat timp mai sunt fisiere care inca se urca.
    func waitUntilDrained() {
        queue.sync {}
    }
}
