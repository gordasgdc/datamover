import Foundation
import CryptoKit
import AppKit
import CoreText

/// Port Swift complet al core/offload_engine.py: listare fisiere (cu
/// excluderi), copiere in bucati (anulabila), verificare (MD5/SHA1/
/// SHA256/SHA512/doar-dimensiune), progres, checkpoint/reluare, raport
/// CSV + PDF. Format de folder si nume de fisiere identice cu Python,
/// ca rapoartele sa fie recognoscibile langa cele generate de Windows.

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

/// Hash generic pe bucati, pentru orice algoritm CryptoKit conform
/// HashFunction (MD5/SHA1/SHA256/SHA512 partajate acelasi cod).
private func genericHash<H: HashFunction>(path: String, using: H.Type, cancel: CancelToken) throws -> String {
    guard let handle = FileHandle(forReadingAtPath: path) else {
        throw NSError(domain: "DataMover", code: 2, userInfo: [NSLocalizedDescriptionKey: "Nu pot citi \(path)"])
    }
    defer { try? handle.close() }

    var hasher = H()
    while true {
        if cancel.isCancelled { throw OffloadCancelled() }
        let chunk = handle.readData(ofLength: offloadChunkSize)
        if chunk.isEmpty { break }
        hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

func hashOfFile(path: String, model: VerificationModel, cancel: CancelToken) throws -> String {
    switch model {
    case .md5: return try genericHash(path: path, using: Insecure.MD5.self, cancel: cancel)
    case .sha1: return try genericHash(path: path, using: Insecure.SHA1.self, cancel: cancel)
    case .sha256: return try genericHash(path: path, using: SHA256.self, cancel: cancel)
    case .sha512: return try genericHash(path: path, using: SHA512.self, cancel: cancel)
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
    let verificationModel: VerificationModel
    let resume: Bool
    let sourceRoot: String?
    /// apelat dupa fiecare fisier procesat (pe thread-ul de fundal —
    /// OffloadRunner e cel care sare pe main thread inainte sa atinga UI)
    let onFileDone: (_ size: Int64) -> Void

    private var reportRows: [ReportRow] = []
    private var okCount = 0, skipCount = 0, failCount = 0
    private var cancelled = false
    private var filesStatus: [String: String] = [:]
    private var filesSinceCheckpoint = 0
    private var lastCheckpointTime = Date.distantPast
    private var startedAt = Date()

    init(destRoot: String, folderName: String, files: [FileEntry], cancel: CancelToken,
         verificationModel: VerificationModel = .md5, resume: Bool = false, sourceRoot: String? = nil,
         onFileDone: @escaping (_ size: Int64) -> Void) {
        self.destRoot = destRoot
        self.folderName = folderName
        self.files = files
        self.cancel = cancel
        self.verificationModel = verificationModel
        self.resume = resume
        self.sourceRoot = sourceRoot
        self.onFileDone = onFileDone
    }

    func run() -> DestinationResult {
        startedAt = Date()
        let targetRoot = (destRoot as NSString).appendingPathComponent(folderName)
        try? FileManager.default.createDirectory(atPath: targetRoot, withIntermediateDirectories: true)

        var alreadyDone: Set<String> = []
        if resume, let saved = CheckpointStore.load(targetRoot: targetRoot) {
            filesStatus = saved
            alreadyDone = Set(saved.filter { $0.value == "ok" || $0.value == "sarit" }.keys)
        }

        for entry in files {
            if cancel.isCancelled { cancelled = true; break }

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
                try copyFileCancelable(src: entry.fullPath, dst: destPath, cancel: cancel)
                let (same, s, d) = try verifyPair(entry: entry, destPath: destPath)
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
            reportRows.append(ReportRow(file: entry.relPath, sizeBytes: entry.size,
                                          srcHash: srcRepr, dstHash: dstRepr,
                                          status: status, error: errorMsg))
            onFileDone(entry.size)
            maybeWriteCheckpoint(targetRoot: targetRoot)
        }

        maybeWriteCheckpoint(targetRoot: targetRoot, force: true)
        let (csvPath, pdfPath) = writeReports(targetRoot: targetRoot)
        return DestinationResult(destRoot: destRoot, okCount: okCount, skipCount: skipCount,
                                  failCount: failCount, cancelled: cancelled,
                                  csvPath: csvPath, pdfPath: pdfPath)
    }

    private func verifyPair(entry: FileEntry, destPath: String) throws -> (same: Bool, srcRepr: String, dstRepr: String) {
        if verificationModel == .sizeOnly {
            let dstSize = (try? FileManager.default.attributesOfItem(atPath: destPath)[.size] as? Int64) ?? nil
            let d = dstSize ?? -1
            return (d == entry.size, "marime=\(entry.size)", "marime=\(d)")
        }
        let srcHash = try hashOfFile(path: entry.fullPath, model: verificationModel, cancel: cancel)
        let dstHash = try hashOfFile(path: destPath, model: verificationModel, cancel: cancel)
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

    private func writeReports(targetRoot: String) -> (csv: String?, pdf: String?) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())

        let csvPath = (targetRoot as NSString).appendingPathComponent("offload_report_\(timestamp).csv")
        var csv = "fisier,marime_bytes,verificare_sursa,verificare_destinatie,status,eroare\n"
        for row in reportRows {
            let fields = [row.file, String(row.sizeBytes), row.srcHash, row.dstHash, row.status, row.error]
            csv += fields.map { csvEscape($0) }.joined(separator: ",") + "\n"
        }
        var savedCSV: String? = nil
        do { try csv.write(toFile: csvPath, atomically: true, encoding: .utf8); savedCSV = csvPath } catch {}

        let pdfPath = (targetRoot as NSString).appendingPathComponent("offload_report_\(timestamp).pdf")
        let savedPDF = writePDFReport(
            path: pdfPath, destination: destRoot, folderName: folderName, rows: reportRows,
            startedAt: startedAt, finishedAt: Date(), okCount: okCount, skipCount: skipCount,
            failCount: failCount, cancelled: cancelled, verificationLabel: verificationModel.label
        ) ? pdfPath : nil

        return (savedCSV, savedPDF)
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
                             failCount: Int, cancelled: Bool, verificationLabel: String) -> Bool {
    let pageWidth: CGFloat = 595 // A4 @ 72dpi
    let pageHeight: CGFloat = 842
    let margin: CGFloat = 40
    var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

    guard let consumer = CGDataConsumer(url: URL(fileURLWithPath: path) as CFURL),
          let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return false }

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
    y -= 26

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
    return true
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

    private var cancelToken = CancelToken()
    private var startTime: Date?
    private var bytesDone: Int64 = 0

    func start(sources: [String], destinations: [String],
               verificationModel: VerificationModel = .md5,
               exclusions: [String] = [], resume: Bool = true,
               project: String = "", card: String = "") {
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

        // Numele folderului de destinatie: <data>_<Proiect>_<Card>, exact ca
        // in aplicatia Windows — implicit "Proiect"/"Card" daca lasi campurile
        // goale. Diferit de timestamp-ul cu ora folosit pentru rapoarte
        // (writeReports isi calculeaza propriul sau, mai jos).
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateStr = dateFormatter.string(from: Date())
        let proj = project.trimmingCharacters(in: .whitespaces).isEmpty ? "Proiect" : project.trimmingCharacters(in: .whitespaces)
        let crd = card.trimmingCharacters(in: .whitespaces).isEmpty ? "Card" : card.trimmingCharacters(in: .whitespaces)
        let folderName = "\(dateStr)_\(proj)_\(crd)".replacingOccurrences(of: " ", with: "_")
        let sourceRoot = sources.first

        cancelToken = CancelToken()
        isRunning = true
        startTime = Date()
        bytesDone = 0
        filesDone = 0
        totalUnits = files.count * destinations.count
        progressPercent = 0
        statusText = L.t("footer.copying")
        speedText = ""
        lastResults = []

        let token = cancelToken
        let group = DispatchGroup()
        var results: [DestinationResult] = []
        let resultsLock = NSLock()

        for dest in destinations {
            group.enter()
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let job = DestinationJob(destRoot: dest, folderName: folderName, files: files, cancel: token,
                                          verificationModel: verificationModel, resume: resume, sourceRoot: sourceRoot) { size in
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
            self?.finish(results: results, folderName: folderName, sources: sources, destinations: destinations)
        }
    }

    func cancel() {
        guard isRunning else { return }
        cancelToken.cancel()
        statusText = L.t("status.cancelling")
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
