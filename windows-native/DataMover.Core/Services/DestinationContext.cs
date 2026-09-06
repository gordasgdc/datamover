using System.Text;
using DataMover.Core.Models;

namespace DataMover.Core.Services;

/// <summary>
/// [M1 FAZA 2, 2026-09-06] Port 1:1 al DestinationContext.swift (Mac) —
/// vezi acolo pentru comentariul complet de arhitectura. Inlocuieste
/// `DestinationJob`: pastreaza DOAR starea/bookkeeping-ul per destinatie
/// (CSV, MHL, checkpoint, contoare, coada de reincercare, rapoarte), FARA
/// propria bucla de copiere - bucla muta in `OffloadRunner.Start()`, care
/// acum itereaza fisierele O SINGURA DATA si le distribuie prin
/// `FanOutCopier` catre toate destinatiile deodata.
/// </summary>
public sealed class DestinationContext
{
    public string DestRoot { get; }
    public string FolderName { get; }
    public VerificationModel Model { get; }
    public bool GenerateMhl { get; }
    public ProductionMeta Meta { get; }
    public string? SourceRoot { get; }
    public CloudUploadQueue? CloudUploadQueue { get; }
    public string AppVersion { get; }
    public Action<string> OnActivity { get; }
    public Action<string> OnPermissionError { get; }

    public string TargetRoot { get; }
    public bool Cancelled { get; private set; }
    public int OkCount { get; private set; }
    public int SkipCount { get; private set; }
    public int FailCount { get; private set; }
    public int RecoveredCount { get; private set; }
    /// Fisierele esuate (EROARE/NEPOTRIVIRE) la prima trecere - reincercate
    /// la finalul transferului. Fiecare destinatie poate avea un set
    /// DIFERIT de fisiere esuate.
    public HashSet<string> FailedRelPaths { get; } = new();

    private readonly DateTime _startedAt;
    private HashSet<string> _alreadyDone = new();
    private readonly Dictionary<string, string> _filesStatus = new();
    private int _filesSinceCheckpoint;
    private DateTime _lastCheckpointTime = DateTime.MinValue;
    private const int PdfSampleLimit = 500;
    private readonly List<ReportRow> _sampleRows = new();
    private StreamWriter? _csvWriter;
    private string? _csvPath;
    private MhlWriter? _mhl;
    private string? _mhlPath;

    public DestinationContext(string destRoot, string folderName, VerificationModel model,
        bool generateMhl, ProductionMeta meta, string? sourceRoot, CloudUploadQueue? cloudUploadQueue,
        DateTime startedAt, string appVersion, Action<string> onActivity, Action<string> onPermissionError)
    {
        DestRoot = destRoot;
        FolderName = folderName;
        Model = model;
        GenerateMhl = generateMhl;
        Meta = meta;
        SourceRoot = sourceRoot;
        CloudUploadQueue = cloudUploadQueue;
        AppVersion = appVersion;
        OnActivity = onActivity;
        OnPermissionError = onPermissionError;
        _startedAt = startedAt;
        TargetRoot = Path.Combine(destRoot, folderName);
    }

    public string DestPath(FileEntry entry) => Path.Combine(TargetRoot, entry.RelPath);

    public void Prepare(bool resume)
    {
        Directory.CreateDirectory(TargetRoot);
        OpenCsv();
        if (GenerateMhl)
        {
            if (MhlWriter.IsSupported(Model))
            {
                _mhlPath = Path.Combine(TargetRoot, $"{FolderName}_{_startedAt:yyyy-MM-dd_HH-mm-ss}.mhl");
                _mhl = MhlWriter.TryCreate(_mhlPath, Model, $"DataMover {AppVersion}", _startedAt);
            }
            else
            {
                OnActivity($"MHL: nu se poate genera cu {Model.Label()} — standardul MHL acceptă doar xxHash64, MD5 sau SHA-1.");
            }
        }
        if (resume)
        {
            var saved = CheckpointStore.Load(TargetRoot);
            if (saved != null)
            {
                foreach (var kv in saved) _filesStatus[kv.Key] = kv.Value;
                var done = new HashSet<string>();
                foreach (var kv in saved)
                    if (kv.Value is "ok" or "sarit") done.Add(kv.Key);
                _alreadyDone = done;
            }
        }
    }

    public enum Classification { AlreadyDone, ExistingSameSize, NeedsCopy }

    public Classification Classify(FileEntry entry, bool allowSkipExisting)
    {
        if (_alreadyDone.Contains(entry.RelPath)) return Classification.AlreadyDone;
        if (!allowSkipExisting) return Classification.NeedsCopy;
        var path = DestPath(entry);
        if (!File.Exists(path)) return Classification.NeedsCopy;
        long size;
        try { size = new FileInfo(path).Length; } catch { return Classification.NeedsCopy; }
        return size == entry.Size ? Classification.ExistingSameSize : Classification.NeedsCopy;
    }

    public void RecordSkippedViaCheckpoint(FileEntry entry)
    {
        SkipCount++;
        MaybeCheckpoint();
    }

    public void RecordVerifiedExisting(FileEntry entry, string srcHash, string dstHash)
    {
        SkipCount++;
        _filesStatus[entry.RelPath] = "sarit";
        LogRow(new ReportRow { File = entry.RelPath, SizeBytes = entry.Size, SrcHash = srcHash, DstHash = dstHash, Status = "SARIT", DestPath = DestPath(entry) });
        RecordInMhl(entry, srcHash);
        CloudUploadQueue?.Enqueue(entry.RelPath);
        MaybeCheckpoint();
    }

    public void RecordCopyOutcome(FileEntry entry, string sourceHash, FanOutDestResult outcome, bool isRetry)
    {
        if (outcome.Success)
        {
            var hash = outcome.Hash ?? "";
            bool same = hash == sourceHash;
            var status = same ? (isRetry ? "OK (reîncercat)" : "OK") : (isRetry ? "NEPOTRIVIRE (reîncercat)" : "NEPOTRIVIRE");
            if (same)
            {
                if (isRetry) { FailCount--; RecoveredCount++; OnActivity($"Recuperat la reîncercare: {entry.RelPath}"); }
                OkCount++;
                _filesStatus[entry.RelPath] = "ok";
                RecordInMhl(entry, sourceHash);
                CloudUploadQueue?.Enqueue(entry.RelPath);
            }
            else
            {
                if (!isRetry) { FailCount++; FailedRelPaths.Add(entry.RelPath); }
                else OnActivity($"Eșuat și la reîncercare: {entry.RelPath}");
                _filesStatus[entry.RelPath] = "fail";
            }
            LogRow(new ReportRow { File = entry.RelPath, SizeBytes = entry.Size, SrcHash = sourceHash, DstHash = hash, Status = status, DestPath = DestPath(entry) });
        }
        else
        {
            if (!isRetry) { FailCount++; FailedRelPaths.Add(entry.RelPath); }
            else OnActivity($"Eșuat și la reîncercare: {entry.RelPath}");
            _filesStatus[entry.RelPath] = "fail";
            var status = isRetry ? "EROARE (reîncercat)" : "EROARE";
            var error = outcome.Error?.Message ?? "eroare necunoscuta";
            LogRow(new ReportRow { File = entry.RelPath, SizeBytes = entry.Size, SrcHash = sourceHash, DstHash = "", Status = status, Error = error, DestPath = DestPath(entry) });
            if (outcome.Error != null && IsPermissionError(outcome.Error)) OnPermissionError(DestPath(entry));
        }
        if (!isRetry) MaybeCheckpoint();
    }

    public void RecordSourceReadFailure(FileEntry entry, Exception error, bool isRetry)
    {
        if (!isRetry) { FailCount++; FailedRelPaths.Add(entry.RelPath); }
        _filesStatus[entry.RelPath] = "fail";
        LogRow(new ReportRow { File = entry.RelPath, SizeBytes = entry.Size, SrcHash = "", DstHash = "", Status = isRetry ? "EROARE (reîncercat)" : "EROARE", Error = error.Message, DestPath = DestPath(entry) });
        if (!isRetry) MaybeCheckpoint();
    }

    public void PrepareForRetry(FileEntry entry)
    {
        try { var p = DestPath(entry); if (File.Exists(p)) File.Delete(p); } catch { /* ignora */ }
    }

    private static bool IsPermissionError(Exception ex) =>
        ex is UnauthorizedAccessException || ex.HResult == unchecked((int)0x80070005);

    private void RecordInMhl(FileEntry entry, string hash)
    {
        if (_mhl == null || string.IsNullOrEmpty(hash)) return;
        DateTime? modified = null;
        try { modified = new FileInfo(entry.FullPath).LastWriteTime; } catch { /* ignora */ }
        _mhl.Add(entry.RelPath, entry.Size, modified, hash, DateTime.Now);
    }

    public void MaybeCheckpoint(bool force = false)
    {
        _filesSinceCheckpoint++;
        var now = DateTime.UtcNow;
        bool dueByCount = _filesSinceCheckpoint >= 10;
        bool dueByTime = (now - _lastCheckpointTime).TotalSeconds >= 5.0;
        if (!(force || dueByCount || dueByTime)) return;
        CheckpointStore.Save(TargetRoot, SourceRoot, FolderName, Model.Key(), _filesStatus, force && !Cancelled, _filesStatus.Count);
        _filesSinceCheckpoint = 0;
        _lastCheckpointTime = now;
    }

    public void MarkCancelled() => Cancelled = true;

    private void OpenCsv()
    {
        var timestamp = DateTime.Now.ToString("yyyy-MM-dd_HH-mm-ss");
        var path = Path.Combine(TargetRoot, $"offload_report_{timestamp}.csv");
        try
        {
            _csvWriter = new StreamWriter(path, append: false, Encoding.UTF8);
            _csvWriter.WriteLine("fisier,marime_bytes,verificare_sursa,verificare_destinatie,status,eroare");
            _csvPath = path;
        }
        catch { _csvWriter = null; }
    }

    private void LogRow(ReportRow row)
    {
        if (_csvWriter != null)
        {
            try
            {
                string[] fields = { row.File, row.SizeBytes.ToString(), row.SrcHash, row.DstHash, row.Status, row.Error };
                _csvWriter.WriteLine(string.Join(",", fields.Select(CsvEscape)));
            }
            catch { /* un rand pierdut nu opreste transferul */ }
        }
        bool isProblem = row.Status.StartsWith("EROARE") || row.Status.StartsWith("NEPOTRIVIRE");
        if (isProblem || _sampleRows.Count < PdfSampleLimit) _sampleRows.Add(row);
    }

    private static string CsvEscape(string field) =>
        field.Contains(',') || field.Contains('"') || field.Contains('\n')
            ? "\"" + field.Replace("\"", "\"\"") + "\""
            : field;

    public DestinationResult Finalize(int totalFilesForThisDest)
    {
        if (CloudUploadQueue != null)
        {
            OnActivity("Cloud: se așteaptă finalizarea urcărilor rămase…");
            CloudUploadQueue.WaitUntilDrained();
        }
        MaybeCheckpoint(force: true);
        _mhlPath = _mhl?.Close(DateTime.Now);
        if (_mhlPath != null)
            OnActivity($"MHL scris: {Path.GetFileName(_mhlPath)} ({_mhl?.EntryCount ?? 0} fișiere certificate)");

        try { _csvWriter?.Flush(); _csvWriter?.Dispose(); } catch { /* ignora */ }
        _csvWriter = null;

        string? htmlPath = null;
        try
        {
            string? truncatedNote = totalFilesForThisDest > _sampleRows.Count
                ? $"Lista completă ({totalFilesForThisDest} fișiere) e în CSV-ul alăturat — raportul arată toate problemele plus un eșantion."
                : null;
            var path = Path.Combine(TargetRoot, $"offload_report_{DateTime.Now:yyyy-MM-dd_HH-mm-ss}.html");
            if (HtmlReport.Write(path, DestRoot, FolderName, _sampleRows, Meta, _startedAt, DateTime.Now,
                    OkCount, SkipCount, FailCount, RecoveredCount, Cancelled, Model.Label(),
                    _mhlPath, truncatedNote, AppVersion))
                htmlPath = path;
            else
                OnActivity("Nu s-a putut genera raportul HTML.");
        }
        catch (Exception ex)
        {
            OnActivity($"Nu s-a putut genera raportul HTML: {ex.Message}");
        }

        string? pdfPath = null;
        try
        {
            string? truncatedNote = totalFilesForThisDest > _sampleRows.Count
                ? $"Esantion plafonat: {_sampleRows.Count} din {totalFilesForThisDest} fisiere afisate mai jos (toate erorile/nepotrivirile sunt incluse). Lista completa e in CSV-ul de langa acest raport."
                : null;
            pdfPath = PdfReport.Generate(
                TargetRoot, DestRoot, FolderName, _sampleRows, _startedAt, DateTime.Now,
                OkCount, SkipCount, FailCount, Cancelled, Model.Label(), truncatedNote,
                Meta, RecoveredCount, _mhlPath);
        }
        catch (Exception ex)
        {
            OnActivity($"Nu s-a putut genera raportul PDF: {ex.Message}");
            try
            {
                var errPath = Path.Combine(TargetRoot, "offload_report_PDF_EROARE.txt");
                File.WriteAllText(errPath,
                    $"Generarea raportului PDF a esuat la {DateTime.Now:yyyy-MM-dd HH:mm:ss}.\n\n" +
                    $"Tip exceptie: {ex.GetType().FullName}\nMesaj: {ex.Message}\n\nStack trace:\n{ex}");
            }
            catch { /* nici asta nu trebuie sa opreasca transferul */ }
        }

        return new DestinationResult
        {
            DestRoot = DestRoot, OkCount = OkCount, SkipCount = SkipCount,
            FailCount = FailCount, Cancelled = Cancelled, CsvPath = _csvPath, PdfPath = pdfPath,
            HtmlPath = htmlPath, MhlPath = _mhlPath, RecoveredCount = RecoveredCount,
        };
    }
}
