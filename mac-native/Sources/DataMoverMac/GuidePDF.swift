import AppKit

/// Deschide ghidul PDF mare (nu ecranul scurt HelpView) - cerut explicit
/// (2026-08-29): "cand apas pe help, credeam ca o sa am acces la PDF-urile
/// alea mari... e prea mic meniul ala asa scurt... port ochelari, nu vad
/// bine". PDF-ul se deschide in Preview (sau vizualizatorul implicit) -
/// zoom nativ, selectie de text, accesibilitate completa, spre deosebire
/// de un panou SwiftUI de dimensiune fixa. Fisierele sunt bundle-uite in
/// Contents/Resources la build (vezi build_app.sh), cate unul per limba.
enum GuidePDF {
    static func open() {
        let filename: String
        switch LanguageStore.shared.lang {
        case .ro: filename = "DataMover_Ghid_RO"
        case .en: filename = "DataMover_Guide_EN"
        case .es: filename = "DataMover_Guia_ES"
        }

        if let url = Bundle.main.url(forResource: filename, withExtension: "pdf") {
            NSWorkspace.shared.open(url)
            return
        }
        // Fallback (build local, fara resursele copiate inca) - RO oricum.
        if let url = Bundle.main.url(forResource: "DataMover_Ghid_RO", withExtension: "pdf") {
            NSWorkspace.shared.open(url)
        }
    }
}
