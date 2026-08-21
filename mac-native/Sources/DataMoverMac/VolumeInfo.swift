import Foundation

/// Un volum montat sub /Volumes — echivalentul Swift al lui
/// core.offload_engine.list_mounted_volumes() (doar ramura macOS a
/// acelei functii Python; nu are nevoie de ramurile Windows/Linux aici).
struct VolumeInfo: Identifiable, Hashable {
    let id: String   // path-ul, unic
    let name: String
    let path: String
    let freeBytes: Int64?

    static func detectAll() -> [VolumeInfo] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: "/Volumes") else { return [] }
        return names.sorted().compactMap { name in
            let path = "/Volumes/\(name)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
            let free = try? fm.attributesOfFileSystem(forPath: path)[.systemFreeSize] as? Int64
            return VolumeInfo(id: path, name: name, path: path, freeBytes: free ?? nil)
        }
    }
}

func formatBytes(_ bytes: Int64?) -> String {
    guard let bytes else { return "—" }
    return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
