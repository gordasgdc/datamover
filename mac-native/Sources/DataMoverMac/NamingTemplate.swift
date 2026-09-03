import Foundation

/// [2026-09-03] Sablon configurabil pentru numele folderului de destinatie.
///
/// DE CE: pana acum numele era fix — `<data>_<Proiect>_<Card>`. Fiecare
/// productie are insa propria conventie de denumire, impusa de casa de
/// post sau de arhiva (unele vor camera in nume, altele ora, altele deloc
/// data). Cand aplicatia nu poate respecta conventia, operatorul
/// redenumeste manual folderele dupa fiecare card — exact genul de munca
/// manuala pe care un ofloader profesional o elimina.
///
/// Sablonul implicit reproduce EXACT comportamentul vechi, deci nimeni nu
/// e afectat daca nu il schimba.
enum NamingTemplate {
    static let defaultTemplate = "{data}_{proiect}_{card}"

    /// Tokenii oferiti in UI, in ordinea in care ii aratam userului.
    static let tokens = ["{data}", "{ora}", "{proiect}", "{card}", "{camera}", "{operator}"]

    struct Context {
        var project: String = ""
        var card: String = ""
        var camera: String = ""
        var operatorName: String = ""
        var date: Date = Date()
    }

    /// Numele complet al folderului, cu tokenii inlocuiti.
    static func render(_ template: String, context: Context) -> String {
        expand(template, context: context, includeTimeTokens: true)
    }

    /// Acelasi sablon, dar FARA partile care se schimba de la o rulare la
    /// alta (data/ora). Rezultatul e "miezul stabil" al numelui, folosit ca
    /// sa recunoastem un transfer anterior al ACELUIASI card, inceput in
    /// alta zi — vezi OffloadRunner.findExistingFolderName. Inainte, acea
    /// cautare era hardcodata pe sufixul `_Proiect_Card`; cu sabloane
    /// libere, singura varianta corecta e sa comparam ce ramane dupa ce
    /// scoatem tokenii de timp.
    static func stableCore(_ template: String, context: Context) -> String {
        expand(template, context: context, includeTimeTokens: false)
    }

    private static func expand(_ template: String, context: Context, includeTimeTokens: Bool) -> String {
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH-mm"

        var out = template.isEmpty ? defaultTemplate : template
        let replacements: [(String, String)] = [
            ("{data}", includeTimeTokens ? dateFmt.string(from: context.date) : ""),
            ("{ora}", includeTimeTokens ? timeFmt.string(from: context.date) : ""),
            ("{proiect}", fallback(context.project, "Proiect")),
            ("{card}", fallback(context.card, "Card")),
            // Camera/operator raman GOALE daca userul nu le-a completat —
            // spre deosebire de proiect/card, care au implicite istorice.
            // Un "Camera" literal in numele fiecarui folder ar fi zgomot.
            ("{camera}", sanitize(context.camera)),
            ("{operator}", sanitize(context.operatorName)),
        ]
        for (token, value) in replacements {
            out = out.replacingOccurrences(of: token, with: value, options: .caseInsensitive)
        }
        return cleanUp(out)
    }

    private static func fallback(_ value: String, _ implicit: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return sanitize(trimmed.isEmpty ? implicit : trimmed)
    }

    /// Scoate ce nu are ce cauta intr-un nume de folder pe niciun sistem de
    /// fisiere (inclusiv `:` — separator de cale in Finder — si `/`), si
    /// inlocuieste spatiile cu `_`, ca in comportamentul vechi.
    private static func sanitize(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return value.trimmingCharacters(in: .whitespaces)
            .components(separatedBy: forbidden).joined()
            .replacingOccurrences(of: " ", with: "_")
    }

    /// Un token gol lasa in urma separatori duplicati (`__`) sau la capete
    /// (`_Proiect`), care arata a bug intr-un nume de folder livrat la
    /// arhiva. Le normalizam.
    private static func cleanUp(_ value: String) -> String {
        var out = value
        while out.contains("__") { out = out.replacingOccurrences(of: "__", with: "_") }
        while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
        out = out.trimmingCharacters(in: CharacterSet(charactersIn: "_- "))
        return out.isEmpty ? "Transfer" : out
    }
}
