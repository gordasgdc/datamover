#if DEBUG
import SwiftUI

/// Galerie de componente — doar în build-urile DEBUG. Arată fiecare stare
/// tipizată a design system-ului cu date sintetice, ca să poată fi revăzută
/// în light/dark și în fiecare limbă fără un transfer real.
/// Deschidere: `DATAMOVER_DESIGN_GALLERY=1` la pornire.
struct DesignGallery: View {
    private let statuses: [(DMStatus, String)] = [
        (.neutral, "destOutcome.cancelled"), (.active, "dest.inProgress"),
        (.verified, "destOutcome.verified"), (.warning, "destOutcome.verifiedWithWarnings"),
        (.failure, "destOutcome.failed"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DM.Space.l) {
                Text("Design gallery · DataMover v\(UpdateChecker.currentVersion)").font(DM.Font.title)
                DMSectionHeader(title: "DMStatusBadge")
                HStack { ForEach(statuses.indices, id: \.self) { DMStatusBadge(status: statuses[$0].0, text: L.t(statuses[$0].1)) } }

                DMSectionHeader(title: "DMPanel · DMMetric")
                DMPanel {
                    HStack {
                        DMMetric(label: L.t("monitor.read"), value: "812,4 MB/s")
                        DMMetric(label: L.t("monitor.write"), value: "1,62 GB/s", detail: String(format: L.t("monitor.copies"), 2))
                        DMMetric(label: L.t("monitor.eta"), value: "04:12", detail: L.t("monitor.elapsed") + " 01:03")
                    }
                }

                DMSectionHeader(title: "DMKeyValue · DMCapacityBar")
                DMPanel {
                    VStack(alignment: .leading, spacing: DM.Space.s) {
                        DMKeyValue(key: L.t("prep.folder"), value: "2026-09-26_Demo_A001", mono: true)
                        DMKeyValue(key: L.t("prep.method"), value: L.t(VerificationDepth.streamChecksum.labelKey))
                        DMKeyValue(key: L.t("dest.title"), value: L.t("destOutcome.failed"), status: .failure)
                        DMCapacityBar(total: 1_000, free: 600, incoming: 200).frame(maxWidth: DM.Layout.capacityBarMaxWidth)
                        DMCapacityBar(total: 1_000, free: 100, incoming: 300).frame(maxWidth: DM.Layout.capacityBarMaxWidth)
                    }
                }

                DMSectionHeader(title: "DestinationProgressRow")
                DestinationProgressRow(state: DestinationLiveState(destRoot: "/Demo/BACKUP_A", bytesWritten: 600, filesConfirmed: 12),
                                       expectedBytes: 1_000)
                DestinationProgressRow(state: DestinationLiveState(destRoot: "/Demo/BACKUP_B", bytesWritten: 300, filesConfirmed: 5,
                                                                   filesFailed: 1, available: false),
                                       expectedBytes: 1_000)
            }
            .padding(DM.Space.l)
        }
        .frame(minWidth: 760, minHeight: 560)
        .background(DM.background)
    }
}
#endif
