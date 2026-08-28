import SwiftUI

/// Istoricul copierilor anterioare (data, proiect/card, sursa->destinatie,
/// cate fisiere OK/sarite/esuate) — persistat pe disc intre lansari
/// (HistoryStore). Fereastra permite atat vizualizarea cat si stergerea
/// intrarilor, una cate una sau toate deodata.
struct HistoryView: View {
    @ObservedObject private var store = HistoryStore.shared
    @Binding var isPresented: Bool
    @State private var confirmClearAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L.t("history.title")).font(.title2).bold()
                Spacer()
                if !store.entries.isEmpty {
                    Button(role: .destructive) {
                        confirmClearAll = true
                    } label: {
                        Label(L.t("history.clearAll"), systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .confirmationDialog(L.t("history.clearAllConfirm"), isPresented: $confirmClearAll) {
                        Button(L.t("history.clearAll"), role: .destructive) { store.clearAll() }
                        Button(L.t("activation.cancel"), role: .cancel) {}
                    }
                }
            }

            if store.entries.isEmpty {
                Spacer()
                Text(L.t("history.empty"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(store.entries.reversed()) { entry in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.folderName).font(.system(size: 13, weight: .semibold))
                                    Text(entry.dateText)
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                    Text("\(L.t("history.source")): \(entry.sourcesSummary)")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    Text("\(L.t("history.destination")): \(entry.destSummary)")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    Text("\(L.t("history.ok")): \(entry.okCount)  \(L.t("history.skipped")): \(entry.skipCount)  \(L.t("history.failed")): \(entry.failCount)")
                                        .font(.system(size: 11))
                                        .foregroundStyle(entry.failCount > 0 ? .red : .secondary)
                                    // Deschidere directa in Finder (2026-08-28, extins 2026-08-28):
                                    // acces rapid la FIECARE sursa/destinatie a sesiunii, nu doar
                                    // prima - cerinta explicita a lui Cristi. Intrarile de istoric
                                    // salvate INAINTE de aceasta functie nu au aceste cai (sourcePaths/
                                    // destinationTargetPaths goale) - nu pot fi recuperate retroactiv,
                                    // deci pur si simplu nu arata niciun buton pentru ele.
                                    if !entry.sourcePaths.isEmpty || !entry.destinationTargetPaths.isEmpty {
                                        VStack(alignment: .leading, spacing: 3) {
                                            ForEach(Array(entry.sourcePaths.enumerated()), id: \.offset) { _, path in
                                                Button("\(L.t("history.openSource")): \((path as NSString).lastPathComponent)") {
                                                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                                                }
                                                .buttonStyle(.link)
                                                .font(.system(size: 11))
                                            }
                                            ForEach(Array(entry.destinationTargetPaths.enumerated()), id: \.offset) { _, path in
                                                Button("\(L.t("history.openDestination")): \((path as NSString).lastPathComponent)") {
                                                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                                                }
                                                .buttonStyle(.link)
                                                .font(.system(size: 11))
                                            }
                                        }
                                        .padding(.top, 2)
                                    }
                                }
                                Spacer()
                                Button {
                                    store.delete(entry)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(10)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button(L.t("activation.cancel")) { isPresented = false }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 480)
    }
}
