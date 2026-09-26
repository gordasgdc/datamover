import Foundation
import AppKit
import CoreText

// MARK: - Raport PDF (CoreGraphics, fara dependinte externe)

func writePDFReport(path: String, destination: String, folderName: String, rows: [ReportRow],
                             startedAt: Date, finishedAt: Date, okCount: Int, skipCount: Int,
                             failCount: Int, cancelled: Bool, verificationLabel: String,
                             meta: ProductionMeta = ProductionMeta(), recoveredCount: Int = 0,
                             mhlPath: String? = nil,
                             truncatedNote: String? = nil) -> (ok: Bool, error: String?) {
    let pageWidth: CGFloat = 595 // A4 @ 72dpi
    let pageHeight: CGFloat = 842
    let margin: CGFloat = 40
    var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

    // FIX VIZIBILITATE (2026-08-30, raportat de Cristi: "PDF-ul nu se
    // creeaza") - pana acum, daca CGDataConsumer/CGContext esuau, functia
    // intorcea `false` FARA niciun motiv, la fel ca bug-ul deja documentat
    // si reparat pe Windows (QuestPDF/ARM64, v2.7.0) - CSV-ul (scris cu
    // FileHandle simplu) reuseste mereu, deci userul vede doar checkpoint +
    // CSV si crede ca PDF-ul "nu porneste", fara niciun indiciu de ce.
    // Motive reale posibile aici: folder de destinatie sters/deconectat
    // intre timp (disc extern), spatiu insuficient pe disc, sau un
    // caracter din cale pe care CFURL nu il accepta.
    guard let consumer = CGDataConsumer(url: URL(fileURLWithPath: path) as CFURL) else {
        return (false, "CGDataConsumer nu a putut fi creat pentru \"\(path)\" - verifica daca folderul de destinatie mai exista si daca discul nu e plin.")
    }
    guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        return (false, "CGContext nu a putut fi creat pentru raportul PDF (dupa ce fisierul consumer a fost deschis cu succes) - cauza necunoscuta, posibil memorie insuficienta.")
    }

    var y: CGFloat = pageHeight - margin

    func newPage() { ctx.beginPDFPage(nil); y = pageHeight - margin }
    func draw(_ text: String, size: CGFloat = 10, bold: Bool = false, color: NSColor = .black, x: CGFloat = margin) {
        if y < margin + size { ctx.endPDFPage(); newPage() }
        let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let line = CTLineCreateWithAttributedString(attr)
        ctx.saveGState()
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
    /// Trunchiaza un text la un numar aproximativ de caractere care incap
    /// intr-o coloana, adaugand "..." — simplu, fara masurare exacta de
    /// glife (suficient pentru un raport monospace-friendly).
    func truncate(_ s: String, maxChars: Int) -> String {
        guard s.count > maxChars else { return s }
        return String(s.prefix(maxChars - 1)) + "…"
    }

    // [M4, 2026-09-06] Randuri "DIT" - thumbnail + metadate video + status
    // Pass/Fail colorat, in loc de tabelul text simplu de pana acum.
    let thumbW: CGFloat = 60, thumbH: CGFloat = 34
    let textX = margin + thumbW + 10
    let rowHeight: CGFloat = thumbH + 12 // spatiu pentru thumbnail + cele 2-3 linii de text

    func drawTableHeader() {
        let headerY = y
        ctx.saveGState()
        ctx.setFillColor(NSColor(white: 0.9, alpha: 1).cgColor)
        ctx.fill(CGRect(x: margin - 4, y: headerY - 3, width: pageWidth - 2 * margin + 8, height: 13))
        ctx.restoreGState()
        draw("Fisier / metadate / MHL", size: 8, bold: true, x: textX)
        y -= 15
    }

    /// Fundalul colorat al bulinei de status (Pass/Fail) - verde pentru
    /// orice varianta de OK (inclusiv "OK (reîncercat)"), rosu altfel.
    func statusBadgeColor(_ status: String) -> NSColor {
        status.hasPrefix("OK") ? NSColor.systemGreen : (status == "SARIT" ? NSColor.systemGray : NSColor.systemRed)
    }

    let df = DateFormatter(); df.dateFormat = "yyyy-MM-dd HH:mm:ss"

    newPage()

    // [2026-09-03] Antet brandat: logo-ul productiei (daca e configurat) in
    // dreapta sus, langa titlu. Un raport care ajunge la client trebuie sa
    // arate ca vine de la o firma, nu dintr-un utilitar generic.
    if !meta.logoPath.isEmpty,
       let image = NSImage(contentsOfFile: meta.logoPath),
       let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        let maxW: CGFloat = 120, maxH: CGFloat = 46
        let ratio = min(maxW / CGFloat(cgImage.width), maxH / CGFloat(cgImage.height))
        let w = CGFloat(cgImage.width) * ratio, h = CGFloat(cgImage.height) * ratio
        ctx.draw(cgImage, in: CGRect(x: pageWidth - margin - w, y: y - h + 12, width: w, height: h))
    }

    draw("Raport offload — \(folderName)", size: 16, bold: true); y -= 20
    draw("Destinatie: \(destination)", size: 10); y -= 16
    // Campurile de productie completate de user (Client, Camera, Operator…)
    // — vezi ProductionMeta.headerFields(): cele goale nu se deseneaza.
    let brandingFields = meta.headerFields()
    if !brandingFields.isEmpty {
        draw(brandingFields.map { "\($0.0): \($0.1)" }.joined(separator: "   |   "), size: 10)
        y -= 16
    }
    draw("Inceput: \(df.string(from: startedAt))   Finalizat: \(df.string(from: finishedAt))", size: 10); y -= 16
    draw("Model verificare: \(verificationLabel)", size: 10); y -= 16
    if let mhlPath {
        draw("MHL: \((mhlPath as NSString).lastPathComponent)", size: 10); y -= 16
    }
    var summary = "OK: \(okCount)   Sarite: \(skipCount)   Probleme: \(failCount)"
    if recoveredCount > 0 { summary += "   Recuperate la reincercare: \(recoveredCount)" }
    draw(summary + (cancelled ? "   (ANULAT)" : ""),
         size: 10, bold: true, color: failCount > 0 || cancelled ? .systemRed : .systemGreen)
    y -= 16
    if !meta.notes.isEmpty {
        draw("Note: " + truncate(meta.notes, maxChars: 110), size: 9, color: .darkGray)
        y -= 14
    }
    if let note = truncatedNote {
        draw(note, size: 8, color: .darkGray)
        y -= 10
    }
    y -= 16

    drawTableHeader()
    for (index, row) in rows.enumerated() {
        if y < margin + rowHeight {
            ctx.endPDFPage(); newPage()
            drawTableHeader()
        }
        let rowTop = y
        if index % 2 == 0 {
            ctx.saveGState()
            ctx.setFillColor(NSColor(white: 0.96, alpha: 1).cgColor)
            ctx.fill(CGRect(x: margin - 4, y: rowTop - rowHeight + 4, width: pageWidth - 2 * margin + 8, height: rowHeight))
            ctx.restoreGState()
        }

        // Thumbnail — extras DOAR la generarea raportului (nu in timpul
        // transferului), pe eșantionul deja plafonat (max. 500 rânduri) —
        // motorul de copiere (FanOutCopier) ramane complet neatins.
        let thumbRect = CGRect(x: margin, y: rowTop - rowHeight + 6, width: thumbW, height: thumbH)
        if let image = MediaInspector.thumbnailImage(path: row.destPath, size: CGSize(width: thumbW * 2, height: thumbH * 2)),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            ctx.draw(cgImage, in: thumbRect)
        } else {
            ctx.saveGState()
            ctx.setFillColor(NSColor(white: 0.88, alpha: 1).cgColor)
            ctx.fill(thumbRect)
            ctx.restoreGState()
        }

        // Bulina de status Pass/Fail (MHL), colorata, langa numele fisierului.
        let badgeColor = statusBadgeColor(row.status)
        ctx.saveGState()
        ctx.setFillColor(badgeColor.cgColor)
        ctx.fillEllipse(in: CGRect(x: textX, y: rowTop - 9, width: 6, height: 6))
        ctx.restoreGState()

        y = rowTop - 1
        draw(truncate(row.file, maxChars: 46), size: 9, bold: true, x: textX + 10)
        draw(row.status, size: 8, color: badgeColor, x: pageWidth - margin - 90)
        y -= 12

        let media = MediaInspector.probe(path: row.destPath)
        var metaParts: [String] = [formatBytes(row.sizeBytes)]
        if let m = media {
            if let r = m.resolutionText { metaParts.append(r) }
            if let fps = m.frameRate { metaParts.append(String(format: "%.2f fps", fps)) }
            if let codec = m.videoCodec { metaParts.append(codec) }
            if let tc = m.timecode { metaParts.append("TC \(tc)") }
            if let ch = m.audioChannels { metaParts.append("\(ch)ch audio") }
        }
        draw(metaParts.joined(separator: "  ·  "), size: 8, color: .darkGray, x: textX + 10)
        y -= 12

        if !row.error.isEmpty {
            draw(truncate(row.error, maxChars: 70), size: 8, color: .systemRed, x: textX + 10)
        }

        y = rowTop - rowHeight
    }
    ctx.endPDFPage()
    ctx.closePDF()
    return (true, nil)
}
