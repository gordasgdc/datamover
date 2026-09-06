import Foundation
import AppKit
import QuickLookThumbnailing

/// [2026-09-03] Metadatele productiei, atasate unui transfer.
///
/// DE CE: raportul unui offload nu e un log tehnic, e un DOCUMENT DE
/// PREDARE — ajunge la producator, la casa de post, uneori la asigurator.
/// Un raport care spune doar "1240 fisiere OK" nu identifica NIMIC: nu se
/// stie al cui e proiectul, cine a facut descarcarea, de pe ce camera, in
/// ce zi de filmare. Ofloaderele profesionale pun toate astea in antetul
/// raportului, cu logo-ul companiei — de aceea raportul lor poate fi
/// trimis mai departe ca atare, iar al nostru trebuia rescris manual.
///
/// Aceleasi campuri alimenteaza si sablonul de denumire a folderelor
/// (vezi NamingTemplate) — se completeaza o singura data.
struct ProductionMeta: Equatable {
    var project = ""
    var card = ""
    var client = ""
    var operatorName = ""
    var camera = ""
    var notes = ""
    /// Cale catre un fisier imagine (PNG/JPG) folosit ca logo in antetul
    /// rapoartelor. Gol = fara logo, raportul ramane la fel de valid.
    var logoPath = ""

    var hasAnyBranding: Bool {
        !(client.isEmpty && operatorName.isEmpty && camera.isEmpty && notes.isEmpty && logoPath.isEmpty)
    }

    /// Perechile completate, gata de afisat in antetul unui raport.
    /// Campurile goale NU apar deloc — un raport cu "Client: —" arata
    /// neterminat, nu profesional.
    func headerFields() -> [(String, String)] {
        var fields: [(String, String)] = []
        if !project.isEmpty { fields.append(("Proiect", project)) }
        if !client.isEmpty { fields.append(("Client", client)) }
        if !card.isEmpty { fields.append(("Card", card)) }
        if !camera.isEmpty { fields.append(("Cameră", camera)) }
        if !operatorName.isEmpty { fields.append(("Operator / DIT", operatorName)) }
        return fields
    }
}

/// Raport HTML — a doua forma a aceluiasi raport, alaturi de CSV si PDF.
///
/// DE CE HTML pe langa PDF: se deschide in orice browser, pe orice
/// telefon, fara cititor de PDF, si poate fi trimis pe WhatsApp/email ca
/// link sau atasament fara sa-si piarda formatarea. Casele de post cer
/// frecvent exact asta pentru confirmarea rapida a unei descarcari, iar
/// PDF-ul ramane pentru arhiva.
enum HTMLReport {
    static func write(path: String, destination: String, folderName: String, rows: [ReportRow],
                      meta: ProductionMeta, startedAt: Date, finishedAt: Date,
                      okCount: Int, skipCount: Int, failCount: Int, recoveredCount: Int,
                      cancelled: Bool, verificationLabel: String, mhlPath: String?,
                      truncatedNote: String?) -> Bool {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var html = """
        <!doctype html>
        <html lang="ro"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Raport offload — \(escape(folderName))</title>
        <style>
        :root { color-scheme: dark; }
        body { margin:0; padding:24px; background:#14161A; color:#EDEFF2;
               font: 14px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
        .wrap { max-width: 1100px; margin: 0 auto; }
        header { display:flex; align-items:center; gap:16px; border-bottom:1px solid #2A2F36; padding-bottom:16px; }
        header img { max-height:56px; max-width:200px; }
        h1 { font-size:20px; margin:0 0 4px; }
        .sub { color:#9AA3AE; font-size:13px; }
        .meta { display:grid; grid-template-columns:repeat(auto-fit,minmax(200px,1fr)); gap:8px 24px; margin:18px 0; }
        .meta div span { color:#9AA3AE; display:block; font-size:11px; text-transform:uppercase; letter-spacing:.04em; }
        .cards { display:flex; flex-wrap:wrap; gap:12px; margin:18px 0; }
        .card { background:#1A1D22; border:1px solid #2A2F36; border-radius:8px; padding:12px 16px; min-width:110px; }
        .card b { display:block; font-size:22px; }
        .ok b { color:#4ADE80; } .skip b { color:#9AA3AE; } .fail b { color:#F87171; } .rec b { color:#D08C40; }
        .notes { background:#1A1D22; border-left:3px solid #D08C40; padding:10px 14px; border-radius:4px; white-space:pre-wrap; }
        table { width:100%; border-collapse:collapse; margin-top:16px; font-size:12px; }
        th { text-align:left; color:#9AA3AE; font-weight:600; border-bottom:1px solid #2A2F36; padding:6px 8px; }
        td { padding:6px 8px; border-bottom:1px solid #20242A; word-break:break-all; }
        td .thumb { display:block; width:64px; max-width:100%; height:36px; object-fit:cover; border-radius:4px; border:1px solid #2A2F36; }
        .s-ok { color:#4ADE80; } .s-fail { color:#F87171; } .s-skip { color:#9AA3AE; }
        footer { margin-top:24px; color:#6B737D; font-size:11px; }
        @media (max-width:700px){ body{padding:14px} table{font-size:11px} }
        </style></head><body><div class="wrap">
        """

        html += "<header>"
        if let logo = logoDataURI(meta.logoPath) {
            html += "<img src=\"\(logo)\" alt=\"logo\">"
        }
        html += "<div><h1>Raport de descărcare (offload)</h1>"
        html += "<div class=\"sub\">\(escape(folderName)) → \(escape(destination))</div></div></header>"

        html += "<div class=\"meta\">"
        for (label, value) in meta.headerFields() {
            html += "<div><span>\(escape(label))</span>\(escape(value))</div>"
        }
        html += "<div><span>Început</span>\(df.string(from: startedAt))</div>"
        html += "<div><span>Terminat</span>\(df.string(from: finishedAt))</div>"
        html += "<div><span>Verificare</span>\(escape(verificationLabel))</div>"
        if let mhlPath {
            html += "<div><span>MHL</span>\(escape((mhlPath as NSString).lastPathComponent))</div>"
        }
        html += "</div>"

        html += "<div class=\"cards\">"
        html += "<div class=\"card ok\"><b>\(okCount)</b>copiate OK</div>"
        html += "<div class=\"card skip\"><b>\(skipCount)</b>sărite</div>"
        html += "<div class=\"card fail\"><b>\(failCount)</b>probleme</div>"
        if recoveredCount > 0 {
            html += "<div class=\"card rec\"><b>\(recoveredCount)</b>recuperate la reîncercare</div>"
        }
        html += "</div>"

        if cancelled {
            html += "<p class=\"s-fail\"><b>Transfer anulat de utilizator — lista de mai jos nu este completă.</b></p>"
        }
        if !meta.notes.isEmpty {
            html += "<div class=\"notes\">\(escape(meta.notes))</div>"
        }

        // [2026-09-06] "Sursă"/"Destinație" era un nume gresit - coloanele
        // arata de fapt hash-urile de verificare (srcHash/dstHash), nu caile
        // fisierelor (calea completa nu era retinuta separat de `file`,
        // care e deja calea relativa afisata in prima coloana).
        html += "<table><thead><tr><th></th><th>Fișier</th><th>Mărime</th><th>Hash sursă</th><th>Hash destinație</th><th>Status</th><th>Eroare</th></tr></thead><tbody>"
        for row in rows {
            let cls = row.status.hasPrefix("OK") ? "s-ok" : (row.status.hasPrefix("SARIT") ? "s-skip" : "s-fail")
            let thumbCell = thumbnailDataURI(path: row.destPath).map { "<img class=\"thumb\" src=\"\($0)\">" } ?? ""
            html += "<tr><td>\(thumbCell)</td><td>\(escape(row.file))</td><td>\(formatBytes(row.sizeBytes))</td>"
            html += "<td>\(escape(short(row.srcHash)))</td><td>\(escape(short(row.dstHash)))</td>"
            html += "<td class=\"\(cls)\">\(escape(row.status))</td><td>\(escape(row.error))</td></tr>"
        }
        html += "</tbody></table>"

        if let truncatedNote {
            html += "<p class=\"sub\">\(escape(truncatedNote))</p>"
        }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        html += "<footer>Generat de DataMover \(escape(version)) — gordas.dev</footer>"
        html += "</div></body></html>"

        do {
            try html.write(toFile: path, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    /// Logo-ul se INCORPOREAZA in HTML ca data URI. Un `<img src="fisier">`
    /// ar functiona doar cat timp raportul sta langa imaginea originala —
    /// exact ce nu se intampla cand raportul e trimis pe email sau mutat.
    private static func logoDataURI(_ path: String) -> String? {
        guard !path.isEmpty, let data = FileManager.default.contents(atPath: path) else { return nil }
        // Limita de bun-simt: un logo de zeci de MB ar umfla fiecare raport.
        guard data.count <= 3 * 1024 * 1024 else { return nil }
        let ext = (path as NSString).pathExtension.lowercased()
        let mime = (ext == "jpg" || ext == "jpeg") ? "image/jpeg" : (ext == "gif" ? "image/gif" : "image/png")
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    /// [2026-09-06] Thumbnail real per fisier, cerut de Cristi dupa ce a
    /// vazut cat de bine arata cele din raportul CG Convertor ("arata
    /// foarte pro"). Foloseste QLThumbnailGenerator (framework de sistem
    /// macOS, ZERO dependinta noua — DataMover ramane fara FFmpeg/librarii
    /// grele, spre deosebire de CGConvertor) — genereaza o previzualizare
    /// reala a CONTINUTULUI (cadru de video, pagina 1 de PDF, imaginea
    /// insasi), nu doar iconita generica de tip de fisier. API-ul e
    /// asincron; `writeReports` ruleaza deja pe un thread de fundal
    /// (Regula 21 — offload-ul intreg e background), deci blocam scurt cu
    /// un semafor, per fisier, fara sa afectam UI-ul principal.
    private static func thumbnailDataURI(path: String) -> String? {
        guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else { return nil }
        let size = CGSize(width: 160, height: 90)
        let request = QLThumbnailGenerator.Request(fileAt: URL(fileURLWithPath: path),
                                                     size: size, scale: 2,
                                                     representationTypes: .thumbnail)
        let semaphore = DispatchSemaphore(value: 0)
        var jpegData: Data?
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            defer { semaphore.signal() }
            guard let representation else { return }
            let image = NSImage(cgImage: representation.cgImage, size: size)
            guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return }
            jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.6])
        }
        // Plafon de asteptare: un fisier corupt/blocat nu trebuie sa
        // inghete generarea raportului la nesfarsit.
        _ = semaphore.wait(timeout: .now() + 3)
        guard let jpegData else { return nil }
        return "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
    }

    private static func short(_ hash: String) -> String {
        hash.count > 20 ? String(hash.prefix(20)) + "…" : hash
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
