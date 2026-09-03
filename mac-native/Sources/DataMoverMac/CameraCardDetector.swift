import Foundation

/// [2026-09-03] Recunoasterea structurii unui card de cameră.
///
/// DE CE: un card nu e un folder oarecare. Fiecare cameră isi scrie
/// materialul dupa o structura proprie, iar greselile clasice de pe platou
/// sunt mereu aceleasi doua:
///  1. operatorul selecteaza un SUBFOLDER (ex. doar `CLIP`) si lasa in urma
///     metadatele fara de care materialul nu se mai poate reasambla in post;
///  2. cardul e defect/scos prea devreme si contine clipuri incomplete sau
///     fisiere de 0 octeti, iar asta se descopera abia in post, cand
///     cardul a fost deja reformatat.
/// Un ofloader profesional recunoaste tipul cardului si avertizeaza INAINTE
/// de copiere. Detectia e pur informativa — nu blocheaza niciodata
/// transferul, doar spune userului ce vede.
struct CameraCardInfo {
    let cardType: String
    /// Numarul de clipuri/fisiere media identificate (nil daca tipul de
    /// card nu permite o numaratoare sigura).
    let clipCount: Int?
    /// Probleme gasite la o inspectie superficiala (fara sa citim
    /// continutul fisierelor) — text gata de afisat.
    let warnings: [String]

    var summary: String {
        var text = cardType
        if let clipCount { text += " — \(clipCount) clip(uri)" }
        return text
    }
}

enum CameraCardDetector {
    /// Extensiile media relevante, per tip de card.
    private static let mediaExtensions: Set<String> = [
        "r3d", "ari", "arx", "mxf", "braw", "mov", "mp4", "crm", "cr2", "cr3",
        "nev", "mts", "m2ts", "dng", "wav", "avi", "insv"
    ]

    /// Inspecteaza radacina data. Intoarce nil daca nu recunoaste nicio
    /// structura cunoscuta (folder normal de lucru) — caz in care UI-ul nu
    /// arata nimic, ca sa nu adauge zgomot.
    static func detect(root: String) -> CameraCardInfo? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root, isDirectory: &isDir), isDir.boolValue else { return nil }
        let entries = (try? fm.contentsOfDirectory(atPath: root)) ?? []
        let names = Set(entries.map { $0.uppercased() })

        var type: String? = nil
        // Ordinea conteaza: structurile specifice se verifica INAINTEA celei
        // generice `DCIM`, pe care o au si Sony, si Canon, si un telefon.
        if entries.contains(where: { $0.uppercased().hasSuffix(".RDM") }) {
            type = "RED (R3D)"
        } else if names.contains("AVID") || entries.contains(where: { $0.uppercased().hasSuffix(".ARI") }) {
            type = "ARRI"
        } else if names.contains("XDROOT") {
            type = "Sony XDCAM"
        } else if names.contains("PRIVATE") {
            // Sony XAVC (`PRIVATE/M4ROOT`) sau Panasonic AVCHD
            // (`PRIVATE/AVCHD`) — deosebite prin subfolder.
            let privateRoot = (root as NSString).appendingPathComponent("PRIVATE")
            let sub = Set(((try? fm.contentsOfDirectory(atPath: privateRoot)) ?? []).map { $0.uppercased() })
            if sub.contains("M4ROOT") { type = "Sony XAVC" }
            else if sub.contains("AVCHD") { type = "Panasonic AVCHD" }
            else { type = "Card video (PRIVATE)" }
        } else if names.contains("CONTENTS") {
            type = "Panasonic P2"
        } else if entries.contains(where: { $0.lowercased().hasSuffix(".braw") }) {
            type = "Blackmagic BRAW"
        } else if names.contains("CLIPS001") || (names.contains("DCIM") && names.contains("MISC")) {
            // Cardurile Canon au `DCIM` alaturi de `MISC` — `DCIM` singur
            // (verificat mai jos) e prea generic, il are si un telefon.
            type = "Canon"
        } else if names.contains("DCIM") {
            type = "Card foto/video (DCIM)"
        }
        guard let cardType = type else { return nil }

        // Numaratoarea + verificarile se fac pe o singura parcurgere,
        // plafonata: pe un card cu zeci de mii de fisiere nu are rost sa
        // blocam UI-ul pentru o informatie orientativa.
        var clipCount = 0
        var zeroByteFiles: [String] = []
        var scanned = 0
        let scanLimit = 60_000
        if let enumerator = fm.enumerator(atPath: root) {
            for case let rel as String in enumerator {
                scanned += 1
                if scanned > scanLimit { break }
                let name = (rel as NSString).lastPathComponent
                if name.hasPrefix(".") { continue }
                let ext = (rel as NSString).pathExtension.lowercased()
                guard mediaExtensions.contains(ext) else { continue }
                clipCount += 1
                let full = (root as NSString).appendingPathComponent(rel)
                if let size = (try? fm.attributesOfItem(atPath: full)[.size] as? Int64) ?? nil, size == 0 {
                    if zeroByteFiles.count < 5 { zeroByteFiles.append(name) }
                }
            }
        }

        var warnings: [String] = []
        if clipCount == 0 {
            warnings.append("Cardul pare gol — nu s-a găsit niciun fișier media.")
        }
        if !zeroByteFiles.isEmpty {
            warnings.append("Fișiere de 0 octeți (posibil clipuri incomplete): \(zeroByteFiles.joined(separator: ", "))")
        }
        if scanned > scanLimit {
            warnings.append("Card foarte mare — numărătoarea de clipuri e orientativă.")
        }
        return CameraCardInfo(cardType: cardType, clipCount: clipCount, warnings: warnings)
    }

    /// Cazul cel mai costisitor de pe platou: userul a tras in Surse un
    /// SUBFOLDER al unui card, nu radacina lui. Urcam pana la 3 nivele in
    /// sus si verificam daca parintele arata a card — daca da, copierea ar
    /// pierde metadatele fratilor (indexuri, XML-uri de clip, LUT-uri).
    static func parentLooksLikeCard(path: String) -> String? {
        var current = (path as NSString).deletingLastPathComponent
        for _ in 0..<3 {
            guard current.count > 1, current != "/" else { return nil }
            if detect(root: current) != nil { return current }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }
}
