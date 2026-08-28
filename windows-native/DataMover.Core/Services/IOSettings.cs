using System.Diagnostics;

namespace DataMover.Core.Services;

/// <summary>
/// Setari configurabile de I/O si memorie - port 1:1 al IOSettings.swift
/// (Mac) / core/io_settings.py (Windows Python). Persistat prin
/// AppSettingsStore (JSON in %AppData%), la fel ca restul setarilor.
/// </summary>
public sealed class IOPerformancePreset
{
    public string Id { get; init; } = "";
    public string Label { get; init; } = "";
    public int ChunkSizeMB { get; init; }
    public int RamLimitMB { get; init; }
}

public static class IOSettings
{
    public const int DefaultChunkSizeMB = 8;

    // Trepte granulate (cerinta explicita) - identice cu Mac/Python.
    public static readonly int[] ChunkSizeChoicesMB = { 1, 2, 4, 8, 16, 32, 64, 128 };
    public static readonly int[] RamLimitChoicesMB = { 0, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536 };

    public static readonly IOPerformancePreset[] Presets =
    {
        new() { Id = "eco", Label = "Eco / Sistem Slab", ChunkSizeMB = 4, RamLimitMB = 1024 },
        new() { Id = "standard", Label = "Standard", ChunkSizeMB = 8, RamLimitMB = 4096 },
        new() { Id = "high", Label = "Performanta Inalta", ChunkSizeMB = 32, RamLimitMB = 16384 },
        new() { Id = "extreme", Label = "Extrem / Productie RAW", ChunkSizeMB = 64, RamLimitMB = 32768 },
    };

    /// "512 MB" sub 1 GB, "8 GB" de la 1024 MB in sus.
    public static string SizeLabel(int mb) => mb >= 1024 ? $"{mb / 1024} GB" : $"{mb} MB";

    /// Memoria de lucru (Working Set) a procesului curent, in bytes -
    /// echivalentul IOSettings.currentResidentMemoryBytes() de pe Mac.
    public static long CurrentProcessMemoryBytes()
    {
        try
        {
            using var proc = Process.GetCurrentProcess();
            return proc.WorkingSet64;
        }
        catch
        {
            return 0;
        }
    }

    /// Backpressure: daca procesul a depasit ramLimitMb configurat,
    /// asteapta putin (verificand cancel-ul intre timpi) inainte sa lase
    /// urmatorul fisier sa inceapa - identic cu waitIfOverRAMLimit (Mac) /
    /// wait_if_over_ram_limit (Python).
    public static void WaitIfOverRamLimit(int ramLimitMb, CancelToken cancel, Action<string>? onWarning = null)
    {
        if (ramLimitMb <= 0) return;
        long limitBytes = (long)ramLimitMb * 1024 * 1024;
        long used = CurrentProcessMemoryBytes();
        if (used <= limitBytes) return;

        double waited = 0;
        bool warned = false;
        while (used > limitBytes && waited < 30.0)
        {
            if (cancel.IsCancelled) return;
            if (!warned)
            {
                onWarning?.Invoke(
                    $"ATENTIE: memoria aplicatiei ({used / 1024 / 1024} MB) a depasit limita " +
                    $"setata ({ramLimitMb} MB) - se asteapta putin inainte de urmatorul fisier (backpressure).");
                warned = true;
            }
            Thread.Sleep(500);
            waited += 0.5;
            used = CurrentProcessMemoryBytes();
        }
    }
}
