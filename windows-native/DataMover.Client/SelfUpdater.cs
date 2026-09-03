using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Windows;
using DataMover.Core.Services;
using MessageBox = System.Windows.MessageBox;

namespace DataMover.Client;

/// Descarca si instaleaza automat un update.
///
/// [2026-09-03] BUG REAL, reparat — raportat de Cristi: "cand fac
/// actualizare din Windows imi da eroare". Cauza: arhiva publicata pe
/// release (`DataMover-WPF-Windows.zip`) contine `DataMoverSetup.exe`
/// (installer-ul Inno Setup, adaugat in 2026-08-28), dar codul de-aici
/// cauta in ea `DataMover.exe` — fisier care nu exista in arhiva. Rezultat:
/// FIECARE incercare de update esua, de fiecare data, cu "Nu am gasit
/// DataMover.exe in arhiva descarcata". Comentariul vechi de aici ("clientul
/// WPF INCA nu are installer Inno Setup") ramasese in urma realitatii.
///
/// Reteta corecta acum (aceeasi ca GDCVaultWin): descarcam arhiva, gasim
/// installer-ul si il LANSAM, apoi inchidem aplicatia ca installer-ul sa
/// poata inlocui fisierele. Installer-ul isi cere singur drepturile de
/// Administrator (UAC) si arata pagina de licenta — pasul de consimtamant
/// din Regula 19 ramane intact, iar update-ul ramane un pas ASISTAT, nu
/// unul silentios (Regula 13).
///
/// DE CE NU vechea reteta cu .bat care copia exe-ul peste cel curent: ar fi
/// esuat oricum. Aplicatia se instaleaza in `Program Files`
/// (`DefaultDirName={autopf}\DataMover`), unde un `copy` dintr-un `cmd.exe`
/// neelevat primeste "Access is denied" — scriptul ar fi reincercat de 30 de
/// ori si ar fi iesit fara sa relanseze nimic, dupa ce aplicatia se inchisese
/// deja. Calea aceea ramane mai jos DOAR ca rezerva, pentru cazul in care o
/// arhiva viitoare ar contine iar exe-ul dezarhivat, fara installer.
public static class SelfUpdater
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromMinutes(5) };

    public static async Task DownloadAndInstallAsync(string version, string downloadUrl)
    {
        var progress = new UpdateProgressWindow(version);
        progress.Show();

        try
        {
            var tempDir = Path.Combine(Path.GetTempPath(), "datamover-update-" + Guid.NewGuid());
            Directory.CreateDirectory(tempDir);

            progress.SetStatus("Se descarcă actualizarea…");
            var zipPath = Path.Combine(tempDir, $"DataMover-{version}.zip");
            await DownloadAsync(downloadUrl, zipPath);

            progress.SetStatus("Se extrage arhiva…");
            var extractDir = Path.Combine(tempDir, "extracted");
            ZipFile.ExtractToDirectory(zipPath, extractDir);

            // Intai installer-ul (cazul REAL de azi), apoi rezerva cu exe
            // dezarhivat. Cautam dupa tipar, nu dupa un nume fix, ca o
            // redenumire viitoare a installer-ului sa nu rupa din nou
            // update-ul in tacere.
            var installer = FindInstaller(extractDir);
            if (installer != null)
            {
                progress.SetStatus("Se lansează programul de instalare…");
                Process.Start(new ProcessStartInfo(installer) { UseShellExecute = true });
                progress.Close();
                // Inchidem aplicatia: installer-ul nu poate inlocui un exe
                // care ruleaza. Userul continua in fereastra installer-ului.
                Application.Current.Shutdown();
                return;
            }

            var newExe = FindFile(extractDir, "DataMover.exe")
                ?? throw new InvalidOperationException(
                    "Arhiva descărcată nu conține nici programul de instalare, nici DataMover.exe.");

            progress.SetStatus("Se instalează și se relansează…");
            var currentExe = Process.GetCurrentProcess().MainModule!.FileName!;
            LaunchSwapScript(tempDir, newExe, currentExe);

            progress.Close();
            Application.Current.Shutdown();
        }
        catch (Exception ex)
        {
            progress.Close();
            MessageBox.Show(
                $"Actualizarea a eșuat: {ex.Message}\n\nPoți descărca manual ultima versiune de pe gordas.dev.",
                "DataMover");
        }
    }

    private static async Task DownloadAsync(string url, string destination)
    {
        using var response = await Http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
        if (!response.IsSuccessStatusCode)
            throw new InvalidOperationException($"Descărcarea a eșuat: HTTP {(int)response.StatusCode}");
        await using var httpStream = await response.Content.ReadAsStreamAsync();
        await using var fileStream = File.Create(destination);
        await httpStream.CopyToAsync(fileStream);
    }

    /// Installer-ul Inno Setup din arhiva. Cautam orice `*setup*.exe` sau
    /// `*install*.exe` — numele exact de azi e `DataMoverSetup.exe`, dar o
    /// cautare dupa nume fix e exact greseala care a rupt update-ul pana acum.
    private static string? FindInstaller(string directory) =>
        Directory.EnumerateFiles(directory, "*.exe", SearchOption.AllDirectories)
            .FirstOrDefault(f =>
            {
                var name = Path.GetFileName(f).ToLowerInvariant();
                return name.Contains("setup") || name.Contains("install");
            });

    private static string? FindFile(string directory, string exactName) =>
        Directory.EnumerateFiles(directory, exactName, SearchOption.AllDirectories).FirstOrDefault();

    /// Script .bat care asteapta (in bucla, nu un timp fix) ca procesul
    /// curent sa elibereze exe-ul, il inlocuieste, apoi relanseaza
    /// aplicatia - identic ca strategie cu perform_update_windows
    /// (core/updater.py, clientul Python vechi).
    private static void LaunchSwapScript(string tempDir, string newExe, string currentExe)
    {
        var batPath = Path.Combine(tempDir, "datamover_update.bat");
        var logPath = Path.Combine(tempDir, "datamover_update.log");
        var batContent = $"""
            @echo off
            setlocal enabledelayedexpansion
            set "NEWEXE={newExe}"
            set "CUREXE={currentExe}"
            set "LOG={logPath}"
            echo Se asteapta inchiderea aplicatiei... > "%LOG%"
            set /a tries=0
            :retry
            timeout /t 1 /nobreak > nul
            copy /Y "%NEWEXE%" "%CUREXE%" >> "%LOG%" 2>&1
            if errorlevel 1 (
                set /a tries+=1
                if !tries! LSS 30 goto retry
                echo Nu s-a putut inlocui exe-ul dupa 30 incercari. >> "%LOG%"
                exit /b 1
            )
            start "" "%CUREXE%"
            (goto) 2>nul & del "%~f0"
            """;
        File.WriteAllText(batPath, batContent);
        Process.Start(new ProcessStartInfo("cmd.exe", $"/c \"{batPath}\"")
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            WindowStyle = ProcessWindowStyle.Hidden,
        });
    }
}
