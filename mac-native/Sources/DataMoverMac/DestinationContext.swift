import Foundation
import CryptoKit
import AppKit
import CoreText

/// [M1 FAZA 2, 2026-09-06] Înlocuiește `DestinationJob` — extrage TOATĂ
/// starea/bookkeeping-ul per destinație (CSV, MHL, checkpoint, contoare,
/// coadă de reîncercare, rapoarte) fără propria buclă de copiere. Bucla
/// de copiere efectivă a mutat în `OffloadRunner.start()`, care acum
/// iterează fișierele O SINGURĂ DATĂ și le distribuie prin `FanOutCopier`
/// către toate destinațiile deodată — vezi comentariul din
/// `FanOutCopier.swift` pentru motiv (economia de 3 din 4 citiri ale
/// sursei per fișier, la 2 destinații).
///
/// Fiecare `DestinationContext` rămâne responsabil DOAR pentru ce ține de
/// EL: propriul CSV, propriul MHL, propriul checkpoint (poate diferi de
/// la o destinație la alta — una poate avea deja jumătate din fișiere
/// dintr-o rulare întreruptă, alta poate fi complet goală), propriile
/// contoare OK/SARIT/EROARE, propria coadă Cloud.
/// `@unchecked Sendable`: toata starea mutabila e atinsa DOAR de pe
/// thread-ul unic de transfer din `OffloadRunner.start()` (niciodata din
/// UI/main thread direct) - acelasi tipar deja folosit de `CancelToken`/
/// `PauseToken` in acest fisier.
final class DestinationContext: @unchecked Sendable {
    let destRoot: String
    let folderName: String
    let verificationModel: VerificationModel
    let generateMHL: Bool
    let meta: ProductionMeta
    let sourceRoot: String?
    let cloudUploadQueue: CloudUploadQueue?
    let onActivity: (_ line: String) -> Void
    let onPermissionError: (_ path: String) -> Void

    let targetRoot: String
    private(set) var cancelled = false
    private(set) var okCount = 0, skipCount = 0, failCount = 0
    private(set) var recoveredCount = 0
    /// Fișierele eșuate (EROARE/NEPOTRIVIRE) la prima trecere — reținute
    /// ca să poată fi reîncercate la finalul transferului. Cheie = relPath,
    /// ca să poată fi intersectate rapid cu lista globală de reîncercare
    /// din `OffloadRunner` (fiecare destinație poate avea un set DIFERIT
    /// de fișiere eșuate).
    private(set) var failedRelPaths: Set<String> = []

    private var alreadyDone: Set<String> = []
    private var filesStatus: [String: String] = [:]
    private var filesSinceCheckpoint = 0
    private var lastCheckpointTime = Date.distantPast
    private var pdfSampleRows: [ReportRow] = []
    private let pdfSampleLimit = 500
    private var csvHandle: FileHandle?
    private var csvPath: String?
    private var mhl: MHLWriter?
    let startedAt: Date

    init(destRoot: String, folderName: String, verificationModel: VerificationModel,
         generateMHL: Bool, meta: ProductionMeta, sourceRoot: String?,
         cloudUploadQueue: CloudUploadQueue?, startedAt: Date,
         onActivity: @escaping (_ line: String) -> Void,
         onPermissionError: @escaping (_ path: String) -> Void) {
        self.destRoot = destRoot
        self.folderName = folderName
        self.verificationModel = verificationModel
        self.generateMHL = generateMHL
        self.meta = meta
        self.sourceRoot = sourceRoot
        self.cloudUploadQueue = cloudUploadQueue
        self.startedAt = startedAt
        self.onActivity = onActivity
        self.onPermissionError = onPermissionError
        self.targetRoot = (destRoot as NSString).appendingPathComponent(folderName)
    }

    func destPath(for entry: FileEntry) -> String {
        (targetRoot as NSString).appendingPathComponent(entry.relPath)
    }

    /// Pregătește destinația: creează folderul țintă, deschide CSV-ul,
    /// pornește MHL-ul, încarcă checkpoint-ul existent (dacă `resume`).
    /// Identic ca efect cu începutul vechiului `DestinationJob.run()`.
    func prepare(resume: Bool) {
        try? FileManager.default.createDirectory(atPath: targetRoot, withIntermediateDirectories: true)
        openCSV()
        if generateMHL {
            if MHLWriter.isSupported(verificationModel) {
                let stamp = DateFormatter()
                stamp.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let mhlPath = (targetRoot as NSString)
                    .appendingPathComponent("\(folderName)_\(stamp.string(from: startedAt)).mhl")
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                mhl = MHLWriter(path: mhlPath, model: verificationModel,
                                toolName: "DataMover \(version)", startedAt: startedAt)
            } else {
                onActivity("MHL: nu se poate genera cu \(verificationModel.label) — standardul MHL acceptă doar xxHash64, MD5 sau SHA-1.")
            }
        }
        if resume, let saved = CheckpointStore.load(targetRoot: targetRoot) {
            filesStatus = saved
            var done: Set<String> = []
            for (relPath, status) in saved where status == "ok" || status == "sarit" {
                done.insert(relPath)
            }
            alreadyDone = done
        }
    }

    enum Classification {
        /// Deja marcat complet în checkpoint-ul ACESTEI destinații — nimic
        /// de citit/scris, nici măcar o verificare.
        case alreadyDone
        /// Fișier deja prezent la destinație, cu ACEEAȘI mărime ca sursa —
        /// candidat pentru "verifică fără recopiere" (recuperare dintr-o
        /// întrerupere fără checkpoint scris).
        case existingSameSize
        /// Nu există încă (sau mărimea diferă) — are nevoie de copiere
        /// reală prin fan-out.
        case needsCopy
    }

    /// Pur — nu are efecte laterale, doar decide în ce categorie intră
    /// fișierul PENTRU ACEASTĂ destinație (fiecare destinație poate avea
    /// un răspuns diferit pentru același fișier).
    func classify(entry: FileEntry, allowSkipExisting: Bool) -> Classification {
        if alreadyDone.contains(entry.relPath) { return .alreadyDone }
        guard allowSkipExisting else { return .needsCopy }
        let path = destPath(for: entry)
        guard FileManager.default.fileExists(atPath: path),
              let existingSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? nil,
              existingSize == entry.size else {
            return .needsCopy
        }
        return .existingSameSize
    }

    /// Fișier deja marcat OK/SARIT în checkpoint — doar contorizare,
    /// FĂRĂ rând nou în CSV (identic cu ramura `alreadyDone` din vechiul
    /// `DestinationJob.run()`, care nu apela `logRow` acolo).
    func recordSkippedViaCheckpoint(entry: FileEntry) {
        skipCount += 1
        maybeCheckpoint()
    }

    /// Fișierul exista deja, cu hash IDENTIC — confirmat fără recopiere.
    func recordVerifiedExisting(entry: FileEntry, srcHash: String, dstHash: String) {
        skipCount += 1
        filesStatus[entry.relPath] = "sarit"
        logRow(ReportRow(file: entry.relPath, sizeBytes: entry.size, srcHash: srcHash, dstHash: dstHash,
                          status: "SARIT", error: "", destPath: destPath(for: entry)))
        recordInMHL(entry: entry, hash: srcHash)
        cloudUploadQueue?.enqueue(relPath: entry.relPath)
        maybeCheckpoint()
    }

    /// Rezultatul unei copieri fan-out (prin `FanOutCopier`) pentru
    /// ACEASTĂ destinație — mapează 1:1 la vechile ramuri OK/NEPOTRIVIRE
    /// din `processOne`, dar hash-ul e deja cel calculat LA SCRIERE (nu
    /// printr-o recitire a destinației de pe disc).
    func recordCopyOutcome(entry: FileEntry, sourceHash: String, outcome: FanOutDestOutcome, isRetry: Bool) {
        switch outcome {
        case .success(let hash, _):
            let same = hash == sourceHash
            let status = same ? (isRetry ? "OK (reîncercat)" : "OK") : (isRetry ? "NEPOTRIVIRE (reîncercat)" : "NEPOTRIVIRE")
            if same {
                if isRetry { failCount -= 1; recoveredCount += 1; onActivity("Recuperat la reîncercare: \(entry.relPath)") }
                okCount += 1
                filesStatus[entry.relPath] = "ok"
                recordInMHL(entry: entry, hash: sourceHash)
                cloudUploadQueue?.enqueue(relPath: entry.relPath)
            } else {
                if !isRetry { failCount += 1; failedRelPaths.insert(entry.relPath) }
                else { onActivity("Eșuat și la reîncercare: \(entry.relPath)") }
                filesStatus[entry.relPath] = "fail"
            }
            logRow(ReportRow(file: entry.relPath, sizeBytes: entry.size, srcHash: sourceHash, dstHash: hash,
                              status: status, error: "", destPath: destPath(for: entry)))
        case .failure(let error):
            if !isRetry { failCount += 1; failedRelPaths.insert(entry.relPath) }
            else { onActivity("Eșuat și la reîncercare: \(entry.relPath)") }
            filesStatus[entry.relPath] = "fail"
            let status = isRetry ? "EROARE (reîncercat)" : "EROARE"
            logRow(ReportRow(file: entry.relPath, sizeBytes: entry.size, srcHash: sourceHash, dstHash: "",
                              status: status, error: error.localizedDescription, destPath: destPath(for: entry)))
            if isPermissionError(error) { onPermissionError(destPath(for: entry)) }
        }
        if !isRetry { maybeCheckpoint() }
    }

    /// Sursa n-a putut fi citită DELOC (card deconectat la mijloc) — toate
    /// destinațiile din bucketul curent primesc aceeași eroare.
    func recordSourceReadFailure(entry: FileEntry, error: Error, isRetry: Bool) {
        if !isRetry { failCount += 1; failedRelPaths.insert(entry.relPath) }
        filesStatus[entry.relPath] = "fail"
        logRow(ReportRow(file: entry.relPath, sizeBytes: entry.size, srcHash: "", dstHash: "",
                          status: isRetry ? "EROARE (reîncercat)" : "EROARE",
                          error: error.localizedDescription, destPath: destPath(for: entry)))
        if !isRetry { maybeCheckpoint() }
    }

    /// Șterge fișierul parțial de la destinație înainte de reîncercare —
    /// identic cu vechiul `retryFailed` (altfel logica "există deja,
    /// verific doar" l-ar putea considera bun).
    func prepareForRetry(entry: FileEntry) {
        try? FileManager.default.removeItem(atPath: destPath(for: entry))
    }

    private func recordInMHL(entry: FileEntry, hash: String) {
        guard let mhl, !hash.isEmpty else { return }
        let modDate = (try? FileManager.default.attributesOfItem(atPath: entry.fullPath)[.modificationDate] as? Date) ?? nil
        mhl.add(relPath: entry.relPath, size: entry.size, modificationDate: modDate, hashHex: hash, hashedAt: Date())
    }

    func maybeCheckpoint(force: Bool = false) {
        filesSinceCheckpoint += 1
        let now = Date()
        let dueByCount = filesSinceCheckpoint >= 10
        let dueByTime = now.timeIntervalSince(lastCheckpointTime) >= 5.0
        guard force || dueByCount || dueByTime else { return }
        CheckpointStore.save(targetRoot: targetRoot, source: sourceRoot, folderName: folderName,
                              verificationModel: verificationModel.rawValue, files: filesStatus,
                              completed: force && !cancelled, totalFiles: filesStatus.count)
        filesSinceCheckpoint = 0
        lastCheckpointTime = now
    }

    func markCancelled() { cancelled = true }

    private func openCSV() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let path = (targetRoot as NSString).appendingPathComponent("offload_report_\(timestamp).csv")
        FileManager.default.createFile(atPath: path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: path) else { return }
        handle.write("fisier,marime_bytes,verificare_sursa,verificare_destinatie,status,eroare\n".data(using: .utf8) ?? Data())
        csvHandle = handle
        csvPath = path
    }

    private func logRow(_ row: ReportRow) {
        if let handle = csvHandle {
            let fields = [row.file, String(row.sizeBytes), row.srcHash, row.dstHash, row.status, row.error]
            let line = fields.map { csvEscape($0) }.joined(separator: ",") + "\n"
            autoreleasepool { handle.write(line.data(using: .utf8) ?? Data()) }
        }
        let isProblem = row.status.hasPrefix("EROARE") || row.status.hasPrefix("NEPOTRIVIRE")
        if isProblem || pdfSampleRows.count < pdfSampleLimit {
            pdfSampleRows.append(row)
        }
    }

    private func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }

    /// Finalizează: așteaptă upload-urile Cloud, scrie checkpoint-ul final,
    /// închide MHL-ul, generează CSV/PDF/HTML — identic cu vechiul
    /// `writeReports` + coada finală din `DestinationJob.run()`.
    func finalize() -> DestinationResult {
        if let queue = cloudUploadQueue {
            onActivity("Cloud: se așteaptă finalizarea urcărilor rămase…")
            queue.waitUntilDrained()
        }
        maybeCheckpoint(force: true)
        let mhlPath = mhl?.close(finishedAt: Date())
        if let mhlPath {
            onActivity("MHL scris: \((mhlPath as NSString).lastPathComponent) (\(mhl?.entryCount ?? 0) fișiere certificate)")
        }

        try? csvHandle?.close()
        csvHandle = nil

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())
        let pdfPath = (targetRoot as NSString).appendingPathComponent("offload_report_\(timestamp).pdf")
        let finishedAt = Date()
        let totalRows = okCount + skipCount + failCount
        let truncatedNote = pdfSampleRows.count < totalRows
            ? "Lista completa (\(totalRows) fisiere) e in CSV-ul alaturat - PDF-ul arata toate problemele plus un esantion."
            : nil

        let htmlPath = (targetRoot as NSString).appendingPathComponent("offload_report_\(timestamp).html")
        let htmlOK = HTMLReport.write(
            path: htmlPath, destination: destRoot, folderName: folderName, rows: pdfSampleRows,
            meta: meta, startedAt: startedAt, finishedAt: finishedAt,
            okCount: okCount, skipCount: skipCount, failCount: failCount,
            recoveredCount: recoveredCount, cancelled: cancelled,
            verificationLabel: verificationModel.label, mhlPath: mhlPath,
            truncatedNote: truncatedNote)
        if !htmlOK { onActivity("Nu s-a putut genera raportul HTML.") }

        let pdfResult = writePDFReport(
            path: pdfPath, destination: destRoot, folderName: folderName, rows: pdfSampleRows,
            startedAt: startedAt, finishedAt: finishedAt, okCount: okCount, skipCount: skipCount,
            failCount: failCount, cancelled: cancelled, verificationLabel: verificationModel.label,
            meta: meta, recoveredCount: recoveredCount, mhlPath: mhlPath,
            truncatedNote: truncatedNote
        )
        let savedPDF: String? = pdfResult.ok ? pdfPath : nil
        if !pdfResult.ok {
            let reason = pdfResult.error ?? "motiv necunoscut"
            onActivity("Nu s-a putut genera raportul PDF: \(reason)")
            let errPath = (targetRoot as NSString).appendingPathComponent("offload_report_PDF_EROARE.txt")
            try? "Generarea raportului PDF a esuat la \(Date()).\n\nMotiv: \(reason)\n".write(toFile: errPath, atomically: true, encoding: .utf8)
        }

        return DestinationResult(destRoot: destRoot, okCount: okCount, skipCount: skipCount,
                                  failCount: failCount, cancelled: cancelled,
                                  csvPath: csvPath, pdfPath: savedPDF,
                                  htmlPath: htmlOK ? htmlPath : nil, mhlPath: mhlPath,
                                  recoveredCount: recoveredCount)
    }
}
