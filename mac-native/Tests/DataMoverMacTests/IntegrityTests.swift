import XCTest
@testable import DataMoverMac

final class FanOutCopierTests: XCTestCase {
    func copier(_ src: String, _ dsts: [String], model: VerificationModel = .xxhash64,
                cancel: CancelToken = CancelToken(), expected: Int64? = nil, readBack: Bool = false) -> FanOutCopier {
        FanOutCopier(sourcePath: src, destinationPaths: dsts, chunkSize: 64 * 1024, model: model,
                     cancel: cancel, pause: PauseToken(), expectedSize: expected, readBack: readBack)
    }

    func testSimpleCopyIsConfirmedAndRenamed() throws {
        let sb = Sandbox()
        let src = sb.file("src/a.bin", bytes: 300_000)
        let dst = (sb.dir("d1") as NSString).appendingPathComponent("a.bin")
        let r = try copier(src, [dst], expected: 300_000).run { _ in }
        guard case .success(let hash, let n) = r.destinations[dst] else { return XCTFail("\(String(describing: r.destinations[dst]))") }
        XCTAssertEqual(hash, r.sourceHash)
        XCTAssertEqual(n, 300_000)
        XCTAssertEqual(try hashOfFile(path: dst, model: .sha256, cancel: CancelToken()),
                       try hashOfFile(path: src, model: .sha256, cancel: CancelToken()))
        XCTAssertTrue(partialFiles(under: sb.root).isEmpty)
    }

    func testReadBackVerification() throws {
        let sb = Sandbox()
        let src = sb.file("src/a.bin", bytes: 200_000)
        let dst = (sb.dir("d1") as NSString).appendingPathComponent("a.bin")
        let r = try copier(src, [dst], expected: 200_000, readBack: true).run { _ in }
        guard case .success = r.destinations[dst] else { return XCTFail() }
    }

    func testZeroByteFile() throws {
        let sb = Sandbox()
        let src = sb.file("src/empty.wav", bytes: 0)
        let dst = (sb.dir("d1") as NSString).appendingPathComponent("empty.wav")
        let r = try copier(src, [dst], expected: 0).run { _ in }
        guard case .success(_, let n) = r.destinations[dst] else { return XCTFail() }
        XCTAssertEqual(n, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dst))
    }

    /// Sursa „s-a schimbat” (mărimea scanată ≠ octeți citiți): nimic nu se
    /// confirmă, parțialul dispare, numele final nu apare.
    func testSourceChangeIsMismatchAndPartialNeverPromoted() throws {
        let sb = Sandbox()
        let src = sb.file("src/a.bin", bytes: 1000)
        let dst = (sb.dir("d1") as NSString).appendingPathComponent("a.bin")
        let r = try copier(src, [dst], expected: 999).run { _ in }
        guard case .mismatch = r.destinations[dst] else { return XCTFail("\(String(describing: r.destinations[dst]))") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst))
        XCTAssertTrue(partialFiles(under: sb.root).isEmpty)
    }

    /// La nepotrivire, un fișier final preexistent rămâne neatins.
    func testExistingFinalFilePreservedOnMismatch() throws {
        let sb = Sandbox()
        let src = sb.file("src/a.bin", bytes: 1000, seed: 1)
        let dst = sb.file("d1/a.bin", bytes: 500, seed: 9)
        let before = try hashOfFile(path: dst, model: .sha256, cancel: CancelToken())
        _ = try copier(src, [dst], expected: 1234).run { _ in }
        XCTAssertEqual(try hashOfFile(path: dst, model: .sha256, cancel: CancelToken()), before)
    }

    /// `.sizeOnly` nu mai confirmă automat („" == ""): verifică mărimea.
    func testSizeOnlyStillChecksBytes() throws {
        let sb = Sandbox()
        let src = sb.file("src/a.bin", bytes: 4096)
        let dst = (sb.dir("d1") as NSString).appendingPathComponent("a.bin")
        let ok = try copier(src, [dst], model: .sizeOnly, expected: 4096).run { _ in }
        guard case .success = ok.destinations[dst] else { return XCTFail() }
        let dst2 = (sb.dir("d2") as NSString).appendingPathComponent("a.bin")
        let bad = try copier(src, [dst2], model: .sizeOnly, expected: 10).run { _ in }
        guard case .mismatch = bad.destinations[dst2] else { return XCTFail() }
    }

    /// Destinații independente: una imposibil de scris (folder dispărut),
    /// cealaltă reușește.
    func testMultipleDestinationsAreIndependent() throws {
        let sb = Sandbox()
        let src = sb.file("src/a.bin", bytes: 150_000)
        let good = (sb.dir("d1") as NSString).appendingPathComponent("a.bin")
        let gone = (sb.root as NSString).appendingPathComponent("missing-volume/a.bin")
        let r = try copier(src, [good, gone], expected: 150_000).run { _ in }
        guard case .success = r.destinations[good] else { return XCTFail() }
        guard case .failure = r.destinations[gone] else { return XCTFail() }
        XCTAssertFalse(FileManager.default.fileExists(atPath: gone))
    }

    /// Eșec de scriere simulat (folder doar-citire), fără a atinge volume.
    /// NU e un disc plin real — acela nu e simulat aici.
    func testWriteFailureOnReadOnlyDestination() throws {
        let sb = Sandbox()
        let src = sb.file("src/a.bin", bytes: 1000)
        let ro = sb.dir("ro")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: ro)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ro) }
        let dst = (ro as NSString).appendingPathComponent("a.bin")
        let r = try copier(src, [dst], expected: 1000).run { _ in }
        guard case .failure = r.destinations[dst] else { return XCTFail() }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst))
    }

    func testCancelLeavesNoPartialAndNoFinal() throws {
        let sb = Sandbox()
        let src = sb.file("src/a.bin", bytes: 500_000)
        let dst = (sb.dir("d1") as NSString).appendingPathComponent("a.bin")
        let token = CancelToken(); token.cancel()
        XCTAssertThrowsError(try copier(src, [dst], cancel: token, expected: 500_000).run { _ in })
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst))
        XCTAssertTrue(partialFiles(under: sb.root).isEmpty)
    }
}

final class CheckpointTests: XCTestCase {
    func testCorruptCheckpointIsRejected() {
        let sb = Sandbox()
        let root = sb.dir("dest/JOB")
        FileManager.default.createFile(atPath: CheckpointStore.path(targetRoot: root), contents: Data("{nu e json".utf8))
        XCTAssertEqual(CheckpointStore.loadValidated(targetRoot: root, folderName: "JOB", verificationModel: "xxhash64"),
                       .rejected("fișier corupt"))
    }

    func testCheckpointWithOtherModelOrFolderIsRejected() {
        let sb = Sandbox()
        let root = sb.dir("dest/JOB")
        CheckpointStore.save(targetRoot: root, source: "/x", folderName: "JOB", verificationModel: "md5",
                             files: ["a": "ok"], completed: false, totalFiles: 1)
        if case .rejected = CheckpointStore.loadValidated(targetRoot: root, folderName: "JOB", verificationModel: "xxhash64") {} else { XCTFail() }
        if case .rejected = CheckpointStore.loadValidated(targetRoot: root, folderName: "OTHER", verificationModel: "md5") {} else { XCTFail() }
        XCTAssertEqual(CheckpointStore.loadValidated(targetRoot: root, folderName: "JOB", verificationModel: "md5"), .valid(["a": "ok"]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: CheckpointStore.path(targetRoot: root) + ".tmp"))
    }
}

final class DestinationContextTests: XCTestCase {
    func makeContext(_ sb: Sandbox, dest: String) -> DestinationContext {
        DestinationContext(destRoot: dest, folderName: "JOB", verificationModel: .xxhash64, generateMHL: false,
                           meta: ProductionMeta(), sourceRoot: nil, cloudUploadQueue: nil, startedAt: Date(),
                           onActivity: { _ in }, onPermissionError: { _ in })
    }

    /// Reîncercare reușită: eroarea inițială devine recuperare, verdict
    /// „verificat cu avertismente”, niciodată „verificat” curat.
    func testRetryIsRecordedAsWarning() {
        let sb = Sandbox()
        let ctx = makeContext(sb, dest: sb.dir("d"))
        ctx.prepare(resume: false)
        let e = FileEntry(fullPath: "/x/a", relPath: "a", size: 10)
        ctx.recordCopyOutcome(entry: e, sourceHash: "h", outcome: .failure(TransferIssueError(message: "io")), isRetry: false)
        XCTAssertEqual(ctx.failCount, 1)
        ctx.recordCopyOutcome(entry: e, sourceHash: "h", outcome: .success(hash: "h", bytesWritten: 10), isRetry: true)
        XCTAssertEqual(ctx.failCount, 0)
        XCTAssertEqual(ctx.recoveredCount, 1)
        XCTAssertEqual(DestinationOutcome.evaluate(failCount: ctx.failCount, recoveredCount: ctx.recoveredCount, cancelled: false),
                       .verifiedWithWarnings)
    }

    func testVanishedDestinationIsUnavailableAndNotRecreated() {
        let sb = Sandbox()
        let dest = sb.dir("vol")
        let ctx = makeContext(sb, dest: dest)
        try? FileManager.default.removeItem(atPath: dest)
        XCTAssertFalse(ctx.isAvailable)
        ctx.prepare(resume: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest))
    }
}

final class OutcomeTests: XCTestCase {
    func testMixedResultIsPartialFailureAndBlocksEject() {
        let o = TransferOutcome.evaluate([.verified, .failed])
        XCTAssertEqual(o, .partialFailure)
        XCTAssertFalse(o.allowsSourceEject)
        XCTAssertEqual(TransferOutcome.evaluate([.failed, .failed]), .failure)
        XCTAssertEqual(TransferOutcome.evaluate([.verified, .verifiedWithWarnings]), .successWithWarnings)
        XCTAssertEqual(TransferOutcome.evaluate([.verified, .cancelled]), .cancelled)
        XCTAssertFalse(TransferOutcome.cancelled.allowsSourceEject)
        XCTAssertTrue(TransferOutcome.success.allowsSourceEject)
        XCTAssertEqual(TransferOutcome.evaluate([]), .failure)
    }
}
