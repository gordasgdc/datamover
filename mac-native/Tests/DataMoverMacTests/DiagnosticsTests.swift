import XCTest
@testable import DataMoverMac

final class RedactorTests: XCTestCase {
    func testSecretsAreRedacted() {
        let raw = "user dumitru@example.com license=GDC1-ABCD-EFGH token: abc.def password \"hunter2\" " +
            "key K3yZx9QvLm2Np7Rt5Wu8Yb4Cd6 path /Users/johndoe/Movies/x.mov"
        let r = Redactor.redactSecrets(raw)
        for leaked in ["dumitru@example.com", "GDC1-ABCD-EFGH", "abc.def", "hunter2", "K3yZx9QvLm2Np7Rt5Wu8Yb4Cd6", "johndoe"] {
            XCTAssertFalse(r.contains(leaked), "\(leaked) în \(r)")
        }
        XCTAssertTrue(r.contains("~/Movies/x.mov"))
    }

    func testPathsAreAnonymizedStablyKeepingExtension() {
        let a = Redactor.anonymizePaths("copiat /Volumes/A001/CLIP/A001C001.mov și /Volumes/A001/CLIP/A001C001.mov")
        XCTAssertFalse(a.contains("A001C001"))
        let tokens = a.components(separatedBy: " ").filter { $0.hasPrefix("<path#") }
        XCTAssertEqual(tokens.count, 2); XCTAssertEqual(tokens[0], tokens[1]); XCTAssertTrue(tokens[0].hasSuffix(".mov"))
        XCTAssertEqual(Redactor.anonymizePaths("fără căi aici"), "fără căi aici")
    }
}

final class StructuredLogTests: XCTestCase {
    func records(_ dir: URL) -> [LogRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.flatMap { (try? String(contentsOf: $0, encoding: .utf8))?.split(separator: "\n") ?? [] }
            .compactMap { try? JSONDecoder().decode(LogRecord.self, from: Data($0.utf8)) }
    }

    func testRecordHasRequiredFieldsInUTC() {
        let sb = Sandbox()
        let dir = URL(fileURLWithPath: sb.dir("log"))
        let log = StructuredLog(config: .init(directory: dir), sessionID: "sess1234")
        log.log(.info, "job", "job.started", "x", job: "job1", dest: "d-1", fields: ["a": "b"])
        log.log(.debug, "copy", "file.confirmed", "sub pragul info — nu se scrie")
        log.flush()
        let r = records(dir)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].session, "sess1234"); XCTAssertEqual(r[0].job, "job1"); XCTAssertEqual(r[0].dest, "d-1")
        XCTAssertEqual(r[0].event, "job.started"); XCTAssertEqual(r[0].level, "info")
        XCTAssertTrue(r[0].ts.hasSuffix("Z"), "UTC: \(r[0].ts)")
        XCTAssertTrue(r[0].platform.hasPrefix("macOS"))
    }

    func testRotationAndRetentionBoundDiskUse() throws {
        let sb = Sandbox()
        let dir = URL(fileURLWithPath: sb.dir("log"))
        let log = StructuredLog(config: .init(directory: dir, maxBytes: 2_000, maxFiles: 3, maxAgeDays: 14))
        for i in 0..<200 { log.log(.info, "t", "t.e", String(repeating: "x", count: 50) + "\(i)") }
        log.flush()
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertLessThanOrEqual(files.count, 3, "\(files)")
        for f in files {
            let size = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(f).path)[.size] as! Int
            XCTAssertLessThanOrEqual(size, 2_000)
        }
        // Arhivă mai veche decât retenția → ștearsă la următoarea scriere.
        let old = dir.appendingPathComponent("datamover.jsonl.2")
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * 86_400)], ofItemAtPath: old.path)
        log.log(.info, "t", "t.e", "declanșează retenția"); log.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
    }

    /// Un jurnal care nu poate scrie nu aruncă, nu blochează, și spune de ce.
    func testUnwritableDirectoryFailsSafely() {
        let sb = Sandbox()
        let notADir = URL(fileURLWithPath: sb.file("blocked", bytes: 1))
        let log = StructuredLog(config: .init(directory: notADir))
        let start = Date()
        for _ in 0..<50 { log.log(.error, "t", "t.e", "nu se poate scrie") }
        log.flush()
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
        XCTAssertNotNil(log.lastWriteError)
    }
}

@MainActor
final class DiagnosticsIntegrationTests: XCTestCase {
    /// Un job cu două destinații: toate evenimentele lui au același job ID,
    /// iar rezultatele au ID-uri de destinație distincte.
    func testJobEventsAreCorrelatedAcrossTwoDestinations() async throws {
        let sb = Sandbox()
        sb.file("CARD/a.mov", bytes: 50_000, seed: 1); sb.file("CARD/b.mov", bytes: 70_000, seed: 2)
        let dir = URL(fileURLWithPath: sb.dir("log"))
        let saved = StructuredLog.shared
        StructuredLog.shared = StructuredLog(config: .init(directory: dir))
        defer { StructuredLog.shared = saved }
        let runner = OffloadRunner()
        try await runTransfer(runner, sources: [sb.root + "/CARD"], destinations: [sb.dir("A"), sb.dir("B")])
        StructuredLog.shared.flush()
        let recs = StructuredLogTests().records(dir)
        let job = runner.jobID
        XCTAssertFalse(job.isEmpty)
        XCTAssertTrue(recs.contains { $0.event == "job.started" && $0.job == job })
        let results = recs.filter { $0.event == "destination.result" }
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy { $0.job == job })
        XCTAssertEqual(Set(results.compactMap(\.dest)).count, 2)
        XCTAssertTrue(recs.contains { $0.event == "job.finished" && $0.job == job && $0.msg == "success" })
    }

    /// Un jurnal defect nu schimbă verdictul transferului.
    func testBrokenLoggerDoesNotAffectTransfer() async throws {
        let sb = Sandbox()
        sb.file("CARD/a.mov", bytes: 30_000)
        let saved = StructuredLog.shared
        StructuredLog.shared = StructuredLog(config: .init(directory: URL(fileURLWithPath: sb.file("notadir", bytes: 1))))
        defer { StructuredLog.shared = saved }
        let runner = OffloadRunner()
        try await runTransfer(runner, sources: [sb.root + "/CARD"], destinations: [sb.dir("A")])
        XCTAssertEqual(runner.lastOutcome, .success)
    }

    /// Exportul: doar jurnale + manifest/system/settings/last-job; fără media,
    /// fără secrete, fără căi (implicit).
    func testExportExcludesMediaSecretsAndPaths() throws {
        let sb = Sandbox()
        let media = sb.file("Volumes-sim/CLIP/SECRET_CLIENT_A001C001.mov", bytes: 4096)
        let dir = URL(fileURLWithPath: sb.dir("log"))
        let log = StructuredLog(config: .init(directory: dir), sessionID: "exp12345")
        log.log(.error, "copy", "file.failed", "eșec la /Volumes/CLIENT/SECRET_CLIENT_A001C001.mov license=GDC1-XYZ9-QWE8",
                fields: ["path": media, "token": "tok"])
        let defaults = UserDefaults(suiteName: "dm-tests-\(UUID().uuidString)")!
        defaults.set("xxhash64", forKey: "dm_verificationModel")
        defaults.set("GDC-LICENSE-SHOULD-NOT-EXPORT", forKey: "datamover_license_code")
        let out = URL(fileURLWithPath: sb.dir("exports"))
        let zip = try DiagnosticExporter(log: log, defaults: defaults).export(to: out)
        let unzip = URL(fileURLWithPath: sb.dir("unzipped"))
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto"); p.arguments = ["-x", "-k", zip.path, unzip.path]
        try p.run(); p.waitUntilExit()
        let files = FileManager.default.enumerator(atPath: unzip.path)!.compactMap { $0 as? String }
            .filter { !$0.hasSuffix("/") && !((try? FileManager.default.attributesOfItem(atPath: unzip.path + "/" + $0)[.type] as? FileAttributeType) == .typeDirectory) }
        XCTAssertTrue(files.allSatisfy { $0.hasSuffix(".jsonl") || $0.hasSuffix(".json") }, "\(files)")
        XCTAssertFalse(files.contains { $0.hasSuffix(".mov") })
        let all = try files.map { try String(contentsOfFile: unzip.path + "/" + $0, encoding: .utf8) }.joined()
        for leaked in ["SECRET_CLIENT", "GDC1-XYZ9-QWE8", "GDC-LICENSE-SHOULD-NOT-EXPORT", "\"tok\"", sb.root] {
            XCTAssertFalse(all.contains(leaked), "\(leaked) a ajuns în export")
        }
        XCTAssertTrue(all.contains("exp12345"))
        XCTAssertTrue(all.contains("\"dm_verificationModel\""))
        XCTAssertTrue(files.contains { $0.hasSuffix("manifest.json") })
    }
}
