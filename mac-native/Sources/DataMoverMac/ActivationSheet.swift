import SwiftUI

struct ActivationSheet: View {
    @EnvironmentObject var license: LicenseManager
    @Binding var isPresented: Bool
    @State private var code: String = ""
    @State private var justCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Activare DataMover").font(.title2).bold()

            VStack(alignment: .leading, spacing: 4) {
                Text("ID calculator (trimite-mi asta):")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack {
                    Text(MachineID.display)
                        .font(.system(.body, design: .monospaced))
                    Button(justCopied ? "Copiat!" : "Copiaza") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(MachineID.display, forType: .string)
                        justCopied = true
                    }
                    .buttonStyle(.bordered)
                }
            }

            TextField("Cod licenta", text: $code)
                .textFieldStyle(.roundedBorder)

            if let error = license.activationError {
                Text(error).foregroundStyle(.red).font(.system(size: 12))
            }

            Text("Cei 23 € sunt o donatie, nu un pret de lista — ma ajuta sa acopar costurile de dezvoltare si sa continui sa intretin si imbunatatesc aplicatia.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button {
                NSWorkspace.shared.open(URL(string: "https://wa.me/40712345678?text=Buna%2C%20vreau%20sa%20cumpar%20licenta%20DataMover")!)
            } label: {
                Label("Contacteaza-ma pe WhatsApp pentru cumparare/suport", systemImage: "message.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .tint(.green)

            HStack {
                Button("Anuleaza") { isPresented = false }
                Spacer()
                Button("Activeaza") {
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
