using DataMover.Core.Models;

namespace DataMover.Core.Services;

/// <summary>
/// Garduri de cale, pure si testabile (paritate cu Preflight.nameCollisions si
/// DestinationContext.isInsideTarget de pe Mac).
/// </summary>
public static class PathSafety
{
    private static readonly StringComparison PathCmp =
        OperatingSystem.IsWindows() || OperatingSystem.IsMacOS() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal;

    /// Caile relative care s-ar suprapune la destinatie (fara majuscule,
    /// normalizare Unicode NFC) — a doua sursa ar inlocui fisierul primei.
    public static List<string> NameCollisions(IEnumerable<FileEntry> files)
    {
        var seen = new Dictionary<string, string>();
        var hits = new List<string>();
        foreach (var f in files)
        {
            var key = f.RelPath.Replace('\\', '/').Normalize(System.Text.NormalizationForm.FormC).ToLowerInvariant();
            if (seen.TryGetValue(key, out var first) && !string.Equals(first, f.FullPath, PathCmp)) hits.Add(f.RelPath);
            else seen[key] = f.FullPath;
        }
        return hits;
    }

    /// Calea ramane in interiorul folderului tinta si niciun folder existent
    /// dintre tinta si fisier nu e reparse point (symlink/junction).
    public static bool IsInsideTarget(string destPath, string targetRoot)
    {
        var full = Path.GetFullPath(destPath);
        var root = Path.GetFullPath(targetRoot).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        if (!full.StartsWith(root + Path.DirectorySeparatorChar, PathCmp)) return false;
        var dir = Path.GetDirectoryName(full);
        while (dir != null && dir.Length >= root.Length)
        {
            if (Directory.Exists(dir) && (File.GetAttributes(dir) & FileAttributes.ReparsePoint) != 0) return false;
            if (string.Equals(dir, root, PathCmp)) break;
            dir = Path.GetDirectoryName(dir);
        }
        return true;
    }
}
