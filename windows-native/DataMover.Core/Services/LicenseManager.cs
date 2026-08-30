namespace DataMover.Core.Services;

/// Port C# al LicenseManager.swift (DataMover Mac, productID
/// "gdc-datamover") - proba de 15 zile, apoi activare prin cod generat
/// manual din Furnizor, acelasi flux WhatsApp ca restul ecosistemului.
/// DECIZIE DE PRODUS (identica cu Mac): NU exista niciun gating dur
/// pe Start - `IsUnlocked` e expus doar pentru afisare (bara de proba),
/// la fel cum Mac nu blocheaza nimic dupa expirare momentan.
public sealed class LicenseManager
{
    public static readonly LicenseManager Shared = new();
    public const string ProductId = "gdc-datamover";
    // 7, NU 15 - trebuie sa fie IDENTIC cu LicenseManager.swift (Mac),
    // acelasi ProductId inseamna acelasi produs/aceleasi coduri de
    // activare emise. Gresit copiat initial dupa Regula 3 (implicitul
    // ecosistemului), dar DataMover Mac foloseste explicit 7 zile -
    // gasit la audit 2026-08-28, dupa observatia lui Cristi despre profil.
    public const int TrialDurationDays = 7;
    /// Plafon de marime per transfer in versiunea neactivata (2026-08-30,
    /// port 1:1 al LicenseManager.swift - Mac). Gating STRICT pe
    /// `IsLicensed`, nu pe `IsTrialActive` - un plafon legat doar de
    /// zilele de proba ar fi ocolit exact de abuzul semnalat (dezinstalare
    /// -> reinstalare -> proba noua); legat de `IsLicensed`, plafonul
    /// ramane activ indiferent cate ori se reseteaza fereastra de 7 zile.
    public const long TrialMaxTransferBytes = 2L * 1024 * 1024 * 1024; // 2 GB

    public bool IsLicensed { get; private set; }
    public long LicenseExpiresAt { get; private set; }
    public bool LicenseMachineLocked { get; private set; }
    public string? ActivationError { get; private set; }

    public event Action? Changed;

    private static string TrialStartFilePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "DataMover", "trial-start.txt");

    private static string ActivationFilePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "DataMover", "license.txt");

    private DateTimeOffset _trialStart;

    private LicenseManager()
    {
        EnsureTrialStarted();
        LoadSavedLicense();
    }

    private void EnsureTrialStarted()
    {
        var path = TrialStartFilePath;
        if (File.Exists(path) && long.TryParse(File.ReadAllText(path).Trim(), out var unixSeconds))
        {
            _trialStart = DateTimeOffset.FromUnixTimeSeconds(unixSeconds);
            return;
        }
        _trialStart = DateTimeOffset.Now;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, _trialStart.ToUnixTimeSeconds().ToString());
    }

    public string? SavedLicenseCode
    {
        get
        {
            var path = ActivationFilePath;
            return File.Exists(path) ? File.ReadAllText(path).Trim() : null;
        }
    }

    public int TrialDaysRemaining
    {
        get
        {
            var elapsed = DateTimeOffset.Now - _trialStart;
            var remaining = TimeSpan.FromDays(TrialDurationDays) - elapsed;
            return Math.Max(0, (int)Math.Ceiling(remaining.TotalDays));
        }
    }

    public bool IsTrialActive => TrialDaysRemaining > 0;
    public bool IsUnlocked => (IsLicensed && !RevocationCheck.IsRevoked(ProductId)) || IsTrialActive;

    public Task RefreshRevocationAsync() => RevocationCheck.RefreshAsync(new[] { ProductId });

    public bool Activate(string code)
    {
        ActivationError = null;
        var trimmed = code.Trim();
        try
        {
            var payload = LicenseCore.Validate(trimmed, ProductId);
            SaveLicense(trimmed);
            ApplyLicense(payload.ExpiresAt, payload.MachineLocked);
            Changed?.Invoke();
            _ = RevocationCheck.RefreshAsync(new[] { ProductId });
            return true;
        }
        catch (LicenseCore.ValidationError error)
        {
            ActivationError = MessageFor(error.Kind);
            Changed?.Invoke();
            return false;
        }
    }

    public void Deactivate()
    {
        IsLicensed = false;
        LicenseExpiresAt = 0;
        LicenseMachineLocked = false;
        var path = ActivationFilePath;
        if (File.Exists(path)) File.Delete(path);
        Changed?.Invoke();
    }

    private void LoadSavedLicense()
    {
        var path = ActivationFilePath;
        if (!File.Exists(path)) return;
        var code = File.ReadAllText(path).Trim();
        try
        {
            var payload = LicenseCore.Validate(code, ProductId);
            ApplyLicense(payload.ExpiresAt, payload.MachineLocked);
        }
        catch (LicenseCore.ValidationError) { /* cod salvat invalid/expirat - ramanem nelicentiati */ }
    }

    private void ApplyLicense(long expiresAt, bool machineLocked)
    {
        IsLicensed = true;
        LicenseExpiresAt = expiresAt;
        LicenseMachineLocked = machineLocked;
    }

    private static void SaveLicense(string code)
    {
        var path = ActivationFilePath;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, code);
    }

    private static string MessageFor(LicenseCore.ValidationErrorKind kind) => kind switch
    {
        LicenseCore.ValidationErrorKind.MalformedCode => "Cod invalid — verifică să nu lipsească vreun caracter.",
        LicenseCore.ValidationErrorKind.BadSignature => "Semnătura codului nu se potrivește.",
        LicenseCore.ValidationErrorKind.WrongProduct => "Codul e valid, dar pentru alt produs GDC.",
        LicenseCore.ValidationErrorKind.WrongMachine => "Codul e blocat pe alt calculator.",
        LicenseCore.ValidationErrorKind.Expired => "Codul a expirat.",
        _ => "Cod invalid.",
    };
}
