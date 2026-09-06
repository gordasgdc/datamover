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
    private readonly string _sourcePath;
    private readonly IReadOnlyList<string> _destinationPaths;
    private readonly int _chunkSize;
    private readonly int _ringDepth;
    private readonly VerificationModel _model;
    private readonly CancelToken _cancel;
    private readonly PauseToken _pause;

    public FanOutCopier(string sourcePath, IReadOnlyList<string> destinationPaths, int chunkSize,
        VerificationModel model, CancelToken cancel, PauseToken pause, int ringDepth = 3)
    {
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
        var failedDestinations = new HashSet<string>();

        var tasks = _destinationPaths.Select(dst => Task.Run(() =>
        {
            var queue = queues[dst];
            try
            {
                using var output = new FileStream(dst, FileMode.Create, FileAccess.Write, FileShare.None, _chunkSize);
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
                output.Flush(true);
                results[dst] = new FanOutDestResult { Success = true, Hash = hasher.FinalizeHex(), BytesWritten = written };
            }
            catch (Exception ex)
            {
                results[dst] = new FanOutDestResult { Success = false, Error = ex };
                try { queue.CompleteAdding(); } catch (ObjectDisposedException) { /* deja completat */ }
            }
        })).ToArray();

        // Thread-ul de CITIRE — singurul care atinge sursa. Ruleaza sincron
        // pe thread-ul apelant (deja de fundal in OffloadRunner).
        using var input = new FileStream(_sourcePath, FileMode.Open, FileAccess.Read, FileShare.Read,
            _chunkSize, FileOptions.SequentialScan);
        using var sourceHasher = new IncrementalHasher(_model);
        long bytesRead = 0;
        Exception? readError = null;
        try
        {
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
                foreach (var (dst, queue) in queues)
                {
                    if (failedDestinations.Contains(dst)) continue;
                    try { queue.Add(chunk); }
                    catch (InvalidOperationException)
                    {
                        // consumatorul acelei destinatii a esuat deja si a
                        // inchis coada (CompleteAdding) - ignoram tacit
                        // pentru restul transferului acestui fisier, dar
                        // NU oprim celelalte destinatii sanatoase.
                        failedDestinations.Add(dst);
                    }
                }
            }
        }
        catch (Exception ex)
        {
            readError = ex;
        }
        finally
        {
            foreach (var q in queues.Values)
            {
                try { q.CompleteAdding(); } catch (InvalidOperationException) { /* deja completat de esec */ }
            }
        }

        Task.WaitAll(tasks);

        if (readError != null) throw readError;

        return new FanOutResult
        {
            SourceHash = sourceHasher.FinalizeHex(),
            BytesRead = bytesRead,
            Destinations = results.ToDictionary(kv => kv.Key, kv => kv.Value),
        };
    }
}
