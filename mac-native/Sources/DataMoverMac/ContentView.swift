import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var license: LicenseManager
    @StateObject private var runner = OffloadRunner()

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
    @State private var projectName: String = ""
    @State private var cardName: String = ""

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
            Text("Proba gratuita — \(license.trialDaysRemaining) zile ramase")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Activeaza licenta") { showActivation = true }
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
                Text("Proiect").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Proiect", text: $projectName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
            }
            HStack(spacing: 6) {
                Text("Card").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Card", text: $cardName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Coloana SOURCES

    private var sourcesColumn: some View {
        VStack(spacing: 10) {
            Text("SOURCES")
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
                    Text("Trage fisiere\nsau foldere aici")
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
                        Image(systemName: isDirectory(path) ? "folder" : "doc")
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
                    Text("Nicio sursa adaugata")
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

    private let gridColumns = [GridItem(.adaptive(minimum: 130, maximum: 150), spacing: 14)]

    private var disksColumn: some View {
        VStack(spacing: 10) {
            Text("Disks")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.top, 14)

            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 14) {
                    ForEach(volumes) { volume in
                        DiskTileView(volume: volume)
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
            Text("DESTINATIONS")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .padding(.top, 14)

            ZStack {
                if destinationPaths.isEmpty {
                    Text("Trage un disc din Disks,\nsau un folder din Finder")
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
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.trailing, 12)
                .disabled(runner.isRunning)
                .popover(isPresented: $showSettings, arrowEdge: .top) {
                    settingsPopover
                }
                Button("Anuleaza") { runner.cancel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 12)
                    .disabled(!runner.isRunning)
                Button(runner.isRunning ? "Se copiaza..." : "Start") {
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
            Text("Setari copiere").font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Model de verificare").font(.system(size: 11)).foregroundStyle(.secondary)
                Picker("", selection: $verificationModel) {
                    ForEach(VerificationModel.allCases) { model in
                        Text(model.label).tag(model)
                    }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Excluderi (nume exact sau .extensie, separate prin virgula)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                TextField(".tmp, .DS_Store, Thumbs.db", text: $exclusionsText)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Reia automat dintr-un checkpoint existent", isOn: $resumeEnabled)
                .font(.system(size: 12))

            if let last = runner.lastResults.first, let folder = last.csvPath.map({ ($0 as NSString).deletingLastPathComponent }) {
                Divider()
                Button("Deschide ultimul raport in Finder") {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder)
                }
                .buttonStyle(.link)
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    private var footerStatusText: String {
        if runner.isRunning || runner.statusText != "Gata de pornire" {
            return runner.statusText
        }
        if sourcePaths.isEmpty || destinationPaths.isEmpty {
            return "Adauga surse si destinatii ca sa pornesti"
        }
        return "\(sourcePaths.count) surse -> \(destinationPaths.count) destinatie(i)"
    }
}

// MARK: - Pictograma-card pentru un disc

private struct DiskTileView: View {
    let volume: VolumeInfo

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.primary)
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
            }
            .padding(.top, 6)
            Text(volume.name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Text(formatBytes(volume.freeBytes))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .frame(width: 130, height: 110)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
