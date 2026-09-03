using System.IO;

namespace DataMover.Core.Services;

/// <summary>
/// [2026-09-03] Port 1:1 al CameraCardDetector.swift (Mac) —
/// recunoasterea structurii unui card de camera.
///
/// DE CE: un card nu e un folder oarecare. Greselile clasice de pe platou
/// sunt mereu aceleasi doua: (1) se selecteaza un SUBFOLDER al cardului si
/// se pierd metadatele fara de care materialul nu se mai reasambleaza in
/// post; (2) cardul e defect/scos prea devreme si contine clipuri
/// incomplete, iar asta se descopera abia cand cardul a fost reformatat.
/// Detectia e pur informativa — nu blocheaza niciodata transferul.
/// </summary>
public sealed class CameraCardInfo
{
    public string CardType { get; init; } = "";
    public int? ClipCount { get; init; }
    public List<string> Warnings { get; init; } = new();

    public string Summary => ClipCount.HasValue ? $"{CardType} — {ClipCount} clip(uri)" : CardType;
}

public static class CameraCardDetector
{
    private static readonly HashSet<string> MediaExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".r3d", ".ari", ".arx", ".mxf", ".braw", ".mov", ".mp4", ".crm", ".cr2", ".cr3",
        ".nev", ".mts", ".m2ts", ".dng", ".wav", ".avi", ".insv"
    };

    /// Intoarce null daca nu recunoaste nicio structura cunoscuta (folder
    /// normal de lucru) — caz in care UI-ul nu arata nimic.
    public static CameraCardInfo? Detect(string root)
    {
        if (!Directory.Exists(root)) return null;

        string[] entries;
        try { entries = Directory.GetFileSystemEntries(root).Select(Path.GetFileName).Where(n => n != null).Cast<string>().ToArray(); }
        catch { return null; }
        var names = new HashSet<string>(entries, StringComparer.OrdinalIgnoreCase);

        string? type = null;
        // Ordinea conteaza: structurile specifice se verifica INAINTEA celei
        // generice `DCIM`, pe care o au si Sony, si Canon, si un telefon.
        if (entries.Any(e => e.EndsWith(".RDM", StringComparison.OrdinalIgnoreCase)))
            type = "RED (R3D)";
        else if (names.Contains("AVID") || entries.Any(e => e.EndsWith(".ARI", StringComparison.OrdinalIgnoreCase)))
            type = "ARRI";
        else if (names.Contains("XDROOT"))
            type = "Sony XDCAM";
        else if (names.Contains("PRIVATE"))
        {
            var sub = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            try
            {
                foreach (var d in Directory.GetDirectories(Path.Combine(root, "PRIVATE")))
                {
                    var n = Path.GetFileName(d);
                    if (n != null) sub.Add(n);
                }
            }
            catch { /* ignora */ }
            if (sub.Contains("M4ROOT")) type = "Sony XAVC";
            else if (sub.Contains("AVCHD")) type = "Panasonic AVCHD";
            else type = "Card video (PRIVATE)";
        }
        else if (names.Contains("CONTENTS"))
            type = "Panasonic P2";
        else if (entries.Any(e => e.EndsWith(".braw", StringComparison.OrdinalIgnoreCase)))
            type = "Blackmagic BRAW";
        else if (names.Contains("CLIPS001") || (names.Contains("DCIM") && names.Contains("MISC")))
            // Cardurile Canon au `DCIM` alaturi de `MISC` — `DCIM` singur
            // (verificat mai jos) e prea generic, il are si un telefon.
            type = "Canon";
        else if (names.Contains("DCIM"))
            type = "Card foto/video (DCIM)";

        if (type == null) return null;

        // Numaratoarea se face plafonat: pe un card cu zeci de mii de fisiere
        // nu are rost sa blocam UI-ul pentru o informatie orientativa.
        int clipCount = 0, scanned = 0;
        const int ScanLimit = 60_000;
        var zeroByteFiles = new List<string>();
        try
        {
            foreach (var full in Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories))
            {
                if (++scanned > ScanLimit) break;
                var name = Path.GetFileName(full);
                if (name.StartsWith('.')) continue;
                if (!MediaExtensions.Contains(Path.GetExtension(full))) continue;
                clipCount++;
                try
                {
                    if (new FileInfo(full).Length == 0 && zeroByteFiles.Count < 5) zeroByteFiles.Add(name);
                }
                catch { /* ignora */ }
            }
        }
        catch { /* card inaccesibil in timpul scanarii - pastram ce am numarat */ }

        var warnings = new List<string>();
        if (clipCount == 0) warnings.Add("Cardul pare gol — nu s-a găsit niciun fișier media.");
        if (zeroByteFiles.Count > 0)
            warnings.Add($"Fișiere de 0 octeți (posibil clipuri incomplete): {string.Join(", ", zeroByteFiles)}");
        if (scanned > ScanLimit) warnings.Add("Card foarte mare — numărătoarea de clipuri e orientativă.");

        return new CameraCardInfo { CardType = type, ClipCount = clipCount, Warnings = warnings };
    }

    /// Cazul cel mai costisitor de pe platou: s-a tras in Surse un SUBFOLDER
    /// al unui card, nu radacina lui. Urcam pana la 3 nivele si verificam
    /// daca parintele arata a card.
    public static string? ParentLooksLikeCard(string path)
    {
        var current = Path.GetDirectoryName(path);
        for (int i = 0; i < 3 && !string.IsNullOrEmpty(current); i++)
        {
            if (Detect(current) != null) return current;
            current = Path.GetDirectoryName(current);
        }
        return null;
    }
}
