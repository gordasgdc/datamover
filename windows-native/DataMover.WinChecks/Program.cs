using Org.BouncyCastle.Crypto.Generators;
using Org.BouncyCastle.Crypto.Parameters;
using Org.BouncyCastle.Crypto.Signers;
using Org.BouncyCastle.Security;
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

    // 6b. Fisier blocat exclusiv de alt proces (FileShare.None): doar el e
    // neconfirmat, restul se copiaza; verdictul nu poate fi „succes”.
    Make(@"LOCK\ok.mov", 50_000, 1); var lockedPath = Make(@"LOCK\locked.mov", 50_000, 2);
    var lkd = Dir("LK");
    OffloadRunner r8;
    using (new FileStream(lockedPath, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        r8 = Run(new() { Path.Combine(root, "LOCK") }, new() { lkd });
    var d8 = r8.LastResults.Count == 1 ? $" [ok={r8.LastResults[0].OkCount} fail={r8.LastResults[0].FailCount} final={File.Exists(Path.Combine(lkd, "JOB", "locked.mov"))} part={Directory.EnumerateFiles(lkd, "*.dmpart", SearchOption.AllDirectories).Count()} csv={Csv(r8)}]" : $" [rezultate={r8.LastResults.Count}]";
    Check("fisier blocat de alt proces: neconfirmat, celalalt confirmat, nicio copie partiala" + d8,
        r8.LastResults.Count == 1 && r8.LastResults[0].OkCount == 1 && r8.LastResults[0].FailCount == 1
        && !File.Exists(Path.Combine(lkd, "JOB", "locked.mov")) && !Directory.EnumerateFiles(lkd, "*.dmpart", SearchOption.AllDirectories).Any());

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
    // Licențe generația 2, cap-coadă pe Windows real (cheie Ed25519 de TEST, niciodată cheia reală).
    {
        var gen = new Ed25519KeyPairGenerator(); gen.Init(new Ed25519KeyGenerationParameters(new SecureRandom()));
        var kp = gen.GenerateKeyPair();
        var priv = (Ed25519PrivateKeyParameters)kp.Private;
        var pubB64 = Convert.ToBase64String(((Ed25519PublicKeyParameters)kp.Public).GetEncoded());
        var me = new byte[] { 1, 2, 3, 4, 5, 6 };
        string Serial(string product, long expires, byte[] machine)
        {
            var p = new List<byte>(LicenseRules.ProductHash(product));
            for (int i = 7; i >= 0; i--) p.Add((byte)((expires >> (8 * i)) & 0xFF));
            p.AddRange(new byte[] { 7, 7, 7, 7 }); p.AddRange(machine);
            var signer = new Ed25519Signer(); signer.Init(true, priv); signer.BlockUpdate(p.ToArray(), 0, p.Count);
            return LicenseCore.Base32Encode(p.Concat(signer.GenerateSignature()).ToArray());
        }
        var lic = new List<string>();
        LicenseManager Mgr(string dir, bool revoked = false) => new(dir, pubB64, me, () => DateTimeOffset.UtcNow, () => revoked,
            (e, f) => lic.Add(e + " " + string.Join(",", f.Select(kv => kv.Key + "=" + kv.Value))));
        long nowU = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var legacy = Serial(LicenseRules.CanonicalProductId, 0, me);
        var good = Serial(LicenseRules.SigningProductId, nowU + 86400 * 30, me);

        var d1 = Dir("LIC1");
        File.WriteAllText(Path.Combine(d1, "license.txt"), legacy);
        var m1 = Mgr(d1);
        Check("licenta: cod legacy salvat -> reactivare necesara, fara proba noua, cod pastrat in copie",
            m1.State == LicenseState.LegacyNeedsReactivation && !m1.IsTrialActive && !m1.HasFullAccess
            && !File.Exists(Path.Combine(d1, "license.txt")) && File.ReadAllText(Path.Combine(d1, "license-legacy-v1.txt")) == legacy);
        Check("licenta: cod legacy reintrodus -> refuzat de doua ori", !m1.Activate(legacy) && !m1.Activate(legacy) && !m1.HasFullAccess);
        Check("licenta: generatia 2 pe acest calculator -> acceptata, valida si dupa repornire (offline)",
            m1.Activate(good) && m1.HasFullAccess && Mgr(d1).HasFullAccess);
        var m2 = Mgr(Dir("LIC2"));
        Check("licenta: instalare noua pastreaza proba", m2.State == LicenseState.Trial && m2.IsTrialActive);
        Check("licenta: alt calculator / expirata / fara calculator -> refuzate",
            !m2.Activate(Serial(LicenseRules.SigningProductId, 0, new byte[] { 9, 9, 9, 9, 9, 9 }))
            && !m2.Activate(Serial(LicenseRules.SigningProductId, nowU - 10, me))
            && !m2.Activate(Serial(LicenseRules.SigningProductId, 0, new byte[6])) && !m2.HasFullAccess);
        var logged = string.Join("\n", lic) + File.ReadAllText(StructuredLog.Shared.FilePath);
        Check("licenta: serialul nu apare in jurnale", lic.Count > 0 && !logged.Contains(legacy) && !logged.Contains(good) && !logged.Contains(good[..20]));

        // Revocată: codul e valid local, dar accesul efectiv e retras -> plafonul de 2 GB rămâne.
        var mr = Mgr(Dir("LIC3"), revoked: true);
        Check("licenta: revocata -> stare Revoked, fara acces complet", mr.Activate(good) && mr.State == LicenseState.Revoked && !mr.HasFullAccess);
        var bigDir = Dir("CAPSRC");
        using (var fs = File.Create(Path.Combine(bigDir, "huge.mov"))) fs.SetLength(LicenseManager.TrialMaxTransferBytes + 1);
        var capDst = Dir("CAPDST");
        var prev = OffloadRunner.FullAccess;
        OffloadRunner.FullAccess = () => mr.HasFullAccess;
        var rc = Run(new() { bigDir }, new() { capDst });
        OffloadRunner.FullAccess = prev;
        Check("licenta: Windows revocat nu porneste un transfer peste plafon",
            rc.TrialLimitExceededBytes > LicenseManager.TrialMaxTransferBytes && !Directory.EnumerateFiles(capDst, "*", SearchOption.AllDirectories).Any());
        File.Delete(Path.Combine(bigDir, "huge.mov"));
    }
}
catch (Exception ex) { Check("exceptie neasteptata: " + ex.GetType().Name + " " + ex.Message, false); }
finally
{
    // Jurnalul si firele runner-elor pot tine inca fisiere deschise cateva
    // sute de ms; se reincearca, iar un esec final se raporteaza, nu se ascunde.
    StructuredLog.Shared = new StructuredLog(new StructuredLog.Config(Path.Combine(Path.GetTempPath(), "dm-winchecks-log")));
    for (int i = 0; i < 10 && Directory.Exists(root); i++)
    {
        try { Directory.Delete(root, true); } catch { GC.Collect(); GC.WaitForPendingFinalizers(); Thread.Sleep(500); }
    }
    if (Directory.Exists(root)) Console.WriteLine($"ATENTIE: folderul temporar {root} nu s-a putut sterge");
}
// Rapoarte PDF randate pe Windows real (QuestPDF/Skia), cele 6 scenarii x RO/EN/ES.
{
    var outDir = Path.Combine(AppContext.BaseDirectory, "report-samples");
    Directory.CreateDirectory(outDir);
    int made = 0; bool ok = true;
    foreach (var lang in new[] { "ro", "en", "es" })
        foreach (var (name, r) in ReportScenarios.All(lang))
        {
            try { var p = Path.Combine(outDir, $"{name}-{lang}.pdf"); PdfReport.Write(r, p); if (new FileInfo(p).Length > 1000) made++; else ok = false; }
            catch (Exception ex) { ok = false; Console.WriteLine($"PDF {name}-{lang}: {ex.Message}"); }
        }
    Check($"raport PDF: {made}/18 mostre generate pe Windows", ok && made == 18);
}
lines.Add(failures == 0 ? "TOATE VERIFICARILE WINDOWS AU TRECUT" : $"{failures} ESECURI");
Console.WriteLine(lines[^1]);
File.WriteAllLines(Path.Combine(AppContext.BaseDirectory, "winchecks-result.txt"), lines);
return failures == 0 ? 0 : 1;
