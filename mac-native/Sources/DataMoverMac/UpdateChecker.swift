import AppKit

/// "Check for Updates" manual — compara versiunea rulata cu ultimul tag de
/// pe GitHub Releases.
///
/// PROCESS (2026-08-26): pana acum, butonul "Descarca" din alerta doar
/// deschidea pagina web de release-uri in browser — userul trebuia sa
/// gaseasca singur fisierul potrivit si sa-l instaleze manual. Acum
/// citeste direct asset-ul `.pkg` din raspunsul GitHub API (acelasi
/// raspuns folosit deja pentru versiune, un singur request) si il pasa lui
/// `SelfUpdater`, care descarca + instaleaza fara sa mai iasa din
/// aplicatie. Pagina web ramane doar fallback (`releasesPageURL`), pentru
/// cazul rar cand release-ul n-are inca un `.pkg` atasat.
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
        /// Versiunea gasita + URL-ul de descarcare direct al `.pkg`-ului,
        /// daca release-ul chiar are unul atasat (ar trebui sa aiba mereu,
        /// vezi release.sh — dar un release facut manual, incomplet, tot
        /// nu trebuie sa blocheze alerta, doar sa cada pe fallback).
        case newVersion(version: String, pkgURL: URL?)
        case error
    }

    /// PROCESS: numele exact al asset-ului stabil, publicat de release.sh
    /// la fiecare lansare (langa cel versionat, DataMover-X.Y.Z.pkg). Daca
    /// vreodata schimbi numele in build_installer.sh, schimba-l si aici —
    /// altfel update-ul automat cade tacut pe fallback-ul de browser.
    private static let stablePkgAssetName = "DataMover.pkg"

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
            guard isVersion(latest, newerThan: currentVersion) else { return .upToDate }

            let pkgURL = pkgDownloadURL(from: json)
            return .newVersion(version: latest, pkgURL: pkgURL)
        } catch {
            return .error
        }
    }

    /// Cauta un asset `.pkg` in raspunsul GitHub API — intai numele stabil
    /// (`DataMover.pkg`), apoi orice `.pkg` (ordine de siguranta, daca
    /// cineva a facut un release manual cu alt nume).
    private static func pkgDownloadURL(from releaseJSON: [String: Any]) -> URL? {
        guard let assets = releaseJSON["assets"] as? [[String: Any]] else { return nil }
        func url(for name: String) -> URL? {
            assets.first { ($0["name"] as? String) == name }
                .flatMap { $0["browser_download_url"] as? String }
                .flatMap(URL.init(string:))
        }
        if let stable = url(for: stablePkgAssetName) { return stable }
        for asset in assets {
            if let name = asset["name"] as? String, name.hasSuffix(".pkg"),
               let urlString = asset["browser_download_url"] as? String {
                return URL(string: urlString)
            }
        }
        return nil
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
            alert.messageText = L.t("update.upToDate.title")
            alert.informativeText = String(format: L.t("update.upToDate.body"), currentVersion)
            alert.addButton(withTitle: "OK")
            alert.runModal()
        case .newVersion(let version, let pkgURL):
            alert.messageText = L.t("update.available.title")
            alert.informativeText = String(format: L.t("update.available.body"), version, currentVersion)
            alert.addButton(withTitle: L.t("update.download"))
            alert.addButton(withTitle: L.t("update.later"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }

            if let pkgURL {
                Task { await SelfUpdater.downloadAndInstall(pkgURL: pkgURL, version: version) }
            } else {
                // Fallback: release-ul n-are (inca) un .pkg atasat — nu
                // blocam userul, doar deschidem pagina, ca inainte.
                NSWorkspace.shared.open(releasesPageURL)
            }
        case .error:
            alert.messageText = L.t("update.error.title")
            alert.informativeText = L.t("update.error.body")
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}
