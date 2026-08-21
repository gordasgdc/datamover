import SwiftUI

@main
struct DataMoverMacApp: App {
    @StateObject private var license = LicenseManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(license)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowResizability(.contentSize)
    }
}
