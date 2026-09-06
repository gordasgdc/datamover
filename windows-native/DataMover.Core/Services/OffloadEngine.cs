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

/// <summary>
/// [M1 FAZA 2, 2026-09-06] Extras din fostul `DestinationJob.HashOfFile` —
/// mutat aici ca sa ramana accesibil orchestratorului din `OffloadRunner`
/// (bucketul "fisier deja existent, verifica fara recopiere"). Comportament
/// NESCHIMBAT.
/// </summary>
public static class FileHashing
{
    public static string HashOfFile(string path, VerificationModel model, int chunkSize, CancelToken? cancel = null)
    {
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

        using System.Security.Cryptography.HashAlgorithm hasher = model switch
        {
            VerificationModel.Md5 => System.Security.Cryptography.MD5.Create(),
            VerificationModel.Sha1 => System.Security.Cryptography.SHA1.Create(),
            VerificationModel.Sha256 => System.Security.Cryptography.SHA256.Create(),
            VerificationModel.Sha512 => System.Security.Cryptography.SHA512.Create(),
            _ => System.Security.Cryptography.MD5.Create(),
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
