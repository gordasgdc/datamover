namespace DataMover.Core.Models;

/// <summary>
/// O intrare de fisier gasita la scanare - port 1:1 al FileEntry (Mac,
/// OffloadEngine.swift).
/// </summary>
public readonly struct FileEntry
{
    public string FullPath { get; }
    public string RelPath { get; }
    public long Size { get; }

    public FileEntry(string fullPath, string relPath, long size)
    {
        FullPath = fullPath;
        RelPath = relPath;
        Size = size;
    }
}

public sealed class ReportRow
{
    public string File { get; init; } = "";
    public long SizeBytes { get; init; }
    public string SrcHash { get; init; } = "";
    public string DstHash { get; init; } = "";
    public string Status { get; init; } = "";
    public string Error { get; init; } = "";
}

public sealed class DestinationResult
{
    public string DestRoot { get; init; } = "";
    public int OkCount { get; init; }
    public int SkipCount { get; init; }
    public int FailCount { get; init; }
    public bool Cancelled { get; init; }
    public string? CsvPath { get; init; }
    public string? PdfPath { get; init; }
}
