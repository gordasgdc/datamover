import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var license: LicenseManager
    @StateObject private var runner = OffloadRunner()

    @State private var sourcePaths: [String] = []
    @State private var destinationPaths: [String] = []
    @State private var volumes: [VolumeInfo] = []
    @State private var isDropTargetedSources = false
    @State private var isDropTargetedDest = false
    @State private var showActivation = false

    private let refreshTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            if license.isTrialActive && !license.isLicensed {
                trialBar
            }

            HStack(spacing: 0) {
                sourcesColumn
                    .frame(width: 230)
                Divider()
                disksColumn
                    .frame(maxWidth: .infinity)
                Divider()
                destinationsColumn
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
                            .onDrag { NSItemProvider(object: volume.path as NSString) }
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
                    Text("Trage un disc aici\nca destinatie")
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
                    .fill(isDropTargetedDest ? Color.green.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .onDrop(of: [.text], isTargeted: $isDropTargetedDest) { providers in
                handleDestinationDrop(providers)
            }
        }
    }

    private func handleDestinationDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: NSString.self) { text, _ in
                guard let path = text as? String else { return }
                DispatchQueue.main.async {
                    if !destinationPaths.contains(path) {
                        destinationPaths.append(path)
                    }
                }
            }
        }
        return true
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
                Button("Anuleaza") { runner.cancel() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 12)
                    .disabled(!runner.isRunning)
                Button(runner.isRunning ? "Se copiaza..." : "Start") {
                    runner.start(sources: sourcePaths, destinations: destinationPaths)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(runner.isRunning || sourcePaths.isEmpty || destinationPaths.isEmpty)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
