import Foundation

// MARK: - Domain: stări și rezultate (sursa unică de adevăr)
//
// Tot ce decide „a reușit / n-a reușit” un transfer stă aici, pur, fără UI și
// fără I/O. Interfața, rapoartele și istoricul citesc aceste valori; nu își
// calculează propriile verdicte din contoare.

/// Faza reală a unui transfer. Ordinea e ordinea din lanț.
enum TransferPhase: String, Codable, CaseIterable {
    case idle, preparing, copying, verifying, reporting, finished

    var labelKey: String { "phase.\(rawValue)" }
}

/// Cum a fost confirmată integritatea unui fișier. Trei niveluri distincte,
/// niciodată amestecate în rapoarte.
enum VerificationDepth: String, Codable {
    /// Doar numărul de octeți scriși = numărul de octeți citiți.
    case sizeOnly
    /// Checksum calculat în flux: sursa din bucățile citite, destinația din
    /// exact aceleași bucăți în momentul scrierii (nu recitită de pe disc).
    case streamChecksum
    /// Destinația recitită complet de pe disc după flush și comparată.
    case readBack

    static func `for`(_ model: VerificationModel, readBack: Bool) -> VerificationDepth {
        if model == .sizeOnly { return .sizeOnly }
        return readBack ? .readBack : .streamChecksum
    }

    var labelKey: String { "depth.\(rawValue)" }
}

/// Verdictul unei destinații la final.
enum DestinationOutcome: String, Codable {
    /// Toate fișierele confirmate, nicio eroare, nicio reîncercare.
    case verified
    /// Toate fișierele confirmate, dar au existat reîncercări reușite.
    case verifiedWithWarnings
    /// Cel puțin un fișier neconfirmat (eroare sau nepotrivire).
    case failed
    /// Oprit de utilizator înainte de final.
    case cancelled

    static func evaluate(failCount: Int, recoveredCount: Int, cancelled: Bool) -> DestinationOutcome {
        if cancelled { return .cancelled }
        if failCount > 0 { return .failed }
        if recoveredCount > 0 { return .verifiedWithWarnings }
        return .verified
    }

    var isSafe: Bool { self == .verified || self == .verifiedWithWarnings }
}

/// Verdictul global. Nu poate fi „succes” dacă O SINGURĂ destinație a eșuat.
enum TransferOutcome: String, Codable {
    case success
    case successWithWarnings
    case partialFailure
    case failure
    case cancelled

    static func evaluate(_ destinations: [DestinationOutcome]) -> TransferOutcome {
        guard !destinations.isEmpty else { return .failure }
        if destinations.contains(.cancelled) { return .cancelled }
        let failed = destinations.filter { $0 == .failed }.count
        if failed == destinations.count { return .failure }
        if failed > 0 { return .partialFailure }
        if destinations.contains(.verifiedWithWarnings) { return .successWithWarnings }
        return .success
    }

    var labelKey: String { "outcome.\(rawValue)" }

    /// Ejectarea automată a sursei e permisă DOAR aici: fiecare destinație are
    /// o copie confirmată. Un avertisment (reîncercare reușită) nu blochează,
    /// o singură destinație eșuată sau o anulare blochează.
    var allowsSourceEject: Bool { self == .success || self == .successWithWarnings }
}

/// Stare live, per destinație, publicată către UI.
struct DestinationLiveState: Identifiable, Equatable {
    var id: String { destRoot }
    let destRoot: String
    var bytesWritten: Int64 = 0
    var filesConfirmed = 0
    var filesFailed = 0
    var available = true
    var outcome: DestinationOutcome? = nil
}

// MARK: - Fișiere parțiale

/// Numele temporar sub care se scrie un fișier până e confirmat. Punct la
/// început (ascuns în Finder, sărit de scanarea surselor) + sufix propriu.
/// Un fișier cu acest nume NU e niciodată raportat ca verificat.
enum PartialFile {
    static let suffix = ".dmpart"

    static func path(for finalPath: String) -> String {
        let dir = (finalPath as NSString).deletingLastPathComponent
        let name = (finalPath as NSString).lastPathComponent
        return (dir as NSString).appendingPathComponent(".\(name)\(suffix)")
    }

    static func isPartial(_ name: String) -> Bool {
        name.hasPrefix(".") && name.hasSuffix(suffix)
    }
}
