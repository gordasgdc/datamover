import Foundation
import Darwin

// MARK: - Persistență pe disc (flush)
//
// Ce garantează, realist:
// - `F_FULLFSYNC` cere controllerului să scrie pe mediu și cache-ul propriu.
//   Apple îl documentează ca singura cale de a cere asta; tot dispozitivul
//   (firmware-ul) decide dacă o respectă. Nu e o garanție matematică.
// - `fsync` (rezerva) garantează doar că datele au plecat din memoria
//   sistemului spre dispozitiv; cache-ul dispozitivului poate să nu fie golit.
//
// Politică:
// - Fișier de date: flush OBLIGATORIU. `F_FULLFSYNC` → dacă volumul nu îl
//   acceptă (ENOTSUP/EINVAL/ENOTTY), `fsync`. Dacă și `fsync` eșuează, sau
//   `F_FULLFSYNC` eșuează cu altă eroare, fișierul NU e confirmat și eroarea
//   păstrează errno.
// - Folder părinte după redenumire: OBLIGATORIU acolo unde e acceptat. Un
//   volum care nu acceptă flush pe foldere (ENOTSUP/EINVAL/ENOTTY/EBADF) e
//   consemnat ca atare; orice altă eroare face fișierul neconfirmat.
// - Checkpoint: încercat cu aceeași strategie, dar e o optimizare, nu o
//   dovadă (vezi `CheckpointStore.save`); eșecul lui se consemnează.

/// Nivelul de flush obținut efectiv — raportat, nu presupus.
enum FlushLevel: String {
    /// `F_FULLFSYNC` acceptat de volum.
    case full
    /// Volumul nu acceptă `F_FULLFSYNC`; `fsync` reușit (garanție mai slabă).
    case fsyncFallback
    /// Doar pentru foldere: volumul nu acceptă flush pe folder.
    case unsupported
}

func posixError(_ code: Int32, _ context: String) -> NSError {
    NSError(domain: NSPOSIXErrorDomain, code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: "\(context): \(String(cString: strerror(code))) (errno \(code))"])
}

/// Primitivele de sistem, injectabile în teste. Fiecare întoarce 0 sau errno.
struct FlushPrimitives {
    var fullFsync: (Int32) -> Int32
    var fsync: (Int32) -> Int32

    static let system = FlushPrimitives(
        fullFsync: { fd in fcntl(fd, F_FULLFSYNC) == -1 ? errno : 0 },
        fsync: { fd in Darwin.fsync(fd) == -1 ? errno : 0 })

    /// Coduri care înseamnă „operația nu e suportată aici”, nu „disc defect”.
    static let unsupportedCodes: Set<Int32> = [ENOTSUP, EINVAL, ENOTTY]
}

/// Flush pe un descriptor de fișier de date. Aruncă dacă datele nu pot fi
/// confirmate ca plecate spre dispozitiv.
@discardableResult
func physicalFlush(fd: Int32, using p: FlushPrimitives = .system) throws -> FlushLevel {
    let full = p.fullFsync(fd)
    if full == 0 { return .full }
    guard FlushPrimitives.unsupportedCodes.contains(full) else {
        throw posixError(full, "Flush fizic (F_FULLFSYNC) eșuat")
    }
    let plain = p.fsync(fd)
    if plain == 0 { return .fsyncFallback }
    throw posixError(plain, "Flush (fsync, după F_FULLFSYNC nesuportat) eșuat")
}

@discardableResult
func physicalFlush(_ handle: FileHandle, using p: FlushPrimitives = .system) throws -> FlushLevel {
    try physicalFlush(fd: handle.fileDescriptor, using: p)
}

/// Flush pe folder (persistă redenumirea). `unsupported` e un rezultat
/// legitim pe unele sisteme de fișiere; orice altă eroare aruncă.
@discardableResult
func flushDirectory(_ dir: String, using p: FlushPrimitives = .system) throws -> FlushLevel {
    let fd = open(dir, O_RDONLY)
    guard fd >= 0 else { throw posixError(errno, "Nu pot deschide folderul pentru flush") }
    defer { close(fd) }
    let full = p.fullFsync(fd)
    if full == 0 { return .full }
    let dirUnsupported = FlushPrimitives.unsupportedCodes.union([EBADF])
    guard dirUnsupported.contains(full) else { throw posixError(full, "Flush folder (F_FULLFSYNC) eșuat") }
    let plain = p.fsync(fd)
    if plain == 0 { return .fsyncFallback }
    if dirUnsupported.contains(plain) { return .unsupported }
    throw posixError(plain, "Flush folder (fsync) eșuat")
}

// MARK: - Recitire (read-back)

/// Rezultatul recitirii: hash-ul și dacă `F_NOCACHE` a fost acceptat.
/// Chiar acceptat, `F_NOCACHE` NU scoate din memorie paginile deja în cache
/// și nu controlează cache-ul propriu al dispozitivului: recitirea e o a doua
/// citire independentă prin sistemul de fișiere, nu o dovadă a mediului fizic.
struct ReadBackResult {
    let hash: String
    let cacheBypassRequested: Bool
}

func readBackHash(path: String, model: VerificationModel, chunkSize: Int, cancel: CancelToken,
                  setNoCache: (Int32) -> Int32 = { fcntl($0, F_NOCACHE, 1) == -1 ? errno : 0 }) throws -> ReadBackResult {
    guard let handle = FileHandle(forReadingAtPath: path) else {
        throw TransferIssueError(message: "Nu pot reciti \(path)")
    }
    defer { try? handle.close() }
    // Politică explicită: dacă volumul refuză F_NOCACHE, recitirea continuă,
    // dar rezultatul e marcat și consemnat ca „cache neocolit”.
    let bypass = setNoCache(handle.fileDescriptor) == 0
    var hasher = IncrementalHasher(model: model)
    while true {
        if cancel.isCancelled { throw OffloadCancelled() }
        var chunk: Data?
        try autoreleasepool { chunk = try handle.read(upToCount: chunkSize) }
        guard let chunk, !chunk.isEmpty else { break }
        hasher.update(chunk)
    }
    return ReadBackResult(hash: hasher.finalizeHex(), cacheBypassRequested: bypass)
}
