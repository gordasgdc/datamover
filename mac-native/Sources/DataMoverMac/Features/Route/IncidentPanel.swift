import SwiftUI

/// Coloana de siguranță: verdictul pe scurt, incidentele (severitate, cauză,
/// acțiune) și verificările trecute. Aceeași coloană în toate etapele.
struct IncidentPanel: View {
    let headline: String
    let headlineStatus: DMStatus
    let incidents: [Incident]
    var passed: [String] = []
    var footnote: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DM.Space.m) {
                HStack(alignment: .firstTextBaseline, spacing: DM.Space.s) {
                    Image(systemName: headlineStatus.symbol).foregroundStyle(headlineStatus.color)
                    Text(headline).font(DM.Font.panelTitle).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                if !incidents.isEmpty {
                    DMSectionHeader(title: L.t("incidents.title"))
                    ForEach(incidents) { IncidentRow(incident: $0) }
                }
                if !passed.isEmpty {
                    Divider()
                    DMSectionHeader(title: L.t("prep.checks"))
                    ForEach(passed, id: \.self) { t in
                        Label(t, systemImage: "checkmark").font(DM.Font.detail).foregroundStyle(DM.textSecondary)
                            .labelStyle(.titleAndIcon)
                            .accessibilityLabel(L.t("severity.ok") + ": " + t)
                    }
                }
                if let footnote {
                    Text(footnote).font(DM.Font.detail).foregroundStyle(DM.textTertiary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(DM.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DM.surface)
    }
}

struct IncidentRow: View {
    let incident: Incident

    private var status: DMStatus {
        switch incident.severity {
        case .blocking: return .failure
        case .warning: return .warning
        case .info: return .neutral
        }
    }
    private var symbol: String {
        switch incident.severity {
        case .blocking: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DM.Space.xs) {
            Label(L.t(incident.severity.labelKey).uppercased(), systemImage: symbol)
                .font(DM.Font.roleChip).tracking(DM.Font.sectionTracking)
                .foregroundStyle(incident.severity == .info ? DM.info : status.color)
            Text(fmt(incident.titleKey, incident.titleArgs)).font(DM.Font.label.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(fmt(incident.causeKey, incident.causeArgs)).font(DM.Font.detail).foregroundStyle(DM.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let a = incident.actionKey {
                (Text(L.t("incident.actionPrefix") + " ").bold() + Text(fmt(a, incident.actionArgs)))
                    .font(DM.Font.detail).fixedSize(horizontal: false, vertical: true)
            }
            if !incident.subject.isEmpty {
                Text(incident.subject).font(DM.Font.mono).foregroundStyle(DM.textTertiary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
        }
        .padding(.leading, DM.Space.s)
        .overlay(alignment: .leading) {
            Rectangle().fill(incident.severity == .info ? DM.info : status.color).frame(width: DM.Layout.routeConnector)
        }
        .accessibilityElement(children: .combine)
    }

    private func fmt(_ key: String, _ args: [String]) -> String {
        let t = L.t(key)
        return args.isEmpty ? t : String(format: t, arguments: args.map { $0 as CVarArg })
    }
}

/// Un dispozitiv disponibil (raftul de jos): obiect mediu, nume, spațiu,
/// conexiune, insigna online. Tragerea și meniul contextual sunt ale apelantului.
struct DeviceShelfItem: View {
    let name: String
    let media: MediaClass?
    let freeBytes: Int64?
    var online = true

    var body: some View {
        HStack(spacing: DM.Space.s) {
            DeviceArt(kind: media?.kind ?? .externalDevice, size: DM.Layout.shelfDeviceWidth, dimmed: !online)
            VStack(alignment: .leading, spacing: DM.Space.xxs) {
                Text(name).font(DM.Font.label.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                Text(L.t((media?.kind ?? .externalDevice).labelKey)).font(DM.Font.detail).foregroundStyle(DM.textSecondary).lineLimit(1)
                Text(online ? String(format: L.t("prep.freeShort"), formatBytes(freeBytes)) : L.t("badge.offline"))
                    .font(DM.Font.detail.monospacedDigit()).foregroundStyle(DM.textTertiary)
            }
        }
        .frame(width: DM.Layout.shelfItemWidth, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
