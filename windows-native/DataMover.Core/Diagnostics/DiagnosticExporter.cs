using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text.Json;

namespace DataMover.Core.Diagnostics;

/// <summary>
/// „Exporta diagnosticul” — ZIP local, inspectabil, nimic trimis automat.
/// Contine NUMAI: jurnalele (re-redactate; cai anonimizate implicit),
/// manifest.json, system.json, settings.json (lista alba primita de la
/// client), last-job.json. Nu citeste alte fisiere (fara media, licente).
/// </summary>
public sealed class DiagnosticExporter
{
    private readonly StructuredLog _log;
    private readonly IDictionary<string, string> _safeSettings;
    private readonly IDictionary<string, string>? _lastJob;

    public DiagnosticExporter(StructuredLog log, IDictionary<string, string> safeSettings, IDictionary<string, string>? lastJob = null)
    {
        _log = log; _safeSettings = safeSettings; _lastJob = lastJob;
    }

    public static string DefaultFolder => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "GDC", "DataMover", "Logs", "Exports");

    public string Export(string folder, bool includePaths = false)
    {
        var stamp = DateTime.UtcNow.ToString("yyyyMMdd-HHmmss'Z'");
        var name = $"DataMover-diagnostic-{stamp}";
        var stage = Path.Combine(Path.GetTempPath(), name + "-" + Guid.NewGuid().ToString("N")[..6]);
        var root = Path.Combine(stage, name);
        Directory.CreateDirectory(Path.Combine(root, "logs"));
        try
        {
            string Clean(string s) { var r = Redactor.RedactSecrets(s); return includePaths ? r : Redactor.AnonymizePaths(r); }
            var written = new List<string>();
            void Write(string rel, string text) { var p = Path.Combine(root, rel); File.WriteAllText(p, text); written.Add(p); }
            var opts = new JsonSerializerOptions { WriteIndented = true, Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping };

            foreach (var f in _log.LogFiles())
            {
                string text;
                try { using var fs = new FileStream(f, FileMode.Open, FileAccess.Read, FileShare.ReadWrite); using var sr = new StreamReader(fs); text = sr.ReadToEnd(); }
                catch { continue; }
                Write(Path.Combine("logs", Path.GetFileName(f)), Clean(text));
            }
            Write("system.json", JsonSerializer.Serialize(new Dictionary<string, string>
            {
                ["os"] = RuntimeInformation.OSDescription, ["arch"] = RuntimeInformation.OSArchitecture.ToString(),
                ["process"] = RuntimeInformation.ProcessArchitecture.ToString(), ["runtime"] = RuntimeInformation.FrameworkDescription,
                ["locale"] = System.Globalization.CultureInfo.CurrentCulture.Name, ["cpuCount"] = Environment.ProcessorCount.ToString(),
                ["logWriteError"] = _log.LastWriteError ?? "",
            }, opts));
            Write("settings.json", JsonSerializer.Serialize(Redactor.RedactFields(_safeSettings), opts));
            if (_lastJob != null)
            {
                var job = _lastJob.ToDictionary(kv => kv.Key, kv => includePaths ? kv.Value : Redactor.AnonymizePaths(kv.Value));
                Write("last-job.json", JsonSerializer.Serialize(Redactor.RedactFields(job), opts));
            }
            var manifest = new
            {
                format = "datamover-diagnostic/1", created = stamp, app = _log.AppVersion, build = _log.Build,
                session = _log.SessionId, pathsIncluded = includePaths, redaction = includePaths ? "secrets" : "secrets+paths",
                files = written.Select(p => new
                {
                    name = Path.GetRelativePath(root, p).Replace('\\', '/'), bytes = new FileInfo(p).Length,
                    sha256 = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(p))).ToLowerInvariant(),
                }).ToList(),
            };
            File.WriteAllText(Path.Combine(root, "manifest.json"), JsonSerializer.Serialize(manifest, opts));
            Directory.CreateDirectory(folder);
            var zip = Path.Combine(folder, name + ".zip");
            if (File.Exists(zip)) File.Delete(zip);
            ZipFile.CreateFromDirectory(root, zip, CompressionLevel.Optimal, includeBaseDirectory: true);
            _log.Log(LogLevel.Info, "diagnostics", "diagnostics.exported", "Pachet de diagnostic creat",
                fields: new Dictionary<string, string> { ["files"] = (written.Count + 1).ToString(), ["paths"] = includePaths ? "included" : "anonymized" });
            return zip;
        }
        finally { try { Directory.Delete(stage, true); } catch { } }
    }
}
