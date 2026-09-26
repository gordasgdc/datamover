import Foundation

/// Capacitatea unui volum (total + liber), citită o singură dată per
/// actualizare de listă. Liber = capacitate utilizabilă reală pe APFS.
struct VolumeCapacity {
    let total: Int64
    let free: Int64

    static func of(_ path: String) -> VolumeCapacity? {
        let url = URL(fileURLWithPath: path)
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                         .volumeAvailableCapacityForImportantUsageKey,
                                                         .volumeAvailableCapacityKey]),
              let total = v.volumeTotalCapacity else { return nil }
        // exFAT/FAT: „important usage” vine 0 (nu nil) — vezi OffloadRunner.freeBytes.
        let important = v.volumeAvailableCapacityForImportantUsage ?? 0
        let free = important > 0 ? important : Int64(v.volumeAvailableCapacity ?? 0)
        return VolumeCapacity(total: Int64(total), free: free)
    }
}
