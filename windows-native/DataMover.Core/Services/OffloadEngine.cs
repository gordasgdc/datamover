using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using DataMover.Core.Models;

namespace DataMover.Core.Services;

/// <summary>
/// Port C# 1:1 al motorului de offload (Mac: OffloadEngine.swift, Windows
/// Python: core/offload_engine.py). Listare fisiere, copiere in bucati
/// (anulabila + pauzabila), verificare (MD5/SHA1/SHA256/SHA512/doar-
/// dimensiune), checkpoint/reluare, raport CSV (streaming, nu tinut in
/// RAM - vezi Regula 21 din CLAUDE.md).
/// </summary>
public enum VerificationModel
{
    /// [2026-09-03] Primul din lista pentru ca e alegerea implicita a
    /// ofloaderelor profesionale (ShotPut Pro, Silverstack): aceeasi
    /// siguranta practica la detectarea coruperii de date ca MD5, dar de
    /// cateva ori mai rapid — pe un card de sute de GB, verificarea e
    /// etapa care dureaza, nu copierea. Vezi XxHash64.cs.
    XxHash64, Md5, Sha1, Sha256, Sha512, SizeOnly
}

public static class VerificationModelExtensions
{
    public static string Label(this VerificationModel m) => m switch
    {
        VerificationModel.XxHash64 => "xxHash64 (recomandat — cel mai rapid)",
        VerificationModel.Md5 => "MD5 (rapid)",
        VerificationModel.Sha1 => "SHA-1",
        VerificationModel.Sha256 => "SHA-256",
        VerificationModel.Sha512 => "SHA-512 (maxim de siguranta)",
        VerificationModel.SizeOnly => "Doar dimensiune fisier",
        _ => m.ToString(),
    };

    public static string Key(this VerificationModel m) => m switch
    {
        VerificationModel.XxHash64 => "xxhash64",
        VerificationModel.Md5 => "md5",
        VerificationModel.Sha1 => "sha1",
        VerificationModel.Sha256 => "sha256",
        VerificationModel.Sha512 => "sha512",
        VerificationModel.SizeOnly => "marime",
        _ => "md5",
    };
}

/// Token de anulare thread-safe, partajat intre UI si toate job-urile.
public sealed class CancelToken
{
    private volatile bool _cancelled;
    public bool IsCancelled => _cancelled;
    public void Cancel() => _cancelled = true;
}

/// Token de PAUZA (reversibil, spre deosebire de CancelToken) - blocheaza
/// bucla principala INTRE fisiere, fara sa piarda progresul facut pana la
/// apasarea Pauza. Identic cu PauseToken (Mac) / pause_event (Python).
public sealed class PauseToken
{
    private volatile bool _paused;
    public bool IsPaused => _paused;
    public void Pause() => _paused = true;
    public void Resume() => _paused = false;

    public void WaitWhilePaused(CancelToken cancel)
    {
        while (IsPaused)
        {
            if (cancel.IsCancelled) return;
            Thread.Sleep(200);
        }
    }
}

public sealed class OffloadCancelledException : Exception { }

public static class FileScanner
{
    public static bool IsExcluded(string filename, IReadOnlyList<string> exclusions)
    {
        if (filename.StartsWith('.')) return true;
        var lower = filename.ToLowerInvariant();
        foreach (var raw in exclusions)
        {
            var pattern = raw.Trim().ToLowerInvariant();
            if (pattern.Length == 0) continue;
            if (pattern.StartsWith('.'))
            {
                if (lower.EndsWith(pattern)) return true;
            }
            else if (lower == pattern) return true;
        }
        return false;
    }

    /// Enumerare recursiva - pastreaza in memorie DOAR lista curenta
    /// (apelantul decide daca o materializeaza sau o consuma pe loturi;
    /// vezi Regula 21 - la volume foarte mari, apelantul ar trebui sa
    /// prefere ScanStreaming de mai jos).
    public static List<FileEntry> ListAllFiles(string root, IReadOnlyList<string> exclusions)
    {
        var results = new List<FileEntry>();
        foreach (var full in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories))
        {
            var name = Path.GetFileName(full);
            if (IsExcluded(name, exclusions)) continue;
            var rel = Path.GetRelativePath(root, full);
            long size = 0;
            try { size = new FileInfo(full).Length; } catch { /* ignora */ }
            results.Add(new FileEntry(full, rel, size));
        }
        return results;
    }
}

/// <summary>
/// Copiaza+verifica lista de fisiere data catre O SINGURA destinatie -
/// echivalentul C# al DestinationJob (Mac/Python). Ruleaza pe un
/// Task/thread de fundal, niciodata pe thread-ul UI.
/// </summary>
public sealed class DestinationJob
{
    public string DestRoot { get; }
    public string FolderName { get; }
    public IReadOnlyList<FileEntry> Files { get; }
    public CancelToken Cancel { get; }
    public PauseToken Pause { get; }
    public VerificationModel Model { get; }
    public bool Resume { get; }
    public string? SourceRoot { get; }
    public int ChunkSizeBytes { get; }
    public int RamLimitMb { get; }
    /// Destinatie secundara Cloud (2026-08-30, vezi CloudSyncService) -
    /// optionala; daca null, comportamentul e identic cu inainte.
    public CloudUploadQueue? CloudUploadQueue { get; set; }

    public Action<long>? OnFileDone { get; set; }
    public Action<string>? OnActivity { get; set; }
    /// [2026-09-03] Apelat cu calea destinatiei la prima eroare de tip
    /// "acces refuzat" (fisier/folder protejat de sistem, sau apartinand
    /// altui utilizator) - OffloadRunner arata un dialog cu optiunea de
    /// a relansa aplicatia ca Administrator, in loc sa lase userul sa
    /// vada doar "EROARE" generic in raport.
    public Action<string>? OnPermissionError { get; set; }

    public int OkCount { get; private set; }
    public int SkipCount { get; private set; }
    public int FailCount { get; private set; }
    public bool Cancelled { get; private set; }
    public string? CsvPath { get; private set; }
    public string? PdfPath { get; private set; }
    public string? HtmlPath { get; private set; }
    public string? MhlPath { get; private set; }
    public int RecoveredCount { get; private set; }

    /// [2026-09-03] Generare MHL (vezi MhlWriter.cs) — optionala, activa implicit.
    public bool GenerateMhl { get; set; } = true;
    /// [2026-09-03] Pasul automat de reincercare a fisierelor esuate.
    public bool RetryFailedFiles { get; set; } = true;
    /// [2026-09-03] Metadatele productiei, pentru antetul rapoartelor.
    public ProductionMeta Meta { get; set; } = new();
    /// Versiunea aplicatiei, scrisa in MHL si in subsolul raportului HTML.
    public string AppVersion { get; set; } = "?";

    private MhlWriter? _mhl;
    private readonly List<FileEntry> _failedEntries = new();

    private const int PdfSampleLimit = 500; // esantion plafonat pentru PDF (Regula 21) - lista completa ramane in CSV
    private readonly List<ReportRow> _sampleRows = new();
    private DateTime _startedAt;
    private readonly Dictionary<string, string> _filesStatus = new();
    private int _filesSinceCheckpoint;
    private DateTime _lastCheckpointTime = DateTime.MinValue;
    private StreamWriter? _csvWriter;

    public DestinationJob(string destRoot, string folderName, IReadOnlyList<FileEntry> files,
        CancelToken cancel, PauseToken pause, VerificationModel model, bool resume,
        string? sourceRoot, int chunkSizeBytes, int ramLimitMb)
    {
        DestRoot = destRoot;
        FolderName = folderName;
        Files = files;
        Cancel = cancel;
        Pause = pause;
        Model = model;
        Resume = resume;
        SourceRoot = sourceRoot;
        ChunkSizeBytes = chunkSizeBytes;
        RamLimitMb = ramLimitMb;
    }

    public DestinationResult Run()
    {
        _startedAt = DateTime.Now;
        var targetRoot = Path.Combine(DestRoot, FolderName);
        Directory.CreateDirectory(targetRoot);

        var alreadyDone = new HashSet<string>();
        if (Resume)
        {
            var saved = CheckpointStore.Load(targetRoot);
            if (saved != null)
            {
                foreach (var kv in saved) _filesStatus[kv.Key] = kv.Value;
                foreach (var kv in saved)
                    if (kv.Value is "ok" or "sarit") alreadyDone.Add(kv.Key);
            }
        }

        OpenCsv(targetRoot);

        // [2026-09-03] MHL (Media Hash List) — se scrie langa datele copiate,
        // in radacina folderului de destinatie. Vezi MhlWriter.
        if (GenerateMhl)
        {
            if (MhlWriter.IsSupported(Model))
            {
                var mhlPath = Path.Combine(targetRoot, $"{FolderName}_{_startedAt:yyyy-MM-dd_HH-mm-ss}.mhl");
                _mhl = MhlWriter.TryCreate(mhlPath, Model, $"DataMover {AppVersion}", _startedAt);
            }
            else
            {
                OnActivity?.Invoke($"MHL: nu se poate genera cu {Model.Label()} — standardul MHL acceptă doar xxHash64, MD5 sau SHA-1.");
            }
        }

        foreach (var entry in Files)
        {
            if (Cancel.IsCancelled) { Cancelled = true; break; }

            // Pauza (INTRE fisiere - fisierul anterior s-a terminat deja).
            if (Pause.IsPaused)
            {
                OnActivity?.Invoke("Pauza — transferul e oprit temporar de utilizator.");
                Pause.WaitWhilePaused(Cancel);
                if (Cancel.IsCancelled) { Cancelled = true; break; }
                OnActivity?.Invoke("Reluat din pauza.");
            }

            IOSettings.WaitIfOverRamLimit(RamLimitMb, Cancel, OnActivity);

            if (alreadyDone.Contains(entry.RelPath))
            {
                SkipCount++;
                OnFileDone?.Invoke(entry.Size);
                MaybeWriteCheckpoint(targetRoot);
                continue;
            }

            var destPath = Path.Combine(targetRoot, entry.RelPath);
            Directory.CreateDirectory(Path.GetDirectoryName(destPath)!);

            var outcome = ProcessOne(entry, destPath, allowSkipExisting: Resume);
            if (outcome.Cancelled) { Cancelled = true; break; }
            if (outcome.Skipped)
            {
                SkipCount++;
                _filesStatus[entry.RelPath] = "sarit";
                LogRow(new ReportRow { File = entry.RelPath, SizeBytes = entry.Size, SrcHash = outcome.SrcHash, DstHash = outcome.DstHash, Status = "SARIT" });
                RecordInMhl(entry, outcome.SrcHash);
                CloudUploadQueue?.Enqueue(entry.RelPath);
                OnFileDone?.Invoke(entry.Size);
                MaybeWriteCheckpoint(targetRoot);
                continue;
            }

            if (outcome.Status == "OK")
            {
                OkCount++;
                _filesStatus[entry.RelPath] = "ok";
            }
            else
            {
                FailCount++;
                _filesStatus[entry.RelPath] = "fail";
                // [2026-09-03] Retinut pentru pasul automat de reincercare
                // de la finalul transferului — un card cu un contact slab
                // sau un disc extern care "hiccup"-uie o data produce exact
                // acest tip de esec, care trece la a doua incercare.
                _failedEntries.Add(entry);
            }
            LogRow(new ReportRow { File = entry.RelPath, SizeBytes = entry.Size, SrcHash = outcome.SrcHash, DstHash = outcome.DstHash, Status = outcome.Status, Error = outcome.Error });
            if (outcome.Status == "OK")
            {
                RecordInMhl(entry, outcome.SrcHash);
                // Urcare Cloud: doar fisierele copiate cu succes local.
                CloudUploadQueue?.Enqueue(entry.RelPath);
            }
            OnFileDone?.Invoke(entry.Size);
            MaybeWriteCheckpoint(targetRoot);
        }

        // [2026-09-03] Pas automat de reincercare, INAINTE de rapoarte —
        // rapoartele trebuie sa reflecte starea finala, nu una intermediara.
        if (!Cancelled && RetryFailedFiles && _failedEntries.Count > 0)
            RetryFailed(targetRoot);

        // Asteapta upload-urile Cloud deja puse in coada inainte de raport.
        if (CloudUploadQueue != null)
        {
            OnActivity?.Invoke("Cloud: se așteaptă finalizarea urcărilor rămase…");
            CloudUploadQueue.WaitUntilDrained();
        }
        MaybeWriteCheckpoint(targetRoot, force: true);
        MhlPath = _mhl?.Close(DateTime.Now);
        if (MhlPath != null)
            OnActivity?.Invoke($"MHL scris: {Path.GetFileName(MhlPath)} ({_mhl?.EntryCount ?? 0} fișiere certificate)");
        CloseCsv();
        WriteHtml(targetRoot);
        WritePdf(targetRoot);

        return new DestinationResult
        {
            DestRoot = DestRoot, OkCount = OkCount, SkipCount = SkipCount,
            FailCount = FailCount, Cancelled = Cancelled, CsvPath = CsvPath, PdfPath = PdfPath,
            HtmlPath = HtmlPath, MhlPath = MhlPath, RecoveredCount = RecoveredCount,
        };
    }

    /// Rezultatul procesarii unui singur fisier — extras din bucla ca sa
    /// poata fi refolosit IDENTIC de pasul de reincercare (altfel cele doua
    /// cai ar putea diverge, iar un fisier recuperat ar fi verificat altfel
    /// decat unul copiat din prima).
    private sealed class FileOutcome
    {
        public string Status = "OK";
        public string SrcHash = "";
        public string DstHash = "";
        public string Error = "";
        public bool Cancelled;
        public bool Skipped;
    }

    private FileOutcome ProcessOne(FileEntry entry, string destPath, bool allowSkipExisting)
    {
        var outcome = new FileOutcome();
        try
        {
            // "Completeaza/Reia": daca fisierul exista deja la destinatie cu
            // ACEEASI marime, il verificam direct (fara sa-l recopiem) -
            // functioneaza si fara checkpoint.
            if (allowSkipExisting && File.Exists(destPath) && new FileInfo(destPath).Length == entry.Size)
            {
                OnActivity?.Invoke($"Verificare fisier existent: {entry.RelPath}…");
                var (same0, s0, d0) = VerifyPair(entry, destPath);
                if (same0)
                {
                    outcome.Skipped = true;
                    outcome.Status = "SARIT";
                    outcome.SrcHash = s0;
                    outcome.DstHash = d0;
                    return outcome;
                }
            }

            OnActivity?.Invoke($"Copiere: {entry.RelPath} ({FormatBytes(entry.Size)})");
            CopyFileCancelable(entry.FullPath, destPath, ChunkSizeBytes);
            OnActivity?.Invoke($"Verificare checksum: {entry.RelPath}…");
            var (same, s, d) = VerifyPair(entry, destPath);
            outcome.SrcHash = s;
            outcome.DstHash = d;
            if (!same) outcome.Status = "NEPOTRIVIRE";
        }
        catch (OffloadCancelledException)
        {
            outcome.Cancelled = true;
        }
        catch (Exception ex)
        {
            outcome.Status = "EROARE";
            outcome.Error = ex.Message;
            if (IsPermissionError(ex)) OnPermissionError?.Invoke(destPath);
        }
        return outcome;
    }

    /// [2026-09-03] A doua trecere peste fisierele care au esuat la prima.
    ///
    /// DE CE: pe platou, cauza tipica a unui esec izolat e tranzitorie — un
    /// card scos si reintrodus prost, un cablu miscat, un disc extern care
    /// intra in sleep. Un ofloader profesional reincearca automat inainte
    /// sa declare pierderea. Fisierul partial de la destinatie se STERGE
    /// inainte de recopiere (de aceea `allowSkipExisting: false`).
    private void RetryFailed(string targetRoot)
    {
        var toRetry = _failedEntries.ToList();
        _failedEntries.Clear();
        OnActivity?.Invoke($"Reîncercare automată: {toRetry.Count} fișier(e) care au eșuat la prima trecere…");
        foreach (var entry in toRetry)
        {
            if (Cancel.IsCancelled) { Cancelled = true; return; }
            if (Pause.IsPaused)
            {
                Pause.WaitWhilePaused(Cancel);
                if (Cancel.IsCancelled) { Cancelled = true; return; }
            }
            var destPath = Path.Combine(targetRoot, entry.RelPath);
            try { if (File.Exists(destPath)) File.Delete(destPath); } catch { /* ignora */ }
            var outcome = ProcessOne(entry, destPath, allowSkipExisting: false);
            if (outcome.Cancelled) { Cancelled = true; return; }
            if (outcome.Status == "OK")
            {
                FailCount--;
                OkCount++;
                RecoveredCount++;
                _filesStatus[entry.RelPath] = "ok";
                RecordInMhl(entry, outcome.SrcHash);
                CloudUploadQueue?.Enqueue(entry.RelPath);
                OnActivity?.Invoke($"Recuperat la reîncercare: {entry.RelPath}");
                LogRow(new ReportRow { File = entry.RelPath, SizeBytes = entry.Size, SrcHash = outcome.SrcHash, DstHash = outcome.DstHash, Status = "OK (reîncercat)" });
            }
            else
            {
                OnActivity?.Invoke($"Eșuat și la reîncercare: {entry.RelPath}");
                LogRow(new ReportRow { File = entry.RelPath, SizeBytes = entry.Size, SrcHash = outcome.SrcHash, DstHash = outcome.DstHash, Status = outcome.Status + " (reîncercat)", Error = outcome.Error });
            }
            MaybeWriteCheckpoint(targetRoot);
        }
    }

    /// Adauga fisierul in MHL — doar cu hash-ul SURSEI si doar dupa ce
    /// verificarea a confirmat ca destinatia are acelasi hash. Un MHL e o
    /// certificare; un fisier nesigur nu are ce cauta in el.
    private void RecordInMhl(FileEntry entry, string hash)
    {
        if (_mhl == null || string.IsNullOrEmpty(hash)) return;
        DateTime? modified = null;
        try { modified = new FileInfo(entry.FullPath).LastWriteTime; } catch { /* ignora */ }
        _mhl.Add(entry.RelPath, entry.Size, modified, hash, DateTime.Now);
    }

    private void WriteHtml(string targetRoot)
    {
        try
        {
            string? truncatedNote = Files.Count > _sampleRows.Count
                ? $"Lista completă ({Files.Count} fișiere) e în CSV-ul alăturat — raportul arată toate problemele plus un eșantion."
                : null;
            var path = Path.Combine(targetRoot, $"offload_report_{DateTime.Now:yyyy-MM-dd_HH-mm-ss}.html");
            if (HtmlReport.Write(path, DestRoot, FolderName, _sampleRows, Meta, _startedAt, DateTime.Now,
                    OkCount, SkipCount, FailCount, RecoveredCount, Cancelled, Model.Label(),
                    MhlPath, truncatedNote, AppVersion))
                HtmlPath = path;
            else
                OnActivity?.Invoke("Nu s-a putut genera raportul HTML.");
        }
        catch (Exception ex)
        {
            OnActivity?.Invoke($"Nu s-a putut genera raportul HTML: {ex.Message}");
        }
    }

    /// [2026-09-03] Detecteaza daca o eroare de copiere/citire e cauzata de
    /// acces refuzat de Windows (fisier/folder protejat de sistem, sau
    /// apartinand altui utilizator/proces) - `UnauthorizedAccessException`
    /// e cazul direct; `IOException` cu HResult ERROR_ACCESS_DENIED (5,
    /// codificat Win32 ca 0x80070005) apare la unele operatii de fisier
    /// care nu arunca direct UnauthorizedAccessException.
    private static bool IsPermissionError(Exception ex) =>
        ex is UnauthorizedAccessException || ex.HResult == unchecked((int)0x80070005);

    private void WritePdf(string targetRoot)
    {
        try
        {
            string? truncatedNote = Files.Count > _sampleRows.Count
                ? $"Esantion plafonat: {_sampleRows.Count} din {Files.Count} fisiere afisate mai jos (toate erorile/nepotrivirile sunt incluse). Lista completa e in CSV-ul de langa acest raport."
                : null;
            PdfPath = PdfReport.Generate(
                targetRoot, DestRoot, FolderName, _sampleRows, _startedAt, DateTime.Now,
                OkCount, SkipCount, FailCount, Cancelled, Model.Label(), truncatedNote,
                Meta, RecoveredCount, MhlPath);
        }
        catch (Exception ex)
        {
            OnActivity?.Invoke($"Nu s-a putut genera raportul PDF: {ex.Message}");
            // Raportat de Cristi (2026-08-28): "nu vad PDF-ul" - fara sa fi
            // vazut vreun mesaj de eroare in feed (usor de ratat/derulat).
            // Scriem eroarea COMPLETA (tip + stack) intr-un fisier langa
            // CSV, ca sa fie gasibila chiar daca feed-ul de activitate a
            // fost ratat sau golit intre timp.
            try
            {
                var errPath = Path.Combine(targetRoot, "offload_report_PDF_EROARE.txt");
                File.WriteAllText(errPath,
                    $"Generarea raportului PDF a esuat la {DateTime.Now:yyyy-MM-dd HH:mm:ss}.\n\n" +
                    $"Tip exceptie: {ex.GetType().FullName}\nMesaj: {ex.Message}\n\nStack trace:\n{ex}");
            }
            catch { /* nici asta nu trebuie sa opreasca transferul */ }
        }
    }

    private (bool same, string srcRepr, string dstRepr) VerifyPair(FileEntry entry, string destPath)
    {
        if (Model == VerificationModel.SizeOnly)
        {
            long dstSize = File.Exists(destPath) ? new FileInfo(destPath).Length : -1;
            return (dstSize == entry.Size, $"marime={entry.Size}", $"marime={dstSize}");
        }
        var srcHash = HashOfFile(entry.FullPath, Model, ChunkSizeBytes, Cancel);
        var dstHash = HashOfFile(destPath, Model, ChunkSizeBytes, Cancel);
        return (srcHash == dstHash, srcHash, dstHash);
    }

    private void MaybeWriteCheckpoint(string targetRoot, bool force = false)
    {
        _filesSinceCheckpoint++;
        var now = DateTime.UtcNow;
        bool dueByCount = _filesSinceCheckpoint >= 10;
        bool dueByTime = (now - _lastCheckpointTime).TotalSeconds >= 5.0;
        if (!(force || dueByCount || dueByTime)) return;
        CheckpointStore.Save(targetRoot, SourceRoot, FolderName, Model.Key(), _filesStatus, force && !Cancelled, Files.Count);
        _filesSinceCheckpoint = 0;
        _lastCheckpointTime = now;
    }

    private void OpenCsv(string targetRoot)
    {
        var timestamp = DateTime.Now.ToString("yyyy-MM-dd_HH-mm-ss");
        var path = Path.Combine(targetRoot, $"offload_report_{timestamp}.csv");
        try
        {
            _csvWriter = new StreamWriter(path, append: false, Encoding.UTF8);
            _csvWriter.WriteLine("fisier,marime_bytes,verificare_sursa,verificare_destinatie,status,eroare");
            CsvPath = path;
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
        bool isProblem = row.Status is "EROARE" or "NEPOTRIVIRE";
        if (isProblem || _sampleRows.Count < PdfSampleLimit) _sampleRows.Add(row);
        OnActivity?.Invoke($"[{Path.GetFileName(DestRoot)}] {row.File} -> {row.Status}");
    }

    private void CloseCsv()
    {
        try { _csvWriter?.Flush(); _csvWriter?.Dispose(); } catch { /* ignora */ }
        _csvWriter = null;
    }

    private static string CsvEscape(string field) =>
        field.Contains(',') || field.Contains('"') || field.Contains('\n')
            ? "\"" + field.Replace("\"", "\"\"") + "\""
            : field;

    private static string FormatBytes(long bytes)
    {
        double b = bytes;
        string[] units = { "B", "KB", "MB", "GB", "TB" };
        int i = 0;
        while (b >= 1024 && i < units.Length - 1) { b /= 1024; i++; }
        return $"{b:0.0} {units[i]}";
    }

    /// Copiaza src -> dst in bucati de chunkSize, verificand cancel intre
    /// bucati - buffer-ul e alocat O SINGURA DATA (nu per iteratie), la
    /// fel ca in Python (bytes read into a reused buffer array).
    public static void CopyFileCancelable(string src, string dst, int chunkSize)
    {
        using var input = new FileStream(src, FileMode.Open, FileAccess.Read, FileShare.Read, chunkSize, FileOptions.SequentialScan);
        using var output = new FileStream(dst, FileMode.Create, FileAccess.Write, FileShare.None, chunkSize);
        var buffer = new byte[chunkSize];
        int read;
        while ((read = input.Read(buffer, 0, buffer.Length)) > 0)
        {
            output.Write(buffer, 0, read);
        }
    }

    public static string HashOfFile(string path, VerificationModel model, int chunkSize, CancelToken? cancel = null)
    {
        // [2026-09-03] xxHash64 nu e un `HashAlgorithm` din BCL, deci are
        // propria bucla de citire — aceeasi structura, acelasi buffer
        // reutilizat, aceeasi verificare de anulare intre bucati.
        if (model == VerificationModel.XxHash64)
        {
            var xx = new XxHash64();
            using var xxStream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, chunkSize, FileOptions.SequentialScan);
            var xxBuffer = new byte[chunkSize];
            int xxRead;
            while ((xxRead = xxStream.Read(xxBuffer, 0, xxBuffer.Length)) > 0)
            {
                if (cancel != null && cancel.IsCancelled) throw new OffloadCancelledException();
                xx.Update(xxBuffer, xxRead);
            }
            return xx.HexDigest();
        }

        using HashAlgorithm hasher = model switch
        {
            VerificationModel.Md5 => MD5.Create(),
            VerificationModel.Sha1 => SHA1.Create(),
            VerificationModel.Sha256 => SHA256.Create(),
            VerificationModel.Sha512 => SHA512.Create(),
            _ => MD5.Create(),
        };
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, chunkSize, FileOptions.SequentialScan);
        var buffer = new byte[chunkSize];
        int read;
        while ((read = stream.Read(buffer, 0, buffer.Length)) > 0)
        {
            if (cancel != null && cancel.IsCancelled) throw new OffloadCancelledException();
            hasher.TransformBlock(buffer, 0, read, null, 0);
        }
        hasher.TransformFinalBlock(Array.Empty<byte>(), 0, 0);
        return Convert.ToHexString(hasher.Hash!).ToLowerInvariant();
    }
}

/// Checkpoint identic ca format cu core/checkpoint.py (Python)/
/// CheckpointStore (Mac) - "offload_checkpoint.json" in radacina folderului
/// de destinatie.
public static class CheckpointStore
{
    private const string Filename = "offload_checkpoint.json";

    private sealed class CheckpointData
    {
        public string? Source { get; set; }
        public string FolderName { get; set; } = "";
        public string VerificationModel { get; set; } = "";
        public bool Completed { get; set; }
        public Dictionary<string, string> Files { get; set; } = new();
        public int? TotalFiles { get; set; }
    }

    public static Dictionary<string, string>? Load(string targetRoot)
    {
        var path = Path.Combine(targetRoot, Filename);
        if (!File.Exists(path)) return null;
        try
        {
            var json = File.ReadAllText(path);
            var data = JsonSerializer.Deserialize<CheckpointData>(json);
            return data?.Files;
        }
        catch { return null; }
    }

    public static void Save(string targetRoot, string? source, string folderName, string verificationModel,
        Dictionary<string, string> files, bool completed, int totalFiles)
    {
        var payload = new CheckpointData
        {
            Source = source, FolderName = folderName, VerificationModel = verificationModel,
            Completed = completed, Files = files, TotalFiles = totalFiles,
        };
        var path = Path.Combine(targetRoot, Filename);
        var tmp = path + ".tmp";
        try
        {
            File.WriteAllText(tmp, JsonSerializer.Serialize(payload));
            if (File.Exists(path)) File.Delete(path);
            File.Move(tmp, path);
        }
        catch { /* best-effort, ca in Python/Mac */ }
    }
}
