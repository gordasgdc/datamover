using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Windows;
using DataMover.Core.Services;
using MessageBox = System.Windows.MessageBox;

namespace DataMover.Client;

/// Descarca si instaleaza automat un update - port pentru clientul WPF al
/// retetei deja functionale din core/updater.py (clientul Python vechi):
/// clientul WPF INCA nu are installer Inno Setup (vezi TODO din CLAUDE.md),
/// deci nu putem folosi reteta "descarca .exe, lanseaza-l" ca pe
/// GDCVaultWin - descarcam arhiva .zip, extragem noul DataMover.exe, si il
/// inlocuim pe cel curent printr-un script .bat auxiliar care asteapta ca
/// procesul curent sa elibereze fisierul, apoi relanseaza aplicatia.
///
/// WARNING: functioneaza doar cand `UpdateChecker.WindowsWpfDownloadUrl`
/// e populat - update.json nu are inca acest camp completat cu o arhiva
/// REALA a clientului WPF (campul "windows" existent tinteste inca
/// arhiva clientului Python vechi) - vezi CLAUDE.md. Pana atunci, arata
/// un mesaj explicit in loc sa descarce arhiva gresita.
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
            var newExe = FindFile(extractDir, "DataMover.exe")
                ?? throw new InvalidOperationException("Nu am găsit DataMover.exe în arhiva descărcată.");

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
