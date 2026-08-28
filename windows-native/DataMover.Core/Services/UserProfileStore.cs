namespace DataMover.Core.Services;

/// Port 1:1 al UserProfileStore.cs (GDCVaultWin) - Nume/Email optionale,
/// persistate local, pentru sidebar (vezi CLAUDE.md Partea 1, Regula 12).
public sealed class UserProfileStore
{
    public static readonly UserProfileStore Shared = new();

    private const string NameKey = "datamover_profile_name";
    private const string EmailKey = "datamover_profile_email";
    private static string SettingsPath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "DataMover", "profile.txt");

    public string Name { get; private set; } = "";
    public string Email { get; private set; } = "";
    public string MachineId => MachineID.Display;

    public string DisplayName
    {
        get
        {
            var trimmed = Name.Trim();
            return string.IsNullOrEmpty(trimmed) ? "Anonim" : trimmed;
        }
    }

    private UserProfileStore() => Load();

    public void Save(string name, string email, bool sendTelemetry)
    {
        Name = name;
        Email = email;
        Persist();
        if (sendTelemetry && !string.IsNullOrWhiteSpace(name))
            AnalyticsClient.RegisterDevice(name, email);
    }

    private void Load()
    {
        try
        {
            if (!File.Exists(SettingsPath)) return;
            foreach (var line in File.ReadAllLines(SettingsPath))
            {
                var idx = line.IndexOf('=');
                if (idx < 0) continue;
                var key = line[..idx];
                var value = line[(idx + 1)..];
                if (key == NameKey) Name = value;
                else if (key == EmailKey) Email = value;
            }
        }
        catch { }
    }

    private void Persist()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(SettingsPath)!);
            File.WriteAllLines(SettingsPath, new[] { $"{NameKey}={Name}", $"{EmailKey}={Email}" });
        }
        catch { }
    }
}
