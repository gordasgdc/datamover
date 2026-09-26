import Foundation
import os.log

// MARK: - Jurnal structurat local (OBSERVABILITY_STANDARD)
//
// O linie JSON per eveniment, în `~/Library/Logs/DataMover/datamover.jsonl`,
// plus unified log (subsistemul `dev.gordas.datamover`). Fiecare intrare are
// timestamp UTC cu milisecunde, nivel, componentă, event ID stabil, versiune,
// build, platformă, session ID și — când există — job ID și destination ID.
//
// Garanții:
// - scrierea NU aruncă și nu blochează operația principală (coadă serială,
//   `try?`); dacă folderul nu se poate scrie, rămâne doar unified log și
//   `lastWriteError` spune de ce;
// - rotație la `maxBytes`, cel mult `maxFiles` fișiere, cele mai vechi de
//   `maxAgeDays` se șterg — jurnalul nu poate umple discul;
// - textul trece prin `Redactor.redactSecrets` înainte de a atinge discul.

enum LogLevel: Int, Comparable, Codable, CaseIterable {
    case trace = 0, debug, info, warning, error, critical
    static func < (a: LogLevel, b: LogLevel) -> Bool { a.rawValue < b.rawValue }
    var name: String { String(describing: self) }
}

struct LogRecord: Codable, Equatable {
    let ts: String
    let level: String
    let component: String
    let event: String
    let app: String
    let build: String
    let platform: String
    let session: String
    var job: String?
    var dest: String?
    var msg: String
    var fields: [String: String]?
    var errorDomain: String?
    var errorCode: Int?
}

final class StructuredLog: @unchecked Sendable {
    struct Config {
        var directory: URL
        var fileName = "datamover.jsonl"
        var maxBytes: Int64 = 5 * 1024 * 1024
        var maxFiles = 5
        var maxAgeDays = 14
    }

    /// Instanța aplicației. Testele o înlocuiesc cu una într-un folder temporar
    /// (niciun test nu scrie în `~/Library/Logs`).
    nonisolated(unsafe) static var shared = StructuredLog(config: Config(directory: FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/DataMover", isDirectory: true)))

    let config: Config
    let sessionID: String
    /// Implicit `info`. `debug` se activează temporar (până la repornire) din Setări.
    var minimumLevel: LogLevel { lock.withLock { debugUntilRelaunch ? .debug : .info } }
    private var debugUntilRelaunch = false
    private(set) var lastWriteError: String?

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "dev.gordas.datamover.structuredlog", qos: .utility)
    private let osLog = Logger(subsystem: "dev.gordas.datamover", category: "structured")
    private let now: () -> Date
    private let app: String
    private let build: String
    private let platform: String
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    init(config: Config, sessionID: String = StructuredLog.newID(), now: @escaping () -> Date = Date.init) {
        self.config = config
        self.sessionID = sessionID
        self.now = now
        let info = Bundle.main.infoDictionary
        app = info?["CFBundleShortVersionString"] as? String ?? "dev"
        build = info?["CFBundleVersion"] as? String ?? "dev"
        let v = ProcessInfo.processInfo.operatingSystemVersion
        platform = "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion) \(Self.arch)"
    }

    static func newID() -> String { String(UUID().uuidString.prefix(8)).lowercased() }

    private static var arch: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }

    var fileURL: URL { config.directory.appendingPathComponent(config.fileName) }

    func setDebugUntilRelaunch(_ on: Bool) {
        lock.withLock { debugUntilRelaunch = on }
        log(.info, "diagnostics", "diagnostics.debug.\(on ? "enabled" : "disabled")", "Jurnal detaliat \(on ? "activat până la repornire" : "dezactivat")")
    }

    /// Punctul unic de intrare. Nu aruncă, nu blochează apelantul.
    func log(_ level: LogLevel, _ component: String, _ event: String, _ message: String,
             job: String? = nil, dest: String? = nil, fields: [String: String]? = nil, error: Error? = nil) {
        guard level >= minimumLevel else { return }
        let ns = error.map { $0 as NSError }
        var record = LogRecord(ts: Self.isoFormatter.string(from: now()), level: level.name, component: component,
                               event: event, app: app, build: build, platform: platform, session: sessionID,
                               job: job, dest: dest, msg: Redactor.redactSecrets(message),
                               fields: fields.map(Redactor.redactFields),
                               errorDomain: ns?.domain, errorCode: ns?.code)
        if let ns, record.fields?["error"] == nil {
            var f = record.fields ?? [:]
            f["error"] = Redactor.redactSecrets(ns.localizedDescription)
            record.fields = f
        }
        let osType: OSLogType = level >= .error ? .error : (level == .warning ? .default : (level == .info ? .info : .debug))
        osLog.log(level: osType, "\(event, privacy: .public) \(record.msg, privacy: .public)")
        queue.async { [weak self] in self?.append(record) }
    }

    /// Așteaptă scrierea tuturor intrărilor (teste, oprire, export).
    func flush() { queue.sync {} }

    // MARK: Scriere + rotație

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    private func append(_ record: LogRecord) {
        do {
            try FileManager.default.createDirectory(at: config.directory, withIntermediateDirectories: true)
            var line = try encoder.encode(record)
            line.append(0x0A)
            try rotateIfNeeded(incoming: Int64(line.count))
            let url = fileURL
            if !FileManager.default.fileExists(atPath: url.path) {
                guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                    throw CocoaError(.fileWriteNoPermission)
                }
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            lock.withLock { lastWriteError = nil }
        } catch {
            // Fallback sigur: unified log rămâne; operația principală nu află nimic.
            lock.withLock { lastWriteError = error.localizedDescription }
        }
    }

    private func rotatedURL(_ i: Int) -> URL { config.directory.appendingPathComponent("\(config.fileName).\(i)") }

    private func rotateIfNeeded(incoming: Int64) throws {
        let fm = FileManager.default
        let size = ((try? fm.attributesOfItem(atPath: fileURL.path)[.size] as? Int64) ?? nil) ?? 0
        if size > 0 && size + incoming > config.maxBytes {
            try? fm.removeItem(at: rotatedURL(config.maxFiles - 1))
            if config.maxFiles > 2 {
                for i in stride(from: config.maxFiles - 2, through: 1, by: -1) where fm.fileExists(atPath: rotatedURL(i).path) {
                    try? fm.moveItem(at: rotatedURL(i), to: rotatedURL(i + 1))
                }
            }
            try? fm.moveItem(at: fileURL, to: rotatedURL(1))
        }
        // Retenție pe vârstă: arhivele mai vechi de `maxAgeDays` dispar.
        let cutoff = now().addingTimeInterval(-Double(config.maxAgeDays) * 86_400)
        for i in 1..<max(config.maxFiles, 2) {
            let u = rotatedURL(i)
            if let m = (try? fm.attributesOfItem(atPath: u.path)[.modificationDate] as? Date) ?? nil, m < cutoff {
                try? fm.removeItem(at: u)
            }
        }
    }

    /// Fișierele existente, de la cel activ la cel mai vechi.
    func logFiles() -> [URL] {
        ([fileURL] + (1..<max(config.maxFiles, 2)).map(rotatedURL)).filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}

/// Identificator scurt și stabil pentru o destinație (corelare în log fără a
/// scrie calea completă în fiecare intrare).
func destinationLogID(_ path: String) -> String {
    Redactor.pathToken(path).replacingOccurrences(of: "<path#", with: "d-").replacingOccurrences(of: ">", with: "")
        .components(separatedBy: ".").first ?? "d-?"
}
