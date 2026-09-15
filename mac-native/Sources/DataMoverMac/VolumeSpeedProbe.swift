import Foundation
import IOKit
import os

/// Tipul conexiunii unui volum, citit din IOKit — NU măsurat prin scriere.
///
/// DE CE NU UN TEST REAL DE VITEZĂ: ar însemna să scriem un fișier de probă
/// pe discul utilizatorului, la montare, fără ca el să ceară. Pe un card de
/// filmare tocmai introdus, asta e exact ce nu vrei: I/O nesolicitat pe
/// mediul de pe care urmează să copiezi. Protocolul spune deja ce contează
/// („USB 2.0" e o veste importantă înainte să pornești un transfer de 500 GB),
/// iar citirea lui e pasivă și instantanee.
struct VolumeSpeedProbe: Sendable {
    /// „Thunderbolt", „USB 3.1", „NVMe", „SATA"… sau `nil` dacă nu se poate
    /// determina — atunci nu se afișează nicio insignă, în loc să afișăm una
    /// care spune „necunoscut".
    let connection: String?
    let isInternal: Bool

    var badgeText: String? {
        if let connection { return connection }
        return isInternal ? "Intern" : nil
    }
}

enum VolumeSpeedProbeService {
    private static let cache = OSAllocatedUnfairLock(initialState: [String: VolumeSpeedProbe]())

    /// Rezultatul deja cunoscut, dacă există. Sincron și instantaneu —
    /// interfața îl poate citi direct la desenare.
    static func cached(for path: String) -> VolumeSpeedProbe? {
        cache.withLock { $0[path] }
    }

    /// Sondare în fundal, cu prioritate scăzută.
    ///
    /// `Task.detached(priority: .utility)`: interogarea IOKit e rapidă, dar
    /// traversează un arbore de dispozitive, iar la montarea simultană a mai
    /// multor volume nu are ce căuta pe firul principal.
    @discardableResult
    static func probe(path: String) async -> VolumeSpeedProbe? {
        if let existing = cached(for: path) { return existing }

        let result = await Task.detached(priority: .utility) { () -> VolumeSpeedProbe in
            let url = URL(fileURLWithPath: path)
            let values = try? url.resourceValues(forKeys: [.volumeIsInternalKey])
            let isInternal = values?.volumeIsInternal ?? false
            return VolumeSpeedProbe(connection: connectionKind(for: path, isInternal: isInternal),
                                    isInternal: isInternal)
        }.value

        cache.withLock { $0[path] = result }
        return result
    }

    /// Șterge intrarea la demontare — un alt disc montat pe aceeași cale
    /// (`/Volumes/Untitled`) nu trebuie să moștenească insigna precedentului.
    static func forget(path: String) {
        _ = cache.withLock { $0.removeValue(forKey: path) }
    }

    private static func connectionKind(for path: String, isInternal: Bool) -> String? {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, URL(fileURLWithPath: path) as CFURL),
              let description = DADiskCopyDescription(disk) as? [String: Any] else {
            return isInternal ? "Intern" : nil
        }

        // `DADeviceProtocol` vine ca "USB", "Thunderbolt", "PCI-Express"…
        if let proto = description["DADeviceProtocol"] as? String, !proto.isEmpty {
            switch proto {
            // "Apple Fabric" e protocolul stocarii interne pe Apple Silicon.
            // Verificat live pe acest Mac — pe disc intern se raporteaza exact
            // asa, iar "Apple Fabric" pe o insigna nu spune nimic utilizatorului.
            case "Apple Fabric": return "NVMe"
            case "PCI-Express": return isInternal ? "NVMe" : "PCIe"
            case "Thunderbolt": return "Thunderbolt"
            case "Serial ATA": return "SATA"
            default: return proto
            }
        }
        return isInternal ? "Intern" : nil
    }
}
