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
        // Pe lățimi mici, starea rămâne ca simbol (forme diferite, nu doar
        // culori) cu eticheta în tooltip și VoiceOver — nu se rupe textul.
        ViewThatFits(in: .horizontal) {
            full
            compact
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var compact: some View {
        HStack(spacing: DM.Space.xs) {
            roleChip
            Image(systemName: online ? "circle.fill" : "circle.dashed").imageScale(.small)
                .foregroundStyle(online ? DM.verified : DM.textTertiary).help(L.t(online ? "badge.online" : "badge.offline"))
            if activity == .reading || activity == .writing {
                Image(systemName: activity == .reading ? "arrow.down.doc" : "arrow.triangle.2.circlepath")
                    .foregroundStyle(DM.accent).help(L.t(activity == .reading ? "badge.reading" : "badge.writing"))
            }
            if warning {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(DM.warning).help(L.t("badge.warning"))
            }
        }
        .font(DM.Font.detail)
    }

    private var accessibilityText: String {
        var parts: [String] = []
        switch role {
        case .source(let n): parts.append(sourceCount > 1 ? String(format: L.t("role.sourceN"), n) : L.t("role.source"))
        case .destination(let n): parts.append(String(format: L.t("role.copyN"), n))
        case .none: break
        }
        parts.append(L.t(online ? "badge.online" : "badge.offline"))
        if activity == .reading { parts.append(L.t("badge.reading")) }
        if activity == .writing { parts.append(L.t("badge.writing")) }
        if warning { parts.append(L.t("badge.warning")) }
        return parts.joined(separator: ", ")
    }

    private var full: some View {
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
        .fixedSize()
    }

    @ViewBuilder private var roleChip: some View {
        switch role {
        case .source(let n):
            Text(sourceCount > 1 ? String(format: L.t("role.sourceN"), n) : L.t("role.source"))
                .font(DM.Font.roleChip).tracking(DM.Font.sectionTracking)
                .padding(.horizontal, DM.Space.xs + 2).padding(.vertical, DM.Space.xxs)
                .foregroundStyle(DM.background)
                .background(DM.textPrimary, in: RoundedRectangle(cornerRadius: DM.Radius.s))
                .fixedSize()
        case .destination(let n):
            Text(String(format: L.t("role.copyN"), n))
                .font(DM.Font.roleChip).tracking(DM.Font.sectionTracking)
                .padding(.horizontal, DM.Space.xs + 2).padding(.vertical, DM.Space.xxs)
                .foregroundStyle(DM.textPrimary)
                .overlay(RoundedRectangle(cornerRadius: DM.Radius.s).strokeBorder(DM.textPrimary, lineWidth: DM.Layout.hairline))
                .fixedSize()
        case .none:
            EmptyView()
        }
    }
}
