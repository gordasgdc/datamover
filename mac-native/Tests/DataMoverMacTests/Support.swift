import Foundation
import XCTest
@testable import DataMoverMac

/// Sandbox de test: un folder unic sub `NSTemporaryDirectory()`, șters la
/// final. Niciun test nu atinge `/Volumes` sau fișiere ale utilizatorului.
final class Sandbox {
    let root: String

    init() {
        root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("dm-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(atPath: root) }

    @discardableResult
    func dir(_ rel: String) -> String {
        let p = (root as NSString).appendingPathComponent(rel)
        try! FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
        return p
    }

    @discardableResult
    func file(_ rel: String, bytes: Int, seed: UInt8 = 7) -> String {
        let p = (root as NSString).appendingPathComponent(rel)
        try! FileManager.default.createDirectory(atPath: (p as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        var data = Data(count: bytes)
        for i in 0..<bytes { data[i] = UInt8(truncatingIfNeeded: i &* 31 &+ Int(seed)) }
        FileManager.default.createFile(atPath: p, contents: data)
        return p
    }
}

/// Amprenta unei ierarhii (cale → mărime, mtime, hash) — folosită ca dovadă
/// că sursa NU a fost modificată de transfer.
func fingerprint(_ root: String) -> [String: String] {
    var out: [String: String] = [:]
    let fm = FileManager.default
    guard let e = fm.enumerator(atPath: root) else { return out }
    for case let rel as String in e {
        let full = (root as NSString).appendingPathComponent(rel)
        guard let a = try? fm.attributesOfItem(atPath: full) else { continue }
        let hash = (try? hashOfFile(path: full, model: .sha256, cancel: CancelToken())) ?? "dir"
        out[rel] = "\(a[.size] ?? 0)|\((a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)|\(hash)"
    }
    return out
}

func partialFiles(under root: String) -> [String] {
    guard let e = FileManager.default.enumerator(atPath: root) else { return [] }
    return e.compactMap { $0 as? String }.filter { PartialFile.isPartial(($0 as NSString).lastPathComponent) }
}

@MainActor
func runTransfer(_ runner: OffloadRunner, sources: [String], destinations: [String],
                 model: VerificationModel = .xxhash64, resume: Bool = true,
                 folder: String = "JOB", readBack: Bool = false,
                 timeout: TimeInterval = 30) async throws {
    OffloadRunner.sideEffectsEnabled = false
    runner.start(sources: sources, destinations: destinations, verificationModel: model,
                 resume: resume, folderNameOverride: folder, generateMHL: true,
                 retryFailedFiles: true, readBackVerification: readBack)
    let deadline = Date().addingTimeInterval(timeout)
    while runner.isRunning {
        if Date() > deadline { XCTFail("transfer timeout"); return }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    // Lasă Task-urile @MainActor programate de motor să se aplice.
    try await Task.sleep(nanoseconds: 50_000_000)
}
