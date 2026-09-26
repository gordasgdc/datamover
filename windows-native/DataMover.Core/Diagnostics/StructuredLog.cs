using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace DataMover.Core.Diagnostics;

public enum LogLevel { Trace = 0, Debug, Info, Warning, Error, Critical }

public sealed class LogRecord
{
    [JsonPropertyName("ts")] public string Ts { get; set; } = "";
    [JsonPropertyName("level")] public string Level { get; set; } = "";
    [JsonPropertyName("component")] public string Component { get; set; } = "";
    [JsonPropertyName("event")] public string Event { get; set; } = "";
    [JsonPropertyName("app")] public string App { get; set; } = "";
    [JsonPropertyName("build")] public string Build { get; set; } = "";
    [JsonPropertyName("platform")] public string Platform { get; set; } = "";
    [JsonPropertyName("session")] public string Session { get; set; } = "";
    [JsonPropertyName("job")] public string? Job { get; set; }
    [JsonPropertyName("dest")] public string? Dest { get; set; }
    [JsonPropertyName("msg")] public string Msg { get; set; } = "";
    [JsonPropertyName("fields")] public Dictionary<string, string>? Fields { get; set; }
    [JsonPropertyName("errorType")] public string? ErrorType { get; set; }
    [JsonPropertyName("hresult")] public int? HResult { get; set; }
}

/// <summary>
/// Jurnal structurat local (OBSERVABILITY_STANDARD), paritate cu
/// `StructuredLog.swift`: o linie JSON per eveniment, UTC cu milisecunde,
/// sesiune/job/destinatie, redactare la scriere, rotatie + retentie.
/// Scrierea nu arunca niciodata si nu schimba verdictul operatiei principale.
/// Locatie implicita: %LOCALAPPDATA%\GDC\DataMover\Logs\datamover.jsonl.
/// </summary>
public sealed class StructuredLog
{
    public sealed record Config(string Directory, string FileName = "datamover.jsonl",
        long MaxBytes = 5 * 1024 * 1024, int MaxFiles = 5, int MaxAgeDays = 14);

    public static StructuredLog Shared { get; set; } = new(new Config(DefaultDirectory));

    public static string DefaultDirectory => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "GDC", "DataMover", "Logs");

    public Config Settings { get; }
    public string SessionId { get; }
    public string? LastWriteError { get; private set; }
    public LogLevel MinimumLevel => _debugUntilRestart ? LogLevel.Debug : LogLevel.Info;
    public string AppVersion { get; set; } = "dev";
    public string Build { get; set; } = "dev";

    private bool _debugUntilRestart;
    private readonly object _lock = new();
    private readonly Func<DateTime> _utcNow;
    private static readonly JsonSerializerOptions Json = new()
    {
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
    };

    public StructuredLog(Config config, string? sessionId = null, Func<DateTime>? utcNow = null)
    {
        Settings = config;
        SessionId = sessionId ?? NewId();
        _utcNow = utcNow ?? (() => DateTime.UtcNow);
    }

    public static string NewId() => Guid.NewGuid().ToString("N")[..8];
    public string FilePath => Path.Combine(Settings.Directory, Settings.FileName);
    private string Rotated(int i) => FilePath + "." + i;

    public void SetDebugUntilRestart(bool on)
    {
        _debugUntilRestart = on;
        Log(LogLevel.Info, "diagnostics", on ? "diagnostics.debug.enabled" : "diagnostics.debug.disabled", "Jurnal detaliat " + (on ? "activat" : "dezactivat"));
    }

    public void Log(LogLevel level, string component, string evt, string message, string? job = null, string? dest = null,
        IDictionary<string, string>? fields = null, Exception? error = null)
    {
        if (level < MinimumLevel) return;
        try
        {
            var f = fields == null ? null : Redactor.RedactFields(fields);
            if (error != null)
            {
                f ??= new();
                if (!f.ContainsKey("error")) f["error"] = Redactor.RedactSecrets(error.Message);
            }
            var rec = new LogRecord
            {
                Ts = _utcNow().ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'"), Level = level.ToString().ToLowerInvariant(),
                Component = component, Event = evt, App = AppVersion, Build = Build,
                Platform = $"{RuntimeInformation.OSDescription.Trim()} {RuntimeInformation.OSArchitecture}".Trim(),
                Session = SessionId, Job = job, Dest = dest, Msg = Redactor.RedactSecrets(message), Fields = f,
                ErrorType = error?.GetType().Name, HResult = error?.HResult,
            };
            var line = JsonSerializer.Serialize(rec, Json) + "\n";
            lock (_lock)
            {
                Directory.CreateDirectory(Settings.Directory);
                RotateIfNeeded(System.Text.Encoding.UTF8.GetByteCount(line));
                File.AppendAllText(FilePath, line);
                LastWriteError = null;
            }
        }
        catch (Exception ex)
        {
            LastWriteError = ex.Message; // fallback sigur: operatia principala nu afla nimic
        }
    }

    private void RotateIfNeeded(long incoming)
    {
        var size = File.Exists(FilePath) ? new FileInfo(FilePath).Length : 0;
        if (size > 0 && size + incoming > Settings.MaxBytes)
        {
            TryDelete(Rotated(Settings.MaxFiles - 1));
            for (int i = Settings.MaxFiles - 2; i >= 1; i--)
                if (File.Exists(Rotated(i))) File.Move(Rotated(i), Rotated(i + 1), overwrite: true);
            File.Move(FilePath, Rotated(1), overwrite: true);
        }
        var cutoff = _utcNow().AddDays(-Settings.MaxAgeDays);
        for (int i = 1; i < Math.Max(Settings.MaxFiles, 2); i++)
            if (File.Exists(Rotated(i)) && File.GetLastWriteTimeUtc(Rotated(i)) < cutoff) TryDelete(Rotated(i));
    }

    private static void TryDelete(string p) { try { if (File.Exists(p)) File.Delete(p); } catch { } }

    public IReadOnlyList<string> LogFiles() =>
        new[] { FilePath }.Concat(Enumerable.Range(1, Math.Max(Settings.MaxFiles, 2) - 1).Select(Rotated)).Where(File.Exists).ToList();
}
