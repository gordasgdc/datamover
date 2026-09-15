import SwiftUI

/// Panoul de monitorizare afișat cât timp rulează un transfer.
///
/// Citește EXCLUSIV din `OffloadRunner` prin `@ObservedObject` — nu pornește
/// nimic, nu măsoară nimic și nu atinge motorul de copiere. Dacă panoul ar
/// fi șters, transferul ar decurge identic.
struct TransferGlassDashboard: View {
    @ObservedObject var runner: OffloadRunner

    /// Maximul de viteză văzut în transferul curent, ca inelele să aibă o
    /// referință. Un maxim FIX (ex. 1 GB/s) ar lăsa inelul aproape gol pe un
    /// card lent și l-ar satura pe un NVMe.
    @State private var peakWrite: Double = 0

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 20) {
                TransferGaugeView(
                    title: "READ",
                    value: speedValue(runner.readBytesPerSecond),
                    unit: "MB/s",
                    fraction: peakWrite > 0 ? runner.readBytesPerSecond / peakWrite : 0,
                    color: .cyan)

                TransferGaugeView(
                    title: "WRITE",
                    value: speedValue(runner.writeBytesPerSecond),
                    unit: "MB/s",
                    fraction: peakWrite > 0 ? runner.writeBytesPerSecond / peakWrite : 0,
                    color: .orange)

                TransferGaugeView(
                    title: "TOTAL",
                    value: "\(runner.progressPercent)",
                    unit: "%",
                    fraction: Double(runner.progressPercent) / 100,
                    color: .green)
            }

            card
        }
        .onChange(of: runner.writeBytesPerSecond) { _, new in
            if new > peakWrite { peakWrite = new }
        }
        .onChange(of: runner.isRunning) { _, running in
            if running { peakWrite = 0 }   // fiecare transfer are scara lui
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(label: "Fișier", value: runner.currentFile.isEmpty ? "—" : runner.currentFile,
                truncation: .middle)
            Divider().opacity(0.4)
            row(label: "Date", value: "\(formatBytes(runner.bytesDone)) / \(formatBytes(runner.totalBytes))")
            Divider().opacity(0.4)
            row(label: "Timp", value: timeLine)
            Divider().opacity(0.4)
            row(label: "Fișiere", value: "\(decimal(runner.filesDone)) / \(decimal(runner.totalUnits))")
        }
        .padding(16)
        .frame(maxWidth: 520)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    private func row(label: String, value: String,
                     truncation: Text.TruncationMode = .tail) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.callout)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(truncation)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(value)   // calea întreagă, la hover
        }
    }

    // MARK: Formatare

    /// MB/s cu o zecimală. Inelul arată un număr mare — două zecimale ar
    /// tremura la fiecare cadru fără să spună nimic în plus.
    private func speedValue(_ bytesPerSecond: Double) -> String {
        String(format: "%.1f", bytesPerSecond / 1_000_000)
    }

    private var timeLine: String {
        let elapsed = clock(runner.elapsedSeconds)
        guard let eta = runner.etaSeconds else { return "Timp scurs: \(elapsed)" }
        return "Timp scurs: \(elapsed) | Rămas: \(clock(eta))"
    }

    private func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds)
        let hours = total / 3600
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, (total % 3600) / 60, total % 60)
            : String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func decimal(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
