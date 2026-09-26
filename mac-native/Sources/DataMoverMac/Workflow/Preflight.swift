import Foundation

// MARK: - Preflight: verificări înainte de primul octet copiat
//
// Pur față de UI: primește căile și întoarce o listă de probleme. Același cod
// e apelat de interfață (ca să arate avertismentele înainte de Start) și de
// `OffloadRunner.start` (apărare în adâncime: nimic periculos nu pornește
// chiar dacă interfața ar fi ocolită).

struct PreflightIssue: Identifiable, Equatable {
    enum Severity: Int, Comparable {
        case warning, blocking
        static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }
    enum Code: String {
        case noSources, noDestinations
        case sourceMissing, destinationMissing, destinationNotWritable, destinationNotDirectory
        case destinationInsideSource, sourceInsideDestination, sameAsSource
        case duplicateDestination, nestedDestinations, sameVolumeAsSource
        case symlinkSource
    }

    var id: String { code.rawValue + "|" + path }
    let code: Code
    let severity: Severity
    let path: String

    var messageKey: String { "preflight.\(code.rawValue)" }
}

enum Preflight {
    /// Cale canonică: absolută, fără `..`, cu symlink-urile rezolvate
    /// (`/tmp` → `/private/tmp`, aliasuri de volum). Comparațiile de
    /// suprapunere se fac DOAR pe forma asta — pe text brut ar rata
    /// `/Volumes/CARD` vs `/Volumes/CARD/`, sau un symlink spre sursă.
    static func canonical(_ path: String) -> String {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            .standardizedFileURL.resolvingSymlinksInPath()
        var p = url.path
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }

    /// `child` e egal cu `parent` sau se află în interiorul lui. Pe
    /// componente, nu pe prefix de text (`/A/Card` nu e în `/A/Car`).
    static func isSameOrInside(_ child: String, _ parent: String) -> Bool {
        let c = (child as NSString).pathComponents
        let p = (parent as NSString).pathComponents
        guard c.count >= p.count else { return false }
        return Array(c.prefix(p.count)) == p
    }

    static func volumeID(of path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let v = try? url.resourceValues(forKeys: [.volumeIdentifierKey]),
              let id = v.volumeIdentifier else { return nil }
        return String(describing: id)
    }

    static func check(sources: [String], destinations: [String],
                      fileManager fm: FileManager = .default) -> [PreflightIssue] {
        var issues: [PreflightIssue] = []
        if sources.isEmpty { issues.append(.init(code: .noSources, severity: .blocking, path: "")) }
        if destinations.isEmpty { issues.append(.init(code: .noDestinations, severity: .blocking, path: "")) }

        var canonSources: [String] = []
        for src in sources {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: src, isDirectory: &isDir) else {
                issues.append(.init(code: .sourceMissing, severity: .blocking, path: src)); continue
            }
            if let attrs = try? fm.attributesOfItem(atPath: src),
               attrs[.type] as? FileAttributeType == .typeSymbolicLink {
                issues.append(.init(code: .symlinkSource, severity: .warning, path: src))
            }
            canonSources.append(canonical(src))
        }

        var seen: [String] = []
        for dest in destinations {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dest, isDirectory: &isDir) else {
                issues.append(.init(code: .destinationMissing, severity: .blocking, path: dest)); continue
            }
            guard isDir.boolValue else {
                issues.append(.init(code: .destinationNotDirectory, severity: .blocking, path: dest)); continue
            }
            if !fm.isWritableFile(atPath: dest) {
                issues.append(.init(code: .destinationNotWritable, severity: .blocking, path: dest))
            }
            let cd = canonical(dest)
            for cs in canonSources {
                if cd == cs {
                    issues.append(.init(code: .sameAsSource, severity: .blocking, path: dest))
                } else if isSameOrInside(cd, cs) {
                    issues.append(.init(code: .destinationInsideSource, severity: .blocking, path: dest))
                } else if isSameOrInside(cs, cd) {
                    // Sursa în destinație: copia s-ar scrie lângă sursă, iar o
                    // reluare ar scana și propriul folder de ieșire.
                    issues.append(.init(code: .sourceInsideDestination, severity: .blocking, path: dest))
                }
            }
            if seen.contains(cd) {
                issues.append(.init(code: .duplicateDestination, severity: .blocking, path: dest))
            } else if seen.contains(where: { isSameOrInside(cd, $0) || isSameOrInside($0, cd) }) {
                issues.append(.init(code: .nestedDestinations, severity: .blocking, path: dest))
            }
            seen.append(cd)

            // Destinație pe același volum cu sursa: nu e o copie de siguranță
            // (un singur disc defect pierde ambele). Permis, dar semnalat.
            if let dv = volumeID(of: dest),
               sources.contains(where: { volumeID(of: $0) == dv }),
               !issues.contains(where: { $0.path == dest && $0.severity == .blocking }) {
                issues.append(.init(code: .sameVolumeAsSource, severity: .warning, path: dest))
            }
        }
        return issues
    }

    static func hasBlocking(_ issues: [PreflightIssue]) -> Bool {
        issues.contains { $0.severity == .blocking }
    }
}
