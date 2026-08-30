using System.Diagnostics;

namespace DataMover.Core.Services;

/// <summary>
/// Destinatie secundara Cloud, powered by Rclone (2026-08-30, port 1:1 al
/// CloudSyncService.swift - Mac) - cerinta explicita a lui Cristi: "vreau
/// sa copiez ceva, dar in acelasi timp sa il si urc direct pe unul dintre
/// serviciile facute cu Rclone". `rclone` tine toate conturile intr-un
/// singur `rclone.conf` GLOBAL (%AppData%\rclone\rclone.conf pe Windows),
/// ne-izolat per aplicatie - orice cont configurat prin Cloud Manager-ul
/// din Master Control Studio Pro (Windows) e deja vizibil aici.
/// </summary>
public static class CloudSyncService
{
    /// PATH proaspat (Machine+User), citit direct din Registry, la fel ca
    /// Shell.cs (Master Control Studio Pro Windows) - motiv identic: un
    /// `rclone` instalat recent prin winget nu apare in PATH-ul deja
    /// mostenit de un proces GUI de lunga durata.
    private static string RefreshedPath()
    {
        var machine = Environment.GetEnvironmentVariable("Path", EnvironmentVariableTarget.Machine) ?? "";
        var user = Environment.GetEnvironmentVariable("Path", EnvironmentVariableTarget.User) ?? "";
        return string.IsNullOrEmpty(user) ? machine : $"{machine};{user}";
    }

    private static ProcessStartInfo MakeStartInfo(string arguments)
    {
        var psi = new ProcessStartInfo
        {
            FileName = "rclone",
            Arguments = arguments,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        psi.EnvironmentVariables["Path"] = RefreshedPath();
        return psi;
    }

    /// True daca `rclone` e gasibil pe PATH-ul proaspat - ascunde
    /// sectiunea "Destinatie Cloud" daca dependinta lipseste.
    public static bool IsAvailable()
    {
        try
        {
            using var process = Process.Start(MakeStartInfo("version"));
            if (process is null) return false;
            process.WaitForExit();
            return process.ExitCode == 0;
        }
        catch
        {
            return false;
        }
    }

    /// Numele conturilor configurate (`rclone listremotes`), fara ":" final -
    /// aceleasi conturi vizibile in Cloud Manager (Master Control Studio Pro).
    public static List<string> ListRemotes()
    {
        var result = new List<string>();
        try
        {
            using var process = Process.Start(MakeStartInfo("listremotes"));
            if (process is null) return result;
            var output = process.StandardOutput.ReadToEnd();
            process.WaitForExit();
            foreach (var line in output.Split('\n', StringSplitOptions.RemoveEmptyEntries))
            {
                var trimmed = line.Trim();
                if (trimmed.EndsWith(':')) trimmed = trimmed[..^1];
                if (trimmed.Length > 0) result.Add(trimmed);
            }
        }
        catch { /* IsAvailable() ar fi trebuit sa prinda asta deja */ }
        return result;
    }

    /// Urca UN SINGUR LOT de fisiere deja copiate local (relPath-uri,
    /// relative la `localRoot`) catre `remote:remoteFolder`, intr-un SINGUR
    /// proces `rclone copy` (2026-08-30, port 1:1 al `CloudSyncService.
    /// uploadBatch` - Mac, inlocuieste `UploadFile`/`copyto` per-fisier -
    /// gasit ca bug real de performanta: un proces `rclone` nou per fisier
    /// are overhead de pornire+autentificare care domina timpul la multe
    /// fisiere mici, iar `copyto` nu paralelizeaza niciodata un singur
    /// fisier per invocare). `rclone copy` cu `--files-from -` (lista de
    /// cai pe stdin) lasa rclone insusi sa paralelizeze (`--transfers`) si
    /// sa foloseasca fragmente mai mari la upload (`--drive-chunk-size`,
    /// util si pentru fisiere mari).
    public static bool UploadBatch(string localRoot, string remote, string remoteFolder,
        IReadOnlyList<string> relPaths, Action<string> onLine)
    {
        if (relPaths.Count == 0) return true;
        var cleanFolder = remoteFolder.Trim('/', '\\');
        var remoteTarget = cleanFolder.Length == 0 ? $"{remote}:" : $"{remote}:{cleanFolder}";

        var psi = MakeStartInfo(
            $"copy \"{localRoot}\" \"{remoteTarget}\" --files-from - " +
            "--transfers 8 --checkers 16 --drive-chunk-size 64M --fast-list --stats 1s -v");
        psi.RedirectStandardInput = true;
        try
        {
            using var process = Process.Start(psi);
            if (process is null)
            {
                onLine("Cloud: eroare pornire rclone — procesul nu a putut fi creat.");
                return false;
            }
            process.OutputDataReceived += (_, e) => { if (!string.IsNullOrEmpty(e.Data)) onLine(e.Data); };
            process.ErrorDataReceived += (_, e) => { if (!string.IsNullOrEmpty(e.Data)) onLine(e.Data); };
            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            // rclone accepta separatorul "/" chiar si pe Windows pentru --files-from.
            foreach (var relPath in relPaths)
                process.StandardInput.WriteLine(relPath.Replace('\\', '/'));
            process.StandardInput.Close();
            process.WaitForExit();
            return process.ExitCode == 0;
        }
        catch (Exception ex)
        {
            onLine($"Cloud: eroare pornire rclone — {ex.Message}");
            return false;
        }
    }
}

/// <summary>
/// Coada SERIALA + pe LOTURI de upload-uri Cloud, una per DestinationJob
/// (port 1:1 al CloudUploadQueue - Mac, rescrisa 2026-08-30 dupa bug-ul de
/// performanta - vezi UploadBatch). Fisierele nu se mai urca unul cate
/// unul (un proces rclone per fisier) - se ACUMULEAZA intr-un lot, golit
/// fie cand ajunge la BatchSize, fie dupa BatchDelay de la primul fisier
/// neurcat inca, oricare vine primul - un SINGUR proces `rclone copy` per
/// lot, care paralelizeaza singur transferurile.
/// </summary>
public sealed class CloudUploadQueue
{
    private const int BatchSize = 25;
    private static readonly TimeSpan BatchDelay = TimeSpan.FromSeconds(3);

    private readonly string _remote;
    private readonly string _remoteFolder;
    private readonly string _localRoot;
    private readonly Action<string> _onLine;
    private Task _tail = Task.CompletedTask;
    private readonly object _lock = new();
    private readonly List<string> _pending = new();
    private CancellationTokenSource? _flushTimerCts;

    /// `localRoot` = radacina locala din care se raporteaza relPath-urile
    /// (acelasi folder tinta folosit de DestinationJob pentru copierea
    /// locala) - `rclone copy` are nevoie de o singura radacina sursa per
    /// invocare, filtrata apoi de `--files-from` la doar fisierele cerute.
    public CloudUploadQueue(string remote, string remoteFolder, string localRoot, Action<string> onLine)
    {
        _remote = remote;
        _remoteFolder = remoteFolder;
        _localRoot = localRoot;
        _onLine = onLine;
    }

    public void Enqueue(string relPath)
    {
        lock (_lock)
        {
            _pending.Add(relPath);
            if (_pending.Count >= BatchSize)
            {
                ScheduleFlushLocked(immediate: true);
            }
            else if (_flushTimerCts is null)
            {
                var cts = new CancellationTokenSource();
                _flushTimerCts = cts;
                _ = Task.Delay(BatchDelay, cts.Token).ContinueWith(t =>
                {
                    if (t.IsCanceled) return;
                    lock (_lock) { ScheduleFlushLocked(immediate: true); }
                }, TaskScheduler.Default);
            }
        }
    }

    /// Trebuie apelata cu `_lock` deja detinut.
    private void ScheduleFlushLocked(bool immediate)
    {
        _flushTimerCts?.Cancel();
        _flushTimerCts = null;
        if (_pending.Count == 0) return;
        var batch = new List<string>(_pending);
        _pending.Clear();
        _tail = _tail.ContinueWith(_ =>
        {
            _onLine($"Cloud: urcare lot de {batch.Count} fișier(e) → {_remote}:{(string.IsNullOrEmpty(_remoteFolder) ? "" : _remoteFolder + "/")}…");
            var ok = CloudSyncService.UploadBatch(_localRoot, _remote, _remoteFolder, batch, _onLine);
            _onLine(ok
                ? $"Cloud: ✔ lot de {batch.Count} fișier(e) urcat cu succes."
                : $"Cloud: ✘ lot de {batch.Count} fișier(e) — cel puțin unul a eșuat (vezi jurnalul rclone de mai sus).");
        }, TaskScheduler.Default);
    }

    /// Blocheaza pana cand toate upload-urile deja puse in coada s-au
    /// terminat (inclusiv un lot inca neajuns la prag/timp) - apelat la
    /// finalul unui job, ca raportul final sa nu arate "gata" cat timp
    /// inca se mai urca fisiere.
    public void WaitUntilDrained()
    {
        Task tail;
        lock (_lock)
        {
            ScheduleFlushLocked(immediate: true);
            tail = _tail;
        }
        tail.Wait();
    }
}
