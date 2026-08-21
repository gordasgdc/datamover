import SwiftUI

@main
struct DataMoverMacApp: App {
    @StateObject private var license = LicenseManager.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(license)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Despre DataMover") { showAboutPanel() }
            }
            CommandGroup(after: .appInfo) {
                Button("Verifica actualizari...") { UpdateChecker.checkAndShowAlert() }
            }
            CommandGroup(replacing: .help) {
                Button("Ghid de utilizare DataMover") { openWindow(id: "help") }
                Button("Contact WhatsApp") {
                    NSWorkspace.shared.open(URL(string: "https://wa.me/40712345678")!)
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
            .credits: NSAttributedString(string: "Dezvoltat de GDC — dumitrugdc@gmail.com\n© \(Calendar.current.component(.year, from: Date())) GDC. Toate drepturile rezervate."),
        ])
    }

}
