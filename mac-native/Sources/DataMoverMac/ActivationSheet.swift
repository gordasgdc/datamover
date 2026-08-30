import SwiftUI

struct ActivationSheet: View {
    @EnvironmentObject var license: LicenseManager
    @Binding var isPresented: Bool
    @State private var code: String = ""
    @State private var justCopied = false
    @ObservedObject private var langStore = LanguageStore.shared
    @ObservedObject private var pricing = PricingChecker.shared
    // Countdown live (2026-08-30) - reimprospatat la fiecare minut cat timp
    // fereastra e deschisa, ca timpul afisat sa nu ramana inghetat.
    private let countdownTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    @State private var countdownTick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L.t("activation.title")).font(.title2).bold()
                Spacer()
                Picker("", selection: $langStore.lang) {
                    ForEach(AppLanguage.allCases) { l in
                        Text(l.displayName).tag(l)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
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

            // Pret dinamic (2026-08-30) - vezi PricingChecker. Fail-open la
            // pretul hardcodat daca pricing.json nu e accesibil.
            if let promo = pricing.activePromo {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("🔥 \(promo.label)").font(.system(size: 12, weight: .bold)).foregroundStyle(.orange)
                        if promo.showCountdown {
                            Label(promo.countdownText, systemImage: "timer")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.orange)
                                .id(countdownTick) // fortam refresh vizual la tick
                        }
                    }
                    Text(String(format: L.t("activation.donationPromo"), formattedPrice(promo.price), formattedPrice(pricing.basePrice)))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(String(format: L.t("activation.donation"), formattedPrice(pricing.effectivePrice)))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Button {
                let priceText = formattedPrice(pricing.effectivePrice)
                NSWorkspace.shared.open(WhatsAppLink.url(text: "Buna, vreau sa donez \(priceText) pentru licenta DataMover"))
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
        .onAppear { pricing.refresh() }
        .onReceive(countdownTimer) { _ in countdownTick += 1 }
    }

    private func formattedPrice(_ value: Double) -> String {
        let isWhole = value.truncatingRemainder(dividingBy: 1) == 0
        return "\(isWhole ? String(Int(value)) : String(value)) €"
    }
}
