using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Threading;
using DataMover.Core.Models;
using DataMover.Core.Services;
using Wpf.Ui.Controls;
using MessageBox = System.Windows.MessageBox;
using MessageBoxButton = System.Windows.MessageBoxButton;
using MessageBoxImage = System.Windows.MessageBoxImage;
using MessageBoxResult = System.Windows.MessageBoxResult;

namespace DataMover.Client;

/// Un disc/volum detectat, afisat in panoul "DISCURI DETECTATE".
public sealed class DriveTile
{
    public string Path { get; init; } = "";
    public string Label { get; init; } = "";
    public string FreeSpaceText { get; init; } = "";
    public System.Windows.Media.ImageSource? IconSource { get; init; }
}

public partial class MainWindow : FluentWindow
{
    private readonly OffloadRunner _runner = new();
    private readonly ObservableCollection<string> _sources = new();
    private readonly ObservableCollection<string> _destinations = new();
    private readonly ObservableCollection<string> _activity = new();
    private readonly ObservableCollection<DriveTile> _drives = new();
    private readonly DispatcherTimer _uiTimer;
    private readonly DispatcherTimer _drivesTimer;
    private bool _wasRunning;

    public MainWindow()
    {
        InitializeComponent();

        SourcesList.ItemsSource = _sources;
        DestinationsList.ItemsSource = _destinations;
        ActivityList.ItemsSource = _activity;
        DrivesList.ItemsSource = _drives;

        VerificationCombo.ItemsSource = Enum.GetValues<VerificationModel>();
        VerificationCombo.SelectedItem = VerificationModel.Md5;

        ChunkSizeCombo.ItemsSource = IOSettings.ChunkSizeChoicesMB.Select(IOSettings.SizeLabel).ToList();
        ChunkSizeCombo.SelectedItem = IOSettings.SizeLabel(IOSettings.DefaultChunkSizeMB);
        RamLimitCombo.ItemsSource = IOSettings.RamLimitChoicesMB.Select(v => v == 0 ? "Fara limita" : IOSettings.SizeLabel(v)).ToList();
        RamLimitCombo.SelectedItem = IOSettings.SizeLabel(1024);

        RefreshProfilesCombo();
        RefreshDrives();

        _runner.ActivityLogged += line => Dispatcher.Invoke(() =>
        {
            _activity.Add(line);
            while (_activity.Count > 200) _activity.RemoveAt(0);
            ActivityScroll.ScrollToEnd();
        });

        // Poller simplu pentru progres/status - la fel ca _poll_log_queue
        // (Python) / binding-ul @Published direct (Mac, aici facem
        // echivalentul prin DispatcherTimer + INotifyPropertyChanged).
        _uiTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(200) };
        _uiTimer.Tick += (_, _) => RefreshUiFromRunner();
        _uiTimer.Start();

        // Reimprospatare periodica a discurilor detectate (2026-08-28) -
        // ca un card SD conectat dupa deschiderea aplicatiei sa apara
        // automat, la fel ca _refreshVolumes (Mac, la fiecare 4s).
        _drivesTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(4) };
        _drivesTimer.Tick += (_, _) => RefreshDrives();
        _drivesTimer.Start();

        VersionText.Text = $"DataMover {UpdateChecker.CurrentVersion}";
        Loaded += async (_, _) =>
        {
            _ = LicenseManager.Shared.RefreshRevocationAsync();
            await CheckForUpdatesAsync(this, respectDismissal: true);
        };
    }

    // ---------------- Versiune, Update Checker, Profil (2026-08-28) ----------------
    // Lipseau complet pe clientul WPF - semnalat de Cristi: "aici nu vad
    // numarul de versiune, update, auto update... numele de la client si
    // ID-ul de la masina si mail-ul". Port al UpdateChecker.swift/.cs
    // (Regula 13/20, CLAUDE.md).

    /// `respectDismissal: true` - verificare automata la lansare, nu
    /// reapare pentru o versiune deja inchisa de user. `false` - verificare
    /// manuala (butonul "Actualizari"/"Cauta actualizari"), arata mereu
    /// rezultatul real chiar daca versiunea a fost respinsa anterior.
    public static async Task CheckForUpdatesAsync(Window owner, bool respectDismissal)
    {
        await UpdateChecker.Shared.CheckAsync();
        var version = UpdateChecker.Shared.AvailableVersion;
        if (version is null)
        {
            if (!respectDismissal)
                MessageBox.Show("Ai deja ultima versiune instalată.", "DataMover", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (respectDismissal && !UpdateChecker.Shared.Mandatory && UpdateChecker.Shared.WasDismissed(version)) return;

        var changes = string.IsNullOrWhiteSpace(UpdateChecker.Shared.Changes) ? "" : $"\n\n{UpdateChecker.Shared.Changes}";
        var result = MessageBox.Show(
            $"Este disponibilă versiunea {version}.{changes}\n\nVrei să actualizezi acum?",
            "Actualizare disponibilă", MessageBoxButton.YesNo, MessageBoxImage.Information);

        if (result == MessageBoxResult.Yes)
        {
            var url = UpdateChecker.Shared.WindowsWpfDownloadUrl;
            if (string.IsNullOrEmpty(url))
            {
                MessageBox.Show(
                    "Versiunea nouă e publicată, dar arhiva pentru clientul Windows nou nu e încă disponibilă la acest link. Descarcă manual de pe gordas.dev.",
                    "DataMover", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }
            await SelfUpdater.DownloadAndInstallAsync(version, url);
        }
        else
        {
            UpdateChecker.Shared.Dismiss();
        }
    }

    private async void OnCheckUpdatesClicked(object sender, RoutedEventArgs e) =>
        await CheckForUpdatesAsync(this, respectDismissal: false);

    private void OnShowProfileClicked(object sender, RoutedEventArgs e) =>
        new ProfileWindow { Owner = this }.ShowDialog();

    // ---------------- Discuri detectate (2026-08-28) ----------------
    // Raportat lipsa la testul real pe Windows: "nu detecteaza sursele, nu
    // se vad hard discurile, cardurile video" - Mac are un grid de discuri
    // (VolumeInfo.swift), Windows nu avea nimic echivalent.

    private void RefreshDrives()
    {
        var tiles = new List<DriveTile>();
        foreach (var drive in DriveInfo.GetDrives())
        {
            if (!drive.IsReady) continue;
            string label;
            try { label = string.IsNullOrEmpty(drive.VolumeLabel) ? drive.Name : $"{drive.VolumeLabel} ({drive.Name})"; }
            catch { label = drive.Name; }
            string freeText;
            try { freeText = $"{FormatBytes(drive.AvailableFreeSpace)} liber din {FormatBytes(drive.TotalSize)}"; }
            catch { freeText = ""; }
            var icon = ShellIcon.GetDriveIcon(drive.RootDirectory.FullName);
            tiles.Add(new DriveTile { Path = drive.RootDirectory.FullName, Label = label, FreeSpaceText = freeText, IconSource = icon });
        }

        // pastram selectia curenta din UI intacta - inlocuim doar continutul
        _drives.Clear();
        foreach (var t in tiles) _drives.Add(t);
    }

    private static string FormatBytes(long bytes)
    {
        double b = bytes;
        string[] units = { "B", "KB", "MB", "GB", "TB" };
        int i = 0;
        while (b >= 1024 && i < units.Length - 1) { b /= 1024; i++; }
        return $"{b:0.#} {units[i]}";
    }

    private void OnAddDriveAsSourceClicked(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).Tag is string path && !_sources.Contains(path)) _sources.Add(path);
    }

    private void OnAddDriveAsDestinationClicked(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).Tag is string path && !_destinations.Contains(path)) _destinations.Add(path);
    }

    // ---------------- Drag & drop din Explorer (2026-08-28) ----------------
    // Raportat lipsa la testul real: "nu functioneaza drag and drop, daca
    // vreau sa trag un folder in sursa/destinatie, nu functioneaza".

    private static void OnFolderDragOver(DragEventArgs e)
    {
        e.Effects = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
        e.Handled = true;
    }

    private static IEnumerable<string> DroppedPaths(DragEventArgs e) =>
        e.Data.GetDataPresent(DataFormats.FileDrop)
            ? (string[])e.Data.GetData(DataFormats.FileDrop)!
            : Array.Empty<string>();

    private void OnSourcesDragOver(object sender, DragEventArgs e) => OnFolderDragOver(e);
    private void OnDestinationsDragOver(object sender, DragEventArgs e) => OnFolderDragOver(e);

    private void OnSourcesDrop(object sender, DragEventArgs e)
    {
        foreach (var path in DroppedPaths(e))
            if (!_sources.Contains(path)) _sources.Add(path);
    }

    private void OnDestinationsDrop(object sender, DragEventArgs e)
    {
        foreach (var path in DroppedPaths(e))
            if (Directory.Exists(path) && !_destinations.Contains(path)) _destinations.Add(path);
    }

    private void RefreshUiFromRunner()
    {
        ProgressBar.Value = _runner.ProgressPercent;
        StatusText.Text = _runner.StatusText;
        SpeedAndUsageText.Text = _runner.IsRunning
            ? $"{_runner.SpeedText}   Buffer Alocat: {_runner.BufferAllocatedText} | Utilizat: {_runner.MemoryUsedText}"
            : "";
        StartButton.IsEnabled = !_runner.IsRunning && _sources.Count > 0 && _destinations.Count > 0;
        CancelButton.IsEnabled = _runner.IsRunning;
        PauseButton.IsEnabled = _runner.IsRunning;
        PauseButton.Content = _runner.IsPaused ? "Continua" : "Pauza";

        // Tranzitie running -> oprit: transferul tocmai s-a terminat.
        // Raportat lipsa la testul real: "la sfarsit nu-mi da optiunea sa
        // deschid folderul destinatie" - acum arata butonul dedicat, plus
        // deschide automat daca userul a bifat optiunea.
        if (_wasRunning && !_runner.IsRunning)
        {
            var anyResult = _runner.LastResults.FirstOrDefault();
            if (anyResult != null)
            {
                OpenDestinationButton.Visibility = Visibility.Visible;
                if (AutoOpenDestCheck.IsChecked == true) OpenLastDestinations();
            }
        }
        _wasRunning = _runner.IsRunning;
    }

    private void OpenLastDestinations()
    {
        foreach (var job in _runner.Jobs)
        {
            var target = Path.Combine(job.DestRoot, job.FolderName);
            if (Directory.Exists(target))
                Process.Start(new ProcessStartInfo("explorer.exe", $"\"{target}\"") { UseShellExecute = true });
        }
    }

    private void OnOpenLastDestinationClicked(object sender, RoutedEventArgs e)
    {
        OpenLastDestinations();
        OpenDestinationButton.Visibility = Visibility.Collapsed;
    }

    // ---------------- Surse / Destinatii ----------------

    private void OnAddSourceClicked(object sender, RoutedEventArgs e)
    {
        var path = PickFolder();
        if (path != null && !_sources.Contains(path)) _sources.Add(path);
    }

    private void OnRemoveSourceClicked(object sender, RoutedEventArgs e)
    {
        if (SourcesList.SelectedItem is string s) _sources.Remove(s);
    }

    private void OnAddDestinationClicked(object sender, RoutedEventArgs e)
    {
        var path = PickFolder();
        if (path != null && !_destinations.Contains(path)) _destinations.Add(path);
    }

    private void OnRemoveDestinationClicked(object sender, RoutedEventArgs e)
    {
        if (DestinationsList.SelectedItem is string s) _destinations.Remove(s);
    }

    private static string? PickFolder()
    {
        // System.Windows.Forms.FolderBrowserDialog ar cere o referinta
        // suplimentara (WinForms) doar pentru un dialog - OpenFolderDialog
        // (Microsoft.Win32, .NET 8+) e nativ WPF, fara dependinte noi -
        // acelasi API folosit deja in GDCVaultWin (EntryDetailControl).
        var dlg = new Microsoft.Win32.OpenFolderDialog();
        return dlg.ShowDialog() == true ? dlg.FolderName : null;
    }

    // ---------------- I/O & Memorie: preset-uri ----------------

    private void OnPresetClicked(object sender, RoutedEventArgs e)
    {
        var preset = sender switch
        {
            _ when sender == PresetEcoBtn => IOSettings.Presets[0],
            _ when sender == PresetStandardBtn => IOSettings.Presets[1],
            _ when sender == PresetHighBtn => IOSettings.Presets[2],
            _ when sender == PresetExtremeBtn => IOSettings.Presets[3],
            _ => IOSettings.Presets[1],
        };
        ChunkSizeCombo.SelectedItem = IOSettings.SizeLabel(preset.ChunkSizeMB);
        RamLimitCombo.SelectedItem = preset.RamLimitMB == 0 ? "Fara limita" : IOSettings.SizeLabel(preset.RamLimitMB);
    }

    private int SelectedChunkSizeMB() =>
        IOSettings.ChunkSizeChoicesMB.FirstOrDefault(v => IOSettings.SizeLabel(v) == (string)ChunkSizeCombo.SelectedItem, IOSettings.DefaultChunkSizeMB);

    private int SelectedRamLimitMB() =>
        (string)RamLimitCombo.SelectedItem == "Fara limita"
            ? 0
            : IOSettings.RamLimitChoicesMB.FirstOrDefault(v => v != 0 && IOSettings.SizeLabel(v) == (string)RamLimitCombo.SelectedItem, 1024);

    // ---------------- Profile de transfer ----------------

    private void RefreshProfilesCombo()
    {
        ProfilesCombo.ItemsSource = TransferProfileStore.Shared.Profiles.Select(p => p.Name).ToList();
    }

    private void OnSaveProfileClicked(object sender, RoutedEventArgs e)
    {
        var name = PromptForText("Salveaza profil", "Nume profil (ex. \"Backup RAW pe SSD\")");
        if (string.IsNullOrWhiteSpace(name)) return;

        TransferProfileStore.Shared.Upsert(new TransferProfile
        {
            Name = name.Trim(),
            SourcePaths = _sources.ToList(),
            DestinationPaths = _destinations.ToList(),
            VerificationModel = (VerificationModel)VerificationCombo.SelectedItem,
            ExclusionsText = ExclusionsBox.Text,
            ChunkSizeMB = SelectedChunkSizeMB(),
            RamLimitMB = SelectedRamLimitMB(),
        });
        RefreshProfilesCombo();
        ProfilesCombo.SelectedItem = name.Trim();
    }

    private void OnLoadProfileClicked(object sender, RoutedEventArgs e)
    {
        if (ProfilesCombo.SelectedItem is not string name) return;
        var profile = TransferProfileStore.Shared.Profiles.FirstOrDefault(p => p.Name == name);
        if (profile == null) return;

        _sources.Clear();
        foreach (var s in profile.SourcePaths.Where(Directory.Exists)) _sources.Add(s);
        _destinations.Clear();
        foreach (var d in profile.DestinationPaths.Where(Directory.Exists)) _destinations.Add(d);
        VerificationCombo.SelectedItem = profile.VerificationModel;
        ExclusionsBox.Text = profile.ExclusionsText;
        ChunkSizeCombo.SelectedItem = IOSettings.SizeLabel(profile.ChunkSizeMB);
        RamLimitCombo.SelectedItem = profile.RamLimitMB == 0 ? "Fara limita" : IOSettings.SizeLabel(profile.RamLimitMB);
    }

    private void OnDeleteProfileClicked(object sender, RoutedEventArgs e)
    {
        if (ProfilesCombo.SelectedItem is not string name) return;
        var profile = TransferProfileStore.Shared.Profiles.FirstOrDefault(p => p.Name == name);
        if (profile == null) return;
        TransferProfileStore.Shared.Delete(profile);
        RefreshProfilesCombo();
    }

    // ---------------- Start / deduplicare / Pauza / Anuleaza ----------------

    private List<string> ParseExclusions() =>
        ExclusionsBox.Text.Split(',').Select(s => s.Trim()).Where(s => s.Length > 0).ToList();

    private void OnStartClicked(object sender, RoutedEventArgs e)
    {
        if (_sources.Count == 0 || _destinations.Count == 0) return;

        var project = ProjectBox.Text.Trim();
        var card = CardBox.Text.Trim();
        var todayFolderName = OffloadRunner.FolderName(project, card);

        // Cautam INTAI un folder deja existent cu acelasi proiect/card,
        // indiferent de data (fix 2026-08-28 - vezi comentariul din
        // OffloadRunner.FindExistingFolderName).
        var existingName = OffloadRunner.FindExistingFolderName(_destinations, project, card) ?? todayFolderName;

        if (OffloadRunner.FolderHasRealFiles(_destinations, existingName))
        {
            var dialog = new DuplicateDialog(existingName) { Owner = this };
            dialog.ShowDialog();
            switch (dialog.Result)
            {
                case DuplicateChoice.Resume:
                    StartTransfer(resume: true, folderNameOverride: existingName);
                    break;
                case DuplicateChoice.NewFolder:
                    var freeName = OffloadRunner.FreeFolderName(todayFolderName, _destinations);
                    StartTransfer(resume: false, folderNameOverride: freeName);
                    break;
                case DuplicateChoice.Overwrite:
                    OffloadRunner.ClearExistingFolders(_destinations, existingName);
                    StartTransfer(resume: false, folderNameOverride: existingName);
                    break;
                case DuplicateChoice.Cancel:
                default:
                    break;
            }
        }
        else
        {
            StartTransfer(resume: false, folderNameOverride: null);
        }
    }

    private void StartTransfer(bool resume, string? folderNameOverride)
    {
        _runner.ChunkSizeMB = SelectedChunkSizeMB();
        _runner.RamLimitMB = SelectedRamLimitMB();
        _activity.Clear();
        OpenDestinationButton.Visibility = Visibility.Collapsed;
        _runner.Start(
            sources: _sources.ToList(),
            destinations: _destinations.ToList(),
            model: (VerificationModel)VerificationCombo.SelectedItem,
            exclusions: ParseExclusions(),
            resume: resume,
            project: ProjectBox.Text.Trim(),
            card: CardBox.Text.Trim(),
            folderNameOverride: folderNameOverride);
    }

    private void OnPauseClicked(object sender, RoutedEventArgs e) => _runner.TogglePause();

    private void OnCancelClicked(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show("Sigur vrei sa anulezi transferul in curs?", "DataMover",
                MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes)
        {
            _runner.Cancel();
        }
    }

    private void OnShowHistoryClicked(object sender, RoutedEventArgs e)
    {
        new HistoryWindow { Owner = this }.ShowDialog();
    }

    /// Prompt minimal de text (nume de profil) - fara dependinta de
    /// Microsoft.VisualBasic.Interaction.InputBox (WinForms), doar un
    /// Window WPF simplu construit in cod.
    private string? PromptForText(string title, string label)
    {
        var win = new Window
        {
            Title = title, Width = 380, Height = 140, Owner = this,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode = ResizeMode.NoResize,
        };
        var panel = new System.Windows.Controls.StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(new System.Windows.Controls.TextBlock { Text = label, Margin = new Thickness(0, 0, 0, 8) });
        var textBox = new System.Windows.Controls.TextBox();
        panel.Children.Add(textBox);
        var buttonRow = new System.Windows.Controls.StackPanel { Orientation = System.Windows.Controls.Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 16, 0, 0) };
        string? result = null;
        var okButton = new System.Windows.Controls.Button { Content = "Salveaza", Width = 90, Margin = new Thickness(0, 0, 8, 0), IsDefault = true };
        okButton.Click += (_, _) => { result = textBox.Text; win.Close(); };
        var cancelButton = new System.Windows.Controls.Button { Content = "Anuleaza", Width = 90, IsCancel = true };
        buttonRow.Children.Add(okButton);
        buttonRow.Children.Add(cancelButton);
        panel.Children.Add(buttonRow);
        win.Content = panel;
        win.ShowDialog();
        return result;
    }
}
