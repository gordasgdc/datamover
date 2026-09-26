import SwiftUI

/// Monitorul transferului: faza reală, progres total, progres independent per
/// destinație, metrici. Înlocuiește cele trei inele fără context.
/// Doar citește starea publicată de `OffloadRunner`; nu calculează verdicte.
struct TransferMonitorView: View {
    @ObservedObject var runner: OffloadRunner

    private static let phases: [TransferPhase] = [.preparing, .copying, .reporting, .finished]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DM.Space.l) {
                header
                phaseStepper
                totalProgress
                metrics
                destinations
            }
            .padding(DM.Space.l)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DM.Space.xxs) {
                Text(runner.lastFolderName).font(DM.Font.title).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                Text(L.t(runner.lastVerificationDepth.labelKey)).font(DM.Font.detail).foregroundStyle(DM.textSecondary)
            }
            Spacer()
            if runner.isPaused {
                DMStatusBadge(status: .warning, text: L.t("footer.pause"))
            } else {
                DMStatusBadge(status: .active, text: L.t(runner.phase.labelKey))
            }
        }
    }

    private var phaseStepper: some View {
        HStack(spacing: DM.Space.xs) {
            ForEach(Array(Self.phases.enumerated()), id: \.offset) { index, phase in
                let current = Self.phases.firstIndex(of: runner.phase) ?? 0
                let state: DMStatus = index < current ? .verified : (index == current ? .active : .neutral)
                HStack(spacing: DM.Space.xs) {
                    Image(systemName: index < current ? "checkmark.circle.fill" : (index == current ? "circle.inset.filled" : "circle"))
                        .foregroundStyle(state.color)
                    Text(L.t(phase.labelKey + ".step")).font(DM.Font.detail)
                        .foregroundStyle(index == current ? DM.textPrimary : DM.textSecondary)
                }
                if index < Self.phases.count - 1 {
                    Rectangle().fill(DM.border).frame(height: 1).frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L.t("monitor.phase") + ": " + L.t(runner.phase.labelKey))
    }

    private var totalProgress: some View {
        VStack(alignment: .leading, spacing: DM.Space.xs) {
            HStack {
                Text(L.t("monitor.total")).font(DM.Font.label.weight(.semibold))
                Spacer()
                Text("\(runner.progressPercent)%").font(DM.Font.label.monospacedDigit())
            }
            ProgressView(value: Double(runner.progressPercent), total: 100).tint(DM.accent)
            if !runner.currentFile.isEmpty {
                Text(runner.currentFile).font(DM.Font.mono).foregroundStyle(DM.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
                    .accessibilityLabel(L.t("monitor.currentFile") + " " + runner.currentFile)
            }
        }
    }

    private var metrics: some View {
        DMPanel {
            Grid(horizontalSpacing: DM.Space.l, verticalSpacing: DM.Space.m) {
                GridRow {
                    DMMetric(label: L.t("monitor.read"), value: rate(runner.readBytesPerSecond))
                    DMMetric(label: L.t("monitor.write"), value: rate(runner.writeBytesPerSecond),
                             detail: runner.destinationCount > 1 ? String(format: L.t("monitor.copies"), runner.destinationCount) : nil)
                    DMMetric(label: L.t("monitor.eta"), value: runner.etaSeconds.map(duration) ?? "—",
                             detail: L.t("monitor.elapsed") + " " + duration(runner.elapsedSeconds))
                }
                GridRow {
                    DMMetric(label: L.t("monitor.data"), value: formatBytes(runner.bytesDone),
                             detail: "/ " + formatBytes(runner.totalBytes))
                    DMMetric(label: L.t("monitor.files"), value: "\(runner.filesDone)",
                             detail: "/ \(runner.totalUnits)")
                    DMMetric(label: L.t("monitor.memory"), value: runner.memoryUsedText.isEmpty ? "—" : runner.memoryUsedText,
                             detail: L.t("io.allocated") + " " + runner.bufferAllocatedText)
                }
            }
        }
    }

    private var destinations: some View {
        VStack(alignment: .leading, spacing: DM.Space.s) {
            DMSectionHeader(title: L.t("dest.title"))
            ForEach(runner.destinationStates) { dest in
                DestinationProgressRow(state: dest,
                                       expectedBytes: runner.totalBytes / Int64(max(runner.destinationCount, 1)))
            }
        }
    }

    private func rate(_ bps: Double) -> String { bps > 0 ? formatBytes(Int64(bps)) + "/s" : "—" }
}

struct DestinationProgressRow: View {
    let state: DestinationLiveState
    let expectedBytes: Int64

    private var status: DMStatus {
        if let outcome = state.outcome { return DMStatus(outcome) }
        if !state.available || state.filesFailed > 0 { return .failure }
        return .active
    }

    var body: some View {
        DMPanel {
            VStack(alignment: .leading, spacing: DM.Space.xs) {
                HStack {
                    Image(systemName: "externaldrive").foregroundStyle(DM.textSecondary)
                    Text((state.destRoot as NSString).lastPathComponent).font(DM.Font.label.weight(.semibold))
                    Text(state.destRoot).font(DM.Font.detail).foregroundStyle(DM.textTertiary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    DMStatusBadge(status: status, text: statusText)
                }
                ProgressView(value: Double(min(state.bytesWritten, expectedBytes)), total: Double(max(expectedBytes, 1)))
                    .tint(status == .failure ? DM.failure : DM.verified)
                HStack {
                    Text(String(format: L.t("monitor.confirmed"), state.filesConfirmed, formatBytes(state.bytesWritten)))
                    if state.filesFailed > 0 {
                        Text(String(format: L.t("monitor.failedFiles"), state.filesFailed)).foregroundStyle(DM.failure)
                    }
                    Spacer()
                }
                .font(DM.Font.detail).foregroundStyle(DM.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        if let outcome = state.outcome { return L.t("destOutcome.\(outcome.rawValue)") }
        if !state.available { return L.t("dest.disconnected") }
        if state.filesFailed > 0 { return L.t("dest.withErrors") }
        return L.t("dest.inProgress")
    }
}

func duration(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
}
