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
    /// Logo-ul producției, încorporat ca data URI în raportul HTML (DeliveryReport),
    /// ca raportul să rămână complet și când e trimis pe email sau mutat.
    static func logoDataURI(_ path: String) -> String? {
        guard !path.isEmpty, let data = FileManager.default.contents(atPath: path) else { return nil }
        // Limita de bun-simt: un logo de zeci de MB ar umfla fiecare raport.
        guard data.count <= 3 * 1024 * 1024 else { return nil }
        let ext = (path as NSString).pathExtension.lowercased()
        let mime = (ext == "jpg" || ext == "jpeg") ? "image/jpeg" : (ext == "gif" ? "image/gif" : "image/png")
        return "data:\(mime);base64,\(data.base64EncodedString())"
    }
}
