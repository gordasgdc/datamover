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
    /// Data modificării la scanare, în microsecunde — parte din identitatea
    /// sursei (vezi `SourceIdentity`). 0 = necunoscută.
    var mtimeMicros: Int64 = 0

    /// „mărime:mtime” — amprenta per fișier salvată în checkpoint.
    var stamp: String { "\(size):\(mtimeMicros)" }
}

func mtimeMicros(_ attrs: [FileAttributeKey: Any]) -> Int64 {
    guard let d = attrs[.modificationDate] as? Date else { return 0 }
    return Int64((d.timeIntervalSince1970 * 1_000_000).rounded())
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
    /// [2026-09-03] `xxhash64` e primul din lista pentru ca e alegerea
    /// implicita a ofloaderelor profesionale (ShotPut Pro, Silverstack):
    /// aceeasi siguranta practica la detectarea coruperii de date ca MD5,
    /// dar de cateva ori mai rapid — pe un card de sute de GB, verificarea
    /// e etapa care dureaza, nu copierea. Vezi XXHash64.swift.
    case xxhash64, md5, sha1, sha256, sha512, sizeOnly = "marime"

    var id: String { rawValue }

    /// Numele scurt al algoritmului (pentru nodul de verificare, jurnal).
    var shortLabel: String {
        switch self {
        case .xxhash64: return "xxHash64"
        case .md5: return "MD5"
        case .sha1: return "SHA-1"
        case .sha256: return "SHA-256"
        case .sha512: return "SHA-512"
        case .sizeOnly: return L.t("depth.short.sizeOnly")
        }
    }

    var label: String {
        switch self {
        case .xxhash64: return L.t("verif.xxhash64")
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
        // Symlink către fișier: se copiază conținutul țintei, deci mărimea și
        // data trebuie să fie ale țintei (altfel verificarea mărimii ar eșua).
        let attrs = (try? fm.attributesOfItem(atPath: (full as NSString).resolvingSymlinksInPath)) ?? [:]
        results.append(FileEntry(fullPath: full, relPath: relPath, size: attrs[.size] as? Int64 ?? 0,
                                 mtimeMicros: mtimeMicros(attrs)))
    }
    return results
}

// [M2, 2026-09-06] `copyFileCancelable` (copiere 1-la-1, sursa->o
// destinatie) a fost STEARSA aici — de la M1 (FanOutCopier), nimic nu o
// mai apela (verificat cu grep pe tot modulul, Regula 30). Motorul de
// copiere real e acum `FanOutCopier.swift`, care foloseste ACELASI tipar
// de I/O throwing (`read(upToCount:)`/`write(contentsOf:)`) pentru
// exact acelasi motiv documentat aici pana acum: `readData(ofLength:)`/
// `.write(_:)` (variantele Objective-C vechi) ridica o exceptie
// Objective-C necapturabila la o eroare reala de I/O (card deconectat,
// disc plin) -> crash total al aplicatiei, nu doar eroare de job -
// confirmat printr-un crash real in trecut. Pastrat aici ca istoric al
// deciziei, pentru oricine atinge din nou I/O de fisiere in acest modul.

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

/// Acelasi tipar de citire in bucati ca `genericHash`, dar pentru xxHash64
/// — care nu e un `HashFunction` CryptoKit, deci nu poate folosi generic-ul
/// de mai sus. Aceleasi doua masuri obligatorii: `read(upToCount:)` (varianta
/// throwing, vezi WARNING-ul din copyFileCancelable) si `autoreleasepool`
/// per bucata (fara el, un fisier de zeci de GB acumuleaza toate bucatile
/// citite in memorie pana la final).
private func xxhash64OfFile(path: String, cancel: CancelToken, chunkSize: Int) throws -> String {
    guard let handle = FileHandle(forReadingAtPath: path) else {
        throw NSError(domain: "DataMover", code: 2, userInfo: [NSLocalizedDescriptionKey: "Nu pot citi \(path)"])
    }
    defer { try? handle.close() }

    var hasher = XXHash64()
    while true {
        if cancel.isCancelled { throw OffloadCancelled() }
        var stop = false
        try autoreleasepool {
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else {
                stop = true
                return
            }
            hasher.update(chunk)
        }
        if stop { break }
    }
    return hasher.hexDigest
}

func hashOfFile(path: String, model: VerificationModel, cancel: CancelToken, chunkSize: Int = offloadChunkSize) throws -> String {
    switch model {
    case .xxhash64: return try xxhash64OfFile(path: path, cancel: cancel, chunkSize: chunkSize)
    case .md5: return try genericHash(path: path, using: Insecure.MD5.self, cancel: cancel, chunkSize: chunkSize)
    case .sha1: return try genericHash(path: path, using: Insecure.SHA1.self, cancel: cancel, chunkSize: chunkSize)
    case .sha256: return try genericHash(path: path, using: SHA256.self, cancel: cancel, chunkSize: chunkSize)
    case .sha512: return try genericHash(path: path, using: SHA512.self, cancel: cancel, chunkSize: chunkSize)
    case .sizeOnly: return ""
    }
}

/// [2026-09-03] Detecteaza daca o eroare de copiere/citire e cauzata de
/// lipsa Full Disk Access (macOS blocheaza silentios citirea/scrierea pe
/// anumite volume/foldere pentru aplicatii fara aceasta permisiune —
/// EACCES/EPERM, nu o eroare de disc defect). `FileHandle.read/write`
/// arunca `NSError` in domeniul POSIX cu codul errno real; verificam si
/// eroarea "underlying", si textul localizat, ca sa prindem toate formele
/// in care Foundation poate ambala acelasi errno.
func isPermissionError(_ error: Error) -> Bool {
    func matches(_ nsErr: NSError) -> Bool {
        nsErr.domain == NSPOSIXErrorDomain && (nsErr.code == Int(EACCES) || nsErr.code == Int(EPERM))
    }
    let nsErr = error as NSError
    if matches(nsErr) { return true }
    if let underlying = nsErr.userInfo[NSUnderlyingErrorKey] as? NSError, matches(underlying) { return true }
    return nsErr.localizedDescription.localizedCaseInsensitiveContains("permission denied")
}

struct ReportRow {
    let file: String
    let sizeBytes: Int64
    let srcHash: String
    let dstHash: String
    let status: String
    let error: String
    /// [2026-09-06] Calea REALA a fisierului copiat la destinatie — pana
    /// acum lipsea (coloanele "Sursa"/"Destinatie" din HTMLReport arata de
    /// fapt hash-urile, nu caile). Necesara ca sa poata genera un thumbnail
    /// real (QLThumbnailGenerator) pentru raportul HTML, cerut de Cristi
    /// dupa ce a vazut thumbnail-urile din raportul CG Convertor.
    let destPath: String
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
    /// [2026-09-03] Raport HTML — vezi HTMLReport.
    var htmlPath: String? = nil
    /// [2026-09-03] Calea fisierului MHL scris langa date (nil daca
    /// generarea a fost oprita din Setari sau algoritmul ales nu e in
    /// standardul MHL — vezi MHLWriter.element(for:)).
    var mhlPath: String? = nil
    /// Cate fisiere esuate la prima trecere au fost recuperate de pasul
    /// automat de reincercare (vezi retryFailedFiles).
    var recoveredCount: Int = 0
    /// Folderul concret scris la această destinație (`<dest>/<folderName>`).
    var targetFolder: String? = nil

    /// Verdictul destinației — sursa unică pentru UI, istoric și ejectare.
    var outcome: DestinationOutcome {
        DestinationOutcome.evaluate(failCount: failCount, recoveredCount: recoveredCount, cancelled: cancelled)
    }
}
