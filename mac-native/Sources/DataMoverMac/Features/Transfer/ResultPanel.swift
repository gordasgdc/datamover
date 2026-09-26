import AppKit
import SwiftUI

/// Rezultatul ultimului transfer: verdict global neambiguu + fiecare
/// destinație cu verdictul ei și acces direct la folder, rapoarte, MHL.
struct ResultPanel: View {
    let outcome: TransferOutcome
    let results: [DestinationResult]
    let folderName: String
    let depth: VerificationDepth
    let onDismiss: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DM.Space.l) {
                banner
                ForEach(results, id: \.destRoot) { result in
                    DestinationResultRow(result: result)
                }
                HStack {
                    Spacer()
                    Button(L.t("result.newTransfer"), action: onDismiss)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(DM.Space.l)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var status: DMStatus { DMStatus(outcome) }

    private var banner: some View {
        HStack(alignment: .top, spacing: DM.Space.m) {
            Image(systemName: status.symbol).font(.system(size: 30)).foregroundStyle(status.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DM.Space.xs) {
                Text(L.t(outcome.labelKey)).font(DM.Font.title)
                Text(L.t("outcomeHelp.\(outcome.rawValue)")).font(DM.Font.label).foregroundStyle(DM.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: DM.Space.l) {
                    Text(folderName).font(DM.Font.mono).textSelection(.enabled)
                    Text(L.t(depth.labelKey)).font(DM.Font.detail).foregroundStyle(DM.textSecondary)
                }
            }
            Spacer()
        }
        .padding(DM.Space.l)
        .background(status.color.opacity(0.10), in: RoundedRectangle(cornerRadius: DM.Radius.l))
        .overlay(RoundedRectangle(cornerRadius: DM.Radius.l).strokeBorder(status.color.opacity(0.45)))
        .accessibilityElement(children: .combine)
    }
}

struct DestinationResultRow: View {
    let result: DestinationResult

    var body: some View {
        DMPanel {
            VStack(alignment: .leading, spacing: DM.Space.s) {
                HStack {
                    Image(systemName: "externaldrive").foregroundStyle(DM.textSecondary)
                    Text((result.destRoot as NSString).lastPathComponent).font(DM.Font.label.weight(.semibold))
                    Spacer()
                    DMStatusBadge(status: DMStatus(result.outcome), text: L.t("destOutcome.\(result.outcome.rawValue)"))
                }
                HStack(spacing: DM.Space.l) {
                    count("result.ok", result.okCount, .verified)
                    count("result.skipped", result.skipCount, .neutral)
                    count("result.failed", result.failCount, result.failCount > 0 ? .failure : .neutral)
                    if result.recoveredCount > 0 { count("result.recovered", result.recoveredCount, .warning) }
                    Spacer()
                }
                HStack(spacing: DM.Space.s) {
                    if let folder = result.targetFolder {
                        Button(L.t("result.openFolder")) { reveal(folder) }
                    }
                    if let pdf = result.pdfPath { Button("PDF") { open(pdf) } }
                    if let html = result.htmlPath { Button("HTML") { open(html) } }
                    if let csv = result.csvPath { Button("CSV") { reveal(csv) } }
                    if let mhl = result.mhlPath { Button("MHL") { reveal(mhl) } }
                    Spacer()
                }
                .controlSize(.small)
            }
        }
    }

    private func count(_ key: String, _ n: Int, _ s: DMStatus) -> some View {
        HStack(spacing: DM.Space.xs) {
            Text("\(n)").font(DM.Font.label.monospacedDigit().weight(.semibold)).foregroundStyle(s.color)
            Text(L.t(key)).font(DM.Font.detail).foregroundStyle(DM.textSecondary)
        }
    }

    private func open(_ path: String) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
    private func reveal(_ path: String) { NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "") }
}

/// Jurnalul tehnic: colapsat implicit, filtrabil, copiabil.
struct ActivityLogView: View {
    let lines: [String]
    @Binding var expanded: Bool
    @State private var filter = ""

    private var visible: [String] {
        filter.isEmpty ? lines : lines.filter { $0.localizedCaseInsensitiveContains(filter) }
    }

    private var warningCount: Int {
        lines.filter { $0.contains("⚠") || $0.hasPrefix("Neconfirmat") || $0.hasPrefix("Preflight") || $0.contains("Eșuat") }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DM.Space.xs) {
            HStack(spacing: DM.Space.s) {
                Button {
                    expanded.toggle()
                } label: {
                    Label(L.t("log.title"), systemImage: expanded ? "chevron.down" : "chevron.right")
                        .font(DM.Font.detail.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DM.textSecondary)
                .accessibilityHint(L.t("log.toggleHint"))
                if warningCount > 0 {
                    DMStatusBadge(status: .warning, text: "\(warningCount)")
                }
                Spacer()
                if expanded {
                    TextField(L.t("log.filter"), text: $filter)
                        .textFieldStyle(.roundedBorder).frame(width: 180).controlSize(.small)
                    Button(L.t("log.copy")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(visible.joined(separator: "\n"), forType: .string)
                    }
                    .controlSize(.small)
                }
            }
            if expanded {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(visible.enumerated()), id: \.offset) { index, line in
                                Text(line).font(DM.Font.mono)
                                    .foregroundStyle(color(for: line))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .id(index)
                            }
                        }
                        .padding(DM.Space.s)
                    }
                    .frame(height: 120)
                    .background(DM.consoleBackground, in: RoundedRectangle(cornerRadius: DM.Radius.m))
                    .overlay(RoundedRectangle(cornerRadius: DM.Radius.m).strokeBorder(DM.border))
                    .onChange(of: visible.count) { _, count in
                        if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                    }
                }
            }
        }
    }

    private func color(for line: String) -> Color {
        if line.hasPrefix("Neconfirmat") || line.contains("Eșuat") || line.hasPrefix("Preflight") { return DM.failure }
        if line.contains("⚠") || line.contains("Checkpoint") { return DM.warning }
        return DM.textSecondary
    }
}
