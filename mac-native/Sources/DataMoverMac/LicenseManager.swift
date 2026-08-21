import Foundation

/// Owns DataMover's trial/license state: starts a 7-day trial on first
/// launch, persists an activated code once entered, and exposes whether
/// the app should currently be unlocked. Same product line/signing key
/// as gdc-license-system (see LicenseCore.swift) — codes issued for
/// "gdc-datamover" via sell.py work here unchanged; this is a
/// same-product Swift port, independent of the Python/Tkinter Windows
/// build's own on-disk license file (different app, different path).
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()
    static let productID = "gdc-datamover"
    static let trialDurationDays = 7

    @Published private(set) var isLicensed = false
    @Published private(set) var licenseExpiresAt: Int64 = 0 // 0 = perpetual
    @Published private(set) var licenseMachineLocked = false
    @Published var activationError: String?

    private let defaults = UserDefaults.standard
    private let trialStartKey = "datamover_trial_start"

    private var activationFileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("DataMover", isDirectory: true)
            .appendingPathComponent("license.txt")
    }

    private init() {
        if defaults.object(forKey: trialStartKey) == nil {
            defaults.set(Date().timeIntervalSince1970, forKey: trialStartKey)
        }
        loadSavedLicense()
    }

    var trialStartDate: Date {
        Date(timeIntervalSince1970: defaults.double(forKey: trialStartKey))
    }

    /// Zile intregi ramase din proba, rotunjit in sus.
    var trialDaysRemaining: Int {
        let elapsed = Date().timeIntervalSince(trialStartDate)
        let remaining = Double(Self.trialDurationDays) * 86400 - elapsed
        return max(0, Int(ceil(remaining / 86400)))
    }

    var isTrialActive: Bool { trialDaysRemaining > 0 }

    /// Singurul loc verificat inainte de a permite pornirea unui offload.
    var isUnlocked: Bool { isLicensed || isTrialActive }

    @discardableResult
    func activate(code: String) -> Bool {
        activationError = nil
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        switch LicenseCore.validate(serial: trimmed, expectedProductID: Self.productID) {
        case .success(let payload):
            saveLicense(code: trimmed)
            applyLicense(payload: payload)
            return true
        case .failure(let error):
            activationError = Self.message(for: error)
            return false
        }
    }

    func deactivate() {
        isLicensed = false
        licenseExpiresAt = 0
        licenseMachineLocked = false
        if let url = activationFileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func loadSavedLicense() {
        guard let url = activationFileURL,
              let code = try? String(contentsOf: url, encoding: .utf8) else { return }
        if case .success(let payload) = LicenseCore.validate(serial: code, expectedProductID: Self.productID) {
            applyLicense(payload: payload)
        }
    }

    private func applyLicense(payload: LicenseCore.Payload) {
        isLicensed = true
        licenseExpiresAt = payload.expiresAt
        licenseMachineLocked = payload.machineLocked
    }

    private func saveLicense(code: String) {
        guard let url = activationFileURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? code.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func message(for error: LicenseCore.ValidationError) -> String {
        switch error {
        case .malformedCode: return "Format de cod invalid."
        case .badSignature: return "Cod serial invalid — semnatura nu se potriveste."
        case .wrongProduct: return "Acest cod e pentru alt produs."
        case .wrongMachine: return "Acest cod e activat pentru alt calculator."
        case .expired: return "Codul serial a expirat."
        }
    }
}
