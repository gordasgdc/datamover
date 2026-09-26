import XCTest
@testable import DataMoverMac

final class PreflightTests: XCTestCase {
    func codes(_ issues: [PreflightIssue]) -> Set<PreflightIssue.Code> { Set(issues.map(\.code)) }

    func testCleanConfigurationPasses() {
        let sb = Sandbox()
        let src = sb.dir("card"), d1 = sb.dir("backupA"), d2 = sb.dir("backupB")
        let issues = Preflight.check(sources: [src], destinations: [d1, d2])
        XCTAssertFalse(Preflight.hasBlocking(issues), "\(issues)")
    }

    func testOverlapsAreBlocking() {
        let sb = Sandbox()
        let src = sb.dir("card")
        let inside = sb.dir("card/out")
        XCTAssertTrue(codes(Preflight.check(sources: [src], destinations: [inside])).contains(.destinationInsideSource))
        XCTAssertTrue(codes(Preflight.check(sources: [src], destinations: [src])).contains(.sameAsSource))
        let parent = sb.dir("work")
        let nestedSrc = sb.dir("work/card")
        XCTAssertTrue(codes(Preflight.check(sources: [nestedSrc], destinations: [parent])).contains(.sourceInsideDestination))
    }

    func testPrefixIsNotContainment() {
        let sb = Sandbox()
        let src = sb.dir("Car")
        let dst = sb.dir("Card")
        XCTAssertFalse(Preflight.hasBlocking(Preflight.check(sources: [src], destinations: [dst])))
    }

    func testDuplicateAndNestedDestinations() {
        let sb = Sandbox()
        let src = sb.dir("card"), d = sb.dir("backup"), sub = sb.dir("backup/day1")
        XCTAssertTrue(codes(Preflight.check(sources: [src], destinations: [d, d + "/"])).contains(.duplicateDestination))
        XCTAssertTrue(codes(Preflight.check(sources: [src], destinations: [d, sub])).contains(.nestedDestinations))
    }

    /// Un symlink către sursă, folosit ca destinație, e prins pe calea
    /// canonică, nu ratat pe text.
    func testSymlinkToSourceIsDetected() throws {
        let sb = Sandbox()
        let src = sb.dir("card")
        let link = (sb.root as NSString).appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: src)
        XCTAssertTrue(codes(Preflight.check(sources: [src], destinations: [link])).contains(.sameAsSource))
        XCTAssertTrue(codes(Preflight.check(sources: [link], destinations: [sb.dir("b")])).contains(.symlinkSource))
    }

    func testMissingPathsAreBlocking() {
        let sb = Sandbox()
        let c = codes(Preflight.check(sources: [sb.root + "/nope"], destinations: [sb.root + "/gone"]))
        XCTAssertTrue(c.contains(.sourceMissing))
        XCTAssertTrue(c.contains(.destinationMissing))
        XCTAssertTrue(codes(Preflight.check(sources: [], destinations: [])).isSuperset(of: [.noSources, .noDestinations]))
    }
}

@MainActor
final class RunnerIntegrationTests: XCTestCase {
    func makeCard(_ sb: Sandbox) -> String {
        sb.file("CARD/CLIP/A001.mov", bytes: 700_000, seed: 1)
        sb.file("CARD/CLIP/A002.mov", bytes: 123_457, seed: 2)
        sb.file("CARD/CLIP/EMPTY.wav", bytes: 0)
        sb.file("CARD/META/index.xml", bytes: 999, seed: 3)
        return (sb.root as NSString).appendingPathComponent("CARD")
    }

    func testTransferToTwoDestinationsVerifiedAndSourceUntouched() async throws {
        let sb = Sandbox()
        let src = makeCard(sb)
        let before = fingerprint(src)
        let d1 = sb.dir("A"), d2 = sb.dir("B")
        let runner = OffloadRunner()
        try await runTransfer(runner, sources: [src], destinations: [d1, d2])
        XCTAssertEqual(runner.lastOutcome, .success)
        XCTAssertEqual(runner.lastResults.count, 2)
        for r in runner.lastResults {
            XCTAssertEqual(r.outcome, .verified)
            XCTAssertEqual(r.okCount, 4)
            XCTAssertEqual(r.failCount, 0)
            XCTAssertNotNil(r.csvPath)
            XCTAssertNotNil(r.mhlPath)
        }
        XCTAssertEqual(fingerprint(src), before, "sursa a fost modificată")
        for d in [d1, d2] {
            let job = (d as NSString).appendingPathComponent("JOB")
            XCTAssertEqual(try hashOfFile(path: job + "/CLIP/A001.mov", model: .sha256, cancel: CancelToken()),
                           try hashOfFile(path: src + "/CLIP/A001.mov", model: .sha256, cancel: CancelToken()))
            XCTAssertTrue(FileManager.default.fileExists(atPath: job + "/CLIP/EMPTY.wav"))
            XCTAssertTrue(partialFiles(under: d).isEmpty)
        }
        // MHL conține exact fișierele confirmate.
        let mhl = try String(contentsOfFile: runner.lastResults[0].mhlPath!, encoding: .utf8)
        XCTAssertTrue(mhl.contains("A001.mov") && mhl.contains("index.xml"))
    }

    /// Checkpoint depășit: fișier marcat „ok” dar șters la destinație →
    /// reluarea îl recopiază, nu îl raportează ca existent.
    func testResumeRecopiesFileMissingDespiteCheckpoint() async throws {
        let sb = Sandbox()
        let src = makeCard(sb)
        let d1 = sb.dir("A")
        let runner = OffloadRunner()
        try await runTransfer(runner, sources: [src], destinations: [d1])
        XCTAssertEqual(runner.lastOutcome, .success)
        let victim = (d1 as NSString).appendingPathComponent("JOB/CLIP/A002.mov")
        try FileManager.default.removeItem(atPath: victim)
        try await runTransfer(runner, sources: [src], destinations: [d1], resume: true)
        XCTAssertEqual(runner.lastOutcome, .success)
        XCTAssertTrue(FileManager.default.fileExists(atPath: victim))
        XCTAssertEqual(runner.lastResults[0].okCount, 1, "doar fișierul lipsă se recopiază")
        XCTAssertEqual(runner.lastResults[0].skipCount, 3, "restul: recitite și acceptate")
    }

    /// Reluare cu alt algoritm: checkpoint-ul e ignorat, fișierele existente
    /// se reverifică (nu se consideră verificate cu algoritmul vechi).
    func testResumeWithOtherModelReverifies() async throws {
        let sb = Sandbox()
        let src = makeCard(sb)
        let d1 = sb.dir("A")
        let runner = OffloadRunner()
        try await runTransfer(runner, sources: [src], destinations: [d1], model: .md5)
        try await runTransfer(runner, sources: [src], destinations: [d1], model: .sha256)
        XCTAssertEqual(runner.lastOutcome, .success)
        XCTAssertTrue(runner.activityLines.contains { $0.contains("Checkpoint ignorat") })
    }

    /// Card nou la ACEEAȘI cale, cu aceleași nume și mărimi, dar alt
    /// conținut: checkpoint-ul vechi nu are voie să sară nimic. Destinația
    /// ajunge să conțină exact noua sursă.
    func testReplacedSourceAtSamePathIsNeverSkipped() async throws {
        let sb = Sandbox()
        let src = makeCard(sb)
        let d1 = sb.dir("A")
        let runner = OffloadRunner()
        try await runTransfer(runner, sources: [src], destinations: [d1])
        XCTAssertEqual(runner.lastOutcome, .success)
        // „Alt card”: aceleași căi relative și mărimi, alt conținut.
        try FileManager.default.removeItem(atPath: src)
        sb.file("CARD/CLIP/A001.mov", bytes: 700_000, seed: 91)
        sb.file("CARD/CLIP/A002.mov", bytes: 123_457, seed: 92)
        sb.file("CARD/CLIP/EMPTY.wav", bytes: 0)
        sb.file("CARD/META/index.xml", bytes: 999, seed: 93)
        for rel in ["CLIP/A001.mov", "CLIP/A002.mov", "CLIP/EMPTY.wav", "META/index.xml"] {
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(3600)],
                                                  ofItemAtPath: src + "/" + rel)
        }
        try await runTransfer(runner, sources: [src], destinations: [d1], resume: true)
        XCTAssertEqual(runner.lastOutcome, .success)
        XCTAssertTrue(runner.activityLines.contains { $0.contains("altă sursă") })
        let r = runner.lastResults[0]
        XCTAssertEqual(r.skipCount + r.okCount, 4)
        for rel in ["CLIP/A001.mov", "CLIP/A002.mov", "META/index.xml"] {
            XCTAssertEqual(try hashOfFile(path: d1 + "/JOB/" + rel, model: .sha256, cancel: CancelToken()),
                           try hashOfFile(path: src + "/" + rel, model: .sha256, cancel: CancelToken()), rel)
        }
    }

    /// Același conținut, altă cale a sursei → checkpoint respins; fișierele
    /// existente se reverifică prin citire (sărite doar după comparare).
    func testSameContentOtherPathReverifiesInsteadOfTrustingCheckpoint() async throws {
        let sb = Sandbox()
        let src = makeCard(sb)
        let d1 = sb.dir("A")
        let runner = OffloadRunner()
        try await runTransfer(runner, sources: [src], destinations: [d1])
        let moved = (sb.root as NSString).appendingPathComponent("CARD2")
        try FileManager.default.copyItem(atPath: src, toPath: moved)
        try await runTransfer(runner, sources: [moved], destinations: [d1], resume: true)
        XCTAssertEqual(runner.lastOutcome, .success)
        XCTAssertTrue(runner.activityLines.contains { $0.contains("Checkpoint ignorat") })
        XCTAssertTrue(runner.activityLines.contains { $0.contains("Verificare fisier existent") })
    }

    /// Același card, aceeași cale, același volum, aceleași nume, mărimi și
    /// mtime — dar alți octeți. Reluarea NU are voie să sară fișierul.
    func testSameMetadataDifferentBytesIsRecopied() async throws {
        let sb = Sandbox()
        let src = makeCard(sb)
        let d1 = sb.dir("A")
        let runner = OffloadRunner()
        try await runTransfer(runner, sources: [src], destinations: [d1])
        XCTAssertEqual(runner.lastOutcome, .success)
        let victim = src + "/CLIP/A002.mov"
        let mtime = try FileManager.default.attributesOfItem(atPath: victim)[.modificationDate] as! Date
        let size = try FileManager.default.attributesOfItem(atPath: victim)[.size] as! Int
        try Data((0..<size).map { UInt8(truncatingIfNeeded: $0 &* 13 &+ 5) }).write(to: URL(fileURLWithPath: victim))
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: victim)
        try await runTransfer(runner, sources: [src], destinations: [d1], resume: true)
        XCTAssertEqual(runner.lastOutcome, .success)
        XCTAssertFalse(runner.activityLines.contains { $0.contains("Checkpoint ignorat") }, "identitatea (metadata) trebuie să coincidă")
        XCTAssertTrue(runner.activityLines.contains { $0.contains("sursa diferă de cea din checkpoint") })
        XCTAssertEqual(try hashOfFile(path: d1 + "/JOB/CLIP/A002.mov", model: .sha256, cancel: CancelToken()),
                       try hashOfFile(path: victim, model: .sha256, cancel: CancelToken()))
        XCTAssertEqual(runner.lastResults[0].okCount, 1)
        XCTAssertEqual(runner.lastResults[0].skipCount, 3, "celelalte: acceptate DOAR după recitirea ambelor părți")
    }

    /// Sursa neschimbată, destinația modificată după checkpoint (alți octeți,
    /// aceeași mărime) → destinația e recitită, nepotrivirea e găsită.
    func testTamperedDestinationSameSizeIsRecopied() async throws {
        let sb = Sandbox()
        let src = makeCard(sb)
        let d1 = sb.dir("A")
        let runner = OffloadRunner()
        try await runTransfer(runner, sources: [src], destinations: [d1])
        let copy = d1 + "/JOB/CLIP/A001.mov"
        let attrs = try FileManager.default.attributesOfItem(atPath: copy)
        let size = attrs[.size] as! Int
        try Data(repeating: 0xAB, count: size).write(to: URL(fileURLWithPath: copy))
        try FileManager.default.setAttributes([.modificationDate: attrs[.modificationDate] as! Date], ofItemAtPath: copy)
        try await runTransfer(runner, sources: [src], destinations: [d1], resume: true)
        XCTAssertEqual(runner.lastOutcome, .success)
        XCTAssertTrue(runner.activityLines.contains { $0.contains("destinația diferă de sursă") })
        XCTAssertEqual(try hashOfFile(path: copy, model: .sha256, cancel: CancelToken()),
                       try hashOfFile(path: src + "/CLIP/A001.mov", model: .sha256, cancel: CancelToken()))
    }

    /// Fișierul de 0 octeți: acceptat la reluare doar prin recitire (hash-ul
    /// gol al algoritmului), nu pe mărime.
    func testZeroByteFileRevalidatedOnResume() async throws {
        let sb = Sandbox()
        let src = makeCard(sb)
        let d1 = sb.dir("A")
        let runner = OffloadRunner()
        try await runTransfer(runner, sources: [src], destinations: [d1])
        try await runTransfer(runner, sources: [src], destinations: [d1], resume: true)
        XCTAssertEqual(runner.lastOutcome, .success)
        XCTAssertEqual(runner.lastResults[0].skipCount, 4)
        XCTAssertTrue(runner.activityLines.contains { $0.contains("Verificare fisier existent: CLIP/EMPTY.wav") })
    }

    /// „Doar octeți”: nicio dovadă de conținut → la reluare totul se recopiază.
    func testSizeOnlyResumeRecopiesEverything() async throws {
        let sb = Sandbox()
        let src = makeCard(sb)
        let d1 = sb.dir("A")
        let runner = OffloadRunner()
        try await runTransfer(runner, sources: [src], destinations: [d1], model: .sizeOnly)
        try await runTransfer(runner, sources: [src], destinations: [d1], model: .sizeOnly, resume: true)
        XCTAssertEqual(runner.lastOutcome, .success)
        XCTAssertEqual(runner.lastResults[0].okCount, 4)
        XCTAssertEqual(runner.lastResults[0].skipCount, 0)
    }

    func testPreflightBlocksDestinationInsideSource() async throws {
        let sb = Sandbox()
        let src = makeCard(sb)
        let inside = sb.dir("CARD/backup")
        let before = fingerprint(src)
        let runner = OffloadRunner()
        OffloadRunner.sideEffectsEnabled = false
        runner.start(sources: [src], destinations: [inside], folderNameOverride: "JOB")
        XCTAssertFalse(runner.isRunning)
        XCTAssertTrue(Preflight.hasBlocking(runner.preflightIssues))
        XCTAssertEqual(fingerprint(src), before)
    }

    func testCancelledTransferIsNeverSuccess() async throws {
        let sb = Sandbox()
        for i in 0..<40 { sb.file("CARD/f\(i).bin", bytes: 200_000, seed: UInt8(i)) }
        let src = (sb.root as NSString).appendingPathComponent("CARD")
        let d1 = sb.dir("A")
        let runner = OffloadRunner()
        OffloadRunner.sideEffectsEnabled = false
        runner.start(sources: [src], destinations: [d1], folderNameOverride: "JOB")
        runner.cancel()
        while runner.isRunning { try await Task.sleep(nanoseconds: 20_000_000) }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(runner.lastOutcome, .cancelled)
        XCTAssertTrue(partialFiles(under: d1).isEmpty)
    }
}

final class LocalizationTests: XCTestCase {
    /// Fiecare cheie nouă are RO/EN/ES, iar specificatorii (%@, %d) coincid.
    func testExtraTableIsCompleteAndConsistent() {
        let spec = try! NSRegularExpression(pattern: "%[@d]")
        for (key, entry) in L.extraTable {
            for lang in AppLanguage.allCases {
                XCTAssertFalse((entry[lang] ?? "").isEmpty, "\(key) lipsește \(lang)")
            }
            let sig = AppLanguage.allCases.map { lang -> [String] in
                let s = entry[lang] ?? ""
                return spec.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { (s as NSString).substring(with: $0.range) }
            }
            XCTAssertTrue(sig.allSatisfy { $0 == sig[0] }, "\(key): specificatori diferiți")
        }
    }

    func testDynamicKeysExist() {
        let keys = TransferPhase.allCases.map(\.labelKey)
            + [TransferOutcome.success, .successWithWarnings, .partialFailure, .failure, .cancelled].flatMap { [$0.labelKey, "outcomeHelp.\($0.rawValue)"] }
            + [DestinationOutcome.verified, .verifiedWithWarnings, .failed, .cancelled].map { "destOutcome.\($0.rawValue)" }
            + [VerificationDepth.sizeOnly, .streamChecksum, .readBack].map(\.labelKey)
            + ["noSources", "noDestinations", "sourceMissing", "destinationMissing", "destinationNotWritable",
               "destinationNotDirectory", "destinationInsideSource", "sourceInsideDestination", "sameAsSource",
               "duplicateDestination", "nestedDestinations", "sameVolumeAsSource", "symlinkSource"].map { "preflight.\($0)" }
        for k in keys { XCTAssertNotNil(L.extraTable[k], k) }
    }
}
