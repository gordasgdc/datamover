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
        var h = new string('a', 16); // xxhash64 bine format
        var proofs = new Dictionary<string, FileProof> { ["CLIP/x.mov"] = new FileProof(h, h, "checksum") };
        Check("checkpoint schema 3 salvat fara eroare, fara .tmp ramas",
            CheckpointStore.Save(target, "JOB", "xxhash64", idA2, new() { ["CLIP/x.mov"] = "ok" }, new() { ["CLIP/x.mov"] = "100:1" }, proofs, false) == null
            && !File.Exists(CheckpointStore.PathFor(target) + ".tmp"));
        Check("checkpoint valid pentru aceeasi identitate", CheckpointStore.LoadValidated(target, "JOB", "xxhash64", idA2).Kind == CheckpointLoadKind.Valid);
        Check("checkpoint respins pentru alta sursa", CheckpointStore.LoadValidated(target, "JOB", "xxhash64", idB).Kind == CheckpointLoadKind.Rejected);
        Check("checkpoint respins pentru algoritm schimbat", CheckpointStore.LoadValidated(target, "JOB", "md5", idA2).Kind == CheckpointLoadKind.Rejected);
        Check("checkpoint respins pentru alt folder", CheckpointStore.LoadValidated(target, "ALT", "xxhash64", idA2).Kind == CheckpointLoadKind.Rejected);
        CheckpointStore.Save(target, "JOB", "xxhash64", idA2, new() { ["CLIP/x.mov"] = "ok" }, new() { ["CLIP/x.mov"] = "100:1" }, new(), false);
        Check("checkpoint respins: checksum absent", CheckpointStore.LoadValidated(target, "JOB", "xxhash64", idA2).Reason?.Contains("absent") == true);
        CheckpointStore.Save(target, "JOB", "xxhash64", idA2, new() { ["CLIP/x.mov"] = "ok" }, new() { ["CLIP/x.mov"] = "100:1" },
            new() { ["CLIP/x.mov"] = new FileProof("XYZ", "XYZ", "checksum") }, false);
        Check("checkpoint respins: checksum corupt", CheckpointStore.LoadValidated(target, "JOB", "xxhash64", idA2).Reason?.Contains("corupt") == true);
        File.WriteAllText(CheckpointStore.PathFor(target), "{nu e json");
        Check("checkpoint corupt respins", CheckpointStore.LoadValidated(target, "JOB", "xxhash64", idA2).Reason == "fișier corupt");
        File.WriteAllText(CheckpointStore.PathFor(target), "{\"schema\":2,\"folder_name\":\"JOB\",\"verification_model\":\"xxhash64\",\"files\":{\"CLIP/x.mov\":\"ok\"},\"file_stamps\":{}}");
        Check("checkpoint schema 2 (fara dovada de continut) respins", CheckpointStore.LoadValidated(target, "JOB", "xxhash64", idA2).Reason?.Contains("format vechi") == true);

        // --- Byte-safe: aceeasi metadata, alti octeti ---------------------------
        var card = Directory.CreateDirectory(Path.Combine(root, "C")).FullName;
        var clip = MakeFile(card, "c.mov", 50_000, 3);
        var dstDir = Directory.CreateDirectory(Path.Combine(root, "Cdst")).FullName;
        var copy = Path.Combine(dstDir, "c.mov"); File.Copy(clip, copy);
        var mt = File.GetLastWriteTimeUtc(clip);
        var original = FileHashing.HashOfFile(clip, VerificationModel.XxHash64, 4096);
        var idBefore = SourceIdentity.Compute(new[] { card }, FileScanner.ListAllFiles(card, Array.Empty<string>()), _ => "VOL-1");
        var e0 = FileScanner.ListAllFiles(card, Array.Empty<string>())[0];
        var proofC = new FileProof(original, original, "checksum");
        Check("revalidare: sursa si destinatia neschimbate -> acceptat DOAR dupa recitire",
            RevalidationPolicy.Revalidate(clip, copy, CheckpointStore.ExpectedSourceHash("ok", e0.Stamp, proofC, e0, copy),
                VerificationModel.XxHash64, 4096, new CancelToken()).Reason == null);
        var bytes = File.ReadAllBytes(clip); for (int i = 0; i < bytes.Length; i++) bytes[i] ^= 0x5A;
        File.WriteAllBytes(clip, bytes); File.SetLastWriteTimeUtc(clip, mt);
        var idAfter = SourceIdentity.Compute(new[] { card }, FileScanner.ListAllFiles(card, Array.Empty<string>()), _ => "VOL-1");
        var e1 = FileScanner.ListAllFiles(card, Array.Empty<string>())[0];
        Check("metadata identica (cale, volum injectat, marime, mtime) -> identitate identica", idBefore.SameAs(idAfter) && e1.Stamp == e0.Stamp);
        var exp1 = CheckpointStore.ExpectedSourceHash("ok", e1.Stamp, proofC, e1, copy);
        Check("metadata coerenta NU acorda verdictul: sursa cu alti octeti -> recopiere",
            RevalidationPolicy.Revalidate(clip, copy, exp1, VerificationModel.XxHash64, 4096, new CancelToken()).Reason?.Contains("sursa diferă") == true);
        File.WriteAllBytes(clip, File.ReadAllBytes(copy)); File.SetLastWriteTimeUtc(clip, mt); // sursa inapoi la original
        var tampered = File.ReadAllBytes(copy); tampered[100] ^= 0xFF; File.WriteAllBytes(copy, tampered);
        Check("destinatie modificata (aceeasi marime) -> recopiere",
            RevalidationPolicy.Revalidate(clip, copy, original, VerificationModel.XxHash64, 4096, new CancelToken()).Reason?.Contains("destinația diferă") == true);
        var z = MakeFile(card, "z.wav", 0); var zc = Path.Combine(dstDir, "z.wav"); File.WriteAllBytes(zc, Array.Empty<byte>());
        var zh = FileHashing.HashOfFile(z, VerificationModel.XxHash64, 4096);
        Check("fisier de 0 octeti: acceptat prin recitire (hash gol al algoritmului)",
            RevalidationPolicy.Revalidate(z, zc, zh, VerificationModel.XxHash64, 4096, new CancelToken()).Reason == null);
        Check("doar-marime: niciodata acceptat la reluare",
            RevalidationPolicy.Revalidate(clip, clip, null, VerificationModel.SizeOnly, 4096, new CancelToken()).Reason != null);
        Check("ExpectedSourceHash null daca destinatia lipseste", CheckpointStore.ExpectedSourceHash("ok", e0.Stamp, proofC, e0, copy + ".nu") == null);
        Check("ExpectedSourceHash null daca stare fail", CheckpointStore.ExpectedSourceHash("fail", e0.Stamp, proofC, e0, copy) == null);
    }

    // --- Observabilitate --------------------------------------------------------
    {
        var raw = "user dumitru@example.com license=GDC1-ABCD token: abc.def password \"hunter2\" key K3yZx9QvLm2Np7Rt5Wu8Yb4Cd6 C:\\Users\\johndoe\\Videos\\x.mov";
        var red = DataMover.Core.Diagnostics.Redactor.RedactSecrets(raw);
        Check("redactare: email, licenta, token, parola, cheie lunga, profil utilizator",
            new[] { "dumitru@example.com", "GDC1-ABCD", "abc.def", "hunter2", "K3yZx9QvLm2Np7Rt5Wu8Yb4Cd6", "johndoe" }.All(x => !red.Contains(x)));
        var an = DataMover.Core.Diagnostics.Redactor.AnonymizePaths(@"copiat D:\CLIENT\A001C001.mov si /Volumes/A001/CLIP/A001C001.mov");
        Check("anonimizare cai (Windows + POSIX), extensie pastrata", !an.Contains("A001C001") && !an.Contains("CLIENT") && an.Contains(".mov"));
        var fr = DataMover.Core.Diagnostics.Redactor.RedactFields(new Dictionary<string, string> { ["token"] = "tok", ["path"] = "x" });
        Check("camp sensibil dupa cheie -> <redacted>", fr["token"] == "<redacted>" && fr["path"] == "x");

        var logDir = Path.Combine(root, "log");
        var log = new DataMover.Core.Diagnostics.StructuredLog(new(logDir, MaxBytes: 2000, MaxFiles: 3), "sess1234");
        log.Log(DataMover.Core.Diagnostics.LogLevel.Info, "job", "job.started", "x", job: "job1", dest: "d-1");
        log.Log(DataMover.Core.Diagnostics.LogLevel.Debug, "copy", "file.confirmed", "sub prag");
        var first = File.ReadAllLines(log.FilePath);
        Check("inregistrare JSON cu sesiune/job/destinatie, UTC, fara debug implicit",
            first.Length == 1 && first[0].Contains("\"session\":\"sess1234\"") && first[0].Contains("\"job\":\"job1\"") && first[0].Contains("Z\""));
        for (int i = 0; i < 200; i++) log.Log(DataMover.Core.Diagnostics.LogLevel.Info, "t", "t.e", new string('x', 50) + i);
        var files = Directory.GetFiles(logDir);
        Check("rotatie: cel mult 3 fisiere, fiecare <= 2000 octeti", files.Length <= 3 && files.All(f => new FileInfo(f).Length <= 2000));
        var old = log.FilePath + ".2";
        File.SetLastWriteTimeUtc(old, DateTime.UtcNow.AddDays(-30));
        log.Log(DataMover.Core.Diagnostics.LogLevel.Info, "t", "t.e", "retentie");
        Check("retentie: arhiva mai veche de 14 zile stearsa", !File.Exists(old));

        var blocker = MakeFile(root, "blocker", 1);
        var bad = new DataMover.Core.Diagnostics.StructuredLog(new(blocker));
        var sw = System.Diagnostics.Stopwatch.StartNew();
        for (int i = 0; i < 50; i++) bad.Log(DataMover.Core.Diagnostics.LogLevel.Error, "t", "t.e", "nu se poate scrie");
        Check("jurnal nescriptibil: nu arunca, nu blocheaza, spune de ce", sw.ElapsedMilliseconds < 2000 && bad.LastWriteError != null);

        var exLog = new DataMover.Core.Diagnostics.StructuredLog(new(Path.Combine(root, "exlog")), "exp12345");
        var media = MakeFile(root, "SECRET_CLIENT_A001C001.mov", 4096);
        exLog.Log(DataMover.Core.Diagnostics.LogLevel.Error, "copy", "file.failed", $"esec la {media} license=GDC1-XYZ9",
            fields: new Dictionary<string, string> { ["path"] = media, ["token"] = "tok" });
        var zip = new DataMover.Core.Diagnostics.DiagnosticExporter(exLog,
            new Dictionary<string, string> { ["verification"] = "xxhash64", ["licenseCode"] = "GDC-SHOULD-NOT" }).Export(Path.Combine(root, "exports"));
        using (var za = System.IO.Compression.ZipFile.OpenRead(zip))
        {
            var names = za.Entries.Where(e => e.Length > 0).Select(e => e.FullName).ToList();
            var all = string.Join("\n", za.Entries.Where(e => e.Length > 0).Select(e => new StreamReader(e.Open()).ReadToEnd()));
            Check("export: doar .jsonl/.json, fara media", names.All(n => n.EndsWith(".jsonl") || n.EndsWith(".json")) && !names.Any(n => n.EndsWith(".mov")));
            Check("export: fara secrete si fara cai", new[] { "SECRET_CLIENT", "GDC1-XYZ9", "GDC-SHOULD-NOT", "\"tok\"", root }.All(x => !all.Contains(x)));
            Check("export: manifest + sesiune", names.Any(n => n.EndsWith("manifest.json")) && all.Contains("exp12345"));
        }

        // --- Garzi de cale ---------------------------------------------------------
        var fe = new List<DataMover.Core.Models.FileEntry> {
            new("/s1/a.mov", "Clip/A.MOV", 1), new("/s2/a.mov", "clip/a.mov", 1),
            new("/s3/x", "s\u0326.mov", 1), new("/s4/x", "\u0219.mov", 1) };
        Check("coliziuni de nume (majuscule + NFC/NFD)", PathSafety.NameCollisions(fe).Count == 2);
        var tgt = Directory.CreateDirectory(Path.Combine(root, "T", "JOB")).FullName;
        var outside = Directory.CreateDirectory(Path.Combine(root, "OUTSIDE")).FullName;
        try
        {
            Directory.CreateSymbolicLink(Path.Combine(tgt, "CLIP"), outside);
            Check("cale prin symlink/reparse point -> refuzata", !PathSafety.IsInsideTarget(Path.Combine(tgt, "CLIP", "a.mov"), tgt));
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            // Pe Windows, symlink-urile cer Developer Mode/admin; junction-ul e verificat in WinChecks.
            Console.WriteLine("- NEVERIFICAT aici: symlink (privilegiu lipsa) — acoperit de junction in WinChecks");
        }
        Check("cale normala in tinta -> acceptata", PathSafety.IsInsideTarget(Path.Combine(tgt, "X", "a.mov"), tgt));
        Check("traversare .. -> refuzata", !PathSafety.IsInsideTarget(Path.Combine(tgt, "..", "..", "a.mov"), tgt));
    }
}
finally { Directory.Delete(root, true); }

// --- Sursa care nu se poate deschide: fara blocaj, fara .dmpart (regresie Windows 2026-09-26) ---
{
    var lr = Path.Combine(Path.GetTempPath(), "dm-lock-" + Guid.NewGuid().ToString("N")[..6]);
    Directory.CreateDirectory(lr);
    var missingSrc = Path.Combine(lr, "nu-exista.mov");
    var d1 = Path.Combine(lr, "a.mov"); var d2 = Path.Combine(lr, "b.mov");
    var copier = new FanOutCopier(missingSrc, new List<string> { d1, d2 }, 4096, VerificationModel.XxHash64,
        new CancelToken(), new PauseToken(), ringDepth: 2, expectedSize: 1000);
    var t = Task.Run(() => { try { copier.Run(_ => { }); return false; } catch { return true; } });
    var finished = t.Wait(TimeSpan.FromSeconds(10));
    Check("sursa imposibil de deschis: eroare, fara blocaj (10 s)", finished && t.Result);
    Thread.Sleep(200);
    Check("sursa imposibil de deschis: niciun .dmpart ramas", !Directory.EnumerateFiles(lr, "*" + PartialFile.Suffix).Any() && !File.Exists(d1));
    try { Directory.Delete(lr, true); } catch { }
}

// --- Preflight (aceleasi reguli ca pe Mac) ---
{
    var pr = Path.Combine(Path.GetTempPath(), "dm-pf-" + Guid.NewGuid().ToString("N")[..6]);
    var card = Directory.CreateDirectory(Path.Combine(pr, "CARD")).FullName;
    var a = Directory.CreateDirectory(Path.Combine(pr, "A")).FullName;
    var inner = Directory.CreateDirectory(Path.Combine(pr, "CARD", "X")).FullName;
    var sub = Directory.CreateDirectory(Path.Combine(pr, "A", "sub")).FullName;
    bool Has(List<DataMover.Core.Domain.PreflightIssue> l, DataMover.Core.Domain.PreflightCode c, bool blocking) => l.Any(i => i.Code == c && i.Blocking == blocking);
    var P = DataMover.Core.Domain.PreflightCode.SameAsSource;
    Check("preflight: fara surse/copii = blocat", DataMover.Core.Domain.Preflight.HasBlocking(DataMover.Core.Domain.Preflight.Check(new List<string>(), new List<string>())));
    Check("preflight: copia = sursa (cu slash final) = blocat", Has(DataMover.Core.Domain.Preflight.Check(new[] { card }, new[] { card + Path.DirectorySeparatorChar }), P, true));
    Check("preflight: copie in interiorul sursei = blocat", Has(DataMover.Core.Domain.Preflight.Check(new[] { card }, new[] { inner }), DataMover.Core.Domain.PreflightCode.DestinationInsideSource, true));
    Check("preflight: sursa in interiorul copiei = blocat", Has(DataMover.Core.Domain.Preflight.Check(new[] { inner }, new[] { card }), DataMover.Core.Domain.PreflightCode.SourceInsideDestination, true));
    Check("preflight: copii imbricate = blocat", Has(DataMover.Core.Domain.Preflight.Check(new[] { card }, new[] { a, sub }), DataMover.Core.Domain.PreflightCode.NestedDestinations, true));
    Check("preflight: copie duplicata = blocat", Has(DataMover.Core.Domain.Preflight.Check(new[] { card }, new[] { a, a }), DataMover.Core.Domain.PreflightCode.DuplicateDestination, true));
    Check("preflight: acelasi disc = doar avertisment", Has(DataMover.Core.Domain.Preflight.Check(new[] { card }, new[] { a }), DataMover.Core.Domain.PreflightCode.SameVolumeAsSource, false)
        && !DataMover.Core.Domain.Preflight.HasBlocking(DataMover.Core.Domain.Preflight.Check(new[] { card }, new[] { a })));
    Check("preflight: prefix de text nu e interior (A vs AB)", !DataMover.Core.Domain.Preflight.IsSameOrInside(Path.Combine(pr, "AB"), a));
    Check("preflight: sursa lipsa = blocat", Has(DataMover.Core.Domain.Preflight.Check(new[] { Path.Combine(pr, "nu") }, new[] { a }), DataMover.Core.Domain.PreflightCode.SourceMissing, true));
    Check("preflight: fiecare cod are text RO (titlu, cauza, actiune)", Enum.GetValues<DataMover.Core.Domain.PreflightCode>()
        .All(c => DataMover.Core.Domain.Preflight.Describe(c) is var d && d.Title.Length > 0 && d.Cause.Length > 0 && d.Action.Length > 0));
    Directory.Delete(pr, true);
}

// --- Clasificarea mediilor: niciodata mai precis decat raporteaza sistemul ---
{
    DataMover.Core.Domain.MediaClass Cls(Action<DataMover.Core.Domain.MediaFacts> set) { var f = new DataMover.Core.Domain.MediaFacts(); set(f); return DataMover.Core.Domain.MediaClassifier.Classify(f); }
    const long G = 1_000_000_000;
    Check("media: folder ales = Folder", Cls(f => f.IsVolumeRoot = false).Kind == DataMover.Core.Domain.DeviceKind.Folder);
    Check("media: fara date = dispozitiv extern (fallback)", Cls(_ => { }) is { Kind: DataMover.Core.Domain.DeviceKind.ExternalDevice, Confidence: DataMover.Core.Domain.Confidence.Fallback });
    Check("media: intern = volum intern", Cls(f => f.IsInternal = true).Kind == DataMover.Core.Domain.DeviceKind.InternalVolume);
    Check("media: retea = extern cert, nu SSD", Cls(f => { f.IsNetwork = true; f.Medium = DataMover.Core.Domain.MediumType.SolidState; }).Kind == DataMover.Core.Domain.DeviceKind.ExternalDevice);
    Check("media: structura camera + CFexpress + amovibil = CFexpress", Cls(f => { f.CameraCardStructure = true; f.IsRemovableMedia = true; f.TotalBytes = 512 * G; f.Model = "CFexpress Reader"; }).Kind == DataMover.Core.Domain.DeviceKind.CFexpress);
    Check("media: structura camera pe 8 TB = NU card", Cls(f => { f.CameraCardStructure = true; f.IsRemovableMedia = true; f.TotalBytes = 8000 * G; f.Medium = DataMover.Core.Domain.MediumType.Rotational; }).Kind == DataMover.Core.Domain.DeviceKind.Hdd);
    Check("media: USB amovibil mic = stick", Cls(f => { f.Bus = "USB"; f.IsRemovableMedia = true; f.TotalBytes = 64 * G; }).Kind == DataMover.Core.Domain.DeviceKind.UsbStick);
    Check("media: SSD raportat = SSD (probabil)", Cls(f => f.Medium = DataMover.Core.Domain.MediumType.SolidState) is { Kind: DataMover.Core.Domain.DeviceKind.Ssd, Confidence: DataMover.Core.Domain.Confidence.Likely });
    Check("media: numele 'RAID' = doar indiciu", Cls(f => f.VolumeName = "Backup RAID").Confidence == DataMover.Core.Domain.Confidence.Hint);
}

// Afisare marimi: zecimal, ca pe macOS (aceeasi sursa = aceeasi cifra).
{
    var inv = System.Globalization.CultureInfo.InvariantCulture;
    Check("marime: 23248896 B = 23.2 MB (zecimal, ca Mac)", ByteSize.Format(23_248_896, culture: inv) == "23.2 MB");
    Check("marime: 999 B / 1000 B / 1,5 GB", ByteSize.Format(999, culture: inv) == "999 B" && ByteSize.Format(1000, culture: inv) == "1 KB"
        && ByteSize.Format(1_500_000_000, culture: inv) == "1.5 GB");
    Check("marime: separator zecimal ro-RO", ByteSize.Format(23_248_896, culture: new System.Globalization.CultureInfo("ro-RO")) == "23,2 MB");
}
// Rapoarte de livrare: verdict = motorul, fara chei brute, fara miniaturi; mostre HTML optionale.
{
    var dir = Environment.GetEnvironmentVariable("DM_REPORT_SAMPLES");
    if (dir != null) Directory.CreateDirectory(dir);
    bool allOk = true, verdicts = true;
    foreach (var lang in new[] { "ro", "en", "es" })
        foreach (var (name, r) in ReportScenarios.All(lang))
        {
            var html = r.Html();
            foreach (var raw in new[] { ">verdict.", ">help.", ">f.", ">col.", ">st.", ">footer." }) if (html.Contains(raw)) allOk = false;
            if (!html.Contains(r.VerdictTitle) || !html.Contains("2.16.2 (40)") || html.Contains("data:image/jpeg")) allOk = false;
            if (dir != null) File.WriteAllText(Path.Combine(dir, $"{name}-{lang}.html"), html, new System.Text.UTF8Encoding(false));
            var expected = name switch { "2-avertisment" => DestinationOutcome.VerifiedWithWarnings, "3-esec-partial" => DestinationOutcome.Failed,
                "6-anulat" => DestinationOutcome.Cancelled, _ => DestinationOutcome.Verified };
            if (r.Outcome != expected) verdicts = false;
        }
    Check("raport: verdictul urmeaza motorul (verificat/avertisment/esec/anulat)", verdicts);
    Check("raport: HTML complet RO/EN/ES, versiune in subsol, fara chei brute sau miniaturi", allOk);
    Check("raport: fiecare cheie are RO/EN/ES", DeliveryReportText.Strings.Values.All(v => v.Length == 3 && v.All(x => x.Length > 0)));
}
// Licențe generația 2 (reguli pure; semnătura e verificată separat, în WinChecks).
{
    byte[] Payload(string product, long expires, byte[] machine)
    {
        var p = new List<byte>(LicenseRules.ProductHash(product));
        for (int i = 7; i >= 0; i--) p.Add((byte)((expires >> (8 * i)) & 0xFF));
        p.AddRange(new byte[] { 7, 7, 7, 7 }); p.AddRange(machine); return p.ToArray();
    }
    var me = new byte[] { 1, 2, 3, 4, 5, 6 }; var other = new byte[] { 9, 9, 9, 9, 9, 9 }; var none = new byte[6]; long now = 1_790_000_000;
    LicenseRules.ValidationErrorKind? Kind(byte[] payload)
    {
        try { LicenseRules.ValidatePayload(payload, LicenseRules.SigningProductId, LicenseRules.CanonicalProductId, true, me, now); return null; }
        catch (LicenseRules.ValidationError e) { return e.Kind; }
    }
    Check("licenta: cod legacy recunoscut explicit (nu 'corupt')", Kind(Payload(LicenseRules.CanonicalProductId, 0, me)) == LicenseRules.ValidationErrorKind.LegacyLicense);
    Check("licenta: generatia 2, acest calculator -> acceptat", Kind(Payload(LicenseRules.SigningProductId, now + 86400, me)) == null);
    Check("licenta: generatia 2, alt calculator -> refuzat", Kind(Payload(LicenseRules.SigningProductId, 0, other)) == LicenseRules.ValidationErrorKind.WrongMachine);
    Check("licenta: generatia 2 expirata -> refuzata", Kind(Payload(LicenseRules.SigningProductId, now - 1, me)) == LicenseRules.ValidationErrorKind.Expired);
    Check("licenta: generatia 2 fara calculator -> refuzata", Kind(Payload(LicenseRules.SigningProductId, 0, none)) == LicenseRules.ValidationErrorKind.NotMachineLocked);
    Check("licenta: alt produs GDC -> WrongProduct", Kind(Payload("cursorpro", 0, me)) == LicenseRules.ValidationErrorKind.WrongProduct);
    var cap = 2L * 1024 * 1024 * 1024;
    Check("licenta: revocata -> fara acces, plafon aplicat", LicensePolicy.Evaluate(true, true, false, 0) == LicenseState.Revoked
        && !LicensePolicy.HasFullAccess(LicenseState.Revoked) && !LicensePolicy.TransferAllowed(cap + 1, false, cap));
    Check("licenta: revocarea nu transforma legacy/invalid in licenta", LicensePolicy.Evaluate(false, true, true, 5) == LicenseState.LegacyNeedsReactivation
        && LicensePolicy.Evaluate(false, false, false, 0) == LicenseState.Expired);
    Check("licenta: legacy nu primeste proba noua", LicensePolicy.Evaluate(false, false, true, 7) == LicenseState.LegacyNeedsReactivation);
    Check("licenta: instalare noua pastreaza proba", LicensePolicy.Evaluate(false, false, false, 7) == LicenseState.Trial);
    Check("licenta: acces complet ridica plafonul", LicensePolicy.TransferAllowed(cap * 10, true, cap));
    Check("licenta: mascare fara cod integral", LicenseRules.Mask("ABCDE-FGHIJ-KLMNO-PQRST") == "ABCDE…QRST");
    Check("licenta: texte RO/EN/ES complete", LicenseText.Complete);
    Check("update: obligatorie nu se amana permanent", UpdatePolicy.ShouldPrompt("2.17.0", true, "2.17.0", true)
        && !UpdatePolicy.ShouldPrompt("2.17.0", false, "2.17.0", true) && UpdatePolicy.ShouldPrompt("2.17.0", false, "2.17.0", false)
        && !UpdatePolicy.ShouldRememberDismissal(true) && !UpdatePolicy.ShouldPrompt(null, true, null, true));
}
// Identitatea buildului in jurnal: commitul real, nu "dev".
{
    Check("build: commit din InformationalVersion", DataMover.Core.Diagnostics.BuildIdentity.FromInformationalVersion("2.16.1+E33723095B3B3ECC") == "e337230");
    Check("build: fara commit -> dev", DataMover.Core.Diagnostics.BuildIdentity.FromInformationalVersion("2.16.1") == "dev"
        && DataMover.Core.Diagnostics.BuildIdentity.FromInformationalVersion(null) == "dev");
    Check("build: SDK pune commitul in assembly (build din git)", DataMover.Core.Diagnostics.BuildIdentity.Of(typeof(ByteSize).Assembly) != "dev");
}
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
