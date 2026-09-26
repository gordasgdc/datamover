import Foundation

/// Când apare fereastra de actualizare — aceeași regulă pe macOS și Windows (UpdatePolicy.cs).
/// Verificarea manuală arată mereu versiunea nouă; cea automată o sare dacă utilizatorul a
/// amânat-o, cu excepția unei actualizări obligatorii. Nimic nu se instalează fără consimțământ.
enum UpdatePolicy {
    static func shouldPrompt(available: String?, mandatory: Bool, dismissedVersion: String?, automatic: Bool) -> Bool {
        guard let available else { return false }
        if !automatic || mandatory { return true }
        return dismissedVersion != available
    }

    /// O actualizare obligatorie nu se poate amâna permanent.
    static func shouldRememberDismissal(mandatory: Bool) -> Bool { !mandatory }
}
