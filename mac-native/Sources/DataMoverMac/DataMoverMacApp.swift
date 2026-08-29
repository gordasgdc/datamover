import SwiftUI

@main
struct DataMoverMacApp: App {
    @StateObject private var license = LicenseManager.shared
    @ObservedObject private var langStore = LanguageStore.shared
    @Environment(\.openWindow) private var openWindow

    init() {
        AppMover.promptIfNeeded()
        ThemeManager.shared.applyNow()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(license)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L.t("menu.about")) { showAboutPanel() }
            }
            CommandGroup(after: .appInfo) {
                Button(L.t("menu.checkForUpdates")) { UpdateChecker.checkAndShowAlert() }
            }
            CommandGroup(replacing: .help) {
                Button(L.t("menu.help")) {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "help")
                }
                Button(L.t("menu.whatsapp")) {
                    NSWorkspace.shared.open(WhatsAppLink.url())
                }
            }
        }

        WindowGroup(id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)
    }

    private func showAboutPanel() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "DataMover",
            .applicationVersion: UpdateChecker.currentVersion,
            .credits: NSAttributedString(string: "\(L.t("about.credits"))\n© \(Calendar.current.component(.year, from: Date())) GDC. \(L.t("about.rights"))"),
        ])
    }

}
