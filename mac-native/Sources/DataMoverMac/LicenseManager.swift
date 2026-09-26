import Foundation

/// Starea efectivă a licenței, singura sursă pentru acces și afișare.
enum LicenseState: Equatable {
    /// Cod generația 2 valid local (offline-first: nu cere rețea).
    case licensed(expiresAt: Int64)
    /// A existat o licență generația 1 (înainte de migrare) — trebuie reemisă.
    /// Nu dă acces complet și nu pornește o probă nouă.
    case legacyNeedsReactivation
    case trial(daysLeft: Int)
    case expired

    var hasFullAccess: Bool { if case .licensed = self { return true }; return false }
}

/// Owns DataMover's trial/license state.
///
/// MIGRAREA LA GENERAȚIA 2 (2026-09-27): identitatea comercială rămâne
/// `canonicalProductID` ("gdc-datamover": catalog, preț, revocare, raportare),
/// dar codurile noi sunt semnate pentru `signingProductID` — alt hash de produs
/// în payload, aceeași cheie Ed25519 comună GDC. Un cod vechi are semnătură
/// validă, dar hash-ul canonic: e recunoscut explicit ca `legacyLicense`,
/// refuzat la activare, iar fișierul lui e mutat într-o copie locală cu acces
/// restrâns (nu șters). Proiectul e open-source (MIT): asta oprește reutilizarea
/// codurilor vechi în aplicația publicată, nu modificarea sursei.
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()
    static let canonicalProductID = "gdc-datamover"
    static let signingProductID = "gdc-datamover-license-v2"
    static let trialDurationDays = 7
    /// Plafon de mărime per transfer fără licență efectivă (2026-08-30). Gating-ul
    /// folosește `hasFullAccess`, nu zilele de probă: reinstalarea nu îl ocolește.
    static let trialMaxTransferBytes: Int64 = 2 * 1024 * 1024 * 1024 // 2 GB

    @Published private(set) var state: LicenseState = .expired
    @Published private(set) var licenseExpiresAt: Int64 = 0 // 0 = perpetual
    @Published var activationError: String?

    /// Compatibilitate: tot codul existent care întreabă „e licențiat?” primește starea EFECTIVĂ.
    var isLicensed: Bool { state.hasFullAccess }
    var hasFullAccess: Bool { state.hasFullAccess }
    var needsReactivation: Bool { state == .legacyNeedsReactivation }

    private let defaults: UserDefaults
    private let directory: URL?
    private let publicKeyBase64: String
    private let machineHash: [UInt8]
    private let now: () -> Date
    private let log: (_ event: String, _ fields: [String: String]) -> Void

    private let trialStartKey = "datamover_trial_start"
    private let legacyDetectedKey = "datamover_legacy_license_detected"
    private let legacyMaskedKey = "datamover_legacy_license_masked"

    private var activationFileURL: URL? { directory?.appendingPathComponent("license.txt") }
    /// Copia codului generația 1, păstrată pentru suport; permisiuni 0600.
    private var legacyBackupURL: URL? { directory?.appendingPathComponent("license-legacy-v1.txt") }

    private convenience init() {
        self.init(defaults: .standard,
                  directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                      .appendingPathComponent("DataMover", isDirectory: true),
                  publicKeyBase64: LicenseCore.publicKeyBase64, machineHash: MachineID.hashBytes, now: Date.init,
                  log: { event, fields in StructuredLog.shared.log(.info, "license", event, "Licență", fields: fields) })
    }

    init(defaults: UserDefaults, directory: URL?, publicKeyBase64: String, machineHash: [UInt8],
         now: @escaping () -> Date, log: @escaping (String, [String: String]) -> Void) {
        self.defaults = defaults
        self.directory = directory
        self.publicKeyBase64 = publicKeyBase64
        self.machineHash = machineHash
        self.now = now
        self.log = log
        // Proba pornește doar la prima rulare; un utilizator legacy nu primește una nouă
        // (vezi `isTrialActive`), iar instalările noi păstrează politica existentă.
        if defaults.object(forKey: trialStartKey) == nil {
            defaults.set(now().timeIntervalSince1970, forKey: trialStartKey)
        }
        loadSavedLicense()
    }

    var trialStartDate: Date { Date(timeIntervalSince1970: defaults.double(forKey: trialStartKey)) }

    var trialDaysRemaining: Int {
        let remaining = Double(Self.trialDurationDays) * 86400 - now().timeIntervalSince(trialStartDate)
        return max(0, Int(ceil(remaining / 86400)))
    }

    /// Un utilizator care a avut o licență generația 1 nu intră în probă.
    var isTrialActive: Bool { !legacyDetected && trialDaysRemaining > 0 }
    var legacyDetected: Bool { defaults.bool(forKey: legacyDetectedKey) }
    /// Codul vechi, mascat (doar pentru suport).
    var legacyCodeMasked: String? { defaults.string(forKey: legacyMaskedKey) }

    /// Codul generația 2 salvat pe disc, pentru afișare (mascat în UI).
    var savedLicenseCode: String? {
        guard let url = activationFileURL,
              let code = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Doar pentru afișare: nu mai decide accesul (vezi `hasFullAccess`).
    var isUnlocked: Bool { hasFullAccess || isTrialActive }

    private func validate(_ code: String) -> Result<LicenseCore.Payload, LicenseCore.ValidationError> {
        LicenseCore.validate(serial: code, expectedProductID: Self.signingProductID,
                             legacyProductID: Self.canonicalProductID, requireMachineLock: true,
                             publicKeyBase64: publicKeyBase64, machineHash: machineHash, now: now())
    }

    @discardableResult
    func activate(code: String) -> Bool {
        activationError = nil
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        switch validate(trimmed) {
        case .success(let payload):
            saveLicense(code: trimmed)
            licenseExpiresAt = payload.expiresAt
            recomputeState(licensed: payload)
            log("license.activated", ["generation": "2", "expires": payload.expiresAt == 0 ? "never" : String(payload.expiresAt)])
            return true
        case .failure(let error):
            if case .legacyLicense = error {
                markLegacy(code: trimmed)
                if !hasFullAccess { recomputeState(licensed: nil) }
            }
            activationError = Self.message(for: error)
            log("license.activationRejected", ["reason": Self.reason(error)])
            return false
        }
    }

    func deactivate() {
        licenseExpiresAt = 0
        if let url = activationFileURL { try? FileManager.default.removeItem(at: url) }
        recomputeState(licensed: nil)
    }

    private func loadSavedLicense() {
        guard let url = activationFileURL,
              let code = try? String(contentsOf: url, encoding: .utf8) else { recomputeState(licensed: nil); return }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        switch validate(trimmed) {
        case .success(let payload):
            licenseExpiresAt = payload.expiresAt
            recomputeState(licensed: payload)
        case .failure(.legacyLicense):
            migrateLegacyFile(code: trimmed, from: url)
            recomputeState(licensed: nil)
        case .failure:
            // Cod generația 2 expirat sau pentru alt calculator: nu dă acces; fișierul rămâne.
            recomputeState(licensed: nil)
        }
    }

    /// Mută codul generația 1 într-o copie cu acces restrâns și reține doar forma mascată.
    private func migrateLegacyFile(code: String, from url: URL) {
        markLegacy(code: code)
        guard let backup = legacyBackupURL else { return }
        let fm = FileManager.default
        try? fm.removeItem(at: backup)
        do {
            try fm.moveItem(at: url, to: backup)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        } catch {
            log("license.legacyBackupFailed", [:])
        }
        log("license.legacyDetected", ["action": "backup"])
    }

    private func markLegacy(code: String) {
        if !legacyDetected { defaults.set(true, forKey: legacyDetectedKey) }
        defaults.set(Self.mask(code), forKey: legacyMaskedKey)
    }

    private func recomputeState(licensed payload: LicenseCore.Payload?) {
        if let payload { state = .licensed(expiresAt: payload.expiresAt) }
        else if legacyDetected { state = .legacyNeedsReactivation }
        else if trialDaysRemaining > 0 { state = .trial(daysLeft: trialDaysRemaining) }
        else { state = .expired }
    }

    private func saveLicense(code: String) {
        guard let url = activationFileURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? code.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Primele 5 și ultimele 4 caractere; niciodată codul întreg.
    static func mask(_ code: String) -> String {
        let c = code.replacingOccurrences(of: "-", with: "")
        guard c.count > 12 else { return "•••" }
        return "\(c.prefix(5))…\(c.suffix(4))"
    }

    private static func reason(_ error: LicenseCore.ValidationError) -> String {
        switch error {
        case .malformedCode: return "malformed"
        case .badSignature: return "badSignature"
        case .wrongProduct: return "wrongProduct"
        case .wrongMachine: return "wrongMachine"
        case .expired: return "expired"
        case .legacyLicense: return "legacyLicense"
        case .notMachineLocked: return "notMachineLocked"
        }
    }

    private static func message(for error: LicenseCore.ValidationError) -> String {
        switch error {
        case .malformedCode: return L.t("license.error.malformed")
        case .badSignature: return L.t("license.error.badSignature")
        case .wrongProduct: return L.t("license.error.wrongProduct")
        case .wrongMachine: return L.t("license.error.wrongMachine")
        case .expired: return L.t("license.error.expired")
        case .legacyLicense: return L.t("license.error.legacy")
        case .notMachineLocked: return L.t("license.error.notMachineLocked")
        }
    }
}
