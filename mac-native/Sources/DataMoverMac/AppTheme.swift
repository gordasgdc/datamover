import AppKit
import Combine
import SwiftUI

/// Selector explicit de temă Sistem/Light/Dark — Regula 18 (CLAUDE.md,
/// Partea 1): "unii clienți vor Light chiar și noaptea, alții Dark
/// permanent; NU e suficient să urmezi orbește tema sistemului".
///
/// Gasit lipsa complet (2026-08-29, raportat de Cristi: "nu vad de unde
/// sa schimb configuratia asta") - DataMover Mac urma pana acum orb tema
/// de sistem, exact ce interzice Regula 18. Port 1:1 al implementarii de
/// referinta `AppTheme.swift`/`ThemeManager` din
/// gdc-plugin-manager-catalog-vendor/Sources/GDCPluginManagerCore.
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Sistem"
        case .light: return "Luminos"
        case .dark: return "Întunecat"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil // nil = urmeaza setarea macOS
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// Persista alegerea local (UserDefaults) si o aplica IMEDIAT, fara
/// repornire. DELIBERAT `NSApp.appearance`, nu `.preferredColorScheme()`
/// pe view-ul radacina: `preferredColorScheme` afecteaza doar ierarhia
/// SwiftUI a acelei ferestre - meniurile, panourile native (NSOpenPanel,
/// NSAlert) ar fi ramas pe tema sistemului, exact incoerenta pe care
/// selectorul trebuie s-o elimine.
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    private static let key = "DataMover.appTheme"

    @Published private(set) var current: AppTheme

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.key)
        current = saved.flatMap(AppTheme.init(rawValue:)) ?? .system
        apply()
    }

    func set(_ theme: AppTheme) {
        guard theme != current else { return }
        UserDefaults.standard.set(theme.rawValue, forKey: Self.key)
        current = theme
        apply()
    }

    private func apply() {
        NSApp?.appearance = current.nsAppearance
    }

    /// De chemat din `.task`/`onAppear`-ul ferestrei principale, ca tema
    /// salvata sa fie activa de la primul cadru chiar daca ThemeManager
    /// s-a initializat inainte ca NSApp sa existe.
    func applyNow() { apply() }
}
