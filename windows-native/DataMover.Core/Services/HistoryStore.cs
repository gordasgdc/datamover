using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace DataMover.Core.Services;

public sealed class HistoryEntry
{
    public string DateText { get; set; } = "";
    public string FolderName { get; set; } = "";
    public string SourcesSummary { get; set; } = "";
    public string DestSummary { get; set; } = "";
    public int OkCount { get; set; }
    public int SkipCount { get; set; }
    public int FailCount { get; set; }
    // Cai complete - necesare pentru "Deschide sursa/destinatia" din
    // istoric. Optionale (JsonIgnoreCondition.WhenWritingNull nu e nevoie
    // aici - default "" e suficient pentru compatibilitate cu istoric
    // vechi care oricum nu exista inca pe acest client nou).
    public List<string> SourcePaths { get; set; } = new();
    public List<string> DestinationPaths { get; set; } = new();
    public List<string> DestinationTargetPaths { get; set; } = new();
}

/// Istoric persistat in %AppData%\DataMover\history.json - port 1:1 al
/// HistoryStore.swift (Mac) / ~/.datamover_history.json (Python).
public sealed class HistoryStore
{
    private static readonly Lazy<HistoryStore> _shared = new(() => new HistoryStore());
    public static HistoryStore Shared => _shared.Value;

    private readonly string _filePath;
    public List<HistoryEntry> Entries { get; private set; } = new();

    private HistoryStore()
    {
        var baseDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DataMover");
        Directory.CreateDirectory(baseDir);
        _filePath = Path.Combine(baseDir, "history.json");
        Load();
    }

    private void Load()
    {
        try
        {
            if (!File.Exists(_filePath)) return;
            var json = File.ReadAllText(_filePath);
            Entries = JsonSerializer.Deserialize<List<HistoryEntry>>(json) ?? new();
        }
        catch { Entries = new(); }
    }

    private void Save()
    {
        try { File.WriteAllText(_filePath, JsonSerializer.Serialize(Entries)); }
        catch { /* best-effort */ }
    }

    public void Record(string folderName, List<string> sources, List<string> destinations,
        int okCount, int skipCount, int failCount)
    {
        var entry = new HistoryEntry
        {
            DateText = DateTime.Now.ToString("dd.MM.yyyy HH:mm"),
            FolderName = folderName,
            SourcesSummary = string.Join(", ", sources.Select(s => Path.GetFileName(s.TrimEnd('/', '\\')))),
            DestSummary = string.Join(", ", destinations.Select(d => Path.GetFileName(d.TrimEnd('/', '\\')))),
            OkCount = okCount, SkipCount = skipCount, FailCount = failCount,
            SourcePaths = sources, DestinationPaths = destinations,
            DestinationTargetPaths = destinations.Select(d => Path.Combine(d, folderName)).ToList(),
        };
        Entries.Add(entry);
        if (Entries.Count > 200) Entries.RemoveRange(0, Entries.Count - 200);
        Save();
    }

    public void Delete(HistoryEntry entry) { Entries.Remove(entry); Save(); }
    public void ClearAll() { Entries.Clear(); Save(); }
}
