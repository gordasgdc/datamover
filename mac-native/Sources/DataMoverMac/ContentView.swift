import SwiftUI
import Combine
import UniformTypeIdentifiers

/// [2026-09-03] Un card in coada de descarcare. Fiecare are propriul nume
/// de card, deci propriul folder la destinatie — spre deosebire de mai
/// multe surse adaugate simultan, care ajung toate in ACELASI folder.
struct QueueItem: Identifiable, Equatable {
    let id = UUID()
    var source: String
    var card: String
}

struct ContentView: View {
    @EnvironmentObject var license: LicenseManager
    @StateObject private var runner = OffloadRunner()
    @ObservedObject private var historyStore = HistoryStore.shared
    @Environment(\.openWindow) private var openWindow

    @State private var sourcePaths: [String] = []
    @State private var destinationPaths: [String] = []
    @State private var volumes: [VolumeInfo] = []
    // Auto-detectare card nou — reintrodusa 2026-08-24 (exista intr-o
    // forma veche, pierduta la rescrierea nativa). `knownVolumePaths`
    // nil = inca n-am facut niciun poll: PRIMUL `detectAll()` de la
    // pornire stabileste doar baseline-ul, fara popup — altfel orice
    // card deja conectat cand deschizi aplicatia ar declansa fals un
    // "card nou detectat".
    @State private var knownVolumePaths: Set<String>? = nil
    @State private var newlyDetectedVolume: VolumeInfo?
    @State private var isDropTargetedSources = false
    @State private var isDropTargetedDestFromFinder = false
    @State private var showActivation = false

    // setari de copiere/verificare
    // [2026-09-03] Implicit xxHash64 (nu MD5): acelasi implicit ca la
    // ofloaderele profesionale, cateva ori mai rapid la verificare pe
    // acelasi grad de siguranta practica. Profilele salvate anterior isi
    // pastreaza algoritmul lor, nu sunt rescrise.
    // [2026-09-03] MHL + reincercare automata — preferinte stabile,
    // persistate (ca autoOpenDestFolder), nu resetate la fiecare pornire.
    @AppStorage("dm_generateMHL") private var generateMHL = true
    @AppStorage("dm_retryFailed") private var retryFailedFiles = true
    // Ultimii parametri de start, retinuti ca butonul "Continuă oricum"
    // din alertul de spatiu insuficient sa reporneasca EXACT acelasi
    // transfer, nu unul recalculat cu alte optiuni.
    @State private var lastStartResume = true
    @State private var lastStartFolderOverride: String? = nil

    // [2026-09-03] Metadate de productie (vezi ProductionMeta.swift) —
    // persistate, pentru ca pe un proiect se schimba doar cardul de la o
    // descarcare la alta; clientul, operatorul si logo-ul raman aceleasi
    // saptamani intregi. Notele sunt singurele per-transfer (nepersistate).
    @AppStorage("dm_client") private var clientName = ""
    @AppStorage("dm_operatorName") private var operatorName = ""
    @AppStorage("dm_cameraName") private var cameraName = ""
    @AppStorage("dm_logoPath") private var logoPath = ""
    // [2026-09-03] Sablon de denumire a folderelor — vezi NamingTemplate.
    @AppStorage("dm_folderTemplate") private var folderTemplate = NamingTemplate.defaultTemplate
    // [2026-09-03] Ejectare automata a cardului dupa un transfer curat.
    @AppStorage("dm_ejectWhenDone") private var ejectSourceWhenDone = false
    // [2026-09-03] Pornire automata la introducerea unui card — modul
    // "nesupravegheat" al unui ofloader de platou.
    @AppStorage("dm_autoStartOnCard") private var autoStartOnCardInsert = false

    // [2026-09-03] Coada de carduri — vezi cardQueueSection.
    @State private var cardQueue: [QueueItem] = []
    @State private var queueRunning = false
    @State private var currentQueueCard: String = ""
    // Structura detectata pentru fiecare sursa (RED/ARRI/Sony…), calculata
    // in fundal la adaugare — vezi CameraCardDetector.
    @State private var cardInfoBySource: [String: CameraCardInfo] = [:]
    // Destinatie secundara Cloud (2026-08-30) - vezi CloudSyncService.
    // "" inseamna "dezactivat", niciun upload nu porneste.
    // Deschidere automata a folderului destinatie la final — persistata
    // (spre deosebire de restul setarilor de mai sus, care se reseteaza
    // la fiecare pornire): e o preferinta stabila a userului, nu ceva ce
    // vrei sa reintrodui manual la fiecare transfer.
    @AppStorage("dm_autoOpenDestFolder") private var autoOpenDestFolder = false
    // Setari I/O & Memorie (2026-08-27) - aceleasi chei UserDefaults ca
    // IOSettings.chunkSizeMB/ramLimitMB, ca engine-ul sa citeasca direct
    // ce alege userul aici, fara alt strat de sincronizare.
    @AppStorage("datamover_chunk_size_mb") private var chunkSizeMB = IOSettings.defaultChunkSizeMB
    // Profil utilizator (2026-08-28) - Nume/Email optionale, doar locale
    // (@AppStorage, la fel ca restul setarilor din acest fisier).
    @AppStorage("datamover_ram_limit_mb") private var ramLimitMB = 1024
    @State private var showCompletionAlert = false
    @ObservedObject private var job = JobSettings.shared
    @State private var logExpanded = false
    @State private var showResult = false
    @State private var sourceBytes: Int64? = nil
    @State private var capacities: [String: VolumeCapacity] = [:]
    @State private var preflightIssues: [PreflightIssue] = []
    // Duplicate/Reluare (2026-08-28) - vezi attemptStart()/startTransfer().
    @State private var showDuplicateDialog = false
    @State private var duplicateFolderName: String = ""
    // Profile de transfer (2026-08-28) - vezi transferProfilesSection.
    @ObservedObject private var profileStore = TransferProfileStore.shared
    @State private var showSaveProfilePrompt = false
    @State private var newProfileName: String = ""
    @State private var showHistory = false
    @State private var projectName: String = ""
    @State private var cardName: String = ""
    /// Clasificarea mediului per cale (MediaProbe) — tipul de obiect afișat.
    @State private var mediaByPath: [String: MediaClass] = [:]
    /// Octeții de copiat, per sursă (măsurați la scanare, nu estimați).
    @State private var bytesBySource: [String: Int64] = [:]
    @State private var showQueue = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var langStore = LanguageStore.shared

    // drag manual disc -> SOURCES sau DESTINATIONS
    //
    // PITFALL FIXED 2026-08-24 (bug critic raportat de Cristi): gest-ul de
    // drag intern al gridului de discuri (DiskTileView, mai jos) urmarea
    // DOAR `destFrame` — nu exista niciun `sourcesFrame`, deci tragerea
    // unui disc peste caseta de Surse nu facea NIMIC, desi acelasi disc
    // tras peste Destinatii mergea perfect. Nu are legatura cu bug-ul de
    // `.onDrop`/NSItemProvider (radacina de volum din Finder) fixat
    // anterior — asta e un mecanism de drag COMPLET SEPARAT, intern
    // aplicatiei (DragGesture + hit-test pe coordonate), folosit doar
    // pentru discurile din grila centrala. `sourcesFrame` adaugat acum,
    // urmarit la fel ca `destFrame` (GeometryReader + coordinateSpace
    // "root"), iar `onEnded` verifica ambele cutii.
    @State private var draggingDiskPath: String? = nil
    @State private var dragPoint: CGPoint = .zero
    @State private var sourcesFrame: CGRect = .zero
    @State private var destFrame: CGRect = .zero

    private let refreshTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    private var isHoveringSource: Bool {
        draggingDiskPath != nil && sourcesFrame.contains(dragPoint)
    }
    private var isHoveringDest: Bool {
        draggingDiskPath != nil && destFrame.contains(dragPoint)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                if license.isTrialActive && !license.isLicensed {
                    trialBar
                }
                headerBar
                Divider()

                GeometryReader { geo in
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            stageTitle
                            mainStage
                            if !runner.isRunning && !showResult {
                                Divider()
                                deviceShelf
                            }
                        }
                        Divider()
                        incidentColumn
                            .frame(width: geo.size.width < DM.Layout.incidentsCompactBelow
                                   ? DM.Layout.incidentsWidthCompact : DM.Layout.incidentsWidth)
                    }
                }
                .frame(maxHeight: .infinity)
                .onPreferenceChange(RouteZoneKey.self) { frames in
                    sourcesFrame = frames.sources
                    destFrame = frames.destinations
                }

                Divider()
                footer
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear {
                volumes = VolumeInfo.detectAll()
                knownVolumePaths = Set(volumes.map(\.path))
                #if DEBUG
                applyUIDemoIfRequested()
                #endif
            }
            .onReceive(refreshTimer) { _ in
                refreshVolumesAndDetectNew()
                if !runner.isRunning { refreshPreparation(scanSources: false) }
            }
            .onChange(of: sourcePaths) { _, _ in refreshPreparation() }
            .task(id: (volumes.map(\.path) + sourcePaths + destinationPaths).joined(separator: "|")) {
                await classifyNewPaths()
            }
            .onChange(of: destinationPaths) { _, _ in refreshPreparation() }
            .onChange(of: job.exclusionsText) { _, _ in refreshPreparation() }
            .sheet(isPresented: $showActivation) {
                ActivationSheet(isPresented: $showActivation)
                    .environmentObject(license)
            }
            .alert(
                L.t("volume.newCard.title"),
                isPresented: Binding(
                    get: { newlyDetectedVolume != nil },
                    set: { if !$0 { newlyDetectedVolume = nil } }
                ),
                presenting: newlyDetectedVolume
            ) { volume in
                Button(L.t("volume.newCard.add")) {
                    addSource(volume.path)
                    newlyDetectedVolume = nil
                }
                Button(L.t("volume.newCard.ignore"), role: .cancel) { newlyDetectedVolume = nil }
            } message: { volume in
                Text(String(format: L.t("volume.newCard.message"), volume.name))
            }
            // Transfer terminat (isRunning: true -> false): deschide
            // automat folderul destinatie daca userul a bifat setarea, si
            // arata mereu alerta de succes cu butonul "Deschide folderul
            // destinatie" — cele doua sunt independente (2026-08-24,
            // cerinta explicita: buton mereu disponibil + o bifa separata
            // de auto-deschidere).
            .onChange(of: runner.isRunning) { wasRunning, isRunning in
                guard wasRunning, !isRunning else { return }
                let wasCancelled = runner.lastResults.first?.cancelled ?? true
                // [2026-09-03] Coada continua singura cu urmatorul card.
                // O anulare opreste TOATA coada — daca userul a apasat
                // Anulează, nu vrea sa porneasca imediat cardul urmator.
                if queueRunning {
                    if wasCancelled {
                        queueRunning = false
                        currentQueueCard = ""
                        runner.logExternal("Coadă oprită (transfer anulat) — au rămas \(cardQueue.count) card(uri).")
                    } else if !cardQueue.isEmpty {
                        startNextInQueue()
                        return
                    } else {
                        queueRunning = false
                        currentQueueCard = ""
                        runner.logExternal("Coadă terminată — toate cardurile au fost descărcate.")
                    }
                }
                // Rezultatul rămâne pe ecran (inclusiv la anulare), cu
                // verdictul fiecărei destinații — nu un alert care dispare.
                showResult = runner.lastOutcome != nil
                if wasCancelled { logExpanded = true; return }
                if autoOpenDestFolder { openLastDestinationFolder() }
            }
            .alert(L.t("completion.title"), isPresented: $showCompletionAlert) {
                Button(L.t("completion.openFolder")) { openLastDestinationFolder() }
                Button(L.t("completion.ok"), role: .cancel) {}
            } message: {
                Text(footerStatusText)
            }
            // Plafon de proba depasit (2026-08-30) - vezi LicenseManager.
            // trialMaxTransferBytes / OffloadRunner.trialLimitExceededBytes.
            .alert(
                L.t("trial.sizeLimitTitle"),
                isPresented: Binding(
                    get: { runner.trialLimitExceededBytes != nil },
                    set: { if !$0 { runner.trialLimitExceededBytes = nil } }
                )
            ) {
                Button(L.t("trial.activate")) { showActivation = true }
                Button(L.t("completion.ok"), role: .cancel) {}
            } message: {
                Text(String(format: L.t("trial.sizeLimitMessage"),
                            ByteCountFormatter.string(fromByteCount: runner.trialLimitExceededBytes ?? 0, countStyle: .file)))
            }
            // Full Disk Access lipsa (2026-09-03) - vezi OffloadEngine.
            // isPermissionError / OffloadRunner.permissionErrorPath. Deschide
            // direct panoul relevant din System Settings - userul bifeaza o
            // singura data, manual (nu se poate acorda din cod).
            .alert(
                L.t("permission.title"),
                isPresented: Binding(
                    get: { runner.permissionErrorPath != nil },
                    set: { if !$0 { runner.permissionErrorPath = nil } }
                )
            ) {
                Button(L.t("permission.openSettings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button(L.t("completion.ok"), role: .cancel) {}
            } message: {
                Text(String(format: L.t("permission.message"), runner.permissionErrorPath ?? ""))
            }

            // [2026-09-03] Spatiu insuficient la destinatie, verificat
            // INAINTE de a copia primul octet (vezi
            // OffloadRunner.spaceShortfall). Nu blocam definitiv: aratam
            // cifrele reale si lasam userul sa forteze, daca stie ceva ce
            // aplicatia nu stie (ex. va elibera spatiu intre timp).
            .alert(item: Binding(
                get: { runner.spaceShortfall },
                set: { runner.spaceShortfall = $0 }
            )) { shortfall in
                Alert(
                    title: Text(L.t("space.title")),
                    message: Text(String(
                        format: L.t("space.message"),
                        (shortfall.destination as NSString).lastPathComponent,
                        ByteCountFormatter.string(fromByteCount: shortfall.needed, countStyle: .file),
                        ByteCountFormatter.string(fromByteCount: shortfall.free, countStyle: .file))),
                    primaryButton: .destructive(Text(L.t("space.continueAnyway"))) {
                        startTransfer(resume: lastStartResume,
                                      folderNameOverride: lastStartFolderOverride,
                                      ignoreSpaceWarning: true)
                    },
                    secondaryButton: .cancel(Text(L.t("space.cancel")))
                )
            }

            // eticheta "fantoma" care urmareste cursorul cat timp tragi un disc
            if let path = draggingDiskPath {
                Text((path as NSString).lastPathComponent)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.green)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .position(dragPoint)
                    .allowsHitTesting(false)
            }
        }
        .coordinateSpace(name: "root")
    }

    #if DEBUG
    @Environment(\.openWindow) private var openWindowDebug
    @Environment(\.openSettings) private var openSettingsDebug

    /// Doar în build-urile DEBUG: `DATAMOVER_UI_DEMO=<folder>` precompletează
    /// sursa `<folder>/CARD` și destinațiile `<folder>/BACKUP_A|B` (foldere
    /// temporare create de test), iar `DATAMOVER_UI_DEMO_START=1` pornește
    /// transferul. Folosit pentru capturile de verificare vizuală — nu atinge
    /// volume reale și nu există în build-ul Release.
    private func applyUIDemoIfRequested() {
        let env = ProcessInfo.processInfo.environment
        if env["DATAMOVER_DESIGN_GALLERY"] == "1" && env["DATAMOVER_UI_DEMO"] == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { openWindowDebug(id: "design-gallery") }
        }
        guard let root = env["DATAMOVER_UI_DEMO"] else { return }
        projectName = "Demo"
        cardName = "A001"
        addSource((root as NSString).appendingPathComponent("CARD"))
        for d in ["BACKUP_A", "BACKUP_B"] { addDestination((root as NSString).appendingPathComponent(d)) }
        if env["DATAMOVER_DESIGN_GALLERY"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { openWindowDebug(id: "design-gallery") }
        }
        if env["DATAMOVER_UI_DEMO_SETTINGS"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { openSettingsDebug() }
        }
        if env["DATAMOVER_UI_DEMO_START"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { attemptStart() }
        }
    }
    #endif

    // MARK: - Header (proba gratuita)

    private var trialBar: some View {
        HStack {
            Text(String(format: L.t("trial.daysLeft"), license.trialDaysRemaining))
                .foregroundStyle(.secondary)
            Spacer()
            Button(L.t("trial.activate")) { showActivation = true }
                .buttonStyle(.plain)
                .foregroundStyle(.green)
                .fontWeight(.semibold)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    // MARK: - Header: job, coadă, acțiunea principală

    /// Proiectul și cardul dau numele folderului; Start stă aici, lângă ce
    /// pornește. Start e dezactivat DOAR de un blocaj real (preflight).
    private var headerBar: some View {
        HStack(spacing: DM.Space.l) {
            HStack(spacing: DM.Space.s) {
                TextField(L.t("meta.project"), text: $projectName)
                    .textFieldStyle(.roundedBorder).frame(width: DM.Layout.routeNodeWidth)
                    .accessibilityLabel(L.t("meta.project"))
                Image(systemName: "chevron.right").foregroundStyle(DM.textTertiary).accessibilityHidden(true)
                TextField(L.t("meta.card"), text: $cardName)
                    .textFieldStyle(.roundedBorder).frame(width: DM.Layout.routeNodeBlock + DM.Space.xl)
                    .accessibilityLabel(L.t("meta.card"))
            }
            .disabled(runner.isRunning)
            Text(previewFolderName).font(DM.Font.mono).foregroundStyle(DM.textSecondary)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                .help(L.t("prep.folder"))
            Spacer(minLength: DM.Space.s)
            Button { showQueue.toggle() } label: {
                Label(cardQueue.isEmpty ? L.t("queue.titleShort") : String(format: L.t("queue.titleCount"), cardQueue.count),
                      systemImage: "square.stack.3d.down.right")
            }
            .popover(isPresented: $showQueue, arrowEdge: .bottom) {
                cardQueueSection.padding(DM.Space.m).frame(width: DM.Layout.routeDestinationColumn)
            }
            if runner.isRunning {
                Button(runner.isPaused ? L.t("footer.resume") : L.t("footer.pause")) { runner.togglePause() }
                Button(L.t("footer.cancel"), role: .destructive) { runner.cancel() }
                    .keyboardShortcut(".", modifiers: .command)
            } else if showResult {
                Button(L.t("result.newTransfer")) { showResult = false }
            }
            Button {
                attemptStart()
            } label: {
                Label(runner.isRunning ? L.t("footer.copying") : L.t("action.startOffload"), systemImage: "play.fill")
                    .padding(.horizontal, DM.Space.xs)
            }
            .buttonStyle(.borderedProminent)
            .tint(DM.accent)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(runner.isRunning || sourcePaths.isEmpty || destinationPaths.isEmpty
                      || IncidentBuilder.blocksStart(prepareIncidents))
            .help(IncidentBuilder.blocksStart(prepareIncidents) ? L.t("action.startBlocked") : L.t("action.startHelp"))
            .confirmationDialog(L.t("duplicate.title"), isPresented: $showDuplicateDialog, titleVisibility: .visible) {
                Button(L.t("duplicate.resume")) {
                    startTransfer(resume: true, folderNameOverride: duplicateFolderName)
                }
                Button(L.t("duplicate.newFolder")) {
                    // Baza e numele "de azi" (nu cel vechi gasit), ca un folder
                    // chiar nou sa nu mosteneasca data transferului anterior.
                    let todayName = runner.folderName(project: projectName, card: cardName,
                                                      template: folderTemplate, camera: cameraName,
                                                      operatorName: operatorName)
                    let freeName = runner.freeFolderName(base: todayName, destinations: destinationPaths)
                    startTransfer(resume: job.resumeEnabled, folderNameOverride: freeName)
                }
                Button(L.t("duplicate.overwrite"), role: .destructive) {
                    runner.clearExistingFolders(destinations: destinationPaths, folderName: duplicateFolderName)
                    startTransfer(resume: false, folderNameOverride: duplicateFolderName)
                }
                Button(L.t("duplicate.cancel"), role: .cancel) {}
            } message: {
                Text(L.t("duplicate.message"))
            }
        }
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, DM.Space.l)
        .padding(.vertical, DM.Space.m)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// [2026-09-03] Coada de carduri — descarcarea mai multor carduri, unul
    /// dupa altul, nesupravegheat.
    ///
    /// DE CE: pe un platou cu 3 camere se aduna 6-8 carduri la finalul
    /// zilei. Pana acum, operatorul trebuia sa stea langa laptop si sa
    /// porneasca manual fiecare card dupa ce se termina cel dinainte —
    /// ore de asteptare activa. Fiecare card din coada isi pastreaza numele
    /// propriu, deci ajunge in propriul folder la destinatie.
    private var cardQueueSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L.t("queue.title"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L.t("queue.add")) { addCurrentToQueue() }
                    .font(.system(size: 10))
                    .disabled(sourcePaths.isEmpty || runner.isRunning)
            }

            if cardQueue.isEmpty {
                Text(L.t("queue.empty"))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(cardQueue) { item in
                    HStack(spacing: 6) {
                        Image(systemName: "sdcard")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(item.card).font(.system(size: 10)).lineLimit(1)
                        Spacer()
                        Button {
                            cardQueue.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button(queueRunning ? L.t("queue.running") : L.t("queue.start")) {
                    startNextInQueue()
                }
                .font(.system(size: 10))
                .disabled(runner.isRunning || destinationPaths.isEmpty)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    /// PITFALL FIXED 2026-08-24: tragerea unui FOLDER din interiorul unui
    /// card extern mergea, dar tragerea iconitei RADACINII volumului
    /// (cardul insusi, din Finder/Desktop) nu era preluata deloc.
    /// `NSItemProvider.loadObject(ofClass: URL.self)` foloseste bridging-ul
    /// standard NSURL<->"public.file-url", care merge sigur pentru un
    /// fisier/folder obisnuit — dar pentru radacina unui volum montat,
    /// Finder nu garanteaza mereu acel bridging (item-ul poate veni doar
    /// ca reprezentare bruta de date pentru identificatorul de tip, fara
    /// sa treaca prin `NSItemProviderReading`). Fix: incercam intai calea
    /// standard, iar daca provider-ul nu poate incarca direct un `URL`
    /// (cazul volumelor), citim manual `public.file-url` ca `Data` si
    /// decodam URL-ul de acolo — acopera ambele cazuri, foldere si
    /// radacini de volum deopotriva. `.onDrop` de mai jos accepta acum si
    /// `.volume`, nu doar `.fileURL`, ca hit-testul de drop sa recunoasca
    /// volumul ca tinta valida inca din faza de hover.
    private func handleSourceDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { self.addSource(url.path) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async { self.addSource(url.path) }
                }
            }
        }
        return handled
    }

    /// Compara volumele curente cu ultimul poll — un volum aparut nou
    /// (nu era in `knownVolumePaths`) declanseaza popup-ul "Card nou
    /// detectat". Nu alertam pentru un card deja conectat la pornirea
    /// aplicatiei (baseline-ul din primul .onAppear) si nu alertam de
    /// doua ori pentru acelasi card cat timp ramane conectat.
    private func refreshVolumesAndDetectNew() {
        let detected = VolumeInfo.detectAll()
        if let known = knownVolumePaths {
            let newlyAppeared = detected.filter { !known.contains($0.path) }
            // [2026-09-03] Mod nesupravegheat: daca userul a bifat pornirea
            // automata si sunt indeplinite conditiile (exista destinatii,
            // nu ruleaza nimic), cardul intra direct in coada si porneste
            // singur. Numele cardului devine numele volumului — singurul
            // pe care il stim fara sa intrebam. Conditia "exista
            // destinatii" nu e optionala: fara ea, un card introdus dupa
            // pornirea aplicatiei ar declansa un start esuat.
            if autoStartOnCardInsert, !newlyAppeared.isEmpty, !destinationPaths.isEmpty {
                for volume in newlyAppeared {
                    cardQueue.append(QueueItem(source: volume.path, card: volume.name))
                    runner.logExternal("Card detectat automat: \(volume.name) — adăugat în coadă.")
                }
                if !runner.isRunning { startNextInQueue() }
            } else if newlyDetectedVolume == nil, let first = newlyAppeared.first {
                // Daca s-au conectat mai multe simultan (rar), aratam popup
                // doar pentru primul — restul raman disponibile in grila,
                // fara sa inecam userul in popup-uri consecutive.
                newlyDetectedVolume = first
            }
        }
        // Un disc scos: clasificarea lui se uită (alt disc montat pe aceeași
        // cale nu trebuie să-i moștenească tipul).
        let gone = Set(volumes.map(\.path)).subtracting(detected.map(\.path))
        for p in gone { MediaProbe.forget(p); mediaByPath[p] = nil }
        volumes = detected
        knownVolumePaths = Set(detected.map(\.path))
    }

    /// Deschide in Finder folderul CREAT pentru ultimul transfer (nu
    /// radacina destinatiei alese de user — subfolderul cu numele
    /// generat `<data>_<Proiect>_<Card>`). `csvPath` e mereu in acel
    /// subfolder (vezi writeReports), deci parintele lui e calea corecta
    /// — acelasi trick folosit deja de "Deschide ultimul raport" din
    /// Setari, aici doar reutilizat pentru noua cerinta.
    private func openLastDestinationFolder() {
        guard let last = runner.lastResults.first,
              let folder = last.csvPath.map({ ($0 as NSString).deletingLastPathComponent }) else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder)
    }

    private func addSource(_ path: String) {
        if !sourcePaths.contains(path) {
            sourcePaths.append(path)
        }
        detectCard(at: path)
    }

    // MARK: - Metadate productie, sablon, coada (2026-09-03)

    /// Metadatele curente, compuse din campurile din bara de sus si din
    /// Setari — o singura sursa de adevar pentru: numele folderului
    /// (NamingTemplate), antetul rapoartelor (PDF/HTML) si istoricul.
    private var currentMeta: ProductionMeta {
        ProductionMeta(project: projectName, card: cardName, client: clientName,
                       operatorName: operatorName, camera: cameraName,
                       notes: job.shootNotes, logoPath: logoPath)
    }

    /// Recunoasterea structurii de card se face pe un thread de fundal:
    /// enumerarea unui card plin (zeci de mii de fisiere) ar bloca UI-ul
    /// exact in momentul in care userul tocmai a tras cardul in fereastra.
    private func detectCard(at path: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let info = CameraCardDetector.detect(root: path)
            let parentCard = info == nil ? CameraCardDetector.parentLooksLikeCard(path: path) : nil
            DispatchQueue.main.async {
                if let info {
                    cardInfoBySource[path] = info
                    for warning in info.warnings {
                        runner.logExternal("⚠ \((path as NSString).lastPathComponent): \(warning)")
                    }
                } else if let parentCard {
                    // Cazul cel mai scump de pe platou: s-a selectat un
                    // subfolder al cardului, nu radacina lui.
                    runner.logExternal("⚠ \((path as NSString).lastPathComponent) pare a fi un SUBFOLDER al cardului \((parentCard as NSString).lastPathComponent) — copiat singur, pierzi metadatele cardului.")
                }
            }
        }
    }

    private func addCurrentToQueue() {
        guard let source = sourcePaths.first else { return }
        let card = cardName.trimmingCharacters(in: .whitespaces)
        cardQueue.append(QueueItem(source: source, card: card.isEmpty ? (source as NSString).lastPathComponent : card))
        // Sursa iese din lista curenta: e "predata" cozii, altfel ar fi
        // copiata de doua ori (o data acum, o data cand ii vine randul).
        sourcePaths.removeAll { $0 == source }
        cardName = ""
    }

    /// Porneste (sau continua) coada. Fiecare card primeste propriul folder
    /// la destinatie, calculat cu acelasi sablon ca un transfer normal.
    /// Reluarea e implicit ACTIVA in coada: modul nesupravegheat nu poate
    /// astepta un raspuns la dialogul de duplicate.
    private func startNextInQueue() {
        guard !cardQueue.isEmpty else {
            queueRunning = false
            currentQueueCard = ""
            return
        }
        let next = cardQueue.removeFirst()
        queueRunning = true
        currentQueueCard = next.card
        sourcePaths = [next.source]
        cardName = next.card
        let existing = runner.findExistingFolderName(
            destinations: destinationPaths, project: projectName, card: next.card,
            template: folderTemplate, camera: cameraName, operatorName: operatorName)
        startTransfer(resume: true, folderNameOverride: existing)
    }

    private func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return isDir.boolValue
    }

    // MARK: - Etapa curentă: titlu, traseu, raft, incidente
    //
    // Un singur traseu (sursă → verificare → copii) pentru Prepare, Transfer
    // și Result; se schimbă doar ce spune fiecare capăt. Vezi RouteView.

    private var stage: RouteStage {
        if runner.isRunning { return .transfer }
        return showResult && runner.lastOutcome != nil ? .result : .prepare
    }

    private var stageKey: String {
        switch stage { case .prepare: return "prepare"; case .transfer: return "transfer"; case .result: return "result" }
    }

    private var stageTitle: some View {
        HStack(alignment: .firstTextBaseline, spacing: DM.Space.m) {
            Text(L.t("screen.\(stageKey)")).font(DM.Font.screenTitle).lineLimit(1).minimumScaleFactor(0.8)
            Text(stageSubtitle).font(DM.Font.label).foregroundStyle(DM.textSecondary).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DM.Space.xl).padding(.top, DM.Space.l)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var stageSubtitle: String {
        switch stage {
        case .prepare: return L.t("screen.prepare.sub")
        case .transfer: return runner.isPaused ? L.t("footer.paused") : L.t(runner.phase.labelKey)
        case .result: return runner.lastOutcome.map { L.t("outcomeHelp.\($0.rawValue)") } ?? ""
        }
    }

    private var mainStage: some View {
        RouteView(stage: stage, sources: sourceEndpoints, destinations: destinationEndpoints, node: routeNode,
                  animateFlow: RouteMotion.animatesFlow(isRunning: runner.isRunning, isPaused: runner.isPaused, reduceMotion: reduceMotion),
                  dropHighlight: (isHoveringSource, isHoveringDest),
                  onRemove: stage == .prepare ? { removeEndpoint($0) } : nil,
                  onDropSources: { handleSourceDrop($0) },
                  onDropDestinations: { handleDestinationFinderDrop($0) })
    }

    private func removeEndpoint(_ path: String) {
        if sourcePaths.contains(path) {
            sourcePaths.removeAll { $0 == path }
            cardInfoBySource[path] = nil
        } else {
            destinationPaths.removeAll { $0 == path }
        }
    }

    private func displayName(_ path: String) -> String {
        FileManager.default.displayName(atPath: path)
    }

    private var sourceEndpoints: [RouteEndpoint] {
        sourcePaths.enumerated().map { i, path in
            var e = RouteEndpoint(path: path, name: displayName(path), media: mediaByPath[path], role: .source(i + 1))
            let info = cardInfoBySource[path]
            e.warning = !(info?.warnings.isEmpty ?? true)
            e.detail = info?.summary ?? ""
            switch stage {
            case .prepare:
                if let b = bytesBySource[path] {
                    e.figure = formatBytes(b); e.figureCaption = L.t("fig.toCopy")
                } else {
                    e.figureCaption = L.t("fig.measuring")
                }
                if let cap = capacities[path] { e.secondary = String(format: L.t("fig.ofVolume"), formatBytes(cap.total)) }
            case .transfer:
                let read = runner.bytesDone / Int64(max(runner.destinationCount, 1))
                e.activity = .reading
                e.figure = formatBytes(read); e.figureCaption = L.t("fig.read")
                e.progress = Double(runner.progressPercent) / 100
                e.secondary = runner.currentFile
            case .result:
                e.activity = .done
                e.figure = formatBytes(runner.bytesDone / Int64(max(runner.destinationCount, 1))); e.figureCaption = L.t("fig.read")
                e.secondary = String(format: L.t("fig.duration"), duration(runner.elapsedSeconds))
            }
            return e
        }
    }

    private var destinationEndpoints: [RouteEndpoint] {
        destinationPaths.enumerated().map { i, path in
            var e = RouteEndpoint(path: path, name: displayName(path), media: mediaByPath[path], role: .destination(i + 1))
            switch stage {
            case .prepare:
                guard let cap = capacities[path] else { e.figureCaption = L.t("fig.unknownSpace"); return e }
                let incoming = sourceBytes ?? 0
                let after = cap.free - incoming
                e.capacity = (cap.total, cap.total - cap.free, incoming)
                e.figure = formatBytes(abs(after))
                e.figureCaption = L.t(after >= 0 ? "fig.freeAfter" : "fig.missing")
                e.warning = after < 0
                e.secondary = String(format: L.t("fig.usedOf"), formatBytes(cap.total - cap.free), formatBytes(cap.total))
            case .transfer:
                let st = runner.destinationStates.first { $0.destRoot == path }
                let expected = max(runner.totalBytes / Int64(max(runner.destinationCount, 1)), 1)
                let written = st?.bytesWritten ?? 0
                e.online = st?.available ?? true
                e.warning = (st?.filesFailed ?? 0) > 0
                e.activity = .writing
                e.progress = min(1, Double(written) / Double(expected))
                e.figure = "\(Int((e.progress ?? 0) * 100))%"
                e.figureCaption = L.t("fig.written")
                e.secondary = String(format: L.t("monitor.confirmed"), st?.filesConfirmed ?? 0, formatBytes(written))
            case .result:
                guard let r = runner.lastResults.first(where: { $0.destRoot == path }) else { return e }
                e.outcome = r.outcome
                e.activity = .done
                e.figure = "\(r.okCount + r.skipCount)"
                e.figureCaption = L.t("fig.confirmed")
                var parts: [String] = []
                if r.failCount > 0 { parts.append(String(format: L.t("monitor.failedFiles"), r.failCount)) }
                if r.recoveredCount > 0 { parts.append("\(r.recoveredCount) \(L.t("result.recovered"))") }
                e.secondary = parts.joined(separator: " · ")
                var reports: [(label: String, path: String)] = []
                if let f = r.targetFolder { reports.append((L.t("result.openFolder"), f)) }
                if let x = r.pdfPath { reports.append(("PDF", x)) }
                if let x = r.htmlPath { reports.append(("HTML", x)) }
                if let x = r.csvPath { reports.append(("CSV", x)) }
                if let x = r.mhlPath { reports.append(("MHL", x)) }
                e.reports = reports
            }
            return e
        }
    }

    private var routeNode: RouteNodeModel {
        var n = RouteNodeModel(stage: stage, method: "\(job.verificationModel.label) · \(L.t(job.depth.labelKey))")
        switch stage {
        case .prepare:
            n.phaseText = L.t("node.prepare")
        case .transfer:
            n.method = "\(job.verificationModel.label) · \(L.t(runner.lastVerificationDepth.labelKey))"
            n.phaseText = runner.isPaused ? L.t("footer.pause") : L.t(runner.phase.labelKey)
            n.percent = runner.progressPercent
            n.status = .active
            if runner.writeBytesPerSecond > 0 {
                n.rateText = String(format: L.t("node.rates"), formatBytes(Int64(runner.readBytesPerSecond)),
                                    formatBytes(Int64(runner.writeBytesPerSecond)))
            }
            n.etaText = runner.etaSeconds.map { String(format: L.t("node.eta"), duration($0)) }
        case .result:
            n.method = "\(job.verificationModel.label) · \(L.t(runner.lastVerificationDepth.labelKey))"
            if let o = runner.lastOutcome {
                n.verdict = o
                n.status = DMStatus(o)
                n.phaseText = L.t(o.labelKey)
            }
        }
        return n
    }

    // MARK: Incidente

    private var prepareIncidents: [Incident] {
        var input = IncidentBuilder.PrepareInput()
        input.issues = preflightIssues
        input.cardWarnings = sourcePaths.flatMap { p in (cardInfoBySource[p]?.warnings ?? []).map { (p, $0) } }
        if let bytes = sourceBytes {
            input.spaceShort = destinationPaths.compactMap { d in
                guard let cap = capacities[d], bytes > cap.free else { return nil }
                return (d, bytes - cap.free)
            }
        }
        input.depth = job.depth
        input.unknownDevices = (sourcePaths + destinationPaths).filter { mediaByPath[$0]?.confidence == .fallback }
        if !destinationPaths.isEmpty,
           let existing = runner.findExistingFolderName(destinations: destinationPaths, project: projectName, card: cardName,
                                                        template: folderTemplate, camera: cameraName, operatorName: operatorName) {
            input.resumingFolder = existing
        }
        return IncidentBuilder.prepare(input)
    }

    private var preparePassed: [String] {
        guard !sourcePaths.isEmpty, !destinationPaths.isEmpty else { return [] }
        var list: [String] = []
        let overlap: Set<PreflightIssue.Code> = [.sameAsSource, .destinationInsideSource, .sourceInsideDestination,
                                                 .duplicateDestination, .nestedDestinations]
        if !preflightIssues.contains(where: { overlap.contains($0.code) }) { list.append(L.t("prep.check.noOverlap")) }
        if let bytes = sourceBytes, destinationPaths.allSatisfy({ d in capacities[d].map { bytes <= $0.free } ?? false }) {
            list.append(L.t("prep.check.spaceOk"))
        }
        if job.depth != .sizeOnly { list.append(L.t("prep.check.checksum")) }
        return list
    }

    @ViewBuilder private var incidentColumn: some View {
        switch stage {
        case .prepare:
            let list = prepareIncidents
            let blocking = list.filter { $0.blocksStart }.count
            let warnings = list.filter { $0.severity == .warning }.count
            if sourcePaths.isEmpty || destinationPaths.isEmpty {
                IncidentPanel(headline: L.t("incidents.incomplete"), headlineStatus: .neutral, incidents: list, passed: [])
            } else if blocking > 0 {
                IncidentPanel(headline: String(format: L.t("incidents.blocked"), blocking), headlineStatus: .failure,
                              incidents: list, passed: preparePassed)
            } else if warnings > 0 {
                IncidentPanel(headline: String(format: L.t("incidents.readyWarnings"), warnings), headlineStatus: .warning,
                              incidents: list, passed: preparePassed, footnote: L.t("incidents.warningsDontBlock"))
            } else {
                IncidentPanel(headline: L.t("prep.state.ready"), headlineStatus: .verified, incidents: list, passed: preparePassed)
            }
        case .transfer:
            let list = IncidentBuilder.transfer(runner.destinationStates)
            IncidentPanel(headline: list.isEmpty ? L.t("incidents.none") : String(format: L.t("incidents.count"), list.count),
                          headlineStatus: list.isEmpty ? .active : .failure, incidents: list,
                          footnote: L.t("incidents.transferNote"))
        case .result:
            let list = IncidentBuilder.result(runner.lastResults)
            let o = runner.lastOutcome ?? .failure
            IncidentPanel(headline: L.t(o.labelKey), headlineStatus: DMStatus(o), incidents: list,
                          footnote: L.t("outcomeHelp.\(o.rawValue)"))
        }
    }

    // MARK: Raftul de dispozitive

    private var deviceShelf: some View {
        VStack(alignment: .leading, spacing: DM.Space.s) {
            HStack(spacing: DM.Space.m) {
                DMSectionHeader(title: L.t("shelf.title")).fixedSize()
                Text(L.t("shelf.hint")).font(DM.Font.detail).foregroundStyle(DM.textTertiary).lineLimit(1)
                Spacer(minLength: 0)
            }
            ScrollView(.horizontal) {
                HStack(spacing: DM.Space.l) {
                    ForEach(volumes) { volume in
                        let used = sourcePaths.contains(volume.path) || destinationPaths.contains(volume.path)
                        DeviceShelfItem(name: volume.name, media: mediaByPath[volume.path], freeBytes: volume.freeBytes)
                            .opacity(used ? 0.45 : 1)
                            .gesture(
                                DragGesture(minimumDistance: 4, coordinateSpace: .named("root"))
                                    .onChanged { value in
                                        draggingDiskPath = volume.path
                                        dragPoint = value.location
                                    }
                                    .onEnded { value in
                                        if sourcesFrame.contains(value.location) {
                                            addSource(volume.path)
                                        } else if destFrame.contains(value.location) {
                                            addDestination(volume.path)
                                        }
                                        draggingDiskPath = nil
                                    }
                            )
                            .contextMenu {
                                Button(L.t("shelf.useAsSource")) { addSource(volume.path) }
                                Button(L.t("shelf.useAsDestination")) { addDestination(volume.path) }
                            }
                            .accessibilityAction(named: L.t("shelf.useAsSource")) { addSource(volume.path) }
                            .accessibilityAction(named: L.t("shelf.useAsDestination")) { addDestination(volume.path) }
                    }
                }
                .padding(.vertical, DM.Space.xs)
            }
        }
        .padding(.horizontal, DM.Space.xl)
        .padding(.vertical, DM.Space.m)
        .background(DM.surfaceSunken.opacity(DM.Opacity.shelf))
    }

    /// Clasifică orice cale nouă (volume montate, surse, destinații).
    private func classifyNewPaths() async {
        let paths = Set(volumes.map(\.path) + sourcePaths + destinationPaths)
        for p in paths where mediaByPath[p] == nil {
            let c = await MediaProbe.classify(path: p)
            mediaByPath[p] = c
        }
    }

    /// Numele folderului care se va crea — aceeași logică ca la Start
    /// (folder existent reluat, altfel numele de azi).
    private var previewFolderName: String {
        runner.findExistingFolderName(destinations: destinationPaths, project: projectName, card: cardName,
                                      template: folderTemplate, camera: cameraName, operatorName: operatorName)
            ?? runner.folderName(project: projectName, card: cardName, template: folderTemplate,
                                 camera: cameraName, operatorName: operatorName)
    }

    /// Recalculează preflight, capacități și mărimea sursei (în fundal).
    private func refreshPreparation(scanSources: Bool = true) {
        preflightIssues = Preflight.check(sources: sourcePaths, destinations: destinationPaths)
        var caps: [String: VolumeCapacity] = [:]
        for d in destinationPaths + sourcePaths { caps[d] = VolumeCapacity.of(d) }
        capacities = caps
        let sources = sourcePaths
        let exclusions = job.exclusions
        guard !sources.isEmpty else { sourceBytes = nil; bytesBySource = [:]; return }
        guard scanSources else { return }
        Task.detached(priority: .utility) {
            var per: [String: Int64] = [:]
            for src in sources {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: src, isDirectory: &isDir) else { continue }
                if isDir.boolValue {
                    per[src] = listAllFiles(root: src, exclusions: exclusions).reduce(0) { $0 + $1.size }
                } else {
                    per[src] = ((try? FileManager.default.attributesOfItem(atPath: src)[.size] as? Int64) ?? nil) ?? 0
                }
            }
            let measured = per
            await MainActor.run {
                if sources == sourcePaths {
                    bytesBySource = measured
                    sourceBytes = measured.values.reduce(0, +)
                }
            }
        }
    }

    /// Permite si tragerea unui folder direct din Finder (nu doar a unui
    /// disc din grila Disks) peste DESTINATIONS, ca sa salvezi intr-un
    /// folder anume, nu neaparat in radacina unui disc intreg.
    private func handleDestinationFinderDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                handled = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    self.acceptDestinationIfDirectory(url)
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handled = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    self.acceptDestinationIfDirectory(url)
                }
            }
        }
        return handled
    }

    private func acceptDestinationIfDirectory(_ url: URL) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }
        DispatchQueue.main.async { addDestination(url.path) }
    }

    private func addDestination(_ path: String) {
        if !destinationPaths.contains(path) {
            destinationPaths.append(path)
        }
    }

    // MARK: - Footer (Start / Anuleaza)

    private var footer: some View {
        VStack(spacing: DM.Space.s) {
            ActivityLogView(lines: runner.activityLines, expanded: $logExpanded)
            HStack(spacing: DM.Space.m) {
                VStack(alignment: .leading, spacing: DM.Space.xxs) {
                    Text(footerStatusText)
                        .font(DM.Font.label)
                        .foregroundStyle(footerStatusColor)
                        .lineLimit(2)
                    if runner.isRunning && !runner.speedText.isEmpty {
                        Text(runner.speedText).font(DM.Font.detail).foregroundStyle(DM.textSecondary)
                    }
                }
                Spacer()
                profilesMenu
                Button {
                    showHistory = true
                } label: {
                    Label(L.t("history.title"), systemImage: "clock.arrow.circlepath")
                }
                .help(L.t("history.title"))
                .sheet(isPresented: $showHistory) {
                    HistoryView(isPresented: $showHistory)
                }
                SettingsLink {
                    Label(L.t("settings.open"), systemImage: "gearshape")
                }
                .help(L.t("settings.open"))
                Text("v\(appVersion)").font(DM.Font.mono).foregroundStyle(DM.textTertiary)
                Button { GuidePDF.open() } label: { Image(systemName: "questionmark.circle") }
                    .buttonStyle(.plain).foregroundStyle(DM.textSecondary)
                    .help(L.t("menu.help")).accessibilityLabel(L.t("menu.help"))
            }
            .labelStyle(.titleAndIcon)
            .controlSize(.regular)
        }
        .padding(.horizontal, DM.Space.l)
        .padding(.vertical, DM.Space.m)
    }

    private var footerStatusColor: Color {
        if runner.isRunning { return DM.textPrimary }
        if let outcome = runner.lastOutcome, runner.statusText != L.t("status.ready") { return DMStatus(outcome).color }
        if Preflight.hasBlocking(preflightIssues) && !sourcePaths.isEmpty && !destinationPaths.isEmpty { return DM.failure }
        return DM.textSecondary
    }

    /// Profilurile de transfer, mutate din popover într-un meniu.
    private var profilesMenu: some View {
        Menu {
            if profileStore.profiles.isEmpty {
                Text(L.t("profiles.none"))
            }
            ForEach(profileStore.profiles) { profile in
                Button(profile.name) { applyProfile(profile) }
            }
            Divider()
            Button(L.t("profiles.save") + "…") { showSaveProfilePrompt = true }
            if !profileStore.profiles.isEmpty {
                Menu(L.t("profiles.delete")) {
                    ForEach(profileStore.profiles) { profile in
                        Button(profile.name, role: .destructive) { profileStore.delete(profile) }
                    }
                }
            }
        } label: {
            Label(L.t("profiles.title"), systemImage: "square.stack")
        }
        .fixedSize()
        .disabled(runner.isRunning)
        .alert(L.t("profiles.namePrompt"), isPresented: $showSaveProfilePrompt) {
            TextField(L.t("profiles.namePrompt"), text: $newProfileName)
            Button(L.t("profiles.save")) { saveCurrentAsProfile() }
            Button(L.t("duplicate.cancel"), role: .cancel) { newProfileName = "" }
        }
    }

    /// Verifica dinainte daca folderul tinta exista deja, nevid, la vreo
    /// destinatie (2026-08-28) - daca da, arata dialogul "Reia / Folder
    /// nou / Suprascrie" in loc sa porneasca direct si sa suprascrie
    /// tacut date existente sau sa creeze duplicate.
    private func attemptStart() {
        // Cautam INTAI un folder deja existent cu acelasi proiect/card,
        // indiferent de data la care a fost creat (vezi
        // findExistingFolderName - fix 2026-08-28 pentru transferuri care
        // trec peste miezul noptii). Doar daca nu gasim niciunul, calculam
        // numele "de azi", ca la un transfer chiar nou.
        let folderName = runner.findExistingFolderName(
            destinations: destinationPaths, project: projectName, card: cardName,
            template: folderTemplate, camera: cameraName, operatorName: operatorName)
            ?? runner.folderName(project: projectName, card: cardName,
                                 template: folderTemplate, camera: cameraName, operatorName: operatorName)
        let existing = runner.existingNonEmptyDestinations(destinations: destinationPaths, folderName: folderName)
        if existing.isEmpty {
            startTransfer(resume: job.resumeEnabled, folderNameOverride: nil)
        } else {
            duplicateFolderName = folderName
            showDuplicateDialog = true
        }
    }

    private func startTransfer(resume: Bool, folderNameOverride: String?, ignoreSpaceWarning: Bool = false) {
        lastStartResume = resume
        lastStartFolderOverride = folderNameOverride
        let exclusions = job.exclusions
        showResult = false
        runner.start(sources: sourcePaths, destinations: destinationPaths,
                     verificationModel: job.verificationModel, exclusions: exclusions,
                     resume: resume, meta: currentMeta, folderTemplate: folderTemplate,
                     folderNameOverride: folderNameOverride,
                     cloudRemote: job.cloudRemote, cloudRemoteFolder: job.cloudRemoteFolder,
                     generateMHL: generateMHL, retryFailedFiles: retryFailedFiles,
                     ejectSourceWhenDone: ejectSourceWhenDone,
                     ignoreSpaceWarning: ignoreSpaceWarning,
                     readBackVerification: job.readBackVerification)
        if runner.isRunning { logExpanded = false }
    }

    // MARK: - Profile de transfer (2026-08-28)

    private func applyProfile(_ profile: TransferProfile) {
        sourcePaths = profile.sourcePaths.filter { FileManager.default.fileExists(atPath: $0) }
        destinationPaths = profile.destinationPaths.filter { FileManager.default.fileExists(atPath: $0) }
        job.verificationModel = profile.verificationModel
        job.exclusionsText = profile.exclusionsText
        chunkSizeMB = profile.chunkSizeMB
        ramLimitMB = profile.ramLimitMB
        job.cloudRemote = profile.cloudRemote ?? ""
        job.cloudRemoteFolder = profile.cloudRemoteFolder ?? ""
    }

    private func saveCurrentAsProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        profileStore.upsert(TransferProfile(
            name: name, sourcePaths: sourcePaths, destinationPaths: destinationPaths,
            verificationModel: job.verificationModel, exclusionsText: job.exclusionsText,
            chunkSizeMB: chunkSizeMB, ramLimitMB: ramLimitMB,
            cloudRemote: job.cloudRemote.isEmpty ? nil : job.cloudRemote,
            cloudRemoteFolder: job.cloudRemoteFolder.isEmpty ? nil : job.cloudRemoteFolder
        ))
        newProfileName = ""
    }


    private var footerStatusText: String {
        if runner.isRunning || runner.statusText != L.t("status.ready") {
            return runner.statusText
        }
        if sourcePaths.isEmpty || destinationPaths.isEmpty {
            return L.t("footer.needSourcesDest")
        }
        return String(format: L.t("footer.summary"), sourcePaths.count, destinationPaths.count)
    }
}

