import XCTest
@testable import DataMoverMac

final class MediaClassifierTests: XCTestCase {
    func c(_ f: MediaFacts) -> MediaClass { MediaClassifier.classify(f) }

    func testManualFolderIsFolderOnlyWhenNotVolumeRoot() {
        XCTAssertEqual(c(MediaFacts(isVolumeRoot: false, deviceProtocol: "USB", medium: .solidState)).kind, .folder)
        // O rădăcină de volum nu devine niciodată folder.
        XCTAssertNotEqual(c(MediaFacts(isVolumeRoot: true, deviceProtocol: "USB", medium: .solidState)).kind, .folder)
    }

    func testInternalVolume() {
        XCTAssertEqual(c(MediaFacts(deviceProtocol: "Apple Fabric", isInternal: true, medium: .solidState)).kind, .internalVolume)
        XCTAssertEqual(c(MediaFacts(deviceProtocol: "PCI-Express", isInternal: true)).kind, .internalVolume)
    }

    /// Faptele reale citite pe Mac-ul de dezvoltare (vezi PROJECT_STATE):
    /// SSD USB = USB, ne-amovibil, Solid State; SSD Thunderbolt = PCI-Express.
    func testExternalSSDFromRealFacts() {
        let usbSSD = c(MediaFacts(deviceProtocol: "USB", isInternal: false, isRemovableMedia: false, medium: .solidState))
        XCTAssertEqual(usbSSD.kind, .ssd); XCTAssertEqual(usbSSD.connectionKey, "conn.usb")
        let tb = c(MediaFacts(deviceProtocol: "PCI-Express", isInternal: false, isRemovableMedia: false, medium: .solidState))
        XCTAssertEqual(tb.kind, .ssd); XCTAssertEqual(tb.connectionKey, "conn.thunderbolt")
    }

    func testRotationalIsHDD() {
        XCTAssertEqual(c(MediaFacts(deviceProtocol: "USB", isInternal: false, medium: .rotational)).kind, .hdd)
    }

    func testBuiltInSDReaderIsSDCard() {
        let r = c(MediaFacts(deviceProtocol: "Secure Digital", isInternal: false, isRemovableMedia: true))
        XCTAssertEqual(r.kind, .sdCard); XCTAssertEqual(r.confidence, .certain)
    }

    /// Card de cameră într-un cititor: tipul exact DOAR dacă modelul îl spune.
    func testCameraCardInReaderIsNotOverclaimed() {
        var f = MediaFacts(deviceProtocol: "USB", isInternal: false, isRemovableMedia: true, totalBytes: 512_000_000_000)
        f.cameraCardStructure = true
        XCTAssertEqual(c(f).kind, .memoryCard)
        f.deviceModel = "ProGrade CFexpress Card Reader"
        XCTAssertEqual(c(f).kind, .cfexpress)
        f.deviceModel = "SD/CFexpress Dual Reader"
        XCTAssertEqual(c(f).kind, .memoryCard, "cititor dual: tipul nu poate fi dedus")
        f.deviceModel = "UHS-II SD Reader"
        XCTAssertEqual(c(f).kind, .sdCard)
    }

    /// Un SSD USB (ne-amovibil) cu o copie de card la rădăcină rămâne SSD.
    func testCardStructureOnNonRemovableSSDStaysSSD() {
        var f = MediaFacts(deviceProtocol: "USB", isInternal: false, isRemovableMedia: false, medium: .solidState, totalBytes: 2_000_000_000_000)
        f.cameraCardStructure = true
        XCTAssertEqual(c(f).kind, .ssd)
    }

    func testUSBStick() {
        XCTAssertEqual(c(MediaFacts(deviceProtocol: "USB", isInternal: false, isRemovableMedia: true, totalBytes: 128_000_000_000)).kind, .usbStick)
    }

    func testVirtualAndNetworkAreExternalDevices() {
        XCTAssertEqual(c(MediaFacts(deviceProtocol: "Virtual Interface", isRemovableMedia: true, medium: .solidState)).kind, .externalDevice)
        XCTAssertEqual(c(MediaFacts(isNetwork: true)).kind, .externalDevice)
    }

    func testFallbackWhenFactsAreMissing() {
        let r = c(MediaFacts(volumeName: "Untitled"))
        XCTAssertEqual(r.kind, .externalDevice); XCTAssertEqual(r.confidence, .fallback)
    }

    /// Numele e indiciu secundar: nu contrazice un fapt.
    func testNameIsOnlyASecondaryHint() {
        XCTAssertEqual(c(MediaFacts(deviceProtocol: "USB", isInternal: false, medium: .unknown, volumeName: "BACKUP-RAID-02")).kind, .hdd)
        XCTAssertEqual(c(MediaFacts(deviceProtocol: "USB", isInternal: false, medium: .unknown, volumeName: "BACKUP-RAID-02")).confidence, .hint)
        XCTAssertEqual(c(MediaFacts(deviceProtocol: "USB", isInternal: false, medium: .solidState, volumeName: "BACKUP-RAID-02")).kind, .ssd,
                       "faptul (solid-state) bate numele")
        XCTAssertEqual(c(MediaFacts(deviceProtocol: "Apple Fabric", isInternal: true, volumeName: "SD_CARD")).kind, .internalVolume)
    }

    func testRealProbeOfTempFolderIsFolder() {
        let sb = Sandbox()
        let f = MediaProbe.gatherFacts(path: sb.dir("x"))
        XCTAssertFalse(f.isVolumeRoot)
        XCTAssertEqual(MediaClassifier.classify(f).kind, .folder)
    }
}

final class IncidentTests: XCTestCase {
    func testOnlyBlockingPreflightBlocksStart() {
        var i = IncidentBuilder.PrepareInput()
        i.issues = [PreflightIssue(code: .sameVolumeAsSource, severity: .warning, path: "/d")]
        i.cardWarnings = [("/Volumes/A001", "2 clipuri de 0 octeți")]
        i.spaceShort = [("/Volumes/SSD", 1_000)]
        i.depth = .sizeOnly
        i.unknownDevices = ["/Volumes/X"]
        let warnOnly = IncidentBuilder.prepare(i)
        XCTAssertFalse(IncidentBuilder.blocksStart(warnOnly), "avertismentele și informațiile nu blochează Start")
        XCTAssertTrue(warnOnly.contains { $0.severity == .info })
        i.issues.append(PreflightIssue(code: .destinationInsideSource, severity: .blocking, path: "/s/d"))
        let blocked = IncidentBuilder.prepare(i)
        XCTAssertTrue(IncidentBuilder.blocksStart(blocked))
        XCTAssertEqual(blocked.first?.severity, .blocking, "critic primul")
        XCTAssertEqual(blocked.last?.severity, .info)
    }

    func testEveryIncidentHasCauseAndLocalizedText() {
        var i = IncidentBuilder.PrepareInput()
        i.issues = [.noSources, .noDestinations, .sourceMissing, .destinationMissing, .destinationNotWritable, .destinationNotDirectory,
                    .destinationInsideSource, .sourceInsideDestination, .sameAsSource, .duplicateDestination, .nestedDestinations,
                    .sameVolumeAsSource, .symlinkSource].map { PreflightIssue(code: $0, severity: .blocking, path: "/p") }
        i.cardWarnings = [("/a", "x")]; i.spaceShort = [("/d", 5)]; i.depth = .sizeOnly; i.unknownDevices = ["/u"]; i.resumingFolder = "F"
        var all = IncidentBuilder.prepare(i)
        all += IncidentBuilder.transfer([DestinationLiveState(destRoot: "/g", available: false),
                                         DestinationLiveState(destRoot: "/f", filesFailed: 2)])
        var failed = DestinationResult(destRoot: "/r", okCount: 1, skipCount: 0, failCount: 2, cancelled: false, csvPath: nil, pdfPath: nil)
        var recovered = failed; recovered = DestinationResult(destRoot: "/q", okCount: 3, skipCount: 0, failCount: 0, cancelled: false,
                                                               csvPath: nil, pdfPath: nil, recoveredCount: 1)
        failed.htmlPath = nil
        all += IncidentBuilder.result([failed, recovered,
                                       DestinationResult(destRoot: "/c", okCount: 0, skipCount: 0, failCount: 0, cancelled: true, csvPath: nil, pdfPath: nil)])
        for inc in all {
            for key in [inc.titleKey, inc.causeKey] + (inc.actionKey.map { [$0] } ?? []) {
                for lang in AppLanguage.allCases {
                    let entry = L.extraTable[key] ?? L.routeTable[key]
                    XCTAssertFalse((entry?[lang] ?? "").isEmpty, "\(key) lipsește în \(lang)")
                }
            }
        }
        XCTAssertTrue(IncidentBuilder.transfer([DestinationLiveState(destRoot: "/ok")]).isEmpty)
    }
}

final class RouteLayoutTests: XCTestCase {
    func testModeSwitchesAtMinimumWidth() {
        // Fereastra minimă (1024) minus coloana de incidente compactă → traseu orizontal compact.
        XCTAssertEqual(RouteLayout.mode(width: 1024 - DM.Layout.incidentsWidthCompact - 1), .compactHorizontal)
        XCTAssertEqual(RouteLayout.mode(width: RouteLayout.compactMinWidth - 1), .stacked)
        // 1280 × 800 implicit → traseu complet.
        XCTAssertEqual(RouteLayout.mode(width: 1280 - DM.Layout.incidentsWidth - 1), .horizontal)
        XCTAssertEqual(RouteLayout.mode(width: RouteLayout.horizontalMinWidth), .horizontal)
        XCTAssertEqual(RouteLayout.mode(width: RouteLayout.horizontalMinWidth - 1), .compactHorizontal)
    }

    /// Pragul orizontal cuprinde efectiv coloanele traseului: altfel, între
    /// suma lor și prag, traseul s-ar tăia.
    func testHorizontalThresholdFitsRouteColumns() {
        let needed = DM.Layout.routeSourceColumn + DM.Layout.routeNodeWidth + DM.Layout.routeDestinationColumn
            + 2 * DM.Layout.routeMinGap + 2 * DM.Space.xl + 4 * DM.Space.s
        XCTAssertLessThanOrEqual(needed, RouteLayout.horizontalMinWidth)
        let compact = DM.Layout.routeSourceColumnCompact + DM.Layout.routeNodeWidthCompact + DM.Layout.routeDestinationColumnCompact
            + 2 * DM.Layout.routeMinGapCompact + 2 * DM.Space.xl + 4 * DM.Space.s
        XCTAssertLessThanOrEqual(compact, RouteLayout.compactMinWidth)
        XCTAssertEqual(RouteLayout.density(mode: .compactHorizontal, height: 900, sources: 1, destinations: 1), .compact)
    }

    func testDensityForOneToFourDestinations() {
        XCTAssertEqual(RouteLayout.density(mode: .horizontal, height: 520, sources: 1, destinations: 2), .large)
        XCTAssertEqual(RouteLayout.density(mode: .horizontal, height: 520, sources: 1, destinations: 4), .compact)
        XCTAssertEqual(RouteLayout.density(mode: .horizontal, height: 380, sources: 1, destinations: 1), .compact)
        XCTAssertEqual(RouteLayout.density(mode: .stacked, height: 700, sources: 2, destinations: 1), .compact)
        // Chiar compact, obiectele rămân peste pragul de recunoaștere.
        XCTAssertGreaterThanOrEqual(RouteLayout.deviceWidth(.compact), RouteLayout.minimumDeviceWidth)
    }

    func testReduceMotionStopsFlowAnimation() {
        XCTAssertTrue(RouteMotion.animatesFlow(isRunning: true, isPaused: false, reduceMotion: false))
        XCTAssertFalse(RouteMotion.animatesFlow(isRunning: true, isPaused: false, reduceMotion: true))
        XCTAssertFalse(RouteMotion.animatesFlow(isRunning: true, isPaused: true, reduceMotion: false))
        XCTAssertFalse(RouteMotion.animatesFlow(isRunning: false, isPaused: false, reduceMotion: false))
    }

    func testRouteTableIsCompleteAndConsistent() {
        let spec = try! NSRegularExpression(pattern: "%[@d]")
        for (key, entry) in L.routeTable {
            let sig = AppLanguage.allCases.map { lang -> [String] in
                let s = entry[lang] ?? ""
                XCTAssertFalse(s.isEmpty, "\(key) \(lang)")
                return spec.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { (s as NSString).substring(with: $0.range) }
            }
            XCTAssertTrue(sig.allSatisfy { $0 == sig[0] }, key)
        }
        for k in DeviceKind.allCases { XCTAssertNotNil(L.routeTable[k.labelKey], k.labelKey) }
    }
}
