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
    /// Fișierul e confirmat și MUTAT la numele final (rename atomic după
    /// flush). Singurul caz în care fișierul final există din această copiere.
    case success(hash: String, bytesWritten: Int64)
    /// Scris complet, dar neconfirmat (hash/mărime diferită, sursă modificată
    /// în timpul citirii). Fișierul parțial a fost șters; numele final NU a
    /// fost atins.
    case mismatch(hash: String, bytesWritten: Int64, reason: String)
    case failure(Error)
}

/// Erori cu mesaj pentru operator (ce s-a întâmplat, nu cod intern).
struct TransferIssueError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Ce s-a obținut efectiv la o destinație (pentru jurnal și rapoarte).
struct DestinationDurability: Equatable {
    var fileFlush: FlushLevel?
    var directoryFlush: FlushLevel?
    /// nil = recitirea nu a rulat; false = F_NOCACHE refuzat de volum.
    var readBackCacheBypass: Bool?
}

struct FanOutResult {
    /// Hash-ul sursei, calculat o singură dată, din bucățile citite.
    let sourceHash: String
    let bytesRead: Int64
    /// Cheie = calea destinației.
    let destinations: [String: FanOutDestOutcome]
    var durability: [String: DestinationDurability] = [:]
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


/// Operațiile de scriere, injectabile în teste (ex. o destinație care
/// eșuează la a N-a bucată).
struct FanOutIO {
    var write: (FileHandle, Data, String) throws -> Void
    var flush: FlushPrimitives

    static let system = FanOutIO(write: { h, d, _ in try h.write(contentsOf: d) }, flush: .system)
}

final class FanOutCopier {
    private let sourcePath: String
    private let destinationPaths: [String]
    private let chunkSize: Int
    private let ringDepth: Int
    private let model: VerificationModel
    private let cancel: CancelToken
    private let pause: PauseToken
    private let expectedSize: Int64?
    private let readBack: Bool
    private let io: FanOutIO

    init(sourcePath: String, destinationPaths: [String], chunkSize: Int,
         ringDepth: Int = 3, model: VerificationModel,
         cancel: CancelToken, pause: PauseToken,
         expectedSize: Int64? = nil, readBack: Bool = false, io: FanOutIO = .system) {
        self.sourcePath = sourcePath
        self.destinationPaths = destinationPaths
        self.chunkSize = chunkSize
        self.ringDepth = max(2, ringDepth)
        self.model = model
        self.cancel = cancel
        self.pause = pause
        self.expectedSize = expectedSize
        self.readBack = readBack
        self.io = io
    }

    private static func sourceStamp(_ path: String) -> (size: Int64, mtime: Date)? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: path),
              let size = a[.size] as? Int64, let m = a[.modificationDate] as? Date else { return nil }
        return (size, m)
    }

    /// Contract (vezi ARCHITECTURE.md):
    /// - sursa e doar citită, niciodată scrisă sau mutată;
    /// - fiecare destinație se scrie în `PartialFile.path(for:)`, primește
    ///   flush obligatoriu (`Durability.swift`), apoi e redenumită la numele
    ///   final DOAR dacă mărimea și checksum-ul coincid cu sursa, iar sursa
    ///   nu s-a schimbat în timpul citirii;
    /// - la orice eșec/anulare, parțialul se șterge; un fișier final
    ///   preexistent rămâne neatins;
    /// - o destinație care eșuează își golește coada (nu blochează cititorul)
    ///   și nu le afectează pe celelalte.
    func run(onBytesRead: @escaping (Int64) -> Void) throws -> FanOutResult {
        let stampBefore = Self.sourceStamp(sourcePath)
        guard let input = FileHandle(forReadingAtPath: sourcePath) else {
            throw FanOutError.cannotOpenSource(sourcePath)
        }
        defer { try? input.close() }

        var queues: [String: BoundedChunkQueue] = [:]
        for dst in destinationPaths {
            queues[dst] = BoundedChunkQueue(capacity: ringDepth)
        }

        var results: [String: FanOutDestOutcome] = [:]
        var durability: [String: DestinationDurability] = [:]
        let resultsLock = NSLock()
        let group = DispatchGroup()
        let fm = FileManager.default
        let io = self.io

        for dst in destinationPaths {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                defer { group.leave() }
                let queue = queues[dst]!
                let part = PartialFile.path(for: dst)
                do {
                    try? fm.removeItem(atPath: part)
                    guard fm.createFile(atPath: part, contents: nil),
                          let output = FileHandle(forWritingAtPath: part) else {
                        throw FanOutError.cannotOpenDestination(dst)
                    }
                    defer { try? output.close() }
                    var hasher = IncrementalHasher(model: model)
                    var written: Int64 = 0
                    while let chunk = queue.pop() {
                        try autoreleasepool {
                            try io.write(output, chunk, dst)
                        }
                        hasher.update(chunk)
                        written += Int64(chunk.count)
                    }
                    let level = try physicalFlush(output, using: io.flush)
                    resultsLock.lock()
                    results[dst] = .success(hash: hasher.finalizeHex(), bytesWritten: written)
                    durability[dst, default: DestinationDurability()].fileFlush = level
                    resultsLock.unlock()
                } catch {
                    resultsLock.lock()
                    results[dst] = .failure(error)
                    resultsLock.unlock()
                    queue.markConsumerFailed()
                }
            }
        }

        // Thread-ul de CITIRE — singurul care atinge sursa.
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

        if let readError {
            for dst in destinationPaths { try? fm.removeItem(atPath: PartialFile.path(for: dst)) }
            throw readError
        }

        let sourceHash = sourceHasher.finalizeHex()
        // Sursa s-a schimbat în timpul citirii (fișier încă în scriere, card
        // defect): nimic nu se confirmă, oricât de bine arată hash-urile.
        var sourceProblem: String?
        let stampAfter = Self.sourceStamp(sourcePath)
        if let expectedSize, bytesRead != expectedSize {
            sourceProblem = "Sursa are \(bytesRead) octeți citiți, dar \(expectedSize) la scanare — s-a modificat în timpul copierii."
        } else if let b = stampBefore, let a = stampAfter, (b.size != a.size || b.mtime != a.mtime) {
            sourceProblem = "Sursa s-a modificat în timpul copierii."
        }

        var final: [String: FanOutDestOutcome] = [:]
        for dst in destinationPaths {
            let part = PartialFile.path(for: dst)
            let outcome = results[dst] ?? .failure(TransferIssueError(message: "Fără rezultat de la motorul de copiere"))
            guard case .success(let hash, let written) = outcome else {
                try? fm.removeItem(atPath: part)
                final[dst] = outcome
                continue
            }
            var reason: String? = sourceProblem
            if reason == nil && written != bytesRead {
                reason = "Scriși \(written) din \(bytesRead) octeți."
            }
            if reason == nil && model != .sizeOnly && hash != sourceHash {
                reason = "Checksum diferit."
            }
            // Recitirea e o verificare SEPARATĂ, după checksum-ul din flux:
            // ambele trebuie să coincidă cu sursa.
            if reason == nil && readBack && model != .sizeOnly {
                do {
                    let rb = try readBackHash(path: part, model: model, chunkSize: chunkSize, cancel: cancel)
                    durability[dst, default: DestinationDurability()].readBackCacheBypass = rb.cacheBypassRequested
                    if rb.hash != sourceHash { reason = "Checksum diferit la recitire." }
                } catch is OffloadCancelled {
                    for d in destinationPaths { try? fm.removeItem(atPath: PartialFile.path(for: d)) }
                    throw OffloadCancelled()
                } catch {
                    reason = "Recitirea a eșuat: \(error.localizedDescription)"
                }
            }
            if let reason {
                try? fm.removeItem(atPath: part)
                final[dst] = .mismatch(hash: hash, bytesWritten: written, reason: reason)
                continue
            }
            // rename(2) înlocuiește atomic un fișier final preexistent.
            if Darwin.rename(part, dst) != 0 {
                let code = errno
                try? fm.removeItem(atPath: part)
                final[dst] = .failure(posixError(code, "Finalizarea (redenumirea) a eșuat"))
                continue
            }
            do {
                let level = try flushDirectory((dst as NSString).deletingLastPathComponent, using: io.flush)
                durability[dst, default: DestinationDurability()].directoryFlush = level
                final[dst] = .success(hash: hash, bytesWritten: written)
            } catch {
                // Conținutul e confirmat, dar persistența numelui nu: fișierul
                // rămâne la destinație, raportat NECONFIRMAT (reîncercarea îl
                // rescrie).
                final[dst] = .failure(TransferIssueError(message: "Fișier scris, dar persistența pe disc neconfirmată: \(error.localizedDescription)"))
            }
        }
        return FanOutResult(sourceHash: sourceHash, bytesRead: bytesRead, destinations: final, durability: durability)
    }
}
