using System.Collections.Concurrent;
using System.Security.Cryptography;

namespace DataMover.Core.Services;

/// <summary>
/// [M1, 2026-09-06] Port 1:1 al FanOutCopier.swift (Mac) — vezi acolo
/// pentru comentariul complet de arhitectura/motiv. Pe scurt: inlocuieste
/// tiparul vechi din OffloadEngine.cs (`VerifyPair` re-citeste sursa PLUS
/// destinatia, per destinatie, dupa ce `CopyFileCancelable` a citit deja
/// o data sursa pentru copiere - 4 citiri ale sursei cu 2 destinatii) cu
/// UN SINGUR thread de citire din card, care distribuie fiecare bucata
/// catre N thread-uri de scriere prin `BlockingCollection&lt;T&gt;`
/// (colectia marginita nativa .NET - potrivire perfecta pentru ring
/// buffer cu backpressure, fara sa trebuiasca reinventata pe aceasta
/// platforma cum a fost nevoie pe Swift/AppKit).
/// </summary>
public sealed class FanOutError : Exception
{
    public FanOutError(string message) : base(message) { }
}

public sealed class FanOutDestResult
{
    public bool Success { get; init; }
    public string? Hash { get; init; }
    public long BytesWritten { get; init; }
    public Exception? Error { get; init; }
    /// [2026-09-26] True DOAR daca fisierul a fost confirmat (hash/marime =
    /// sursa, sursa nemodificata) si mutat la numele final. Success fara
    /// Verified = scris complet, dar neconfirmat: partialul a fost sters,
    /// numele final nu a fost atins. Paritate cu `.mismatch` din Swift.
    public bool Verified { get; init; }
    public string? MismatchReason { get; init; }
}

/// Numele temporar sub care se scrie un fisier pana e confirmat — identic
/// cu `PartialFile` (Mac). Nu e niciodata raportat drept verificat.
public static class PartialFile
{
    public const string Suffix = ".dmpart";
    public static string PathFor(string finalPath) =>
        System.IO.Path.Combine(System.IO.Path.GetDirectoryName(finalPath) ?? "",
            "." + System.IO.Path.GetFileName(finalPath) + Suffix);
}

public sealed class FanOutResult
{
    public string SourceHash { get; init; } = "";
    public long BytesRead { get; init; }
    public Dictionary<string, FanOutDestResult> Destinations { get; init; } = new();
}

/// <summary>
/// Wrapper incremental unificat peste toate modelele de verificare —
/// extras din bucla existenta a lui `HashOfFile` (OffloadEngine.cs) ca sa
/// poata fi alimentat bucata-cu-bucata dintr-un flux extern (fan-out),
/// nu doar dintr-o bucla proprie care citeste un fisier de pe disc.
/// `HashOfFile` ramane neschimbat — foloseste in continuare propria bucla.
/// </summary>
public sealed class IncrementalHasher : IDisposable
{
    private readonly XxHash64? _xx;
    private readonly HashAlgorithm? _algo;
    private long _sizeOnlyCount;

    public IncrementalHasher(VerificationModel model)
    {
        if (model == VerificationModel.XxHash64)
        {
            _xx = new XxHash64();
        }
        else if (model != VerificationModel.SizeOnly)
        {
            _algo = model switch
            {
                VerificationModel.Md5 => MD5.Create(),
                VerificationModel.Sha1 => SHA1.Create(),
                VerificationModel.Sha256 => SHA256.Create(),
                VerificationModel.Sha512 => SHA512.Create(),
                _ => MD5.Create(),
            };
        }
    }

    public void Update(byte[] buffer, int count)
    {
        if (_xx != null) { _xx.Update(buffer, count); return; }
        if (_algo != null) { _algo.TransformBlock(buffer, 0, count, null, 0); return; }
        _sizeOnlyCount += count; // marime-doar: nu exista hash real, doar numaram
    }

    public string FinalizeHex()
    {
        if (_xx != null) return _xx.HexDigest();
        if (_algo != null)
        {
            _algo.TransformFinalBlock(Array.Empty<byte>(), 0, 0);
            return Convert.ToHexString(_algo.Hash!).ToLowerInvariant();
        }
        return "";
    }

    public void Dispose() => _algo?.Dispose();
}

/// O bucata citita din sursa — `Length` poate fi mai mic decat
/// `Data.Length` la ultima bucata dintr-un fisier (buffer alocat per
/// bucata, nu reutilizat, ca fiecare consumator sa aiba propria referinta
/// stabila cat timp o proceseaza pe threadul lui).
public sealed record ChunkBuffer(byte[] Data, int Length);

public sealed class FanOutCopier
{
    private static void TryDelete(string path)
    {
        try { if (File.Exists(path)) File.Delete(path); } catch { /* parțial propriu, best-effort */ }
    }

    private readonly string _sourcePath;
    private readonly IReadOnlyList<string> _destinationPaths;
    private readonly int _chunkSize;
    private readonly int _ringDepth;
    private readonly VerificationModel _model;
    private readonly CancelToken _cancel;
    private readonly PauseToken _pause;
    private readonly long? _expectedSize;
    private readonly Func<string, string, Stream> _openOutput;

    /// `openOutput(partialPath, finalPath)` — injectabil in teste (ex. o
    /// destinatie care esueaza la a N-a scriere).
    public FanOutCopier(string sourcePath, IReadOnlyList<string> destinationPaths, int chunkSize,
        VerificationModel model, CancelToken cancel, PauseToken pause, int ringDepth = 3, long? expectedSize = null,
        Func<string, string, Stream>? openOutput = null)
    {
        _expectedSize = expectedSize;
        _openOutput = openOutput ?? ((part, _) => new FileStream(part, FileMode.Create, FileAccess.Write, FileShare.None, chunkSize));
        _sourcePath = sourcePath;
        _destinationPaths = destinationPaths;
        _chunkSize = chunkSize;
        _ringDepth = Math.Max(2, ringDepth);
        _model = model;
        _cancel = cancel;
        _pause = pause;
    }

    public FanOutResult Run(Action<long> onBytesRead)
    {
        var queues = _destinationPaths.ToDictionary(
            d => d, d => new BlockingCollection<ChunkBuffer>(boundedCapacity: _ringDepth));
        var results = new ConcurrentDictionary<string, FanOutDestResult>();

        var tasks = _destinationPaths.Select(dst => Task.Run(() =>
        {
            var queue = queues[dst];
            try
            {
                using var output = _openOutput(PartialFile.PathFor(dst), dst);
                using var hasher = new IncrementalHasher(_model);
                long written = 0;
                foreach (var chunk in queue.GetConsumingEnumerable())
                {
                    output.Write(chunk.Data, 0, chunk.Length);
                    hasher.Update(chunk.Data, chunk.Length);
                    written += chunk.Length;
                }
                // [M2, 2026-09-06] Flush FIZIC obligatoriu inainte de a marca
                // fisierul OK - vezi comentariul complet din FanOutCopier.swift
                // (Mac) pentru motiv. `FileStream.Flush(true)` e documentat
                // oficial de Microsoft sa apeleze `FlushFileBuffers` la nivel
                // de OS pe Windows (nu doar bufferul intern .NET) - fara
                // P/Invoke necesar. O eroare aici opreste DOAR aceasta
                // destinatie, nu si celelalte.
                if (output is FileStream fsOut) fsOut.Flush(true); else output.Flush();
                results[dst] = new FanOutDestResult { Success = true, Hash = hasher.FinalizeHex(), BytesWritten = written };
            }
            catch (Exception ex)
            {
                results[dst] = new FanOutDestResult { Success = false, Error = ex };
                // [2026-09-26] Golim coada in loc de CompleteAdding: un
                // producator blocat in Add() pe o coada plina nu era trezit de
                // CompleteAdding -> blocaj al intregului transfer.
                foreach (var _ in queue.GetConsumingEnumerable()) { }
            }
        })).ToArray();

        // Thread-ul de CITIRE — singurul care atinge sursa. Ruleaza sincron
        // pe thread-ul apelant (deja de fundal in OffloadRunner).
        // Deschiderea sursei sta IN try: daca esueaza (fisier blocat de alt
        // proces, acces refuzat), cozile trebuie totusi inchise — altfel
        // scriitorii raman blocati pentru totdeauna, cu .dmpart deschis
        // (gasit in Windows 11, 2026-09-26).
        using var sourceHasher = new IncrementalHasher(_model);
        long bytesRead = 0;
        Exception? readError = null;
        FileStream? input = null;
        (long Length, DateTime LastWriteTimeUtc) stampBefore = default;
        try
        {
            var infoBefore = new FileInfo(_sourcePath);
            stampBefore = (infoBefore.Length, infoBefore.LastWriteTimeUtc);
            input = new FileStream(_sourcePath, FileMode.Open, FileAccess.Read, FileShare.Read,
                _chunkSize, FileOptions.SequentialScan);
            while (true)
            {
                if (_cancel.IsCancelled) throw new OffloadCancelledException();
                while (_pause.IsPaused && !_cancel.IsCancelled) Thread.Sleep(50);
                if (_cancel.IsCancelled) throw new OffloadCancelledException();

                var buffer = new byte[_chunkSize];
                int read = input.Read(buffer, 0, _chunkSize);
                if (read == 0) break;

                sourceHasher.Update(buffer, read);
                bytesRead += read;
                onBytesRead(read);

                var chunk = new ChunkBuffer(buffer, read);
                // Un consumator esuat isi goleste singur coada (vezi catch-ul
                // de mai sus), deci Add nu se poate bloca definitiv si coada nu
                // creste peste capacitate (BlockingCollection marginita).
                foreach (var queue in queues.Values) queue.Add(chunk);
            }
        }
        catch (Exception ex)
        {
            readError = ex;
        }
        finally
        {
            input?.Dispose();
            foreach (var q in queues.Values)
            {
                q.CompleteAdding();
            }
        }

        Task.WaitAll(tasks);

        if (readError != null)
        {
            foreach (var dst in _destinationPaths) TryDelete(PartialFile.PathFor(dst));
            throw readError;
        }

        var sourceHash = sourceHasher.FinalizeHex();
        string? sourceProblem = null;
        var infoAfter = new FileInfo(_sourcePath);
        if (_expectedSize.HasValue && bytesRead != _expectedSize.Value)
            sourceProblem = $"Sursa are {bytesRead} octeti cititi, dar {_expectedSize.Value} la scanare — s-a modificat in timpul copierii.";
        else if (infoAfter.Length != stampBefore.Length || infoAfter.LastWriteTimeUtc != stampBefore.LastWriteTimeUtc)
            sourceProblem = "Sursa s-a modificat in timpul copierii.";

        var final = new Dictionary<string, FanOutDestResult>();
        foreach (var dst in _destinationPaths)
        {
            var part = PartialFile.PathFor(dst);
            if (!results.TryGetValue(dst, out var r) || !r.Success)
            {
                TryDelete(part);
                final[dst] = r ?? new FanOutDestResult { Success = false, Error = new FanOutError("Fara rezultat de la motorul de copiere") };
                continue;
            }
            string? reason = sourceProblem;
            if (reason == null && r.BytesWritten != bytesRead) reason = $"Scrisi {r.BytesWritten} din {bytesRead} octeti.";
            if (reason == null && _model != VerificationModel.SizeOnly && r.Hash != sourceHash) reason = "Checksum diferit.";
            if (reason != null)
            {
                TryDelete(part);
                final[dst] = new FanOutDestResult { Success = true, Verified = false, Hash = r.Hash, BytesWritten = r.BytesWritten, MismatchReason = reason };
                continue;
            }
            try
            {
                AtomicReplace.Move(part, dst);
                final[dst] = new FanOutDestResult { Success = true, Verified = true, Hash = r.Hash, BytesWritten = r.BytesWritten };
            }
            catch (Exception ex)
            {
                TryDelete(part);
                final[dst] = new FanOutDestResult { Success = false, Error = new FanOutError($"Finalizarea (redenumirea) a esuat: {ex.Message}") };
            }
        }

        return new FanOutResult
        {
            SourceHash = sourceHash,
            BytesRead = bytesRead,
            Destinations = final,
        };
    }
}
