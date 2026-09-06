import Foundation
import CryptoKit
import Darwin

/// [M1, 2026-09-06] Motor de copiere "citire unică, scriere multiplă" —
/// înlocuiește tiparul vechi (un `DestinationJob` separat per destinație,
/// fiecare citind sursa de la zero pentru copiere ȘI din nou pentru
/// verificare) cu UN SINGUR thread de citire din card, care distribuie
/// fiecare bucată către N thread-uri de scriere + calculează hash-ul
/// sursei O SINGURĂ DATĂ, din exact aceleași bucăți citite.
///
/// DE CE (găsit direct în cod, nu presupus): vechiul `processOne` apela
/// `copyFileCancelable` (1 citire completă a sursei) apoi `verifyPair`
/// (încă o citire COMPLETĂ a sursei pentru `srcHash`, plus o citire a
/// destinației pentru `dstHash`) — PER destinație. Cu 2 destinații, un
/// card se citea efectiv de 4 ori. Motorul de aici citește sursa O DATĂ,
/// indiferent de câte destinații există, și calculează hash-ul fiecărei
/// destinații ÎN TIMP CE SE SCRIE (nu printr-o recitire ulterioară de pe
/// disc) — elimină și cele N citiri ale destinațiilor.
///
/// ARHITECTURĂ: un `BoundedChunkQueue` per destinație (ring buffer marginit,
/// adâncime implicit 3 bucăți) — thread-ul de citire împinge aceeași
/// instanță `Data` (Copy-on-Write, niciun consumator n-o mutează, deci nu
/// se copiază efectiv de N ori în memorie) în toate cozile; câte un thread
/// de scriere per destinație consumă din propria coadă, scrie pe disc și
/// actualizează propriul hash incremental. Adâncimea marginită e
/// backpressure-ul cerut de Regula 21 („fără read-ahead nemărginit care ar
/// acumula date nescrise în RAM") — dacă o destinație e lentă (HDD extern),
/// coada ei se umple, thread-ul de citire se blochează la următorul
/// `push`, deci viteza reală de citire de pe card se aliniază la CEA MAI
/// LENTĂ destinație, exact comportamentul de siguranță cerut.
enum FanOutError: Error {
    case cannotOpenSource(String)
    case cannotOpenDestination(String)
}

/// Rezultatul per-destinație al unei copieri fan-out — fie succes cu
/// hash-ul calculat la scriere, fie eroarea specifică acelei destinații
/// (o destinație poate eșua — disc plin, deconectat — fără să oprească
/// scrierea către celelalte).
enum FanOutDestOutcome {
    case success(hash: String, bytesWritten: Int64)
    case failure(Error)
}

struct FanOutResult {
    /// Hash-ul sursei, calculat o singură dată, din bucățile citite.
    let sourceHash: String
    let bytesRead: Int64
    /// Cheie = calea destinației.
    let destinations: [String: FanOutDestOutcome]
}

/// Wrapper incremental unificat peste toate modelele de verificare —
/// extras din `genericHash`/`xxhash64OfFile` (OffloadEngine.swift) ca să
/// poată fi alimentat bucată-cu-bucată dintr-un flux extern, nu doar
/// dintr-o buclă proprie de citire a unui fișier de pe disc. Funcțiile
/// EXISTENTE rămân neschimbate — folosesc în continuare propriile bucle
/// (verificarea unui fișier deja existent la reluare, de exemplu, tot
/// citește fișierul o dată, nu are ce economisi).
enum IncrementalHasher {
    case xx(XXHash64)
    case md5(Insecure.MD5)
    case sha1(Insecure.SHA1)
    case sha256(SHA256)
    case sha512(SHA512)
    case sizeOnly(Int64)

    init(model: VerificationModel) {
        switch model {
        case .xxhash64: self = .xx(XXHash64())
        case .md5: self = .md5(Insecure.MD5())
        case .sha1: self = .sha1(Insecure.SHA1())
        case .sha256: self = .sha256(SHA256())
        case .sha512: self = .sha512(SHA512())
        case .sizeOnly: self = .sizeOnly(0)
        }
    }

    mutating func update(_ data: Data) {
        switch self {
        case .xx(var h): h.update(data); self = .xx(h)
        case .md5(var h): h.update(data: data); self = .md5(h)
        case .sha1(var h): h.update(data: data); self = .sha1(h)
        case .sha256(var h): h.update(data: data); self = .sha256(h)
        case .sha512(var h): h.update(data: data); self = .sha512(h)
        case .sizeOnly(let n): self = .sizeOnly(n + Int64(data.count))
        }
    }

    /// Gol pentru `.sizeOnly` — la fel ca modelul existent, unde
    /// "verificarea" e doar o comparație de mărime, nu un hash real.
    func finalizeHex() -> String {
        switch self {
        case .xx(let h): return h.hexDigest
        case .md5(let h): return h.finalize().map { String(format: "%02x", $0) }.joined()
        case .sha1(let h): return h.finalize().map { String(format: "%02x", $0) }.joined()
        case .sha256(let h): return h.finalize().map { String(format: "%02x", $0) }.joined()
        case .sha512(let h): return h.finalize().map { String(format: "%02x", $0) }.joined()
        case .sizeOnly: return ""
        }
    }
}

/// Coadă marginită, thread-safe, cu UN singur producător (thread-ul de
/// citire) și UN singur consumator (thread-ul de scriere al destinației
/// respective). `push` blochează dacă adâncimea `capacity` e deja atinsă
/// (backpressure real) — dacă un consumator eșuează, `markConsumerFailed()`
/// oprește orice blocare viitoare, ca thread-ul de citire să nu rămână
/// agățat de o destinație moartă.
final class BoundedChunkQueue {
    private var buffer: [Data] = []
    private let capacity: Int
    private let cond = NSCondition()
    private var finished = false
    private var consumerFailed = false

    init(capacity: Int) { self.capacity = capacity }

    func push(_ chunk: Data) {
        cond.lock()
        defer { cond.unlock() }
        if consumerFailed { return }
        while buffer.count >= capacity && !consumerFailed {
            cond.wait()
        }
        guard !consumerFailed else { return }
        buffer.append(chunk)
        cond.signal()
    }

    func finish() {
        cond.lock(); finished = true; cond.signal(); cond.unlock()
    }

    func markConsumerFailed() {
        cond.lock(); consumerFailed = true; cond.signal(); cond.unlock()
    }

    /// `nil` = EOF normal (sursa s-a terminat, coada s-a golit).
    func pop() -> Data? {
        cond.lock()
        defer { cond.unlock() }
        while buffer.isEmpty && !finished {
            cond.wait()
        }
        guard !buffer.isEmpty else { return nil }
        let chunk = buffer.removeFirst()
        cond.signal() // elibereaza un loc pentru un push care astepta
        return chunk
    }
}

/// [M2, 2026-09-06] Flush FIZIC pe disc — obligatoriu înainte de a marca
/// un fișier "OK". Motiv: apelurile standard de scriere (`FileHandle.write`)
/// scriu doar în cache-ul RAM al sistemului de operare, NU garantează că
/// datele au ajuns pe cipurile flash. Dacă userul scoate cardul/SSD-ul din
/// mufă imediat după ce bara de progres arată 100%, fișierele pot rămâne
/// corupte — exact scenariul pe care un ofloader profesional trebuie să-l
/// elimine matematic, nu doar statistic.
///
/// `fsync(2)` obișnuit NU e suficient pe macOS — documentat oficial de
/// Apple (`man fsync`): pe multe dispozitive de stocare, controllerul
/// hardware raportează scrierea ca „terminată" imediat ce a ajuns în
/// propriul cache electric, ÎNAINTE de a ajunge fizic pe celulele flash.
/// `F_FULLFSYNC` (specific Apple, via `fcntl`) e singurul apel care cere
/// explicit controllerului să golească ACEL cache și să confirme scrierea
/// fizică reală.
///
/// Degradare controlată: unele sisteme de fișiere (volume de rețea SMB/
/// NFS, unele formatări exFAT/FAT32 vechi) NU suportă `F_FULLFSYNC` —
/// întorc `ENOTSUP`. În acel caz, cade pe `fsync()` simplu (tot mai bine
/// decât nimic) — NU tratăm asta ca eroare de transfer. Orice ALTĂ eroare
/// (disc efectiv deconectat, defect) chiar trebuie să oprească fișierul
/// respectiv cu eroare — datele nu sunt confirmate pe disc.
func physicalFlush(_ handle: FileHandle) throws {
    if fcntl(handle.fileDescriptor, F_FULLFSYNC) == -1 {
        let code = errno
        if code == ENOTSUP {
            _ = fsync(handle.fileDescriptor) // fallback - vezi comentariul de mai sus
        } else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code),
                           userInfo: [NSLocalizedDescriptionKey: "Flush fizic eșuat: \(String(cString: strerror(code)))"])
        }
    }
}

final class FanOutCopier {
    private let sourcePath: String
    private let destinationPaths: [String]
    private let chunkSize: Int
    private let ringDepth: Int
    private let model: VerificationModel
    private let cancel: CancelToken
    private let pause: PauseToken

    init(sourcePath: String, destinationPaths: [String], chunkSize: Int,
         ringDepth: Int = 3, model: VerificationModel,
         cancel: CancelToken, pause: PauseToken) {
        self.sourcePath = sourcePath
        self.destinationPaths = destinationPaths
        self.chunkSize = chunkSize
        self.ringDepth = max(2, ringDepth)
        self.model = model
        self.cancel = cancel
        self.pause = pause
    }

    /// `onBytesRead` — apelat de pe thread-ul de citire, o dată per bucată
    /// citită din sursă (pentru progres live în UI, ca înainte).
    func run(onBytesRead: @escaping (Int64) -> Void) throws -> FanOutResult {
        guard let input = FileHandle(forReadingAtPath: sourcePath) else {
            throw FanOutError.cannotOpenSource(sourcePath)
        }
        defer { try? input.close() }

        var queues: [String: BoundedChunkQueue] = [:]
        for dst in destinationPaths {
            queues[dst] = BoundedChunkQueue(capacity: ringDepth)
        }

        var results: [String: FanOutDestOutcome] = [:]
        let resultsLock = NSLock()
        let group = DispatchGroup()

        for dst in destinationPaths {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                defer { group.leave() }
                let queue = queues[dst]!
                do {
                    FileManager.default.createFile(atPath: dst, contents: nil)
                    guard let output = FileHandle(forWritingAtPath: dst) else {
                        throw FanOutError.cannotOpenDestination(dst)
                    }
                    defer { try? output.close() }
                    var hasher = IncrementalHasher(model: model)
                    var written: Int64 = 0
                    while let chunk = queue.pop() {
                        try autoreleasepool {
                            try output.write(contentsOf: chunk)
                        }
                        hasher.update(chunk)
                        written += Int64(chunk.count)
                    }
                    // [M2] Flush fizic OBLIGATORIU inainte de a marca fisierul
                    // OK - vezi comentariul din physicalFlush(). O eroare reala
                    // aici (nu ENOTSUP) opreste DOAR aceasta destinatie.
                    try physicalFlush(output)
                    resultsLock.lock()
                    results[dst] = .success(hash: hasher.finalizeHex(), bytesWritten: written)
                    resultsLock.unlock()
                } catch {
                    resultsLock.lock()
                    results[dst] = .failure(error)
                    resultsLock.unlock()
                    queue.markConsumerFailed()
                }
            }
        }

        // Thread-ul de CITIRE — singurul care atinge sursa. Rulează pe
        // thread-ul curent (cel care a apelat `run`), care e deja de
        // fundal in OffloadRunner — nu mai are nevoie de propriul lui
        // DispatchQueue.
        var sourceHasher = IncrementalHasher(model: model)
        var bytesRead: Int64 = 0
        var readError: Error?
        do {
            while true {
                if cancel.isCancelled { throw OffloadCancelled() }
                pause.waitWhilePaused(cancel: cancel)
                if cancel.isCancelled { throw OffloadCancelled() }

                var chunk: Data?
                try autoreleasepool {
                    chunk = try input.read(upToCount: chunkSize)
                }
                guard let chunk, !chunk.isEmpty else { break }

                sourceHasher.update(chunk)
                bytesRead += Int64(chunk.count)
                onBytesRead(Int64(chunk.count))

                for queue in queues.values {
                    queue.push(chunk)
                }
            }
        } catch {
            readError = error
        }
        for queue in queues.values { queue.finish() }

        group.wait()

        if let readError { throw readError }
        return FanOutResult(sourceHash: sourceHasher.finalizeHex(), bytesRead: bytesRead, destinations: results)
    }
}
