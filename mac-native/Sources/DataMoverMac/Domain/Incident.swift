import Foundation
import CoreGraphics

// MARK: - Incidente (pur)
//
// Un incident are severitate, cauză și — când există — acțiunea recomandată.
// Doar incidentele `blocksStart` dezactivează Start (preflight blocant);
// avertismentele și informațiile nu. Textele sunt chei de localizare +
// argumente, ca modelul să fie testabil fără UI.

struct Incident: Identifiable, Equatable {
    enum Severity: Int, Comparable {
        case info = 0, warning = 1, blocking = 2
        static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
        var labelKey: String { "severity.\(self)" }
    }
    let id: String
    let severity: Severity
    let titleKey: String
    var titleArgs: [String] = []
    let causeKey: String
    var causeArgs: [String] = []
    var actionKey: String? = nil
    var actionArgs: [String] = []
    /// Căi sau fișiere afectate (afișate monospace, trunchiate la mijloc).
    var subject: String = ""
    var blocksStart = false
}

enum IncidentBuilder {
    struct PrepareInput {
        var issues: [PreflightIssue] = []
        /// Avertismentele detectorului de card, per sursă.
        var cardWarnings: [(source: String, text: String)] = []
        /// Destinațiile unde transferul NU încape (cu octeții lipsă).
        var spaceShort: [(dest: String, missing: Int64)] = []
        var depth: VerificationDepth = .streamChecksum
        var unknownDevices: [String] = []
        var resumingFolder: String? = nil
    }

    static func prepare(_ i: PrepareInput) -> [Incident] {
        var out: [Incident] = []
        for issue in i.issues {
            let blocking = issue.severity == .blocking
            out.append(Incident(id: "pf-\(issue.id)", severity: blocking ? .blocking : .warning,
                                titleKey: issue.messageKey, causeKey: "incident.cause.\(issue.code.rawValue)",
                                actionKey: "incident.action.\(issue.code.rawValue)", subject: issue.path, blocksStart: blocking))
        }
        for (idx, w) in i.cardWarnings.enumerated() {
            out.append(Incident(id: "card-\(idx)", severity: .warning, titleKey: "incident.card.title",
                                titleArgs: [(w.source as NSString).lastPathComponent], causeKey: "incident.card.cause",
                                causeArgs: [w.text], actionKey: "incident.card.action"))
        }
        for s in i.spaceShort {
            // Nu blochează: pornirea cere confirmare explicită (decizia operatorului).
            out.append(Incident(id: "space-\(s.dest)", severity: .warning, titleKey: "incident.space.title",
                                titleArgs: [(s.dest as NSString).lastPathComponent], causeKey: "incident.space.cause",
                                causeArgs: [formatBytes(s.missing)], actionKey: "incident.space.action", subject: s.dest))
        }
        if i.depth == .sizeOnly {
            out.append(Incident(id: "depth", severity: .warning, titleKey: "incident.sizeOnly.title",
                                causeKey: "incident.sizeOnly.cause", actionKey: "incident.sizeOnly.action"))
        }
        for d in i.unknownDevices {
            out.append(Incident(id: "unknown-\(d)", severity: .info, titleKey: "incident.unknown.title",
                                titleArgs: [(d as NSString).lastPathComponent], causeKey: "incident.unknown.cause", subject: d))
        }
        if let f = i.resumingFolder {
            out.append(Incident(id: "resume", severity: .info, titleKey: "incident.resume.title",
                                causeKey: "incident.resume.cause", causeArgs: [f]))
        }
        return sorted(out)
    }

    /// În timpul transferului: doar ce s-a întâmplat efectiv.
    static func transfer(_ states: [DestinationLiveState]) -> [Incident] {
        var out: [Incident] = []
        for s in states {
            let name = (s.destRoot as NSString).lastPathComponent
            if !s.available {
                out.append(Incident(id: "gone-\(s.destRoot)", severity: .blocking, titleKey: "incident.disconnected.title",
                                    titleArgs: [name], causeKey: "incident.disconnected.cause",
                                    actionKey: "incident.disconnected.action", subject: s.destRoot))
            } else if s.filesFailed > 0 {
                out.append(Incident(id: "fail-\(s.destRoot)", severity: .blocking, titleKey: "incident.failing.title",
                                    titleArgs: [name, "\(s.filesFailed)"], causeKey: "incident.failing.cause",
                                    actionKey: "incident.failing.action", subject: s.destRoot))
            }
        }
        return sorted(out)
    }

    static func result(_ results: [DestinationResult]) -> [Incident] {
        var out: [Incident] = []
        for r in results {
            let name = (r.destRoot as NSString).lastPathComponent
            if r.cancelled {
                out.append(Incident(id: "cancel-\(r.destRoot)", severity: .info, titleKey: "incident.cancelled.title",
                                    titleArgs: [name], causeKey: "incident.cancelled.cause", actionKey: "incident.cancelled.action"))
            } else if r.failCount > 0 {
                out.append(Incident(id: "unconfirmed-\(r.destRoot)", severity: .blocking, titleKey: "incident.unconfirmed.title",
                                    titleArgs: [name, "\(r.failCount)"], causeKey: "incident.unconfirmed.cause",
                                    actionKey: "incident.unconfirmed.action", subject: r.csvPath ?? r.destRoot))
            } else if r.recoveredCount > 0 {
                out.append(Incident(id: "recovered-\(r.destRoot)", severity: .warning, titleKey: "incident.recovered.title",
                                    titleArgs: [name, "\(r.recoveredCount)"], causeKey: "incident.recovered.cause",
                                    actionKey: "incident.recovered.action"))
            }
        }
        return sorted(out)
    }

    static func sorted(_ list: [Incident]) -> [Incident] {
        list.enumerated().sorted { a, b in
            a.element.severity != b.element.severity ? a.element.severity > b.element.severity : a.offset < b.offset
        }.map(\.element)
    }

    static func blocksStart(_ list: [Incident]) -> Bool { list.contains { $0.blocksStart } }
}

// MARK: - Layout adaptiv al traseului (pur)

enum RouteLayout {
    enum Mode: Equatable { case horizontal, stacked }
    enum Density: Equatable { case large, compact }

    /// Lățimea minimă pentru traseul complet pe orizontală: coloana surselor,
    /// nodul de verificare, coloana destinațiilor și spațiile dintre ele.
    static let horizontalMinWidth: CGFloat = 820

    static func mode(width: CGFloat) -> Mode {
        width >= horizontalMinWidth ? .horizontal : .stacked
    }

    /// Obiecte mari doar dacă încap toate pe înălțime; altfel compacte (dar
    /// niciodată sub pragul de lizibilitate — vezi `deviceWidth`).
    static func density(mode: Mode, height: CGFloat, sources: Int, destinations: Int) -> Density {
        let rows = max(sources, destinations)
        switch mode {
        case .horizontal: return rows <= 2 && height >= 420 ? .large : .compact
        case .stacked: return rows <= 1 && height >= 560 ? .large : .compact
        }
    }

    static func deviceWidth(_ d: Density) -> CGFloat { d == .large ? 150 : 92 }
    static let minimumDeviceWidth: CGFloat = 72
}

enum RouteMotion {
    /// Fluxul pe traseu se animă doar cât se scrie efectiv și doar dacă
    /// utilizatorul nu a cerut Reduce Motion.
    static func animatesFlow(isRunning: Bool, isPaused: Bool, reduceMotion: Bool) -> Bool {
        isRunning && !isPaused && !reduceMotion
    }
}
