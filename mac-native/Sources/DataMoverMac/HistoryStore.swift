import Foundation

/// Istoricul copierilor efectuate — data, numele folderului (Proiect+Card),
/// sursele si destinatiile folosite, plus cate fisiere OK/sarite/esuate.
/// Persistat in Application Support, ca sa ramana intre lansari ale aplicatiei
/// (echivalentul "istoricului" pe care il avea si aplicatia Windows).
struct HistoryEntry: Codable, Identifiable {
    var id: String { "\(dateText)-\(folderName)" }
    let dateText: String
    let folderName: String
    let sourcesSummary: String
    let destSummary: String
    let okCount: Int
    let skipCount: Int
    let failCount: Int
}

final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    private let fileURL: URL

    @Published private(set) var entries: [HistoryEntry] = []

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DataMover", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("history.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([HistoryEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func record(folderName: String, sources: [String], destinations: [String],
                okCount: Int, skipCount: Int, failCount: Int) {
        let df = DateFormatter()
        df.dateFormat = "dd.MM.yyyy HH:mm"
        let entry = HistoryEntry(
            dateText: df.string(from: Date()),
            folderName: folderName,
            sourcesSummary: sources.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "),
            destSummary: destinations.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "),
            okCount: okCount, skipCount: skipCount, failCount: failCount
        )
        entries.append(entry)
        if entries.count > 200 { entries.removeFirst(entries.count - 200) }
        save()
    }

    func delete(_ entry: HistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    func clearAll() {
        entries.removeAll()
        save()
    }
}
