import Foundation

/// [2026-09-03] Generator de fisier MHL (Media Hash List, versiunea 1.1) —
/// standardul de facto prin care un ofloader de platou preda datele catre
/// post-productie.
///
/// DE CE: pana acum DataMover producea CSV + PDF, adica rapoarte pe care le
/// citeste un OM. Un MHL e acelasi lucru, dar citit de MASINA: Silverstack,
/// YoYotta, ShotPut Pro, Resolve si orice casa de post pot re-verifica
/// automat, luni mai tarziu, ca fiecare fisier de pe LTO/NAS e bit-identic
/// cu ce a iesit din camera in ziua filmarii. Fara MHL, un card descarcat
/// cu DataMover nu poate intra intr-un flux profesional — cu el, poate.
///
/// Fisierul se scrie LANGA datele copiate (in radacina folderului de
/// destinatie) si contine cai RELATIVE la propria pozitie, exact ca cele
/// scrise de ShotPut Pro — altfel mutarea folderului pe alt disc ar
/// invalida tot.
///
/// MEMORIE (Regula 21): intrarile NU se acumuleaza in RAM. Fiecare `<hash>`
/// se scrie imediat intr-un fisier temporar `.part`; la `close()` se
/// compune fisierul final (antet + corp), citind `.part`-ul in bucati.
/// Motivul pentru care corpul nu poate fi scris direct in fisierul final:
/// `<creatorinfo>` sta obligatoriu PRIMUL in schema MHL si contine
/// `<finishdate>`, pe care il stim abia la sfarsit.
final class MHLWriter {
    /// Algoritmii pe care ii accepta schema MHL 1.1. SHA-256/SHA-512 NU
    /// fac parte din standard — daca userul alege unul dintre ele,
    /// verificarea si rapoartele CSV/PDF raman complete, doar MHL-ul nu se
    /// genereaza (vezi `element(for:)` -> nil).
    static func element(for model: VerificationModel) -> String? {
        switch model {
        case .md5: return "md5"
        case .sha1: return "sha1"
        case .xxhash64: return "xxhash64be"
        case .sha256, .sha512, .sizeOnly: return nil
        }
    }

    static func isSupported(_ model: VerificationModel) -> Bool { element(for: model) != nil }

    private let finalPath: String
    private let partPath: String
    private let hashElement: String
    private let toolName: String
    private let startedAt: Date
    private var partHandle: FileHandle?
    private(set) var entryCount = 0

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    init?(path: String, model: VerificationModel, toolName: String, startedAt: Date) {
        guard let element = Self.element(for: model) else { return nil }
        self.finalPath = path
        self.partPath = path + ".part"
        self.hashElement = element
        self.toolName = toolName
        self.startedAt = startedAt
        FileManager.default.createFile(atPath: partPath, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: partPath) else { return nil }
        self.partHandle = handle
    }

    /// Un fisier verificat cu succes. Se apeleaza DOAR pentru fisierele cu
    /// status OK/SARIT — un MHL nu are voie sa contina un fisier care n-a
    /// trecut verificarea, altfel ar certifica date corupte.
    func add(relPath: String, size: Int64, modificationDate: Date?, hashHex: String, hashedAt: Date) {
        guard let handle = partHandle, !hashHex.isEmpty else { return }
        var xml = "  <hash>\n"
        xml += "    <file>\(Self.escape(relPath))</file>\n"
        xml += "    <size>\(size)</size>\n"
        if let mod = modificationDate {
            xml += "    <lastmodificationdate>\(Self.iso.string(from: mod))</lastmodificationdate>\n"
        }
        xml += "    <\(hashElement)>\(hashHex)</\(hashElement)>\n"
        xml += "    <hashdate>\(Self.iso.string(from: hashedAt))</hashdate>\n"
        xml += "  </hash>\n"
        autoreleasepool {
            try? handle.write(contentsOf: Data(xml.utf8))
        }
        entryCount += 1
    }

    /// Scrie fisierul MHL final. Intoarce calea lui, sau nil daca n-a
    /// existat nicio intrare valida (nu lasam pe disc un MHL gol, care ar
    /// parea o certificare a zero fisiere).
    @discardableResult
    func close(finishedAt: Date) -> String? {
        try? partHandle?.close()
        partHandle = nil
        defer { try? FileManager.default.removeItem(atPath: partPath) }
        guard entryCount > 0 else { return nil }

        var header = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        header += "<hashlist version=\"1.1\">\n"
        header += "  <creatorinfo>\n"
        header += "    <name>\(Self.escape(NSFullUserName()))</name>\n"
        header += "    <username>\(Self.escape(NSUserName()))</username>\n"
        header += "    <hostname>\(Self.escape(Host.current().localizedName ?? ProcessInfo.processInfo.hostName))</hostname>\n"
        header += "    <tool>\(Self.escape(toolName))</tool>\n"
        header += "    <startdate>\(Self.iso.string(from: startedAt))</startdate>\n"
        header += "    <finishdate>\(Self.iso.string(from: finishedAt))</finishdate>\n"
        header += "  </creatorinfo>\n"

        FileManager.default.createFile(atPath: finalPath, contents: nil)
        guard let out = FileHandle(forWritingAtPath: finalPath),
              let part = FileHandle(forReadingAtPath: partPath) else { return nil }
        defer { try? out.close(); try? part.close() }
        do {
            try out.write(contentsOf: Data(header.utf8))
            while true {
                var stop = false
                try autoreleasepool {
                    guard let chunk = try part.read(upToCount: 256 * 1024), !chunk.isEmpty else {
                        stop = true
                        return
                    }
                    try out.write(contentsOf: chunk)
                }
                if stop { break }
            }
            try out.write(contentsOf: Data("</hashlist>\n".utf8))
        } catch {
            return nil
        }
        return finalPath
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
    }
}
