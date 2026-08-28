import Foundation

/// Setari configurabile de I/O si memorie (2026-08-27) - port Swift al
/// core/io_settings.py. Motiv: raportat un caz real de "Your system has
/// run out of application memory" / swap la maxim, la un transfer de 3 TB
/// - vezi fix-ul de autoreleasepool din copyFileCancelable/genericHash
/// (OffloadEngine.swift), plus aceste setari configurabile de buffer si
/// plafon de memorie (Regula globala "Memory & I/O Performance" din
/// CLAUDE.md).
/// Preset rapid de performanta (2026-08-28) - combina o treapta de buffer
/// cu un plafon de RAM, ca userul sa nu trebuiasca sa aleaga doua valori
/// separat de fiecare data. Valorile individuale (chunkSizeMB/ramLimitMB)
/// raman oricand ajustabile manual dupa aplicarea unui preset.
struct IOPerformancePreset: Identifiable {
    let id: String
    let nameKey: String
    let chunkSizeMB: Int
    let ramLimitMB: Int

    static let all: [IOPerformancePreset] = [
        IOPerformancePreset(id: "eco", nameKey: "io.preset.eco", chunkSizeMB: 4, ramLimitMB: 1024),
        IOPerformancePreset(id: "standard", nameKey: "io.preset.standard", chunkSizeMB: 8, ramLimitMB: 4096),
        IOPerformancePreset(id: "high", nameKey: "io.preset.high", chunkSizeMB: 32, ramLimitMB: 16384),
        IOPerformancePreset(id: "extreme", nameKey: "io.preset.extreme", chunkSizeMB: 64, ramLimitMB: 32768),
    ]
}

enum IOSettings {
    // Trepte granulate (2026-08-28, cerinta explicita) - de la masini
    // modeste (carduri SD pe un Mac mini de baza) pana la statii de
    // productie RAW cu zeci de GB de RAM disponibili.
    static let chunkSizeChoicesMB = [1, 2, 4, 8, 16, 32, 64, 128]
    static let ramLimitChoicesMB = [0, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536] // 0 = fara limita
    static let defaultChunkSizeMB = 8

    private static let chunkKey = "datamover_chunk_size_mb"
    private static let ramLimitKey = "datamover_ram_limit_mb"

    static var chunkSizeMB: Int {
        get {
            let saved = UserDefaults.standard.integer(forKey: chunkKey)
            return saved > 0 ? saved : defaultChunkSizeMB
        }
        set { UserDefaults.standard.set(newValue, forKey: chunkKey) }
    }

    static var chunkSizeBytes: Int { chunkSizeMB * 1024 * 1024 }

    /// 0 = fara limita configurata de user.
    static var ramLimitMB: Int {
        get { UserDefaults.standard.object(forKey: ramLimitKey) as? Int ?? 1024 }
        set { UserDefaults.standard.set(newValue, forKey: ramLimitKey) }
    }

    static var ramLimitBytes: UInt64 { ramLimitMB > 0 ? UInt64(ramLimitMB) * 1024 * 1024 : 0 }

    /// Memoria rezidenta (RSS) a procesului curent, in bytes - foloseste
    /// task_info/mach_task_basic_info, singura API stabila pentru asta pe
    /// macOS (Foundation/AppKit nu expun un echivalent direct).
    static func currentResidentMemoryBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info.resident_size
    }

    /// Backpressure simplu: daca procesul a depasit ramLimitMB configurat,
    /// asteapta putin (verificand cancelul intre timpi) inainte sa lase
    /// urmatorul fisier sa inceapa - previne acumularea nestapanita in
    /// RAM/swap cand scrierea (ex. HDD) e mai lenta decat citirea (ex.
    /// SSD). E o limita ORIENTATIVA la nivel de proces, nu un plafon dur
    /// impus de OS - scopul e sa incetineasca sursa, nu sa garanteze un
    /// maxim absolut.
    static func waitIfOverRAMLimit(cancel: CancelToken, onWarning: ((String) -> Void)? = nil) {
        let limit = ramLimitBytes
        guard limit > 0 else { return }
        guard var used = currentResidentMemoryBytes(), used > limit else { return }

        var waited = 0.0
        var warned = false
        while used > limit && waited < 30.0 {
            if cancel.isCancelled { return }
            if !warned {
                onWarning?(
                    "ATENTIE: memoria aplicatiei (\(used / 1024 / 1024) MB) a depasit limita "
                    + "setata (\(limit / 1024 / 1024) MB) - se asteapta putin inainte de "
                    + "urmatorul fisier (backpressure)."
                )
                warned = true
            }
            Thread.sleep(forTimeInterval: 0.5)
            waited += 0.5
            guard let next = currentResidentMemoryBytes() else { break }
            used = next
        }
    }
}
