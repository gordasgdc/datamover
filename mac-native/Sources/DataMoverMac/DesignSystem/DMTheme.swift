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
    static let surface = dynamic(light: NSColor(white: 1, alpha: 1),
                                 dark: NSColor(white: 0.155, alpha: 1))
    static let surfaceSunken = dynamic(light: NSColor(white: 0.955, alpha: 1),
                                       dark: NSColor(white: 0.11, alpha: 1))
    static let border = Color(nsColor: .separatorColor)
    static let consoleBackground = dynamic(light: NSColor(white: 0.97, alpha: 1),
                                           dark: NSColor(white: 0.08, alpha: 1))

    // MARK: Spațiere / raze
    enum Space {
        static let xxs: CGFloat = 2, xs: CGFloat = 4, s: CGFloat = 8, m: CGFloat = 12
        static let l: CGFloat = 16, xl: CGFloat = 24
    }
    enum Radius {
        static let s: CGFloat = 4, m: CGFloat = 6, l: CGFloat = 8
    }
    /// Țintă minimă de click (HIG macOS: 20–24 pt pe controale dense).
    static let minHit: CGFloat = 22

    // MARK: Tipografie (text semantic → respectă Dynamic Type, Regula 24)
    enum Font {
        static let sectionTitle = SwiftUI.Font.system(.caption, weight: .semibold)
        static let title = SwiftUI.Font.system(.title3, weight: .semibold)
        static let body = SwiftUI.Font.system(.body)
        static let label = SwiftUI.Font.system(.callout)
        static let detail = SwiftUI.Font.system(.caption)
        static let metric = SwiftUI.Font.system(.title2, design: .rounded, weight: .semibold).monospacedDigit()
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
                .tracking(0.6)
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
        .background(status.color.opacity(0.12), in: Capsule())
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
                .frame(width: 118, alignment: .leading)
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
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Bordura de focus/hover consistentă pentru zonele de drop.
    func dmDropHighlight(_ active: Bool) -> some View {
        overlay(RoundedRectangle(cornerRadius: DM.Radius.l)
            .strokeBorder(active ? DM.accent : Color.clear, lineWidth: 2))
    }
}
