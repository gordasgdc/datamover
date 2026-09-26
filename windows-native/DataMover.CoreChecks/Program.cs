using DataMover.Core.Services;

// Verificari de integritate pentru FanOutCopier (paritate cu testele Swift).
// Ruleaza numai in directoare temporare. Iesire 0 = toate trec.
var failures = 0;
void Check(string name, bool ok) { Console.WriteLine($"{(ok ? "✓" : "✗")} {name}"); if (!ok) failures++; }

string Tmp() { var p = Path.Combine(Path.GetTempPath(), "dm-checks-" + Guid.NewGuid()); Directory.CreateDirectory(p); return p; }
string MakeFile(string dir, string name, int bytes, byte seed = 7)
{
    var p = Path.Combine(dir, name);
    var data = new byte[bytes];
    for (int i = 0; i < bytes; i++) data[i] = (byte)(i * 31 + seed);
    File.WriteAllBytes(p, data);
    return p;
}
FanOutCopier C(string src, List<string> d, long? expected, VerificationModel m = VerificationModel.XxHash64, CancelToken? t = null)
    => new(src, d, 64 * 1024, m, t ?? new CancelToken(), new PauseToken(), expectedSize: expected);
bool NoPartials(string root) => !Directory.EnumerateFiles(root, "*" + PartialFile.Suffix, SearchOption.AllDirectories).Any();

var root = Tmp();
try
{
    var src = MakeFile(root, "a.bin", 300_000);
    var d1 = Path.Combine(Directory.CreateDirectory(Path.Combine(root, "d1")).FullName, "a.bin");
    var d2 = Path.Combine(Directory.CreateDirectory(Path.Combine(root, "d2")).FullName, "a.bin");
    var r = C(src, new() { d1, d2 }, 300_000).Run(_ => { });
    Check("copie simpla, doua destinatii, confirmata", r.Destinations[d1].Verified && r.Destinations[d2].Verified
        && File.ReadAllBytes(d1).SequenceEqual(File.ReadAllBytes(src)) && NoPartials(root));

    var d3 = Path.Combine(root, "d1", "b.bin");
    var r2 = C(src, new() { d3 }, 12345).Run(_ => { });
    Check("sursa modificata -> neconfirmat, fara fisier final", !r2.Destinations[d3].Verified && !File.Exists(d3) && NoPartials(root));

    var preexisting = MakeFile(Path.Combine(root, "d2"), "c.bin", 50, 9);
    var before = File.ReadAllBytes(preexisting);
    C(src, new() { preexisting }, 1).Run(_ => { });
    Check("fisier final preexistent pastrat la nepotrivire", File.ReadAllBytes(preexisting).SequenceEqual(before));

    var d4 = Path.Combine(root, "d1", "s.bin");
    var r4 = C(src, new() { d4 }, 10, VerificationModel.SizeOnly).Run(_ => { });
    Check("doar-marime nu confirma automat", !r4.Destinations[d4].Verified);

    var empty = MakeFile(root, "empty.wav", 0);
    var d5 = Path.Combine(root, "d1", "empty.wav");
    var r5 = C(empty, new() { d5 }, 0).Run(_ => { });
    Check("fisier de 0 octeti", r5.Destinations[d5].Verified && File.Exists(d5));

    var gone = Path.Combine(root, "missing-volume", "a.bin");
    var d6 = Path.Combine(root, "d2", "ok.bin");
    var bigSrc = MakeFile(root, "big.bin", 2_000_000);
    var r6 = C(bigSrc, new() { gone, d6 }, 2_000_000).Run(_ => { });
    Check("destinatie disparuta nu blocheaza/strica cealalta", !r6.Destinations[gone].Success && r6.Destinations[d6].Verified);

    var t = new CancelToken(); t.Cancel();
    var d7 = Path.Combine(root, "d1", "x.bin");
    try { C(src, new() { d7 }, 300_000, t: t).Run(_ => { }); Check("anulare arunca", false); }
    catch (OffloadCancelledException) { Check("anulare: fara final, fara partial", !File.Exists(d7) && NoPartials(root)); }

    // --- Destinatie care esueaza in timpul fan-out: fara deadlock -------------
    {
        var big = MakeFile(root, "fan.bin", 64 * 4096);
        var good = Path.Combine(root, "d1", "fan.bin");
        var bad = Path.Combine(root, "d2", "fan.bin");
        var copier = new FanOutCopier(big, new List<string> { good, bad }, 4096, VerificationModel.XxHash64,
            new CancelToken(), new PauseToken(), ringDepth: 2, expectedSize: 64 * 4096,
            openOutput: (part, final) => final == bad
                ? new FailingStream(new FileStream(part, FileMode.Create), failAtWrite: 3)
                : new FileStream(part, FileMode.Create));
        var task = Task.Run(() => copier.Run(_ => { }));
        bool finished = task.Wait(TimeSpan.FromSeconds(10));
        Check("writer esuat la a 3-a scriere: fan-out se termina (<10 s), fara deadlock", finished);
        if (finished)
        {
            var fr = task.Result;
            Check("  destinatia buna confirmata", fr.Destinations[good].Verified);
            Check("  destinatia defecta: eroare, fara fisier final, fara partial",
                !fr.Destinations[bad].Success && fr.Destinations[bad].Error is IOException && !File.Exists(bad) && NoPartials(root));
        }
    }

    // --- Checkpoint: identitate, validare, scriere atomica ---------------------
    {
        var a = Directory.CreateDirectory(Path.Combine(root, "A", "CLIP")).FullName;
        var b = Directory.CreateDirectory(Path.Combine(root, "B", "CLIP")).FullName;
        MakeFile(a, "x.mov", 100, 1); MakeFile(b, "x.mov", 100, 2);
        var rootA = Path.Combine(root, "A"); var rootB = Path.Combine(root, "B");
        var idA = SourceIdentity.Compute(new[] { rootA }, FileScanner.ListAllFiles(rootA, Array.Empty<string>()));
        var idB = SourceIdentity.Compute(new[] { rootB }, FileScanner.ListAllFiles(rootB, Array.Empty<string>()));
        Check("identitate: aceleasi nume si marimi, alta sursa -> diferita", !idA.SameAs(idB));
        File.SetLastWriteTimeUtc(Path.Combine(a, "x.mov"), DateTime.UtcNow.AddHours(1));
        File.WriteAllBytes(Path.Combine(a, "x.mov"), File.ReadAllBytes(Path.Combine(b, "x.mov")));
        File.SetLastWriteTimeUtc(Path.Combine(a, "x.mov"), DateTime.UtcNow.AddHours(2));
        var idA2 = SourceIdentity.Compute(new[] { rootA }, FileScanner.ListAllFiles(rootA, Array.Empty<string>()));
        Check("identitate: aceeasi cale, continut inlocuit -> diferita", !idA.SameAs(idA2));

        var target = Directory.CreateDirectory(Path.Combine(root, "dest", "JOB")).FullName;
        Check("checkpoint salvat fara eroare, fara .tmp ramas",
            CheckpointStore.Save(target, "JOB", "xxhash64", idA2, new() { ["CLIP/x.mov"] = "ok" }, new() { ["CLIP/x.mov"] = "100:1" }, false) == null
            && !File.Exists(CheckpointStore.PathFor(target) + ".tmp"));
        Check("checkpoint valid pentru aceeasi identitate", CheckpointStore.LoadValidated(target, "JOB", "xxhash64", idA2).Kind == CheckpointLoadKind.Valid);
        Check("checkpoint respins pentru alta sursa", CheckpointStore.LoadValidated(target, "JOB", "xxhash64", idB).Kind == CheckpointLoadKind.Rejected);
        Check("checkpoint respins pentru alt model", CheckpointStore.LoadValidated(target, "JOB", "md5", idA2).Kind == CheckpointLoadKind.Rejected);
        Check("checkpoint respins pentru alt folder", CheckpointStore.LoadValidated(target, "ALT", "xxhash64", idA2).Kind == CheckpointLoadKind.Rejected);
        File.WriteAllText(CheckpointStore.PathFor(target), "{nu e json");
        Check("checkpoint corupt respins", CheckpointStore.LoadValidated(target, "JOB", "xxhash64", idA2).Reason == "fișier corupt");
        File.WriteAllText(CheckpointStore.PathFor(target), "{\"folder_name\":\"JOB\",\"verification_model\":\"xxhash64\",\"files\":{\"CLIP/x.mov\":\"ok\"}}");
        Check("checkpoint vechi (fara identitate) respins", CheckpointStore.LoadValidated(target, "JOB", "xxhash64", idA2).Kind == CheckpointLoadKind.Rejected);

        var entry = FileScanner.ListAllFiles(rootA, Array.Empty<string>())[0];
        var destFile = Path.Combine(target, "CLIP", "x.mov");
        Check("CanSkip fals: destinatie absenta", !CheckpointStore.CanSkip("ok", entry.Stamp, entry, destFile));
        Directory.CreateDirectory(Path.GetDirectoryName(destFile)!);
        File.WriteAllBytes(destFile, new byte[99]);
        Check("CanSkip fals: marime diferita", !CheckpointStore.CanSkip("ok", entry.Stamp, entry, destFile));
        File.WriteAllBytes(destFile, new byte[100]);
        Check("CanSkip fals: amprenta sursei diferita", !CheckpointStore.CanSkip("ok", "100:1", entry, destFile));
        Check("CanSkip fals: stare fail", !CheckpointStore.CanSkip("fail", entry.Stamp, entry, destFile));
        Check("CanSkip adevarat doar cu toate conditiile", CheckpointStore.CanSkip("ok", entry.Stamp, entry, destFile));
    }
}
finally { Directory.Delete(root, true); }

Console.WriteLine(failures == 0 ? "TOATE VERIFICARILE AU TRECUT" : $"{failures} ESECURI");
return failures == 0 ? 0 : 1;


/// Stream care arunca IOException la a N-a scriere (simuleaza disc plin /
/// deconectat), fara a atinge volume reale.
sealed class FailingStream : Stream
{
    private readonly Stream _inner; private readonly int _failAt; private int _writes;
    public FailingStream(Stream inner, int failAtWrite) { _inner = inner; _failAt = failAtWrite; }
    public override void Write(byte[] buffer, int offset, int count)
    {
        if (++_writes >= _failAt) throw new IOException("scriere simulata esuata (ENOSPC)");
        _inner.Write(buffer, offset, count);
    }
    public override bool CanRead => false; public override bool CanSeek => false; public override bool CanWrite => true;
    public override long Length => _inner.Length; public override long Position { get => _inner.Position; set => _inner.Position = value; }
    public override void Flush() => _inner.Flush();
    public override int Read(byte[] b, int o, int c) => throw new NotSupportedException();
    public override long Seek(long o, SeekOrigin s) => throw new NotSupportedException();
    public override void SetLength(long v) => throw new NotSupportedException();
    protected override void Dispose(bool d) { if (d) _inner.Dispose(); base.Dispose(d); }
}
