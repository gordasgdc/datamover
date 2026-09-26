import SwiftUI

/// Capacitatea unui volum (total + liber), citită o singură dată per
/// actualizare de listă. Liber = capacitate utilizabilă reală pe APFS.
struct VolumeCapacity {
    let total: Int64
    let free: Int64

    static func of(_ path: String) -> VolumeCapacity? {
        let url = URL(fileURLWithPath: path)
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                         .volumeAvailableCapacityForImportantUsageKey,
                                                         .volumeAvailableCapacityKey]),
              let total = v.volumeTotalCapacity else { return nil }
        let free = v.volumeAvailableCapacityForImportantUsage ?? Int64(v.volumeAvailableCapacity ?? 0)
        return VolumeCapacity(total: Int64(total), free: free)
    }
}

/// O verificare de pregătire afișată operatorului — tipizată, ca UI-ul să nu
/// deducă starea din text.
struct PrepCheck: Identifiable {
    let id: String
    let status: DMStatus
    let title: String
    let detail: String
}

/// Ce va porni, înainte de Start: sursa și structura detectată, destinațiile
/// cu capacitate, folderul rezultat, metoda de verificare, verificările.
/// Pe ferestre late: rezumatul la stânga, verificările la dreapta.
struct PrepPanel: View {
    let sources: [String]
    let cardInfo: [String: CameraCardInfo]
    let destinations: [String]
    let capacities: [String: VolumeCapacity]
    let sourceBytes: Int64?
    let folderName: String
    let depth: VerificationDepth
    let issues: [PreflightIssue]
    @Binding var notes: String

    var body: some View {
        DMPanel {
            VStack(alignment: .leading, spacing: DM.Space.m) {
                HStack {
                    Text(L.t("prep.title")).font(DM.Font.panelTitle)
                    Spacer()
                    DMStatusBadge(status: overallStatus, text: L.t(overallKey))
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: DM.Space.xl) {
                        summary.frame(minWidth: DM.Layout.wideBreakpoint / 2, maxWidth: .infinity, alignment: .leading)
                        Divider()
                        checksList.frame(minWidth: DM.Layout.wideBreakpoint / 3, maxWidth: .infinity, alignment: .leading)
                    }
                    // Divider-ul vertical ar întinde panoul pe toată înălțimea.
                    .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: DM.Space.m) {
                        summary
                        Divider()
                        checksList
                    }
                }
            }
        }
    }

    // MARK: Rezumat

    private var summary: some View {
        Grid(alignment: .leading, horizontalSpacing: DM.Space.m, verticalSpacing: DM.Space.s) {
            GridRow {
                label("prep.source")
                VStack(alignment: .leading, spacing: DM.Space.xxs) {
                    if sources.isEmpty {
                        Text(L.t("prep.noSource")).foregroundStyle(DM.textTertiary)
                    }
                    ForEach(sources, id: \.self) { src in
                        HStack(spacing: DM.Space.s) {
                            Text((src as NSString).lastPathComponent).font(DM.Font.label.weight(.semibold))
                            if let info = cardInfo[src] {
                                DMStatusBadge(status: info.warnings.isEmpty ? .verified : .warning, text: info.summary)
                            }
                        }
                    }
                    if let sourceBytes, !sources.isEmpty {
                        Text(formatBytes(sourceBytes)).font(DM.Font.detail).foregroundStyle(DM.textSecondary)
                    }
                }
            }
            GridRow {
                label("prep.destinations")
                VStack(alignment: .leading, spacing: DM.Space.xs) {
                    if destinations.isEmpty {
                        Text(L.t("prep.noDestination")).foregroundStyle(DM.textTertiary)
                    }
                    ForEach(destinations, id: \.self) { destinationLine($0) }
                }
            }
            GridRow {
                label("prep.folder")
                Text(folderName).font(DM.Font.mono).textSelection(.enabled)
                    .lineLimit(1).truncationMode(.middle)
            }
            GridRow {
                label("prep.method")
                Text(L.t(depth.labelKey)).font(DM.Font.label)
                    .foregroundStyle(depth == .sizeOnly ? DM.warning : DM.textPrimary)
            }
            GridRow {
                label("prep.notes")
                TextField(L.t("meta.notes"), text: $notes).textFieldStyle(.roundedBorder)
            }
        }
    }

    private func label(_ key: String) -> some View {
        Text(L.t(key)).font(DM.Font.detail).foregroundStyle(DM.textSecondary)
            .frame(width: DM.Layout.labelColumn, alignment: .leading)
    }

    private func destinationLine(_ dest: String) -> some View {
        let cap = capacities[dest]
        let incoming = sourceBytes ?? 0
        let tooSmall = cap.map { incoming > $0.free } ?? false
        return VStack(alignment: .leading, spacing: DM.Space.xxs) {
            HStack(spacing: DM.Space.s) {
                Text((dest as NSString).lastPathComponent).font(DM.Font.label.weight(.semibold))
                if let cap {
                    Text(String(format: L.t("prep.free"), formatBytes(cap.free), formatBytes(cap.total)))
                        .font(DM.Font.detail).foregroundStyle(tooSmall ? DM.failure : DM.textSecondary)
                }
            }
            if let cap {
                DMCapacityBar(total: cap.total, free: cap.free, incoming: incoming)
                    .frame(maxWidth: DM.Layout.capacityBarMaxWidth)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Verificări

    private var checks: [PrepCheck] {
        var list: [PrepCheck] = issues.sorted { $0.severity > $1.severity }.map { issue in
            PrepCheck(id: issue.id, status: issue.severity == .blocking ? .failure : .warning,
                      title: L.t(issue.messageKey), detail: issue.path)
        }
        let ready = !sources.isEmpty && !destinations.isEmpty
        if ready && !issues.contains(where: { [.sameAsSource, .destinationInsideSource, .sourceInsideDestination,
                                               .duplicateDestination, .nestedDestinations].contains($0.code) }) {
            list.append(PrepCheck(id: "overlap-ok", status: .verified, title: L.t("prep.check.noOverlap"), detail: ""))
        }
        if ready, let bytes = sourceBytes {
            let short = destinations.filter { d in capacities[d].map { bytes > $0.free } ?? false }
            if short.isEmpty {
                list.append(PrepCheck(id: "space-ok", status: .verified, title: L.t("prep.check.spaceOk"), detail: ""))
            } else {
                for d in short {
                    list.append(PrepCheck(id: "space-\(d)", status: .warning, title: L.t("prep.check.spaceLow"), detail: d))
                }
            }
        }
        list.append(PrepCheck(id: "depth", status: depth == .sizeOnly ? .warning : .verified,
                              title: L.t(depth == .sizeOnly ? "prep.weakVerification" : "prep.check.checksum"), detail: ""))
        return list
    }

    private var overallStatus: DMStatus {
        if sources.isEmpty || destinations.isEmpty { return .neutral }
        if checks.contains(where: { $0.status == .failure }) { return .failure }
        if checks.contains(where: { $0.status == .warning }) { return .warning }
        return .verified
    }

    private var overallKey: String {
        switch overallStatus {
        case .failure: return "prep.state.blocked"
        case .warning: return "prep.state.warnings"
        case .verified: return "prep.state.ready"
        default: return "prep.state.incomplete"
        }
    }

    private var checksList: some View {
        VStack(alignment: .leading, spacing: DM.Space.s) {
            DMSectionHeader(title: L.t("prep.checks"))
            ForEach(checks) { check in
                HStack(alignment: .firstTextBaseline, spacing: DM.Space.s) {
                    Image(systemName: check.status.symbol).foregroundStyle(check.status.color)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(check.title).font(DM.Font.label)
                        if !check.detail.isEmpty {
                            Text(check.detail).font(DM.Font.mono).foregroundStyle(DM.textSecondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
