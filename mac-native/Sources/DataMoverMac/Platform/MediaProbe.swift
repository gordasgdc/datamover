import Foundation
import DiskArbitration
import IOKit
import os

/// Adaptor de platformă: adună `MediaFacts` pentru o cale, pasiv (fără I/O pe
/// mediu în afara metadatelor), și le clasifică cu `MediaClassifier`.
/// Rezultatele se păstrează în cache per cale; `forget` la demontare.
enum MediaProbe {
    private static let cache = OSAllocatedUnfairLock(initialState: [String: MediaClass]())

    static func cached(_ path: String) -> MediaClass? { cache.withLock { $0[path] } }
    static func forget(_ path: String) { _ = cache.withLock { $0.removeValue(forKey: path) } }

    /// Clasifică în fundal; `cardInfo` (dacă e deja cunoscut) evită o a doua
    /// enumerare a cardului.
    static func classify(path: String, cameraCard: Bool? = nil) async -> MediaClass {
        if let c = cached(path) { return c }
        let result = await Task.detached(priority: .utility) { () -> MediaClass in
            #if DEBUG
            if let demo = demoClass(for: path) { return demo }
            #endif
            var facts = gatherFacts(path: path)
            facts.cameraCardStructure = cameraCard ?? (facts.isVolumeRoot && CameraCardDetector.detect(root: path) != nil)
            return MediaClassifier.classify(facts)
        }.value
        cache.withLock { $0[path] = result }
        return result
    }

    static func gatherFacts(path: String) -> MediaFacts {
        var f = MediaFacts()
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [.volumeURLKey, .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
                                         .volumeIsLocalKey, .volumeTotalCapacityKey, .volumeNameKey]
        let v = try? url.resourceValues(forKeys: keys)
        if let root = v?.volume {
            f.isVolumeRoot = root.standardizedFileURL.resolvingSymlinksInPath().path
                == url.standardizedFileURL.resolvingSymlinksInPath().path
        }
        f.isInternal = v?.volumeIsInternal
        f.isRemovableMedia = v?.volumeIsRemovable
        f.isEjectable = v?.volumeIsEjectable
        f.isNetwork = v?.volumeIsLocal == false
        f.totalBytes = v?.volumeTotalCapacity.map(Int64.init)
        f.volumeName = v?.volumeName ?? (path as NSString).lastPathComponent

        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
              let d = DADiskCopyDescription(disk) as? [String: Any] else { return f }
        f.deviceProtocol = d["DADeviceProtocol"] as? String
        if let isInt = d["DADeviceInternal"] as? Bool { f.isInternal = isInt }
        if let removable = d["DAMediaRemovable"] as? Bool { f.isRemovableMedia = removable }
        if let net = d["DAVolumeNetwork"] as? Bool, net { f.isNetwork = true }
        f.deviceModel = [d["DADeviceModel"] as? String, d["DAMediaName"] as? String].compactMap { $0 }.joined(separator: " ")
        let media = DADiskCopyIOMedia(disk)
        if media != 0 {
            defer { IOObjectRelease(media) }
            if let ch = IORegistryEntrySearchCFProperty(media, kIOServicePlane, "Device Characteristics" as CFString, nil,
                                                        IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)) as? [String: Any] {
                switch ch["Medium Type"] as? String {
                case "Solid State": f.medium = .solidState
                case "Rotational": f.medium = .rotational
                default: break
                }
            }
        }
        return f
    }

    #if DEBUG
    /// Mod demo (capturi): folderele sintetice primesc tipul din prefixul
    /// numelui. Există doar în build-urile DEBUG, doar cu `DATAMOVER_UI_DEMO`.
    static func demoClass(for path: String) -> MediaClass? {
        guard let root = ProcessInfo.processInfo.environment["DATAMOVER_UI_DEMO"],
              path.hasPrefix(root) else { return nil }
        let name = (path as NSString).lastPathComponent.uppercased()
        let table: [(String, DeviceKind, String?)] = [
            ("CF_", .cfexpress, "conn.usb"), ("SD_", .sdCard, "conn.sdReader"), ("CARD_", .memoryCard, "conn.usb"),
            ("SSD_", .ssd, "conn.thunderbolt"), ("RAID_", .hdd, "conn.usb"), ("USB_", .usbStick, "conn.usb"),
            ("INT_", .internalVolume, "conn.internal"), ("EXT_", .externalDevice, "conn.usb"), ("DIR_", .folder, nil),
        ]
        for (prefix, kind, conn) in table where name.hasPrefix(prefix) {
            return MediaClass(kind: kind, confidence: .certain, reasonKey: "why.demo", connectionKey: conn)
        }
        return nil
    }
    #endif
}
