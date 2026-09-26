using System.Globalization;

namespace DataMover.Core.Services;

/// Afisarea marimilor, aliniata la macOS (ByteCountFormatter .file):
/// unitati zecimale (1 KB = 1000 B), deci valoarea corespunde etichetei.
/// Aceeasi sursa arata acum aceeasi cifra pe Mac si pe Windows.
public static class ByteSize
{
    private static readonly string[] Units = { "B", "KB", "MB", "GB", "TB" };

    public static string Format(long bytes, string pattern = "0.#", CultureInfo? culture = null)
    {
        double b = bytes;
        int i = 0;
        while (Math.Abs(b) >= 1000 && i < Units.Length - 1) { b /= 1000; i++; }
        return b.ToString(i == 0 ? "0" : pattern, culture ?? CultureInfo.CurrentCulture) + " " + Units[i];
    }
}
