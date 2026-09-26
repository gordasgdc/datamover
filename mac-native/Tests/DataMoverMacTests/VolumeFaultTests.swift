import XCTest
@testable import DataMoverMac

/// Volume reale, dar temporare: imagini de disc create și șterse de
/// `scripts/volume-fault-tests.sh`. Fără variabilele de mediu, testele se sar.
/// DM_SMALL_VOL = volum APFS de ~20 MB (disc plin); DM_EXFAT_VOL = volum exFAT.
@MainActor
final class VolumeFaultTests: XCTestCase {
    func sha(_ p: String) throws -> String { try hashOfFile(path: p, model: .sha256, cancel: CancelToken()) }
    func env(_ k: String) throws -> String {
        guard let v = ProcessInfo.processInfo.environment[k], FileManager.default.fileExists(atPath: v) else {
            throw XCTSkip("\(k) nesetat — rulează scripts/volume-fault-tests.sh")
        }
        return v
    }

    /// Spațiu insuficient cunoscut dinainte: pornirea e oprită, nimic scris.
    func testSpaceShortfallBlocksStartBeforeAnyWrite() throws {
        let small = try env("DM_SMALL_VOL")
        let sb = Sandbox()
        for i in 0..<4 { sb.file("CARD/c\(i).mov", bytes: 8 << 20, seed: UInt8(i)) }
        let dest = small + "/shortfall-\(UUID().uuidString.prefix(6))"
        try FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dest) }
        OffloadRunner.sideEffectsEnabled = false
        let runner = OffloadRunner()
        runner.start(sources: [sb.root + "/CARD"], destinations: [dest], folderNameOverride: "JOB")
        XCTAssertFalse(runner.isRunning)
        XCTAssertNotNil(runner.spaceShortfall)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest + "/JOB"))
    }

    /// Disc plin în timpul copierii (utilizatorul a ales să continue): ce nu
    /// încape nu e confirmat, nu rămân .dmpart, cealaltă copie e verificată.
    func testDiskFullMidTransferIsNeverConfirmed() async throws {
        let small = try env("DM_SMALL_VOL")
        let sb = Sandbox()
        for i in 0..<4 { sb.file("CARD/c\(i).mov", bytes: 8 << 20, seed: UInt8(i)) }
        let full = small + "/full-\(UUID().uuidString.prefix(6))"
        try FileManager.default.createDirectory(atPath: full, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: full) }
        let other = sb.dir("OTHER")
        OffloadRunner.sideEffectsEnabled = false
        let runner = OffloadRunner()
        runner.start(sources: [sb.root + "/CARD"], destinations: [full, other], folderNameOverride: "JOB",
                     retryFailedFiles: true, ignoreSpaceWarning: true)
        let deadline = Date().addingTimeInterval(120)
        while runner.isRunning { if Date() > deadline { XCTFail("timeout"); return }; try await Task.sleep(nanoseconds: 50_000_000) }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(runner.lastOutcome, .partialFailure)
        XCTAssertFalse(runner.lastOutcome!.allowsSourceEject)
        func result(_ p: String) -> DestinationResult? { runner.lastResults.first { $0.destRoot.hasSuffix((p as NSString).lastPathComponent) } }
        XCTAssertEqual(result(other)?.failCount, 0)
        XCTAssertGreaterThan(result(full)?.failCount ?? 0, 0)
        XCTAssertTrue(partialFiles(under: full).isEmpty, "\(partialFiles(under: full))")
        // Orice fișier final rămas pe discul plin e identic cu sursa.
        for i in 0..<4 where FileManager.default.fileExists(atPath: full + "/JOB/c\(i).mov") {
            XCTAssertEqual(try sha(full + "/JOB/c\(i).mov"), try sha(sb.root + "/CARD/c\(i).mov"))
        }
    }

    /// exFAT (sistemul tipic al cardurilor): nume Unicode, fișier gol,
    /// reluare fără recopiere a ce e deja confirmat.
    func testExFATTransferAndResume() async throws {
        let ex = try env("DM_EXFAT_VOL")
        let sb = Sandbox()
        let names = ["Clip ș ț ă î â.mov", "日本語.mxf", "empty.wav", "Sub/Ünï.mov"]
        for (i, n) in names.enumerated() { sb.file("CARD/" + n, bytes: n == "empty.wav" ? 0 : 200_000 + i, seed: UInt8(i)) }
        let dest = ex + "/ex-\(UUID().uuidString.prefix(6))"
        try FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dest) }
        // Regresie: pe exFAT, „important usage” e 0; spațiul liber trebuie să fie real.
        XCTAssertGreaterThan(OffloadRunner.freeBytes(at: dest) ?? 0, 100_000_000)
        XCTAssertGreaterThan(VolumeCapacity.of(dest)?.free ?? 0, 100_000_000)
        let runner = OffloadRunner()
        try await runTransfer(runner, sources: [sb.root + "/CARD"], destinations: [dest], timeout: 60)
        XCTAssertEqual(runner.lastOutcome, .success, "preflight: \(runner.preflightIssues.map(\.code)) · spațiu: \(String(describing: runner.spaceShortfall)) · coliziuni")
        guard runner.lastOutcome != nil else { return }
        for n in names { XCTAssertEqual(try sha(dest + "/JOB/" + n), try sha(sb.root + "/CARD/" + n), n) }
        try await runTransfer(runner, sources: [sb.root + "/CARD"], destinations: [dest], resume: true, timeout: 60)
        XCTAssertEqual(runner.lastOutcome, .success)
        XCTAssertEqual(runner.lastResults.first.map { $0.okCount + $0.skipCount }, names.count)
    }
}
