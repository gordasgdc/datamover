import Foundation
import SwiftUI

/// Setările jobului curent, partajate între fereastra principală și
/// fereastra Settings. Înainte erau `@State` în `ContentView` și existau doar
/// cât timp popover-ul era deschis; acum sunt un singur obiect, iar cele care
/// descriu metoda de lucru (verificare, excluderi, reluare) sunt persistate.
@MainActor
final class JobSettings: ObservableObject {
    static let shared = JobSettings()

    private let defaults = UserDefaults.standard

    @Published var verificationModel: VerificationModel {
        didSet { defaults.set(verificationModel.rawValue, forKey: "dm_verificationModel") }
    }
    /// Recitire separată a fiecărei copii după flush, cu F_NOCACHE cerut
    /// (vezi `readBackHash`). O a doua citire independentă prin sistemul de
    /// fișiere — nu o dovadă a mediului fizic (cache-ul discului rămâne).
    @Published var readBackVerification: Bool {
        didSet { defaults.set(readBackVerification, forKey: "dm_readBackVerification") }
    }
    @Published var exclusionsText: String {
        didSet { defaults.set(exclusionsText, forKey: "dm_exclusions") }
    }
    @Published var resumeEnabled: Bool {
        didSet { defaults.set(resumeEnabled, forKey: "dm_resumeEnabled") }
    }
    /// Cloud și notițele rămân per sesiune (ca înainte): un cont cloud ales
    /// ieri nu trebuie să pornească singur azi.
    @Published var cloudRemote = ""
    @Published var cloudRemoteFolder = ""
    @Published var shootNotes = ""

    private init() {
        verificationModel = VerificationModel(rawValue: defaults.string(forKey: "dm_verificationModel") ?? "") ?? .xxhash64
        readBackVerification = defaults.bool(forKey: "dm_readBackVerification")
        exclusionsText = defaults.string(forKey: "dm_exclusions") ?? ""
        resumeEnabled = defaults.object(forKey: "dm_resumeEnabled") as? Bool ?? true
    }

    var exclusions: [String] {
        exclusionsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var depth: VerificationDepth { .for(verificationModel, readBack: readBackVerification) }
}
