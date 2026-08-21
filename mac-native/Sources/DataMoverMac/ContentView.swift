import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var license: LicenseManager
    @StateObject private var runner = OffloadRunner()
    @Environment(\.openWindow) private var openWindow

    @State private var sourcePaths: [String] = []
    @State private var destinationPaths: [String] = []
    @State private var volumes: [VolumeInfo] = []
    @State private var isDropTargetedSources = false
    @State private var isDropTargetedDestFromFinder = false
    @State private var showActivation = false

    // setari de copiere/verificare
    @State private var verificationModel: VerificationModel = .md5
    @State private var exclusionsText: String = ""
    @State private var resumeEnabled: Bool = true
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var projectName: String = ""
    @State private var cardName: String = ""
    @State private var diskIconSize: CGFloat = 150
    @State private var lang: AppLanguage = L.current

    // drag manual disc -> DESTINATIONS
    @State private var draggingDiskPath: String? = nil
    @State private var dragPoint: CGPoint = .zero
    @State private var destFrame: CGRect = .zero

    private let refreshTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

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
            .onAppear { volumes = VolumeInfo.detectAll() }
            .onReceive(refreshTimer) { _ in volumes = VolumeInfo.detectAll() }
            .sheet(isPresented: $showActivation) {
                ActivationSheet(isPresented: $showActivation)
                    .environmentObject(license)
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
            Button {
                openWindow(id: "help")
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

    // MARK: - Coloana SOURCES

    private var sourcesColumn: some View {
        VStack(spacing: 10) {
            Text(L.t("sources.title"))
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.top, 14)

            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [5, 3]))
                .foregroundStyle(isDropTargetedSources ? .green : .secondary.opacity(0.4))
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
                .onDrop(of: [.fileURL], isTargeted: $isDropTargetedSources) { providers in
                    handleSourceDrop(providers)
                }

            List {
                ForEach(sourcePaths, id: \.self) { path in
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: 18, height: 18)
                        Text((path as NSString).lastPathComponent)
                            .lineLimit(1)
                        Spacer()
                        Button {
                            sourcePaths.removeAll { $0 == path }
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
        }
    }

    private func handleSourceDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    if !sourcePaths.contains(url.path) {
                        sourcePaths.append(url.path)
                    }
                }
            }
        }
        return true
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
                                        if destFrame.contains(value.location) {
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
            .onDrop(of: [.fileURL], isTargeted: $isDropTargetedDestFromFinder) { providers in
                handleDestinationFinderDrop(providers)
            }
        }
    }

    /// Permite si tragerea unui folder direct din Finder (nu doar a unui
    /// disc din grila Disks) peste DESTINATIONS, ca sa salvezi intr-un
    /// folder anume, nu neaparat in radacina unui disc intreg.
    private func handleDestinationFinderDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return }
                DispatchQueue.main.async { addDestination(url.path) }
            }
        }
        return true
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
                .popover(isPresented: $showHistory, arrowEdge: .top) {
                    historyPopover
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
                }
                Button(L.t("footer.cancel")) { runner.cancel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 12)
                    .disabled(!runner.isRunning)
                Button(runner.isRunning ? L.t("footer.copying") : L.t("footer.start")) {
                    let exclusions = exclusionsText.split(separator: ",").map(String.init)
                    runner.start(sources: sourcePaths, destinations: destinationPaths,
                                 verificationModel: verificationModel, exclusions: exclusions,
                                 resume: resumeEnabled, project: projectName, card: cardName)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(runner.isRunning || sourcePaths.isEmpty || destinationPaths.isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L.t("settings.title")).font(.headline)
                Spacer()
                Picker("", selection: $lang) {
                    ForEach(AppLanguage.allCases) { l in
                        Text(l.displayName).tag(l)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                .onChange(of: lang) { _, newValue in L.current = newValue }
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

            if let last = runner.lastResults.first, let folder = last.csvPath.map({ ($0 as NSString).deletingLastPathComponent }) {
                Divider()
                Button(L.t("settings.openLastReport")) {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder)
                }
                .buttonStyle(.link)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    /// Istoricul copierilor anterioare (data, proiect/card, sursa->destinatie,
    /// cate fisiere OK/sarite/esuate) — persistat pe disc intre lansari.
    private var historyPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L.t("history.title")).font(.headline)
            if HistoryStore.shared.entries.isEmpty {
                Text(L.t("history.empty"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(HistoryStore.shared.entries.reversed()) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.folderName).font(.system(size: 12, weight: .semibold))
                                Text("\(entry.dateText) · \(entry.sourcesSummary) -> \(entry.destSummary)")
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                                Text("\(L.t("history.ok")): \(entry.okCount)  \(L.t("history.skipped")): \(entry.skipCount)  \(L.t("history.failed")): \(entry.failCount)")
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 260)
            }
        }
        .padding(16)
        .frame(width: 340)
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
