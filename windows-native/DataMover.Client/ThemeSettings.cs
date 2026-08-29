using System;
using System.IO;
using System.Text.Json;
using Wpf.Ui.Appearance;

namespace DataMover.Client;

/// Selector explicit System/Light/Dark (Regula 18, CLAUDE.md) - lipsea
/// complet pe clientul WPF (App.xaml avea `Theme="Dark"` hardcodat, fara
/// nicio cale sa treci pe Light). Persistat in %AppData%\DataMover\theme.json,
/// acelasi tipar ca HistoryStore/TransferProfileStore.
public enum AppTheme { System, Light, Dark }

public static class ThemeSettings
{
    private static readonly string FilePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "DataMover", "theme.json");

    public static AppTheme Current { get; private set; } = AppTheme.Dark;

    public static void ApplySaved()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                var saved = JsonSerializer.Deserialize<AppTheme>(File.ReadAllText(FilePath));
                Current = saved;
            }
        }
        catch { /* ignora - ramane Dark implicit */ }

        Apply(Current);
    }

    public static void Apply(AppTheme theme)
    {
        Current = theme;
        ApplicationThemeManager.Apply(theme switch
        {
            AppTheme.Light => ApplicationTheme.Light,
            AppTheme.Dark => ApplicationTheme.Dark,
            _ => SystemThemeManager.GetCachedSystemTheme() == SystemTheme.Light
                ? ApplicationTheme.Light
                : ApplicationTheme.Dark,
        });

        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(theme));
        }
        catch { /* setarea tot s-a aplicat vizual, doar nu s-a salvat */ }
    }
}
