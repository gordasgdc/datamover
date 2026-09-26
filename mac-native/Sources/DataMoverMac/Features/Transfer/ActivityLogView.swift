import AppKit
import SwiftUI

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
                        .textFieldStyle(.roundedBorder).frame(width: DM.Layout.logFilterWidth).controlSize(.small)
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
                        LazyVStack(alignment: .leading, spacing: DM.Space.line) {
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
                    .frame(height: DM.Layout.logHeight)
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

/// „mm:ss” sau „h:mm:ss”.
func duration(_ seconds: Double) -> String {
    let s = Int(seconds.rounded())
    let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
}
