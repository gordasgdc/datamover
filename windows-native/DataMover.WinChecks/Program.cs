using System.Diagnostics;
using System.Security.Cryptography;
using DataMover.Core.Diagnostics;
using DataMover.Core.Services;

// Verificari cap-coada pe Windows real (NTFS). Totul in %TEMP%\dm-winchecks-*;
// istoricul utilizatorului nu e atins (SideEffectsEnabled = false).
// Iesire 0 = toate trec. Rezultatul se scrie si in winchecks-result.txt.
var failures = 0;
var lines = new List<string>();
void Check(string name, bool ok) { var l = $"{(ok ? "PASS" : "FAIL")} {name}"; Console.WriteLine(l); lines.Add(l); if (!ok) failures++; }

var root = Path.Combine(Path.GetTempPath(), "dm-winchecks-" + Guid.NewGuid().ToString("N")[..8]);
Directory.CreateDirectory(root);
OffloadRunner.SideEffectsEnabled = false;
StructuredLog.Shared = new StructuredLog(new StructuredLog.Config(Path.Combine(root, "log")));

string Make(string rel, int bytes, byte seed = 7)
{
    var p = Path.Combine(root, rel);
    Directory.CreateDirectory(Path.GetDirectoryName(p)!);
    var data = new byte[bytes];
    for (int i = 0; i < bytes; i++) data[i] = (byte)(i * 31 + seed);
    File.WriteAllBytes(p, data);
    return p;
}
string Sha(string p) => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(p)));
string Dir(string rel) => Directory.CreateDirectory(Path.Combine(root, rel)).FullName;

OffloadRunner Run(List<string> sources, List<string> dests, bool resume = false, int timeoutSec = 60)
{
    var r = new OffloadRunner();
    r.Start(sources, dests, VerificationModel.XxHash64, new List<string>(), resume, new ProductionMeta(),
        folderNameOverride: "JOB", appVersion: "winchecks");
    var sw = Stopwatch.StartNew();
    while (r.IsRunning && sw.Elapsed.TotalSeconds < timeoutSec) Thread.Sleep(20);
    if (r.IsRunning) Check($"transfer terminat in {timeoutSec}s (fara blocaj)", false);
    return r;
}

try
{
    Console.WriteLine($"Windows: {System.Runtime.InteropServices.RuntimeInformation.OSDescription} · {System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture}");

    // 1. Transfer simplu, doua destinatii, jurnal corelat.
    Make(@"CARD\CLIP\A001.mov", 300_000, 1); Make(@"CARD\CLIP\A002.mov", 120_000, 2); Make(@"CARD\EMPTY.wav", 0);
    var src = Path.Combine(root, "CARD");
    var a = Dir("A"); var b = Dir("B");
    var r1 = Run(new() { src }, new() { a, b });
    Check("transfer 2 destinatii: 0 erori, 3 fisiere la fiecare", r1.LastResults.Count == 2 && r1.LastResults.All(x => x.FailCount == 0 && x.OkCount == 3));
    Check("continut identic (SHA-256) si fara .dmpart", Sha(Path.Combine(a, @"JOB\CLIP\A001.mov")) == Sha(Path.Combine(src, @"CLIP\A001.mov"))
        && !Directory.EnumerateFiles(a, "*.dmpart", SearchOption.AllDirectories).Any());
    var logText = File.ReadAllText(StructuredLog.Shared.FilePath);
    Check("jurnal: job.started + 2 x destination.result + job.finished cu acelasi job ID",
        logText.Contains($"\"job\":\"{r1.JobId}\"") && logText.Split("destination.result").Length - 1 == 2 && logText.Contains("job.finished"));

    // 2. Reluare byte-safe: copie modificata cu aceeasi marime -> recopiata.
    var copy = Path.Combine(a, @"JOB\CLIP\A002.mov");
    var t = File.GetLastWriteTimeUtc(copy);
    File.WriteAllBytes(copy, new byte[new FileInfo(copy).Length]); File.SetLastWriteTimeUtc(copy, t);
    var r2 = Run(new() { src }, new() { a }, resume: true);
    Check("reluare: copia alterata (aceeasi marime) e detectata si recopiata", Sha(copy) == Sha(Path.Combine(src, @"CLIP\A002.mov")) && r2.LastResults[0].FailCount == 0);

    // 3. Coliziune de nume intre surse -> blocat, nimic scris.
    Make(@"C1\CLIP\X.mov", 1000, 3); Make(@"C2\clip\x.MOV", 1000, 4);
    var cd = Dir("COLL");
    var r3 = new OffloadRunner();
    r3.Start(new() { Path.Combine(root, "C1"), Path.Combine(root, "C2") }, new() { cd }, VerificationModel.XxHash64,
        new List<string>(), false, new ProductionMeta(), folderNameOverride: "JOB");
    Check("coliziune de nume: blocat inainte de orice scriere", !r3.IsRunning && r3.LastCollisions.Count == 1 && !Directory.Exists(Path.Combine(cd, "JOB")));

    // 4a. Unitate lipsa la pornire: refuzat de preflight, nimic scris.
    var missing = Enumerable.Range('F', 20).Select(c => $"{(char)c}:\\").First(d => !Directory.Exists(d));
    var ok4 = Dir("OK4");
    var r4 = new OffloadRunner();
    r4.Start(new() { src }, new() { ok4, Path.Combine(missing, "DM-TEST") }, VerificationModel.XxHash64, new List<string>(), false,
        new ProductionMeta(), folderNameOverride: "JOB");
    Check($"destinatie pe unitate lipsa ({missing}) la pornire: blocat de preflight, nimic scris",
        !r4.IsRunning && r4.LastPreflight.Any(i => i.Code == DataMover.Core.Domain.PreflightCode.DestinationMissing) && !Directory.Exists(Path.Combine(ok4, "JOB")));

    // 4b. Deconectare in timpul transferului: unitate virtuala (subst) scoasa
    // din mers. Transferul se termina, copia ramasa e verificata, cealalta nu.
    var letter = Enumerable.Range('K', 14).Select(c => $"{(char)c}:").First(d => !Directory.Exists(d + "\\"));
    var substTarget = Dir("SUBST");
    void Subst(string args) { var p = Process.Start(new ProcessStartInfo("subst.exe", args) { CreateNoWindow = true, UseShellExecute = false })!; p.WaitForExit(); }
    Subst($"{letter} \"{substTarget}\"");
    try
    {
        for (int i = 0; i < 40; i++) Make($@"BIG\CLIP\B{i:D3}.mov", 4_000_000, (byte)i);
        var ok4b = Dir("OK4B");
        var r4b = new OffloadRunner();
        r4b.Start(new() { Path.Combine(root, "BIG") }, new() { ok4b, letter + "\\" }, VerificationModel.XxHash64, new List<string>(), false,
            new ProductionMeta(), folderNameOverride: "JOB");
        var sw4 = Stopwatch.StartNew();
        while (r4b.IsRunning && r4b.ProgressPercent < 10 && sw4.Elapsed.TotalSeconds < 60) Thread.Sleep(10);
        var cutAt = r4b.ProgressPercent;
        Subst($"{letter} /D");
        while (r4b.IsRunning && sw4.Elapsed.TotalSeconds < 120) Thread.Sleep(20);
        var okRes = r4b.LastResults.FirstOrDefault(x => x.DestRoot.StartsWith(ok4b, StringComparison.OrdinalIgnoreCase));
        var cutRes = r4b.LastResults.FirstOrDefault(x => x.DestRoot.StartsWith(letter, StringComparison.OrdinalIgnoreCase));
        Check($"deconectare la {cutAt}% ({letter} scoasa): transfer terminat, copia locala verificata (40/40), cea deconectata cu esecuri",
            !r4b.IsRunning && cutAt < 100 && okRes is { FailCount: 0, OkCount: 40 } && cutRes is { FailCount: > 0 });
    }
    finally { Subst($"{letter} /D"); }

    // 5. Junction la destinatie care duce in afara tintei -> refuzat.
    Make(@"JCARD\CLIP\j.mov", 5000, 5);
    var jd = Dir("JD"); var outside = Dir("OUTSIDE"); Directory.CreateDirectory(Path.Combine(jd, "JOB"));
    var mk = Process.Start(new ProcessStartInfo("cmd.exe", $"/c mklink /J \"{Path.Combine(jd, "JOB", "CLIP")}\" \"{outside}\"") { CreateNoWindow = true, UseShellExecute = false });
    mk!.WaitForExit();
    var r5 = Run(new() { Path.Combine(root, "JCARD") }, new() { jd });
    Check("junction spre exterior: nimic scris in afara tintei, fisier neconfirmat",
        !Directory.EnumerateFileSystemEntries(outside).Any() && r5.LastResults[0].FailCount == 1);

    // 6. Nume Unicode (separat) si cale lunga (separat), cu diagnostic.
    string Csv(OffloadRunner r) => r.LastResults.Count > 0 && r.LastResults[0].CsvPath is string c && File.Exists(c)
        ? string.Join(" | ", File.ReadAllLines(c).Skip(1).Where(l => !l.Contains(",OK")).Take(3)) : "(fara CSV)";
    var names = new[] { "Clip ș ț ă î â — ✓.mov", "日本語 テスト.mxf", "Ünïcödé Ωmega.wav" };
    for (int i = 0; i < names.Length; i++) Make(Path.Combine("UCARD", names[i]), 4000 + i * 100, (byte)i);
    var ud = Dir("U");
    var r6 = Run(new() { Path.Combine(root, "UCARD") }, new() { ud });
    var ok6 = r6.LastResults[0].OkCount == names.Length && names.All(n => Sha(Path.Combine(ud, "JOB", n)) == Sha(Path.Combine(root, "UCARD", n)));
    Check("nume Unicode pe NTFS: toate confirmate, continut identic" + (ok6 ? "" : " — " + Csv(r6)), ok6);

    var deep = string.Join("\\", Enumerable.Range(0, 6).Select(i => $"Nivel_{i}_" + new string('x', 40)));
    var longRel = Path.Combine("LCARD", deep, "lung.mov");
    Make(longRel, 3000, 9);
    var ld = Dir("L");
    var r7 = Run(new() { Path.Combine(root, "LCARD") }, new() { ld });
    var destLong = Path.Combine(ld, "JOB", deep, "lung.mov");
    var ok7 = r7.LastResults[0].OkCount == 1 && File.Exists(destLong);
    Check($"cale lunga ({destLong.Length} caractere, peste MAX_PATH 260): confirmata" + (ok7 ? "" : " — " + Csv(r7)), ok7);

    // 7. Export de diagnostic pe Windows: fara cai si fara secrete.
    StructuredLog.Shared.Log(LogLevel.Error, "t", "t.secret", $"licenta license=GDC1-SECRET1 la {src}");
    var zip = new DiagnosticExporter(StructuredLog.Shared, new Dictionary<string, string> { ["verification"] = "xxhash64" })
        .Export(Path.Combine(root, "exports"));
    using (var za = System.IO.Compression.ZipFile.OpenRead(zip))
    {
        var all = string.Join("\n", za.Entries.Where(e => e.Length > 0).Select(e => new StreamReader(e.Open()).ReadToEnd()));
        Check("export diagnostic: fara cai locale, fara licenta, cu manifest",
            !all.Contains(root, StringComparison.OrdinalIgnoreCase) && !all.Contains("GDC1-SECRET1") && za.Entries.Any(e => e.FullName.EndsWith("manifest.json")));
    }
}
catch (Exception ex) { Check("exceptie neasteptata: " + ex.GetType().Name + " " + ex.Message, false); }
finally
{
    try { Directory.Delete(root, true); } catch { }
}
lines.Add(failures == 0 ? "TOATE VERIFICARILE WINDOWS AU TRECUT" : $"{failures} ESECURI");
Console.WriteLine(lines[^1]);
File.WriteAllLines(Path.Combine(AppContext.BaseDirectory, "winchecks-result.txt"), lines);
return failures == 0 ? 0 : 1;
