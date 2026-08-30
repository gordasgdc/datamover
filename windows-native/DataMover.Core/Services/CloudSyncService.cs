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

    /// Urca UN singur fisier deja copiat local catre `remote:remoteFolder/relPath`
    /// (`rclone copyto`, fisier -> fisier, nu re-scaneaza tot folderul de
    /// destinatie la fiecare fisier - Regula 21). `onLine` primeste
    /// progresul linie-cu-linie pentru feed-ul de activitate deja existent.
    public static bool UploadFile(string localPath, string remote, string remoteFolder,
        string relPath, Action<string> onLine)
    {
        var cleanFolder = remoteFolder.Trim('/', '\\');
        // rclone accepta separatorul "/" chiar si pe Windows pentru caile remote.
        var relPathForward = relPath.Replace('\\', '/');
        var remoteTarget = cleanFolder.Length == 0
            ? $"{remote}:{relPathForward}"
            : $"{remote}:{cleanFolder}/{relPathForward}";

        var psi = MakeStartInfo($"copyto \"{localPath}\" \"{remoteTarget}\" --stats=1s -v");
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
/// Coada SERIALA de upload-uri Cloud, una per DestinationJob (port 1:1 al
/// CloudUploadQueue - Mac). Motiv: mai multe procese `rclone` in paralel
/// ar concura pentru aceeasi banda de retea si ar creste memoria/CPU
/// nestapanit pe un transfer de mii de fisiere mici - o coada seriala
/// uploadeaza in fundal, fara sa blocheze bucla de copiere locala.
/// </summary>
public sealed class CloudUploadQueue
{
    private readonly string _remote;
    private readonly string _remoteFolder;
    private readonly Action<string> _onLine;
    private Task _tail = Task.CompletedTask;
    private readonly object _lock = new();

    public CloudUploadQueue(string remote, string remoteFolder, Action<string> onLine)
    {
        _remote = remote;
        _remoteFolder = remoteFolder;
        _onLine = onLine;
    }

    public void Enqueue(string localPath, string relPath)
    {
        lock (_lock)
        {
            _tail = _tail.ContinueWith(_ =>
            {
                var folderDisplay = string.IsNullOrEmpty(_remoteFolder) ? "" : _remoteFolder + "/";
                _onLine($"Cloud: urcare {relPath} → {_remote}:{folderDisplay}{relPath}…");
                var ok = CloudSyncService.UploadFile(localPath, _remote, _remoteFolder, relPath, _onLine);
                _onLine(ok ? $"Cloud: ✔ {relPath} urcat cu succes." : $"Cloud: ✘ {relPath} — urcarea a eșuat.");
            }, TaskScheduler.Default);
        }
    }

    /// Blocheaza pana cand toate upload-urile deja puse in coada s-au
    /// terminat - apelat la finalul unui job, ca raportul final sa nu
    /// arate "gata" cat timp inca se mai urca fisiere.
    public void WaitUntilDrained()
    {
        Task tail;
        lock (_lock) { tail = _tail; }
        tail.Wait();
    }
}
