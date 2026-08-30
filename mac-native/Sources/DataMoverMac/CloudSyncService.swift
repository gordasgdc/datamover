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

    /// Urca UN SINGUR LOT de fisiere deja copiate local (relPath-uri, relative
    /// la `localRoot`) catre `remote:remoteFolder`, intr-un SINGUR proces
    /// `rclone copy`. Inlocuieste vechiul `uploadFile`/`copyto` per-fisier
    /// (2026-08-30, gasit ca bug real de performanta - Cristi: "mi se pare
    /// exagerat de mult ca dureaza transferul"): un proces `rclone` nou per
    /// fisier are un overhead de pornire+autentificare care domina timpul
    /// la multe fisiere mici, iar `copyto` nu paralelizeaza niciodata (un
    /// singur fisier per invocare). `rclone copy` cu `--files-from=-`
    /// (lista de cai primita pe stdin) lasa RCLONE INSUSI sa paralelizeze
    /// (`--transfers`) si sa foloseasca fragmente mai mari la upload
    /// (`--drive-chunk-size`, relevant si pentru fisiere mari) - un singur
    /// proces, mult mai rapid, indiferent daca lotul e "multe fisiere mici"
    /// sau "putine fisiere mari" (ambele cazuri confirmate de Cristi).
    /// `onLine` primeste progresul linie-cu-linie (stdout+stderr combinate).
    @discardableResult
    static func uploadBatch(localRoot: String, remote: String, remoteFolder: String,
                             relPaths: [String], onLine: @escaping (String) -> Void) -> Bool {
        guard !relPaths.isEmpty else { return true }
        let cleanFolder = remoteFolder.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let remoteTarget = cleanFolder.isEmpty ? "\(remote):" : "\(remote):\(cleanFolder)"
        let p = makeProcess([
            "copy", localRoot, remoteTarget,
            "--files-from", "-",
            "--transfers", "8",
            "--checkers", "16",
            "--drive-chunk-size", "64M",
            "--fast-list",
            "--stats", "1s", "-v",
        ])
        let inPipe = Pipe()
        p.standardInput = inPipe
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
            let listText = relPaths.joined(separator: "\n") + "\n"
            if let listData = listText.data(using: .utf8) {
                inPipe.fileHandleForWriting.write(listData)
            }
            try? inPipe.fileHandleForWriting.close()
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

/// Coada SERIALA + pe LOTURI de upload-uri Cloud, una per DestinationJob
/// (2026-08-30, rescrisa dupa un bug real de performanta - vezi
/// `uploadBatch`). Motiv al variantei seriale (nemodificat): mai multe
/// procese `rclone` in paralel (cate unul per fisier terminat local) ar
/// concura pentru aceeasi banda de retea si ar creste memoria/CPU
/// nestapanit pe un transfer de mii de fisiere mici. NOU: fisierele nu se
/// mai urca unul cate unul (un proces `rclone` per fisier, overhead mare la
/// multe fisiere mici) - se ACUMULEAZA intr-un lot, golit fie cand ajunge
/// la `batchSize`, fie dupa `batchDelay` secunde de la primul fisier
/// neurcat inca, oricare vine primul - un SINGUR proces `rclone copy` per
/// lot, care paralelizeaza singur transferurile (`--transfers`).
final class CloudUploadQueue: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.gdc.datamover.clouduploads", qos: .utility)
    private let remote: String
    private let remoteFolder: String
    private let localRoot: String
    private let onLine: (String) -> Void
    private var pending: [String] = []
    private var flushScheduled = false
    private let batchSize = 25
    private let batchDelay: TimeInterval = 3.0

    /// `localRoot` = radacina locala din care se raporteaza `relPath`-urile
    /// (acelasi `targetRoot` folosit de DestinationJob pentru copierea
    /// locala) - `rclone copy` are nevoie de o singura radacina sursa per
    /// invocare, filtrata apoi de `--files-from` la doar fisierele cerute.
    init(remote: String, remoteFolder: String, localRoot: String, onLine: @escaping (String) -> Void) {
        self.remote = remote
        self.remoteFolder = remoteFolder
        self.localRoot = localRoot
        self.onLine = onLine
    }

    func enqueue(relPath: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pending.append(relPath)
            if self.pending.count >= self.batchSize {
                self.flushLocked()
            } else if !self.flushScheduled {
                self.flushScheduled = true
                self.queue.asyncAfter(deadline: .now() + self.batchDelay) { [weak self] in
                    self?.flushLocked()
                }
            }
        }
    }

    /// Trebuie apelata DOAR pe `queue` (async sau sync) - nu e thread-safe
    /// singura, se bazeaza pe serializarea cozii.
    private func flushLocked() {
        flushScheduled = false
        guard !pending.isEmpty else { return }
        let batch = pending
        pending.removeAll()
        onLine("Cloud: urcare lot de \(batch.count) fișier(e) → \(remote):\(remoteFolder.isEmpty ? "" : remoteFolder + "/")…")
        let ok = CloudSyncService.uploadBatch(localRoot: localRoot, remote: remote,
                                               remoteFolder: remoteFolder, relPaths: batch, onLine: onLine)
        onLine(ok ? "Cloud: ✔ lot de \(batch.count) fișier(e) urcat cu succes."
                   : "Cloud: ✘ lot de \(batch.count) fișier(e) — cel puțin unul a eșuat (vezi jurnalul rclone de mai sus).")
    }

    /// Blocheaza pana cand toate upload-urile deja puse in coada s-au
    /// terminat (inclusiv un lot inca neajuns la prag/timp) - apelat la
    /// finalul unui job, ca raportul final sa nu arate "gata" cat timp mai
    /// sunt fisiere care inca se urca.
    func waitUntilDrained() {
        queue.sync { [weak self] in self?.flushLocked() }
    }
}
