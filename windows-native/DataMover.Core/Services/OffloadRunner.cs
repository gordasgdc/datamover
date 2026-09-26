using System.ComponentModel;
using System.IO;
using System.Linq;
using System.Runtime.CompilerServices;
using DataMover.Core.Models;

namespace DataMover.Core.Services;

/// <summary>
/// Orchestreaza cate un DestinationJob per destinatie, in paralel, si
/// expune progresul catre WPF prin INotifyPropertyChanged - echivalentul
/// C# al OffloadRunner (Mac, @Published/ObservableObject).
/// </summary>
public sealed class OffloadRunner : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    private void Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        field = value;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }

    private bool _isRunning;
    public bool IsRunning { get => _isRunning; private set => Set(ref _isRunning, value); }

    private int _progressPercent;
    public int ProgressPercent { get => _progressPercent; private set => Set(ref _progressPercent, value); }

    private int _filesDone;
    public int FilesDone { get => _filesDone; private set => Set(ref _filesDone, value); }

    private int _totalUnits;
    public int TotalUnits { get => _totalUnits; private set => Set(ref _totalUnits, value); }

    private string _statusText = "Gata de pornire";
    public string StatusText { get => _statusText; private set => Set(ref _statusText, value); }

    private string _speedText = "";
    public string SpeedText { get => _speedText; private set => Set(ref _speedText, value); }

    private bool _isPaused;
    public bool IsPaused { get => _isPaused; private set => Set(ref _isPaused, value); }

    private string _bufferAllocatedText = "";
    public string BufferAllocatedText { get => _bufferAllocatedText; private set => Set(ref _bufferAllocatedText, value); }

    private string _memoryUsedText = "";
    public string MemoryUsedText { get => _memoryUsedText; private set => Set(ref _memoryUsedText, value); }

    public List<DestinationResult> LastResults { get; private set; } = new();
    /// ID-ul jobului curent/ultim — coreleaza jurnalul structurat.
    public string JobId { get; private set; } = "";
    /// Istoric persistent (si alte efecte in profilul utilizatorului). Verificarile
    /// automate il opresc, ca sa nu scrie in istoricul real.
    public static bool SideEffectsEnabled { get; set; } = true;
    /// Coliziuni de nume intre surse gasite la ultima pornire (blocante).
    public List<string> LastCollisions { get; private set; } = new();
    public List<Domain.PreflightIssue> LastPreflight { get; private set; } = new();

    /// Plafon de proba depasit (2026-08-30) - vezi LicenseManager.
    /// TrialMaxTransferBytes. MainWindow verifica asta dupa Start() si
    /// arata un MessageBox cu buton de activare, in loc sa lase Start-ul
    /// sa esueze tacut.
    public long? TrialLimitExceededBytes { get; private set; }

    /// [2026-09-03] Setat o singura data la prima eroare de tip "acces
    /// refuzat" intalnita pe parcursul unui transfer - MainWindow asculta
    /// asta si arata un dialog cu optiunea de a relansa aplicatia ca
    /// Administrator, in loc sa lase userul sa vada doar "EROARE" generic
    /// in raport. Are nevoie de notificare (nu doar `private set` simplu,
    /// ca la TrialLimitExceededBytes) - apare ASINCRON, la mijlocul unui
    /// transfer deja pornit, nu doar imediat dupa Start().
    private string? _permissionErrorPath;
    public string? PermissionErrorPath { get => _permissionErrorPath; private set => Set(ref _permissionErrorPath, value); }

    /// MainWindow apeleaza asta dupa ce a aratat dialogul o data - fara ea,
    /// polling-ul din DispatcherTimer (RefreshUiFromRunner) ar re-arata
    /// acelasi MessageBox la fiecare tick cat timp transferul continua.
    public void AcknowledgePermissionError() => PermissionErrorPath = null;

    /// Feed-ul de activitate, plafonat la 200 linii (Regula 21 - nu tinem
    /// tot istoricul unui transfer de mii de fisiere in memorie/UI).
    public event Action<string>? ActivityLogged;
    private readonly List<string> _activityLines = new();
    private const int ActivityLogLimit = 200;
    public IReadOnlyList<string> ActivityLines => _activityLines;

    private CancelToken _cancelToken = new();
    private PauseToken _pauseToken = new();
    private DateTime _startTime;
    private long _bytesDone;
    public List<DestinationContext> Contexts { get; private set; } = new();

    public int ChunkSizeMB { get; set; } = IOSettings.DefaultChunkSizeMB;
    public int RamLimitMB { get; set; } = 1024;

    // ---------------- Nume de folder / deduplicare (2026-08-28) ----------------
    // Fix real: numele folderului include data zilei - un transfer de ore/
    // zile intregi (ex. 4 TB) calcula un folder NOU la o repornire in alta
    // zi, iar orice verificare "existent?" facuta doar pe numele de azi ar
    // rata complet folderul vechi cu sute de GB deja copiate. Identic cu
    // OffloadRunner (Mac, OffloadEngine.swift).

    /// [2026-09-03] Numele se compune acum dintr-un SABLON configurabil
    /// (vezi NamingTemplate.cs). Sablonul implicit produce exact acelasi
    /// rezultat ca varianta veche, hardcodata: `&lt;data&gt;_&lt;Proiect&gt;_&lt;Card&gt;`.
    public static string FolderName(string project, string card,
        string template = NamingTemplate.DefaultTemplate, string camera = "", string operatorName = "")
        => NamingTemplate.Render(template, new NamingTemplate.Context
        {
            Project = project, Card = card, Camera = camera, OperatorName = operatorName, Date = DateTime.Now,
        });

    /// Cauta un folder deja EXISTENT (creat oricand, nu neaparat azi) cu
    /// acelasi proiect/card, la oricare destinatie - alege cel mai RECENT
    /// daca gaseste mai multe (prefixul de data se sorteaza lexicografic
    /// identic cu ordinea cronologica).
    ///
    /// [2026-09-03] Cu sabloane libere de denumire, cautarea nu mai poate fi
    /// hardcodata pe sufixul `_Proiect_Card`. Comparam acum "miezul stabil"
    /// al sablonului (tot, mai putin data/ora) — vezi NamingTemplate.StableCore.
    public static string? FindExistingFolderName(IEnumerable<string> destinations, string project, string card,
        string template = NamingTemplate.DefaultTemplate, string camera = "", string operatorName = "")
    {
        var core = NamingTemplate.StableCore(template, new NamingTemplate.Context
        {
            Project = project, Card = card, Camera = camera, OperatorName = operatorName,
        });
        if (string.IsNullOrEmpty(core) || core == "Transfer") return null;
        var candidates = new List<string>();
        foreach (var dest in destinations)
        {
            if (!Directory.Exists(dest)) continue;
            try
            {
                candidates.AddRange(Directory.GetDirectories(dest)
                    .Select(Path.GetFileName)
                    .Where(n => n != null && n.Contains(core, StringComparison.Ordinal))!
                    .Cast<string>());
            }
            catch { /* destinatie inaccesibila momentan - ignora */ }
        }
        candidates.Sort(StringComparer.Ordinal);
        return candidates.Count > 0 ? candidates[^1] : null;
    }

    // ---------------- Spatiu liber (2026-09-03) ----------------

    /// [2026-09-03] Prima destinatie la care NU incape transferul, sau null
    /// daca incape peste tot.
    ///
    /// DE CE: pana acum, un card de 512 GB pornit catre un disc cu 80 GB
    /// liberi copia linistit ore intregi si esua abia la mijloc, cu zeci de
    /// erori "There is not enough space on the disk" in raport — exact
    /// scenariul in care operatorul crede ca are backup si nu are.
    /// La o reluare (folderul tinta exista deja) scadem fisierele deja
    /// prezente cu aceeasi dimensiune.
    public sealed class SpaceShortfall
    {
        public string Destination { get; init; } = "";
        public long Needed { get; init; }
        public long Free { get; init; }
    }

    public SpaceShortfall? LastSpaceShortfall { get; private set; }

    public static SpaceShortfall? CheckSpace(IEnumerable<string> destinations, IReadOnlyList<FileEntry> files, string folderName)
    {
        foreach (var dest in destinations)
        {
            long free;
            try { free = new DriveInfo(Path.GetPathRoot(Path.GetFullPath(dest))!).AvailableFreeSpace; }
            catch { continue; } // volum de retea fara informatii de spatiu - nu blocam transferul
            var targetRoot = Path.Combine(dest, folderName);
            bool targetExists = Directory.Exists(targetRoot);
            long needed = 0;
            foreach (var file in files)
            {
                if (targetExists)
                {
                    try
                    {
                        var destPath = Path.Combine(targetRoot, file.RelPath);
                        if (File.Exists(destPath) && new FileInfo(destPath).Length == file.Size) continue;
                    }
                    catch { /* il consideram necopiat */ }
                }
                needed += file.Size;
            }
            // Marja: 1% din transfer, minim 100 MB. Un volum umplut la refuz
            // devine imprevizibil, iar rapoartele se scriu tot acolo, la final.
            long margin = Math.Max(100L * 1024 * 1024, needed / 100);
            if (free < needed + margin)
                return new SpaceShortfall { Destination = dest, Needed = needed, Free = free };
        }
        return null;
    }

    public static bool FolderHasRealFiles(IEnumerable<string> destinations, string folderName)
    {
        foreach (var dest in destinations)
        {
            var target = Path.Combine(dest, folderName);
            if (!Directory.Exists(target)) continue;
            try
            {
                var items = Directory.GetFileSystemEntries(target);
                if (items.Any(p =>
                    {
                        var n = Path.GetFileName(p);
                        return !n.StartsWith("offload_checkpoint") && !n.StartsWith("offload_report_");
                    }))
                    return true;
            }
            catch { /* ignora */ }
        }
        return false;
    }

    public static string FreeFolderName(string baseName, IEnumerable<string> destinations)
    {
        var candidate = baseName;
        int i = 2;
        var destList = destinations.ToList();
        while (FolderHasRealFiles(destList, candidate))
        {
            candidate = $"{baseName} ({i})";
            i++;
        }
        return candidate;
    }

    public static void ClearExistingFolders(IEnumerable<string> destinations, string folderName)
    {
        foreach (var dest in destinations)
        {
            var target = Path.Combine(dest, folderName);
            if (!Directory.Exists(target)) continue;
            try
            {
                foreach (var item in Directory.GetFileSystemEntries(target))
                {
                    if (Directory.Exists(item)) Directory.Delete(item, recursive: true);
                    else File.Delete(item);
                }
            }
            catch { /* ignora */ }
        }
    }

    // ---------------- Pauza ----------------

    public void TogglePause()
    {
        Diagnostics.StructuredLog.Shared.Log(Diagnostics.LogLevel.Info, "job", IsPaused ? "job.resumed" : "job.paused", IsPaused ? "Reluat" : "Pauza", job: JobId);
        if (!IsRunning) return;
        if (_pauseToken.IsPaused)
        {
            _pauseToken.Resume();
            IsPaused = false;
            StatusText = "Se copiaza...";
        }
        else
        {
            _pauseToken.Pause();
            IsPaused = true;
            StatusText = "Pauza — apasa Continua pentru a relua";
        }
    }

    public void Cancel()
    {
        Diagnostics.StructuredLog.Shared.Log(Diagnostics.LogLevel.Info, "job", "job.cancel.requested", "Anulare ceruta", job: JobId);
        if (!IsRunning) return;
        _cancelToken.Cancel();
        StatusText = "Se anuleaza...";
    }

    private void UpdateMemoryDisplay()
    {
        BufferAllocatedText = RamLimitMB == 0 ? "Fara limita" : IOSettings.SizeLabel(RamLimitMB);
        MemoryUsedText = IOSettings.SizeLabel((int)(IOSettings.CurrentProcessMemoryBytes() / 1024 / 1024));
    }

    // ---------------- Start ----------------

    public void Start(List<string> sources, List<string> destinations, VerificationModel model,
        List<string> exclusions, bool resume, ProductionMeta meta, string? folderNameOverride = null,
        string cloudRemote = "", string cloudRemoteFolder = "",
        string folderTemplate = NamingTemplate.DefaultTemplate,
        bool generateMhl = true, bool retryFailedFiles = true,
        bool ejectSourceWhenDone = false, bool ignoreSpaceWarning = false,
        string appVersion = "?")
    {
        if (IsRunning) return;

        // [2026-09-26] Preflight (paritate Mac): suprapuneri sursa/destinatie,
        // destinatii duble/imbricate, cai lipsa — blocant inainte de orice scriere.
        LastPreflight = Domain.Preflight.Check(sources, destinations);
        if (Domain.Preflight.HasBlocking(LastPreflight))
        {
            var first = LastPreflight.First(i => i.Blocking);
            StatusText = "Pornire blocată: " + Domain.Preflight.Describe(first.Code).Title + (first.Path.Length > 0 ? $" ({first.Path})" : "");
            Diagnostics.StructuredLog.Shared.Log(Diagnostics.LogLevel.Warning, "preflight", "preflight.blocked", StatusText,
                fields: new Dictionary<string, string> { ["codes"] = string.Join(",", LastPreflight.Select(i => i.Code)) });
            return;
        }

        var files = new List<FileEntry>();
        foreach (var src in sources)
        {
            if (Directory.Exists(src))
            {
                files.AddRange(FileScanner.ListAllFiles(src, exclusions));
            }
            else if (File.Exists(src))
            {
                var name = Path.GetFileName(src);
                if (FileScanner.IsExcluded(name, exclusions)) continue;
                long size = 0, mtime = 0;
                try { var fi = new FileInfo(src); size = fi.Length; mtime = FileEntry.MicrosOf(fi); } catch { /* ignora */ }
                files.Add(new FileEntry(src, name, size, mtime));
            }
        }
        if (files.Count == 0)
        {
            StatusText = "Nu am gasit niciun fisier de copiat.";
            return;
        }

        // [2026-09-26] Coliziuni de nume intre surse: blocant (paritate Mac).
        LastCollisions = sources.Count > 1 ? PathSafety.NameCollisions(files) : new List<string>();
        if (LastCollisions.Count > 0)
        {
            StatusText = $"Pornire blocata: {LastCollisions.Count} fisier(e) cu acelasi nume in surse diferite (ex. {LastCollisions[0]}).";
            Diagnostics.StructuredLog.Shared.Log(Diagnostics.LogLevel.Warning, "preflight", "preflight.nameCollision", "Coliziune de nume intre surse",
                fields: new Dictionary<string, string> { ["count"] = LastCollisions.Count.ToString() });
            return;
        }

        // Plafon de proba (2026-08-30) - vezi LicenseManager.
        // TrialMaxTransferBytes. Verificat pe dimensiunea TOTALA a
        // transferului, o singura data, inainte de a porni orice copiere -
        // nu un plafon per fisier, ca sa nu poata fi ocolit trimitand
        // multe fisiere mici.
        if (!LicenseManager.Shared.IsLicensed)
        {
            long totalBytes = files.Sum(f => f.Size);
            if (totalBytes > LicenseManager.TrialMaxTransferBytes)
            {
                TrialLimitExceededBytes = totalBytes;
                StatusText = "Transfer blocat — depășește plafonul de 2 GB al probei.";
                return;
            }
        }
        TrialLimitExceededBytes = null;
        PermissionErrorPath = null;

        var folderName = folderNameOverride ?? FolderName(meta.Project, meta.Card, folderTemplate, meta.Camera, meta.OperatorName);
        var sourceRoot = sources.FirstOrDefault();
        var sourceIdentity = SourceIdentity.Compute(sources, files);

        // [2026-09-03] Spatiu insuficient: nu pornim deloc. MainWindow arata
        // un dialog cu cifrele exacte si un buton "Continua oricum", care
        // re-apeleaza Start() cu ignoreSpaceWarning: true — decizia ramane a
        // userului, dar informata, nu descoperita dupa 3 ore.
        if (!ignoreSpaceWarning)
        {
            var shortfall = CheckSpace(destinations, files, folderName);
            if (shortfall != null)
            {
                LastSpaceShortfall = shortfall;
                StatusText = "Spațiu insuficient la destinație — transferul nu a pornit.";
                return;
            }
        }
        LastSpaceShortfall = null;

        _cancelToken = new CancelToken();
        _pauseToken = new PauseToken();
        IsPaused = false;
        IsRunning = true;
        _startTime = DateTime.Now;
        _bytesDone = 0;
        FilesDone = 0;
        TotalUnits = files.Count * destinations.Count;
        ProgressPercent = 0;
        StatusText = "Se copiaza...";
        SpeedText = "";
        LastResults = new();
        // [2026-09-03] Feed-ul NU se mai goleste la start: avertismentele
        // detectorului de carduri apar INAINTE de start si tocmai ele
        // trebuie sa ramana vizibile in timpul transferului.
        LogActivity($"──────── Transfer nou: {folderName} ────────");
        JobId = Diagnostics.StructuredLog.NewId();
        Diagnostics.StructuredLog.Shared.Log(Diagnostics.LogLevel.Info, "job", "job.started", "Transfer pornit", job: JobId,
            fields: new Dictionary<string, string>
            {
                ["sources"] = sources.Count.ToString(), ["destinations"] = destinations.Count.ToString(),
                ["files"] = files.Count.ToString(), ["bytes"] = files.Sum(f => f.Size).ToString(), ["model"] = model.Key(),
                ["resume"] = resume.ToString(), ["destIDs"] = string.Join(",", destinations.Select(Diagnostics.Redactor.DestinationId)),
            });
        UpdateMemoryDisplay();

        int chunkBytes = ChunkSizeMB * 1024 * 1024;
        var token = _cancelToken;
        var pauseTok = _pauseToken;
        var results = new List<DestinationResult>();

        // Cloud secondary destination (2026-08-30) - o coada NOUA per
        // destinatie locala, ca fiecare disc/destinatie sa urce independent.
        var trimmedRemote = cloudRemote.Trim();

        var started = DateTime.Now;
        Contexts = destinations.Select(dest =>
        {
            CloudUploadQueue? cloudQueue = trimmedRemote.Length > 0
                ? new CloudUploadQueue(trimmedRemote, cloudRemoteFolder, Path.Combine(dest, folderName), line => LogActivity(line))
                : null;
            return new DestinationContext(dest, folderName, model, generateMhl, meta, sourceRoot, sourceIdentity,
                cloudQueue, started, appVersion,
                onActivity: line => LogActivity(line),
                onPermissionError: path =>
                {
                    // Doar prima eroare conteaza pentru dialog - restul, din
                    // aceeasi cauza, sunt zgomot odata ce userul stie problema.
                    if (PermissionErrorPath is null) PermissionErrorPath = path;
                });
        }).ToList();

        Task.Run(() =>
        {
            foreach (var ctx in Contexts) ctx.Prepare(resume);

            bool cancelledFlag = false;

            // [M1 FAZA 2] O SINGURA trecere peste `entries`, cu fan-out per
            // fisier — folosita ATAT pentru bucla principala CAT si pentru
            // reincercarea automata de la final (acelasi cod, ca cele doua
            // cai sa nu diveraga).
            void RunPass(IReadOnlyList<FileEntry> entries, bool isRetry)
            {
                foreach (var entry in entries)
                {
                    if (token.IsCancelled) { cancelledFlag = true; return; }
                    if (pauseTok.IsPaused)
                    {
                        LogActivity("Pauza — transferul e oprit temporar de utilizator.");
                        pauseTok.WaitWhilePaused(token);
                        if (token.IsCancelled) { cancelledFlag = true; return; }
                    }
                    IOSettings.WaitIfOverRamLimit(RamLimitMB, token, LogActivity);

                    var toCopy = new List<DestinationContext>();
                    var toVerify = new List<DestinationContext>();
                    foreach (var ctx in Contexts)
                    {
                        if (isRetry)
                        {
                            if (!ctx.FailedRelPaths.Contains(entry.RelPath)) continue;
                            ctx.PrepareForRetry(entry);
                            toCopy.Add(ctx);
                            continue;
                        }
                        switch (ctx.Classify(entry, resume))
                        {
                            case DestinationContext.Classification.Revalidate:
                                toVerify.Add(ctx);
                                break;
                            case DestinationContext.Classification.NeedsCopy:
                                toCopy.Add(ctx);
                                break;
                        }
                    }

                    // Fisiere deja existente, cu marime identica — verificate
                    // fara recopiere. Hash-ul sursei se calculeaza O SINGURA
                    // DATA si e reutilizat pentru toate destinatiile din
                    // acest bucket, daca sunt mai multe.
                    if (toVerify.Count > 0)
                    {
                        string? verifiedSourceHash = null;
                        foreach (var ctx in toVerify)
                        {
                            ctx.OnActivity($"Verificare fisier existent: {entry.RelPath}…");
                            // [2026-09-26] Byte-safe: sursa si destinatia recitite;
                            // checksum-ul din checkpoint (daca exista) trebuie reprodus.
                            var (reason, srcHash, dstHash) = RevalidationPolicy.Revalidate(
                                entry.FullPath, ctx.DestPath(entry), ctx.ExpectedHashFor(entry.RelPath), model, chunkBytes, token,
                                cachedSourceHash: verifiedSourceHash);
                            verifiedSourceHash ??= srcHash;
                            if (reason == null)
                            {
                                ctx.RecordVerifiedExisting(entry, srcHash!, dstHash!);
                                Advance(entry.Size);
                            }
                            else
                            {
                                ctx.OnActivity($"Se recopiază {entry.RelPath}: {reason}.");
                                toCopy.Add(ctx);
                            }
                        }
                        if (token.IsCancelled) { cancelledFlag = true; return; }
                    }

                    // Copiere REALA prin fan-out — o singura citire a sursei
                    // pentru TOATE destinatiile care au nevoie de copiere la
                    // acest fisier (vezi FanOutCopier.cs).
                    // [2026-09-26] Garzi per destinatie, INAINTE de fan-out: disc
                    // disparut, cale care iese din tinta (reparse point), folder
                    // imposibil de creat. Inainte, CreateDirectory arunca in afara
                    // try-ului -> Task.Run cadea, Finish nu mai rula, UI blocat.
                    var ready = new List<DestinationContext>();
                    foreach (var ctx in toCopy)
                    {
                        var destPath = ctx.DestPath(entry);
                        string? problem = null;
                        if (!Directory.Exists(ctx.DestRoot)) problem = "Destinatia nu mai e disponibila (disc deconectat?)";
                        else if (!PathSafety.IsInsideTarget(destPath, ctx.TargetRoot)) problem = "Calea ar iesi din folderul destinatiei (link/junction)";
                        else
                        {
                            try { Directory.CreateDirectory(Path.GetDirectoryName(destPath)!); }
                            catch (Exception ex) { problem = "Folderul destinatiei nu poate fi creat: " + ex.Message; }
                        }
                        if (problem == null) { ready.Add(ctx); continue; }
                        ctx.RecordCopyOutcome(entry, "", new FanOutDestResult { Success = false, Error = new IOException(problem) }, isRetry);
                        Diagnostics.StructuredLog.Shared.Log(Diagnostics.LogLevel.Error, "copy", "destination.refused", problem, job: JobId,
                            dest: Diagnostics.Redactor.DestinationId(ctx.DestRoot), fields: new Dictionary<string, string> { ["path"] = destPath });
                        Advance(entry.Size);
                    }
                    toCopy = ready;
                    if (toCopy.Count > 0)
                    {
                        var destPaths = new List<string>();
                        foreach (var ctx in toCopy)
                        {
                            destPaths.Add(ctx.DestPath(entry));
                            ctx.OnActivity($"Copiere: {entry.RelPath} ({FormatBytesLocal(entry.Size)})");
                        }
                        try
                        {
                            var copier = new FanOutCopier(entry.FullPath, destPaths, chunkBytes, model, token, pauseTok, expectedSize: entry.Size);
                            var result = copier.Run(_ => { });
                            foreach (var ctx in toCopy) ctx.OnActivity($"Verificare checksum: {entry.RelPath}…");
                            for (int i = 0; i < toCopy.Count; i++)
                            {
                                var ctx = toCopy[i];
                                var outcome = result.Destinations.TryGetValue(destPaths[i], out var o) ? o
                                    : new FanOutDestResult { Success = false, Error = new Exception("Fara rezultat de la motorul de copiere") };
                                ctx.RecordCopyOutcome(entry, result.SourceHash, outcome, isRetry);
                                if (!outcome.Verified)
                                    Diagnostics.StructuredLog.Shared.Log(outcome.Success ? Diagnostics.LogLevel.Warning : Diagnostics.LogLevel.Error,
                                        "copy", outcome.Success ? "file.mismatch" : "file.failed", outcome.MismatchReason ?? outcome.Error?.Message ?? "?",
                                        job: JobId, dest: Diagnostics.Redactor.DestinationId(ctx.DestRoot),
                                        fields: new Dictionary<string, string> { ["path"] = destPaths[i], ["retry"] = isRetry.ToString() }, error: outcome.Error);
                                Advance(entry.Size);
                            }
                        }
                        catch (OffloadCancelledException)
                        {
                            cancelledFlag = true; return;
                        }
                        catch (Exception ex)
                        {
                            foreach (var ctx in toCopy)
                            {
                                ctx.RecordSourceReadFailure(entry, ex, isRetry);
                                Advance(entry.Size);
                            }
                        }
                    }
                }
            }

            RunPass(files, isRetry: false);

            // [2026-09-03, pastrat identic] Pas automat de reincercare,
            // INAINTE de rapoarte — rapoartele trebuie sa reflecte starea
            // finala, nu una intermediara.
            if (!cancelledFlag && retryFailedFiles)
            {
                var retryPaths = new HashSet<string>();
                foreach (var ctx in Contexts) retryPaths.UnionWith(ctx.FailedRelPaths);
                if (retryPaths.Count > 0)
                {
                    LogActivity($"Reîncercare automată: {retryPaths.Count} fișier(e) care au eșuat la prima trecere…");
                    var retryEntries = files.Where(f => retryPaths.Contains(f.RelPath)).ToList();
                    RunPass(retryEntries, isRetry: true);
                }
            }

            if (cancelledFlag) foreach (var ctx in Contexts) ctx.MarkCancelled();
            foreach (var ctx in Contexts) results.Add(ctx.Finalize(files.Count));

            Finish(results, folderName, sources, destinations, ejectSourceWhenDone);
        });
    }

    private static string? TryHash(string path, VerificationModel model, int chunkSize, CancelToken cancel)
    {
        try { return FileHashing.HashOfFile(path, model, chunkSize, cancel); }
        catch { return null; }
    }

    private static string FormatBytesLocal(long bytes)
    {
        return ByteSize.Format(bytes, "0.0");
    }

    /// MainWindow apeleaza asta dupa ce a aratat dialogul de spatiu, ca
    /// polling-ul din DispatcherTimer sa nu-l re-afiseze la fiecare tick.
    public void AcknowledgeSpaceShortfall() => LastSpaceShortfall = null;

    /// [2026-09-03] Acelasi feed, dar scris din AFARA runner-ului (UI) —
    /// folosit de avertismentele detectorului de carduri, care apar inainte
    /// sa porneasca vreun transfer.
    public void LogExternal(string line) => LogActivity(line);

    private void LogActivity(string line)
    {
        var withSpeed = string.IsNullOrEmpty(SpeedText) ? line : $"{line} — {SpeedText}";
        _activityLines.Add(withSpeed);
        if (_activityLines.Count > ActivityLogLimit) _activityLines.RemoveRange(0, _activityLines.Count - ActivityLogLimit);
        ActivityLogged?.Invoke(withSpeed);
    }

    private void Advance(long size)
    {
        FilesDone++;
        _bytesDone += size;
        ProgressPercent = TotalUnits > 0 ? (int)(FilesDone * 100.0 / TotalUnits) : 0;
        StatusText = $"{ProgressPercent}% ({FilesDone}/{TotalUnits} fisiere)";
        var elapsed = (DateTime.Now - _startTime).TotalSeconds;
        if (elapsed > 0) SpeedText = $"{IOSettings.SizeLabel((int)(_bytesDone / elapsed / 1024 / 1024))}/s";
        UpdateMemoryDisplay();
    }

    private void Finish(List<DestinationResult> results, string folderName, List<string> sources,
        List<string> destinations, bool ejectSource = false)
    {
        LastResults = results;
        foreach (var r in results)
            Diagnostics.StructuredLog.Shared.Log(r.FailCount > 0 || r.Cancelled ? Diagnostics.LogLevel.Warning : Diagnostics.LogLevel.Info,
                "job", "destination.result", r.Cancelled ? "cancelled" : r.FailCount > 0 ? "failed" : r.RecoveredCount > 0 ? "verifiedWithWarnings" : "verified",
                job: JobId, dest: Diagnostics.Redactor.DestinationId(r.DestRoot), fields: new Dictionary<string, string>
                {
                    ["ok"] = r.OkCount.ToString(), ["skipped"] = r.SkipCount.ToString(), ["failed"] = r.FailCount.ToString(),
                    ["recovered"] = r.RecoveredCount.ToString(), ["mhl"] = r.MhlPath == null ? "no" : "yes",
                });
        bool anyCancelled = results.Any(r => r.Cancelled);
        int totalOk = results.Sum(r => r.OkCount);
        int totalSkip = results.Sum(r => r.SkipCount);
        int totalFail = results.Sum(r => r.FailCount);
        int totalRecovered = results.Sum(r => r.RecoveredCount);
        var summary = $"Finalizat — {totalOk} OK";
        if (totalFail > 0) summary += $", {totalFail} probleme";
        // Recuperarile la reincercare se afiseaza explicit: userul trebuie sa
        // stie ca transferul a avut probleme tranzitorii, chiar daca s-a
        // terminat cu bine (indiciu de cablu/card/disc care da rateuri).
        if (totalRecovered > 0) summary += $", {totalRecovered} recuperate la reîncercare";
        // [2026-09-26] Verdict neambiguu, aceleasi reguli ca TransferOutcome
        // (Mac): nicio destinatie esuata nu poate da „succes”.
        int failedDests = results.Count(r => r.FailCount > 0);
        string verdict = anyCancelled ? "Transfer anulat"
            : failedDests == results.Count ? "Transfer eșuat"
            : failedDests > 0 ? "Eșec parțial — nu formata cardul"
            : totalRecovered > 0 ? "Verificat, cu avertismente"
            : "Transfer verificat";
        LastVerdict = verdict;
        Diagnostics.StructuredLog.Shared.Log(verdict == "Transfer verificat" || verdict.StartsWith("Verificat") ? Diagnostics.LogLevel.Info : Diagnostics.LogLevel.Warning,
            "job", "job.finished", verdict, job: JobId);
        StatusText = anyCancelled ? "Anulat." : verdict + " — " + summary + ".";

        // [2026-09-03] Ejectare automata a cardului sursa, DOAR daca totul a
        // mers bine. Un card cu erori nu se scoate niciodata automat: s-ar
        // putea sa mai fie nevoie de o reluare de pe el.
        if (ejectSource && !anyCancelled && totalFail == 0) EjectSourceVolumes(sources);

        if (SideEffectsEnabled) HistoryStore.Shared.Record(folderName, sources, destinations, totalOk, totalSkip, totalFail);
        // Ultimul pas: cine asteapta IsRunning == false gaseste deja rezultatele
        // si jurnalul complete (ordine gasita la verificarea in VM).
        IsRunning = false;
    }

    /// Scoate in siguranta volumele amovibile de pe care s-a citit.
    ///
    /// NOTA (diferenta reala fata de Mac): Windows nu are un echivalent
    /// simplu si sigur al lui `NSWorkspace.unmountAndEjectDevice` accesibil
    /// din .NET fara P/Invoke pe handle-uri de volum. Folosim utilitarul
    /// nativ `mountvol /P`, care demonteaza volumul si il pregateste pentru
    /// scoatere fizica — exact ce face "Safely Remove Hardware". Necesita
    /// drepturi de administrator; daca nu le are, esecul e RAPORTAT in feed,
    /// nu ascuns (userul trebuie sa stie ca mai trebuie sa scoata cardul
    /// manual, nu sa creada ca s-a facut).
    /// Verdictul ultimului transfer (vezi Finish).
    public string LastVerdict { get; private set; } = "";

    private void EjectSourceVolumes(IEnumerable<string> sources)
    {
        var done = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var source in sources)
        {
            string? root;
            try { root = Path.GetPathRoot(Path.GetFullPath(source)); }
            catch { continue; }
            if (string.IsNullOrEmpty(root) || !done.Add(root)) continue;
            try
            {
                var drive = new DriveInfo(root);
                if (drive.DriveType != DriveType.Removable) continue;
                var psi = new System.Diagnostics.ProcessStartInfo("mountvol", $"{root.TrimEnd('\\')} /P")
                {
                    UseShellExecute = false, CreateNoWindow = true,
                    RedirectStandardOutput = true, RedirectStandardError = true,
                };
                using var proc = System.Diagnostics.Process.Start(psi);
                proc?.WaitForExit(10000);
                if (proc != null && proc.ExitCode == 0)
                    LogActivity($"Card ejectat automat: {root}");
                else
                    LogActivity($"Cardul {root} nu a putut fi ejectat automat — scoate-l manual (ejectarea cere drepturi de administrator).");
            }
            catch (Exception ex)
            {
                LogActivity($"Cardul {root} nu a putut fi ejectat: {ex.Message}");
            }
        }
    }
}
