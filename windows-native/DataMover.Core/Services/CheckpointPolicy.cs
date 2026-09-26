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

    public static SourceIdentity Compute(IReadOnlyList<string> sources, IReadOnlyList<FileEntry> files,
        Func<string, string>? volumeOf = null)
    {
        volumeOf ??= VolumeOf;
        using var sha = SHA256.Create();
        var sb = new StringBuilder();
        foreach (var f in files.OrderBy(f => f.RelPath, StringComparer.Ordinal).ThenBy(f => f.FullPath, StringComparer.Ordinal))
            sb.Append(f.RelPath).Append('\0').Append(f.Size).Append('\0').Append(f.MtimeMicros).Append('\n');
        var digest = Convert.ToHexString(sha.ComputeHash(Encoding.UTF8.GetBytes(sb.ToString()))).ToLowerInvariant();
        return new SourceIdentity(sources.Select(Canonical).ToList(), sources.Select(volumeOf).ToList(), digest, files.Count);
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool GetVolumeInformation(string root, StringBuilder? name, int nameSize,
        out uint serial, out uint maxComponent, out uint flags, StringBuilder? fsName, int fsNameSize);
}

public enum CheckpointLoadKind { None, Valid, Rejected }

/// Dovada per fisier (schema 3) — identica cu `FileProof` (Mac).
public sealed record FileProof(
    [property: JsonPropertyName("source")] string Source,
    [property: JsonPropertyName("destination")] string Destination,
    [property: JsonPropertyName("verdict")] string Verdict);

public sealed record CheckpointLoad(CheckpointLoadKind Kind, Dictionary<string, string> Files,
    Dictionary<string, string> Stamps, Dictionary<string, FileProof> Proofs, string? Reason)
{
    public static CheckpointLoad None() => new(CheckpointLoadKind.None, new(), new(), new(), null);
    public static CheckpointLoad Rejected(string why) => new(CheckpointLoadKind.Rejected, new(), new(), new(), why);
}

/// Decizia byte-safe la reluare — aceeasi politica ca `RevalidationPolicy`
/// (Mac): nici metadata, nici checkpoint-ul singure nu acorda „verificat”.
public static class RevalidationPolicy
{
    public static int? HexLength(VerificationModel m) => m switch
    {
        VerificationModel.XxHash64 => 16,
        VerificationModel.Md5 => 32,
        VerificationModel.Sha1 => 40,
        VerificationModel.Sha256 => 64,
        VerificationModel.Sha512 => 128,
        _ => null,
    };

    public static bool IsWellFormed(string? hash, VerificationModel m) =>
        hash != null && HexLength(m) is int n && hash.Length == n && hash.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f');

    /// null = accepta; altfel motivul recopierii.
    public static string? Decide(VerificationModel model, string? expected, string? sourceHash, string? destinationHash)
    {
        if (model == VerificationModel.SizeOnly) return "mod „doar octeți”: fără dovadă de conținut, se recopiază";
        if (!IsWellFormed(sourceHash, model)) return "sursa nu a putut fi recitită";
        if (expected != null && expected != sourceHash) return "sursa diferă de cea din checkpoint (alți octeți)";
        if (destinationHash != sourceHash) return "destinația diferă de sursă";
        return null;
    }

    /// Recitește sursa și destinația (niciodata doar metadata) si decide.
    public static (string? Reason, string? SourceHash, string? DestinationHash) Revalidate(
        string sourcePath, string destinationPath, string? expected, VerificationModel model, int chunkSize, CancelToken cancel,
        string? cachedSourceHash = null)
    {
        string? Try(string p) { try { return FileHashing.HashOfFile(p, model, chunkSize, cancel); } catch (OffloadCancelledException) { throw; } catch { return null; } }
        var src = model == VerificationModel.SizeOnly ? null : cachedSourceHash ?? Try(sourcePath);
        var dst = model == VerificationModel.SizeOnly ? null : Try(destinationPath);
        return (Decide(model, expected, src, dst), src, dst);
    }
}

public static class CheckpointStore
{
    public const string Filename = "offload_checkpoint.json";
    /// 3: dovada per fisier (checksum sursa + destinatie); 1-2 respinse.
    public const int Schema = 3;
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
        [JsonPropertyName("file_proofs")] public Dictionary<string, FileProof>? FileProofs { get; set; }
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
        if (d.Schema != Schema || d.SourceIdentity == null || d.FileStamps == null || d.FileProofs == null)
            return CheckpointLoad.Rejected("format vechi, fără dovada de conținut");
        if (d.VerificationModel != verificationModel) return CheckpointLoad.Rejected($"alt model de verificare: {d.VerificationModel}");
        if (d.FolderName != folderName) return CheckpointLoad.Rejected($"alt folder: {d.FolderName}");
        if (!identity.SameAs(d.SourceIdentity)) return CheckpointLoad.Rejected("altă sursă (cale, volum sau conținut listat diferit)");
        if (d.Files.Values.Any(v => !AllowedStates.Contains(v))) return CheckpointLoad.Rejected("stare necunoscută în fișier");
        var model = VerificationModelFromKey(verificationModel);
        if (model == null) return CheckpointLoad.Rejected("model necunoscut");
        foreach (var kv in d.Files.Where(kv => kv.Value is "ok" or "sarit"))
        {
            if (!d.FileProofs.TryGetValue(kv.Key, out var p) || p == null) return CheckpointLoad.Rejected($"checksum absent pentru {kv.Key}");
            if (model == VerificationModel.SizeOnly)
            {
                if (p.Verdict != "size") return CheckpointLoad.Rejected($"verdict incoerent pentru {kv.Key}");
            }
            else if (p.Verdict != "checksum" || !RevalidationPolicy.IsWellFormed(p.Source, model.Value) || p.Destination != p.Source)
                return CheckpointLoad.Rejected($"checksum corupt pentru {kv.Key}");
        }
        return new CheckpointLoad(CheckpointLoadKind.Valid, d.Files, d.FileStamps, d.FileProofs, null);
    }

    private static VerificationModel? VerificationModelFromKey(string key)
    {
        foreach (VerificationModel m in Enum.GetValues(typeof(VerificationModel)))
            if (m.Key() == key) return m;
        return null;
    }

    /// Scriere atomica: temp + Flush(true) + inlocuire intr-un singur pas
    /// (MoveFileEx REPLACE_EXISTING|WRITE_THROUGH pe Windows), fara fereastra
    /// „sterge, apoi muta”. Intoarce eroarea (politica: checkpoint-ul e o
    /// optimizare, nu dovada — eroarea se consemneaza, nu schimba verdictul).
    public static Exception? Save(string targetRoot, string folderName, string verificationModel, SourceIdentity identity,
        Dictionary<string, string> files, Dictionary<string, string> stamps, Dictionary<string, FileProof> proofs, bool completed)
    {
        var path = PathFor(targetRoot);
        var tmp = path + ".tmp";
        try
        {
            var payload = new CheckpointData
            {
                Schema = Schema, Source = identity.Roots.FirstOrDefault(), FolderName = folderName,
                VerificationModel = verificationModel, Completed = completed, Files = files,
                TotalFiles = files.Count, SourceIdentity = identity, FileStamps = stamps, FileProofs = proofs,
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

    /// Metadata poate doar RESPINGE dovada (stare, amprenta sursei, fisier
    /// lipsa/alta marime). Cand e coerenta, intoarce checksum-ul asteptat al
    /// sursei — care tot trebuie reprodus prin recitire (RevalidationPolicy).
    public static string? ExpectedSourceHash(string? status, string? savedStamp, FileProof? proof, FileEntry entry, string destPath)
    {
        if (status is not ("ok" or "sarit") || proof == null || proof.Verdict != "checksum") return null;
        if (savedStamp != entry.Stamp) return null;
        try { return File.Exists(destPath) && new FileInfo(destPath).Length == entry.Size ? proof.Source : null; }
        catch { return null; }
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

    /// P/Invoke nu primeste prefixarea automata pe care .NET o face pentru cai
    /// lungi: fara `\\?\`, MoveFileEx esueaza peste MAX_PATH (Win32 3, gasit in VM).
    public static string ExtendedPath(string path)
    {
        var full = Path.GetFullPath(path);
        if (full.StartsWith(@"\\?\")) return full;
        return full.StartsWith(@"\\") ? @"\\?\UNC\" + full.Substring(2) : @"\\?\" + full;
    }

    public static void Move(string from, string to)
    {
        if (OperatingSystem.IsWindows())
        {
            if (!MoveFileEx(ExtendedPath(from), ExtendedPath(to), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH))
                throw new IOException($"Înlocuirea atomică a eșuat (Win32 {Marshal.GetLastWin32Error()})");
            return;
        }
        File.Move(from, to, overwrite: true); // rename(2) pe macOS/Linux
    }
}
