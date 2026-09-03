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

/// [2026-09-03] Un card in coada de descarcare. Fiecare are propriul nume
/// de card, deci propriul folder la destinatie — spre deosebire de mai
/// multe surse adaugate simultan, care ajung toate in ACELASI folder.
public sealed class QueueItem
{
    public string Source { get; init; } = "";
    public string Card { get; init; } = "";
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

    // [2026-09-03] Ultimii parametri de start, retinuti ca reincercarea din
    // dialogul de spatiu insuficient sa reporneasca EXACT acelasi transfer.
    private bool _lastStartResume = true;
    private string? _lastStartFolderOverride;

    // [2026-09-03] Coada de carduri (vezi QueueItem/StartNextInQueue) —
    // descarcarea mai multor carduri, unul dupa altul, nesupravegheat.
    private readonly ObservableCollection<QueueItem> _cardQueue = new();
    private bool _queueRunning;
    /// Radacinile de volum vazute la ultima verificare — baza pentru
    /// detectarea unui card NOU introdus. `null` = inca n-am facut niciun
    /// poll: prima trecere stabileste doar baseline-ul, fara sa considere
    /// "nou" tot ce era deja conectat la pornirea aplicatiei.
    private HashSet<string>? _knownDriveRoots;

    /// Metadatele curente, compuse din campurile din bara de sus si din
    /// Setari — o singura sursa de adevar pentru numele folderului
    /// (NamingTemplate) si antetul rapoartelor (PDF/HTML).
    private ProductionMeta CurrentMeta() => new()
    {
        Project = ProjectBox.Text.Trim(),
        Card = CardBox.Text.Trim(),
        Client = AppSettings.Client,
        OperatorName = AppSettings.OperatorName,
        Camera = AppSettings.Camera,
        Notes = AppSettings.ShootNotes,
        LogoPath = AppSettings.LogoPath,
    };

    private void OnToggleSettingsPopup(object sender, RoutedEventArgs e)
    {
        SettingsPopup.IsOpen = !SettingsPopup.IsOpen;
        if (SettingsPopup.IsOpen) RefreshCloudRemotes();
    }

    private const string CloudDisabledLabel = "Dezactivat";

    /// Reimprospateaza lista de conturi Cloud (rclone listremotes), headless,
    /// pe un thread de fundal - la fel ca DependencyDot de mai sus (Regula 4).
    private void RefreshCloudRemotes()
    {
        var previouslySelected = CloudRemoteCombo.SelectedItem as string ?? CloudDisabledLabel;
        Task.Run(() =>
        {
            var available = CloudSyncService.IsAvailable();
            var remotes = available ? CloudSyncService.ListRemotes() : new List<string>();
            Dispatcher.Invoke(() =>
            {
                CloudUnavailableText.Visibility = available ? Visibility.Collapsed : Visibility.Visible;
                CloudRemotePanel.Visibility = available ? Visibility.Visible : Visibility.Collapsed;
                var items = new List<string> { CloudDisabledLabel }.Concat(remotes).ToList();
                CloudRemoteCombo.ItemsSource = items;
                CloudRemoteCombo.SelectedItem = items.Contains(previouslySelected) ? previouslySelected : CloudDisabledLabel;
            });
        });
    }

    private void OnCloudRemoteChanged(object sender, System.Windows.Controls.SelectionChangedEventArgs e)
    {
        var hasRemote = CloudRemoteCombo.SelectedItem is string s && s != CloudDisabledLabel;
        CloudFolderPanel.Visibility = hasRemote ? Visibility.Visible : Visibility.Collapsed;
        CloudHintText.Visibility = hasRemote ? Visibility.Visible : Visibility.Collapsed;
    }

    private string SelectedCloudRemote()
    {
        var s = CloudRemoteCombo.SelectedItem as string ?? CloudDisabledLabel;
        return s == CloudDisabledLabel ? "" : s;
    }

    private string SelectedCloudFolder() => CloudFolderBox.Text.Trim();

    private void ApplyCloudSelection(string remote, string folder)
    {
        var target = string.IsNullOrEmpty(remote) ? CloudDisabledLabel : remote;
        if (((List<string>?)CloudRemoteCombo.ItemsSource)?.Contains(target) == true)
            CloudRemoteCombo.SelectedItem = target;
        CloudFolderBox.Text = folder;
    }

    public MainWindow()
    {
        InitializeComponent();
        MainTitleBar.Title = $"DataMover {UpdateChecker.CurrentVersion}";
        ThemeSettings.ApplySaved();
        DependencyDot.Fill = SystemDependencyChecker.AllRequiredPresent(SystemDependencyChecker.CheckAll())
            ? System.Windows.Media.Brushes.MediumSeaGreen
            : System.Windows.Media.Brushes.OrangeRed;

        SourcesList.ItemsSource = _sources;
        DestinationsList.ItemsSource = _destinations;
        ActivityList.ItemsSource = _activity;
        DrivesList.ItemsSource = _drives;

        VerificationCombo.ItemsSource = Enum.GetValues<VerificationModel>();
        // [2026-09-03] Implicit xxHash64 (nu MD5): acelasi implicit ca la
        // ofloaderele profesionale, cateva ori mai rapid la verificare pe
        // acelasi grad de siguranta practica. Profilele salvate anterior
        // isi pastreaza algoritmul lor, nu sunt rescrise.
        VerificationCombo.SelectedItem = VerificationModel.XxHash64;

        // [2026-09-03] Coada de carduri + preferintele persistate.
        CardQueueList.ItemsSource = _cardQueue;
        ClientBox.Text = AppSettings.Client;
        OperatorBox.Text = AppSettings.OperatorName;
        CameraBox.Text = AppSettings.Camera;
        FolderTemplateBox.Text = AppSettings.FolderTemplate;
        LogoPathText.Text = string.IsNullOrEmpty(AppSettings.LogoPath)
            ? "(niciun logo)" : Path.GetFileName(AppSettings.LogoPath);
        GenerateMhlCheck.IsChecked = AppSettings.GenerateMhl;
        RetryFailedCheck.IsChecked = AppSettings.RetryFailedFiles;
        EjectWhenDoneCheck.IsChecked = AppSettings.EjectWhenDone;
        AutoStartOnCardCheck.IsChecked = AppSettings.AutoStartOnCard;

        ChunkSizeCombo.ItemsSource = IOSettings.ChunkSizeChoicesMB.Select(IOSettings.SizeLabel).ToList();
        ChunkSizeCombo.SelectedItem = IOSettings.SizeLabel(IOSettings.DefaultChunkSizeMB);
        RamLimitCombo.ItemsSource = IOSettings.RamLimitChoicesMB.Select(v => v == 0 ? "Fara limita" : IOSettings.SizeLabel(v)).ToList();
        RamLimitCombo.SelectedItem = IOSettings.SizeLabel(1024);

        CloudRemoteCombo.ItemsSource = new List<string> { CloudDisabledLabel };
        CloudRemoteCombo.SelectedItem = CloudDisabledLabel;

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
        UpdateFolderPreview();
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

    // ---------------- Setari persistate (2026-09-03) ----------------
    // Fiecare control isi scrie valoarea imediat (AppSettings salveaza in
    // %AppData%\DataMover\settings.json) - fara buton "Salveaza", la fel ca
    // @AppStorage pe Mac.

    private void OnProductionMetaChanged(object sender, System.Windows.Controls.TextChangedEventArgs e)
    {
        if (!IsLoaded) return;
        AppSettings.Client = ClientBox.Text;
        AppSettings.OperatorName = OperatorBox.Text;
        AppSettings.Camera = CameraBox.Text;
        AppSettings.ShootNotes = NotesBox.Text;
        AppSettings.FolderTemplate = FolderTemplateBox.Text;
        UpdateFolderPreview();
    }

    /// Previzualizare live: userul vede EXACT numele folderului care se va
    /// crea, inainte sa porneasca transferul — un sablon gresit descoperit
    /// dupa 2 TB copiati nu se mai poate corecta fara sa muti folderul.
    private void UpdateFolderPreview()
    {
        if (FolderPreviewText == null) return;
        FolderPreviewText.Text = "Va rezulta: " + OffloadRunner.FolderName(
            ProjectBox.Text.Trim(), CardBox.Text.Trim(), AppSettings.FolderTemplate,
            AppSettings.Camera, AppSettings.OperatorName);
    }

    private void OnToggleSettingChanged(object sender, RoutedEventArgs e)
    {
        if (!IsLoaded) return;
        AppSettings.GenerateMhl = GenerateMhlCheck.IsChecked == true;
        AppSettings.RetryFailedFiles = RetryFailedCheck.IsChecked == true;
        AppSettings.EjectWhenDone = EjectWhenDoneCheck.IsChecked == true;
        AppSettings.AutoStartOnCard = AutoStartOnCardCheck.IsChecked == true;
    }

    private void OnChooseLogoClicked(object sender, RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Filter = "Imagini (*.png;*.jpg;*.jpeg;*.gif)|*.png;*.jpg;*.jpeg;*.gif",
            Title = "Alege logo-ul pentru rapoarte",
        };
        if (dialog.ShowDialog() == true)
        {
            AppSettings.LogoPath = dialog.FileName;
            LogoPathText.Text = Path.GetFileName(dialog.FileName);
        }
    }

    private void OnClearLogoClicked(object sender, RoutedEventArgs e)
    {
        AppSettings.LogoPath = "";
        LogoPathText.Text = "(niciun logo)";
    }

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

        // [2026-09-03] Mod nesupravegheat: un card nou introdus intra direct
        // in coada si porneste singur. Prima trecere stabileste doar
        // baseline-ul (`_knownDriveRoots == null`) — altfel orice card deja
        // conectat la pornirea aplicatiei ar declansa fals o descarcare.
        var roots = new HashSet<string>(tiles.Select(t => t.Path), StringComparer.OrdinalIgnoreCase);
        if (_knownDriveRoots != null && AppSettings.AutoStartOnCard && _destinations.Count > 0)
        {
            var appeared = roots.Where(r => !_knownDriveRoots.Contains(r)).ToList();
            foreach (var root in appeared)
            {
                var label = tiles.FirstOrDefault(t => t.Path == root)?.Label ?? root;
                _cardQueue.Add(new QueueItem { Source = root, Card = CleanCardName(label) });
                _runner.LogExternal($"Card detectat automat: {label} — adăugat în coadă.");
            }
            if (appeared.Count > 0 && !_runner.IsRunning) StartNextInQueue();
        }
        _knownDriveRoots = roots;
    }

    /// Eticheta unui volum ("CARD_A (E:\)") nu e un nume de folder valid —
    /// pastram doar partea utila, fara calea dintre paranteze.
    private static string CleanCardName(string label)
    {
        var idx = label.IndexOf(" (", StringComparison.Ordinal);
        var name = idx > 0 ? label[..idx] : label;
        return name.Trim().Length == 0 ? "Card" : name.Trim();
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
        if (((FrameworkElement)sender).Tag is string path && !_sources.Contains(path))
        {
            _sources.Add(path);
            DetectCard(path);
        }
    }

    // ---------------- Detectie card, coada (2026-09-03) ----------------

    /// Recunoasterea structurii de card se face pe un thread de fundal:
    /// enumerarea unui card plin (zeci de mii de fisiere) ar bloca UI-ul
    /// exact cand userul tocmai a adaugat cardul. Rezultatul se scrie in
    /// feed-ul de activitate, unde userul se uita deja.
    private void DetectCard(string path)
    {
        Task.Run(() =>
        {
            var info = CameraCardDetector.Detect(path);
            var parentCard = info == null ? CameraCardDetector.ParentLooksLikeCard(path) : null;
            Dispatcher.Invoke(() =>
            {
                if (info != null)
                {
                    _runner.LogExternal($"{Path.GetFileName(path.TrimEnd('\\'))}: {info.Summary}");
                    foreach (var warning in info.Warnings)
                        _runner.LogExternal($"⚠ {warning}");
                }
                else if (parentCard != null)
                {
                    // Cazul cel mai scump de pe platou: s-a selectat un
                    // subfolder al cardului, nu radacina lui.
                    _runner.LogExternal($"⚠ {Path.GetFileName(path.TrimEnd('\\'))} pare a fi un SUBFOLDER al cardului {parentCard} — copiat singur, pierzi metadatele cardului.");
                }
            });
        });
    }

    private void OnAddToQueueClicked(object sender, RoutedEventArgs e)
    {
        var source = _sources.FirstOrDefault();
        if (source == null) return;
        var card = CardBox.Text.Trim();
        if (card.Length == 0) card = CleanCardName(Path.GetFileName(source.TrimEnd('\\')));
        _cardQueue.Add(new QueueItem { Source = source, Card = card });
        // Sursa iese din lista curenta: e "predata" cozii, altfel ar fi
        // copiata de doua ori (o data acum, o data cand ii vine randul).
        _sources.Remove(source);
        CardBox.Text = "";
    }

    private void OnRemoveFromQueueClicked(object sender, RoutedEventArgs e)
    {
        if (((FrameworkElement)sender).Tag is QueueItem item) _cardQueue.Remove(item);
    }

    private void OnStartQueueClicked(object sender, RoutedEventArgs e) => StartNextInQueue();

    /// Porneste (sau continua) coada. Fiecare card primeste propriul folder
    /// la destinatie. Reluarea e implicit ACTIVA in coada: modul
    /// nesupravegheat nu poate astepta un raspuns la dialogul de duplicate.
    private void StartNextInQueue()
    {
        if (_cardQueue.Count == 0 || _destinations.Count == 0 || _runner.IsRunning)
        {
            _queueRunning = false;
            return;
        }
        var next = _cardQueue[0];
        _cardQueue.RemoveAt(0);
        _queueRunning = true;
        _sources.Clear();
        _sources.Add(next.Source);
        CardBox.Text = next.Card;
        var existing = OffloadRunner.FindExistingFolderName(
            _destinations, ProjectBox.Text.Trim(), next.Card,
            AppSettings.FolderTemplate, AppSettings.Camera, AppSettings.OperatorName);
        StartTransfer(resume: true, folderNameOverride: existing);
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
            if (!_sources.Contains(path))
            {
                _sources.Add(path);
                DetectCard(path);
            }
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
            bool wasCancelled = anyResult?.Cancelled ?? true;

            // [2026-09-03] Coada continua singura cu urmatorul card. O
            // anulare opreste TOATA coada — daca userul a apasat Anuleaza,
            // nu vrea sa porneasca imediat cardul urmator.
            if (_queueRunning)
            {
                if (wasCancelled)
                {
                    _queueRunning = false;
                    _runner.LogExternal($"Coadă oprită (transfer anulat) — au rămas {_cardQueue.Count} card(uri).");
                }
                else if (_cardQueue.Count > 0)
                {
                    _wasRunning = _runner.IsRunning;
                    StartNextInQueue();
                    return;
                }
                else
                {
                    _queueRunning = false;
                    _runner.LogExternal("Coadă terminată — toate cardurile au fost descărcate.");
                }
            }

            if (anyResult != null)
            {
                OpenDestinationButton.Visibility = Visibility.Visible;
                if (AutoOpenDestCheck.IsChecked == true && !wasCancelled) OpenLastDestinations();
            }
        }
        _wasRunning = _runner.IsRunning;

        // Acces refuzat de Windows (2026-09-03) - vezi OffloadEngine.
        // IsPermissionError / OffloadRunner.PermissionErrorPath. Arata o
        // singura data un dialog cu optiunea de a relansa aplicatia ca
        // Administrator, in loc sa lase userul sa vada doar "EROARE"
        // generic in raport.
        if (_runner.PermissionErrorPath is { } deniedPath)
        {
            _runner.AcknowledgePermissionError();
            var result = MessageBox.Show(
                $"DataMover nu are voie să scrie la:\n{deniedPath}\n\n" +
                "Fișierul/folderul e protejat de Windows (deseori aparține altui utilizator sau unei zone de sistem) — copierea are nevoie de drepturi de Administrator.\n\n" +
                "Repornești aplicația ca Administrator?",
                "Acces la disc refuzat",
                MessageBoxButton.YesNo,
                MessageBoxImage.Warning);
            if (result == MessageBoxResult.Yes) RelaunchAsAdministrator();
        }
    }

    /// Relanseaza acest executabil cu promptul NATIV UAC ("Verb = runas")
    /// - NICIODATA elevare silentioasa. Aplicatia curenta se inchide dupa
    /// ce noul proces a fost lansat cu succes; daca userul refuza promptul
    /// UAC, ramane pe procesul curent, neelevat.
    private void RelaunchAsAdministrator()
    {
        try
        {
            var exePath = Process.GetCurrentProcess().MainModule?.FileName;
            if (string.IsNullOrEmpty(exePath)) return;
            Process.Start(new ProcessStartInfo(exePath) { UseShellExecute = true, Verb = "runas" });
            Application.Current.Shutdown();
        }
        catch (System.ComponentModel.Win32Exception)
        {
            // Userul a apasat "Nu" pe promptul UAC - ramanem pe procesul curent.
        }
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
            CloudRemote = SelectedCloudRemote(),
            CloudRemoteFolder = SelectedCloudFolder(),
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
        ApplyCloudSelection(profile.CloudRemote, profile.CloudRemoteFolder);
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
        var template = AppSettings.FolderTemplate;
        var camera = AppSettings.Camera;
        var operatorName = AppSettings.OperatorName;
        var todayFolderName = OffloadRunner.FolderName(project, card, template, camera, operatorName);

        // Cautam INTAI un folder deja existent cu acelasi proiect/card,
        // indiferent de data (fix 2026-08-28 - vezi comentariul din
        // OffloadRunner.FindExistingFolderName).
        var existingName = OffloadRunner.FindExistingFolderName(
            _destinations, project, card, template, camera, operatorName) ?? todayFolderName;

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

    private void StartTransfer(bool resume, string? folderNameOverride, bool ignoreSpaceWarning = false)
    {
        _runner.ChunkSizeMB = SelectedChunkSizeMB();
        _runner.RamLimitMB = SelectedRamLimitMB();
        _lastStartResume = resume;
        _lastStartFolderOverride = folderNameOverride;
        OpenDestinationButton.Visibility = Visibility.Collapsed;
        _runner.Start(
            sources: _sources.ToList(),
            destinations: _destinations.ToList(),
            model: (VerificationModel)VerificationCombo.SelectedItem,
            exclusions: ParseExclusions(),
            resume: resume,
            meta: CurrentMeta(),
            folderNameOverride: folderNameOverride,
            cloudRemote: SelectedCloudRemote(),
            cloudRemoteFolder: SelectedCloudFolder(),
            folderTemplate: AppSettings.FolderTemplate,
            generateMhl: AppSettings.GenerateMhl,
            retryFailedFiles: AppSettings.RetryFailedFiles,
            ejectSourceWhenDone: AppSettings.EjectWhenDone,
            ignoreSpaceWarning: ignoreSpaceWarning,
            appVersion: UpdateChecker.CurrentVersion);

        // [2026-09-03] Spatiu insuficient la destinatie, verificat INAINTE de
        // a copia primul octet (vezi OffloadRunner.CheckSpace). Nu blocam
        // definitiv: aratam cifrele reale si lasam userul sa forteze.
        if (_runner.LastSpaceShortfall is OffloadRunner.SpaceShortfall shortfall)
        {
            _runner.AcknowledgeSpaceShortfall();
            var answer = MessageBox.Show(
                $"Pe „{shortfall.Destination}\" mai sunt {FormatBytes(shortfall.Free)} liberi, " +
                $"dar transferul are nevoie de {FormatBytes(shortfall.Needed)}.\n\n" +
                "Eliberează spațiu sau alege altă destinație.\n\nVrei să continui oricum?",
                "Spațiu insuficient la destinație", MessageBoxButton.YesNo, MessageBoxImage.Warning);
            if (answer == MessageBoxResult.Yes)
                StartTransfer(resume, folderNameOverride, ignoreSpaceWarning: true);
            return;
        }

        // Plafon de proba depasit (2026-08-30) - vezi LicenseManager.
        // TrialMaxTransferBytes / OffloadRunner.TrialLimitExceededBytes.
        if (_runner.TrialLimitExceededBytes is long totalBytes)
        {
            var sizeText = IOSettings.SizeLabel((int)(totalBytes / (1024 * 1024)));
            var result = MessageBox.Show(
                $"Acest transfer ({sizeText}) depășește plafonul de 2 GB per transfer al versiunii de probă.\n\n" +
                "Activează licența pentru acces complet, fără limită de dimensiune.",
                "Plafon de probă depășit", MessageBoxButton.OKCancel, MessageBoxImage.Warning);
            if (result == MessageBoxResult.OK) new ProfileWindow { Owner = this }.ShowDialog();
        }
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
