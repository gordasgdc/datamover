import SwiftUI

struct ActivationSheet: View {
    @EnvironmentObject var license: LicenseManager
    @Binding var isPresented: Bool
    @State private var code: String = ""
    @State private var justCopied = false
    @State private var lang: AppLanguage = L.current

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L.t("activation.title")).font(.title2).bold()
                Spacer()
                Picker("", selection: $lang) {
                    ForEach(AppLanguage.allCases) { l in
                        Text(l.displayName).tag(l)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                .onChange(of: lang) { _, newValue in L.current = newValue }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("activation.machineID"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack {
                    Text(MachineID.display)
                        .font(.system(.body, design: .monospaced))
                    Button(justCopied ? L.t("activation.copied") : L.t("activation.copy")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(MachineID.display, forType: .string)
                        justCopied = true
                    }
                    .buttonStyle(.bordered)
                }
            }

            TextField(L.t("activation.codePlaceholder"), text: $code)
                .textFieldStyle(.roundedBorder)

            if let error = license.activationError {
                Text(error).foregroundStyle(.red).font(.system(size: 12))
            }

            Text(L.t("activation.donation"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button {
                NSWorkspace.shared.open(URL(string: "https://wa.me/40712345678?text=Buna%2C%20vreau%20sa%20cumpar%20licenta%20DataMover")!)
            } label: {
                Label(L.t("activation.whatsapp"), systemImage: "message.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .tint(.green)

            HStack {
                Button(L.t("activation.cancel")) { isPresented = false }
                Spacer()
                Button(L.t("activation.activate")) {
                    if license.activate(code: code) {
                        isPresented = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
