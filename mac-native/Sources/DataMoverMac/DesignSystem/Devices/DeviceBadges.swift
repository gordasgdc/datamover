import SwiftUI

/// Rolul unui obiect pe traseu.
enum RouteRole: Equatable {
    case source(Int)       // 1-based; afișat „SURSA” sau „SURSA 2”
    case destination(Int)  // „COPIA n”
    case none
}

enum DeviceActivity: Equatable { case idle, reading, writing, done }

/// Insignele de stare — SEPARATE de obiect. Fiecare are simbol + text, deci
/// rămâne inteligibilă fără culoare și e citită de VoiceOver.
struct DeviceBadges: View {
    let role: RouteRole
    var online = true
    var activity: DeviceActivity = .idle
    var warning = false
    var sourceCount = 1

    var body: some View {
        HStack(spacing: DM.Space.s) {
            roleChip
            Label(L.t(online ? "badge.online" : "badge.offline"), systemImage: online ? "circle.fill" : "circle.dashed")
                .labelStyle(.titleAndIcon)
                .font(DM.Font.detail)
                .foregroundStyle(online ? DM.verified : DM.textTertiary)
                .imageScale(.small)
            switch activity {
            case .reading: Label(L.t("badge.reading"), systemImage: "arrow.down.doc").font(DM.Font.detail).foregroundStyle(DM.accent)
            case .writing: Label(L.t("badge.writing"), systemImage: "arrow.triangle.2.circlepath").font(DM.Font.detail).foregroundStyle(DM.accent)
            case .done, .idle: EmptyView()
            }
            if warning {
                Label(L.t("badge.warning"), systemImage: "exclamationmark.triangle.fill")
                    .font(DM.Font.detail).foregroundStyle(DM.warning)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var roleChip: some View {
        switch role {
        case .source(let n):
            Text(sourceCount > 1 ? String(format: L.t("role.sourceN"), n) : L.t("role.source"))
                .font(DM.Font.roleChip).tracking(DM.Font.sectionTracking)
                .padding(.horizontal, DM.Space.xs + 2).padding(.vertical, DM.Space.xxs)
                .foregroundStyle(DM.background)
                .background(DM.textPrimary, in: RoundedRectangle(cornerRadius: DM.Radius.s))
        case .destination(let n):
            Text(String(format: L.t("role.copyN"), n))
                .font(DM.Font.roleChip).tracking(DM.Font.sectionTracking)
                .padding(.horizontal, DM.Space.xs + 2).padding(.vertical, DM.Space.xxs)
                .foregroundStyle(DM.textPrimary)
                .overlay(RoundedRectangle(cornerRadius: DM.Radius.s).strokeBorder(DM.textPrimary, lineWidth: DM.Layout.hairline))
        case .none:
            EmptyView()
        }
    }
}
