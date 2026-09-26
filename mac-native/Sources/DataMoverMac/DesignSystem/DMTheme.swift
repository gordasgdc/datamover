import AppKit
import SwiftUI

// MARK: - Design system DataMover
//
// Un singur loc pentru culori, tipografie, spațiere, raze și stări. Culorile
// sunt SEMANTICE și dinamice (NSColor cu variantă light/dark) — nicio
// culoare literală pe controale (Regula 37). Verde = verificat, nu „apasă-mă”:
// accentul de acțiune e cupru (standard GDC), ca semnificația verdelui să
// rămână neambiguă pentru operator.

enum DM {
    // MARK: Culori
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    static let accent = dynamic(light: NSColor(srgbRed: 0.72, green: 0.40, blue: 0.16, alpha: 1),
                                dark: NSColor(srgbRed: 0.93, green: 0.60, blue: 0.32, alpha: 1))
    static let verified = dynamic(light: NSColor(srgbRed: 0.10, green: 0.52, blue: 0.27, alpha: 1),
                                  dark: NSColor(srgbRed: 0.35, green: 0.80, blue: 0.48, alpha: 1))
    static let warning = dynamic(light: NSColor(srgbRed: 0.70, green: 0.45, blue: 0.00, alpha: 1),
                                 dark: NSColor(srgbRed: 0.98, green: 0.75, blue: 0.25, alpha: 1))
    static let failure = dynamic(light: NSColor(srgbRed: 0.75, green: 0.15, blue: 0.15, alpha: 1),
                                 dark: NSColor(srgbRed: 1.00, green: 0.45, blue: 0.42, alpha: 1))
    static let info = Color(nsColor: .systemBlue)

    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    static let background = Color(nsColor: .windowBackgroundColor)
    /// Panou ridicat: mai deschis decât fundalul ferestrei în AMBELE teme
    /// (în dark, un panou mai închis decât fundalul pare o gaură).
    static let surface = dynamic(light: NSColor(white: 1, alpha: 1),
                                 dark: NSColor(white: 0.235, alpha: 1))
    static let surfaceSunken = dynamic(light: NSColor(white: 0.93, alpha: 1),
                                       dark: NSColor(white: 0.13, alpha: 1))
    /// Bordura panourilor: mai fermă decât separatorul de sistem în light.
    static let border = dynamic(light: NSColor(white: 0, alpha: 0.14),
                                dark: NSColor(white: 1, alpha: 0.10))
    static let divider = Color(nsColor: .separatorColor)
    static let consoleBackground = dynamic(light: NSColor(white: 0.97, alpha: 1),
                                           dark: NSColor(white: 0.08, alpha: 1))

    // MARK: Spațiere / raze
    enum Space {
        static let xxs: CGFloat = 2, xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12
        static let l: CGFloat = 16, xl: CGFloat = 24
        /// Distanța dintre rândurile unui jurnal monospace.
        static let line: CGFloat = 1
    }
    enum Radius {
        static let s: CGFloat = 4, m: CGFloat = 6, l: CGFloat = 8
    }
    /// Țintă minimă de click (HIG macOS: 20–24 pt pe controale dense).
    static let minHit: CGFloat = 22

    // MARK: Layout (lățimi adaptive)
    enum Layout {
        /// Lățimea maximă a conținutului central — dincolo de ea, liniile de
        /// citit devin prea lungi; sub ea, totul se întinde.
        static let contentMaxWidth: CGFloat = 1440
        /// Peste această lățime, panourile trec pe două coloane.
        static let wideBreakpoint: CGFloat = 900
        /// Lățimea minimă a unei carduri de destinație în grilă.
        static let destinationMinWidth: CGFloat = 400
        static let sideColumnWidth: CGFloat = 240
        static let labelColumn: CGFloat = 104
        static let keyColumn: CGFloat = 118
        static let capacityBarMaxWidth: CGFloat = 280
        static let logHeight: CGFloat = 140
        static let logFilterWidth: CGFloat = 200
        static let windowMinWidth: CGFloat = 1040
        static let windowMinHeight: CGFloat = 640
        static let windowDefaultWidth: CGFloat = 1280
        static let windowDefaultHeight: CGFloat = 800
        static let settingsWidth: CGFloat = 560
        /// Linie de 1 pt (separatoare, stepper).
        static let hairline: CGFloat = 1
        // Traseu
        static let routeSourceColumn: CGFloat = 270
        static let routeDestinationColumn: CGFloat = 360
        static let routeNodeWidth: CGFloat = 190
        static let routeNodeBlock: CGFloat = 104
        static let routeConnector: CGFloat = 2.5
        static let routeMinGap: CGFloat = 36
        static let incidentsWidth: CGFloat = 300
        static let incidentsWidthCompact: CGFloat = 264
        static let incidentsCompactBelow: CGFloat = 1180
        static let shelfDeviceWidth: CGFloat = 84
        static let shelfItemWidth: CGFloat = 176
        static let endpointBarWidth: CGFloat = 220
        static let slotHeight: CGFloat = 96
    }

    // MARK: Opacități semantice
    enum Opacity {
        /// Fundalul unei insigne de stare.
        static let tint: Double = 0.14
        /// Fundalul bannerului de rezultat.
        static let bannerFill: Double = 0.10
        /// Bordura bannerului de rezultat.
        static let bannerStroke: Double = 0.50
        /// Fundalul raftului de dispozitive (zona „pe masă”).
        static let shelf: Double = 0.55
    }

    enum IconSize {
        static let banner: CGFloat = 30
        static let capacityBar: CGFloat = 6
    }

    // MARK: Tipografie (text semantic → respectă Dynamic Type, Regula 24)
    enum Font {
        static let sectionTitle = SwiftUI.Font.system(.caption, weight: .semibold)
        static let title = SwiftUI.Font.system(.title3, weight: .semibold)
        static let body = SwiftUI.Font.system(.body)
        static let label = SwiftUI.Font.system(.callout)
        static let detail = SwiftUI.Font.system(.caption)
        static let metric = SwiftUI.Font.system(.title2, design: .rounded, weight: .semibold).monospacedDigit()
        static let metricLarge = SwiftUI.Font.system(.title, design: .rounded, weight: .semibold).monospacedDigit()
        static let panelTitle = SwiftUI.Font.system(.headline)
        /// Cifrele mari (volum, capacitate, viteză) — citibile de la distanță.
        static let figure = SwiftUI.Font.system(.title, design: .rounded, weight: .semibold).monospacedDigit()
        static let figureCompact = SwiftUI.Font.system(.title3, design: .rounded, weight: .semibold).monospacedDigit()
        static let deviceName = SwiftUI.Font.system(.title3, weight: .bold)
        static let roleChip = SwiftUI.Font.system(.caption2, weight: .heavy)
        static let screenTitle = SwiftUI.Font.system(.largeTitle, weight: .semibold)
        static let sectionTracking: CGFloat = 0.6
        static let mono = SwiftUI.Font.system(.caption, design: .monospaced)
    }
}

// MARK: - Stări semantice

enum DMStatus {
    case neutral, active, verified, warning, failure

    var color: Color {
        switch self {
        case .neutral: return DM.textSecondary
        case .active: return DM.accent
        case .verified: return DM.verified
        case .warning: return DM.warning
        case .failure: return DM.failure
        }
    }

    var symbol: String {
        switch self {
        case .neutral: return "circle"
        case .active: return "arrow.triangle.2.circlepath"
        case .verified: return "checkmark.seal.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.octagon.fill"
        }
    }

    init(_ outcome: DestinationOutcome) {
        switch outcome {
        case .verified: self = .verified
        case .verifiedWithWarnings: self = .warning
        case .failed: self = .failure
        case .cancelled: self = .neutral
        }
    }

    init(_ outcome: TransferOutcome) {
        switch outcome {
        case .success: self = .verified
        case .successWithWarnings: self = .warning
        case .partialFailure, .failure: self = .failure
        case .cancelled: self = .neutral
        }
    }
}

// MARK: - Componente

struct DMSectionHeader: View {
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: DM.Space.s) {
            Text(title.uppercased())
                .font(DM.Font.sectionTitle)
                .tracking(DM.Font.sectionTracking)
                .foregroundStyle(DM.textSecondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if let trailing { trailing }
        }
    }
}

struct DMPanel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(DM.Space.m)
            .background(DM.surface, in: RoundedRectangle(cornerRadius: DM.Radius.l))
            .overlay(RoundedRectangle(cornerRadius: DM.Radius.l).strokeBorder(DM.border))
    }
}

struct DMStatusBadge: View {
    let status: DMStatus
    let text: String

    var body: some View {
        Label {
            Text(text).font(DM.Font.detail.weight(.semibold))
        } icon: {
            Image(systemName: status.symbol).imageScale(.small)
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, DM.Space.s)
        .padding(.vertical, DM.Space.xxs + 1)
        .background(status.color.opacity(DM.Opacity.tint), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct DMMetric: View {
    let label: String
    let value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DM.Space.xxs) {
            Text(label).font(DM.Font.detail).foregroundStyle(DM.textSecondary)
            Text(value).font(DM.Font.metric).foregroundStyle(DM.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            if let detail {
                Text(detail).font(DM.Font.detail).foregroundStyle(DM.textTertiary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Rând cheie–valoare dens, aliniat pe coloane.
struct DMKeyValue: View {
    let key: String
    let value: String
    var mono = false
    var status: DMStatus? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DM.Space.m) {
            Text(key).font(DM.Font.detail).foregroundStyle(DM.textSecondary)
                .frame(width: DM.Layout.keyColumn, alignment: .leading)
            Text(value)
                .font(mono ? DM.Font.mono : DM.Font.label)
                .foregroundStyle(status?.color ?? DM.textPrimary)
                .lineLimit(2).truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Bară de capacitate: ocupat + ce va adăuga transferul.
struct DMCapacityBar: View {
    let total: Int64
    let free: Int64
    let incoming: Int64

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let used = total > 0 ? CGFloat(Double(total - free) / Double(total)) : 0
            let add = total > 0 ? CGFloat(Double(incoming) / Double(total)) : 0
            let overflow = incoming > free
            ZStack(alignment: .leading) {
                Capsule().fill(DM.surfaceSunken)
                Capsule().fill(DM.textTertiary).frame(width: max(0, min(w, w * used)))
                Rectangle().fill(overflow ? DM.failure : DM.accent)
                    .frame(width: max(0, min(w - w * used, w * add)))
                    .offset(x: w * used)
            }
            .clipShape(Capsule())
        }
        .frame(height: DM.IconSize.capacityBar)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Profunzime (material E): umbră scurtă, de contact, nu decorativă.
    func dmElevation() -> some View {
        shadow(color: .black.opacity(0.18), radius: 8, y: 4)
    }

    /// Bordura de focus/hover consistentă pentru zonele de drop.
    func dmDropHighlight(_ active: Bool) -> some View {
        overlay(RoundedRectangle(cornerRadius: DM.Radius.l)
            .strokeBorder(active ? DM.accent : Color.clear, lineWidth: 2))
    }
}
