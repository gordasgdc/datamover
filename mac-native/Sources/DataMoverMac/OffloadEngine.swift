import Foundation
import CryptoKit
import AppKit
import CoreText

/// Port Swift complet al core/offload_engine.py: listare fisiere (cu
/// excluderi), copiere in bucati (anulabila), verificare (MD5/SHA1/
/// SHA256/SHA512/doar-dimensiune), progres, checkpoint/reluare, raport
/// CSV + PDF. Format de folder si nume de fisiere identice cu Python,
/// ca rapoartele sa fie recognoscibile langa cele generate de Windows.

let offloadChunkSize = 1024 * 1024 // 1 MB, fallback - vezi IOSettings.chunkSizeBytes pentru valoarea configurabila reala

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

/// Token de PAUZA thread-safe (2026-08-28), partajat intre thread-ul UI si
/// toate job-urile de destinatie - la fel ca CancelToken, dar reversibil:
/// spre deosebire de Cancel (definitiv, opreste job-ul), Pause doar
/// blocheaza bucla principala pana la resume(), FARA sa piarda progresul
/// facut pana atunci (fisierul curent isi termina copierea in curs, nu se
/// intrerupe la mijloc - pauza se aplica INTRE fisiere).
final class PauseToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _paused = false

    var isPaused: Bool {
        lock.lock(); defer { lock.unlock() }
        return _paused
    }

    func pause() { lock.lock(); _paused = true; lock.unlock() }
    func resume() { lock.lock(); _paused = false; lock.unlock() }

    /// Blocheaza thread-ul curent (job-ul de destinatie, NU thread-ul UI)
    /// cat timp e in pauza, verificand periodic cancel-ul ca sa nu ramana
    /// blocat definitiv daca userul apasa Anuleaza in timp ce e in pauza.
    func waitWhilePaused(cancel: CancelToken) {
        while isPaused {
            if cancel.isCancelled { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }
}

// MARK: - Model de verificare

enum VerificationModel: String, CaseIterable, Identifiable, Codable {
    case md5, sha1, sha256, sha512, sizeOnly = "marime"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .md5: return L.t("verif.md5")
        case .sha1: return L.t("verif.sha1")
        case .sha256: return L.t("verif.sha256")
        case .sha512: return L.t("verif.sha512")
        case .sizeOnly: return L.t("verif.sizeOnly")
        }
    }
}

// MARK: - Excluderi

/// Sare fisierele ascunse (nume care incep cu ".") plus orice tipar din
/// exclusions — nume exact sau extensie (tipar care incepe cu ".").
/// Identic cu _is_excluded din Python.
func isExcluded(filename: String, exclusions: [String]) -> Bool {
    if filename.hasPrefix(".") { return true }
    let lower = filename.lowercased()
    for raw in exclusions {
        let pattern = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if pattern.isEmpty { continue }
        if pattern.hasPrefix(".") {
            if lower.hasSuffix(pattern) { return true }
        } else if lower == pattern {
            return true
        }
    }
    return false
}

/// Enumera recursiv un folder, aplicand excluderile de mai sus.
func listAllFiles(root: String, exclusions: [String] = []) -> [FileEntry] {
    let fm = FileManager.default
    var results: [FileEntry] = []
    guard let enumerator = fm.enumerator(atPath: root) else { return results }
    for case let relPath as String in enumerator {
        let name = (relPath as NSString).lastPathComponent
        if isExcluded(filename: name, exclusions: exclusions) { continue }
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
///
/// WARNING (2026-08-26, fix de crash): NU folosi niciodata
/// `FileHandle.readData(ofLength:)` / `.write(_:)` fara `try` aici. Sunt
/// API-uri Objective-C legacy — la o eroare reala de citire/scriere (card
/// SD deconectat in timpul copierii, disc extern scos, disc plin,
/// permisiune refuzata) NU arunca o eroare Swift capturabila cu
/// `do/catch`, ci ridica o EXCEPTIE OBJECTIVE-C
/// (`_NSFileHandleRaiseOperationExceptionWhileReading`), pe care Swift n-o
/// poate prinde. Rezultatul: `objc_exception_throw` necaptata -> `abort()`
/// -> toata aplicatia crapa, nu doar job-ul curent. Confirmat printr-un
/// crash real (`copyFileCancelable` -> `readDataOfLength:` -> abort) —
/// pentru un tool de offload de pe platou, exact scenariul "cineva scoate
/// cardul SD in timp ce copiaza" trebuia sa fie o eroare de job, nu un
/// crash total. `FileHandle.read(upToCount:)` / `.write(contentsOf:)` sunt
/// variantele THROWING corecte, introduse tocmai pentru asta (macOS
/// 10.15.4+) — orice eroare de I/O ajunge acum in catch-ul de mai jos, ca
/// eroare normala de job.
func copyFileCancelable(src: String, dst: String, cancel: CancelToken, chunkSize: Int = offloadChunkSize) throws {
    FileManager.default.createFile(atPath: dst, contents: nil)
    guard let input = FileHandle(forReadingAtPath: src),
          let output = FileHandle(forWritingAtPath: dst) else {
        throw NSError(domain: "DataMover", code: 1, userInfo: [NSLocalizedDescriptionKey: "Nu pot deschide \(src) sau \(dst)"])
    }
    defer { try? input.close(); try? output.close() }

    do {
        // FIX MEMORIE REAL (2026-08-27): fara `autoreleasepool` aici,
        // fiecare `Data` intoarsa de `read(upToCount:)` e backed de un
        // obiect Objective-C (NSData) ale carui autorelease-uri NU se
        // elibereaza pana la drenarea urmatorului autorelease pool -
        // pe un DispatchQueue.global de fundal, GCD creeaza un pool o
        // singura data PER BLOC dispatch-uit, nu per iteratie a acestei
        // bucle `while`. Pentru un singur fisier de zeci/sute de GB (sau
        // un transfer total de 3 TB), asta insemna ca memoria Objective-C
        // temporara a FIECAREI bucati citite se acumula neintrerupt pe
        // toata durata copierii, in loc sa fie eliberata dupa fiecare
        // bloc scris pe disc - exact simptomul raportat ("Your system has
        // run out of application memory", swap la maxim). `autoreleasepool`
        // explicit, per iteratie, dreneaza acele temporare imediat dupa
        // scrierea pe disc a fiecarui bloc.
        while true {
            if cancel.isCancelled { throw OffloadCancelled() }
            var stop = false
            try autoreleasepool {
                // `read(upToCount:)` intoarce nil sau Data goala la EOF (in
                // functie de versiune) — verificam ambele, nu doar `.isEmpty`.
                guard let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty else {
                    stop = true
                    return
                }
                try output.write(contentsOf: chunk)
            }
            if stop { break }
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

/// Hash generic pe bucati, pentru orice algoritm CryptoKit conform
/// HashFunction (MD5/SHA1/SHA256/SHA512 partajate acelasi cod).
private func genericHash<H: HashFunction>(path: String, using: H.Type, cancel: CancelToken, chunkSize: Int) throws -> String {
    guard let handle = FileHandle(forReadingAtPath: path) else {
        throw NSError(domain: "DataMover", code: 2, userInfo: [NSLocalizedDescriptionKey: "Nu pot citi \(path)"])
    }
    defer { try? handle.close() }

    var hasher = H()
    while true {
        if cancel.isCancelled { throw OffloadCancelled() }
        // Acelasi fix de memorie ca in copyFileCancelable: fara
        // autoreleasepool per iteratie, Data-urile bridge-uite din
        // Objective-C se acumuleaza pe toata durata hash-uirii unui
        // fisier urias, nu doar cat o bucata.
        var stop = false
        try autoreleasepool {
            // Vezi WARNING-ul de la copyFileCancelable: `readData(ofLength:)`
            // ridica o exceptie Objective-C necapturabila la o eroare reala de
            // citire, in loc sa arunce o eroare Swift. Verificarea (hash-ul de
            // dupa copiere) rula pe acelasi risc de crash ca si copierea.
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else {
                stop = true
                return
            }
            hasher.update(data: chunk)
        }
        if stop { break }
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

func hashOfFile(path: String, model: VerificationModel, cancel: CancelToken, chunkSize: Int = offloadChunkSize) throws -> String {
    switch model {
    case .md5: return try genericHash(path: path, using: Insecure.MD5.self, cancel: cancel, chunkSize: chunkSize)
    case .sha1: return try genericHash(path: path, using: Insecure.SHA1.self, cancel: cancel, chunkSize: chunkSize)
    case .sha256: return try genericHash(path: path, using: SHA256.self, cancel: cancel, chunkSize: chunkSize)
    case .sha512: return try genericHash(path: path, using: SHA512.self, cancel: cancel, chunkSize: chunkSize)
    case .sizeOnly: return ""
    }
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
    let pdfPath: String?
}

// MARK: - Checkpoint (identic ca format cu core/checkpoint.py)

private struct CheckpointData: Codable {
    var source: String?
    var folderName: String
    var verificationModel: String
    var completed: Bool
    var files: [String: String]
    var totalFiles: Int?

    enum CodingKeys: String, CodingKey {
        case source, completed, files
        case folderName = "folder_name"
        case verificationModel = "verification_model"
        case totalFiles = "total_files"
    }
}

private enum CheckpointStore {
    static let filename = "offload_checkpoint.json"

    static func path(targetRoot: String) -> String {
        (targetRoot as NSString).appendingPathComponent(filename)
    }

    static func load(targetRoot: String) -> [String: String]? {
        let p = path(targetRoot: targetRoot)
        guard let data = FileManager.default.contents(atPath: p),
              let decoded = try? JSONDecoder().decode(CheckpointData.self, from: data) else { return nil }
        return decoded.files
    }

    static func save(targetRoot: String, source: String?, folderName: String,
                      verificationModel: String, files: [String: String],
                      completed: Bool, totalFiles: Int) {
        let payload = CheckpointData(source: source, folderName: folderName,
                                      verificationModel: verificationModel, completed: completed,
                                      files: files, totalFiles: totalFiles)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let p = path(targetRoot: targetRoot)
        let tmp = p + ".tmp"
        do {
            try data.write(to: URL(fileURLWithPath: tmp))
            _ = try? FileManager.default.removeItem(atPath: p)
            try FileManager.default.moveItem(atPath: tmp, toPath: p)
        } catch { /* best-effort, ca in Python */ }
    }
}

// MARK: - DestinationJob

/// Copiaza+verifica lista de fisiere data catre O SINGURA destinatie —
/// echivalentul Swift al lui DestinationJob din Python. Ruleaza pe un
/// thread de fundal (vezi OffloadRunner), niciodata pe thread-ul UI.
final class DestinationJob {
    let destRoot: String
    let folderName: String
    let files: [FileEntry]
    let cancel: CancelToken
    let pause: PauseToken
    let verificationModel: VerificationModel
    let resume: Bool
    let sourceRoot: String?
    /// Destinatie secundara Cloud (2026-08-30, vezi CloudSyncService) -
    /// optionala; daca nil, comportamentul e identic cu inainte.
    let cloudUploadQueue: CloudUploadQueue?
    /// apelat dupa fiecare fisier procesat (pe thread-ul de fundal —
    /// OffloadRunner e cel care sare pe main thread inainte sa atinga UI)
    let onFileDone: (_ size: Int64) -> Void
    /// Feed-ul de activitate stil Terminal din footer — apelat INAINTE de
    /// copiere si INAINTE de verificare (nu doar la final, ca onFileDone),
    /// tocmai ca userul sa vada ceva miscandu-se cat timp un fisier mare
    /// (video 4K/RAW) ia zeci de secunde si bara de progres pare inghetata
    /// intre doua incrementari. Fisierele mari sunt EXACT cazul in care
    /// asigurarea asta psihologica conteaza cel mai mult.
    let onActivity: (_ line: String) -> Void

    /// Esantion plafonat pentru raportul PDF (nu tot istoricul - vezi
    /// pdfSampleLimit): toate erorile/nepotrivirile plus o mostra din
    /// restul. CSV-ul complet e scris INCREMENTAL pe disc (csvHandle),
    /// nu tinut in memorie - un transfer de sute de mii de fisiere nu mai
    /// pastreaza randul fiecaruia in RAM pana la sfarsit.
    private var pdfSampleRows: [ReportRow] = []
    private let pdfSampleLimit = 500
    private var csvHandle: FileHandle?
    private var csvPath: String?
    private var okCount = 0, skipCount = 0, failCount = 0
    private var cancelled = false
    private var filesStatus: [String: String] = [:]
    private var filesSinceCheckpoint = 0
    private var lastCheckpointTime = Date.distantPast
    private var startedAt = Date()

    init(destRoot: String, folderName: String, files: [FileEntry], cancel: CancelToken,
         pause: PauseToken = PauseToken(),
         verificationModel: VerificationModel = .md5, resume: Bool = false, sourceRoot: String? = nil,
         cloudUploadQueue: CloudUploadQueue? = nil,
         onFileDone: @escaping (_ size: Int64) -> Void,
         onActivity: @escaping (_ line: String) -> Void = { _ in }) {
        self.destRoot = destRoot
        self.folderName = folderName
        self.files = files
        self.cancel = cancel
        self.pause = pause
        self.onActivity = onActivity
        self.verificationModel = verificationModel
        self.resume = resume
        self.sourceRoot = sourceRoot
        self.cloudUploadQueue = cloudUploadQueue
        self.onFileDone = onFileDone
    }

    func run() -> DestinationResult {
        startedAt = Date()
        let targetRoot = (destRoot as NSString).appendingPathComponent(folderName)
        try? FileManager.default.createDirectory(atPath: targetRoot, withIntermediateDirectories: true)
        let chunkSize = IOSettings.chunkSizeBytes
        openCSV(targetRoot: targetRoot)

        var alreadyDone: Set<String> = []
        if resume, let saved = CheckpointStore.load(targetRoot: targetRoot) {
            filesStatus = saved
            alreadyDone = Set(saved.filter { $0.value == "ok" || $0.value == "sarit" }.keys)
        }

        for entry in files {
            if cancel.isCancelled { cancelled = true; break }

            // Pauza (2026-08-28): blocheaza AICI, INTRE fisiere - fisierul
            // anterior si-a terminat deja copierea/verificarea, deci nu se
            // pierde niciun progres facut pana la apasarea Pauza. La
            // Resume, bucla continua exact de unde a ramas.
            if pause.isPaused {
                onActivity("Pauza — transferul e oprit temporar de utilizator.")
                pause.waitWhilePaused(cancel: cancel)
                if cancel.isCancelled { cancelled = true; break }
                onActivity("Reluat din pauza.")
            }

            // Backpressure: daca memoria procesului a depasit limita
            // configurata (Setari), asteapta putin inainte de urmatorul
            // fisier - vezi IOSettings.waitIfOverRAMLimit.
            IOSettings.waitIfOverRAMLimit(cancel: cancel) { [onActivity] warning in
                onActivity(warning)
            }

            if alreadyDone.contains(entry.relPath) {
                skipCount += 1
                onFileDone(entry.size)
                maybeWriteCheckpoint(targetRoot: targetRoot)
                continue
            }

            let destPath = (targetRoot as NSString).appendingPathComponent(entry.relPath)
            let destDir = (destPath as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: destDir, withIntermediateDirectories: true)

            var status = "OK"
            var srcRepr = "", dstRepr = "", errorMsg = ""

            do {
                // "Completeaza/Reia" (2026-08-28): daca fisierul de la
                // destinatie exista deja si are ACEEASI marime ca sursa,
                // il verificam direct (fara sa-l recopiem) - daca hash-ul
                // coincide, il numaram ca deja transferat corect. Acopera
                // cazul unei reporniri neasteptate FARA checkpoint (ex.
                // s-a inchis calculatorul brusc) - nu doar reluarea
                // normala prin offload_checkpoint.json.
                if resume, FileManager.default.fileExists(atPath: destPath),
                   let existingSize = (try? FileManager.default.attributesOfItem(atPath: destPath)[.size] as? Int64) ?? nil,
                   existingSize == entry.size {
                    onActivity("Verificare fisier existent: \(entry.relPath)…")
                    let (same, s, d) = try verifyPair(entry: entry, destPath: destPath, chunkSize: chunkSize)
                    if same {
                        status = "SARIT"
                        srcRepr = s; dstRepr = d
                        skipCount += 1
                        filesStatus[entry.relPath] = "sarit"
                        logRow(ReportRow(file: entry.relPath, sizeBytes: entry.size,
                                          srcHash: s, dstHash: d, status: status, error: ""))
                        cloudUploadQueue?.enqueue(localPath: destPath, relPath: entry.relPath)
                        onFileDone(entry.size)
                        maybeWriteCheckpoint(targetRoot: targetRoot)
                        continue
                    }
                    // marimea coincide dar continutul nu - recopiem normal mai jos
                }

                onActivity("Copiere: \(entry.relPath) (\(formatBytes(entry.size)))")
                try copyFileCancelable(src: entry.fullPath, dst: destPath, cancel: cancel, chunkSize: chunkSize)
                onActivity("Verificare checksum: \(entry.relPath)…")
                let (same, s, d) = try verifyPair(entry: entry, destPath: destPath, chunkSize: chunkSize)
                srcRepr = s; dstRepr = d
                if !same { status = "NEPOTRIVIRE" }
            } catch is OffloadCancelled {
                cancelled = true
                break
            } catch {
                status = "EROARE"
                errorMsg = error.localizedDescription
            }

            switch status {
            case "OK": okCount += 1; filesStatus[entry.relPath] = "ok"
            case "SARIT": skipCount += 1; filesStatus[entry.relPath] = "sarit"
            default: failCount += 1; filesStatus[entry.relPath] = "fail"
            }
            logRow(ReportRow(file: entry.relPath, sizeBytes: entry.size,
                              srcHash: srcRepr, dstHash: dstRepr,
                              status: status, error: errorMsg))
            // Urcare Cloud (2026-08-30): doar fisierele copiate cu succes
            // local (OK/SARIT) - un fisier cu NEPOTRIVIRE/EROARE local nu se
            // urca, la fel cum nu s-ar considera "transferat" nici pe disc.
            if status == "OK" || status == "SARIT" {
                cloudUploadQueue?.enqueue(localPath: destPath, relPath: entry.relPath)
            }
            onFileDone(entry.size)
            maybeWriteCheckpoint(targetRoot: targetRoot)
        }

        // Asteapta upload-urile Cloud deja puse in coada inainte de raport -
        // altfel raportul final ar aparea "complet" cat timp inca se mai
        // urca fisiere in fundal.
        if let queue = cloudUploadQueue {
            onActivity("Cloud: se așteaptă finalizarea urcărilor rămase…")
            queue.waitUntilDrained()
        }
        maybeWriteCheckpoint(targetRoot: targetRoot, force: true)
        let (savedCSV, pdfPath) = writeReports(targetRoot: targetRoot)
        return DestinationResult(destRoot: destRoot, okCount: okCount, skipCount: skipCount,
                                  failCount: failCount, cancelled: cancelled,
                                  csvPath: savedCSV, pdfPath: pdfPath)
    }

    private func verifyPair(entry: FileEntry, destPath: String, chunkSize: Int) throws -> (same: Bool, srcRepr: String, dstRepr: String) {
        if verificationModel == .sizeOnly {
            let dstSize = (try? FileManager.default.attributesOfItem(atPath: destPath)[.size] as? Int64) ?? nil
            let d = dstSize ?? -1
            return (d == entry.size, "marime=\(entry.size)", "marime=\(d)")
        }
        let srcHash = try hashOfFile(path: entry.fullPath, model: verificationModel, cancel: cancel, chunkSize: chunkSize)
        let dstHash = try hashOfFile(path: destPath, model: verificationModel, cancel: cancel, chunkSize: chunkSize)
        return (srcHash == dstHash, srcHash, dstHash)
    }

    private func maybeWriteCheckpoint(targetRoot: String, force: Bool = false) {
        filesSinceCheckpoint += 1
        let now = Date()
        let dueByCount = filesSinceCheckpoint >= 10
        let dueByTime = now.timeIntervalSince(lastCheckpointTime) >= 5.0
        guard force || dueByCount || dueByTime else { return }
        CheckpointStore.save(targetRoot: targetRoot, source: sourceRoot, folderName: folderName,
                              verificationModel: verificationModel.rawValue, files: filesStatus,
                              completed: force && !cancelled, totalFiles: files.count)
        filesSinceCheckpoint = 0
        lastCheckpointTime = now
    }

    /// Deschide CSV-ul de raport O SINGURA DATA, la inceputul run(), si il
    /// tine deschis (csvHandle) pe toata durata copierii - fiecare rand se
    /// scrie IMEDIAT (logRow), nu se acumuleaza intr-un array Swift pana
    /// la final (regula "Log-uri si Stare UI": nu tinem in RAM istoricul
    /// complet al unui transfer de sute de mii de fisiere).
    private func openCSV(targetRoot: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let path = (targetRoot as NSString).appendingPathComponent("offload_report_\(timestamp).csv")
        FileManager.default.createFile(atPath: path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        let header = "fisier,marime_bytes,verificare_sursa,verificare_destinatie,status,eroare\n"
        handle.write(header.data(using: .utf8) ?? Data())
        csvHandle = handle
        csvPath = path
    }

    private func logRow(_ row: ReportRow) {
        if let handle = csvHandle {
            let fields = [row.file, String(row.sizeBytes), row.srcHash, row.dstHash, row.status, row.error]
            let line = fields.map { csvEscape($0) }.joined(separator: ",") + "\n"
            autoreleasepool {
                handle.write(line.data(using: .utf8) ?? Data())
            }
        }

        // Esantion plafonat pentru PDF: toate erorile/nepotrivirile (putine,
        // importante de vazut), plus primele pdfSampleLimit randuri - restul
        // ramane doar in CSV, care e complet.
        let isProblem = row.status == "EROARE" || row.status == "NEPOTRIVIRE"
        if isProblem || pdfSampleRows.count < pdfSampleLimit {
            pdfSampleRows.append(row)
        }
    }

    private func writeReports(targetRoot: String) -> (csv: String?, pdf: String?) {
        try? csvHandle?.close()
        csvHandle = nil

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let pdfPath = (targetRoot as NSString).appendingPathComponent("offload_report_\(timestamp).pdf")
        let totalRows = okCount + skipCount + failCount
        let truncatedNote = pdfSampleRows.count < totalRows
            ? "Lista completa (\(totalRows) fisiere) e in CSV-ul alaturat - PDF-ul arata toate problemele plus un esantion."
            : nil
        let pdfResult = writePDFReport(
            path: pdfPath, destination: destRoot, folderName: folderName, rows: pdfSampleRows,
            startedAt: startedAt, finishedAt: Date(), okCount: okCount, skipCount: skipCount,
            failCount: failCount, cancelled: cancelled, verificationLabel: verificationModel.label,
            truncatedNote: truncatedNote
        )
        let savedPDF: String? = pdfResult.ok ? pdfPath : nil
        if !pdfResult.ok {
            let reason = pdfResult.error ?? "motiv necunoscut"
            onActivity("Nu s-a putut genera raportul PDF: \(reason)")
            // Fisier de fallback langa CSV, la fel ca pe Windows (v2.7.0) -
            // gasibil chiar daca feed-ul de activitate a fost ratat/golit.
            let errPath = (targetRoot as NSString).appendingPathComponent("offload_report_PDF_EROARE.txt")
            let content = "Generarea raportului PDF a esuat la \(Date()).\n\nMotiv: \(reason)\n"
            try? content.write(toFile: errPath, atomically: true, encoding: .utf8)
        }

        return (csvPath, savedPDF)
    }

    private func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}

// MARK: - Raport PDF (CoreGraphics, fara dependinte externe)

private func writePDFReport(path: String, destination: String, folderName: String, rows: [ReportRow],
                             startedAt: Date, finishedAt: Date, okCount: Int, skipCount: Int,
                             failCount: Int, cancelled: Bool, verificationLabel: String,
                             truncatedNote: String? = nil) -> (ok: Bool, error: String?) {
    let pageWidth: CGFloat = 595 // A4 @ 72dpi
    let pageHeight: CGFloat = 842
    let margin: CGFloat = 40
    var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

    // FIX VIZIBILITATE (2026-08-30, raportat de Cristi: "PDF-ul nu se
    // creeaza") - pana acum, daca CGDataConsumer/CGContext esuau, functia
    // intorcea `false` FARA niciun motiv, la fel ca bug-ul deja documentat
    // si reparat pe Windows (QuestPDF/ARM64, v2.7.0) - CSV-ul (scris cu
    // FileHandle simplu) reuseste mereu, deci userul vede doar checkpoint +
    // CSV si crede ca PDF-ul "nu porneste", fara niciun indiciu de ce.
    // Motive reale posibile aici: folder de destinatie sters/deconectat
    // intre timp (disc extern), spatiu insuficient pe disc, sau un
    // caracter din cale pe care CFURL nu il accepta.
    guard let consumer = CGDataConsumer(url: URL(fileURLWithPath: path) as CFURL) else {
        return (false, "CGDataConsumer nu a putut fi creat pentru \"\(path)\" - verifica daca folderul de destinatie mai exista si daca discul nu e plin.")
    }
    guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        return (false, "CGContext nu a putut fi creat pentru raportul PDF (dupa ce fisierul consumer a fost deschis cu succes) - cauza necunoscuta, posibil memorie insuficienta.")
    }

    var y: CGFloat = pageHeight - margin

    func newPage() { ctx.beginPDFPage(nil); y = pageHeight - margin }
    func draw(_ text: String, size: CGFloat = 10, bold: Bool = false, color: NSColor = .black, x: CGFloat = margin) {
        if y < margin + size { ctx.endPDFPage(); newPage() }
        let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let line = CTLineCreateWithAttributedString(attr)
        ctx.saveGState()
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
    /// Trunchiaza un text la un numar aproximativ de caractere care incap
    /// intr-o coloana, adaugand "..." — simplu, fara masurare exacta de
    /// glife (suficient pentru un raport monospace-friendly).
    func truncate(_ s: String, maxChars: Int) -> String {
        guard s.count > maxChars else { return s }
        return String(s.prefix(maxChars - 1)) + "…"
    }

    // Coloanele tabelului: Status | Fisier | Marime | Eroare
    let colStatusX = margin
    let colFileX = margin + 46
    let colSizeX = pageWidth - margin - 150
    let colErrorX = pageWidth - margin - 90
    let rowHeight: CGFloat = 13

    func drawTableHeader() {
        let headerY = y
        ctx.saveGState()
        ctx.setFillColor(NSColor(white: 0.9, alpha: 1).cgColor)
        ctx.fill(CGRect(x: margin - 4, y: headerY - 3, width: pageWidth - 2 * margin + 8, height: rowHeight))
        ctx.restoreGState()
        draw("Status", size: 8, bold: true, x: colStatusX)
        draw("Fisier", size: 8, bold: true, x: colFileX)
        draw("Marime", size: 8, bold: true, x: colSizeX)
        draw("Eroare", size: 8, bold: true, x: colErrorX)
        y -= rowHeight
    }

    let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss"

    newPage()
    draw("Raport offload — \(folderName)", size: 16, bold: true); y -= 20
    draw("Destinatie: \(destination)", size: 10); y -= 16
    draw("Inceput: \(df.string(from: startedAt))   Finalizat: \(df.string(from: finishedAt))", size: 10); y -= 16
    draw("Model verificare: \(verificationLabel)", size: 10); y -= 16
    draw("OK: \(okCount)   Sarite: \(skipCount)   Probleme: \(failCount)" + (cancelled ? "   (ANULAT)" : ""),
         size: 10, bold: true, color: failCount > 0 || cancelled ? .systemRed : .systemGreen)
    y -= 16
    if let note = truncatedNote {
        draw(note, size: 8, color: .darkGray)
        y -= 10
    }
    y -= 16

    drawTableHeader()
    for (index, row) in rows.enumerated() {
        if y < margin + rowHeight {
            ctx.endPDFPage(); newPage()
            drawTableHeader()
        }
        if index % 2 == 0 {
            ctx.saveGState()
            ctx.setFillColor(NSColor(white: 0.96, alpha: 1).cgColor)
            ctx.fill(CGRect(x: margin - 4, y: y - 3, width: pageWidth - 2 * margin + 8, height: rowHeight))
            ctx.restoreGState()
        }
        let color: NSColor = row.status == "OK" ? .black : .systemRed
        draw(row.status, size: 8, color: color, x: colStatusX)
        draw(truncate(row.file, maxChars: 42), size: 8, color: color, x: colFileX)
        draw(formatBytes(row.sizeBytes), size: 8, color: color, x: colSizeX)
        draw(truncate(row.error, maxChars: 22), size: 8, color: .systemRed, x: colErrorX)
        y -= rowHeight
    }
    ctx.endPDFPage()
    ctx.closePDF()
    return (true, nil)
}

// MARK: - OffloadRunner (orchestrare, expus catre SwiftUI)

/// Orchestreaza cate un DestinationJob per destinatie, in paralel (ca
/// thread-urile din Python), si expune progresul global catre SwiftUI
/// prin @Published — legat direct in ContentView.
@MainActor
final class OffloadRunner: ObservableObject {
    @Published var isRunning = false
    @Published var progressPercent = 0
    @Published var filesDone = 0
    @Published var totalUnits = 0
    @Published var statusText = L.t("status.ready")
    @Published var speedText = ""
    @Published var lastResults: [DestinationResult] = []
    /// Plafon de proba depasit (2026-08-30) - vezi LicenseManager.
    /// trialMaxTransferBytes. ContentView asculta asta si arata un alert
    /// cu buton de activare, in loc sa lase Start-ul sa esueze tacut.
    @Published var trialLimitExceededBytes: Int64? = nil
    /// Feed-ul stil Terminal din footer (vezi DestinationJob.onActivity).
    /// Capat la `activityLogLimit` — nu tinem tot istoricul unui transfer
    /// de mii de fisiere in memorie/UI, doar ce s-a intamplat recent.
    @Published private(set) var activityLines: [String] = []
    private let activityLogLimit = 200

    // Pauza (2026-08-28) - vezi PauseToken. Butonul de Pauza din UI leaga
    // direct de isPaused; job-urile de destinatie citesc acelasi token.
    @Published var isPaused = false
    private var pauseToken = PauseToken()

    // Buffer/Memorie afisate live in UI (2026-08-28) - "Buffer Alocat: X |
    // Utilizat: Y", actualizate la fiecare progres (advance()).
    @Published var bufferAllocatedText = ""
    @Published var memoryUsedText = ""

    private var cancelToken = CancelToken()
    private var startTime: Date?
    private var bytesDone: Int64 = 0

    /// Numele folderului de destinatie pentru o pereche proiect/card - pur,
    /// fara efecte laterale, ca ContentView sa poata verifica dinainte
    /// daca exista deja o destinatie cu acest nume (vezi
    /// existingNonEmptyDestinations) inainte sa porneasca efectiv start().
    func folderName(project: String, card: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())
        let proj = project.trimmingCharacters(in: .whitespaces).isEmpty ? "Proiect" : project.trimmingCharacters(in: .whitespaces)
        let crd = card.trimmingCharacters(in: .whitespaces).isEmpty ? "Card" : card.trimmingCharacters(in: .whitespaces)
        return "\(dateStr)_\(proj)_\(crd)".replacingOccurrences(of: " ", with: "_")
    }

    /// Sanitizeaza proiect/card exact ca folderName(), fara data - folosit
    /// ca sa gasim un folder EXISTENT (dintr-o zi anterioara) cu acelasi
    /// proiect/card, nu doar cel al zilei curente.
    private func sanitizedProjectCard(project: String, card: String) -> String {
        let proj = project.trimmingCharacters(in: .whitespaces).isEmpty ? "Proiect" : project.trimmingCharacters(in: .whitespaces)
        let crd = card.trimmingCharacters(in: .whitespaces).isEmpty ? "Card" : card.trimmingCharacters(in: .whitespaces)
        return "\(proj)_\(crd)".replacingOccurrences(of: " ", with: "_")
    }

    /// Cauta un folder deja EXISTENT (creat oricand, nu neaparat azi) cu
    /// acelasi proiect/card la oricare destinatie - bug real gasit
    /// 2026-08-28: `folderName(project:card:)` include data zilei curente,
    /// deci un transfer de 4 TB care trece peste miezul noptii (sau e
    /// reluat a doua zi) calcula un nume de folder NOU, iar verificarea
    /// de duplicate se uita gresit la folderul nou (inca inexistent), nu
    /// la cel vechi cu sute de GB deja copiate - userul nu mai era
    /// intrebat NIMIC si aplicatia pornea o copiere completa, paralela,
    /// intr-un folder separat. Daca gaseste mai multe (ex. incercari din
    /// zile diferite), alege cel mai RECENT (prefixul de data se sorteaza
    /// lexicografic identic cu ordinea cronologica).
    func findExistingFolderName(destinations: [String], project: String, card: String) -> String? {
        let suffix = "_" + sanitizedProjectCard(project: project, card: card)
        var candidates: [String] = []
        for dest in destinations {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: dest) else { continue }
            candidates.append(contentsOf: items.filter { $0.hasSuffix(suffix) })
        }
        return candidates.sorted().last
    }

    /// Un nume de folder liber (neexistent inca la nicio destinatie),
    /// pornind de la `base` si adaugand " (2)", " (3)"... - folosit de
    /// optiunea "Creeaza folder nou" din dialogul de duplicate.
    func freeFolderName(base: String, destinations: [String]) -> String {
        var candidate = base
        var suffix = 2
        while !existingNonEmptyDestinations(destinations: destinations, folderName: candidate).isEmpty {
            candidate = "\(base) (\(suffix))"
            suffix += 1
        }
        return candidate
    }

    /// Destinatiile la care folderul `folderName` exista DEJA si contine
    /// cel putin un fisier - semnal ca acest transfer ar suprascrie/
    /// duplica date, nu ca porneste intr-un folder gol. Apelat de
    /// ContentView INAINTE de start(), ca sa decida daca arata dialogul
    /// "Reia / Folder nou / Suprascrie".
    func existingNonEmptyDestinations(destinations: [String], folderName: String) -> [String] {
        destinations.filter { dest in
            let targetRoot = (dest as NSString).appendingPathComponent(folderName)
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: targetRoot) else { return false }
            // ignoram fisierele proprii de raport/checkpoint - un folder
            // care contine DOAR un checkpoint dintr-o rulare intrerupta
            // fara niciun fisier real copiat inca nu e "duplicat", e
            // pur si simplu o reluare normala.
            return contents.contains { !$0.hasPrefix("offload_checkpoint") && !$0.hasPrefix("offload_report_") }
        }
    }

    /// Sterge continutul folderelor deja existente la `folderName`, pe
    /// TOATE destinatiile date - folosit de optiunea "Suprascrie complet".
    func clearExistingFolders(destinations: [String], folderName: String) {
        for dest in destinations {
            let targetRoot = (dest as NSString).appendingPathComponent(folderName)
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: targetRoot) else { continue }
            for item in contents {
                try? FileManager.default.removeItem(atPath: (targetRoot as NSString).appendingPathComponent(item))
            }
        }
    }

    func togglePause() {
        guard isRunning else { return }
        if isPaused {
            pauseToken.resume()
            isPaused = false
            statusText = L.t("footer.copying")
        } else {
            pauseToken.pause()
            isPaused = true
            statusText = L.t("footer.paused")
        }
    }

    private func updateMemoryDisplay() {
        let limit = IOSettings.ramLimitMB
        bufferAllocatedText = limit == 0 ? "Fara limita" : formatBytes(Int64(limit) * 1024 * 1024)
        if let used = IOSettings.currentResidentMemoryBytes() {
            memoryUsedText = formatBytes(Int64(used))
        }
    }

    func start(sources: [String], destinations: [String],
               verificationModel: VerificationModel = .md5,
               exclusions: [String] = [], resume: Bool = true,
               project: String = "", card: String = "",
               folderNameOverride: String? = nil,
               cloudRemote: String = "", cloudRemoteFolder: String = "") {
        guard !isRunning else { return }

        var files: [FileEntry] = []
        for src in sources {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: src, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                files.append(contentsOf: listAllFiles(root: src, exclusions: exclusions))
            } else {
                let name = (src as NSString).lastPathComponent
                if isExcluded(filename: name, exclusions: exclusions) { continue }
                let size = (try? FileManager.default.attributesOfItem(atPath: src)[.size] as? Int64) ?? nil
                files.append(FileEntry(fullPath: src, relPath: name, size: size ?? 0))
            }
        }
        guard !files.isEmpty else {
            statusText = L.t("footer.noFiles")
            return
        }

        // Plafon de proba (2026-08-30) - vezi LicenseManager.
        // trialMaxTransferBytes. Verificat pe DIMENSIUNEA TOTALA a
        // transferului (suma tuturor fisierelor sursa), o singura data,
        // inainte de a porni orice copiere - nu un plafon per fisier, ca
        // sa nu poata fi ocolit trimitand multe fisiere mici.
        if !LicenseManager.shared.isLicensed {
            let totalBytes = files.reduce(Int64(0)) { $0 + $1.size }
            if totalBytes > LicenseManager.trialMaxTransferBytes {
                trialLimitExceededBytes = totalBytes
                statusText = L.t("trial.sizeLimitStatus")
                return
            }
        }
        trialLimitExceededBytes = nil

        // Numele folderului de destinatie: <data>_<Proiect>_<Card>, exact ca
        // in aplicatia Windows — implicit "Proiect"/"Card" daca lasi campurile
        // goale. `folderNameOverride` vine de la optiunea "Creeaza folder
        // nou" din dialogul de duplicate (ContentView), cand userul alege
        // sa NU foloseasca numele implicit deja existent la destinatie.
        let folderName = folderNameOverride ?? self.folderName(project: project, card: card)
        let sourceRoot = sources.first

        cancelToken = CancelToken()
        pauseToken = PauseToken()
        isPaused = false
        isRunning = true
        startTime = Date()
        bytesDone = 0
        filesDone = 0
        totalUnits = files.count * destinations.count
        progressPercent = 0
        statusText = L.t("footer.copying")
        speedText = ""
        lastResults = []
        activityLines = []
        updateMemoryDisplay()

        let token = cancelToken
        let pauseTok = pauseToken
        let group = DispatchGroup()
        var results: [DestinationResult] = []
        let resultsLock = NSLock()

        // Cloud secondary destination (2026-08-30) - o coada de upload NOUA
        // per destinatie locala, ca fiecare disc/destinatie sa urce
        // independent, in paralel cu celelalte destinatii locale (fiecare
        // job ruleaza deja pe propriul thread).
        let trimmedRemote = cloudRemote.trimmingCharacters(in: .whitespaces)

        for dest in destinations {
            group.enter()
            let cloudQueue: CloudUploadQueue? = trimmedRemote.isEmpty ? nil : CloudUploadQueue(
                remote: trimmedRemote, remoteFolder: cloudRemoteFolder,
                onLine: { [weak self] line in
                    Task { @MainActor [weak self] in self?.logActivity(line) }
                }
            )
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let job = DestinationJob(
                    destRoot: dest, folderName: folderName, files: files, cancel: token,
                    pause: pauseTok,
                    verificationModel: verificationModel, resume: resume, sourceRoot: sourceRoot,
                    cloudUploadQueue: cloudQueue,
                    onFileDone: { size in
                        Task { @MainActor [weak self] in
                            self?.advance(size: size)
                        }
                    },
                    onActivity: { line in
                        Task { @MainActor [weak self] in
                            self?.logActivity(line)
                        }
                    }
                )
                let result = job.run()
                resultsLock.lock(); results.append(result); resultsLock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.finish(results: results, folderName: folderName, sources: sources, destinations: destinations)
        }
    }

    func cancel() {
        guard isRunning else { return }
        cancelToken.cancel()
        statusText = L.t("status.cancelling")
    }

    /// Adauga o linie in feed-ul de activitate — cu viteza curenta atasata,
    /// ca in exemplul cerut ("Copiere: fisier.MOV | 450 MB/s"), ca userul
    /// sa vada dintr-o privire ca aplicatia lucreaza, nu ca s-a blocat.
    private func logActivity(_ line: String) {
        let withSpeed = speedText.isEmpty ? line : "\(line) — \(speedText)"
        activityLines.append(withSpeed)
        if activityLines.count > activityLogLimit {
            activityLines.removeFirst(activityLines.count - activityLogLimit)
        }
    }

    private func advance(size: Int64) {
        filesDone += 1
        bytesDone += size
        progressPercent = totalUnits > 0 ? Int(Double(filesDone) * 100 / Double(totalUnits)) : 0
        statusText = "\(progressPercent)% (\(filesDone)/\(totalUnits) \(L.t("footer.filesWord")))"
        if let start = startTime {
            let elapsed = Date().timeIntervalSince(start)
            if elapsed > 0 {
                speedText = formatBytes(Int64(Double(bytesDone) / elapsed)) + "/s"
            }
        }
        updateMemoryDisplay()
    }

    private func finish(results: [DestinationResult], folderName: String, sources: [String], destinations: [String]) {
        isRunning = false
        lastResults = results
        let anyCancelled = results.contains { $0.cancelled }
        let totalOK = results.reduce(0) { $0 + $1.okCount }
        let totalSkip = results.reduce(0) { $0 + $1.skipCount }
        let totalFail = results.reduce(0) { $0 + $1.failCount }
        statusText = anyCancelled
            ? L.t("footer.cancelled")
            : "\(L.t("footer.finished")) — \(totalOK) OK\(totalFail > 0 ? ", \(totalFail) \(L.t("footer.problems"))" : "")."
        NSSound(named: "Glass")?.play()

        HistoryStore.shared.record(folderName: folderName, sources: sources, destinations: destinations,
                                    okCount: totalOK, skipCount: totalSkip, failCount: totalFail)
    }
}
