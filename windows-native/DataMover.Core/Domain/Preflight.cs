namespace DataMover.Core.Domain;

/// <summary>
/// Verificari inainte de primul octet — paritate cu `Preflight.swift`.
/// Pur fata de UI; rulat si de interfata (incidente) si de OffloadRunner.Start.
/// </summary>
public enum PreflightCode
{
    NoSources, NoDestinations, SourceMissing, DestinationMissing, DestinationNotDirectory,
    DestinationInsideSource, SourceInsideDestination, SameAsSource, DuplicateDestination,
    NestedDestinations, SameVolumeAsSource, SourceNameCollision,
}

public sealed record PreflightIssue(PreflightCode Code, bool Blocking, string Path);

public static class Preflight
{
    private static StringComparison Cmp => OperatingSystem.IsLinux() ? StringComparison.Ordinal : StringComparison.OrdinalIgnoreCase;

    public static string Canonical(string p)
    {
        var full = System.IO.Path.GetFullPath(p);
        try
        {
            var target = new DirectoryInfo(full).ResolveLinkTarget(returnFinalTarget: true);
            if (target != null) full = target.FullName;
        }
        catch { /* fara link sau fara drepturi: calea completa ramane */ }
        return full.TrimEnd(System.IO.Path.DirectorySeparatorChar, System.IO.Path.AltDirectorySeparatorChar);
    }

    public static bool IsSameOrInside(string child, string parent) =>
        string.Equals(child, parent, Cmp) || child.StartsWith(parent + System.IO.Path.DirectorySeparatorChar, Cmp);

    public static List<PreflightIssue> Check(IReadOnlyList<string> sources, IReadOnlyList<string> destinations)
    {
        var issues = new List<PreflightIssue>();
        if (sources.Count == 0) issues.Add(new(PreflightCode.NoSources, true, ""));
        if (destinations.Count == 0) issues.Add(new(PreflightCode.NoDestinations, true, ""));
        var cs = new List<string>();
        foreach (var s in sources)
        {
            if (!Directory.Exists(s) && !File.Exists(s)) { issues.Add(new(PreflightCode.SourceMissing, true, s)); continue; }
            cs.Add(Canonical(s));
        }
        var seen = new List<string>();
        foreach (var d in destinations)
        {
            if (File.Exists(d)) { issues.Add(new(PreflightCode.DestinationNotDirectory, true, d)); continue; }
            if (!Directory.Exists(d)) { issues.Add(new(PreflightCode.DestinationMissing, true, d)); continue; }
            var cd = Canonical(d);
            foreach (var s in cs)
            {
                if (string.Equals(cd, s, Cmp)) issues.Add(new(PreflightCode.SameAsSource, true, d));
                else if (IsSameOrInside(cd, s)) issues.Add(new(PreflightCode.DestinationInsideSource, true, d));
                else if (IsSameOrInside(s, cd)) issues.Add(new(PreflightCode.SourceInsideDestination, true, d));
            }
            if (seen.Any(x => string.Equals(x, cd, Cmp))) issues.Add(new(PreflightCode.DuplicateDestination, true, d));
            else if (seen.Any(x => IsSameOrInside(cd, x) || IsSameOrInside(x, cd))) issues.Add(new(PreflightCode.NestedDestinations, true, d));
            seen.Add(cd);
            var dv = System.IO.Path.GetPathRoot(cd);
            if (!issues.Any(i => i.Path == d && i.Blocking) && cs.Any(s => string.Equals(System.IO.Path.GetPathRoot(s), dv, Cmp)))
                issues.Add(new(PreflightCode.SameVolumeAsSource, false, d));
        }
        return issues;
    }

    public static bool HasBlocking(IEnumerable<PreflightIssue> issues) => issues.Any(i => i.Blocking);

    /// Textul pentru operator (cauza + actiunea), in romana (UI Windows e RO).
    public static (string Title, string Cause, string Action) Describe(PreflightCode c) => c switch
    {
        PreflightCode.NoSources => ("Nicio sursă", "Traseul nu are încă o sursă.", "Adaugă cardul (Dispozitive sau Adaugă sursă…)."),
        PreflightCode.NoDestinations => ("Nicio copie", "Traseul nu are încă nicio destinație.", "Adaugă cel puțin un disc."),
        PreflightCode.SourceMissing => ("Sursa lipsește", "Calea sursei nu mai există.", "Reintrodu cardul sau scoate-l din listă."),
        PreflightCode.DestinationMissing => ("Destinația lipsește", "Calea destinației nu mai există.", "Reconectează discul sau scoate-l din listă."),
        PreflightCode.DestinationNotDirectory => ("Destinația e un fișier", "Destinația trebuie să fie un folder sau un disc.", "Alege un folder."),
        PreflightCode.DestinationInsideSource => ("Copia ar ajunge pe card", "Destinația se află în interiorul sursei.", "Alege un disc separat."),
        PreflightCode.SourceInsideDestination => ("Sursa e în destinație", "O reluare ar copia propria ieșire.", "Alege o destinație în afara sursei."),
        PreflightCode.SameAsSource => ("Sursa = destinația", "Sursa și copia sunt același loc.", "Alege alt disc pentru copie."),
        PreflightCode.DuplicateDestination => ("Destinație dublată", "Aceeași destinație apare de două ori.", "Scoate duplicatul."),
        PreflightCode.NestedDestinations => ("Destinații imbricate", "O copie ar ajunge în interiorul alteia.", "Folosește destinații separate."),
        PreflightCode.SameVolumeAsSource => ("Același disc cu sursa", "Un singur disc defect ar pierde și sursa, și copia.", "Pentru siguranță, folosește un disc separat."),
        PreflightCode.SourceNameCollision => ("Nume identice în surse", "Două surse au fișiere cu aceeași cale; a doua ar înlocui prima.", "Copiază sursele separat."),
        _ => (c.ToString(), "", ""),
    };
}
