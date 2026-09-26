using System.Reflection;

namespace DataMover.Core.Diagnostics;

/// Identitatea buildului din jurnal: commitul scurt din
/// AssemblyInformationalVersion ("2.16.1+<sha>", pus de SDK la build din git).
/// Fara commit (build in afara git) ramane "dev".
public static class BuildIdentity
{
    public static string FromInformationalVersion(string? info)
    {
        if (string.IsNullOrWhiteSpace(info)) return "dev";
        var plus = info.IndexOf('+');
        if (plus < 0) return "dev";
        var sha = info[(plus + 1)..].Trim();
        if (sha.Length < 7 || !sha.All(Uri.IsHexDigit)) return "dev";
        return sha[..7].ToLowerInvariant();
    }

    public static string Of(Assembly asm) =>
        FromInformationalVersion(asm.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion);
}
