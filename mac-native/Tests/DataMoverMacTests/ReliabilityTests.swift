import XCTest
@testable import DataMoverMac

/// Matricea de fiabilitate: fault injection sigură, doar în directoare
/// temporare. Fiecare test numește ce simulează și ce NU simulează.
@MainActor
final class ReliabilityTests: XCTestCase {
    func sha(_ p: String) throws -> String { try hashOfFile(path: p, model: .sha256, cancel: CancelToken()) }

    // MARK: Coliziuni

    func testSourceNameCollisionIsBlockedBeforeAnyWrite() async throws {
        let sb = Sandbox()
        sb.file("CARD1/CLIP/A001.mov", bytes: 1000, seed: 1)
        sb.file("CARD2/CLIP/A001.mov", bytes: 1000, seed: 2)
        let d = sb.dir("DEST")
        let runner = OffloadRunner()
        OffloadRunner.sideEffectsEnabled = false
        runner.start(sources: [sb.root + "/CARD1", sb.root + "/CARD2"], destinations: [d], folderNameOverride: "JOB")
        XCTAssertFalse(runner.isRunning)
        XCTAssertTrue(runner.preflightIssues.contains { $0.code == .sourceNameCollision })
        XCTAssertFalse(FileManager.default.fileExists(atPath: d + "/JOB"), "nimic scris")
    }

    func testCollisionIsCaseAndNormalizationInsensitive() {
        let a = FileEntry(fullPath: "/s1/a.mov", relPath: "Clip/A.MOV", size: 1)
        let b = FileEntry(fullPath: "/s2/a.mov", relPath: "clip/a.mov", size: 1)
        let nfd = FileEntry(fullPath: "/s3/x", relPath: "s\u{0326}.mov", size: 1)   // ș descompus
        let nfc = FileEntry(fullPath: "/s4/x", relPath: "\u{0219}.mov", size: 1)    // ș precompus
        XCTAssertEqual(Preflight.nameCollisions([a, b]).count, 1)
        XCTAssertEqual(Preflight.nameCollisions([nfd, nfc]).count, 1)
        XCTAssertTrue(Preflight.nameCollisions([a]).isEmpty)
    }

    // MARK: Anulare și oprire bruscă

    /// Anulare în MIJLOCUL unui fișier (după prima bucată): nici final, nici parțial.
    func testCancelMidFileLeavesNeitherFinalNorPartial() throws {
        let sb = Sandbox()
        let src = sb.file("src/big.bin", bytes: 64 * 4096)
        let dsts = [sb.dir("a") + "/big.bin", sb.dir("b") + "/big.bin"]
        let token = CancelToken()
        let copier = FanOutCopier(sourcePath: src, destinationPaths: dsts, chunkSize: 4096, model: .xxhash64,
                                  cancel: token, pause: PauseToken(), expectedSize: 64 * 4096)
        XCTAssertThrowsError(try copier.run { _ in token.cancel() })
        for d in dsts { XCTAssertFalse(FileManager.default.fileExists(atPath: d)) }
        XCTAssertTrue(partialFiles(under: sb.root).isEmpty)
    }

    /// Simulare de crash: parțial rămas lângă un fișier neconfirmat + parțial
    /// „orfan” lângă unul confirmat. Reluarea curăță tot și confirmă prin citire.
    /// (Nu simulează o oprire reală a procesului în timpul scrierii.)
    func testResumeAfterSimulatedCrashCleansPartialsAndVerifies() async throws {
        let sb = Sandbox()
        sb.file("CARD/CLIP/A001.mov", bytes: 90_000, seed: 3)
        sb.file("CARD/CLIP/A002.mov", bytes: 70_000, seed: 4)
        let src = sb.root + "/CARD", d = sb.dir("A")
        let runner = OffloadRunner()
        try await runTransfer(runner, sources: [src], destinations: [d])
        let job = d + "/JOB/CLIP"
        try FileManager.default.removeItem(atPath: job + "/A002.mov")
        FileManager.default.createFile(atPath: job + "/.A002.mov.dmpart", contents: Data(repeating: 1, count: 1234))
        FileManager.default.createFile(atPath: job + "/.A001.mov.dmpart", contents: Data(repeating: 2, count: 99))
        try await runTransfer(runner, sources: [src], destinations: [d], resume: true)
        XCTAssertEqual(runner.lastOutcome, .success)
        XCTAssertTrue(partialFiles(under: d).isEmpty, "\(partialFiles(under: d))")
        XCTAssertEqual(try sha(job + "/A002.mov"), try sha(src + "/CLIP/A002.mov"))
    }

    // MARK: Nume și volum

    func testUnicodeAndLongPathNames() async throws {
        let sb = Sandbox()
        let deep = (0..<6).map { "Nivel_\($0)_ăâîșț_日本語_" + String(repeating: "x", count: 18) }.joined(separator: "/")
        let names = ["Clip ș ț ă î â — ✓.mov", "日本語 テスト.mxf", "Ünïcödé Ωmega.wav", deep + "/lung.mov"]
        for (i, n) in names.enumerated() { sb.file("CARD/" + n, bytes: 5_000 + i * 700, seed: UInt8(i)) }
        let src = sb.root + "/CARD", d = sb.dir("A")
        let runner = OffloadRunner()
        try await runTransfer(runner, sources: [src], destinations: [d])
        XCTAssertEqual(runner.lastOutcome, .success)
        XCTAssertEqual(runner.lastResults[0].okCount, names.count)
        for n in names { XCTAssertEqual(try sha(d + "/JOB/" + n), try sha(src + "/" + n), n) }
    }

    func testManySmallFilesAndEmptyFiles() async throws {
        let sb = Sandbox()
        for i in 0..<400 { sb.file("CARD/f/\(i).dat", bytes: i % 7 == 0 ? 0 : 500 + i, seed: UInt8(i % 250)) }
        let runner = OffloadRunner()
        try await runTransfer(runner, sources: [sb.root + "/CARD"], destinations: [sb.dir("A"), sb.dir("B")], timeout: 120)
        XCTAssertEqual(runner.lastOutcome, .success)
        XCTAssertEqual(runner.lastResults.map(\.okCount), [400, 400])
    }

    // MARK: Erori parțiale

    /// Fișier sursă fără drept de citire („blocat”): neconfirmat la ambele
    /// destinații, restul confirmat; verdict nu poate fi „succes”.
    func testUnreadableSourceFileIsNeverConfirmed() async throws {
        let sb = Sandbox()
        sb.file("CARD/ok.mov", bytes: 20_000, seed: 1)
        let locked = sb.file("CARD/locked.mov", bytes: 20_000, seed: 2)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked) }
        let runner = OffloadRunner()
        try await runTransfer(runner, sources: [sb.root + "/CARD"], destinations: [sb.dir("A"), sb.dir("B")])
        XCTAssertEqual(runner.lastOutcome, .failure)
        XCTAssertEqual(runner.lastResults.map(\.okCount), [1, 1])
        XCTAssertFalse(FileManager.default.fileExists(atPath: sb.root + "/A/JOB/locked.mov"))
    }

    /// Acces refuzat la o singură destinație: cealaltă e verificată, verdict
    /// „eșec parțial”, ejectarea nu e permisă.
    func testReadOnlyDestinationGivesPartialFailure() async throws {
        let sb = Sandbox()
        sb.file("CARD/a.mov", bytes: 30_000)
        let a = sb.dir("A"), b = sb.dir("B")
        sb.dir("B/JOB")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: b + "/JOB")
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: b + "/JOB") }
        let runner = OffloadRunner()
        try await runTransfer(runner, sources: [sb.root + "/CARD"], destinations: [a, b])
        XCTAssertEqual(runner.lastOutcome, .partialFailure)
        XCTAssertFalse(runner.lastOutcome!.allowsSourceEject)
        XCTAssertEqual(Set(runner.lastResults.map(\.outcome)), [.verified, .failed])
    }

    // MARK: Symlink-uri

    /// Un folder-symlink deja existent la destinație nu poate trimite scrierea în afara țintei.
    func testSymlinkedDestinationFolderCannotEscapeTarget() async throws {
        let sb = Sandbox()
        sb.file("CARD/CLIP/a.mov", bytes: 10_000)
        let d = sb.dir("A"), outside = sb.dir("OUTSIDE")
        sb.dir("A/JOB")
        try FileManager.default.createSymbolicLink(atPath: d + "/JOB/CLIP", withDestinationPath: outside)
        let runner = OffloadRunner()
        try await runTransfer(runner, sources: [sb.root + "/CARD"], destinations: [d])
        XCTAssertEqual(runner.lastOutcome, .failure)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside).isEmpty, "nimic scris în afara țintei")
    }

    /// Symlink către fișier în sursă: se copiază conținutul țintei (documentat),
    /// cu mărimea țintei — nu se raportează nepotrivire falsă.
    func testSymlinkedSourceFileCopiesTargetContent() async throws {
        let sb = Sandbox()
        let real = sb.file("REAL/clip.mov", bytes: 12_345, seed: 9)
        sb.dir("CARD")
        try FileManager.default.createSymbolicLink(atPath: sb.root + "/CARD/clip.mov", withDestinationPath: real)
        let runner = OffloadRunner()
        try await runTransfer(runner, sources: [sb.root + "/CARD"], destinations: [sb.dir("A")])
        XCTAssertEqual(runner.lastOutcome, .success)
        XCTAssertEqual(try sha(sb.root + "/A/JOB/clip.mov"), try sha(real))
    }
}
