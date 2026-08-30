import Foundation

/// Preț dinamic (2026-08-30) — citește `pricing.json` (publicat de
/// Furnizor, `PricingManagerView`, în `gdc-plugin-manager-catalog-vendor`,
/// servit static la `https://gordas.dev/pricing.json`) în loc de o valoare
/// hardcodată în cod. Motiv direct: o ofertă de Black Friday necesita până
/// acum recompilarea + resemnarea + republicarea aplicației doar ca să
/// schimbi o cifră afișată — acum devine vizibilă în câteva minute, fără
/// recompilare.
///
/// **Fail-open, la fel ca RevocationCheck (Regula 12)**: fără conexiune la
/// internet, sau dacă `productID`-ul lipsește din `pricing.json`, se
/// folosește prețul hardcodat de mai jos (`fallbackBasePrice`) — niciodată
/// un ecran de donație gol/eronat doar pentru că userul e offline.
final class PricingChecker: ObservableObject {
    static let shared = PricingChecker()

    private static let pricingURL = URL(string: "https://gordas.dev/pricing.json")!
    private static let productID = "gdc-datamover"
    /// Preț de referință dacă `pricing.json` e inaccesibil - IDENTIC cu
    /// suma documentată în Regula 3/CLAUDE.md la data acestei implementări.
    static let fallbackBasePrice: Double = 23

    @Published private(set) var basePrice: Double = fallbackBasePrice
    @Published private(set) var activePromo: PricingPromo?

    /// Prețul afișat ACUM — fereastra activă din program, dacă există,
    /// altfel prețul de bază.
    var effectivePrice: Double { activePromo?.price ?? basePrice }

    private struct PricingCatalog: Codable {
        var products: [String: ProductPricing]
    }
    private struct ProductPricing: Codable {
        var basePrice: Double
        /// Program de ferestre de preț (2026-08-30) - vezi Furnizor
        /// PricingManagerView. Doar prima fereastră a cărei perioadă
        /// conține "acum" contează; restul sunt trecute/viitoare.
        var promoSchedule: [PricingPromo] = []

        enum CodingKeys: String, CodingKey { case basePrice, promoSchedule }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            basePrice = try c.decode(Double.self, forKey: .basePrice)
            promoSchedule = try c.decodeIfPresent([PricingPromo].self, forKey: .promoSchedule) ?? []
        }
    }

    struct PricingPromo: Codable {
        var price: Double
        var label: String
        var startsAt: Date
        var endsAt: Date
        var showCountdown: Bool = false

        enum CodingKeys: String, CodingKey { case price, label, startsAt, endsAt, showCountdown }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            price = try c.decode(Double.self, forKey: .price)
            label = try c.decode(String.self, forKey: .label)
            startsAt = try c.decode(Date.self, forKey: .startsAt)
            endsAt = try c.decode(Date.self, forKey: .endsAt)
            showCountdown = try c.decodeIfPresent(Bool.self, forKey: .showCountdown) ?? false
        }

        var isActiveNow: Bool {
            let now = Date()
            return now >= startsAt && now <= endsAt
        }

        var countdownText: String {
            let remaining = max(0, endsAt.timeIntervalSinceNow)
            let days = Int(remaining) / 86400
            let hours = (Int(remaining) % 86400) / 3600
            let minutes = (Int(remaining) % 3600) / 60
            if days > 0 { return "\(days)z \(hours)h" }
            if hours > 0 { return "\(hours)h \(minutes)m" }
            return "\(minutes)m"
        }
    }

    private init() {
        refresh()
    }

    /// Apelat la lansare + manual (ex. la deschiderea ecranului de
    /// activare) — niciodată blocant, fail-open pe orice eroare.
    func refresh() {
        let task = URLSession.shared.dataTask(with: Self.pricingURL) { [weak self] data, response, error in
            guard let self, error == nil,
                  let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data else { return }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let catalog = try? decoder.decode(PricingCatalog.self, from: data),
                  let product = catalog.products[Self.productID] else { return }
            DispatchQueue.main.async {
                self.basePrice = product.basePrice
                self.activePromo = product.promoSchedule.first(where: { $0.isActiveNow })
            }
        }
        task.resume()
    }
}
