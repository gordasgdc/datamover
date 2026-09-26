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
    @State private var diskIconSize: CGFloat = 150
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
                metaBar
                Divider()

                HStack(spacing: 0) {
                    sourcesColumn
                        .frame(width: 230)
                    Divider()
                    disksColumn
                        .frame(maxWidth: .infinity)
                    Divider()
                    GeometryReader { geo in
                        destinationsColumn
                            .onAppear { destFrame = geo.frame(in: .named("root")) }
                            .onChange(of: geo.size) { _, _ in
                                destFrame = geo.frame(in: .named("root"))
                            }
                    }
                    .frame(width: 230)
                }
                .frame(maxHeight: .infinity)

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

    /// Numele folderului de destinatie (<data>_Proiect_Card), la fel ca in
    /// aplicatia Windows — implicit "Proiect"/"Card" daca lasi gol.
    private var metaBar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Text(L.t("meta.project")).font(.system(size: 11)).foregroundStyle(.secondary)
                TextField(L.t("meta.project"), text: $projectName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
            }
            HStack(spacing: 6) {
                Text(L.t("meta.card")).font(.system(size: 11)).foregroundStyle(.secondary)
                TextField(L.t("meta.card"), text: $cardName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            Spacer()
            // Versiune vizibila in UI — "Directiva Permanenta Suprema"
            // (2026-08-25, CLAUDE.md): orice aplicatie GDC trebuie sa-si
            // arate versiunea, fara exceptie.
            Text("v\(appVersion)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Button {
                GuidePDF.open()
            } label: {
                Image(systemName: "questionmark.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(L.t("menu.help"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    // MARK: - Coloana SOURCES

    private var sourcesColumn: some View {
        VStack(spacing: 10) {
            Text(L.t("sources.title"))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.top, 14)

            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                .foregroundStyle((isDropTargetedSources || isHoveringSource) ? .green : .secondary.opacity(0.4))
                .background(
                    // strokeBorder deseneaza DOAR conturul — fara un fundal
                    // "plin" (chiar si transparent), doar linia subtire e
                    // hit-testabila, nu tot interiorul cutiei. RoundedRectangle
                    // umplut cu .clear rezolva asta, fara sa schimbe vizual nimic.
                    RoundedRectangle(cornerRadius: 8).fill(Color.clear)
                )
                .contentShape(Rectangle())
                .frame(height: 90)
                .overlay(
                    Text(L.t("sources.dropHint"))
                        .multilineTextAlignment(.center)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                )
                .padding(.horizontal, 10)
                .background(
                    // Urmarim cutia asta (nu toata coloana) in coordonate
                    // "root", la fel ca destFrame pt. Destinatii — vezi
                    // nota de arhitectura de la `sourcesFrame`.
                    GeometryReader { geo in
                        Color.clear
                            .onAppear { sourcesFrame = geo.frame(in: .named("root")) }
                            .onChange(of: geo.size) { _, _ in
                                sourcesFrame = geo.frame(in: .named("root"))
                            }
                    }
                )
                .onDrop(of: [.fileURL, .volume], isTargeted: $isDropTargetedSources) { providers in
                    handleSourceDrop(providers)
                }

            List {
                ForEach(sourcePaths, id: \.self) { path in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text((path as NSString).lastPathComponent)
                                .lineLimit(1)
                            // [2026-09-03] Tipul de card recunoscut
                            // (RED/ARRI/Sony…) + numarul de clipuri —
                            // confirmarea vizuala ca s-a selectat cardul
                            // intreg, nu un subfolder din el.
                            if let info = cardInfoBySource[path] {
                                Text(info.summary)
                                    .font(.system(size: 9))
                                    .foregroundStyle(info.warnings.isEmpty ? Color.green : Color.orange)
                            }
                        }
                        Spacer()
                        Button {
                            sourcePaths.removeAll { $0 == path }
                            cardInfoBySource[path] = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.system(size: 11))
                }
            }
            .listStyle(.plain)
            .overlay {
                if sourcePaths.isEmpty {
                    Text(L.t("sources.empty"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            cardQueueSection
        }
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

    // MARK: - Coloana centrala: Disks

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: diskIconSize, maximum: diskIconSize + 20), spacing: 14)]
    }

    /// Coloana centrala: grila de discuri cat timp nu se copiaza, panoul de
    /// monitorizare in timpul transferului.
    ///
    /// Comutarea e pe `runner.isRunning`, singura stare care spune asta —
    /// nu pe un flag propriu, care s-ar putea desincroniza de motor.
    private var disksColumn: some View {
        ZStack {
            if runner.isRunning {
                TransferMonitorView(runner: runner)
                    .transition(.opacity)
            } else if showResult, let outcome = runner.lastOutcome {
                ResultPanel(outcome: outcome, results: runner.lastResults,
                            folderName: runner.lastFolderName, depth: runner.lastVerificationDepth,
                            totalBytes: runner.bytesDone, elapsedSeconds: runner.elapsedSeconds,
                            onDismiss: { showResult = false })
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    PrepPanel(sources: sourcePaths, cardInfo: cardInfoBySource,
                              destinations: destinationPaths, capacities: capacities,
                              sourceBytes: sourceBytes, folderName: previewFolderName,
                              depth: job.depth, issues: preflightIssues, notes: $job.shootNotes)
                        .padding([.horizontal, .top], DM.Space.l)
                    diskGridColumn
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: runner.isRunning)
        .animation(.easeInOut(duration: 0.2), value: showResult)
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
        for d in destinationPaths { caps[d] = VolumeCapacity.of(d) }
        capacities = caps
        let sources = sourcePaths
        let exclusions = job.exclusions
        guard !sources.isEmpty else { sourceBytes = nil; return }
        guard scanSources else { return }
        Task.detached(priority: .utility) {
            var total: Int64 = 0
            for src in sources {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: src, isDirectory: &isDir) else { continue }
                if isDir.boolValue {
                    total += listAllFiles(root: src, exclusions: exclusions).reduce(0) { $0 + $1.size }
                } else {
                    total += ((try? FileManager.default.attributesOfItem(atPath: src)[.size] as? Int64) ?? nil) ?? 0
                }
            }
            let measured = total
            await MainActor.run { if sources == sourcePaths { sourceBytes = measured } }
        }
    }

    private var diskGridColumn: some View {
        VStack(spacing: 10) {
            HStack {
                Text(L.t("disks.title"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "photo")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Slider(value: $diskIconSize, in: 100...220)
                    .frame(width: 90)
                Image(systemName: "photo")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 14)
            .padding(.horizontal, 14)

            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(volumes) { volume in
                        DiskTileView(volume: volume, size: diskIconSize)
                            .contentShape(Rectangle())
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
                    }
                }
                .padding(14)
            }
        }
    }

    // MARK: - Coloana DESTINATIONS

    private var destinationsColumn: some View {
        VStack(spacing: 10) {
            Text(L.t("dest.title"))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.top, 14)

            ZStack {
                if destinationPaths.isEmpty {
                    Text(L.t("dest.dropHint"))
                        .multilineTextAlignment(.center)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                List {
                    ForEach(destinationPaths, id: \.self) { path in
                        HStack {
                            Image(systemName: "externaldrive").foregroundStyle(DM.textSecondary)
                            VStack(alignment: .leading, spacing: DM.Space.xxs) {
                                Text((path as NSString).lastPathComponent)
                                    .font(DM.Font.label.weight(.semibold))
                                    .lineLimit(1)
                                if let cap = capacities[path] {
                                    Text(String(format: L.t("prep.freeShort"), formatBytes(cap.free)))
                                        .font(DM.Font.detail).foregroundStyle(DM.textSecondary)
                                    DMCapacityBar(total: cap.total, free: cap.free, incoming: sourceBytes ?? 0)
                                }
                            }
                            .help(path)
                            Spacer()
                            Button {
                                destinationPaths.removeAll { $0 == path }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(runner.isRunning)
                            .accessibilityLabel(L.t("dest.remove") + " " + (path as NSString).lastPathComponent)
                        }
                        .padding(.vertical, DM.Space.xxs)
                    }
                }
                .listStyle(.plain)
                .opacity(destinationPaths.isEmpty ? 0 : 1)
            }
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill((isHoveringDest || isDropTargetedDestFromFinder) ? Color.green.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .onDrop(of: [.fileURL, .volume], isTargeted: $isDropTargetedDestFromFinder) { providers in
                handleDestinationFinderDrop(providers)
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
                if runner.isRunning {
                    Button(runner.isPaused ? L.t("footer.resume") : L.t("footer.pause")) {
                        runner.togglePause()
                    }
                    Button(L.t("footer.cancel"), role: .destructive) { runner.cancel() }
                        .keyboardShortcut(".", modifiers: .command)
                }
                Button(runner.isRunning ? L.t("footer.copying") : L.t("footer.start")) {
                    attemptStart()
                }
                .buttonStyle(.borderedProminent)
                .tint(DM.accent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(runner.isRunning || sourcePaths.isEmpty || destinationPaths.isEmpty
                          || Preflight.hasBlocking(preflightIssues))
                .confirmationDialog(L.t("duplicate.title"), isPresented: $showDuplicateDialog, titleVisibility: .visible) {
                    Button(L.t("duplicate.resume")) {
                        startTransfer(resume: true, folderNameOverride: duplicateFolderName)
                    }
                    Button(L.t("duplicate.newFolder")) {
                        // Baza e numele "de azi" (nu cel vechi gasit),
                        // ca un folder chiar nou sa nu mosteneasca data
                        // veche a transferului anterior.
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

// MARK: - Pictograma-card pentru un disc

private struct DiskTileView: View {
    let volume: VolumeInfo
    var size: CGFloat = 150

    /// Rezultatul sondarii, incarcat asincron. `nil` = inca nesondat sau
    /// nedeterminabil; atunci nu se afiseaza nicio insigna, in loc de una
    /// care spune "necunoscut".
    @State private var probe: VolumeSpeedProbe?

    private var iconSize: CGFloat { size * 0.35 }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                // iconita nativa macOS a discului (extern portocaliu/argintiu,
                // intern etc.) — aceeasi cu cea din Finder, nu un simbol generic.
                Image(nsImage: volume.icon)
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
                Circle()
                    .fill(.green)
                    .frame(width: 10, height: 10)
                    .offset(x: 2, y: -2)
            }
            .padding(.top, 8)
            Text(volume.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Text(formatBytes(volume.freeBytes))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            if let badge = probe?.badgeText {
                Text(badge)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
        }
        .padding(.vertical, 12)
        .frame(width: size, height: size + (size * 0.13))
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: volume.path) {
            // Sincron din cache daca a mai fost sondat (montare repetata,
            // redesenare), altfel in fundal — vezi VolumeSpeedProbeService.
            // `??` nu accepta `await` in dreapta, deci cele doua cazuri se
            // scriu explicit.
            if let known = VolumeSpeedProbeService.cached(for: volume.path) {
                probe = known
            } else {
                probe = await VolumeSpeedProbeService.probe(path: volume.path)
            }
        }
    }
}
