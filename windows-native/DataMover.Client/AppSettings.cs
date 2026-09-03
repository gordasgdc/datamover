using System;
using System.IO;
using System.Text.Json;
using DataMover.Core.Services;

namespace DataMover.Client;

/// <summary>
/// [2026-09-03] Preferintele persistate ale aplicatiei — echivalentul
/// Windows al `@AppStorage` de pe Mac (ContentView.swift). Acelasi tipar de
/// stocare ca ThemeSettings/HistoryStore: un JSON in
/// `%AppData%\DataMover\settings.json`.
///
/// DE CE persistate: pe un proiect se schimba doar cardul de la o
/// descarcare la alta; clientul, operatorul, camera, logo-ul si sablonul de
/// denumire raman aceleasi saptamani intregi. Recompletarea lor la fiecare
/// pornire ar face optiunile inutilizabile in practica.
/// </summary>
public static class AppSettings
{
    private static readonly string FilePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "DataMover", "settings.json");

    private sealed class Data
    {
        public string Client { get; set; } = "";
        public string OperatorName { get; set; } = "";
        public string Camera { get; set; } = "";
        public string LogoPath { get; set; } = "";
        public string FolderTemplate { get; set; } = NamingTemplate.DefaultTemplate;
        public bool GenerateMhl { get; set; } = true;
        public bool RetryFailedFiles { get; set; } = true;
        public bool EjectWhenDone { get; set; }
        public bool AutoStartOnCard { get; set; }
    }

    private static Data _data = Load();

    private static Data Load()
    {
        try
        {
            if (File.Exists(FilePath))
                return JsonSerializer.Deserialize<Data>(File.ReadAllText(FilePath)) ?? new Data();
        }
        catch { /* fisier corupt/lipsa - pornim de la implicit */ }
        return new Data();
    }

    private static void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(_data));
        }
        catch { /* nescrierea unei preferinte nu trebuie sa blocheze UI-ul */ }
    }

    public static string Client { get => _data.Client; set { _data.Client = value; Save(); } }
    public static string OperatorName { get => _data.OperatorName; set { _data.OperatorName = value; Save(); } }
    public static string Camera { get => _data.Camera; set { _data.Camera = value; Save(); } }
    public static string LogoPath { get => _data.LogoPath; set { _data.LogoPath = value; Save(); } }
    public static string FolderTemplate
    {
        get => string.IsNullOrWhiteSpace(_data.FolderTemplate) ? NamingTemplate.DefaultTemplate : _data.FolderTemplate;
        set { _data.FolderTemplate = value; Save(); }
    }
    public static bool GenerateMhl { get => _data.GenerateMhl; set { _data.GenerateMhl = value; Save(); } }
    public static bool RetryFailedFiles { get => _data.RetryFailedFiles; set { _data.RetryFailedFiles = value; Save(); } }
    public static bool EjectWhenDone { get => _data.EjectWhenDone; set { _data.EjectWhenDone = value; Save(); } }
    public static bool AutoStartOnCard { get => _data.AutoStartOnCard; set { _data.AutoStartOnCard = value; Save(); } }

    /// Notele de filmare sunt singurele care NU se persista — sunt specifice
    /// unui transfer, iar o nota veche aparuta in raportul de maine ar fi o
    /// informatie gresita intr-un document de predare.
    public static string ShootNotes { get; set; } = "";
}
