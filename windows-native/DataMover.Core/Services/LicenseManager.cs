using System.Globalization;

namespace DataMover.Core.Services;

/// Starea de probă/licență DataMover pe Windows — port al mac-native LicenseManager.swift.
///
/// Accesul complet are O SINGURĂ sursă: `HasFullAccess` (stare `Licensed`, adică un cod
/// generația 2 valid local și nerevocat). Plafonul de transfer și orice alt gating îl
/// folosesc pe acesta, niciodată `IsLicensed` brut. Validarea e offline-first: fără rețea,
/// un cod generația 2 valid funcționează; revocarea (fail-open) poate doar retrage accesul.
/// Migrarea (2026-09-27): un cod generația 1 salvat e mutat în `license-legacy-v1.txt`
/// (nu șters), iar aplicația cere un cod nou; utilizatorul legacy nu primește probă nouă.
public sealed class LicenseManager
{
    public static readonly LicenseManager Shared = new(
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DataMover"),
        publicKeyBase64: null, machineHash: null, now: () => DateTimeOffset.Now,
        isRevoked: () => RevocationCheck.IsRevoked(ProductId),
        log: (evt, fields) => Diagnostics.StructuredLog.Shared.Log(Diagnostics.LogLevel.Info, "license", evt, "Licenta", fields: fields));

    /// Identitatea comercială (catalog, preț, revocare) — neschimbată.
    public const string ProductId = LicenseRules.CanonicalProductId;
    public const int TrialDurationDays = 7;
    public const long TrialMaxTransferBytes = 2L * 1024 * 1024 * 1024; // 2 GB

    private readonly string _dir;
    private readonly string? _publicKey;
    private readonly byte[]? _machineHash;
    private readonly Func<DateTimeOffset> _now;
    private readonly Func<bool> _isRevoked;
    private readonly Action<string, Dictionary<string, string>> _log;
    private DateTimeOffset _trialStart;
    private bool _licensedLocally;

    public long LicenseExpiresAt { get; private set; }
    public string? ActivationError { get; private set; }
    public event Action? Changed;

    /// Pentru teste (WinChecks): director, cheie de test, Machine ID, ora și revocarea injectate.
    public LicenseManager(string directory, string? publicKeyBase64, byte[]? machineHash, Func<DateTimeOffset> now,
                          Func<bool> isRevoked, Action<string, Dictionary<string, string>> log)
    {
        _dir = directory; _publicKey = publicKeyBase64; _machineHash = machineHash; _now = now; _isRevoked = isRevoked; _log = log;
        EnsureTrialStarted();
        LoadSavedLicense();
    }

    private string TrialStartFilePath => Path.Combine(_dir, "trial-start.txt");
    private string ActivationFilePath => Path.Combine(_dir, "license.txt");
    private string LegacyBackupPath => Path.Combine(_dir, "license-legacy-v1.txt");
    /// Marcaj persistent: a existat o licență generația 1 (conține doar forma mascată).
    private string LegacyMarkerPath => Path.Combine(_dir, "license-legacy-detected.txt");

    public LicenseState State => LicensePolicy.Evaluate(_licensedLocally, _licensedLocally && _isRevoked(), LegacyDetected, TrialDaysRemainingRaw);
    public bool HasFullAccess => LicensePolicy.HasFullAccess(State);
    /// Compatibilitate: înseamnă acum acces EFECTIV (licență generația 2 nerevocată).
    public bool IsLicensed => HasFullAccess;
    public bool NeedsReactivation => State == LicenseState.LegacyNeedsReactivation;
    public bool LegacyDetected => File.Exists(LegacyMarkerPath);
    public string? LegacyCodeMasked => LegacyDetected ? SafeRead(LegacyMarkerPath) : null;

    private void EnsureTrialStarted()
    {
        if (File.Exists(TrialStartFilePath) && long.TryParse(SafeRead(TrialStartFilePath), out var unix))
        {
            _trialStart = DateTimeOffset.FromUnixTimeSeconds(unix);
            return;
        }
        _trialStart = _now();
        Directory.CreateDirectory(_dir);
        File.WriteAllText(TrialStartFilePath, _trialStart.ToUnixTimeSeconds().ToString());
    }

    /// Codul generația 2 salvat (afișat mascat în UI).
    public string? SavedLicenseCode => File.Exists(ActivationFilePath) ? SafeRead(ActivationFilePath) : null;

    private int TrialDaysRemainingRaw
    {
        get
        {
            var remaining = TimeSpan.FromDays(TrialDurationDays) - (_now() - _trialStart);
            return Math.Max(0, (int)Math.Ceiling(remaining.TotalDays));
        }
    }
    public int TrialDaysRemaining => LegacyDetected ? 0 : TrialDaysRemainingRaw;
    /// Un utilizator care a avut o licență generația 1 nu intră în probă.
    public bool IsTrialActive => State == LicenseState.Trial;
    /// Doar pentru afișare.
    public bool IsUnlocked => HasFullAccess || IsTrialActive;

    public Task RefreshRevocationAsync() => RevocationCheck.RefreshAsync(new[] { ProductId });

    private LicenseRules.Payload Validate(string code) =>
        LicenseCore.Validate(code, LicenseRules.SigningProductId, LicenseRules.CanonicalProductId, requireMachineLock: true,
            publicKeyBase64: _publicKey, machineHash: _machineHash, nowUnix: _now().ToUnixTimeSeconds());

    public bool Activate(string code)
    {
        ActivationError = null;
        var trimmed = code.Trim();
        try
        {
            var payload = Validate(trimmed);
            Directory.CreateDirectory(_dir);
            File.WriteAllText(ActivationFilePath, trimmed);
            _licensedLocally = true;
            LicenseExpiresAt = payload.ExpiresAt;
            _log("license.activated", new() { ["generation"] = "2", ["expires"] = payload.ExpiresAt == 0 ? "never" : payload.ExpiresAt.ToString() });
            Changed?.Invoke();
            _ = RevocationCheck.RefreshAsync(new[] { ProductId });
            return true;
        }
        catch (LicenseRules.ValidationError error)
        {
            if (error.Kind == LicenseRules.ValidationErrorKind.LegacyLicense) MarkLegacy(trimmed);
            ActivationError = LicenseText.T(LicenseText.ErrorKey(error.Kind), LicenseText.Lang(CultureInfo.CurrentUICulture));
            _log("license.activationRejected", new() { ["reason"] = LicenseRules.Reason(error.Kind) });
            Changed?.Invoke();
            return false;
        }
    }

    public void Deactivate()
    {
        _licensedLocally = false;
        LicenseExpiresAt = 0;
        if (File.Exists(ActivationFilePath)) File.Delete(ActivationFilePath);
        Changed?.Invoke();
    }

    private void LoadSavedLicense()
    {
        if (!File.Exists(ActivationFilePath)) return;
        var code = SafeRead(ActivationFilePath) ?? "";
        try
        {
            var payload = Validate(code);
            _licensedLocally = true;
            LicenseExpiresAt = payload.ExpiresAt;
        }
        catch (LicenseRules.ValidationError e) when (e.Kind == LicenseRules.ValidationErrorKind.LegacyLicense)
        {
            MigrateLegacyFile(code);
        }
        catch (LicenseRules.ValidationError) { /* cod generația 2 expirat / alt calculator: fără acces; fișierul rămâne */ }
    }

    /// Mută codul generația 1 într-o copie (nu îl șterge) și păstrează doar forma mascată.
    private void MigrateLegacyFile(string code)
    {
        MarkLegacy(code);
        try
        {
            if (File.Exists(LegacyBackupPath)) File.Delete(LegacyBackupPath);
            File.Move(ActivationFilePath, LegacyBackupPath);
            // Profilul utilizatorului (%LOCALAPPDATA%) are deja acces restrâns la utilizatorul curent.
            File.SetAttributes(LegacyBackupPath, FileAttributes.Hidden);
        }
        catch { _log("license.legacyBackupFailed", new()); }
        _log("license.legacyDetected", new() { ["action"] = "backup" });
    }

    private void MarkLegacy(string code)
    {
        try { Directory.CreateDirectory(_dir); File.WriteAllText(LegacyMarkerPath, LicenseRules.Mask(code)); } catch { }
    }

    private static string? SafeRead(string path) { try { return File.ReadAllText(path).Trim(); } catch { return null; } }
}
