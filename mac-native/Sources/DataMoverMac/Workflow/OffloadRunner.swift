import Foundation
import AppKit

// MARK: - OffloadRunner (orchestrare, expus catre SwiftUI)

/// [2026-09-03] Rezultatul verificarii de spatiu liber, pentru o singura
/// destinatie — prima gasita insuficienta. `Identifiable` ca sa poata fi
/// legat direct la un `.alert(item:)` in SwiftUI.
struct SpaceShortfall: Identifiable {
    let id = UUID()
    let destination: String
    let needed: Int64
    let free: Int64
}

/// Orchestreaza cate un DestinationJob per destinatie, in paralel (ca
/// thread-urile din Python), si expune progresul global catre SwiftUI
/// prin @Published — legat direct in ContentView.
@MainActor
final class OffloadRunner: ObservableObject {
    @Published var isRunning = false
    @Published var progressPercent = 0
    @Published var filesDone = 0
    @Published var totalUnits = 0
    @Published var statusText = L.t("status.ready")
    @Published var speedText = ""
    @Published var lastResults: [DestinationResult] = []
    /// Plafon de proba depasit (2026-08-30) - vezi LicenseManager.
    /// trialMaxTransferBytes. ContentView asculta asta si arata un alert
    /// cu buton de activare, in loc sa lase Start-ul sa esueze tacut.
    @Published var trialLimitExceededBytes: Int64? = nil
    /// [2026-09-03] Setat o singura data la prima eroare de tip "Permission
    /// denied" intalnita pe parcursul unui transfer — ContentView asculta
    /// asta si arata un alert cu buton direct catre panoul de Full Disk
    /// Access din System Settings, in loc sa lase userul sa se descurce
    /// singur cu un mesaj generic "EROARE" din raport.
    @Published var permissionErrorPath: String? = nil
    /// [2026-09-03] Verificare de spatiu liber INAINTE de a copia primul
    /// octet. Pana acum, un card de 512 GB pornit catre un disc cu 80 GB
    /// liberi copia linistit ore intregi si esua abia la mijloc, cu zeci de
    /// erori "No space left on device" in raport — exact scenariul in care
    /// operatorul crede ca are backup si nu are. Orice ofloader profesional
    /// (ShotPut Pro, Silverstack) refuza sa porneasca in acest caz.
    @Published var spaceShortfall: SpaceShortfall? = nil
    /// Feed-ul stil Terminal din footer (vezi DestinationJob.onActivity).
    /// Capat la `activityLogLimit` — nu tinem tot istoricul unui transfer
    /// de mii de fisiere in memorie/UI, doar ce s-a intamplat recent.
    @Published private(set) var activityLines: [String] = []
    /// Faza reală (Domain) și stările per destinație — sursa unică pentru UI.
    @Published private(set) var phase: TransferPhase = .idle
    @Published private(set) var destinationStates: [DestinationLiveState] = []
    @Published private(set) var lastOutcome: TransferOutcome? = nil
    /// Probleme de preflight găsite de `start` (apărare în adâncime).
    @Published var preflightIssues: [PreflightIssue] = []
    @Published private(set) var lastFolderName = ""
    @Published private(set) var lastVerificationDepth: VerificationDepth = .streamChecksum
    private let activityLogLimit = 200

    // Pauza (2026-08-28) - vezi PauseToken. Butonul de Pauza din UI leaga
    // direct de isPaused; job-urile de destinatie citesc acelasi token.
    @Published var isPaused = false
    private var pauseToken = PauseToken()

    // Buffer/Memorie afisate live in UI (2026-08-28) - "Buffer Alocat: X |
    // Utilizat: Y", actualizate la fiecare progres (advance()).
    @Published var bufferAllocatedText = ""
    @Published var memoryUsedText = ""

    // MARK: - Metrice pentru panoul de monitorizare (2026-09-15)
    //
    // DOAR oglinzi ale valorilor pe care motorul le calcula deja. Nicio
    // bucla de I/O, niciun algoritm de copiere si niciun buffer nu se
    // schimba — `advance()` primea deja `size`, iar `startTime`/`bytesDone`
    // existau ca variabile private. Aici devin doar VIZIBILE pentru UI.

    /// Octeti SCRISI in total (suma pe toate destinatiile) — motorul
    /// contorizeaza per destinatie, la fel ca `totalUnits`.
    @Published private(set) var bytesDone: Int64 = 0

    /// Totalul de scris, tot pe toate destinatiile.
    @Published private(set) var totalBytes: Int64 = 0

    /// Cate destinatii primesc aceleasi fisiere. Face diferenta dintre
    /// viteza de CITIRE si cea de SCRIERE: sursa se citeste o data, dar se
    /// scrie de `destinationCount` ori (vezi FanOutCopier).
    @Published private(set) var destinationCount = 1

    @Published private(set) var elapsedSeconds: Double = 0

    /// Calea relativa a fisierului aflat in lucru.
    @Published private(set) var currentFile = ""

    /// Viteza de SCRIERE, in octeti/s. Aceeasi valoare din care se compune
    /// `speedText`, expusa numeric pentru inele.
    var writeBytesPerSecond: Double {
        elapsedSeconds > 0 ? Double(bytesDone) / elapsedSeconds : 0
    }

    /// Viteza de CITIRE: sursa se citeste o singura data, indiferent de cate
    /// copii se scriu. NU o masuratoare separata — o impartire onesta a
    /// aceleiasi contorizari, ca sa nu inventam un numar.
    var readBytesPerSecond: Double {
        destinationCount > 0 ? writeBytesPerSecond / Double(destinationCount) : 0
    }

    /// Secunde ramase, estimate din ritmul de pana acum. `nil` cat timp nu
    /// exista destule date ca estimarea sa insemne ceva.
    var etaSeconds: Double? {
        guard bytesDone > 0, totalBytes > bytesDone, elapsedSeconds > 1 else { return nil }
        let remaining = Double(totalBytes - bytesDone)
        return remaining / writeBytesPerSecond
    }

    private var cancelToken = CancelToken()
    private var startTime: Date?
    /// ID-ul jobului curent/ultim — corelează toate intrările din jurnal.
    @Published private(set) var jobID = ""
    private let diag = StructuredLog.shared

    /// Sunet, notificare de sistem și istoric persistent. Testele îl opresc
    /// ca să nu scrie în istoricul real al utilizatorului.
    nonisolated(unsafe) static var sideEffectsEnabled = true

    /// Numele folderului de destinatie pentru o pereche proiect/card - pur,
    /// fara efecte laterale, ca ContentView sa poata verifica dinainte
    /// daca exista deja o destinatie cu acest nume (vezi
    /// existingNonEmptyDestinations) inainte sa porneasca efectiv start().
    /// [2026-09-03] Numele se compune acum dintr-un SABLON configurabil
    /// (vezi NamingTemplate.swift). Sablonul implicit produce exact acelasi
    /// rezultat ca varianta veche, hardcodata: `<data>_<Proiect>_<Card>`.
    func folderName(project: String, card: String,
                    template: String = NamingTemplate.defaultTemplate,
                    camera: String = "", operatorName: String = "") -> String {
        NamingTemplate.render(template, context: NamingTemplate.Context(
            project: project, card: card, camera: camera, operatorName: operatorName, date: Date()))
    }

    /// Cauta un folder deja EXISTENT (creat oricand, nu neaparat azi) cu
    /// acelasi proiect/card la oricare destinatie - bug real gasit
    /// 2026-08-28: `folderName(project:card:)` include data zilei curente,
    /// deci un transfer de 4 TB care trece peste miezul noptii (sau e
    /// reluat a doua zi) calcula un nume de folder NOU, iar verificarea
    /// de duplicate se uita gresit la folderul nou (inca inexistent), nu
    /// la cel vechi cu sute de GB deja copiate - userul nu mai era
    /// intrebat NIMIC si aplicatia pornea o copiere completa, paralela,
    /// intr-un folder separat. Daca gaseste mai multe (ex. incercari din
    /// zile diferite), alege cel mai RECENT (prefixul de data se sorteaza
    /// lexicografic identic cu ordinea cronologica).
    ///
    /// [2026-09-03] Cu sabloane libere de denumire, cautarea nu mai poate
    /// fi hardcodata pe sufixul `_Proiect_Card`. Comparam acum "miezul
    /// stabil" al sablonului (tot, mai putin data/ora) — vezi
    /// NamingTemplate.stableCore.
    func findExistingFolderName(destinations: [String], project: String, card: String,
                                template: String = NamingTemplate.defaultTemplate,
                                camera: String = "", operatorName: String = "") -> String? {
        let core = NamingTemplate.stableCore(template, context: NamingTemplate.Context(
            project: project, card: card, camera: camera, operatorName: operatorName, date: Date()))
        guard !core.isEmpty, core != "Transfer" else { return nil }
        var candidates: [String] = []
        for dest in destinations {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: dest) else { continue }
            candidates.append(contentsOf: items.filter { $0.contains(core) })
        }
        return candidates.sorted().last
    }

    /// Un nume de folder liber (neexistent inca la nicio destinatie),
    /// pornind de la `base` si adaugand " (2)", " (3)"... - folosit de
    /// optiunea "Creeaza folder nou" din dialogul de duplicate.
    func freeFolderName(base: String, destinations: [String]) -> String {
        var candidate = base
        var suffix = 2
        while !existingNonEmptyDestinations(destinations: destinations, folderName: candidate).isEmpty {
            candidate = "\(base) (\(suffix))"
            suffix += 1
        }
        return candidate
    }

    /// Destinatiile la care folderul `folderName` exista DEJA si contine
    /// cel putin un fisier - semnal ca acest transfer ar suprascrie/
    /// duplica date, nu ca porneste intr-un folder gol. Apelat de
    /// ContentView INAINTE de start(), ca sa decida daca arata dialogul
    /// "Reia / Folder nou / Suprascrie".
    func existingNonEmptyDestinations(destinations: [String], folderName: String) -> [String] {
        destinations.filter { dest in
            let targetRoot = (dest as NSString).appendingPathComponent(folderName)
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: targetRoot) else { return false }
            // ignoram fisierele proprii de raport/checkpoint - un folder
            // care contine DOAR un checkpoint dintr-o rulare intrerupta
            // fara niciun fisier real copiat inca nu e "duplicat", e
            // pur si simplu o reluare normala.
            return contents.contains { !$0.hasPrefix("offload_checkpoint") && !$0.hasPrefix("offload_report_") }
        }
    }

    /// Sterge continutul folderelor deja existente la `folderName`, pe
    /// TOATE destinatiile date - folosit de optiunea "Suprascrie complet".
    func clearExistingFolders(destinations: [String], folderName: String) {
        for dest in destinations {
            let targetRoot = (dest as NSString).appendingPathComponent(folderName)
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: targetRoot) else { continue }
            for item in contents {
                try? FileManager.default.removeItem(atPath: (targetRoot as NSString).appendingPathComponent(item))
            }
        }
    }

    func togglePause() {
        guard isRunning else { return }
        diag.log(.info, "job", isPaused ? "job.resumed" : "job.paused", isPaused ? "Reluat" : "Pauză", job: jobID)
        if isPaused {
            pauseToken.resume()
            isPaused = false
            statusText = L.t("footer.copying")
        } else {
            pauseToken.pause()
            isPaused = true
            statusText = L.t("footer.paused")
        }
    }

    private func updateMemoryDisplay() {
        let limit = IOSettings.ramLimitMB
        bufferAllocatedText = limit == 0 ? "Fara limita" : formatBytes(Int64(limit) * 1024 * 1024)
        if let used = IOSettings.currentResidentMemoryBytes() {
            memoryUsedText = formatBytes(Int64(used))
        }
    }

    /// Spatiul liber real al volumului care contine `path`.
    /// `volumeAvailableCapacityForImportantUsage` e valoarea corecta pe
    /// APFS (tine cont de snapshot-uri purjabile), nu `systemFreeSize`,
    /// care raporteaza mai putin decat poate elibera efectiv sistemul;
    /// al doilea ramane doar ca rezerva pe volume non-APFS.
    private func freeBytes(at path: String) -> Int64? {
        let url = URL(fileURLWithPath: path)
        if let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let capacity = values.volumeAvailableCapacityForImportantUsage {
            return Int64(capacity)
        }
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
           let free = attrs[.systemFreeSize] as? NSNumber {
            return free.int64Value
        }
        return nil
    }

    /// Prima destinatie la care NU incape transferul, sau nil daca incape
    /// peste tot. La o reluare (folderul tinta exista deja) scade fisierele
    /// deja prezente cu aceeasi dimensiune — altfel o reluare la 90% ar fi
    /// blocata cerand spatiu pentru datele deja copiate.
    func spaceShortfall(destinations: [String], files: [FileEntry], folderName: String) -> SpaceShortfall? {
        let fm = FileManager.default
        for dest in destinations {
            guard let free = freeBytes(at: dest) else { continue }
            let targetRoot = (dest as NSString).appendingPathComponent(folderName)
            let targetExists = fm.fileExists(atPath: targetRoot)
            var needed: Int64 = 0
            for file in files {
                if targetExists {
                    let destPath = (targetRoot as NSString).appendingPathComponent(file.relPath)
                    if let size = (try? fm.attributesOfItem(atPath: destPath)[.size] as? Int64) ?? nil,
                       size == file.size {
                        continue
                    }
                }
                needed += file.size
            }
            // Marja: 1% din transfer, minim 100 MB. Un volum umplut la
            // refuz devine imprevizibil (metadate, jurnal), iar rapoartele
            // CSV/PDF/MHL se scriu tot acolo, la final.
            let margin = max(Int64(100 * 1024 * 1024), needed / 100)
            if free < needed + margin {
                return SpaceShortfall(destination: dest, needed: needed, free: free)
            }
        }
        return nil
    }

    func start(sources: [String], destinations: [String],
               verificationModel: VerificationModel = .md5,
               exclusions: [String] = [], resume: Bool = true,
               meta: ProductionMeta = ProductionMeta(),
               folderTemplate: String = NamingTemplate.defaultTemplate,
               folderNameOverride: String? = nil,
               cloudRemote: String = "", cloudRemoteFolder: String = "",
               generateMHL: Bool = true, retryFailedFiles: Bool = true,
               ejectSourceWhenDone: Bool = false,
               ignoreSpaceWarning: Bool = false,
               readBackVerification: Bool = false) {
        guard !isRunning else { return }

        let issues = Preflight.check(sources: sources, destinations: destinations)
        preflightIssues = issues
        let job = StructuredLog.newID()
        diag.log(.info, "preflight", "preflight.checked", "Preflight la pornire", job: job,
                 fields: ["blocking": "\(issues.filter { $0.severity == .blocking }.count)",
                          "warnings": "\(issues.filter { $0.severity == .warning }.count)",
                          "codes": issues.map(\.code.rawValue).joined(separator: ",")])
        if Preflight.hasBlocking(issues) {
            diag.log(.warning, "preflight", "preflight.blocked", "Pornire blocată de preflight", job: job)
            statusText = L.t("preflight.blockedStatus")
            for issue in issues where issue.severity == .blocking {
                logActivity("Preflight: \(L.t(issue.messageKey)) \(issue.path)")
            }
            return
        }

        var files: [FileEntry] = []
        for src in sources {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: src, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                files.append(contentsOf: listAllFiles(root: src, exclusions: exclusions))
            } else {
                let name = (src as NSString).lastPathComponent
                if isExcluded(filename: name, exclusions: exclusions) { continue }
                let size = (try? FileManager.default.attributesOfItem(atPath: src)[.size] as? Int64) ?? nil
                let attrs = (try? FileManager.default.attributesOfItem(atPath: src)) ?? [:]
                files.append(FileEntry(fullPath: src, relPath: name, size: size ?? 0, mtimeMicros: mtimeMicros(attrs)))
            }
        }
        guard !files.isEmpty else {
            statusText = L.t("footer.noFiles")
            return
        }
        // [2026-09-26] Coliziuni de nume între surse: blocant (altfel a doua
        // sursă ar înlocui fișierul confirmat al primeia, raportat totuși OK).
        let collisions = Preflight.nameCollisions(files)
        if !collisions.isEmpty {
            preflightIssues += collisions
            statusText = L.t("preflight.blockedStatus")
            diag.log(.warning, "preflight", "preflight.nameCollision", "Coliziune de nume între surse", job: job,
                     fields: ["count": "\(collisions.count)"])
            return
        }

        // Plafon de proba (2026-08-30) - vezi LicenseManager.
        // trialMaxTransferBytes. Verificat pe DIMENSIUNEA TOTALA a
        // transferului (suma tuturor fisierelor sursa), o singura data,
        // inainte de a porni orice copiere - nu un plafon per fisier, ca
        // sa nu poata fi ocolit trimitand multe fisiere mici.
        if !LicenseManager.shared.isLicensed {
            let totalBytes = files.reduce(Int64(0)) { $0 + $1.size }
            if totalBytes > LicenseManager.trialMaxTransferBytes {
                trialLimitExceededBytes = totalBytes
                diag.log(.warning, "license", "job.blocked.trialLimit", "Plafonul probei depășit", job: job,
                         fields: ["bytes": "\(totalBytes)"])
                statusText = L.t("trial.sizeLimitStatus")
                return
            }
        }
        trialLimitExceededBytes = nil

        // Numele folderului de destinatie: <data>_<Proiect>_<Card>, exact ca
        // in aplicatia Windows — implicit "Proiect"/"Card" daca lasi campurile
        // goale. `folderNameOverride` vine de la optiunea "Creeaza folder
        // nou" din dialogul de duplicate (ContentView), cand userul alege
        // sa NU foloseasca numele implicit deja existent la destinatie.
        let folderName = folderNameOverride ?? self.folderName(
            project: meta.project, card: meta.card, template: folderTemplate,
            camera: meta.camera, operatorName: meta.operatorName)
        let sourceRoot = sources.first
        let identity = SourceIdentity.compute(sources: sources, files: files)

        // [2026-09-03] Spatiu insuficient: nu pornim deloc. ContentView
        // arata un alert cu cifrele exacte si un buton "Continuă oricum",
        // care re-apeleaza start() cu ignoreSpaceWarning: true — decizia
        // ramane a userului, dar informata, nu descoperita dupa 3 ore.
        if !ignoreSpaceWarning,
           let shortfall = spaceShortfall(destinations: destinations, files: files, folderName: folderName) {
            spaceShortfall = shortfall
            diag.log(.warning, "preflight", "job.blocked.space", "Spațiu insuficient la destinație", job: job,
                     dest: destinationLogID(shortfall.destination),
                     fields: ["needed": "\(shortfall.needed)", "free": "\(shortfall.free)", "path": shortfall.destination])
            statusText = L.t("space.statusBlocked")
            return
        }
        spaceShortfall = nil

        cancelToken = CancelToken()
        pauseToken = PauseToken()
        isPaused = false
        isRunning = true
        phase = .preparing
        lastOutcome = nil
        lastFolderName = folderName
        lastVerificationDepth = VerificationDepth.for(verificationModel, readBack: readBackVerification)
        destinationStates = destinations.map { DestinationLiveState(destRoot: $0) }
        startTime = Date()
        bytesDone = 0
        filesDone = 0
        totalUnits = files.count * destinations.count
        destinationCount = max(destinations.count, 1)
        totalBytes = files.reduce(Int64(0)) { $0 + $1.size } * Int64(destinationCount)
        elapsedSeconds = 0
        currentFile = ""
        progressPercent = 0
        statusText = L.t("footer.copying")
        speedText = ""
        lastResults = []
        // [2026-09-03] Feed-ul NU se mai goleste la start: avertismentele
        // detectorului de carduri (structura, clipuri de 0 octeti) apar
        // INAINTE de start si tocmai ele trebuie sa ramana vizibile in
        // timpul transferului. Separatorul marcheaza inceputul clar.
        logActivity("──────── Transfer nou: \(folderName) ────────")
        jobID = job
        diag.log(.info, "job", "job.started", "Transfer pornit", job: job, fields: [
            "sources": "\(sources.count)", "destinations": "\(destinations.count)", "files": "\(files.count)",
            "bytes": "\(files.reduce(Int64(0)) { $0 + $1.size })", "model": verificationModel.rawValue,
            "depth": VerificationDepth.for(verificationModel, readBack: readBackVerification).rawValue,
            "resume": "\(resume)", "destIDs": destinations.map(destinationLogID).joined(separator: ","),
        ])
        permissionErrorPath = nil
        updateMemoryDisplay()

        let token = cancelToken
        let pauseTok = pauseToken
        let started = Date()
        let trimmedRemote = cloudRemote.trimmingCharacters(in: .whitespaces)
        let chunkSize = IOSettings.chunkSizeBytes

        // [M1 FAZA 2, 2026-09-06] Un DestinationContext per destinatie —
        // doar starea/bookkeeping-ul (CSV, MHL, checkpoint, contoare), FARA
        // propria bucla de copiere. Vezi DestinationContext.swift.
        let contexts: [DestinationContext] = destinations.map { dest in
            let cloudQueue: CloudUploadQueue? = trimmedRemote.isEmpty ? nil : CloudUploadQueue(
                remote: trimmedRemote, remoteFolder: cloudRemoteFolder,
                localRoot: (dest as NSString).appendingPathComponent(folderName),
                onLine: { [weak self] line in Task { @MainActor [weak self] in self?.logActivity(line) } }
            )
            return DestinationContext(
                destRoot: dest, folderName: folderName, verificationModel: verificationModel,
                generateMHL: generateMHL, meta: meta, sourceRoot: sourceRoot, sourceIdentity: identity,
                cloudUploadQueue: cloudQueue, startedAt: started,
                onActivity: { line in Task { @MainActor [weak self] in self?.logActivity(line) } },
                onPermissionError: { path in
                    Task { @MainActor [weak self] in
                        // Doar prima eroare conteaza pentru alert - nu vrem sa
                        // suprascriem calea aratata userului cu fisiere
                        // ulterioare care esueaza din ACEEASI cauza.
                        if self?.permissionErrorPath == nil { self?.permissionErrorPath = path }
                    }
                }
            )
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let depthText = L.t(VerificationDepth.for(verificationModel, readBack: readBackVerification).labelKey)
            for ctx in contexts {
                ctx.jobID = job
                ctx.verificationDescription = "\(verificationModel.label) — \(depthText)"
                ctx.prepare(resume: resume)
            }
            Task { @MainActor [weak self] in self?.phase = .copying }
            let readBack = readBackVerification

            var cancelledFlag = false

            /// O SINGURA trecere peste `entries`, cu fan-out per fisier —
            /// folosita ATAT pentru bucla principala CAT si pentru
            /// reincercarea automata de la final (acelasi cod, ca cele doua
            /// cai sa nu diveraga — disciplina deja stabilita in acest
            /// fisier pentru `processOne`/`retryFailed`).
            func runPass(entries: [FileEntry], isRetry: Bool) {
                for entry in entries {
                    if token.isCancelled { cancelledFlag = true; return }
                    if pauseTok.isPaused {
                        Task { @MainActor [weak self] in self?.logActivity("Pauza — transferul e oprit temporar de utilizator.") }
                        pauseTok.waitWhilePaused(cancel: token)
                        if token.isCancelled { cancelledFlag = true; return }
                    }
                    IOSettings.waitIfOverRAMLimit(cancel: token) { warning in
                        Task { @MainActor [weak self] in self?.logActivity(warning) }
                    }

                    var toCopy: [DestinationContext] = []
                    var toVerify: [(ctx: DestinationContext, expected: String?)] = []
                    for ctx in contexts {
                        if isRetry {
                            guard ctx.failedRelPaths.contains(entry.relPath) else { continue }
                            ctx.prepareForRetry(entry: entry)
                            toCopy.append(ctx)
                            continue
                        }
                        switch ctx.classify(entry: entry, allowSkipExisting: resume) {
                        case .revalidate(let expected):
                            toVerify.append((ctx, expected))
                        case .needsCopy:
                            toCopy.append(ctx)
                        }
                    }

                    // Fisiere deja existente, cu marime identica — verificate
                    // fara recopiere. Hash-ul sursei se calculeaza O SINGURA
                    // DATA si e reutilizat pentru toate destinatiile din
                    // acest bucket, daca sunt mai multe.
                    if !toVerify.isEmpty {
                        var verifiedSourceHash: String?
                        for (ctx, expected) in toVerify {
                            ctx.onActivity("Verificare fisier existent: \(entry.relPath)…")
                            if verifiedSourceHash == nil {
                                verifiedSourceHash = try? hashOfFile(path: entry.fullPath, model: verificationModel, cancel: token, chunkSize: chunkSize)
                            }
                            let dstHash = try? hashOfFile(path: ctx.destPath(for: entry), model: verificationModel, cancel: token, chunkSize: chunkSize)
                            switch RevalidationPolicy.decide(model: verificationModel, expected: expected,
                                                             sourceHash: verifiedSourceHash, destinationHash: dstHash) {
                            case .accept:
                                ctx.recordVerifiedExisting(entry: entry, srcHash: verifiedSourceHash ?? "", dstHash: dstHash ?? "")
                                let root = ctx.destRoot
                                Task { @MainActor [weak self] in self?.advance(size: entry.size, file: entry.relPath, dest: root, confirmed: true) }
                            case .recopy(let reason):
                                StructuredLog.shared.log(.info, "resume", "resume.recopy", reason, job: ctx.jobID,
                                                         dest: ctx.destLogID, fields: ["path": ctx.destPath(for: entry)])
                                ctx.onActivity("Se recopiază \(entry.relPath): \(reason).")
                                toCopy.append(ctx)
                            }
                        }
                        if token.isCancelled { cancelledFlag = true; return }
                    }

                    // Copiere REALA prin fan-out — o singura citire a sursei
                    // pentru TOATE destinatiile care au nevoie de copiere la
                    // acest fisier (vezi FanOutCopier.swift).
                    // Destinație dispărută (disc scos): fișierul eșuează DOAR
                    // acolo, cu motiv explicit; celelalte continuă.
                    let vanished = toCopy.filter { !$0.isAvailable }
                    if !vanished.isEmpty {
                        toCopy.removeAll { !$0.isAvailable }
                        for ctx in vanished {
                            StructuredLog.shared.log(.error, "destination", "destination.unavailable",
                                                     "Destinația nu mai e disponibilă", job: ctx.jobID, dest: ctx.destLogID,
                                                     fields: ["path": ctx.destRoot])
                            ctx.recordCopyOutcome(entry: entry, sourceHash: "", outcome: .failure(TransferIssueError(
                                message: "Destinația nu mai e disponibilă (disc deconectat?): \(ctx.destRoot)")), isRetry: isRetry)
                            let root = ctx.destRoot
                            Task { @MainActor [weak self] in
                                self?.markDestination(root, available: false)
                                self?.advance(size: entry.size, file: entry.relPath, dest: root, confirmed: false)
                            }
                        }
                    }
                    // Gardă: un symlink existent la destinație nu are voie să
                    // ducă scrierea în afara folderului țintă.
                    let escaping = toCopy.filter { !$0.isInsideTarget($0.destPath(for: entry)) }
                    if !escaping.isEmpty {
                        toCopy.removeAll { !$0.isInsideTarget($0.destPath(for: entry)) }
                        for ctx in escaping {
                            ctx.recordCopyOutcome(entry: entry, sourceHash: "", outcome: .failure(TransferIssueError(
                                message: "Calea ar ieși din folderul destinației (link simbolic): \(ctx.destPath(for: entry))")), isRetry: isRetry)
                            StructuredLog.shared.log(.error, "copy", "destination.pathEscape", "Scriere refuzată în afara țintei",
                                                     job: ctx.jobID, dest: ctx.destLogID, fields: ["path": ctx.destPath(for: entry)])
                            let root = ctx.destRoot
                            Task { @MainActor [weak self] in self?.advance(size: entry.size, file: entry.relPath, dest: root, confirmed: false) }
                        }
                    }
                    if !toCopy.isEmpty {
                        for ctx in toCopy {
                            let dir = (ctx.destPath(for: entry) as NSString).deletingLastPathComponent
                            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                        }
                        let destPaths = toCopy.map { $0.destPath(for: entry) }
                        for ctx in toCopy { ctx.onActivity("Copiere: \(entry.relPath) (\(formatBytes(entry.size)))") }
                        do {
                            let copier = FanOutCopier(sourcePath: entry.fullPath, destinationPaths: destPaths,
                                                       chunkSize: chunkSize, model: verificationModel,
                                                       cancel: token, pause: pauseTok,
                                                       expectedSize: entry.size, readBack: readBack)
                            let result = try copier.run { _ in }
                            for (ctx, destPath) in zip(toCopy, destPaths) {
                                let outcome = result.destinations[destPath] ?? .failure(
                                    TransferIssueError(message: "Fără rezultat de la motorul de copiere"))
                                ctx.recordCopyOutcome(entry: entry, sourceHash: result.sourceHash, outcome: outcome, isRetry: isRetry)
                                if let d = result.durability[destPath] { ctx.noteDurability(d) }
                                switch outcome {
                                case .success:
                                    StructuredLog.shared.log(.debug, "copy", "file.confirmed", "Fișier confirmat", job: ctx.jobID,
                                                             dest: ctx.destLogID, fields: ["path": destPath, "bytes": "\(entry.size)"])
                                case .mismatch(_, _, let reason):
                                    StructuredLog.shared.log(.warning, "copy", "file.mismatch", reason, job: ctx.jobID,
                                                             dest: ctx.destLogID, fields: ["path": destPath, "retry": "\(isRetry)"])
                                case .failure(let err):
                                    StructuredLog.shared.log(.error, "copy", "file.failed", "Scriere sau finalizare eșuată",
                                                             job: ctx.jobID, dest: ctx.destLogID,
                                                             fields: ["path": destPath, "retry": "\(isRetry)"], error: err)
                                }
                                let ok: Bool = { if case .success = outcome { return true } else { return false } }()
                                if !ok { ctx.onActivity("Neconfirmat: \(entry.relPath) — \(Self.describe(outcome))") }
                                let root = ctx.destRoot
                                Task { @MainActor [weak self] in self?.advance(size: entry.size, file: entry.relPath, dest: root, confirmed: ok) }
                            }
                        } catch is OffloadCancelled {
                            cancelledFlag = true; return
                        } catch {
                            for ctx in toCopy {
                                ctx.recordSourceReadFailure(entry: entry, error: error, isRetry: isRetry)
                                let root = ctx.destRoot
                                Task { @MainActor [weak self] in self?.advance(size: entry.size, file: entry.relPath, dest: root, confirmed: false) }
                            }
                        }
                    }
                }
            }

            runPass(entries: files, isRetry: false)

            // [2026-09-03, pastrat identic] Pas automat de reincercare,
            // INAINTE de rapoarte — rapoartele trebuie sa reflecte starea
            // finala, nu una intermediara.
            if !cancelledFlag && retryFailedFiles {
                let retryPaths = Set(contexts.flatMap { $0.failedRelPaths })
                if !retryPaths.isEmpty {
                    Task { @MainActor [weak self] in
                        self?.logActivity("Reîncercare automată: \(retryPaths.count) fișier(e) care au eșuat la prima trecere…")
                    }
                    let retryEntries = files.filter { retryPaths.contains($0.relPath) }
                    runPass(entries: retryEntries, isRetry: true)
                }
            }

            if cancelledFlag { for ctx in contexts { ctx.markCancelled() } }
            Task { @MainActor [weak self] in self?.phase = .reporting }
            let results = contexts.map { $0.finalize() }

            Task { @MainActor [weak self] in
                self?.finish(results: results, folderName: folderName, sources: sources,
                             destinations: destinations, ejectSource: ejectSourceWhenDone)
            }
        }
    }

    func cancel() {
        guard isRunning else { return }
        diag.log(.info, "job", "job.cancel.requested", "Anulare cerută de utilizator", job: jobID)
        cancelToken.cancel()
        statusText = L.t("status.cancelling")
    }

    /// Adauga o linie in feed-ul de activitate — cu viteza curenta atasata,
    /// ca in exemplul cerut ("Copiere: fisier.MOV | 450 MB/s"), ca userul
    /// sa vada dintr-o privire ca aplicatia lucreaza, nu ca s-a blocat.
    /// [2026-09-03] Acelasi feed, dar scris din AFARA engine-ului (UI) —
    /// folosit de avertismentele detectorului de carduri, care apar inainte
    /// sa porneasca vreun transfer. Feed-ul e locul unde userul se uita
    /// deja; un al doilea loc de mesaje ar fi ratat.
    func logExternal(_ line: String) { logActivity(line) }

    private func logActivity(_ line: String) {
        let withSpeed = speedText.isEmpty ? line : "\(line) — \(speedText)"
        activityLines.append(withSpeed)
        if activityLines.count > activityLogLimit {
            activityLines.removeFirst(activityLines.count - activityLogLimit)
        }
    }

    nonisolated static func describe(_ outcome: FanOutDestOutcome) -> String {
        switch outcome {
        case .success: return "OK"
        case .mismatch(_, _, let reason): return reason
        case .failure(let error): return error.localizedDescription
        }
    }

    private func markDestination(_ root: String, available: Bool) {
        guard let i = destinationStates.firstIndex(where: { $0.destRoot == root }) else { return }
        destinationStates[i].available = available
    }

    private func advance(size: Int64, file: String = "", dest: String? = nil, confirmed: Bool = true) {
        if let dest, let i = destinationStates.firstIndex(where: { $0.destRoot == dest }) {
            if confirmed {
                destinationStates[i].bytesWritten += size
                destinationStates[i].filesConfirmed += 1
            } else {
                destinationStates[i].filesFailed += 1
            }
        }
        filesDone += 1
        bytesDone += size
        if !file.isEmpty { currentFile = file }
        progressPercent = totalUnits > 0 ? Int(Double(filesDone) * 100 / Double(totalUnits)) : 0
        statusText = "\(progressPercent)% (\(filesDone)/\(totalUnits) \(L.t("footer.filesWord")))"
        if let start = startTime {
            let elapsed = Date().timeIntervalSince(start)
            elapsedSeconds = elapsed
            if elapsed > 0 {
                speedText = formatBytes(Int64(Double(bytesDone) / elapsed)) + "/s"
            }
        }
        updateMemoryDisplay()
    }

    private func finish(results: [DestinationResult], folderName: String, sources: [String],
                        destinations: [String], ejectSource: Bool = false) {
        isRunning = false
        if let start = startTime { elapsedSeconds = Date().timeIntervalSince(start) }
        lastResults = results
        let outcome = TransferOutcome.evaluate(results.map { $0.outcome })
        lastOutcome = outcome
        for r in results {
            diag.log(r.outcome.isSafe ? .info : .warning, "job", "destination.result", r.outcome.rawValue, job: jobID,
                     dest: destinationLogID(r.destRoot),
                     fields: ["ok": "\(r.okCount)", "skipped": "\(r.skipCount)", "failed": "\(r.failCount)",
                              "recovered": "\(r.recoveredCount)", "mhl": r.mhlPath == nil ? "no" : "yes",
                              "pdf": r.pdfPath == nil ? "no" : "yes"])
        }
        diag.log(outcome.allowsSourceEject ? .info : .warning, "job", "job.finished", outcome.rawValue, job: jobID,
                 fields: ["seconds": String(format: "%.1f", elapsedSeconds), "bytes": "\(bytesDone)"])
        phase = .finished
        for r in results {
            if let i = destinationStates.firstIndex(where: { $0.destRoot == r.destRoot }) {
                destinationStates[i].outcome = r.outcome
            }
        }
        let anyCancelled = outcome == .cancelled
        let totalOK = results.reduce(0) { $0 + $1.okCount }
        let totalSkip = results.reduce(0) { $0 + $1.skipCount }
        let totalFail = results.reduce(0) { $0 + $1.failCount }
        let totalRecovered = results.reduce(0) { $0 + $1.recoveredCount }
        var summary = "\(L.t("footer.finished")) — \(totalOK) OK"
        if totalFail > 0 { summary += ", \(totalFail) \(L.t("footer.problems"))" }
        // Recuperarile la reincercare se afiseaza explicit: userul trebuie
        // sa stie ca transferul a avut probleme tranzitorii, chiar daca
        // s-a terminat cu bine (indiciu de cablu/card/disc care da rateuri).
        if totalRecovered > 0 { summary += ", \(totalRecovered) \(L.t("footer.recovered"))" }
        statusText = anyCancelled ? L.t("footer.cancelled") : L.t(outcome.labelKey) + " — " + summary + "."
        if Self.sideEffectsEnabled { NSSound(named: "Glass")?.play() }

        // [2026-09-03] Notificare de sistem: la un transfer de ore, userul
        // nu sta cu ochii pe fereastra — un sunet singur se rateaza usor
        // daca e in alta camera sau are casti pe alt canal. Notificarea
        // ramane in Centrul de notificari pana e citita.
        if Self.sideEffectsEnabled { SystemNotifier.notify(
            title: anyCancelled ? L.t("notify.cancelledTitle") : L.t("notify.doneTitle"),
            body: "\(folderName) — \(summary)") }

        // [2026-09-03] Ejectare automata a cardului sursa, DOAR daca totul
        // a mers bine. Un card cu erori nu se scoate niciodata automat:
        // s-ar putea sa mai fie nevoie de o reluare de pe el, iar
        // scoaterea lui ar transforma o problema reparabila in pierdere
        // de material.
        if ejectSource && outcome.allowsSourceEject && totalFail == 0 {
            ejectSourceVolumes(sources)
        } else if ejectSource {
            logActivity("Cardul NU a fost ejectat: \(L.t(outcome.labelKey)).")
        }

        guard Self.sideEffectsEnabled else { return }
        HistoryStore.shared.record(folderName: folderName, sources: sources, destinations: destinations,
                                    okCount: totalOK, skipCount: totalSkip, failCount: totalFail,
                                    outcome: outcome, verification: lastVerificationDepth.rawValue,
                                    reportPaths: results.flatMap { [$0.csvPath, $0.pdfPath, $0.htmlPath, $0.mhlPath].compactMap { $0 } })
    }

    /// Demonteaza volumele amovibile de pe care s-a citit. Un folder de pe
    /// discul intern NU se ejecteaza (nici nu s-ar putea) — filtram dupa
    /// `volumeIsRemovable`/`volumeIsEjectable`.
    private func ejectSourceVolumes(_ sources: [String]) {
        var done: Set<String> = []
        for source in sources {
            let url = URL(fileURLWithPath: source)
            guard let values = try? url.resourceValues(forKeys: [.volumeURLKey, .volumeIsRemovableKey, .volumeIsEjectableKey]),
                  let volumeURL = values.volume,
                  (values.volumeIsRemovable == true || values.volumeIsEjectable == true),
                  !done.contains(volumeURL.path) else { continue }
            done.insert(volumeURL.path)
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: volumeURL)
                logActivity("Card ejectat automat: \(volumeURL.lastPathComponent)")
            } catch {
                logActivity("Cardul \(volumeURL.lastPathComponent) nu a putut fi ejectat: \(error.localizedDescription)")
            }
        }
    }
}
