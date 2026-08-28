using System.ComponentModel;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Runtime.CompilerServices;
using System.Text.Json;

namespace DataMover.Core.Services;

/// Verifica update.json (acelasi fisier folosit de Mac/Python, NU un API
/// GitHub separat - vezi core/update_config.py) si compara versiunea
/// instalata cu cea publicata. Port pentru clientul Windows WPF nou
/// (2026-08-28, cerut de Cristi - lipsea complet).
///
/// IMPORTANT: campul JSON "windows" din update.json arata inca spre
/// arhiva clientului VECHI (Python/PyInstaller) - `DataMover-Windows.zip`.
/// Acest client citeste un camp NOU, optional, "windows_wpf" (arhiva cu
/// exe-ul WPF) - daca lipseste (cazul de-acum, pana la primul release
/// real al acestui client), verificarea de versiune tot functioneaza,
/// dar butonul de update arata un mesaj explicit in loc sa descarce
/// arhiva GRESITA (clientul Python vechi peste clientul WPF nou).
public sealed class UpdateChecker : INotifyPropertyChanged
{
    public static readonly UpdateChecker Shared = new();

    private static readonly Uri UpdateJsonUrl = new("https://gordasgdc.github.io/datamover/update.json");
    private const string DismissedVersionKey = "datamover_dismissed_update_version";

    private readonly HttpClient _http = new();

    public string? AvailableVersion { get; private set; }
    public string? Changes { get; private set; }
    public bool Mandatory { get; private set; }
    public string? WindowsWpfDownloadUrl { get; private set; }

    public event PropertyChangedEventHandler? PropertyChanged;

    public static string CurrentVersion =>
        System.Reflection.Assembly.GetEntryAssembly()?.GetName().Version?.ToString(3) ?? "0.0.0";

    public UpdateChecker()
    {
        _http.DefaultRequestHeaders.UserAgent.Add(new ProductInfoHeaderValue("DataMover", CurrentVersion));
        _http.Timeout = TimeSpan.FromSeconds(10);
    }

    public async Task CheckAsync()
    {
        try
        {
            using var response = await _http.GetAsync(UpdateJsonUrl);
            if (!response.IsSuccessStatusCode) return;
            var data = await response.Content.ReadAsByteArrayAsync();
            using var doc = JsonDocument.Parse(data);
            var root = doc.RootElement;
            var latest = root.GetProperty("version").GetString();
            if (string.IsNullOrEmpty(latest) || !IsNewer(latest, CurrentVersion))
            {
                AvailableVersion = null;
                Raise(nameof(AvailableVersion));
                return;
            }

            AvailableVersion = latest;
            Changes = root.TryGetProperty("changes", out var c) ? c.GetString() : null;
            Mandatory = root.TryGetProperty("mandatory", out var m) && m.GetBoolean();
            if (root.TryGetProperty("download_url", out var downloadUrls) &&
                downloadUrls.TryGetProperty("windows_wpf", out var wpfUrl))
            {
                WindowsWpfDownloadUrl = wpfUrl.GetString();
            }
            else
            {
                WindowsWpfDownloadUrl = null;
            }
            Raise(nameof(AvailableVersion));
        }
        catch { /* fara conexiune - verificarea urmatoare o va reincerca */ }
    }

    public bool WasDismissed(string version) => ReadDismissedVersion() == version;

    public void Dismiss()
    {
        if (AvailableVersion is null) return;
        WriteDismissedVersion(AvailableVersion);
        AvailableVersion = null;
        Raise(nameof(AvailableVersion));
    }

    private static string DismissedVersionFilePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "DataMover", "dismissed-update-version.txt");

    private static string? ReadDismissedVersion()
    {
        try { return File.Exists(DismissedVersionFilePath) ? File.ReadAllText(DismissedVersionFilePath).Trim() : null; }
        catch { return null; }
    }

    private static void WriteDismissedVersion(string version)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(DismissedVersionFilePath)!);
            File.WriteAllText(DismissedVersionFilePath, version);
        }
        catch { }
    }

    private static bool IsNewer(string a, string b)
    {
        var partsA = a.Split('.').Select(s => int.TryParse(s, out var n) ? n : 0).ToArray();
        var partsB = b.Split('.').Select(s => int.TryParse(s, out var n) ? n : 0).ToArray();
        var len = Math.Max(partsA.Length, partsB.Length);
        for (var i = 0; i < len; i++)
        {
            var x = i < partsA.Length ? partsA[i] : 0;
            var y = i < partsB.Length ? partsB[i] : 0;
            if (x != y) return x > y;
        }
        return false;
    }

    private void Raise([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
