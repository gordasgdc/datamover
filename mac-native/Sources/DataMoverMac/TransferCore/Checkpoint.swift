import Foundation
import CryptoKit

// MARK: - Identitatea sursei
//
// Un checkpoint spune „fișierul X a fost confirmat” — dar confirmat pentru CE
// sursă? Fără identitate, un card nou montat la aceeași cale, cu aceleași
// nume și mărimi (situație obișnuită: aceeași cameră, alt card), ar fi fost
// sărit ca „deja copiat”. Identitatea de mai jos e comparată integral; orice
// diferență respinge checkpoint-ul, iar fișierele existente se reverifică
// prin citire (nu se presupun corecte).
//
// Limită declarată: două surse cu aceleași căi, mărimi ȘI date de modificare
// identice la microsecundă, dar conținut diferit, nu pot fi deosebite fără a
// reciti sursa. De aceea checkpoint-ul cere în plus ca volumul să fie același
// (UUID), iar fișierele marcate „ok” să aibă aceeași amprentă mărime:mtime.

struct SourceIdentity: Codable, Equatable {
    /// Căile canonice ale surselor (symlink-uri rezolvate), în ordine.
    let roots: [String]
    /// UUID-ul volumului fiecărei surse ("?" dacă sistemul nu îl expune).
    let volumes: [String]
    /// SHA-256 peste lista sortată „cale relativă · mărime · mtime”.
    let manifestDigest: String
    let fileCount: Int

    enum CodingKeys: String, CodingKey {
        case roots, volumes, fileCount = "file_count", manifestDigest = "manifest_digest"
    }

    static func volumeUUID(of path: String) -> String {
        let v = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeUUIDStringKey])
        return v?.volumeUUIDString ?? "?"
    }

    static func compute(sources: [String], files: [FileEntry]) -> SourceIdentity {
        var hasher = SHA256()
        for f in files.sorted(by: { $0.relPath < $1.relPath || ($0.relPath == $1.relPath && $0.fullPath < $1.fullPath) }) {
            hasher.update(data: Data("\(f.relPath)\u{0}\(f.size)\u{0}\(f.mtimeMicros)\n".utf8))
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return SourceIdentity(roots: sources.map(Preflight.canonical),
                              volumes: sources.map(volumeUUID(of:)),
                              manifestDigest: digest, fileCount: files.count)
    }
}

// MARK: - Checkpoint (schema 2)

struct CheckpointData: Codable {
    var schema: Int?
    var source: String?
    var folderName: String
    var verificationModel: String
    var completed: Bool
    var files: [String: String]
    var totalFiles: Int?
    var sourceIdentity: SourceIdentity?
    /// Amprenta sursei (mărime:mtime) pentru fiecare fișier confirmat.
    var fileStamps: [String: String]?

    enum CodingKeys: String, CodingKey {
        case schema, source, completed, files
        case folderName = "folder_name"
        case verificationModel = "verification_model"
        case totalFiles = "total_files"
        case sourceIdentity = "source_identity"
        case fileStamps = "file_stamps"
    }
}

enum CheckpointStore {
    static let filename = "offload_checkpoint.json"
    static let schema = 2
    static let allowedStates: Set<String> = ["ok", "sarit", "fail"]

    static func path(targetRoot: String) -> String {
        (targetRoot as NSString).appendingPathComponent(filename)
    }

    struct Loaded: Equatable {
        let files: [String: String]
        let stamps: [String: String]
    }

    enum LoadResult: Equatable {
        case none
        case valid(Loaded)
        case rejected(String)
    }

    /// Acceptă checkpoint-ul DOAR dacă aparține exact aceluiași transfer:
    /// schema curentă, aceeași identitate a sursei, același folder, același
    /// model de verificare, stări cunoscute. Orice altceva e respins, cu
    /// motivul întors (nu înghițit).
    static func loadValidated(targetRoot: String, folderName: String, verificationModel: String,
                              identity: SourceIdentity) -> LoadResult {
        let p = path(targetRoot: targetRoot)
        guard let data = FileManager.default.contents(atPath: p) else { return .none }
        guard let d = try? JSONDecoder().decode(CheckpointData.self, from: data) else {
            return .rejected("fișier corupt")
        }
        guard d.schema == schema, let saved = d.sourceIdentity, let stamps = d.fileStamps else {
            return .rejected("format vechi, fără identitatea sursei")
        }
        if d.verificationModel != verificationModel { return .rejected("alt model de verificare: \(d.verificationModel)") }
        if d.folderName != folderName { return .rejected("alt folder: \(d.folderName)") }
        if saved != identity { return .rejected("altă sursă (cale, volum sau conținut listat diferit)") }
        if d.files.values.contains(where: { !allowedStates.contains($0) }) { return .rejected("stare necunoscută în fișier") }
        return .valid(Loaded(files: d.files, stamps: stamps))
    }

    /// Scriere atomică: tmp + flush + rename(2). Întoarce eroarea, nu o
    /// înghite. Politică: checkpoint-ul e o OPTIMIZARE (nu dovadă — o reluare
    /// tot cere identitatea sursei + fișierul existent cu mărimea corectă),
    /// deci un eșec aici nu schimbă verdictul fișierelor, dar se consemnează.
    @discardableResult
    static func save(targetRoot: String, folderName: String, verificationModel: String,
                     identity: SourceIdentity, files: [String: String], stamps: [String: String],
                     completed: Bool) -> Error? {
        let payload = CheckpointData(schema: schema, source: identity.roots.first, folderName: folderName,
                                     verificationModel: verificationModel, completed: completed,
                                     files: files, totalFiles: files.count,
                                     sourceIdentity: identity, fileStamps: stamps)
        let p = path(targetRoot: targetRoot)
        let tmp = p + ".tmp"
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: URL(fileURLWithPath: tmp))
            guard let h = FileHandle(forWritingAtPath: tmp) else {
                throw TransferIssueError(message: "Checkpoint: nu pot redeschide fișierul temporar")
            }
            defer { try? h.close() }
            _ = try physicalFlush(h)
            if Darwin.rename(tmp, p) != 0 {
                let code = errno
                try? FileManager.default.removeItem(atPath: tmp)
                throw posixError(code, "Checkpoint: redenumirea a eșuat")
            }
            return nil
        } catch {
            try? FileManager.default.removeItem(atPath: tmp)
            return error
        }
    }
}
