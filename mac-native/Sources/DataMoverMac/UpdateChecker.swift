import AppKit

/// "Check for Updates" manual — compara versiunea rulata cu ultimul tag de
/// pe GitHub Releases si ofera un link direct de download daca e mai noua.
/// Nu e updater silentios/automat (ar avea nevoie de Sparkle + appcast
/// semnat) — e varianta simpla, fara infrastructura suplimentara.
enum UpdateChecker {
    private static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/gordasgdc/datamover/releases/latest")!
    private static let releasesPageURL = URL(string: "https://github.com/gordasgdc/datamover/releases/latest")!

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    static func checkAndShowAlert() {
        Task {
            let result = await fetchLatestTag()
            await MainActor.run { presentResult(result) }
        }
    }

    private enum Result {
        case upToDate
        case newVersion(String)
        case error
    }

    private static func fetchLatestTag() async -> Result {
        var request = URLRequest(url: latestReleaseAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                return .error
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            if isVersion(latest, newerThan: currentVersion) {
                return .newVersion(latest)
            }
            return .upToDate
        } catch {
            return .error
        }
    }

    private static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let partsA = a.split(separator: ".").compactMap { Int($0) }
        let partsB = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(partsA.count, partsB.count) {
            let x = i < partsA.count ? partsA[i] : 0
            let y = i < partsB.count ? partsB[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func presentResult(_ result: Result) {
        let alert = NSAlert()
        switch result {
        case .upToDate:
            alert.messageText = "Esti la zi"
            alert.informativeText = "Ai deja ultima versiune (\(currentVersion))."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        case .newVersion(let version):
            alert.messageText = "Versiune noua disponibila"
            alert.informativeText = "Versiunea \(version) este disponibila (ai \(currentVersion))."
            alert.addButton(withTitle: "Descarca")
            alert.addButton(withTitle: "Mai tarziu")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(releasesPageURL)
            }
        case .error:
            alert.messageText = "Verificare actualizari"
            alert.informativeText = "Nu am putut verifica versiunea — incearca mai tarziu."
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
