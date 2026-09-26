#if DEBUG
import SwiftUI

/// Galerie de componente — doar în build-urile DEBUG. Fiecare dispozitiv,
/// stare, incident și capăt de traseu, cu date sintetice, ca să poată fi
/// revăzute în light/dark și în fiecare limbă fără un transfer real.
/// Deschidere: `DATAMOVER_DESIGN_GALLERY=1` la pornire.
struct DesignGallery: View {
    private static let demoMedia: [DeviceKind: MediaClass] = Dictionary(uniqueKeysWithValues: DeviceKind.allCases.map {
        ($0, MediaClass(kind: $0, confidence: .certain, reasonKey: "why.demo", connectionKey: "conn.usb"))
    })

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DM.Space.xl) {
                Text("Design gallery · DataMover v\(UpdateChecker.currentVersion)").font(DM.Font.title)

                DMSectionHeader(title: L.t("gallery.devices"))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: DM.Space.l)], spacing: DM.Space.l) {
                    ForEach(DeviceKind.allCases) { k in
                        VStack(spacing: DM.Space.xs) {
                            DeviceArt(kind: k, size: 160)
                            Text(L.t(k.labelKey)).font(DM.Font.label.weight(.semibold))
                        }
                    }
                }

                DMSectionHeader(title: L.t("gallery.scale"))
                HStack(alignment: .bottom, spacing: DM.Space.l) {
                    ForEach(DeviceKind.allCases) { k in
                        VStack(spacing: DM.Space.xs) {
                            DeviceArt(kind: k, size: RouteLayout.minimumDeviceWidth)
                            DeviceArt(kind: k, size: RouteLayout.deviceWidth(.compact))
                        }
                    }
                }

                DMSectionHeader(title: L.t("gallery.badges"))
                VStack(alignment: .leading, spacing: DM.Space.s) {
                    DeviceBadges(role: .source(1))
                    DeviceBadges(role: .source(2), activity: .reading, sourceCount: 2)
                    DeviceBadges(role: .destination(1), activity: .writing)
                    DeviceBadges(role: .destination(3), warning: true)
                    DeviceBadges(role: .none, online: false)
                }

                DMSectionHeader(title: L.t("gallery.incidents"))
                HStack(alignment: .top, spacing: DM.Space.l) {
                    ForEach(sampleIncidents) { IncidentRow(incident: $0).frame(maxWidth: 300, alignment: .leading) }
                }

                DMSectionHeader(title: L.t("gallery.endpoints"))
                HStack(alignment: .top, spacing: DM.Space.xl) {
                    EndpointView(endpoint: prepareEndpoint, stage: .prepare, density: .large)
                    EndpointView(endpoint: transferEndpoint, stage: .transfer, density: .compact)
                    EndpointView(endpoint: resultEndpoint, stage: .result, density: .compact)
                }

                DMSectionHeader(title: L.t("gallery.shelf"))
                HStack(spacing: DM.Space.l) {
                    DeviceShelfItem(name: "SND_07", media: Self.demoMedia[.sdCard], freeBytes: 215_000_000_000)
                    DeviceShelfItem(name: "LUT-KEY", media: Self.demoMedia[.usbStick], freeBytes: 125_000_000_000)
                    DeviceShelfItem(name: "ARHIVA-2025", media: Self.demoMedia[.hdd], freeBytes: nil, online: false)
                    DeviceShelfItem(name: "NECUNOSCUT", media: Self.demoMedia[.externalDevice], freeBytes: 1_000_000_000_000)
                }
            }
            .padding(DM.Space.xl)
        }
        .frame(minWidth: DM.Layout.windowMinWidth, minHeight: DM.Layout.windowMinHeight)
        .background(DM.background)
    }

    private var sampleIncidents: [Incident] {
        [Incident(id: "b", severity: .blocking, titleKey: "preflight.destinationInsideSource",
                  causeKey: "incident.cause.destinationInsideSource", actionKey: "incident.action.destinationInsideSource",
                  subject: "/Volumes/A001/BACKUP", blocksStart: true),
         Incident(id: "w", severity: .warning, titleKey: "incident.card.title", titleArgs: ["A001"],
                  causeKey: "incident.card.cause", causeArgs: ["2 clipuri de 0 octeți"], actionKey: "incident.card.action"),
         Incident(id: "i", severity: .info, titleKey: "incident.resume.title", causeKey: "incident.resume.cause",
                  causeArgs: ["2026-09-26_Demo_A001"])]
    }

    private var prepareEndpoint: RouteEndpoint {
        var e = RouteEndpoint(path: "/Demo/A001", name: "A001", media: Self.demoMedia[.cfexpress], role: .source(1))
        e.figure = "612 GB"; e.figureCaption = L.t("fig.toCopy"); e.secondary = String(format: L.t("fig.ofVolume"), "1 TB")
        e.warning = true
        return e
    }
    private var transferEndpoint: RouteEndpoint {
        var e = RouteEndpoint(path: "/Demo/SHUTTLE", name: "SHUTTLE-01", media: Self.demoMedia[.ssd], role: .destination(1))
        e.activity = .writing; e.progress = 0.58; e.figure = "58%"; e.figureCaption = L.t("fig.written")
        e.secondary = String(format: L.t("monitor.confirmed"), 124, "355 GB")
        return e
    }
    private var resultEndpoint: RouteEndpoint {
        var e = RouteEndpoint(path: "/Demo/RAID", name: "BACKUP-RAID-02", media: Self.demoMedia[.hdd], role: .destination(2))
        e.outcome = .failed; e.figure = "212"; e.figureCaption = L.t("fig.confirmed")
        e.secondary = String(format: L.t("monitor.failedFiles"), 2)
        return e
    }
}
#endif
