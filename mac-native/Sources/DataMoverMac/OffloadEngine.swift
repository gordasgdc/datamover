import Foundation
import CryptoKit
import AppKit

/// Port Swift al partii esentiale din core/offload_engine.py: listare
/// fisiere, copiere in bucati (anulabila), verificare MD5, progres,
/// raport CSV. Simplificat fata de Python pentru v1:
///   - NU are inca: checkpoint/reluare, raport PDF, model de verificare
///     configurabil (fix pe MD5, ca DEFAULT_VERIFICATION_MODEL), lista
///     de excluderi editabila (doar fisierele ascunse "." sunt sarite,
///     ca in Python), "skip existing identical".
///   - Foloseste acelasi format de folder de destinatie
///     (<destinatie>/<timestamp>/<cale relativa>) si acelasi nume de
///     fisier CSV (offload_report_<timestamp>.csv), ca sa fie
///     recognoscibil langa rapoartele generate de Windows.

let offloadChunkSize = 1024 * 1024 // 1 MB, ca in Python

struct FileEntry {
    let fullPath: String
    let relPath: String
    let size: Int64
}

/// Token de anulare thread-safe, echivalentul lui threading.Event() din
/// Python — un singur obiect partajat intre thread-ul UI si toate
/// job-urile de destinatie.
final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _cancelled
    }

    func cancel() {
        lock.lock(); _cancelled = true; lock.unlock()
    }
}

struct OffloadCancelled: Error {}

/// Enumera recursiv un folder, sarind fisierele ascunse (nume care incep
/// cu ".") — exact regula implicita din Python (_is_excluded, fara alte
/// excluderi custom in v1).
func listAllFiles(root: String) -> [FileEntry] {
    let fm = FileManager.default
    var results: [FileEntry] = []
    guard let enumerator = fm.enumerator(atPath: root) else { return results }
    for case let relPath as String in enumerator {
        let name = (relPath as NSString).lastPathComponent
        if name.hasPrefix(".") { continue }
        let full = (root as NSString).appendingPathComponent(relPath)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue else { continue }
        let size = (try? fm.attributesOfItem(atPath: full)[.size] as? Int64) ?? nil
        results.append(FileEntry(fullPath: full, relPath: relPath, size: size ?? 0))
    }
    return results
}

/// Copiaza src -> dst in bucati de offloadChunkSize, verificand
/// cancelToken intre bucati — ca butonul Anuleaza sa opreasca efectiv
/// copierea unui fisier urias in cateva secunde, nu abia dupa ce
/// fisierul respectiv termina.
func copyFileCancelable(src: String, dst: String, cancel: CancelToken) throws {
    FileManager.default.createFile(atPath: dst, contents: nil)
    guard let input = FileHandle(forReadingAtPath: src),
          let output = FileHandle(forWritingAtPath: dst) else {
        throw NSError(domain: "DataMover", code: 1, userInfo: [NSLocalizedDescriptionKey: "Nu pot deschide \(src) sau \(dst)"])
    }
    defer { try? input.close(); try? output.close() }

    do {
        while true {
            if cancel.isCancelled { throw OffloadCancelled() }
            let chunk = input.readData(ofLength: offloadChunkSize)
            if chunk.isEmpty { break }
            output.write(chunk)
        }
    } catch {
        try? FileManager.default.removeItem(atPath: dst) // nu lasam fisier partial
        throw error
    }

    // pastreaza data modificarii sursei, ca shutil.copystat in Python
    if let attrs = try? FileManager.default.attributesOfItem(atPath: src),
       let modDate = attrs[.modificationDate] as? Date {
        try? FileManager.default.setAttributes([.modificationDate: modDate], ofItemAtPath: dst)
    }
}

/// MD5 al unui fisier, calculat pe bucati (fisiere mari nu incap intreg
/// in memorie) — CryptoKit.Insecure.MD5 accepta actualizari incrementale.
func md5Hash(path: String, cancel: CancelToken) throws -> String {
    guard let handle = FileHandle(forReadingAtPath: path) else {
        throw NSError(domain: "DataMover", code: 2, userInfo: [NSLocalizedDescriptionKey: "Nu pot citi \(path)"])
    }
    defer { try? handle.close() }

    var hasher = Insecure.MD5()
    while true {
        if cancel.isCancelled { throw OffloadCancelled() }
        let chunk = handle.readData(ofLength: offloadChunkSize)
        if chunk.isEmpty { break }
        hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

struct ReportRow {
    let file: String
    let sizeBytes: Int64
    let srcHash: String
    let dstHash: String
    let status: String
    let error: String
}

/// Rezultatul unei singure destinatii, la final — folosit de OffloadRunner
/// ca sa arate un rezumat in UI.
struct DestinationResult {
    let destRoot: String
    let okCount: Int
    let skipCount: Int
    let failCount: Int
    let cancelled: Bool
    let csvPath: String?
}

/// Copiaza+verifica lista de fisiere data catre O SINGURA destinatie —
/// echivalentul Swift al lui DestinationJob din Python. Ruleaza pe un
/// thread de fundal (vezi OffloadRunner), niciodata pe thread-ul UI.
final class DestinationJob {
    let destRoot: String
    let folderName: String
    let files: [FileEntry]
    let cancel: CancelToken
    /// apelat dupa fiecare fisier procesat (pe thread-ul de fundal —
    /// OffloadRunner e cel care sare pe main thread inainte sa atinga UI)
    let onFileDone: (_ size: Int64) -> Void

    private var reportRows: [ReportRow] = []
    private var okCount = 0, skipCount = 0, failCount = 0
    private var cancelled = false

    init(destRoot: String, folderName: String, files: [FileEntry], cancel: CancelToken,
         onFileDone: @escaping (_ size: Int64) -> Void) {
        self.destRoot = destRoot
        self.folderName = folderName
        self.files = files
        self.cancel = cancel
        self.onFileDone = onFileDone
    }

    func run() -> DestinationResult {
        let targetRoot = (destRoot as NSString).appendingPathComponent(folderName)
        try? FileManager.default.createDirectory(atPath: targetRoot, withIntermediateDirectories: true)

        for entry in files {
            if cancel.isCancelled { cancelled = true; break }

            let destPath = (targetRoot as NSString).appendingPathComponent(entry.relPath)
            let destDir = (destPath as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: destDir, withIntermediateDirectories: true)

            var status = "OK"
            var srcHash = "", dstHash = "", errorMsg = ""

            do {
                try copyFileCancelable(src: entry.fullPath, dst: destPath, cancel: cancel)
                srcHash = try md5Hash(path: entry.fullPath, cancel: cancel)
                dstHash = try md5Hash(path: destPath, cancel: cancel)
                if srcHash != dstHash { status = "NEPOTRIVIRE" }
            } catch is OffloadCancelled {
                cancelled = true
                break
            } catch {
                status = "EROARE"
                errorMsg = error.localizedDescription
            }

            switch status {
            case "OK": okCount += 1
            case "SARIT": skipCount += 1
            default: failCount += 1
            }
            reportRows.append(ReportRow(file: entry.relPath, sizeBytes: entry.size,
                                          srcHash: srcHash, dstHash: dstHash,
                                          status: status, error: errorMsg))
            onFileDone(entry.size)
        }

        let csvPath = writeReport(targetRoot: targetRoot)
        return DestinationResult(destRoot: destRoot, okCount: okCount, skipCount: skipCount,
                                  failCount: failCount, cancelled: cancelled, csvPath: csvPath)
    }

    private func writeReport(targetRoot: String) -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let csvPath = (targetRoot as NSString).appendingPathComponent("offload_report_\(timestamp).csv")

        var csv = "fisier,marime_bytes,verificare_sursa,verificare_destinatie,status,eroare\n"
        for row in reportRows {
            let fields = [row.file, String(row.sizeBytes), row.srcHash, row.dstHash, row.status, row.error]
            csv += fields.map { csvEscape($0) }.joined(separator: ",") + "\n"
        }
        do {
            try csv.write(toFile: csvPath, atomically: true, encoding: .utf8)
            return csvPath
        } catch {
            return nil
        }
    }

    private func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}

/// Orchestreaza cate un DestinationJob per destinatie, in paralel (ca
/// thread-urile din Python), si expune progresul global catre SwiftUI
/// prin @Published — legat direct in ContentView.
@MainActor
final class OffloadRunner: ObservableObject {
    @Published var isRunning = false
    @Published var progressPercent = 0
    @Published var filesDone = 0
    @Published var totalUnits = 0
    @Published var statusText = "Gata de pornire"
    @Published var speedText = ""
    @Published var lastResults: [DestinationResult] = []

    private var cancelToken = CancelToken()
    private var startTime: Date?
    private var bytesDone: Int64 = 0
    private let progressLock = NSLock()

    func start(sources: [String], destinations: [String]) {
        guard !isRunning else { return }

        var files: [FileEntry] = []
        for src in sources {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: src, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                files.append(contentsOf: listAllFiles(root: src))
            } else {
                let size = (try? FileManager.default.attributesOfItem(atPath: src)[.size] as? Int64) ?? nil
                files.append(FileEntry(fullPath: src, relPath: (src as NSString).lastPathComponent, size: size ?? 0))
            }
        }
        guard !files.isEmpty else {
            statusText = "Nu am gasit niciun fisier de copiat."
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let folderName = formatter.string(from: Date())

        cancelToken = CancelToken()
        isRunning = true
        startTime = Date()
        bytesDone = 0
        filesDone = 0
        totalUnits = files.count * destinations.count
        progressPercent = 0
        statusText = "Se copiaza..."
        speedText = ""
        lastResults = []

        let token = cancelToken
        let group = DispatchGroup()
        var results: [DestinationResult] = []
        let resultsLock = NSLock()

        for dest in destinations {
            group.enter()
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let job = DestinationJob(destRoot: dest, folderName: folderName, files: files, cancel: token) { size in
                    Task { @MainActor [weak self] in
                        self?.advance(size: size)
                    }
                }
                let result = job.run()
                resultsLock.lock(); results.append(result); resultsLock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.finish(results: results)
        }
    }

    func cancel() {
        guard isRunning else { return }
        cancelToken.cancel()
        statusText = "Se anuleaza..."
    }

    private func advance(size: Int64) {
        filesDone += 1
        bytesDone += size
        progressPercent = totalUnits > 0 ? Int(Double(filesDone) * 100 / Double(totalUnits)) : 0
        statusText = "\(progressPercent)% (\(filesDone)/\(totalUnits) fisiere)"
        if let start = startTime {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > 0 {
                speedText = formatBytes(Int64(Double(bytesDone) / elapsed)) + "/s"
            }
        }
    }

    private func finish(results: [DestinationResult]) {
        isRunning = false
        lastResults = results
        let anyCancelled = results.contains { $0.cancelled }
        let totalOK = results.reduce(0) { $0 + $1.okCount }
        let totalFail = results.reduce(0) { $0 + $1.failCount }
        statusText = anyCancelled
            ? "Anulat."
            : "Finalizat — \(totalOK) OK\(totalFail > 0 ? ", \(totalFail) probleme" : "")."
        NSSound(named: "Glass")?.play()
    }
}
