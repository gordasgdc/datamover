import XCTest
import CryptoKit
@testable import DataMoverMac

/// Migrarea la licențele generația 2. Cheie Ed25519 de TEST generată în test (cheia reală
/// nu e folosită); semnarea reproduce formatul Furnizor (22 octeți + semnătură, Base32).
final class LicenseMigrationTests: XCTestCase {
    let key = Curve25519.Signing.PrivateKey()
    let thisMachine: [UInt8] = [1, 2, 3, 4, 5, 6]
    let otherMachine: [UInt8] = [9, 9, 9, 9, 9, 9]
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    var dir: URL!
    var defaults: UserDefaults!
    var suite = ""
    var logs: [String] = []

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("dm-lic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        suite = "dm-lic-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        logs = []
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
        defaults.removePersistentDomain(forName: suite)
    }

    func serial(_ productID: String, expires: Int64 = 0, machine: [UInt8]?) throws -> String {
        var p = LicenseCore.productHash(for: productID)
        var v = UInt64(bitPattern: expires); var exp = [UInt8](repeating: 0, count: 8)
        for i in stride(from: 7, through: 0, by: -1) { exp[i] = UInt8(v & 0xFF); v >>= 8 }
        p += exp + [7, 7, 7, 7] + (machine ?? [0, 0, 0, 0, 0, 0])
        let sig = try key.signature(for: Data(p))
        return LicenseCore.base32Encode(Data(p) + sig)
    }
    func manager(at date: Date? = nil) -> LicenseManager {
        LicenseManager(defaults: defaults, directory: dir, publicKeyBase64: key.publicKey.rawRepresentation.base64EncodedString(),
                       machineHash: thisMachine, now: { date ?? self.now },
                       log: { event, fields in self.logs.append(event + " " + fields.description) })
    }

    func testLegacyCodeIsDetectedAndRefused() throws {
        let legacy = try serial(LicenseManager.canonicalProductID, machine: thisMachine)
        let m = manager()
        XCTAssertFalse(m.activate(code: legacy))
        XCTAssertEqual(m.activationError, L.t("license.error.legacy"))
        XCTAssertEqual(m.state, .legacyNeedsReactivation)
        XCTAssertFalse(m.hasFullAccess)
        // Reintrodus: tot refuzat.
        XCTAssertFalse(m.activate(code: legacy))
        XCTAssertFalse(m.hasFullAccess)
    }

    func testSavedLegacyLicenseIsMigratedWithoutNewTrial() throws {
        let legacy = try serial(LicenseManager.canonicalProductID, machine: thisMachine)
        defaults.set(now.timeIntervalSince1970, forKey: "datamover_trial_start") // probă încă „activă”
        try legacy.write(to: dir.appendingPathComponent("license.txt"), atomically: true, encoding: .utf8)
        let m = manager()
        XCTAssertEqual(m.state, .legacyNeedsReactivation)
        XCTAssertFalse(m.isTrialActive, "utilizatorul legacy nu primește probă")
        XCTAssertFalse(m.hasFullAccess)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("license.txt").path))
        let backup = dir.appendingPathComponent("license-legacy-v1.txt")
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), legacy, "codul vechi nu se pierde")
        let perms = try FileManager.default.attributesOfItem(atPath: backup.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
        XCTAssertNotNil(m.legacyCodeMasked)
        XCTAssertFalse(m.legacyCodeMasked!.contains(legacy))
        // Starea persistă după repornire.
        XCTAssertEqual(manager().state, .legacyNeedsReactivation)
    }

    func testGeneration2CorrectMachineIsAcceptedAndWorksOffline() throws {
        let code = try serial(LicenseManager.signingProductID, expires: Int64(now.timeIntervalSince1970) + 86400 * 30, machine: thisMachine)
        let m = manager()
        XCTAssertTrue(m.activate(code: code), m.activationError ?? "")
        XCTAssertTrue(m.hasFullAccess)
        // Repornire: validare locală, fără rețea.
        XCTAssertTrue(manager().hasFullAccess)
    }

    func testGeneration2AfterLegacyRestoresAccess() throws {
        let m = manager()
        XCTAssertFalse(m.activate(code: try serial(LicenseManager.canonicalProductID, machine: thisMachine)))
        XCTAssertTrue(m.activate(code: try serial(LicenseManager.signingProductID, machine: thisMachine)))
        XCTAssertTrue(m.hasFullAccess)
        XCTAssertTrue(manager().hasFullAccess)
    }

    func testGeneration2OtherMachineExpiredOrAnyMachineIsRefused() throws {
        let m = manager()
        XCTAssertFalse(m.activate(code: try serial(LicenseManager.signingProductID, machine: otherMachine)))
        XCTAssertEqual(m.activationError, L.t("license.error.wrongMachine"))
        XCTAssertFalse(m.activate(code: try serial(LicenseManager.signingProductID, expires: Int64(now.timeIntervalSince1970) - 1, machine: thisMachine)))
        XCTAssertEqual(m.activationError, L.t("license.error.expired"))
        XCTAssertFalse(m.activate(code: try serial(LicenseManager.signingProductID, machine: nil)))
        XCTAssertEqual(m.activationError, L.t("license.error.notMachineLocked"))
        XCTAssertFalse(m.hasFullAccess)
    }

    func testSerialNeverLogged() throws {
        let legacy = try serial(LicenseManager.canonicalProductID, machine: thisMachine)
        let good = try serial(LicenseManager.signingProductID, machine: thisMachine)
        try legacy.write(to: dir.appendingPathComponent("license.txt"), atomically: true, encoding: .utf8)
        let m = manager()
        _ = m.activate(code: legacy); _ = m.activate(code: good)
        XCTAssertFalse(logs.isEmpty)
        for line in logs { XCTAssertFalse(line.contains(legacy) || line.contains(good) || line.contains(String(good.prefix(20)))) }
    }

    func testFreshInstallKeepsTrial() {
        let m = manager()
        XCTAssertEqual(m.state, .trial(daysLeft: 7))
        XCTAssertTrue(m.isTrialActive)
        XCTAssertFalse(m.hasFullAccess, "proba nu ridică plafonul de 2 GB (politica existentă)")
        XCTAssertEqual(manager(at: now.addingTimeInterval(8 * 86400)).state, .expired)
    }

    func testUpdatePolicy() {
        XCTAssertFalse(UpdatePolicy.shouldPrompt(available: nil, mandatory: false, dismissedVersion: nil, automatic: true))
        XCTAssertTrue(UpdatePolicy.shouldPrompt(available: "2.17.0", mandatory: false, dismissedVersion: nil, automatic: true))
        XCTAssertFalse(UpdatePolicy.shouldPrompt(available: "2.17.0", mandatory: false, dismissedVersion: "2.17.0", automatic: true))
        XCTAssertTrue(UpdatePolicy.shouldPrompt(available: "2.17.0", mandatory: true, dismissedVersion: "2.17.0", automatic: true))
        XCTAssertTrue(UpdatePolicy.shouldPrompt(available: "2.17.0", mandatory: false, dismissedVersion: "2.17.0", automatic: false))
        XCTAssertFalse(UpdatePolicy.shouldRememberDismissal(mandatory: true))
    }
}
