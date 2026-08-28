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
    // Cai complete (2026-08-28) - sourcesSummary/destSummary raman doar
    // pentru afisare scurta; astea sunt necesare ca sa poti deschide
    // direct sursa/destinatia din istoric (Finder). `decodeIfPresent`
    // pastreaza compatibilitatea cu intrari vechi de istoric, salvate
    // inainte de aceasta schimbare (fara aceste campuri).
    var sourcePaths: [String] = []
    var destinationPaths: [String] = []
    /// Radacinile REALE create la fiecare destinatie (destinationPaths[i]
    /// + folderName) - ce ar trebui deschis efectiv in Finder, nu discul
    /// intreg.
    var destinationTargetPaths: [String] = []

    enum CodingKeys: String, CodingKey {
        case dateText, folderName, sourcesSummary, destSummary, okCount, skipCount, failCount
        case sourcePaths, destinationPaths, destinationTargetPaths
    }

    init(dateText: String, folderName: String, sourcesSummary: String, destSummary: String,
         okCount: Int, skipCount: Int, failCount: Int,
         sourcePaths: [String] = [], destinationPaths: [String] = [], destinationTargetPaths: [String] = []) {
        self.dateText = dateText
        self.folderName = folderName
        self.sourcesSummary = sourcesSummary
        self.destSummary = destSummary
        self.okCount = okCount
        self.skipCount = skipCount
        self.failCount = failCount
        self.sourcePaths = sourcePaths
        self.destinationPaths = destinationPaths
        self.destinationTargetPaths = destinationTargetPaths
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dateText = try c.decode(String.self, forKey: .dateText)
        folderName = try c.decode(String.self, forKey: .folderName)
        sourcesSummary = try c.decode(String.self, forKey: .sourcesSummary)
        destSummary = try c.decode(String.self, forKey: .destSummary)
        okCount = try c.decode(Int.self, forKey: .okCount)
        skipCount = try c.decode(Int.self, forKey: .skipCount)
        failCount = try c.decode(Int.self, forKey: .failCount)
        sourcePaths = try c.decodeIfPresent([String].self, forKey: .sourcePaths) ?? []
        destinationPaths = try c.decodeIfPresent([String].self, forKey: .destinationPaths) ?? []
        destinationTargetPaths = try c.decodeIfPresent([String].self, forKey: .destinationTargetPaths) ?? []
    }
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
            okCount: okCount, skipCount: skipCount, failCount: failCount,
            sourcePaths: sources, destinationPaths: destinations,
            destinationTargetPaths: destinations.map { ($0 as NSString).appendingPathComponent(folderName) }
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
