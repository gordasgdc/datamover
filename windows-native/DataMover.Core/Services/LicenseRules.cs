using System.Security.Cryptography;
using System.Text;

namespace DataMover.Core.Services;

/// Regulile de licență fără dependențe de platformă (testate în CoreChecks, pe orice OS).
/// Port 1:1 al mac-native LicenseCore/LicenseManager: aceeași clasificare a codurilor,
/// aceleași stări, aceeași poartă de acces.
///
/// MIGRAREA LA GENERAȚIA 2 (2026-09-27): identitatea comercială rămâne
/// `CanonicalProductId` ("gdc-datamover": catalog, preț, revocare, raportare), dar codurile
/// noi sunt semnate pentru `SigningProductId` — alt hash de produs în payload, aceeași
/// cheie Ed25519 comună GDC. Un cod vechi are semnătură validă și hash-ul canonic:
/// e recunoscut explicit drept `LegacyLicense` și refuzat.
public static class LicenseRules
{
    public const string CanonicalProductId = "gdc-datamover";
    public const string SigningProductId = "gdc-datamover-license-v2";
    public const int PayloadSize = 22;

    public readonly record struct Payload(long ExpiresAt, bool MachineLocked);
    public enum ValidationErrorKind { MalformedCode, BadSignature, WrongProduct, WrongMachine, Expired, LegacyLicense, NotMachineLocked }
    public sealed class ValidationError(ValidationErrorKind kind, long expiredAt = 0) : Exception
    {
        public ValidationErrorKind Kind { get; } = kind;
        public long ExpiredAt { get; } = expiredAt;
    }

    public static byte[] ProductHash(string productId) => SHA512.HashData(Encoding.UTF8.GetBytes(productId))[..4];

    /// Verifică un payload a cărui semnătură a fost deja confirmată.
    public static Payload ValidatePayload(byte[] payload, string expectedProductId, string? legacyProductId,
                                          bool requireMachineLock, byte[] machineHash, long nowUnix)
    {
        if (payload.Length != PayloadSize) throw new ValidationError(ValidationErrorKind.MalformedCode);
        var stored = payload.AsSpan(0, 4);
        if (!stored.SequenceEqual(ProductHash(expectedProductId)))
        {
            if (legacyProductId != null && stored.SequenceEqual(ProductHash(legacyProductId)))
                throw new ValidationError(ValidationErrorKind.LegacyLicense);
            throw new ValidationError(ValidationErrorKind.WrongProduct);
        }
        long expiresAt = 0;
        for (var i = 4; i < 12; i++) expiresAt = (expiresAt << 8) | payload[i];
        var machine = payload.AsSpan(16, 6);
        var locked = machine.ToArray().Any(b => b != 0);
        if (requireMachineLock && !locked) throw new ValidationError(ValidationErrorKind.NotMachineLocked);
        if (locked && !machine.SequenceEqual(machineHash)) throw new ValidationError(ValidationErrorKind.WrongMachine);
        if (expiresAt != 0 && expiresAt < nowUnix) throw new ValidationError(ValidationErrorKind.Expired, expiresAt);
        return new Payload(expiresAt, locked);
    }

    public static string Reason(ValidationErrorKind k) => k switch
    {
        ValidationErrorKind.MalformedCode => "malformed", ValidationErrorKind.BadSignature => "badSignature",
        ValidationErrorKind.WrongProduct => "wrongProduct", ValidationErrorKind.WrongMachine => "wrongMachine",
        ValidationErrorKind.Expired => "expired", ValidationErrorKind.LegacyLicense => "legacyLicense",
        _ => "notMachineLocked",
    };

    /// Primele 5 și ultimele 4 caractere; niciodată codul întreg.
    public static string Mask(string code)
    {
        var c = code.Replace("-", "").Trim();
        return c.Length <= 12 ? "•••" : $"{c[..5]}…{c[^4..]}";
    }
}

/// Starea efectivă — singura sursă pentru acces și pentru afișarea în Profil.
public enum LicenseState { Licensed, LegacyNeedsReactivation, Revoked, Trial, Expired }

public static class LicensePolicy
{
    /// `licensedLocally` = un cod generația 2 valid local (offline). Revocarea (fail-open) poate
    /// doar RETRAGE accesul unei licențe valide; nu transformă niciodată un cod invalid/legacy în licență.
    public static LicenseState Evaluate(bool licensedLocally, bool revoked, bool legacyDetected, int trialDaysRemaining)
    {
        if (licensedLocally) return revoked ? LicenseState.Revoked : LicenseState.Licensed;
        if (legacyDetected) return LicenseState.LegacyNeedsReactivation;
        return trialDaysRemaining > 0 ? LicenseState.Trial : LicenseState.Expired;
    }

    public static bool HasFullAccess(LicenseState s) => s == LicenseState.Licensed;

    /// Singura poartă a transferului: fără acces complet, plafonul de probă se aplică.
    public static bool TransferAllowed(long totalBytes, bool fullAccess, long capBytes) => fullAccess || totalBytes <= capBytes;
}

/// Textele migrării și ale erorilor de activare, RO/EN/ES (aceleași ca pe macOS).
public static class LicenseText
{
    static readonly Dictionary<string, string[]> S = new()
    {
        ["migration.title"] = new[] { "Licența trebuie reactivată", "Your license needs reactivation", "Hay que reactivar la licencia" },
        ["migration.body"] = new[] {
            "Sistemul de licențiere DataMover a fost actualizat. Codul anterior nu mai este valabil în această versiune: pentru acest calculator este necesar un cod nou. Trimite-ne ID-ul calculatorului și introdu codul primit în Profil.",
            "DataMover's licensing system has been updated. Your previous code is no longer valid in this version: this computer needs a new code. Send us the computer ID and enter the code you receive in Profile.",
            "El sistema de licencias de DataMover se ha actualizado. El código anterior ya no es válido en esta versión: este ordenador necesita un código nuevo. Envíanos el ID del ordenador e introduce el código que recibas en Perfil." },
        ["migration.machine"] = new[] { "ID calculator", "Computer ID", "ID del ordenador" },
        ["migration.open"] = new[] { "Deschid acum Profilul, ca să copiezi ID-ul și să introduci codul nou?", "Open Profile now to copy the ID and enter the new code?", "¿Abrir ahora el Perfil para copiar el ID e introducir el código nuevo?" },
        ["err.malformed"] = new[] { "Cod invalid — verifică să nu lipsească vreun caracter.", "Invalid code — check that no character is missing.", "Código no válido: comprueba que no falte ningún carácter." },
        ["err.badSignature"] = new[] { "Semnătura codului nu se potrivește.", "The code's signature does not match.", "La firma del código no coincide." },
        ["err.wrongProduct"] = new[] { "Codul e valid, dar pentru alt produs GDC.", "The code is valid, but for another GDC product.", "El código es válido, pero para otro producto GDC." },
        ["err.wrongMachine"] = new[] { "Codul e blocat pe alt calculator.", "The code is locked to another computer.", "El código está vinculado a otro ordenador." },
        ["err.expired"] = new[] { "Codul a expirat.", "The code has expired.", "El código ha caducado." },
        ["err.legacy"] = new[] {
            "Acest cod este din sistemul vechi de licențiere și nu mai activează DataMover. Cere un cod nou pentru acest calculator.",
            "This code is from the previous licensing system and no longer activates DataMover. Ask for a new code for this computer.",
            "Este código es del sistema de licencias anterior y ya no activa DataMover. Pide un código nuevo para este ordenador." },
        ["err.notMachineLocked"] = new[] { "Codul nou trebuie emis pentru acest calculator (ID calculator).", "The new code must be issued for this computer (computer ID).", "El código nuevo debe emitirse para este ordenador (ID del ordenador)." },
    };

    public static string Lang(System.Globalization.CultureInfo c) => c.TwoLetterISOLanguageName switch { "en" => "en", "es" => "es", _ => "ro" };
    public static string T(string key, string lang) => S.TryGetValue(key, out var v) ? v[lang == "en" ? 1 : lang == "es" ? 2 : 0] : key;
    public static IEnumerable<string> Keys => S.Keys;
    public static bool Complete => S.Values.All(v => v.Length == 3 && v.All(x => x.Length > 0));

    public static string ErrorKey(LicenseRules.ValidationErrorKind k) => k switch
    {
        LicenseRules.ValidationErrorKind.MalformedCode => "err.malformed", LicenseRules.ValidationErrorKind.BadSignature => "err.badSignature",
        LicenseRules.ValidationErrorKind.WrongProduct => "err.wrongProduct", LicenseRules.ValidationErrorKind.WrongMachine => "err.wrongMachine",
        LicenseRules.ValidationErrorKind.Expired => "err.expired", LicenseRules.ValidationErrorKind.LegacyLicense => "err.legacy",
        _ => "err.notMachineLocked",
    };
}

/// Când apare fereastra de actualizare — aceeași regulă ca pe macOS (UpdatePolicy.swift).
public static class UpdatePolicy
{
    public static bool ShouldPrompt(string? available, bool mandatory, string? dismissedVersion, bool automatic)
    {
        if (available is null) return false;
        if (!automatic || mandatory) return true;
        return dismissedVersion != available;
    }
    /// O actualizare obligatorie nu se poate amâna permanent.
    public static bool ShouldRememberDismissal(bool mandatory) => !mandatory;
}
