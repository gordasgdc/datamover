import Foundation

/// Profil de transfer salvat (2026-08-28) - o configuratie completa,
/// numita de user, reutilizabila fara sa retastezi cai/optiuni de fiecare
/// data ("Backup Proiecte RAW pe SSD 3TB", "Transfer Rapid SD Card").
/// Retine: cai prestabilite (sursa/destinatie), nivelul de
/// securitate/verificare ales si treapta de Buffer/RAM selectata - cerinta
/// explicita, nu doar destinatii ca varianta veche de "presetari" Windows.
struct TransferProfile: Codable, Identifiable, Equatable {
    var id: String { name }
    var name: String
    var sourcePaths: [String]
    var destinationPaths: [String]
    var verificationModel: VerificationModel
    var exclusionsText: String
    var chunkSizeMB: Int
    var ramLimitMB: Int
}

final class TransferProfileStore: ObservableObject {
    static let shared = TransferProfileStore()

    private let fileURL: URL
    @Published private(set) var profiles: [TransferProfile] = []

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DataMover", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("transfer_profiles.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([TransferProfile].self, from: data) else { return }
        profiles = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Salveaza (sau suprascrie, daca exista deja un profil cu acelasi
    /// nume) profilul dat.
    func upsert(_ profile: TransferProfile) {
        if let idx = profiles.firstIndex(where: { $0.name == profile.name }) {
            profiles[idx] = profile
        } else {
            profiles.append(profile)
        }
        save()
    }

    func delete(_ profile: TransferProfile) {
        profiles.removeAll { $0.name == profile.name }
        save()
    }
}
