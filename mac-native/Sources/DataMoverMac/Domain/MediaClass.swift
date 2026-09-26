import Foundation

// MARK: - Clasificarea mediilor (pură, fără I/O)
//
// Decide ce OBIECT arată interfața pentru o cale, doar din fapte citite de la
// sistem (`MediaFacts`, adunate de `MediaProbe`). Regula de bază: nu afirmăm
// un tip mai precis decât poate detecta sistemul. Când certitudinea lipsește,
// rezultatul e `.externalDevice` („dispozitiv extern”). Numele volumului e
// doar un indiciu secundar: nu poate contrazice un fapt.

enum DeviceKind: String, CaseIterable, Identifiable, Codable {
    case cfexpress, sdCard, memoryCard, ssd, hdd, usbStick, internalVolume, folder, externalDevice
    var id: String { rawValue }
    var labelKey: String { "device.\(rawValue)" }
}

enum MediumType: String, Codable { case solidState, rotational, unknown }

/// Faptele disponibile despre o cale. Toate opționale: sistemul nu le
/// expune mereu (volume de rețea, share-uri de virtualizare, imagini disc).
struct MediaFacts: Equatable {
    /// Calea e rădăcina unui volum (altfel e un folder ales manual).
    var isVolumeRoot = true
    /// `DADeviceProtocol`: "USB", "PCI-Express", "Thunderbolt", "Secure Digital",
    /// "Apple Fabric", "Serial ATA", "Virtual Interface"…
    var deviceProtocol: String? = nil
    var isInternal: Bool? = nil
    var isRemovableMedia: Bool? = nil
    var isEjectable: Bool? = nil
    var isNetwork = false
    /// IOKit „Device Characteristics / Medium Type”.
    var medium: MediumType = .unknown
    var totalBytes: Int64? = nil
    /// `DADeviceModel` / `DAMediaName` (ex. „CFexpress Card Reader”).
    var deviceModel: String? = nil
    /// Structură de card de cameră recunoscută la rădăcină (CameraCardDetector).
    var cameraCardStructure = false
    var volumeName = ""
}

struct MediaClass: Equatable {
    enum Confidence: String { case certain, likely, hint, fallback }
    let kind: DeviceKind
    let confidence: Confidence
    /// Cheia de localizare a motivului (ce fapt a decis).
    let reasonKey: String
    /// Cheia conexiunii afișate (USB, Thunderbolt/PCIe, cititor SD…), dacă e cunoscută.
    let connectionKey: String?
}

enum MediaClassifier {
    static let cardMaxBytes: Int64 = 4 * 1_000_000_000_000 // 4 TB — peste asta nu e card de cameră

    static func connectionKey(_ f: MediaFacts) -> String? {
        if f.isNetwork { return "conn.network" }
        switch f.deviceProtocol {
        case "USB": return "conn.usb"
        case "Thunderbolt", "PCI-Express": return f.isInternal == true ? "conn.internal" : "conn.thunderbolt"
        case "Secure Digital": return "conn.sdReader"
        case "Serial ATA", "SATA": return "conn.sata"
        case "Apple Fabric": return "conn.internal"
        case "Virtual Interface": return "conn.virtual"
        default: return f.isInternal == true ? "conn.internal" : nil
        }
    }

    private static func model(_ f: MediaFacts, contains s: String) -> Bool {
        (f.deviceModel ?? "").range(of: s, options: .caseInsensitive) != nil
    }

    private static func name(_ f: MediaFacts, contains words: [String]) -> Bool {
        words.contains { f.volumeName.range(of: $0, options: .caseInsensitive) != nil }
    }

    static func classify(_ f: MediaFacts) -> MediaClass {
        let conn = connectionKey(f)
        func r(_ k: DeviceKind, _ c: MediaClass.Confidence, _ why: String) -> MediaClass {
            MediaClass(kind: k, confidence: c, reasonKey: "why.\(why)", connectionKey: conn)
        }

        // 1. O cale care nu e rădăcina unui volum = folder ales manual.
        if !f.isVolumeRoot { return r(.folder, .certain, "folder") }
        // 2. Stocarea internă a Mac-ului.
        if f.isInternal == true || f.deviceProtocol == "Apple Fabric" { return r(.internalVolume, .certain, "internal") }
        // 3. Volume fără dispozitiv fizic identificabil.
        if f.isNetwork { return r(.externalDevice, .certain, "network") }
        if f.deviceProtocol == "Virtual Interface" { return r(.externalDevice, .certain, "virtual") }
        // 4. Cititorul SD integrat raportează protocolul „Secure Digital”.
        if f.deviceProtocol == "Secure Digital" { return r(.sdCard, .certain, "sdReader") }

        let small = (f.totalBytes ?? .max) <= cardMaxBytes
        // 5. Card de cameră într-un cititor extern: structura de cameră la
        //    rădăcină + mediu AMOVIBIL (un SSD USB raportează ne-amovibil, deci
        //    o copie de card pe SSD rămâne SSD) + capacitate de card. Tipul
        //    exact (CFexpress/SD) doar dacă modelul cititorului/mediului îl spune.
        if f.cameraCardStructure && small && f.isRemovableMedia == true {
            let cf = model(f, contains: "CFexpress"), sd = model(f, contains: "SD")
            if cf && !sd { return r(.cfexpress, .likely, "cameraCardModelCF") }
            if sd && !cf { return r(.sdCard, .likely, "cameraCardModelSD") }
            return r(.memoryCard, .likely, "cameraCard")
        }
        // 6. Stick USB: mediu amovibil pe USB, fără structură de cameră.
        if f.deviceProtocol == "USB" && f.isRemovableMedia == true && small && f.medium != .rotational {
            return r(.usbStick, .likely, "usbRemovable")
        }
        // 7. Disc extern: tipul mediului vine din IOKit.
        switch f.medium {
        case .solidState: return r(.ssd, .likely, "solidState")
        case .rotational: return r(.hdd, .likely, "rotational")
        case .unknown: break
        }
        // 8. Indicii secundare din nume — doar când faptele tac.
        if name(f, contains: ["RAID", "HDD"]) { return r(.hdd, .hint, "nameHintHDD") }
        if name(f, contains: ["SSD"]) { return r(.ssd, .hint, "nameHintSSD") }
        if f.isRemovableMedia == true && name(f, contains: ["CARD", "SDCARD", "EOS_DIGITAL", "A00"]) {
            return r(.memoryCard, .hint, "nameHintCard")
        }
        return r(.externalDevice, .fallback, "unknown")
    }
}
