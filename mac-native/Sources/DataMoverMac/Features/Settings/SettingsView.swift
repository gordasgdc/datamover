import AppKit
import SwiftUI

/// Fereastra Settings nativă (⌘,) — înlocuiește popover-ul lung din bara de
/// jos. Opțiunile zilnice sunt primele; cele cu efect asupra integrității sau
/// resurselor stau separat, cu explicația lângă ele.
struct SettingsView: View {
    @ObservedObject private var langStore = LanguageStore.shared

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label(L.t("settingsTab.general"), systemImage: "gearshape") }
            VerificationSettingsTab()
                .tabItem { Label(L.t("settingsTab.verification"), systemImage: "checkmark.shield") }
            ReportsSettingsTab()
                .tabItem { Label(L.t("settingsTab.reports"), systemImage: "doc.text") }
            PerformanceSettingsTab()
                .tabItem { Label(L.t("settingsTab.performance"), systemImage: "speedometer") }
            CloudSettingsTab()
                .tabItem { Label(L.t("settingsTab.cloud"), systemImage: "icloud") }
            AccountSettingsTab()
                .tabItem { Label(L.t("settingsTab.account"), systemImage: "person.crop.circle") }
            DiagnosticsSettingsTab()
                .tabItem { Label(L.t("settingsTab.diagnostics"), systemImage: "stethoscope") }
        }
        .frame(width: DM.Layout.settingsWidth)
        .id(langStore.lang) // relayout la schimbarea limbii
    }
}

private struct SettingsHelp: View {
    let key: String
    var body: some View {
        Text(L.t(key)).font(DM.Font.detail).foregroundStyle(DM.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct GeneralSettingsTab: View {
    @ObservedObject private var langStore = LanguageStore.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    @AppStorage("dm_autoOpenDestFolder") private var autoOpenDestFolder = false
    @AppStorage("dm_ejectWhenDone") private var ejectSourceWhenDone = false
    @AppStorage("dm_autoStartOnCard") private var autoStartOnCardInsert = false

    var body: some View {
        Form {
            Picker(L.t("prefs.language"), selection: $langStore.lang) {
                ForEach(AppLanguage.allCases) { Text($0.displayName).tag($0) }
            }
            Picker(L.t("settings.appearance"), selection: Binding(
                get: { themeManager.current }, set: { themeManager.set($0) })) {
                ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
            }
            Section {
                Toggle(L.t("settings.autoOpenDestFolder"), isOn: $autoOpenDestFolder)
                Toggle(L.t("settings.ejectWhenDone"), isOn: $ejectSourceWhenDone)
                SettingsHelp(key: "settings.ejectWhenDoneHelp2")
                Toggle(L.t("settings.autoStartOnCard"), isOn: $autoStartOnCardInsert)
                SettingsHelp(key: "settings.autoStartOnCardHelp")
            }
            Section {
                LabeledContent(L.t("settings.version")) {
                    Text("DataMover v\(UpdateChecker.currentVersion)").font(DM.Font.mono).textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct VerificationSettingsTab: View {
    @ObservedObject private var job = JobSettings.shared
    @AppStorage("dm_generateMHL") private var generateMHL = true
    @AppStorage("dm_retryFailed") private var retryFailedFiles = true

    var body: some View {
        Form {
            Section {
                Picker(L.t("settings.verificationModel"), selection: $job.verificationModel) {
                    ForEach(VerificationModel.allCases) { Text($0.label).tag($0) }
                }
                Toggle(L.t("settings.readBack"), isOn: $job.readBackVerification)
                    .disabled(job.verificationModel == .sizeOnly)
                SettingsHelp(key: "settings.readBackHelp")
                LabeledContent(L.t("prep.method")) {
                    Text(L.t(job.depth.labelKey)).foregroundStyle(job.depth == .sizeOnly ? DM.warning : DM.textPrimary)
                }
            } header: { Text(L.t("settingsTab.verification")) }
            Section {
                Toggle(L.t("settings.generateMHL"), isOn: $generateMHL)
                SettingsHelp(key: "settings.generateMHLHelp")
                Toggle(L.t("settings.retryFailed"), isOn: $retryFailedFiles)
                SettingsHelp(key: "settings.retryFailedHelp")
                Toggle(L.t("settings.resume"), isOn: $job.resumeEnabled)
                SettingsHelp(key: "settings.resumeHelp")
            }
            Section {
                TextField(L.t("settings.exclusions"), text: $job.exclusionsText, prompt: Text(".tmp, Thumbs.db"))
                SettingsHelp(key: "settings.exclusionsHelp")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ReportsSettingsTab: View {
    @AppStorage("dm_client") private var clientName = ""
    @AppStorage("dm_operatorName") private var operatorName = ""
    @AppStorage("dm_cameraName") private var cameraName = ""
    @AppStorage("dm_logoPath") private var logoPath = ""
    @AppStorage("dm_folderTemplate") private var folderTemplate = NamingTemplate.defaultTemplate

    var body: some View {
        Form {
            Section {
                TextField(L.t("meta.client"), text: $clientName)
                TextField(L.t("meta.operator"), text: $operatorName)
                TextField(L.t("meta.camera"), text: $cameraName)
                LabeledContent(L.t("settings.logo")) {
                    HStack {
                        if !logoPath.isEmpty {
                            Text((logoPath as NSString).lastPathComponent).lineLimit(1).foregroundStyle(DM.textSecondary)
                            Button(L.t("settings.remove")) { logoPath = "" }
                        }
                        Button(logoPath.isEmpty ? L.t("meta.chooseLogo") : L.t("meta.changeLogo")) { chooseLogo() }
                    }
                }
            } header: { Text(L.t("settings.productionTitle")) }
            Section {
                TextField(L.t("settings.folderTemplate"), text: $folderTemplate)
                    .font(DM.Font.mono)
                LabeledContent(L.t("settings.folderPreview")) {
                    Text(NamingTemplate.render(folderTemplate, context: .init(
                        project: L.t("meta.project"), card: "A001", camera: cameraName,
                        operatorName: operatorName, date: Date())))
                        .font(DM.Font.mono).textSelection(.enabled)
                }
                Text(NamingTemplate.tokens.joined(separator: "  ")).font(DM.Font.mono).foregroundStyle(DM.textTertiary)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseLogo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .gif]
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url { logoPath = url.path }
    }
}

private struct PerformanceSettingsTab: View {
    @AppStorage("datamover_chunk_size_mb") private var chunkSizeMB = IOSettings.defaultChunkSizeMB
    @AppStorage("datamover_ram_limit_mb") private var ramLimitMB = 1024

    var body: some View {
        Form {
            Section {
                HStack {
                    ForEach(IOPerformancePreset.all) { preset in
                        Button(L.t(preset.nameKey)) {
                            chunkSizeMB = preset.chunkSizeMB
                            ramLimitMB = preset.ramLimitMB
                        }
                    }
                }
                Picker(L.t("io.buffer"), selection: $chunkSizeMB) {
                    ForEach(IOSettings.chunkSizeChoicesMB, id: \.self) { Text(Self.size($0)).tag($0) }
                }
                Picker(L.t("io.ramLimit"), selection: $ramLimitMB) {
                    ForEach(IOSettings.ramLimitChoicesMB, id: \.self) { mb in
                        Text(mb == 0 ? L.t("io.noLimit") : Self.size(mb)).tag(mb)
                    }
                }
                SettingsHelp(key: "settings.ioHelp")
            } header: { Text(L.t("io.title")) }
        }
        .formStyle(.grouped)
    }

    static func size(_ mb: Int) -> String { mb >= 1024 ? "\(mb / 1024) GB" : "\(mb) MB" }
}

private struct CloudSettingsTab: View {
    @ObservedObject private var job = JobSettings.shared
    @State private var available = false
    @State private var remotes: [String] = []
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                if !loaded {
                    ProgressView().controlSize(.small)
                } else if !available {
                    Text(L.t("settings.cloudUnavailable")).foregroundStyle(DM.warning)
                } else {
                    Picker(L.t("settings.cloudAccount"), selection: $job.cloudRemote) {
                        Text(L.t("settings.cloudNone")).tag("")
                        ForEach(remotes, id: \.self) { Text($0).tag($0) }
                    }
                    if !job.cloudRemote.isEmpty {
                        TextField(L.t("settings.cloudFolderPlaceholder"), text: $job.cloudRemoteFolder)
                        SettingsHelp(key: "settings.cloudHint")
                    }
                }
            } header: { Text(L.t("settings.cloudTitle")) }
        }
        .formStyle(.grouped)
        .task {
            let result = await Task.detached(priority: .utility) { () -> (Bool, [String]) in
                let ok = CloudSyncService.isAvailable()
                return (ok, ok ? CloudSyncService.listRemotes() : [])
            }.value
            available = result.0; remotes = result.1; loaded = true
        }
    }
}

/// Suport: jurnalul local, ID-ul sesiunii, jurnal detaliat temporar și
/// exportul pachetului de diagnostic (nimic nu se trimite automat).
struct DiagnosticsSettingsTab: View {
    @State private var includePaths = false
    @State private var debugOn = StructuredLog.shared.minimumLevel <= .debug
    @State private var lastExport: URL?
    @State private var exportError: String?

    var body: some View {
        Form {
            Section {
                LabeledContent(L.t("diag.session")) {
                    HStack {
                        Text(StructuredLog.shared.sessionID).font(DM.Font.mono).textSelection(.enabled)
                        Button(L.t("activation.copy")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(StructuredLog.shared.sessionID, forType: .string)
                        }
                    }
                }
                LabeledContent(L.t("diag.location")) {
                    Text(StructuredLog.shared.config.directory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(DM.Font.mono).textSelection(.enabled)
                }
                Button(L.t("diag.openFolder")) {
                    try? FileManager.default.createDirectory(at: StructuredLog.shared.config.directory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(StructuredLog.shared.config.directory)
                }
                Toggle(L.t("diag.debug"), isOn: $debugOn)
                    .onChange(of: debugOn) { _, on in StructuredLog.shared.setDebugUntilRelaunch(on) }
                SettingsHelp(key: "diag.debugHelp")
            } header: { Text(L.t("settingsTab.diagnostics")) }
            Section {
                Toggle(L.t("diag.includePaths"), isOn: $includePaths)
                SettingsHelp(key: "diag.includePathsHelp")
                Button(L.t("diag.export")) { export() }
                if let lastExport {
                    Text(lastExport.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(DM.Font.mono).textSelection(.enabled)
                }
                if let exportError { Text(exportError).foregroundStyle(DM.failure) }
                SettingsHelp(key: "diag.exportHelp")
            }
        }
        .formStyle(.grouped)
    }

    private func export() {
        do {
            let url = try DiagnosticExporter(log: StructuredLog.shared, lastJob: HistoryStore.shared.entries.last)
                .export(to: DiagnosticExporter.defaultFolder, options: .init(includePaths: includePaths))
            lastExport = url
            exportError = nil
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            exportError = L.t("diag.exportFailed") + " " + error.localizedDescription
            StructuredLog.shared.log(.error, "diagnostics", "diagnostics.exportFailed", "Export eșuat", error: error)
        }
    }
}

private struct AccountSettingsTab: View {
    @ObservedObject private var license = LicenseManager.shared
    @AppStorage("datamover_profile_name") private var profileName = ""
    @AppStorage("datamover_profile_email") private var profileEmail = ""
    @State private var revealCode = false
    @State private var showActivation = false

    var body: some View {
        Form {
            Section {
                TextField(L.t("profile.name"), text: $profileName)
                TextField(L.t("profile.email"), text: $profileEmail)
                LabeledContent(L.t("profile.machineId")) {
                    HStack {
                        Text(MachineID.display).font(DM.Font.mono).textSelection(.enabled)
                        Button(L.t("activation.copy")) { copy(MachineID.display) }
                    }
                }
            } header: { Text(L.t("profile.title")) }
            Section {
                LabeledContent(L.t("settings.licenseStatus")) {
                    if license.isLicensed {
                        DMStatusBadge(status: .verified, text: L.t("profile.licensedStatus"))
                    } else if license.isTrialActive {
                        DMStatusBadge(status: .warning, text: String(format: L.t("trial.daysLeft"), license.trialDaysRemaining))
                    } else {
                        DMStatusBadge(status: .failure, text: L.t("profile.expiredStatus"))
                    }
                }
                if let code = license.savedLicenseCode {
                    LabeledContent(L.t("profile.savedCode")) {
                        HStack {
                            // Mascat implicit: capturile de ecran nu trebuie
                            // să expună codul.
                            Text(revealCode ? code : Self.mask(code))
                                .font(DM.Font.mono).lineLimit(1).truncationMode(.middle)
                                .textSelection(.enabled)
                            Button(revealCode ? L.t("settings.hide") : L.t("settings.show")) { revealCode.toggle() }
                            Button(L.t("activation.copy")) { copy(code) }
                        }
                    }
                } else {
                    Button(L.t("profile.activate")) { showActivation = true }
                }
            }
            Section {
                LabeledContent(L.t("settings.version")) { Text("v\(UpdateChecker.currentVersion)").font(DM.Font.mono) }
                Button(L.t("menu.checkForUpdates")) { UpdateChecker.checkAndShowAlert() }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showActivation) {
            ActivationSheet(isPresented: $showActivation).environmentObject(license)
        }
    }

    static func mask(_ code: String) -> String {
        guard code.count > 4 else { return String(repeating: "•", count: code.count) }
        return String(repeating: "•", count: min(16, code.count - 4)) + code.suffix(4)
    }

    private func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
