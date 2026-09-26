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
    let identity = SourceIdentity(roots: ["/src"], volumes: ["V"], manifestDigest: "abc", fileCount: 1)

    func load(_ root: String, folder: String = "JOB", model: String = "xxhash64", identity: SourceIdentity? = nil) -> CheckpointStore.LoadResult {
        CheckpointStore.loadValidated(targetRoot: root, folderName: folder, verificationModel: model, identity: identity ?? self.identity)
    }

    func testCorruptCheckpointIsRejected() {
        let sb = Sandbox()
        let root = sb.dir("dest/JOB")
        FileManager.default.createFile(atPath: CheckpointStore.path(targetRoot: root), contents: Data("{nu e json".utf8))
        XCTAssertEqual(load(root), .rejected("fișier corupt"))
    }

    /// Checkpoint vechi (schema 1, fără identitate) → respins conservator.
    func testLegacyCheckpointWithoutIdentityIsRejected() {
        let sb = Sandbox()
        let root = sb.dir("dest/JOB")
        let legacy = #"{"source":"/src","folder_name":"JOB","verification_model":"xxhash64","completed":false,"files":{"a":"ok"}}"#
        FileManager.default.createFile(atPath: CheckpointStore.path(targetRoot: root), contents: Data(legacy.utf8))
        guard case .rejected(let why) = load(root) else { return XCTFail() }
        XCTAssertTrue(why.contains("format vechi"))
    }

    func testCheckpointMustMatchModelFolderAndIdentity() {
        let sb = Sandbox()
        let root = sb.dir("dest/JOB")
        let proof = FileProof(source: "0123456789abcdef0123456789abcdef", destination: "0123456789abcdef0123456789abcdef", verdict: "checksum")
        XCTAssertNil(CheckpointStore.save(targetRoot: root, folderName: "JOB", verificationModel: "md5", identity: identity,
                                          files: ["a": "ok"], stamps: ["a": "1:2"], proofs: ["a": proof], completed: false))
        if case .rejected = load(root, model: "xxhash64") {} else { XCTFail("model") }
        if case .rejected = load(root, folder: "OTHER", model: "md5") {} else { XCTFail("folder") }
        let other = SourceIdentity(roots: ["/src"], volumes: ["V"], manifestDigest: "zzz", fileCount: 1)
        if case .rejected = load(root, model: "md5", identity: other) {} else { XCTFail("identity") }
        XCTAssertEqual(load(root, model: "md5"), .valid(.init(files: ["a": "ok"], stamps: ["a": "1:2"], proofs: ["a": proof])))
        XCTAssertFalse(FileManager.default.fileExists(atPath: CheckpointStore.path(targetRoot: root) + ".tmp"))
    }

    func testUnknownStateIsRejected() {
        let sb = Sandbox()
        let root = sb.dir("dest/JOB")
        CheckpointStore.save(targetRoot: root, folderName: "JOB", verificationModel: "xxhash64", identity: identity,
                             files: ["a": "maybe"], stamps: [:], proofs: [:], completed: false)
        guard case .rejected = load(root) else { return XCTFail() }
    }

    /// Identitatea depinde de conținutul listat (mărime + mtime), de cale și
    /// de volum — nu doar de nume.
    func testIdentityDistinguishesSameNamesAndSizes() throws {
        let sb = Sandbox()
        let a = sb.file("A/CLIP/x.mov", bytes: 100, seed: 1)
        let b = sb.file("B/CLIP/x.mov", bytes: 100, seed: 2)
        let rootA = (sb.root as NSString).appendingPathComponent("A")
        let rootB = (sb.root as NSString).appendingPathComponent("B")
        let fa = listAllFiles(root: rootA), fb = listAllFiles(root: rootB)
        XCTAssertNotEqual(SourceIdentity.compute(sources: [rootA], files: fa), SourceIdentity.compute(sources: [rootB], files: fb))
        // Aceeași cale, conținut înlocuit (mtime diferit) → identitate diferită.
        let before = SourceIdentity.compute(sources: [rootA], files: fa)
        try FileManager.default.removeItem(atPath: a)
        FileManager.default.createFile(atPath: a, contents: try Data(contentsOf: URL(fileURLWithPath: b)))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(100)], ofItemAtPath: a)
        XCTAssertNotEqual(before, SourceIdentity.compute(sources: [rootA], files: listAllFiles(root: rootA)))
        // Aceeași sursă, neatinsă → identitate identică (reluarea legitimă merge).
        let again = SourceIdentity.compute(sources: [rootA], files: listAllFiles(root: rootA))
        XCTAssertEqual(again, SourceIdentity.compute(sources: [rootA], files: listAllFiles(root: rootA)))
    }
}

final class ProofSchemaTests: XCTestCase {
    let identity = SourceIdentity(roots: ["/src"], volumes: ["V"], manifestDigest: "abc", fileCount: 1)
    let good = "0123456789abcdef0123456789abcdef"

    func write(_ root: String, _ json: String) {
        FileManager.default.createFile(atPath: CheckpointStore.path(targetRoot: root), contents: Data(json.utf8))
    }
    func load(_ root: String, model: String = "md5") -> CheckpointStore.LoadResult {
        CheckpointStore.loadValidated(targetRoot: root, folderName: "JOB", verificationModel: model, identity: identity)
    }
    func identityJSON() -> String {
        String(data: try! JSONEncoder().encode(identity), encoding: .utf8)!
    }

    /// Schema 2 (identitate + amprente, fără checksum) → respinsă.
    func testSchema2IsRejected() {
        let sb = Sandbox(); let root = sb.dir("d/JOB")
        write(root, #"{"schema":2,"folder_name":"JOB","verification_model":"md5","completed":false,"files":{"a":"ok"},"file_stamps":{"a":"1:2"},"source_identity":"# + identityJSON() + "}")
        guard case .rejected(let why) = load(root) else { return XCTFail() }
        XCTAssertTrue(why.contains("format vechi"))
    }

    func testMissingProofIsRejected() {
        let sb = Sandbox(); let root = sb.dir("d/JOB")
        CheckpointStore.save(targetRoot: root, folderName: "JOB", verificationModel: "md5", identity: identity,
                             files: ["a": "ok"], stamps: ["a": "1:2"], proofs: [:], completed: false)
        guard case .rejected(let why) = load(root) else { return XCTFail() }
        XCTAssertTrue(why.contains("absent"))
    }

    func testCorruptProofIsRejected() {
        let sb = Sandbox(); let root = sb.dir("d/JOB")
        for bad in ["xyz", String(good.dropLast()), good.uppercased()] {
            CheckpointStore.save(targetRoot: root, folderName: "JOB", verificationModel: "md5", identity: identity,
                                 files: ["a": "ok"], stamps: ["a": "1:2"],
                                 proofs: ["a": FileProof(source: bad, destination: bad, verdict: "checksum")], completed: false)
            guard case .rejected(let why) = load(root) else { return XCTFail(bad) }
            XCTAssertTrue(why.contains("corupt"), bad)
        }
        // Sursă ≠ destinație în dovadă → corupt.
        CheckpointStore.save(targetRoot: root, folderName: "JOB", verificationModel: "md5", identity: identity,
                             files: ["a": "ok"], stamps: ["a": "1:2"],
                             proofs: ["a": FileProof(source: good, destination: String(repeating: "0", count: 32), verdict: "checksum")],
                             completed: false)
        guard case .rejected = load(root) else { return XCTFail() }
    }

    func testChangedAlgorithmIsRejected() {
        let sb = Sandbox(); let root = sb.dir("d/JOB")
        CheckpointStore.save(targetRoot: root, folderName: "JOB", verificationModel: "md5", identity: identity,
                             files: ["a": "ok"], stamps: ["a": "1:2"],
                             proofs: ["a": FileProof(source: good, destination: good, verdict: "checksum")], completed: false)
        guard case .rejected = load(root, model: "sha256") else { return XCTFail() }
    }

    func testRevalidationPolicy() {
        let s = good, other = String(repeating: "1", count: 32)
        XCTAssertEqual(RevalidationPolicy.decide(model: .md5, expected: s, sourceHash: s, destinationHash: s), .accept)
        XCTAssertEqual(RevalidationPolicy.decide(model: .md5, expected: nil, sourceHash: s, destinationHash: s), .accept)
        if case .recopy = RevalidationPolicy.decide(model: .md5, expected: other, sourceHash: s, destinationHash: s) {} else { XCTFail("sursa diferă de checkpoint") }
        if case .recopy = RevalidationPolicy.decide(model: .md5, expected: s, sourceHash: s, destinationHash: other) {} else { XCTFail("destinația diferă") }
        if case .recopy = RevalidationPolicy.decide(model: .md5, expected: s, sourceHash: nil, destinationHash: s) {} else { XCTFail("sursă ilizibilă") }
        if case .recopy = RevalidationPolicy.decide(model: .md5, expected: s, sourceHash: s, destinationHash: nil) {} else { XCTFail("destinație ilizibilă") }
        if case .recopy = RevalidationPolicy.decide(model: .sizeOnly, expected: nil, sourceHash: "", destinationHash: "") {} else { XCTFail("sizeOnly") }
    }

    /// Metadata identică (cale, volum injectat, listă, mărimi, mtime) → aceeași
    /// identitate, deși octeții diferă. Deci identitatea NU poate acorda
    /// verdictul; doar recitirea (politica de mai sus) o poate face.
    func testIdentityCannotSeeBytes() throws {
        let sb = Sandbox()
        let f = sb.file("CARD/x.mov", bytes: 4096, seed: 1)
        let root = (sb.root as NSString).appendingPathComponent("CARD")
        let mtime = try FileManager.default.attributesOfItem(atPath: f)[.modificationDate] as! Date
        let a = SourceIdentity.compute(sources: [root], files: listAllFiles(root: root), volumeOf: { _ in "VOL-1" })
        let other = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 * 7 + 3) })
        try other.write(to: URL(fileURLWithPath: f))
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: f)
        let b = SourceIdentity.compute(sources: [root], files: listAllFiles(root: root), volumeOf: { _ in "VOL-1" })
        XCTAssertEqual(a, b, "metadata identică → identitate identică")
    }
}

final class DurabilityTests: XCTestCase {
    func prims(full: Int32, fsync: Int32) -> FlushPrimitives { FlushPrimitives(fullFsync: { _ in full }, fsync: { _ in fsync }) }

    func testFullFsyncAccepted() throws {
        XCTAssertEqual(try physicalFlush(fd: 0, using: prims(full: 0, fsync: EIO)), .full)
    }

    func testFallbackOnlyWhenUnsupportedAndSucceeds() throws {
        XCTAssertEqual(try physicalFlush(fd: 0, using: prims(full: ENOTSUP, fsync: 0)), .fsyncFallback)
        XCTAssertEqual(try physicalFlush(fd: 0, using: prims(full: EINVAL, fsync: 0)), .fsyncFallback)
    }

    func testFallbackFailurePreservesErrno() {
        XCTAssertThrowsError(try physicalFlush(fd: 0, using: prims(full: ENOTSUP, fsync: EIO))) { e in
            XCTAssertEqual((e as NSError).domain, NSPOSIXErrorDomain)
            XCTAssertEqual((e as NSError).code, Int(EIO))
        }
    }

    /// O eroare reală a F_FULLFSYNC (nu „nesuportat”) NU cade pe fsync.
    func testRealFullFsyncErrorIsNotMaskedByFallback() {
        XCTAssertThrowsError(try physicalFlush(fd: 0, using: prims(full: EIO, fsync: 0))) { e in
            XCTAssertEqual((e as NSError).code, Int(EIO))
        }
    }

    func testDirectoryFlushPolicy() throws {
        let sb = Sandbox()
        XCTAssertEqual(try flushDirectory(sb.root, using: prims(full: ENOTSUP, fsync: ENOTSUP)), .unsupported)
        XCTAssertEqual(try flushDirectory(sb.root, using: prims(full: ENOTSUP, fsync: 0)), .fsyncFallback)
        XCTAssertThrowsError(try flushDirectory(sb.root, using: prims(full: EIO, fsync: 0)))
        XCTAssertEqual(try flushDirectory(sb.root), .full, "APFS acceptă F_FULLFSYNC pe foldere")
    }

    /// Flush eșuat în copiere → fișier neconfirmat, fără nume final.
    func testCopyWithFailingFlushIsNotConfirmed() throws {
        let sb = Sandbox()
        let src = sb.file("src/a.bin", bytes: 10_000)
        let dst = (sb.dir("d") as NSString).appendingPathComponent("a.bin")
        let io = FanOutIO(write: FanOutIO.system.write, flush: prims(full: ENOTSUP, fsync: EIO))
        let r = try FanOutCopier(sourcePath: src, destinationPaths: [dst], chunkSize: 4096, model: .xxhash64,
                                 cancel: CancelToken(), pause: PauseToken(), expectedSize: 10_000, io: io).run { _ in }
        guard case .failure(let e) = r.destinations[dst] else { return XCTFail() }
        XCTAssertEqual((e as NSError).code, Int(EIO))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst))
        XCTAssertTrue(partialFiles(under: sb.root).isEmpty)
    }

    func testReadBackReportsRefusedNoCache() throws {
        let sb = Sandbox()
        let f = sb.file("a.bin", bytes: 5000)
        let refused = try readBackHash(path: f, model: .xxhash64, chunkSize: 1024, cancel: CancelToken(), setNoCache: { _ in EINVAL })
        XCTAssertFalse(refused.cacheBypassRequested)
        let accepted = try readBackHash(path: f, model: .xxhash64, chunkSize: 1024, cancel: CancelToken())
        XCTAssertTrue(accepted.cacheBypassRequested)
        XCTAssertEqual(refused.hash, accepted.hash)
    }
}

final class FanOutFailureTests: XCTestCase {
    /// O destinație care eșuează la a 3-a bucată, pe un fișier de ~64 de
    /// bucăți cu coadă de adâncime 2: cititorul nu se blochează, cealaltă
    /// destinație se confirmă, nu rămân parțiale. Limită de timp strictă.
    func testFailingWriterDoesNotDeadlockOthers() throws {
        let sb = Sandbox()
        let src = sb.file("src/big.bin", bytes: 64 * 4096)
        let good = (sb.dir("good") as NSString).appendingPathComponent("big.bin")
        let bad = (sb.dir("bad") as NSString).appendingPathComponent("big.bin")
        let counter = NSLock(); var calls = 0
        let io = FanOutIO(write: { h, d, dst in
            if dst == bad {
                counter.lock(); calls += 1; let n = calls; counter.unlock()
                if n == 3 { throw posixError(ENOSPC, "scriere simulată") }
            }
            try h.write(contentsOf: d)
        }, flush: .system)
        let done = expectation(description: "fan-out terminat")
        var result: FanOutResult?
        DispatchQueue.global().async {
            result = try? FanOutCopier(sourcePath: src, destinationPaths: [good, bad], chunkSize: 4096, ringDepth: 2,
                                       model: .xxhash64, cancel: CancelToken(), pause: PauseToken(),
                                       expectedSize: 64 * 4096, io: io).run { _ in }
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        guard let r = result else { return XCTFail("fără rezultat") }
        guard case .success = r.destinations[good] else { return XCTFail("destinația bună") }
        guard case .failure(let e) = r.destinations[bad] else { return XCTFail("destinația defectă") }
        XCTAssertEqual((e as NSError).code, Int(ENOSPC))
        XCTAssertFalse(FileManager.default.fileExists(atPath: bad))
        XCTAssertTrue(partialFiles(under: sb.root).isEmpty)
    }
}

final class DestinationContextTests: XCTestCase {
    func makeContext(_ sb: Sandbox, dest: String) -> DestinationContext {
        DestinationContext(destRoot: dest, folderName: "JOB", verificationModel: .xxhash64, generateMHL: false,
                           meta: ProductionMeta(), sourceRoot: nil,
                           sourceIdentity: SourceIdentity(roots: [], volumes: [], manifestDigest: "", fileCount: 0),
                           cloudUploadQueue: nil, startedAt: Date(),
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
