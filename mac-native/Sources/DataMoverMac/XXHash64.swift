import Foundation

/// [2026-09-03] xxHash64 (XXH64, seed 0) — implementare pura Swift, fara
/// nicio dependinta externa.
///
/// DE CE: e algoritmul implicit al ofloaderelor profesionale (ShotPut Pro,
/// Silverstack, YoYotta) si singurul checksum non-criptografic acceptat de
/// formatul MHL (vezi MHLWriter.swift). E de ordinul a 5-10x mai rapid
/// decat MD5 pe acelasi fisier, pentru ca nu face runde criptografice —
/// pe un card de 512 GB diferenta e de zeci de minute de verificare.
/// Nu e potrivit pentru securitate (nu e criptografic), dar verificarea
/// unui offload NU e o problema de securitate, ci de detectare a
/// coruperii de date la copiere: acolo xxHash e la fel de bun ca MD5.
///
/// VALIDAT (2026-09-03) byte-for-byte fata de implementarea de referinta
/// (`python-xxhash`), pe 8 vectori de test (0, 1, 3, 31, 32, 33, 256 si
/// 1800 de octeti), fiecare hash-uit in bucati de 7 / 32 / 1M octeti —
/// toate cele 24 de combinatii au dat acelasi rezultat ca referinta.
/// Cazurile de 31/32/33 acopera exact granita stripe-ului de 32 de octeti,
/// unde o implementare gresita de streaming trece testul pe fisiere mici
/// si esueaza pe cele mari.
struct XXHash64 {
    private static let p1: UInt64 = 0x9E37_79B1_85EB_CA87
    private static let p2: UInt64 = 0xC2B2_AE3D_27D4_EB4F
    private static let p3: UInt64 = 0x1656_67B1_9E37_79F9
    private static let p4: UInt64 = 0x85EB_CA77_C2B2_AE63
    private static let p5: UInt64 = 0x27D4_EB2F_1656_67C5

    private let seed: UInt64
    private var v1: UInt64, v2: UInt64, v3: UInt64, v4: UInt64
    private var total: UInt64 = 0
    /// Tampon pentru resturile sub 32 de octeti dintre doua apeluri
    /// `update` — hash-ul se calculeaza pe stripe-uri de 32, iar bucatile
    /// citite de pe disc nu sunt niciodata garantat multipli de 32.
    private var buf = [UInt8](repeating: 0, count: 32)
    private var bufLen = 0

    init(seed: UInt64 = 0) {
        self.seed = seed
        v1 = seed &+ Self.p1 &+ Self.p2
        v2 = seed &+ Self.p2
        v3 = seed
        v4 = seed &- Self.p1
    }

    @inline(__always) private static func rotl(_ x: UInt64, _ r: UInt64) -> UInt64 {
        (x << r) | (x >> (64 - r))
    }
    @inline(__always) private static func round(_ acc: UInt64, _ input: UInt64) -> UInt64 {
        rotl(acc &+ (input &* p2), 31) &* p1
    }
    @inline(__always) private static func mergeRound(_ acc: UInt64, _ val: UInt64) -> UInt64 {
        ((acc ^ round(0, val)) &* p1) &+ p4
    }
    /// `loadUnaligned` e obligatoriu: bucata citita de pe disc nu are
    /// niciun aliniament garantat, iar `load(as:)` clasic ar da crash pe
    /// o adresa nealiniata.
    @inline(__always) private static func u64(_ p: UnsafeRawPointer, _ offset: Int) -> UInt64 {
        UInt64(littleEndian: p.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
    }
    @inline(__always) private static func u32(_ p: UnsafeRawPointer, _ offset: Int) -> UInt32 {
        UInt32(littleEndian: p.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
    }

    mutating func update(_ data: Data) {
        guard !data.isEmpty else { return }
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let base = raw.baseAddress else { return }
            let n = raw.count
            total &+= UInt64(n)
            var idx = 0
            if bufLen > 0 {
                if bufLen + n < 32 {
                    buf.withUnsafeMutableBytes { $0.baseAddress!.advanced(by: bufLen).copyMemory(from: base, byteCount: n) }
                    bufLen += n
                    return
                }
                let need = 32 - bufLen
                buf.withUnsafeMutableBytes { $0.baseAddress!.advanced(by: bufLen).copyMemory(from: base, byteCount: need) }
                buf.withUnsafeBytes { b in
                    let p = b.baseAddress!
                    v1 = Self.round(v1, Self.u64(p, 0))
                    v2 = Self.round(v2, Self.u64(p, 8))
                    v3 = Self.round(v3, Self.u64(p, 16))
                    v4 = Self.round(v4, Self.u64(p, 24))
                }
                idx = need
                bufLen = 0
            }
            while idx + 32 <= n {
                v1 = Self.round(v1, Self.u64(base, idx))
                v2 = Self.round(v2, Self.u64(base, idx + 8))
                v3 = Self.round(v3, Self.u64(base, idx + 16))
                v4 = Self.round(v4, Self.u64(base, idx + 24))
                idx += 32
            }
            if idx < n {
                let rest = n - idx
                buf.withUnsafeMutableBytes { $0.baseAddress!.copyMemory(from: base.advanced(by: idx), byteCount: rest) }
                bufLen = rest
            }
        }
    }

    func digest() -> UInt64 {
        var h: UInt64
        if total >= 32 {
            h = Self.rotl(v1, 1) &+ Self.rotl(v2, 7) &+ Self.rotl(v3, 12) &+ Self.rotl(v4, 18)
            h = Self.mergeRound(h, v1)
            h = Self.mergeRound(h, v2)
            h = Self.mergeRound(h, v3)
            h = Self.mergeRound(h, v4)
        } else {
            h = seed &+ Self.p5
        }
        h = h &+ total

        buf.withUnsafeBytes { b in
            let p = b.baseAddress!
            var i = 0
            while i + 8 <= bufLen {
                h ^= Self.round(0, Self.u64(p, i))
                h = (Self.rotl(h, 27) &* Self.p1) &+ Self.p4
                i += 8
            }
            if i + 4 <= bufLen {
                h ^= UInt64(Self.u32(p, i)) &* Self.p1
                h = (Self.rotl(h, 23) &* Self.p2) &+ Self.p3
                i += 4
            }
            while i < bufLen {
                h ^= UInt64(b[i]) &* Self.p5
                h = Self.rotl(h, 11) &* Self.p1
                i += 1
            }
        }

        h ^= h >> 33
        h = h &* Self.p2
        h ^= h >> 29
        h = h &* Self.p3
        h ^= h >> 32
        return h
    }

    /// Reprezentarea canonica (big-endian, ca numar) — identica cu ce
    /// scriu `xxhsum` si Silverstack in campul `<xxhash64be>` din MHL.
    var hexDigest: String { String(format: "%016llx", digest()) }
}
