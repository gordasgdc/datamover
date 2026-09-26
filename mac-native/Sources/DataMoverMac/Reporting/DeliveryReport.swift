import Foundation
import AppKit
import CoreText

// MARK: - Raportul de livrare (PDF + HTML) — model comun, texte RO/EN/ES
//
// Un singur model alimentează ambele formate, ca PDF-ul și HTML-ul să spună
// exact același lucru. Verdictul vine din `DestinationOutcome.evaluate` —
// aceeași funcție pe care o folosește ecranul Rezultat — deci un raport nu
// poate spune „verificat” când motorul nu a spus-o. Textele sunt aceleași ca
// în `windows-native/DataMover.Core/Services/DeliveryReport.cs`.
// Fără miniaturi: raportul nu conține nimic din conținutul fișierelor media.

enum ReportLang: String { case ro, en, es }

struct DeliveryReport {
    var lang: ReportLang = .ro
    var appVersion = ""
    var generatedAt = Date()
    var folderName = ""
    var sourceName = ""
    var destination = ""
    var project = "", card = "", client = "", operatorName = "", camera = "", notes = ""
    var logoPath = ""
    var startedAt = Date()
    var finishedAt = Date()
    var verification = ""
    var copyCount = 1
    var okCount = 0, skipCount = 0, failCount = 0, recoveredCount = 0
    var bytesConfirmed: Int64 = 0
    var cancelled = false
    var mhlFile: String?
    var csvFile: String?
    var jobID = ""
    /// Eșantionul plafonat (toate problemele + primele rânduri) — lista completă e în CSV.
    var rows: [ReportRow] = []
    /// Metadate tehnice opționale pe rând (rezoluție, fps, codec); nil în teste.
    var mediaLine: ((ReportRow) -> String?)? = nil

    var totalFiles: Int { okCount + skipCount + failCount }
    var outcome: DestinationOutcome {
        DestinationOutcome.evaluate(failCount: failCount, recoveredCount: recoveredCount, cancelled: cancelled)
    }
    var isTruncated: Bool { rows.count < totalFiles }

    // MARK: Texte

    static let strings: [String: [ReportLang: String]] = [
        "doc": [.ro: "Raport de livrare", .en: "Delivery report", .es: "Informe de entrega"],
        "destination": [.ro: "Destinație", .en: "Destination", .es: "Destino"],
        "verdict.verified": [.ro: "VERIFICAT", .en: "VERIFIED", .es: "VERIFICADO"],
        "verdict.verifiedWithWarnings": [.ro: "VERIFICAT, CU AVERTISMENTE", .en: "VERIFIED, WITH WARNINGS", .es: "VERIFICADO, CON AVISOS"],
        "verdict.failed": [.ro: "NECONFIRMAT", .en: "NOT CONFIRMED", .es: "NO CONFIRMADO"],
        "verdict.cancelled": [.ro: "ANULAT", .en: "CANCELLED", .es: "CANCELADO"],
        "help.verified": [.ro: "Toate fișierele (%d) au fost confirmate prin verificarea aleasă la această destinație.", .en: "All files (%d) were confirmed by the selected verification at this destination.", .es: "Todos los archivos (%d) se confirmaron con la verificación elegida en este destino."],
        "help.verifiedWithWarnings": [.ro: "Toate fișierele sunt confirmate. Reușite abia la reîncercare: %d — verifică cablul, cardul și discul.", .en: "All files are confirmed. Succeeded only on retry: %d — check the cable, card and drive.", .es: "Todos los archivos están confirmados. Correctos solo al reintentar: %d — revisa el cable, la tarjeta y el disco."],
        "help.failed": [.ro: "Fișiere neconfirmate la această destinație: %d. Nu formata cardul.", .en: "Files not confirmed at this destination: %d. Do not format the card.", .es: "Archivos sin confirmar en este destino: %d. No formatees la tarjeta."],
        "help.cancelled": [.ro: "Transferul a fost oprit înainte de final; lista nu este completă. Nu formata cardul.", .en: "The transfer was stopped before it finished; the list is incomplete. Do not format the card.", .es: "La transferencia se detuvo antes de terminar; la lista no está completa. No formatees la tarjeta."],
        "f.project": [.ro: "Proiect", .en: "Project", .es: "Proyecto"],
        "f.card": [.ro: "Card", .en: "Card", .es: "Tarjeta"],
        "f.source": [.ro: "Sursă", .en: "Source", .es: "Origen"],
        "f.client": [.ro: "Client", .en: "Client", .es: "Cliente"],
        "f.operator": [.ro: "Operator", .en: "Operator", .es: "Operador"],
        "f.camera": [.ro: "Cameră", .en: "Camera", .es: "Cámara"],
        "f.started": [.ro: "Început", .en: "Started", .es: "Inicio"],
        "f.finished": [.ro: "Terminat", .en: "Finished", .es: "Fin"],
        "f.duration": [.ro: "Durată", .en: "Duration", .es: "Duración"],
        "f.verification": [.ro: "Verificare", .en: "Verification", .es: "Verificación"],
        "f.copies": [.ro: "Copii în acest transfer", .en: "Copies in this transfer", .es: "Copias en esta transferencia"],
        "f.mhl": [.ro: "Fișier MHL", .en: "MHL file", .es: "Archivo MHL"],
        "f.csv": [.ro: "Listă completă (CSV)", .en: "Full list (CSV)", .es: "Lista completa (CSV)"],
        "f.notes": [.ro: "Note", .en: "Notes", .es: "Notas"],
        "f.job": [.ro: "ID job (suport)", .en: "Job ID (support)", .es: "ID de trabajo (soporte)"],
        "s.confirmed": [.ro: "Fișiere confirmate", .en: "Files confirmed", .es: "Archivos confirmados"],
        "s.bytes": [.ro: "Date confirmate", .en: "Data confirmed", .es: "Datos confirmados"],
        "s.retried": [.ro: "Reușite la reîncercare", .en: "Succeeded on retry", .es: "Correctos al reintentar"],
        "s.failed": [.ro: "Neconfirmate", .en: "Not confirmed", .es: "No confirmados"],
        "s.skipped": [.ro: "Sărite", .en: "Skipped", .es: "Omitidos"],
        "files": [.ro: "Fișiere", .en: "Files", .es: "Archivos"],
        "files.sample": [.ro: "Sunt afișate %d din %d fișiere: toate problemele și primele rânduri. Lista completă, cu checksum-urile întregi, e în CSV.", .en: "Showing %d of %d files: every problem plus the first rows. The full list, with complete checksums, is in the CSV.", .es: "Se muestran %d de %d archivos: todos los problemas y las primeras filas. La lista completa, con los checksums enteros, está en el CSV."],
        "col.file": [.ro: "Fișier", .en: "File", .es: "Archivo"],
        "col.size": [.ro: "Mărime", .en: "Size", .es: "Tamaño"],
        "col.checksum": [.ro: "Checksum", .en: "Checksum", .es: "Checksum"],
        "col.status": [.ro: "Status", .en: "Status", .es: "Estado"],
        "cs.match": [.ro: "sursă = copie", .en: "source = copy", .es: "origen = copia"],
        "cs.differs": [.ro: "sursă ≠ copie", .en: "source ≠ copy", .es: "origen ≠ copia"],
        "st.ok": [.ro: "Confirmat", .en: "Confirmed", .es: "Confirmado"],
        "st.skip": [.ro: "Sărit", .en: "Skipped", .es: "Omitido"],
        "st.mismatch": [.ro: "Checksum diferit", .en: "Checksum mismatch", .es: "Checksum distinto"],
        "st.error": [.ro: "Eroare", .en: "Error", .es: "Error"],
        "st.retry": [.ro: "la reîncercare", .en: "on retry", .es: "al reintentar"],
        "footer.gen": [.ro: "Generat de DataMover %@ la %@", .en: "Generated by DataMover %@ on %@", .es: "Generado por DataMover %@ el %@"],
        "footer.page": [.ro: "Pagina %d din %d", .en: "Page %d of %d", .es: "Página %d de %d"],
        "footer.basis": [.ro: "Verdictul și cifrele provin din motorul de verificare DataMover pentru această destinație.", .en: "The verdict and figures come from the DataMover verification engine for this destination.", .es: "El veredicto y las cifras proceden del motor de verificación de DataMover para este destino."],
    ]

    func t(_ key: String) -> String { Self.strings[key]?[lang] ?? Self.strings[key]?[.ro] ?? key }

    var verdictTitle: String { t("verdict.\(outcome.rawValue)") }
    var verdictSymbol: String {
        switch outcome { case .verified: return "✓"; case .verifiedWithWarnings: return "!"; case .failed: return "✕"; case .cancelled: return "–" }
    }
    var verdictHelp: String {
        switch outcome {
        case .verified: return String(format: t("help.verified"), okCount)
        case .verifiedWithWarnings: return String(format: t("help.verifiedWithWarnings"), recoveredCount)
        case .failed: return String(format: t("help.failed"), failCount)
        case .cancelled: return t("help.cancelled")
        }
    }

    /// Statusul brut din motor (OK / SARIT / NEPOTRIVIRE / EROARE, opțional „(reîncercat)”),
    /// tradus. CSV-ul păstrează valoarea brută — e contractul lui.
    func statusText(_ raw: String) -> (text: String, kind: String) {
        let retry = raw.contains("reîncercat")
        let base: (String, String)
        if raw.hasPrefix("OK") { base = (t("st.ok"), retry ? "warn" : "ok") }
        else if raw.hasPrefix("SARIT") { base = (t("st.skip"), "skip") }
        else if raw.hasPrefix("NEPOTRIVIRE") { base = (t("st.mismatch"), "fail") }
        else { base = (t("st.error"), "fail") }
        return (retry ? "\(base.0), \(t("st.retry"))" : base.0, base.1)
    }
    static func symbol(forKind kind: String) -> String {
        switch kind { case "ok": return "✓"; case "warn": return "!"; case "skip": return "–"; default: return "✕" }
    }

    func checksumText(_ row: ReportRow) -> String {
        if row.srcHash.isEmpty && row.dstHash.isEmpty { return "—" }
        if !row.srcHash.isEmpty && row.srcHash == row.dstHash { return "\(Self.shortHash(row.srcHash))\n\(t("cs.match"))" }
        return "\(Self.shortHash(row.srcHash.isEmpty ? row.dstHash : row.srcHash))\n\(t("cs.differs"))"
    }
    static func shortHash(_ h: String) -> String { h.count > 16 ? String(h.prefix(16)) + "…" : h }

    // MARK: Formatare deterministă (independentă de localizarea sistemului)

    func bytes(_ b: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = Double(b), i = 0
        while v >= 1000 && i < units.count - 1 { v /= 1000; i += 1 }
        var s = i == 0 ? String(Int(v)) : String(format: "%.1f", v)
        if lang != .en { s = s.replacingOccurrences(of: ".", with: ",") }
        return "\(s) \(units[i])"
    }
    func grouped(_ n: Int64) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        f.groupingSeparator = lang == .en ? "," : "."; f.usesGroupingSeparator = true
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }
    func date(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss xxx"
        return f.string(from: d)
    }
    var duration: String {
        let s = max(0, Int(finishedAt.timeIntervalSince(startedAt).rounded()))
        return String(format: "%02d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    /// Câmpurile de identificare, în ordinea în care le caută un DIT; cele goale lipsesc.
    var detailFields: [(String, String)] {
        var f: [(String, String)] = []
        func add(_ k: String, _ v: String) { if !v.trimmingCharacters(in: .whitespaces).isEmpty { f.append((t(k), v)) } }
        add("f.project", project); add("f.card", card); add("f.source", sourceName)
        add("f.client", client); add("f.operator", operatorName); add("f.camera", camera)
        add("f.started", date(startedAt)); add("f.finished", date(finishedAt)); add("f.duration", duration)
        add("f.verification", verification); add("f.copies", String(copyCount))
        if let mhlFile { add("f.mhl", mhlFile) }
        if let csvFile { add("f.csv", csvFile) }
        add("f.job", jobID)
        return f
    }
    var summaryFields: [(String, String)] {
        var s: [(String, String)] = [
            (t("s.confirmed"), "\(okCount) / \(totalFiles)"),
            (t("s.bytes"), "\(bytes(bytesConfirmed)) (\(grouped(bytesConfirmed)) B)"),
        ]
        if recoveredCount > 0 { s.append((t("s.retried"), String(recoveredCount))) }
        s.append((t("s.failed"), String(failCount)))
        if skipCount > 0 { s.append((t("s.skipped"), String(skipCount))) }
        return s
    }
    var footerLine: String { String(format: t("footer.gen"), appVersion, date(generatedAt)) }
}

// MARK: - HTML (document luminos, gândit pentru ecran și tipar A4)

extension DeliveryReport {
    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static let css = """
    @page { size: A4; margin: 14mm 14mm 16mm; }
    * { box-sizing: border-box; }
    body { margin: 0; background: #F4F5F7; color: #1A1D22; font: 13px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; }
    .doc { max-width: 900px; margin: 24px auto; background: #fff; padding: 36px 40px; border: 1px solid #D5D9DE; }
    .mono { font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; font-size: 12px; }
    header { display: flex; justify-content: space-between; align-items: center; border-bottom: 2px solid #1A1D22; padding-bottom: 10px; }
    .brand { display: flex; align-items: center; gap: 8px; font-weight: 700; letter-spacing: .02em; }
    .brand svg { width: 22px; height: 22px; }
    .kind { font-size: 11px; letter-spacing: .12em; text-transform: uppercase; color: #5B6470; }
    header img { max-height: 40px; max-width: 160px; }
    h1 { font-size: 22px; margin: 18px 0 2px; word-break: break-word; }
    .dest { color: #5B6470; word-break: break-all; margin: 0 0 16px; }
    .verdict { display: grid; grid-template-columns: 44px 1fr; gap: 12px; align-items: center; border: 2px solid currentColor; border-left-width: 8px; padding: 12px 16px; margin: 0 0 18px; }
    .verdict .sym { font-size: 30px; font-weight: 700; text-align: center; line-height: 1; }
    .verdict b { display: block; font-size: 19px; letter-spacing: .04em; }
    .verdict p { margin: 2px 0 0; color: #1A1D22; }
    .v-verified { color: #1F7A45; } .v-verifiedWithWarnings { color: #9A6200; border-style: dashed; } .v-failed { color: #B42318; border-style: double; border-width: 4px 4px 4px 8px; } .v-cancelled { color: #5B6470; border-style: dotted; }
    dl.grid { display: grid; grid-template-columns: 190px 1fr; gap: 4px 16px; margin: 0 0 18px; }
    dl.grid dt { color: #5B6470; } dl.grid dd { margin: 0; word-break: break-word; }
    .summary { display: flex; flex-wrap: wrap; border: 1px solid #D5D9DE; margin: 0 0 22px; }
    .summary div { flex: 1 1 150px; padding: 10px 14px; border-right: 1px solid #D5D9DE; }
    .summary div:last-child { border-right: 0; }
    .summary span { display: block; color: #5B6470; font-size: 11px; text-transform: uppercase; letter-spacing: .06em; }
    .summary b { font-size: 16px; }
    .notes { border-left: 3px solid #B8691F; padding: 6px 12px; white-space: pre-wrap; margin: 0 0 18px; }
    h2 { font-size: 15px; margin: 0 0 6px; }
    .sample { color: #5B6470; margin: 0 0 8px; }
    table { width: 100%; border-collapse: collapse; }
    thead { display: table-header-group; }
    th { text-align: left; font-size: 11px; text-transform: uppercase; letter-spacing: .06em; color: #5B6470; border-bottom: 1.5px solid #1A1D22; padding: 6px 6px; }
    td { border-bottom: 1px solid #E3E6EA; padding: 6px 6px; vertical-align: top; }
    tr { break-inside: avoid; page-break-inside: avoid; }
    td.file { word-break: break-all; }
    td.num { text-align: right; white-space: nowrap; }
    td .sub { color: #5B6470; font-size: 11px; }
    td .err { color: #B42318; font-size: 12px; }
    .st { white-space: nowrap; font-weight: 600; }
    .k-ok { color: #1F7A45; } .k-warn { color: #9A6200; } .k-fail { color: #B42318; } .k-skip { color: #5B6470; }
    footer { margin-top: 22px; padding-top: 10px; border-top: 1px solid #D5D9DE; color: #5B6470; font-size: 11px; }
    @media print { body { background: #fff; } .doc { margin: 0; padding: 0; border: 0; max-width: none; } }
    @media (max-width: 640px) { .doc { padding: 20px 16px; margin: 0; } dl.grid { grid-template-columns: 1fr; } dl.grid dt { margin-top: 6px; } }
    """

    static let markSVG = "<svg viewBox=\"150 150 724 724\" aria-hidden=\"true\"><path d=\"M232 512 H430 C505 512 520 392 598 392 H792 M430 512 C505 512 520 632 598 632 H792\" fill=\"none\" stroke=\"#B8691F\" stroke-width=\"72\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/><circle cx=\"430\" cy=\"512\" r=\"46\" fill=\"#1A1D22\"/></svg>"

    func html(logoDataURI: String? = nil) -> String {
        let E = Self.esc
        var h = "<!doctype html>\n<html lang=\"\(lang.rawValue)\"><head><meta charset=\"utf-8\">"
        h += "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
        h += "<title>\(E(t("doc"))) — \(E(folderName))</title><style>\(Self.css)</style></head><body><div class=\"doc\">"
        h += "<header><div class=\"brand\">\(Self.markSVG)DataMover</div>"
        h += logoDataURI.map { "<img src=\"\($0)\" alt=\"\">" } ?? "<div class=\"kind\">\(E(t("doc")))</div>"
        h += "</header>"
        h += "<h1>\(E(t("doc"))) — \(E(folderName))</h1>"
        h += "<p class=\"dest mono\">\(E(t("destination"))): \(E(destination))</p>"
        h += "<section class=\"verdict v-\(outcome.rawValue)\" role=\"status\"><div class=\"sym\" aria-hidden=\"true\">\(verdictSymbol)</div>"
        h += "<div><b>\(E(verdictTitle))</b><p>\(E(verdictHelp))</p></div></section>"
        h += "<div class=\"summary\">" + summaryFields.map { "<div><span>\(E($0.0))</span><b>\(E($0.1))</b></div>" }.joined() + "</div>"
        h += "<dl class=\"grid\">" + detailFields.map { "<dt>\(E($0.0))</dt><dd>\(E($0.1))</dd>" }.joined() + "</dl>"
        if !notes.isEmpty { h += "<div class=\"notes\"><b>\(E(t("f.notes")))</b>\n\(E(notes))</div>" }
        h += "<h2>\(E(t("files"))) (\(totalFiles))</h2>"
        if isTruncated { h += "<p class=\"sample\">\(E(String(format: t("files.sample"), rows.count, totalFiles)))</p>" }
        h += "<table><thead><tr><th>#</th><th>\(E(t("col.file")))</th><th>\(E(t("col.size")))</th><th>\(E(t("col.checksum")))</th><th>\(E(t("col.status")))</th></tr></thead><tbody>"
        for (i, row) in rows.enumerated() {
            let st = statusText(row.status)
            h += "<tr><td class=\"num\">\(i + 1)</td><td class=\"file mono\">\(E(row.file))"
            if let m = mediaLine?(row), !m.isEmpty { h += "<div class=\"sub\">\(E(m))</div>" }
            if !row.error.isEmpty { h += "<div class=\"err\">\(E(row.error))</div>" }
            h += "</td><td class=\"num\">\(E(bytes(row.sizeBytes)))</td><td class=\"mono\">\(E(checksumText(row)).replacingOccurrences(of: "\n", with: "<br>"))</td>"
            h += "<td class=\"st k-\(st.kind)\">\(Self.symbol(forKind: st.kind)) \(E(st.text))</td></tr>"
        }
        h += "</tbody></table>"
        h += "<footer>\(E(footerLine))<br>\(E(t("footer.basis")))</footer></div></body></html>\n"
        return h
    }
}

// MARK: - PDF (CoreText, A4, paginare în două treceri)

extension DeliveryReport {
    private struct Palette {
        static let ink = NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1)
        static let dim = NSColor(srgbRed: 0.36, green: 0.39, blue: 0.44, alpha: 1)
        static let rule = NSColor(srgbRed: 0.84, green: 0.85, blue: 0.87, alpha: 1)
        static let band = NSColor(srgbRed: 0.965, green: 0.97, blue: 0.975, alpha: 1)
        static let amber = NSColor(srgbRed: 0.72, green: 0.41, blue: 0.12, alpha: 1)
        static let ok = NSColor(srgbRed: 0.12, green: 0.48, blue: 0.27, alpha: 1)
        static let warn = NSColor(srgbRed: 0.60, green: 0.38, blue: 0.0, alpha: 1)
        static let fail = NSColor(srgbRed: 0.71, green: 0.14, blue: 0.09, alpha: 1)
    }
    private func color(forKind k: String) -> NSColor {
        switch k { case "ok": return Palette.ok; case "warn": return Palette.warn; case "fail": return Palette.fail; default: return Palette.dim }
    }
    private var verdictColor: NSColor {
        switch outcome { case .verified: return Palette.ok; case .verifiedWithWarnings: return Palette.warn; case .failed: return Palette.fail; case .cancelled: return Palette.dim }
    }

    private static func attr(_ s: String, _ size: CGFloat, bold: Bool = false, mono: Bool = false, color: NSColor = Palette.ink, align: NSTextAlignment = .left) -> NSAttributedString {
        let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .semibold : .regular)
                        : NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular)
        let p = NSMutableParagraphStyle(); p.alignment = align; p.lineBreakMode = mono ? .byCharWrapping : .byWordWrapping; p.lineSpacing = 1
        return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
    }
    private static func height(_ a: NSAttributedString, width: CGFloat) -> CGFloat {
        let fs = CTFramesetterCreateWithAttributedString(a)
        let s = CTFramesetterSuggestFrameSizeWithConstraints(fs, CFRange(), nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        return ceil(s.height)
    }
    /// Desenează textul cu marginea de sus la `top` (coordonate PDF, originea jos) și întoarce înălțimea.
    @discardableResult
    private static func draw(_ a: NSAttributedString, in ctx: CGContext, x: CGFloat, top: CGFloat, width: CGFloat) -> CGFloat {
        let h = height(a, width: width)
        let fs = CTFramesetterCreateWithAttributedString(a)
        let path = CGPath(rect: CGRect(x: x, y: top - h, width: width, height: h + 1), transform: nil)
        CTFrameDraw(CTFramesetterCreateFrame(fs, CFRange(), path, nil), ctx)
        return h
    }

    func writePDF(to path: String, logo: CGImage? = nil) -> (ok: Bool, error: String?) {
        let W: CGFloat = 595, H: CGFloat = 842, M: CGFloat = 42
        let contentW = W - 2 * M
        let headerBottom = H - M - 30, footerTop = M + 34
        // Coloane tabel: # | fișier | mărime | checksum | status
        let cols: [CGFloat] = [22, 200, 54, 142, contentW - 22 - 200 - 54 - 142]
        let pad: CGFloat = 4

        // Rânduri pregătite (text + înălțime) — aceleași în ambele treceri.
        struct Row { let cells: [NSAttributedString]; let height: CGFloat }
        let tableHead = [ "#", t("col.file"), t("col.size"), t("col.checksum"), t("col.status") ]
            .map { Self.attr($0.uppercased(), 7, bold: true, color: Palette.dim) }
        let headH: CGFloat = 16
        let rowsPrepared: [Row] = rows.enumerated().map { i, r in
            let st = statusText(r.status)
            let file = NSMutableAttributedString(attributedString: Self.attr(r.file, 7.5, mono: true))
            if let m = mediaLine?(r), !m.isEmpty { file.append(Self.attr("\n" + m, 7, color: Palette.dim)) }
            if !r.error.isEmpty { file.append(Self.attr("\n" + r.error, 7, color: Palette.fail)) }
            let cells = [
                Self.attr(String(i + 1), 7.5, color: Palette.dim, align: .right),
                file,
                Self.attr(bytes(r.sizeBytes), 7.5, align: .right),
                Self.attr(checksumText(r), 7, mono: true),
                Self.attr("\(Self.symbol(forKind: st.kind)) \(st.text)", 7.5, bold: true, color: color(forKind: st.kind)),
            ]
            let h = zip(cells, cols).map { Self.height($0, width: $1 - 2 * pad) }.max() ?? 10
            return Row(cells: cells, height: h + 2 * pad + 1)
        }

        // Blocul de deschidere (doar pagina 1).
        let title = Self.attr("\(t("doc")) — \(folderName)", 17, bold: true)
        let dest = Self.attr("\(t("destination")): \(destination)", 8, mono: true, color: Palette.dim)
        let vTitle = Self.attr(verdictTitle, 15, bold: true, color: verdictColor)
        let vHelp = Self.attr(verdictHelp, 9)
        let vSym = Self.attr(verdictSymbol, 26, bold: true, color: verdictColor, align: .center)
        let labelW: CGFloat = 150
        let details = detailFields.map { (Self.attr($0.0, 8.5, color: Palette.dim), Self.attr($0.1, 8.5, mono: $0.0 == t("f.job") || $0.0 == t("f.mhl") || $0.0 == t("f.csv"))) }
        let notesA = notes.isEmpty ? nil : Self.attr("\(t("f.notes")): \(notes)", 8.5)
        let sample = isTruncated ? Self.attr(String(format: t("files.sample"), rows.count, totalFiles), 8, color: Palette.dim) : nil
        let vInner = contentW - 16 - 44 - 12
        let verdictH = max(44, Self.height(vTitle, width: vInner) + 4 + Self.height(vHelp, width: vInner)) + 20
        let summaryH: CGFloat = 40
        let detailsH = details.reduce(CGFloat(0)) { $0 + max(Self.height($1.0, width: labelW), Self.height($1.1, width: contentW - labelW)) + 3 }
        var introH = Self.height(title, width: contentW) + 4 + Self.height(dest, width: contentW) + 14 + verdictH + 12 + summaryH + 14 + detailsH + 10
        if let notesA { introH += Self.height(notesA, width: contentW - 12) + 12 }
        let filesTitle = Self.attr("\(t("files")) (\(totalFiles))", 11, bold: true)
        introH += Self.height(filesTitle, width: contentW) + 4 + (sample.map { Self.height($0, width: contentW) + 4 } ?? 0)

        // Trecerea 1: împărțirea rândurilor pe pagini.
        var pages: [[Int]] = [[]]
        var avail = headerBottom - footerTop - introH - headH
        for (i, r) in rowsPrepared.enumerated() {
            if r.height > avail && !(pages.last!.isEmpty && pages.count > 1) {
                pages.append([]); avail = headerBottom - footerTop - 10 - headH
            }
            pages[pages.count - 1].append(i); avail -= r.height
        }
        let total = pages.count

        var box = CGRect(x: 0, y: 0, width: W, height: H)
        guard let consumer = CGDataConsumer(url: URL(fileURLWithPath: path) as CFURL) else {
            return (false, "CGDataConsumer nu a putut fi creat pentru \"\(path)\" - verifica daca folderul de destinatie mai exista si daca discul nu e plin.")
        }
        let info: [CFString: Any] = [kCGPDFContextTitle: "\(t("doc")) — \(folderName)", kCGPDFContextCreator: "DataMover \(appVersion)"]
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary) else {
            return (false, "CGContext nu a putut fi creat pentru raportul PDF - cauza necunoscuta, posibil memorie insuficienta.")
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        func rule(_ y: CGFloat, _ c: NSColor = Palette.rule, _ w: CGFloat = 0.6) {
            ctx.setStrokeColor(c.cgColor); ctx.setLineWidth(w)
            ctx.move(to: CGPoint(x: M, y: y)); ctx.addLine(to: CGPoint(x: W - M, y: y)); ctx.strokePath()
        }
        func pageChrome(_ n: Int) {
            // Semnul „Verified Signal Split” + numele.
            ctx.saveGState()
            // viewBox SVG 150…874 → pătrat de 16 pt în colțul stâng sus (y SVG crește în jos).
            let s: CGFloat = 20 / 724, top = H - M + 2
            let p = CGMutablePath()
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: M + (x - 150) * s, y: top - (y - 150) * s) }
            p.move(to: pt(232, 512)); p.addLine(to: pt(430, 512))
            p.addCurve(to: pt(598, 392), control1: pt(505, 512), control2: pt(520, 392)); p.addLine(to: pt(792, 392))
            p.move(to: pt(430, 512)); p.addCurve(to: pt(598, 632), control1: pt(505, 512), control2: pt(520, 632)); p.addLine(to: pt(792, 632))
            ctx.addPath(p); ctx.setStrokeColor(Palette.amber.cgColor); ctx.setLineWidth(2.0); ctx.setLineCap(.round); ctx.strokePath()
            ctx.setFillColor(Palette.ink.cgColor); ctx.fillEllipse(in: CGRect(x: pt(430, 512).x - 2.6, y: pt(430, 512).y - 2.6, width: 5.2, height: 5.2))
            ctx.restoreGState()
            Self.draw(Self.attr("DataMover", 10, bold: true), in: ctx, x: M + 27, top: H - M - 2, width: 120)
            if let logo, n == 1 {
                let r = min(110 / CGFloat(logo.width), 26 / CGFloat(logo.height))
                let w = CGFloat(logo.width) * r, h = CGFloat(logo.height) * r
                ctx.draw(logo, in: CGRect(x: W - M - w, y: H - M - h - 2, width: w, height: h))
            } else {
                Self.draw(Self.attr(t("doc").uppercased(), 7.5, bold: true, color: Palette.dim, align: .right), in: ctx, x: W - M - 220, top: H - M, width: 220)
            }
            rule(headerBottom + 6, Palette.ink, 1.2)
            rule(footerTop - 4)
            Self.draw(Self.attr(footerLine, 7, color: Palette.dim), in: ctx, x: M, top: footerTop - 10, width: contentW - 90)
            Self.draw(Self.attr(t("footer.basis"), 7, color: Palette.dim), in: ctx, x: M, top: footerTop - 20, width: contentW - 90)
            Self.draw(Self.attr(String(format: t("footer.page"), n, total), 7.5, bold: true, color: Palette.dim, align: .right), in: ctx, x: W - M - 90, top: footerTop - 10, width: 90)
        }
        func tableHeader(_ top: CGFloat) -> CGFloat {
            ctx.setFillColor(Palette.band.cgColor); ctx.fill(CGRect(x: M, y: top - headH, width: contentW, height: headH))
            var x = M
            for (a, w) in zip(tableHead, cols) { Self.draw(a, in: ctx, x: x + pad, top: top - 5, width: w - 2 * pad); x += w }
            rule(top - headH, Palette.ink, 0.9)
            return top - headH
        }

        for (pi, idx) in pages.enumerated() {
            ctx.beginPDFPage(nil)
            pageChrome(pi + 1)
            var y = headerBottom - 4
            if pi == 0 {
                y -= Self.draw(title, in: ctx, x: M, top: y, width: contentW) + 4
                y -= Self.draw(dest, in: ctx, x: M, top: y, width: contentW) + 14
                // Verdict: bordură în culoarea verdictului + simbol și cuvânt (lizibil și alb-negru).
                let vr = CGRect(x: M, y: y - verdictH, width: contentW, height: verdictH)
                ctx.setStrokeColor(verdictColor.cgColor); ctx.setLineWidth(outcome == .failed ? 2.4 : 1.4)
                if outcome == .verifiedWithWarnings { ctx.setLineDash(phase: 0, lengths: [5, 3]) }
                if outcome == .cancelled { ctx.setLineDash(phase: 0, lengths: [1.5, 2.5]) }
                ctx.stroke(vr.insetBy(dx: 0.7, dy: 0.7)); ctx.setLineDash(phase: 0, lengths: [])
                ctx.setFillColor(verdictColor.cgColor); ctx.fill(CGRect(x: M, y: vr.minY, width: 6, height: verdictH))
                Self.draw(vSym, in: ctx, x: M + 12, top: y - (verdictH - 30) / 2, width: 44)
                var vy = y - 10
                vy -= Self.draw(vTitle, in: ctx, x: M + 68, top: vy, width: vInner) + 4
                Self.draw(vHelp, in: ctx, x: M + 68, top: vy, width: vInner)
                y -= verdictH + 12
                // Rezumat numeric.
                let sf = summaryFields, cw = contentW / CGFloat(sf.count)
                ctx.setStrokeColor(Palette.rule.cgColor); ctx.setLineWidth(0.6); ctx.stroke(CGRect(x: M, y: y - summaryH, width: contentW, height: summaryH))
                for (i, f) in sf.enumerated() {
                    let x = M + CGFloat(i) * cw
                    if i > 0 { ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: CGPoint(x: x, y: y - summaryH)); ctx.strokePath() }
                    Self.draw(Self.attr(f.0.uppercased(), 6.5, bold: true, color: Palette.dim), in: ctx, x: x + 8, top: y - 7, width: cw - 12)
                    Self.draw(Self.attr(f.1, 9.5, bold: true), in: ctx, x: x + 8, top: y - 20, width: cw - 12)
                }
                y -= summaryH + 14
                for (l, v) in details {
                    let h = max(Self.height(l, width: labelW), Self.height(v, width: contentW - labelW))
                    Self.draw(l, in: ctx, x: M, top: y, width: labelW); Self.draw(v, in: ctx, x: M + labelW, top: y, width: contentW - labelW)
                    y -= h + 3
                }
                y -= 10
                if let notesA {
                    ctx.setFillColor(Palette.amber.cgColor)
                    let h = Self.height(notesA, width: contentW - 12)
                    ctx.fill(CGRect(x: M, y: y - h, width: 2.5, height: h))
                    Self.draw(notesA, in: ctx, x: M + 12, top: y, width: contentW - 12); y -= h + 12
                }
                y -= Self.draw(filesTitle, in: ctx, x: M, top: y, width: contentW) + 4
                if let sample { y -= Self.draw(sample, in: ctx, x: M, top: y, width: contentW) + 4 }
            } else { y -= 6 }
            if !idx.isEmpty || pi == 0 { y = tableHeader(y) }
            for i in idx {
                let r = rowsPrepared[i]
                var x = M
                for (a, w) in zip(r.cells, cols) { Self.draw(a, in: ctx, x: x + pad, top: y - pad, width: w - 2 * pad); x += w }
                y -= r.height
                rule(y)
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return (true, nil)
    }
}
