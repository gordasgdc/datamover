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

/// Ce va porni, înainte de Start: sursa și structura detectată, destinațiile
/// cu capacitate, folderul rezultat, metoda de verificare, avertismentele.
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
                DMSectionHeader(title: L.t("prep.title"))
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
                            ForEach(destinations, id: \.self) { dest in
                                destinationLine(dest)
                            }
                        }
                    }
                    GridRow {
                        label("prep.folder")
                        Text(folderName).font(DM.Font.mono).textSelection(.enabled)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    GridRow {
                        label("prep.method")
                        HStack(spacing: DM.Space.s) {
                            Text(L.t(depth.labelKey)).font(DM.Font.label)
                            if depth == .sizeOnly {
                                DMStatusBadge(status: .warning, text: L.t("prep.weakVerification"))
                            }
                        }
                    }
                    GridRow {
                        label("prep.notes")
                        TextField(L.t("meta.notes"), text: $notes).textFieldStyle(.roundedBorder)
                    }
                }
                if !issues.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: DM.Space.xs) {
                        ForEach(issues.sorted { $0.severity > $1.severity }) { issue in
                            HStack(alignment: .firstTextBaseline, spacing: DM.Space.s) {
                                Image(systemName: issue.severity == .blocking ? DMStatus.failure.symbol : DMStatus.warning.symbol)
                                    .foregroundStyle(issue.severity == .blocking ? DM.failure : DM.warning)
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(L.t(issue.messageKey)).font(DM.Font.label)
                                    if !issue.path.isEmpty {
                                        Text(issue.path).font(DM.Font.mono).foregroundStyle(DM.textSecondary)
                                            .lineLimit(1).truncationMode(.middle)
                                    }
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }

    private func label(_ key: String) -> some View {
        Text(L.t(key)).font(DM.Font.detail).foregroundStyle(DM.textSecondary)
            .frame(width: 96, alignment: .leading)
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
                DMCapacityBar(total: cap.total, free: cap.free, incoming: incoming).frame(maxWidth: 260)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
