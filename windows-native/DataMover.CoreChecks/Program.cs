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
}
finally { Directory.Delete(root, true); }

Console.WriteLine(failures == 0 ? "TOATE VERIFICARILE AU TRECUT" : $"{failures} ESECURI");
return failures == 0 ? 0 : 1;
