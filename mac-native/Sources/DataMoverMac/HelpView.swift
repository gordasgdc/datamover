import SwiftUI

/// Ghid de utilizare pas cu pas — fereastra deschisa din meniul Help sau
/// din butonul "?" din interfata.
struct HelpView: View {
    private var steps: [(String, String)] {
        [
            (L.t("help.step1.title"), L.t("help.step1.body")),
            (L.t("help.step2.title"), L.t("help.step2.body")),
            (L.t("help.step3.title"), L.t("help.step3.body")),
            (L.t("help.step4.title"), L.t("help.step4.body")),
            (L.t("help.step5.title"), L.t("help.step5.body")),
            (L.t("help.step6.title"), L.t("help.step6.body")),
            (L.t("help.step7.title"), L.t("help.step7.body")),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(L.t("help.windowTitle")).font(.title2).bold()
                ForEach(steps, id: \.0) { step in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.0).font(.system(size: 13, weight: .semibold))
                        Text(step.1).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
        }
        .frame(width: 480, height: 520)
    }
}
