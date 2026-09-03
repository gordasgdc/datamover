import Foundation
import UserNotifications

/// [2026-09-03] Notificare nativa macOS la finalul unui transfer.
///
/// DE CE: un offload de card plin dureaza zeci de minute pana la ore.
/// Pana acum, singurul semnal de final era un sunet ("Glass") — care se
/// pierde daca operatorul e in alta camera, are casti puse pe alt canal,
/// sau pur si simplu s-a intamplat sa vorbeasca cu cineva in secunda aia.
/// O notificare de sistem ramane in Centrul de notificari pana e citita,
/// deci intrebarea "s-a terminat cardul?" are un raspuns verificabil.
enum SystemNotifier {
    /// `UNUserNotificationCenter.current()` arunca o exceptie fatala daca
    /// procesul nu are bundle identifier (cazul unei rulari directe din
    /// linia de comanda, `swift run`, nu al aplicatiei instalate). Verificam
    /// explicit, ca o rulare de test sa nu crape aplicatia la final.
    static func notify(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = nil // sunetul propriu (NSSound "Glass") ramane cel principal
            let request = UNNotificationRequest(identifier: UUID().uuidString,
                                                content: content, trigger: nil)
            center.add(request, withCompletionHandler: nil)
        }
    }
}
