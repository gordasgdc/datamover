using System.ComponentModel;
using System.IO;
using System.Runtime.CompilerServices;
using DataMover.Core.Models;

namespace DataMover.Core.Services;

/// <summary>
/// Orchestreaza cate un DestinationJob per destinatie, in paralel, si
/// expune progresul catre WPF prin INotifyPropertyChanged - echivalentul
/// C# al OffloadRunner (Mac, @Published/ObservableObject).
/// </summary>
public sealed class OffloadRunner : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }

    private bool _isRunning;
    public bool IsRunning { get => _isRunning; private set => Set(ref _isRunning, value); }

    private int _progressPercent;
    public int ProgressPercent { get => _progressPercent; private set => Set(ref _progressPercent, value); }

    private int _filesDone;
    public int FilesDone { get => _filesDone; private set => Set(ref _filesDone, value); }

    private int _totalUnits;
    public int TotalUnits { get => _totalUnits; private set => Set(ref _totalUnits, value); }

    private string _statusText = "Gata de pornire";
    public string StatusText { get => _statusText; private set => Set(ref _statusText, value); }

    private string _speedText = "";
    public string SpeedText { get => _speedText; private set => Set(ref _speedText, value); }

    private bool _isPaused;
    public bool IsPaused { get => _isPaused; private set => Set(ref _isPaused, value); }

    private string _bufferAllocatedText = "";
    public string BufferAllocatedText { get => _bufferAllocatedText; private set => Set(ref _bufferAllocatedText, value); }

    private string _memoryUsedText = "";
    public string MemoryUsedText { get => _memoryUsedText; private set => Set(ref _memoryUsedText, value); }

    public List<DestinationResult> LastResults { get; private set; } = new();

    /// Feed-ul de activitate, plafonat la 200 linii (Regula 21 - nu tinem
    /// tot istoricul unui transfer de mii de fisiere in memorie/UI).
    public event Action<string>? ActivityLogged;
    private readonly List<string> _activityLines = new();
    private const int ActivityLogLimit = 200;
    public IReadOnlyList<string> ActivityLines => _activityLines;

    private CancelToken _cancelToken = new();
    private PauseToken _pauseToken = new();
    private DateTime _startTime;
    private long _bytesDone;
    public List<DestinationJob> Jobs { get; private set; } = new();

    public int ChunkSizeMB { get; set; } = IOSettings.DefaultChunkSizeMB;
    public int RamLimitMB { get; set; } = 1024;

    // ---------------- Nume de folder / deduplicare (2026-08-28) ----------------
    // Fix real: numele folderului include data zilei - un transfer de ore/
    // zile intregi (ex. 4 TB) calcula un folder NOU la o repornire in alta
    // zi, iar orice verificare "existent?" facuta doar pe numele de azi ar
    // rata complet folderul vechi cu sute de GB deja copiate. Identic cu
    // OffloadRunner (Mac, OffloadEngine.swift).

    public static string FolderName(string project, string card)
    {
        var proj = string.IsNullOrWhiteSpace(project) ? "Proiect" : project.Trim();
        var crd = string.IsNullOrWhiteSpace(card) ? "Card" : card.Trim();
        return $"{DateTime.Now:yyyy-MM-dd}_{proj}_{crd}".Replace(" ", "_");
    }

    private static string SanitizedProjectCard(string project, string card)
    {
        var proj = string.IsNullOrWhiteSpace(project) ? "Proiect" : project.Trim();
        var crd = string.IsNullOrWhiteSpace(card) ? "Card" : card.Trim();
        return $"{proj}_{crd}".Replace(" ", "_");
    }

    /// Cauta un folder deja EXISTENT (creat oricand, nu neaparat azi) cu
    /// acelasi proiect/card, la oricare destinatie - alege cel mai RECENT
    /// daca gaseste mai multe (prefixul de data se sorteaza lexicografic
    /// identic cu ordinea cronologica).
    public static string? FindExistingFolderName(IEnumerable<string> destinations, string project, string card)
    {
        var suffix = "_" + SanitizedProjectCard(project, card);
        var candidates = new List<string>();
        foreach (var dest in destinations)
        {
            if (!Directory.Exists(dest)) continue;
            try
            {
                candidates.AddRange(Directory.GetDirectories(dest)
                    .Select(Path.GetFileName)
                    .Where(n => n != null && n.EndsWith(suffix))!
                    .Cast<string>());
            }
            catch { /* destinatie inaccesibila momentan - ignora */ }
        }
        candidates.Sort(StringComparer.Ordinal);
        return candidates.Count > 0 ? candidates[^1] : null;
    }

    public static bool FolderHasRealFiles(IEnumerable<string> destinations, string folderName)
    {
        foreach (var dest in destinations)
        {
            var target = Path.Combine(dest, folderName);
            if (!Directory.Exists(target)) continue;
            try
            {
                var items = Directory.GetFileSystemEntries(target);
                if (items.Any(p =>
                    {
                        var n = Path.GetFileName(p);
                        return !n.StartsWith("offload_checkpoint") && !n.StartsWith("offload_report_");
                    }))
                    return true;
            }
            catch { /* ignora */ }
        }
        return false;
    }

    public static string FreeFolderName(string baseName, IEnumerable<string> destinations)
    {
        var candidate = baseName;
        int i = 2;
        var destList = destinations.ToList();
        while (FolderHasRealFiles(destList, candidate))
        {
            candidate = $"{baseName} ({i})";
            i++;
        }
        return candidate;
    }

    public static void ClearExistingFolders(IEnumerable<string> destinations, string folderName)
    {
        foreach (var dest in destinations)
        {
            var target = Path.Combine(dest, folderName);
            if (!Directory.Exists(target)) continue;
            try
            {
                foreach (var item in Directory.GetFileSystemEntries(target))
                {
                    if (Directory.Exists(item)) Directory.Delete(item, recursive: true);
                    else File.Delete(item);
                }
            }
            catch { /* ignora */ }
        }
    }

    // ---------------- Pauza ----------------

    public void TogglePause()
    {
        if (!IsRunning) return;
        if (_pauseToken.IsPaused)
        {
            _pauseToken.Resume();
            IsPaused = false;
            StatusText = "Se copiaza...";
        }
        else
        {
            _pauseToken.Pause();
            IsPaused = true;
            StatusText = "Pauza — apasa Continua pentru a relua";
        }
    }

    public void Cancel()
    {
        if (!IsRunning) return;
        _cancelToken.Cancel();
        StatusText = "Se anuleaza...";
    }

    private void UpdateMemoryDisplay()
    {
        BufferAllocatedText = RamLimitMB == 0 ? "Fara limita" : IOSettings.SizeLabel(RamLimitMB);
        MemoryUsedText = IOSettings.SizeLabel((int)(IOSettings.CurrentProcessMemoryBytes() / 1024 / 1024));
    }

    // ---------------- Start ----------------

    public void Start(List<string> sources, List<string> destinations, VerificationModel model,
        List<string> exclusions, bool resume, string project, string card, string? folderNameOverride = null)
    {
        if (IsRunning) return;

        var files = new List<FileEntry>();
        foreach (var src in sources)
        {
            if (Directory.Exists(src))
            {
                files.AddRange(FileScanner.ListAllFiles(src, exclusions));
            }
            else if (File.Exists(src))
            {
                var name = Path.GetFileName(src);
                if (FileScanner.IsExcluded(name, exclusions)) continue;
                long size = 0;
                try { size = new FileInfo(src).Length; } catch { /* ignora */ }
                files.Add(new FileEntry(src, name, size));
            }
        }
        if (files.Count == 0)
        {
            StatusText = "Nu am gasit niciun fisier de copiat.";
            return;
        }

        var folderName = folderNameOverride ?? FolderName(project, card);
        var sourceRoot = sources.FirstOrDefault();

        _cancelToken = new CancelToken();
        _pauseToken = new PauseToken();
        IsPaused = false;
        IsRunning = true;
        _startTime = DateTime.Now;
        _bytesDone = 0;
        FilesDone = 0;
        TotalUnits = files.Count * destinations.Count;
        ProgressPercent = 0;
        StatusText = "Se copiaza...";
        SpeedText = "";
        LastResults = new();
        _activityLines.Clear();
        UpdateMemoryDisplay();

        int chunkBytes = ChunkSizeMB * 1024 * 1024;
        var token = _cancelToken;
        var pauseTok = _pauseToken;
        var results = new List<DestinationResult>();
        var resultsLock = new object();

        Jobs = destinations.Select(dest =>
        {
            var job = new DestinationJob(dest, folderName, files, token, pauseTok, model, resume, sourceRoot, chunkBytes, RamLimitMB);
            job.OnFileDone = size => Advance(size);
            job.OnActivity = line => LogActivity(line);
            return job;
        }).ToList();

        var tasks = Jobs.Select(job => Task.Run(() =>
        {
            var result = job.Run();
            lock (resultsLock) { results.Add(result); }
        })).ToArray();

        Task.WhenAll(tasks).ContinueWith(_ =>
        {
            Finish(results, folderName, sources, destinations);
        });
    }

    private void LogActivity(string line)
    {
        var withSpeed = string.IsNullOrEmpty(SpeedText) ? line : $"{line} — {SpeedText}";
        _activityLines.Add(withSpeed);
        if (_activityLines.Count > ActivityLogLimit) _activityLines.RemoveRange(0, _activityLines.Count - ActivityLogLimit);
        ActivityLogged?.Invoke(withSpeed);
    }

    private void Advance(long size)
    {
        FilesDone++;
        _bytesDone += size;
        ProgressPercent = TotalUnits > 0 ? (int)(FilesDone * 100.0 / TotalUnits) : 0;
        StatusText = $"{ProgressPercent}% ({FilesDone}/{TotalUnits} fisiere)";
        var elapsed = (DateTime.Now - _startTime).TotalSeconds;
        if (elapsed > 0) SpeedText = $"{IOSettings.SizeLabel((int)(_bytesDone / elapsed / 1024 / 1024))}/s";
        UpdateMemoryDisplay();
    }

    private void Finish(List<DestinationResult> results, string folderName, List<string> sources, List<string> destinations)
    {
        IsRunning = false;
        LastResults = results;
        bool anyCancelled = results.Any(r => r.Cancelled);
        int totalOk = results.Sum(r => r.OkCount);
        int totalSkip = results.Sum(r => r.SkipCount);
        int totalFail = results.Sum(r => r.FailCount);
        StatusText = anyCancelled
            ? "Anulat."
            : $"Finalizat — {totalOk} OK" + (totalFail > 0 ? $", {totalFail} probleme." : ".");

        HistoryStore.Shared.Record(folderName, sources, destinations, totalOk, totalSkip, totalFail);
    }
}
