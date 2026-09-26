import XCTest
import PDFKit
@testable import DataMoverMac

/// Rapoartele de livrare: verdict = motorul, texte complete RO/EN/ES, PDF paginat.
/// Mostrele se scriu în directorul temporar al testului; cu DM_REPORT_SAMPLES=<dir>
/// se păstrează acolo pentru inspecție vizuală (în afara repo-ului).
final class ReportTests: XCTestCase {
    static func row(_ i: Int, status: String = "OK", file: String? = nil, error: String = "") -> ReportRow {
        let h = String(format: "%016llx", UInt64(i) &* 0x9E3779B97F4A7C15)
        let bad = status.hasPrefix("NEPOTRIVIRE")
        return ReportRow(file: file ?? "PRIVATE/M4ROOT/CLIP/C\(String(format: "%04d", i)).MP4", sizeBytes: Int64(1_000_000 + i * 4099),
                         srcHash: status.hasPrefix("EROARE") ? "" : h, dstHash: status.hasPrefix("EROARE") ? "" : (bad ? "ffff" + h.dropFirst(4) : h),
                         status: status, error: error, destPath: "")
    }

    static func base(_ lang: ReportLang) -> DeliveryReport {
        var r = DeliveryReport()
        r.lang = lang; r.appVersion = "2.16.2 (40)"
        r.generatedAt = Date(timeIntervalSince1970: 1_790_000_000)
        r.startedAt = Date(timeIntervalSince1970: 1_789_999_000); r.finishedAt = Date(timeIntervalSince1970: 1_789_999_754)
        r.folderName = "2026-09-26_SOARE_DE_IARNĂ_A001"; r.destination = "/Volumes/SHUTTLE-01/2026-09-26_SOARE_DE_IARNĂ_A001"
        r.project = "Soare de iarnă"; r.card = "A001"; r.sourceName = "A001"; r.operatorName = "DIT — Ana Pérez Núñez"
        r.camera = "ARRI Alexa 35"; r.verification = "xxHash64 — checksum în flux"; r.copyCount = 2
        r.mhlFile = "2026-09-26_SOARE_DE_IARNĂ_A001.mhl"; r.csvFile = "offload_report_2026-09-26_10-00-00.csv"; r.jobID = "1d861b6f"
        return r
    }

    /// Cele 6 scenarii cerute: reușit, avertisment, eșec parțial, căi lungi, multipagină, anulat.
    static func scenarios(_ lang: ReportLang) -> [(String, DeliveryReport)] {
        var ok = base(lang); ok.rows = (1...10).map { row($0) }; ok.okCount = 10; ok.bytesConfirmed = ok.rows.reduce(0) { $0 + $1.sizeBytes }
        var warn = ok; warn.rows[3] = row(4, status: "OK (reîncercat)"); warn.recoveredCount = 1
        var fail = base(lang); fail.rows = (1...8).map { row($0) } + [row(9, status: "NEPOTRIVIRE", error: "Checksum-ul copiei diferă de sursă."), row(10, status: "EROARE (reîncercat)", error: "Discul nu a confirmat scrierea (flush).")]
        fail.okCount = 8; fail.failCount = 2; fail.bytesConfirmed = 8_100_000
        var long = ok
        long.destination = "/Volumes/RAID-02 Backup Principal Producție/" + String(repeating: "Subfolder_foarte_lung_pentru_test_", count: 5) + "A001"
        long.rows = [row(1, file: "PRIVATE/M4ROOT/CLIP/" + String(repeating: "Numele_unui_clip_extrem_de_lung_ăîșțâ_ñáéíóú_", count: 6) + "C0001.MP4"), row(2)]
        long.okCount = 2; long.notes = "Card cu fișiere Unicode: ăîșțâ ÄÖÜ ñ 日本語 — verificat."
        var many = ok; many.rows = (1...140).map { row($0) }; many.okCount = 180; many.bytesConfirmed = 185_000_000_000
        var cancel = ok; cancel.cancelled = true; cancel.okCount = 4; cancel.rows = Array(ok.rows.prefix(4))
        return [("1-reusit", ok), ("2-avertisment", warn), ("3-esec-partial", fail), ("4-cai-lungi", long), ("5-multipagina", many), ("6-anulat", cancel)]
    }

    var outDir: URL!
    override func setUpWithError() throws {
        if let d = ProcessInfo.processInfo.environment["DM_REPORT_SAMPLES"] { outDir = URL(fileURLWithPath: d) }
        else { outDir = FileManager.default.temporaryDirectory.appendingPathComponent("dm-report-\(UUID().uuidString)") }
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        if ProcessInfo.processInfo.environment["DM_REPORT_SAMPLES"] == nil { try? FileManager.default.removeItem(at: outDir) }
    }

    func testVerdictFollowsEngine() {
        let s = Dictionary(uniqueKeysWithValues: Self.scenarios(.ro))
        XCTAssertEqual(s["1-reusit"]!.outcome, .verified)
        XCTAssertEqual(s["2-avertisment"]!.outcome, .verifiedWithWarnings)
        XCTAssertEqual(s["3-esec-partial"]!.outcome, .failed)
        XCTAssertEqual(s["6-anulat"]!.outcome, .cancelled)
        XCTAssertFalse(s["3-esec-partial"]!.html().contains("VERIFICAT</b>"), "un eșec nu poate apărea ca verificat")
    }

    func testAllStringsTranslated() {
        for (k, v) in DeliveryReport.strings {
            for l in [ReportLang.ro, .en, .es] { XCTAssertFalse((v[l] ?? "").isEmpty, "\(k) lipsă în \(l)") }
            XCTAssertEqual(v[.ro]!.components(separatedBy: "%").count, v[.en]!.components(separatedBy: "%").count, "specificatori \(k)")
            XCTAssertEqual(v[.ro]!.components(separatedBy: "%").count, v[.es]!.components(separatedBy: "%").count, "specificatori \(k)")
        }
    }

    func testHTMLAndPDFForAllScenariosAndLanguages() throws {
        for lang in [ReportLang.ro, .en, .es] {
            for (name, r) in Self.scenarios(lang) {
                let html = r.html()
                XCTAssertTrue(html.contains(r.verdictTitle), "\(name)/\(lang): verdict în HTML")
                XCTAssertTrue(html.contains("2.16.2 (40)"), "versiunea în subsol")
                for raw in ["verdict.", "help.", "f.project", "col.", "st.", "footer."] {
                    XCTAssertFalse(html.contains(">\(raw)"), "\(name)/\(lang): cheie brută \(raw)")
                }
                XCTAssertFalse(html.contains("data:image/jpeg"), "fără miniaturi media")
                try html.write(to: outDir.appendingPathComponent("\(name)-\(lang.rawValue).html"), atomically: true, encoding: .utf8)
                let pdfURL = outDir.appendingPathComponent("\(name)-\(lang.rawValue).pdf")
                let res = r.writePDF(to: pdfURL.path)
                XCTAssertTrue(res.ok, res.error ?? "")
                let doc = try XCTUnwrap(PDFDocument(url: pdfURL))
                let text = (0..<doc.pageCount).compactMap { doc.page(at: $0)?.string }.joined(separator: "\n")
                XCTAssertTrue(text.contains(r.verdictTitle), "\(name)/\(lang): verdict în PDF")
                XCTAssertTrue(text.contains(String(format: r.t("footer.page"), doc.pageCount, doc.pageCount)), "\(name)/\(lang): paginare")
                if name == "5-multipagina" { XCTAssertGreaterThan(doc.pageCount, 2) }
                if name == "4-cai-lungi" { XCTAssertTrue(text.contains("ăîșțâ"), "diacritice în PDF") }
            }
        }
    }
}
