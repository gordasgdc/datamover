using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using DataMover.Core.Models;

namespace DataMover.Core.Services;

/// <summary>
/// [2026-09-26] Identitatea sursei — aceeași politică ca `SourceIdentity`
/// (Mac, TransferCore/Checkpoint.swift). Un checkpoint e acceptat DOAR pentru
/// aceeași sursă: aceleași radacini canonice, acelasi volum, aceeasi lista
/// „cale · marime · data modificarii”. Limita declarata: doua surse cu
/// aceleasi cai, marimi si date identice, dar continut diferit, nu pot fi
/// deosebite fara recitirea sursei.
/// </summary>
public sealed record SourceIdentity(
    [property: JsonPropertyName("roots")] IReadOnlyList<string> Roots,
    [property: JsonPropertyName("volumes")] IReadOnlyList<string> Volumes,
    [property: JsonPropertyName("manifest_digest")] string ManifestDigest,
    [property: JsonPropertyName("file_count")] int FileCount)
{
    public bool SameAs(SourceIdentity? other) =>
        other != null && other.ManifestDigest == ManifestDigest && other.FileCount == FileCount
        && Roots.SequenceEqual(other.Roots) && Volumes.SequenceEqual(other.Volumes);

    public static string Canonical(string path)
    {
        var full = Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        // Windows: caile nu tin cont de majuscule.
        return OperatingSystem.IsWindows() ? full.ToUpperInvariant() : full;
    }

    public static string VolumeOf(string path)
    {
        try
        {
            var root = Path.GetPathRoot(Path.GetFullPath(path)) ?? "?";
            if (OperatingSystem.IsWindows() && GetVolumeInformation(root, null, 0, out uint serial, out _, out _, null, 0))
                return $"{root}#{serial:X8}";
            return root;
        }
        catch { return "?"; }
    }

    public static SourceIdentity Compute(IReadOnlyList<string> sources, IReadOnlyList<FileEntry> files)
    {
        using var sha = SHA256.Create();
        var sb = new StringBuilder();
        foreach (var f in files.OrderBy(f => f.RelPath, StringComparer.Ordinal).ThenBy(f => f.FullPath, StringComparer.Ordinal))
            sb.Append(f.RelPath).Append('\0').Append(f.Size).Append('\0').Append(f.MtimeMicros).Append('\n');
        var digest = Convert.ToHexString(sha.ComputeHash(Encoding.UTF8.GetBytes(sb.ToString()))).ToLowerInvariant();
        return new SourceIdentity(sources.Select(Canonical).ToList(), sources.Select(VolumeOf).ToList(), digest, files.Count);
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool GetVolumeInformation(string root, StringBuilder? name, int nameSize,
        out uint serial, out uint maxComponent, out uint flags, StringBuilder? fsName, int fsNameSize);
}

public enum CheckpointLoadKind { None, Valid, Rejected }

public sealed record CheckpointLoad(CheckpointLoadKind Kind, Dictionary<string, string> Files,
    Dictionary<string, string> Stamps, string? Reason)
{
    public static CheckpointLoad None() => new(CheckpointLoadKind.None, new(), new(), null);
    public static CheckpointLoad Rejected(string why) => new(CheckpointLoadKind.Rejected, new(), new(), why);
}

public static class CheckpointStore
{
    public const string Filename = "offload_checkpoint.json";
    public const int Schema = 2;
    private static readonly HashSet<string> AllowedStates = new() { "ok", "sarit", "fail" };

    private sealed class CheckpointData
    {
        [JsonPropertyName("schema")] public int? Schema { get; set; }
        [JsonPropertyName("source")] public string? Source { get; set; }
        [JsonPropertyName("folder_name")] public string FolderName { get; set; } = "";
        [JsonPropertyName("verification_model")] public string VerificationModel { get; set; } = "";
        [JsonPropertyName("completed")] public bool Completed { get; set; }
        [JsonPropertyName("files")] public Dictionary<string, string> Files { get; set; } = new();
        [JsonPropertyName("total_files")] public int? TotalFiles { get; set; }
        [JsonPropertyName("source_identity")] public SourceIdentity? SourceIdentity { get; set; }
        [JsonPropertyName("file_stamps")] public Dictionary<string, string>? FileStamps { get; set; }
    }

    public static string PathFor(string targetRoot) => Path.Combine(targetRoot, Filename);

    /// Accepta checkpoint-ul DOAR daca apartine exact aceluiasi transfer
    /// (schema, identitatea sursei, folder, model, stari cunoscute).
    public static CheckpointLoad LoadValidated(string targetRoot, string folderName, string verificationModel, SourceIdentity identity)
    {
        var path = PathFor(targetRoot);
        if (!File.Exists(path)) return CheckpointLoad.None();
        CheckpointData? d;
        try { d = JsonSerializer.Deserialize<CheckpointData>(File.ReadAllText(path)); }
        catch { return CheckpointLoad.Rejected("fișier corupt"); }
        if (d == null) return CheckpointLoad.Rejected("fișier corupt");
        if (d.Schema != Schema || d.SourceIdentity == null || d.FileStamps == null)
            return CheckpointLoad.Rejected("format vechi, fără identitatea sursei");
        if (d.VerificationModel != verificationModel) return CheckpointLoad.Rejected($"alt model de verificare: {d.VerificationModel}");
        if (d.FolderName != folderName) return CheckpointLoad.Rejected($"alt folder: {d.FolderName}");
        if (!identity.SameAs(d.SourceIdentity)) return CheckpointLoad.Rejected("altă sursă (cale, volum sau conținut listat diferit)");
        if (d.Files.Values.Any(v => !AllowedStates.Contains(v))) return CheckpointLoad.Rejected("stare necunoscută în fișier");
        return new CheckpointLoad(CheckpointLoadKind.Valid, d.Files, d.FileStamps, null);
    }

    /// Scriere atomica: temp + Flush(true) + inlocuire intr-un singur pas
    /// (MoveFileEx REPLACE_EXISTING|WRITE_THROUGH pe Windows), fara fereastra
    /// „sterge, apoi muta”. Intoarce eroarea (politica: checkpoint-ul e o
    /// optimizare, nu dovada — eroarea se consemneaza, nu schimba verdictul).
    public static Exception? Save(string targetRoot, string folderName, string verificationModel, SourceIdentity identity,
        Dictionary<string, string> files, Dictionary<string, string> stamps, bool completed)
    {
        var path = PathFor(targetRoot);
        var tmp = path + ".tmp";
        try
        {
            var payload = new CheckpointData
            {
                Schema = Schema, Source = identity.Roots.FirstOrDefault(), FolderName = folderName,
                VerificationModel = verificationModel, Completed = completed, Files = files,
                TotalFiles = files.Count, SourceIdentity = identity, FileStamps = stamps,
            };
            var bytes = JsonSerializer.SerializeToUtf8Bytes(payload);
            using (var fs = new FileStream(tmp, FileMode.Create, FileAccess.Write, FileShare.None))
            {
                fs.Write(bytes, 0, bytes.Length);
                fs.Flush(true);
            }
            AtomicReplace.Move(tmp, path);
            return null;
        }
        catch (Exception ex)
        {
            try { if (File.Exists(tmp)) File.Delete(tmp); } catch { /* temp propriu */ }
            return ex;
        }
    }

    /// Un fisier marcat „ok/sarit” poate fi sarit DOAR daca: amprenta sursei
    /// (marime:mtime) e cea de la confirmare si destinatia exista cu marimea
    /// sursei. Identitatea globala a sursei a fost deja validata la incarcare.
    public static bool CanSkip(string? status, string? savedStamp, FileEntry entry, string destPath)
    {
        if (status is not ("ok" or "sarit")) return false;
        if (savedStamp != entry.Stamp) return false;
        try { return File.Exists(destPath) && new FileInfo(destPath).Length == entry.Size; }
        catch { return false; }
    }
}

/// Inlocuire atomica a unui fisier. Pe Windows: MoveFileEx cu WRITE_THROUGH
/// (operatia se intoarce abia dupa ce redenumirea e scrisa pe disc).
public static class AtomicReplace
{
    private const uint MOVEFILE_REPLACE_EXISTING = 0x1;
    private const uint MOVEFILE_WRITE_THROUGH = 0x8;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool MoveFileEx(string existing, string target, uint flags);

    public static void Move(string from, string to)
    {
        if (OperatingSystem.IsWindows())
        {
            if (!MoveFileEx(from, to, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
                throw new IOException($"Înlocuirea atomică a eșuat (Win32 {Marshal.GetLastWin32Error()})");
            return;
        }
        File.Move(from, to, overwrite: true); // rename(2) pe macOS/Linux
    }
}
