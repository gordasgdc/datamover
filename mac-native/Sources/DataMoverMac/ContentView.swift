import SwiftUI
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
    @State private var verificationModel: VerificationModel = .xxhash64
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
    @State private var shootNotes = ""
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
    @State private var exclusionsText: String = ""
    // Destinatie secundara Cloud (2026-08-30) - vezi CloudSyncService.
    // "" inseamna "dezactivat", niciun upload nu porneste.
    @State private var cloudRemote: String = ""
    @State private var cloudRemoteFolder: String = ""
    @State private var availableCloudRemotes: [String] = []
    @State private var cloudAvailable = false
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
    @AppStorage("datamover_profile_name") private var profileName = ""
    @AppStorage("datamover_profile_email") private var profileEmail = ""
    @AppStorage("datamover_ram_limit_mb") private var ramLimitMB = 1024
    @State private var showCompletionAlert = false
    @State private var resumeEnabled: Bool = true
    // Duplicate/Reluare (2026-08-28) - vezi attemptStart()/startTransfer().
    @State private var showDuplicateDialog = false
    @State private var duplicateFolderName: String = ""
    // Profile de transfer (2026-08-28) - vezi transferProfilesSection.
    @ObservedObject private var profileStore = TransferProfileStore.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @State private var showSaveProfilePrompt = false
    @State private var newProfileName: String = ""
    @State private var showSettings = false
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
            }
            .onReceive(refreshTimer) { _ in refreshVolumesAndDetectNew() }
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
                guard !wasCancelled else { return }
                if autoOpenDestFolder { openLastDestinationFolder() }
                showCompletionAlert = true
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
                       notes: shootNotes, logoPath: logoPath)
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

    private var disksColumn: some View {
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
                            Image(systemName: "externaldrive")
                            Text((path as NSString).lastPathComponent)
                                .lineLimit(1)
                            Spacer()
                            Button {
                                destinationPaths.removeAll { $0 == path }
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
        VStack(spacing: 6) {
            if runner.isRunning {
                ProgressView(value: Double(runner.progressPercent), total: 100)
                    .tint(.green)
                terminalActivityFeed
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(footerStatusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    if !runner.speedText.isEmpty {
                        Text(runner.speedText)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    // Buffer Alocat / Utilizat, live (2026-08-28) - cerinta
                    // explicita: userul vede clar ce resurse sunt alocate,
                    // nu doar un procent de progres.
                    if runner.isRunning {
                        Text("\(L.t("io.allocated")): \(runner.bufferAllocatedText)  |  \(L.t("io.used")): \(runner.memoryUsedText)")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    showHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 15))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
                .contentShape(Circle())
                .padding(.trailing, 8)
                .help(L.t("history.title"))
                .sheet(isPresented: $showHistory) {
                    HistoryView(isPresented: $showHistory)
                }
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
                .padding(.trailing, 12)
                .disabled(runner.isRunning)
                .popover(isPresented: $showSettings, arrowEdge: .top) {
                    settingsPopover
                        .onAppear { refreshCloudRemotes() }
                }
                // Pauza/Continua (2026-08-28) - alaturi de Anuleaza, dar
                // reversibil: opreste temporar transferul FARA sa piarda
                // progresul, spre deosebire de Anuleaza (definitiv). Vezi
                // PauseToken/OffloadRunner.togglePause.
                if runner.isRunning {
                    Button(runner.isPaused ? L.t("footer.resume") : L.t("footer.pause")) {
                        runner.togglePause()
                    }
                    .buttonStyle(.bordered)
                    .padding(.trailing, 12)
                }
                Button(L.t("footer.cancel")) { runner.cancel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 12)
                    .disabled(!runner.isRunning)
                Button(runner.isRunning ? L.t("footer.copying") : L.t("footer.start")) {
                    attemptStart()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(runner.isRunning || sourcePaths.isEmpty || destinationPaths.isEmpty)
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
                        startTransfer(resume: resumeEnabled, folderNameOverride: freeName)
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
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
            startTransfer(resume: resumeEnabled, folderNameOverride: nil)
        } else {
            duplicateFolderName = folderName
            showDuplicateDialog = true
        }
    }

    private func startTransfer(resume: Bool, folderNameOverride: String?, ignoreSpaceWarning: Bool = false) {
        lastStartResume = resume
        lastStartFolderOverride = folderNameOverride
        let exclusions = exclusionsText.split(separator: ",").map(String.init)
        runner.start(sources: sourcePaths, destinations: destinationPaths,
                     verificationModel: verificationModel, exclusions: exclusions,
                     resume: resume, meta: currentMeta, folderTemplate: folderTemplate,
                     folderNameOverride: folderNameOverride,
                     cloudRemote: cloudRemote, cloudRemoteFolder: cloudRemoteFolder,
                     generateMHL: generateMHL, retryFailedFiles: retryFailedFiles,
                     ejectSourceWhenDone: ejectSourceWhenDone,
                     ignoreSpaceWarning: ignoreSpaceWarning)
    }

    /// [2026-09-03] Metadatele productiei + sablonul de denumire.
    /// Toate campurile sunt OPTIONALE — un transfer fara ele functioneaza
    /// exact ca inainte. Completate, apar in antetul rapoartelor PDF/HTML
    /// si (unde userul le pune in sablon) in numele folderelor.
    private var productionMetaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("settings.productionTitle"))
                .font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)

            HStack(spacing: 8) {
                TextField(L.t("meta.client"), text: $clientName).textFieldStyle(.roundedBorder)
                TextField(L.t("meta.operator"), text: $operatorName).textFieldStyle(.roundedBorder)
            }
            TextField(L.t("meta.camera"), text: $cameraName).textFieldStyle(.roundedBorder)
            TextField(L.t("meta.notes"), text: $shootNotes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)

            HStack(spacing: 8) {
                Button(logoPath.isEmpty ? L.t("meta.chooseLogo") : L.t("meta.changeLogo")) {
                    chooseLogo()
                }
                .font(.system(size: 11))
                if !logoPath.isEmpty {
                    Text((logoPath as NSString).lastPathComponent)
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    Button {
                        logoPath = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(L.t("settings.folderTemplate"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                TextField(NamingTemplate.defaultTemplate, text: $folderTemplate)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                // Previzualizare live: userul vede EXACT numele folderului
                // care se va crea, inainte sa porneasca transferul — un
                // sablon gresit descoperit dupa 2 TB copiati nu se mai
                // poate corecta fara sa muti manual folderul.
                Text(L.t("settings.folderPreview") + " " + runner.folderName(
                    project: projectName, card: cardName, template: folderTemplate,
                    camera: cameraName, operatorName: operatorName))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Text(NamingTemplate.tokens.joined(separator: "  "))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func chooseLogo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            logoPath = url.path
        }
    }

    /// Reimprospateaza lista de conturi Cloud (rclone listremotes) - apelat
    /// la deschiderea popover-ului de Setari, headless, ca in Regula 4.
    private func refreshCloudRemotes() {
        DispatchQueue.global(qos: .utility).async {
            let available = CloudSyncService.isAvailable()
            let remotes = available ? CloudSyncService.listRemotes() : []
            DispatchQueue.main.async {
                cloudAvailable = available
                availableCloudRemotes = remotes
            }
        }
    }

    /// Flux de activitate stil Terminal, in footer, cat timp ruleaza un
    /// transfer — vezi DestinationJob.onActivity/OffloadRunner.logActivity.
    /// Motivul: la fisiere foarte mari (video 4K/RAW), bara de progres
    /// poate ramane pe loc zeci de secunde intre doua fisiere, dand
    /// impresia ca aplicatia s-a blocat. Un flux de text care se misca
    /// (chiar daca procentul nu se misca inca) e liniștitor — userul vede
    /// ca se lucreaza, nu ghiceste.
    private var terminalActivityFeed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(runner.activityLines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.green.opacity(0.85))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(6)
            }
            .background(Color.black.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(height: 70)
            .padding(.horizontal, 14)
            // Deruleaza automat la ultima linie — un terminal real nu
            // asteapta ca userul sa dea scroll manual ca sa vada ce
            // urmeaza sa se intample.
            .onChange(of: runner.activityLines.count) { _, _ in
                guard let lastIndex = runner.activityLines.indices.last else { return }
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo(lastIndex, anchor: .bottom)
                }
            }
        }
    }

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L.t("settings.title")).font(.headline)
                Spacer()
                Picker("", selection: $langStore.lang) {
                    ForEach(AppLanguage.allCases) { l in
                        Text(l.displayName).tag(l)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
            }

            // Selector Sistem/Luminos/Intunecat (Regula 18) - lipsea complet,
            // aplicatia urma orb tema macOS. Vezi AppTheme.swift.
            HStack {
                Text(L.t("settings.appearance")).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: Binding(
                    get: { themeManager.current },
                    set: { themeManager.set($0) }
                )) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.label).tag(theme)
                    }
                }
                .labelsHidden()
                .frame(width: 130)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("settings.verificationModel")).font(.system(size: 11)).foregroundStyle(.secondary)
                Picker("", selection: $verificationModel) {
                    ForEach(VerificationModel.allCases) { model in
                        Text(model.label).tag(model)
                    }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("settings.exclusions"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                TextField(".tmp, .DS_Store, Thumbs.db", text: $exclusionsText)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle(L.t("settings.resume"), isOn: $resumeEnabled)
                .font(.system(size: 12))

            Toggle(L.t("settings.autoOpenDestFolder"), isOn: $autoOpenDestFolder)
                .font(.system(size: 12))

            // [2026-09-03] MHL + reincercare automata — vezi MHLWriter.swift
            // si DestinationJob.retryFailed. Explicatia de sub fiecare bifa
            // nu e decor: un DIT stie ce e un MHL, dar un videograf care
            // descarca singur cardul nu, iar bifa fara context ar fi lasata
            // pe implicit fara sa inteleaga ce livreaza mai departe.
            VStack(alignment: .leading, spacing: 2) {
                Toggle(L.t("settings.generateMHL"), isOn: $generateMHL)
                    .font(.system(size: 12))
                Text(L.t("settings.generateMHLHelp"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Toggle(L.t("settings.retryFailed"), isOn: $retryFailedFiles)
                    .font(.system(size: 12))
                Text(L.t("settings.retryFailedHelp"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(L.t("settings.ejectWhenDone"), isOn: $ejectSourceWhenDone)
                .font(.system(size: 12))
                .help(L.t("settings.ejectWhenDoneHelp"))

            Toggle(L.t("settings.autoStartOnCard"), isOn: $autoStartOnCardInsert)
                .font(.system(size: 12))
                .help(L.t("settings.autoStartOnCardHelp"))

            Divider()

            productionMetaSection

            Divider()

            // Destinatie secundara Cloud, powered by Rclone (2026-08-30) -
            // vezi CloudSyncService. Foloseste ACELEASI conturi configurate
            // in Cloud Manager-ul din Master Control Studio Pro (rclone.conf
            // e global, nu izolat per aplicatie) - nimic nou de configurat
            // aici daca userul are deja un cont acolo.
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("settings.cloudTitle")).font(.system(size: 11)).foregroundStyle(.secondary)
                if !cloudAvailable {
                    Text(L.t("settings.cloudUnavailable"))
                        .font(.system(size: 11)).foregroundStyle(.orange)
                } else {
                    Picker("", selection: $cloudRemote) {
                        Text(L.t("settings.cloudNone")).tag("")
                        ForEach(availableCloudRemotes, id: \.self) { remote in
                            Text(remote).tag(remote)
                        }
                    }
                    .labelsHidden()
                    if !cloudRemote.isEmpty {
                        TextField(L.t("settings.cloudFolderPlaceholder"), text: $cloudRemoteFolder)
                            .textFieldStyle(.roundedBorder)
                        Text(L.t("settings.cloudHint"))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            // I/O & Memorie (2026-08-27, extins 2026-08-28) - vezi
            // IOSettings.swift. Motiv: caz real de swap la maxim / "out of
            // application memory" la un transfer de 3 TB - userul poate
            // alege acum un buffer mai mic (masini modeste) sau un plafon
            // de RAM la care aplicatia face pauza intre fisiere in loc sa
            // lase memoria sa creasca nestapanit (backpressure).
            VStack(alignment: .leading, spacing: 6) {
                Text(L.t("io.title")).font(.system(size: 11)).foregroundStyle(.secondary)

                // Preset-uri rapide (2026-08-28, cerinta explicita):
                // Eco/Standard/High Performance/Extreme - fiecare seteaza
                // simultan buffer + plafon RAM, ramanand oricand ajustabile
                // manual dupa.
                HStack(spacing: 6) {
                    ForEach(IOPerformancePreset.all) { preset in
                        Button(L.t(preset.nameKey)) {
                            chunkSizeMB = preset.chunkSizeMB
                            ramLimitMB = preset.ramLimitMB
                        }
                        .buttonStyle(.bordered)
                        .font(.system(size: 10))
                    }
                }

                HStack {
                    Text(L.t("io.buffer"))
                    Picker("", selection: $chunkSizeMB) {
                        ForEach(IOSettings.chunkSizeChoicesMB, id: \.self) { mb in
                            Text(ioSizeLabel(mb)).tag(mb)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }
                HStack {
                    Text(L.t("io.ramLimit"))
                    Picker("", selection: $ramLimitMB) {
                        ForEach(IOSettings.ramLimitChoicesMB, id: \.self) { mb in
                            Text(mb == 0 ? L.t("io.noLimit") : ioSizeLabel(mb)).tag(mb)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 90)
                }
            }
            .font(.system(size: 12))

            Divider()
            transferProfilesSection

            if let last = runner.lastResults.first, let folder = last.csvPath.map({ ($0 as NSString).deletingLastPathComponent }) {
                Divider()
                Button(L.t("settings.openLastReport")) {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder)
                }
                .buttonStyle(.link)
            }

            Divider()
            profileSection

            Divider()
            Button {
                UpdateChecker.checkAndShowAlert()
            } label: {
                Label(L.t("menu.checkForUpdates"), systemImage: "arrow.down.circle")
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(width: 360)
    }

    // MARK: - Profil utilizator + Licenta (2026-08-28)
    // Lipsea complet - Cristi: "nu vad panoul... numele de la client,
    // email, ID-ul masinii, plus acces sa-si vada serialul introdus, ca
    // sa stie care e". Nume/Email raman locale (@AppStorage) - Mac nu are
    // inca infrastructura Supabase de profil (vezi flag de paritate din
    // CLAUDE.md, portat deja pe Windows) - de aliniat la o etapa viitoare.
    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t("profile.title")).font(.system(size: 11)).foregroundStyle(.secondary)

            TextField(L.t("profile.name"), text: $profileName)
                .textFieldStyle(.roundedBorder)
            TextField(L.t("profile.email"), text: $profileEmail)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("profile.machineId")).font(.system(size: 10)).foregroundStyle(.secondary)
                HStack {
                    Text(MachineID.display).font(.system(.caption, design: .monospaced))
                    Spacer()
                    Button(L.t("activation.copy")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(MachineID.display, forType: .string)
                    }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L.t("profile.savedCode")).font(.system(size: 10)).foregroundStyle(.secondary)
                if let code = license.savedLicenseCode {
                    HStack {
                        Text(code).font(.system(.caption, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(L.t("activation.copy")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(code, forType: .string)
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                    }
                } else {
                    HStack {
                        Text(L.t("profile.noCode")).font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Button(L.t("profile.activate")) { showSettings = false; showActivation = true }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                    }
                }
            }

            if license.isLicensed {
                Text(L.t("profile.licensedStatus")).font(.system(size: 11)).foregroundStyle(.secondary)
            } else if license.isTrialActive {
                Text(String(format: L.t("trial.daysLeft"), license.trialDaysRemaining)).font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Text(L.t("profile.expiredStatus")).font(.system(size: 11)).foregroundStyle(.red)
            }
        }
        .font(.system(size: 12))
    }

    /// "512 MB" sub 1 GB, "8 GB" de la 1024 MB in sus - cerinta explicita
    /// (trepte pana la 64 GB+ trebuie sa ramana lizibile, nu "65536 MB").
    private func ioSizeLabel(_ mb: Int) -> String {
        mb >= 1024 ? "\(mb / 1024) GB" : "\(mb) MB"
    }

    // MARK: - Profile de transfer (2026-08-28)

    /// Salveaza/incarca o configuratie completa sub un nume ales de user
    /// (cai sursa/destinatie, model de verificare, buffer/RAM) - cerinta
    /// explicita: seteaza o singura data un backup recurent, refolosit
    /// fara sa retastezi nimic data viitoare.
    private var transferProfilesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L.t("profiles.title")).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button {
                    showSaveProfilePrompt = true
                } label: {
                    Image(systemName: "plus.circle")
                }
                .buttonStyle(.plain)
                .help(L.t("profiles.save"))
            }

            if profileStore.profiles.isEmpty {
                Text(L.t("profiles.none")).font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ForEach(profileStore.profiles) { profile in
                    HStack {
                        Text(profile.name).font(.system(size: 12)).lineLimit(1)
                        Spacer()
                        Button(L.t("profiles.load")) { applyProfile(profile) }
                            .buttonStyle(.link).font(.system(size: 11))
                        Button {
                            profileStore.delete(profile)
                        } label: {
                            Image(systemName: "trash").font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .alert(L.t("profiles.namePrompt"), isPresented: $showSaveProfilePrompt) {
            TextField(L.t("profiles.namePrompt"), text: $newProfileName)
            Button(L.t("profiles.save")) {
                saveCurrentAsProfile()
            }
            Button(L.t("duplicate.cancel"), role: .cancel) { newProfileName = "" }
        }
    }

    private func applyProfile(_ profile: TransferProfile) {
        sourcePaths = profile.sourcePaths.filter { FileManager.default.fileExists(atPath: $0) }
        destinationPaths = profile.destinationPaths.filter { FileManager.default.fileExists(atPath: $0) }
        verificationModel = profile.verificationModel
        exclusionsText = profile.exclusionsText
        chunkSizeMB = profile.chunkSizeMB
        ramLimitMB = profile.ramLimitMB
        cloudRemote = profile.cloudRemote ?? ""
        cloudRemoteFolder = profile.cloudRemoteFolder ?? ""
    }

    private func saveCurrentAsProfile() {
        let name = newProfileName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        profileStore.upsert(TransferProfile(
            name: name, sourcePaths: sourcePaths, destinationPaths: destinationPaths,
            verificationModel: verificationModel, exclusionsText: exclusionsText,
            chunkSizeMB: chunkSizeMB, ramLimitMB: ramLimitMB,
            cloudRemote: cloudRemote.isEmpty ? nil : cloudRemote,
            cloudRemoteFolder: cloudRemoteFolder.isEmpty ? nil : cloudRemoteFolder
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
        }
        .padding(.vertical, 12)
        .frame(width: size, height: size + (size * 0.13))
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
