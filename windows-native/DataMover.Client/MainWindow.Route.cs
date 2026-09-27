using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using DataMover.Core.Diagnostics;
using DataMover.Core.Domain;
using DataMover.Core.Services;

namespace DataMover.Client;

/// <summary>
/// Traseul (sursa → verificare → copii), incidentele, clasificarea mediilor si
/// diagnosticul. Separat de restul ferestrei ca sa poata fi citit si testat
/// independent; foloseste aceleasi reguli (Core) ca runner-ul.
/// </summary>
public partial class MainWindow
{
    private bool _blockingNow;
    private bool _showingResult;

    private static string Fmt(long b) => FormatBytes(b);

    private DeviceKind KindOf(string path) =>
        _media.TryGetValue(path, out var m) ? m.Kind : (IsDriveRoot(path) ? DeviceKind.ExternalDevice : DeviceKind.Folder);

    private static bool IsDriveRoot(string p)
    {
        try { var full = Path.GetFullPath(p); return string.Equals(full.TrimEnd('\\'), (Path.GetPathRoot(full) ?? "").TrimEnd('\\'), StringComparison.OrdinalIgnoreCase); }
        catch { return false; }
    }

    private string KindLine(string path)
    {
        var parts = new List<string> { RouteText.KindLabel(KindOf(path)) };
        if (_media.TryGetValue(path, out var m) && m.Connection != null) parts.Add(m.Connection);
        if (_cardInfo.TryGetValue(path, out var ci) && ci != null) parts.Add(ci.Summary);
        return string.Join(" · ", parts);
    }

    /// Clasificare in fundal (WMI poate dura), apoi reimprospatare.
    private void ClassifyInBackground(IEnumerable<string> paths)
    {
        var todo = paths.Where(p => !_media.ContainsKey(p)).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        if (todo.Count == 0) return;
        Task.Run(() =>
        {
            var found = todo.Select(p => (p, m: Classify(p))).ToList();
            Dispatcher.Invoke(() =>
            {
                foreach (var (p, m) in found) _media[p] = m;
                RefreshDrives();
                RefreshRoute();
            });
        });
    }

    private MediaClass Classify(string path)
    {
#if DEBUG
        if (UiTest.DemoKind(path) is DeviceKind demo) return new MediaClass(demo, Confidence.Certain, "date demo", UiTest.DemoConnection(demo));
#endif
        var card = _cardInfo.TryGetValue(path, out var ci) && ci != null;
        return WindowsMediaProbe.Classify(path, card);
    }

    /// Masoara octetii de copiat si structura de card, per sursa, in fundal.
    private void ScanSourcesInBackground()
    {
        var sources = _sources.ToList();
        ClassifyInBackground(sources.Concat(_destinations));
        Task.Run(() =>
        {
            var bytes = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
            var cards = new Dictionary<string, CameraCardInfo?>(StringComparer.OrdinalIgnoreCase);
            foreach (var s in sources)
            {
                try
                {
                    bytes[s] = Directory.Exists(s) ? FileScanner.ListAllFiles(s, Array.Empty<string>()).Sum(f => f.Size)
                        : File.Exists(s) ? new FileInfo(s).Length : 0;
                    cards[s] = Directory.Exists(s) ? CameraCardDetector.Detect(s) : null;
                }
                catch { /* sursa disparuta intre timp: preflight o semnaleaza */ }
            }
            Dispatcher.Invoke(() =>
            {
                foreach (var kv in bytes) _bytesBySource[kv.Key] = kv.Value;
                foreach (var kv in cards) _cardInfo[kv.Key] = kv.Value;
                RefreshRoute();
            });
        });
    }

    private static void Sync(ObservableCollection<EndpointTile> target, List<EndpointTile> fresh)
    {
        for (int i = 0; i < fresh.Count; i++)
        {
            if (i < target.Count) { if (target[i] != fresh[i]) target[i] = fresh[i]; }
            else target.Add(fresh[i]);
        }
        while (target.Count > fresh.Count) target.RemoveAt(target.Count - 1);
    }

    private void OnProjectOrCardChanged(object sender, TextChangedEventArgs e)
    {
        if (!IsLoaded) return;
        UpdateFolderPreview();
        RefreshRoute();
    }

    private void OnToggleQueuePopup(object sender, RoutedEventArgs e) => QueuePopup.IsOpen = !QueuePopup.IsOpen;

    /// Traseul + incidentele, pentru etapa curenta (pregatire / transfer / rezultat).
    private void RefreshRoute()
    {
        var running = _runner.IsRunning;
        var hasResult = !running && _showingResult && _runner.LastResults.Count > 0;
        UpdateRouteFlow(RouteFlow.StageOf(running, _runner.IsPaused, hasResult));
        long incoming = _sources.Sum(s => _bytesBySource.TryGetValue(s, out var b) ? b : 0);

        FolderPathText.Text = OffloadRunner.FolderName(ProjectBox.Text.Trim(), CardBox.Text.Trim(), AppSettings.FolderTemplate,
            AppSettings.Camera, AppSettings.OperatorName);
        QueueButton.Content = _cardQueue.Count > 0 ? $"Coadă ({_cardQueue.Count})" : "Coadă";

        // --- Surse ---
        var src = _sources.Select((p, i) =>
        {
            var known = _bytesBySource.TryGetValue(p, out var b);
            var card = _cardInfo.TryGetValue(p, out var ci) ? ci : null;
            var warn = card != null && card.Warnings.Count > 0;
            // Cu o singura sursa, progresul global e chiar al ei; cu mai multe nu
            // avem progres per sursa, deci nu il inventam.
            var own = running && _sources.Count == 1;
            return new EndpointTile(p, DisplayName(p), KindOf(p), _sources.Count > 1 ? $"SURSA {i + 1}" : "SURSĂ", KindLine(p),
                (running ? "online · citire" : "online") + (warn ? " · ⚠ avertisment" : ""),
                own ? $"{_runner.ProgressPercent}%" : known ? Fmt(b) : "…",
                own ? "citit" : running ? "în transferul comun" : !known ? "se măsoară" : _showingResult ? "citit o dată" : "de copiat",
                running ? "" : Directory.Exists(p) ? "" : "⚠ sursa nu mai există", own ? _runner.ProgressPercent : 0, own, false, !running);
        }).ToList();
        Sync(_sourceTiles, src);

        // --- Copii ---
        var dst = _destinations.Select((p, i) =>
        {
            var ctx = _runner.Contexts.FirstOrDefault(c => string.Equals(c.DestRoot, p, StringComparison.OrdinalIgnoreCase));
            var res = _runner.LastResults.FirstOrDefault(r => string.Equals(r.DestRoot, p, StringComparison.OrdinalIgnoreCase));
            long free = 0, total = 0;
            try { var di = new DriveInfo(Path.GetPathRoot(Path.GetFullPath(p))!); if (di.IsReady) { free = di.AvailableFreeSpace; total = di.TotalSize; } } catch { }
            var online = Directory.Exists(p);
            if (running && ctx != null)
            {
                var done = ctx.OkCount + ctx.SkipCount;
                return new EndpointTile(p, DisplayName(p), KindOf(p), $"COPIA {i + 1}", KindLine(p),
                    (online ? "online · scriere" : "offline") + (ctx.FailCount > 0 ? $" · ⚠ {ctx.FailCount} neconfirmate" : ""),
                    $"{done}", "fișiere confirmate", "", _runner.ProgressPercent, true, !online, false);
            }
            if (res != null && !running)
            {
                var verdict = res.Cancelled ? "anulat" : res.FailCount > 0 ? "✕ neconfirmat" : res.RecoveredCount > 0 ? "✓ verificat, cu avertismente" : "✓ verificat";
                var sec = res.FailCount > 0 ? $"{res.FailCount} neconfirmate · raport CSV lângă date" : res.MhlPath != null ? "MHL + PDF + CSV scrise" : "PDF + CSV scrise";
                return new EndpointTile(p, DisplayName(p), KindOf(p), $"COPIA {i + 1}", KindLine(p), verdict,
                    $"{res.OkCount + res.SkipCount}", "fișiere confirmate", sec, 0, false, !online, true);
            }
            var after = free - incoming;
            return new EndpointTile(p, DisplayName(p), KindOf(p), $"COPIA {i + 1}", KindLine(p),
                online ? (after < 0 ? "online · ⚠ nu încape" : "online") : "offline",
                total > 0 ? Fmt(Math.Abs(after)) : "—", total > 0 ? (after >= 0 ? "liberi după copie" : "lipsă") : "spațiu necunoscut",
                total > 0 ? $"ocupat {Fmt(total - free)} din {Fmt(total)}" : "", total > 0 ? 100.0 * (total - free) / total : 0, total > 0, !online, true);
        }).ToList();
        Sync(_destinationTiles, dst);

        // --- Nod + incidente ---
        var model = VerificationCombo.SelectedItem is VerificationModel vm ? vm : VerificationModel.XxHash64;
        NodeMethod.Text = $"{model.Label()} · checksum per copie, sursa citită o singură dată";
        var list = new List<IncidentItem>();
        var warnBrush = (Brush)FindResource("StatusWarningBrush");
        var errBrush = (Brush)FindResource("StatusErrorBrush");
        var infoBrush = (Brush)FindResource("TextSecondaryBrush");
        var okBrush = (Brush)FindResource("StatusSuccessBrush");

        if (running)
        {
            StageTitle.Text = "Transfer în curs";
            StageSubtitle.Text = _runner.IsPaused ? "Pauză — apasă Continuă pentru a relua." : "Copiere · flush · verificare, pentru fiecare fișier și fiecare copie.";
            NodeTitle.Text = $"Copiere și verificare · {_runner.ProgressPercent}%";
            NodeRates.Text = _runner.SpeedText.Length > 0 ? $"scriere {_runner.SpeedText} (măsurat)" : "";
            RouteSpine.Fill = warnBrush;
            foreach (var c in _runner.Contexts.Where(c => c.FailCount > 0))
                list.Add(new IncidentItem("✕ CRITIC", errBrush, $"{DisplayName(c.DestRoot)}: {c.FailCount} fișier(e) neconfirmate",
                    "Scriere sau verificare eșuată la această destinație (vezi jurnalul tehnic).", "Acțiune: reîncercarea automată rulează la final, dacă e activă.", c.DestRoot));
            VerdictText.Text = list.Count == 0 ? "Fără incidente până acum" : $"{list.Count} incident(e)";
            PassedChecksText.Text = "Cifrele sunt măsurate; nu se afișează estimări neverificate.";
        }
        else if (hasResult)
        {
            var failed = _runner.LastResults.Count(r => r.FailCount > 0);
            var cancelled = _runner.LastResults.Any(r => r.Cancelled);
            StageTitle.Text = "Rezultat";
            VerdictText.Text = cancelled ? "Transfer anulat" : failed == _runner.LastResults.Count ? "✕ Transfer eșuat"
                : failed > 0 ? "✕ Eșec parțial — nu formata cardul" : _runner.LastResults.Any(r => r.RecoveredCount > 0) ? "✓ Verificat, cu avertismente" : "✓ Transfer verificat";
            StageSubtitle.Text = failed > 0 ? "Cel puțin o copie are fișiere neconfirmate." : "Fiecare fișier a trecut verificarea aleasă la fiecare copie.";
            NodeTitle.Text = VerdictText.Text;
            NodeRates.Text = "";
            RouteSpine.Fill = failed > 0 ? errBrush : okBrush;
            foreach (var r in _runner.LastResults.Where(r => r.FailCount > 0))
                list.Add(new IncidentItem("✕ CRITIC", errBrush, $"{DisplayName(r.DestRoot)}: {r.FailCount} fișier(e) neconfirmate",
                    "Aceste fișiere nu au o copie verificată la această destinație.", "Acțiune: nu formata cardul; deschide raportul CSV și reia transferul.", r.CsvPath ?? r.DestRoot));
            foreach (var r in _runner.LastResults.Where(r => r.FailCount == 0 && r.RecoveredCount > 0))
                list.Add(new IncidentItem("⚠ AVERTISMENT", warnBrush, $"{DisplayName(r.DestRoot)}: {r.RecoveredCount} recuperate la reîncercare",
                    "Au eșuat prima dată și au fost confirmate la reîncercare.", "Acțiune: verifică cablul, cititorul și discul.", ""));
            PassedChecksText.Text = $"✓ {_runner.LastResults.Sum(r => r.OkCount + r.SkipCount)} fișiere confirmate în {_runner.LastResults.Count} copii";
        }
        else
        {
            StageTitle.Text = "Pregătire offload";
            StageSubtitle.Text = "Sursa se citește o singură dată și se verifică pentru fiecare copie.";
            NodeTitle.Text = "Verificare în flux";
            NodeRates.Text = "";
            RouteSpine.Fill = (Brush)FindResource("StatusWarningBrush");
            var issues = Preflight.Check(_sources.ToList(), _destinations.ToList());
            foreach (var i in issues.Where(i => i.Code is not (PreflightCode.NoSources or PreflightCode.NoDestinations)))
            {
                var d = Preflight.Describe(i.Code);
                list.Add(new IncidentItem(i.Blocking ? "✕ CRITIC" : "⚠ AVERTISMENT", i.Blocking ? errBrush : warnBrush,
                    i.Path.Length > 0 ? $"{DisplayName(i.Path)}: {d.Title}" : d.Title, d.Cause, "Acțiune: " + d.Action, i.Path));
            }
            foreach (var s in _sources)
                if (_cardInfo.TryGetValue(s, out var ci) && ci != null)
                    foreach (var w in ci.Warnings)
                        list.Add(new IncidentItem("⚠ AVERTISMENT", warnBrush, $"{DisplayName(s)}: structura cardului", w,
                            "Acțiune: verifică în cameră înainte de a formata cardul.", ""));
            foreach (var t in dst.Where(t => t.StateLine.Contains("nu încape")))
                list.Add(new IncidentItem("⚠ AVERTISMENT", warnBrush, $"{t.Name}: spațiu insuficient", "Transferul nu încape pe acest disc.",
                    "Acțiune: eliberează spațiu sau alege alt disc; pornirea va cere confirmare.", t.Path));
            foreach (var p in _sources.Concat(_destinations).Where(p => _media.TryGetValue(p, out var m) && m.Confidence == Confidence.Fallback))
                list.Add(new IncidentItem("ⓘ INFORMAȚIE", infoBrush, $"{DisplayName(p)}: tip necunoscut",
                    "Windows nu raportează tipul mediului; e afișat ca dispozitiv extern. Transferul nu e afectat.", "", p));
            _blockingNow = Preflight.HasBlocking(issues.Where(i => i.Code is not (PreflightCode.NoSources or PreflightCode.NoDestinations)));
            var critical = list.Count(x => x.SeverityLabel.Contains("CRITIC"));
            var warnings = list.Count(x => x.SeverityLabel.Contains("AVERTISMENT"));
            VerdictText.Text = _sources.Count == 0 || _destinations.Count == 0 ? "Adaugă o sursă și cel puțin o copie"
                : critical > 0 ? $"✕ Blocat: {critical} incident(e) critic(e)" : warnings > 0 ? $"⚠ Gata, cu {warnings} avertisment(e)" : "✓ Gata de pornire";
            PassedChecksText.Text = _sources.Count > 0 && _destinations.Count > 0 && critical == 0
                ? "✓ Sursa și copiile nu se suprapun\n✓ Checksum per copie, sursa citită o singură dată" + (warnings > 0 ? "\nAvertismentele nu blochează pornirea." : "")
                : "";
        }
        var preparing = !running && !hasResult;
        AddSourceSlot.Visibility = preparing ? Visibility.Visible : Visibility.Collapsed;
        AddDestinationSlot.Visibility = preparing ? Visibility.Visible : Visibility.Collapsed;
        CorrelationText.Text = _runner.JobId.Length > 0 ? $"ID job {_runner.JobId} · sesiune {StructuredLog.Shared.SessionId}" : $"sesiune {StructuredLog.Shared.SessionId}";
        if (!_incidents.SequenceEqual(list)) { _incidents.Clear(); foreach (var x in list) _incidents.Add(x); }
    }

    private static string DisplayName(string p)
    {
#if DEBUG
        if (UiTest.DemoDisplay(p) is string demo) return demo;
#endif
        try
        {
            var full = Path.GetFullPath(p);
            if (IsDriveRoot(full)) { var di = new DriveInfo(full); return di.IsReady && di.VolumeLabel.Length > 0 ? $"{di.VolumeLabel} ({di.Name.TrimEnd('\\')})" : di.Name; }
            return Path.GetFileName(full.TrimEnd('\\'));
        }
        catch { return p; }
    }

    // --- Diagnostic (OBSERVABILITY_STANDARD) ---

    private void OnDiagnosticsClicked(object sender, RoutedEventArgs e)
    {
        var menu = new ContextMenu();
        void Add(string text, Action act) { var mi = new MenuItem { Header = text }; mi.Click += (_, _) => act(); menu.Items.Add(mi); }
        Add("Exportă diagnosticul (căi anonimizate)", () => ExportDiagnostic(false));
        Add("Exportă diagnosticul, cu căile fișierelor", () => ExportDiagnostic(true));
        Add("Deschide folderul de jurnale", () =>
        {
            Directory.CreateDirectory(StructuredLog.Shared.Settings.Directory);
            Process.Start(new ProcessStartInfo("explorer.exe", $"\"{StructuredLog.Shared.Settings.Directory}\"") { UseShellExecute = true });
        });
        Add($"Copiază ID-ul sesiunii ({StructuredLog.Shared.SessionId})", () => Clipboard.SetText(StructuredLog.Shared.SessionId));
        Add(StructuredLog.Shared.MinimumLevel <= LogLevel.Debug ? "Oprește jurnalul detaliat" : "Jurnal detaliat până la repornire",
            () => StructuredLog.Shared.SetDebugUntilRestart(StructuredLog.Shared.MinimumLevel > LogLevel.Debug));
        menu.PlacementTarget = (UIElement)sender;
        menu.IsOpen = true;
    }

    private void ExportDiagnostic(bool includePaths)
    {
        try
        {
            var settings = new Dictionary<string, string>
            {
                ["verification"] = (VerificationCombo.SelectedItem ?? "").ToString()!, ["generateMhl"] = AppSettings.GenerateMhl.ToString(),
                ["retryFailed"] = AppSettings.RetryFailedFiles.ToString(), ["ejectWhenDone"] = AppSettings.EjectWhenDone.ToString(),
                ["autoStartOnCard"] = AppSettings.AutoStartOnCard.ToString(), ["theme"] = ThemeSettings.Current.ToString(),
            };
            var last = _runner.LastResults.Count == 0 ? null : new Dictionary<string, string>
            {
                ["job"] = _runner.JobId, ["destinations"] = _runner.LastResults.Count.ToString(),
                ["ok"] = _runner.LastResults.Sum(r => r.OkCount).ToString(), ["failed"] = _runner.LastResults.Sum(r => r.FailCount).ToString(),
                ["verdict"] = _runner.LastVerdict,
            };
            var zip = new DiagnosticExporter(StructuredLog.Shared, settings, last).Export(DiagnosticExporter.DefaultFolder, includePaths);
            Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{zip}\"") { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            StructuredLog.Shared.Log(LogLevel.Error, "diagnostics", "diagnostics.exportFailed", "Export esuat", error: ex);
            System.Windows.MessageBox.Show(this, "Exportul diagnosticului a eșuat: " + ex.Message, "DataMover");
        }
    }
}

#if DEBUG
public partial class MainWindow
{
    /// Capturi deterministe: randare WPF la DPI-ul cerut (fara capturi de
    /// ecran ale desktopului), apoi iesire. Numai in DEBUG si cu --uitest.
    private void RunUiTest()
    {
        if (UiTest.Root == null) return;
        if (UiTest.Theme is AppTheme t) ThemeSettings.Apply(t, persist: false);
        Width = UiTest.W; Height = UiTest.H;
        Loaded += async (_, _) =>
        {
            foreach (var s in UiTest.Sources) _sources.Add(s);
            foreach (var d in UiTest.Dests) _destinations.Add(d);
            await Task.Delay(2500);
            if (UiTest.Capture is not string cap) return;
            Snap(this, cap + "-prepare.png");
            if (UiTest.Settings)
            {
                SettingsPopup.IsOpen = true; await Task.Delay(600);
                Snap((FrameworkElement)SettingsPopup.Child, cap + "-settings.png");
                SettingsPopup.IsOpen = false;
            }
            if (UiTest.Start)
            {
                FileStream? locked = UiTest.Lock is string lk ? new FileStream(lk, FileMode.Open, FileAccess.Read, FileShare.None) : null;
                // Latența UI (sondă la 100 ms) și ticurile animației, pentru raportul de performanță.
                var lag = new List<double>(); var probe = Stopwatch.StartNew(); var probing = true;
                _ = Task.Run(async () =>
                {
                    while (probing)
                    {
                        var t0 = probe.Elapsed.TotalMilliseconds;
                        await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.Input);
                        lock (lag) lag.Add(probe.Elapsed.TotalMilliseconds - t0);
                        await Task.Delay(100);
                    }
                });
                var ticks = 0; EventHandler count = (_, _) => ticks++; _flowTimer.Tick += count;
                StartButton.RaiseEvent(new RoutedEventArgs(System.Windows.Controls.Primitives.ButtonBase.ClickEvent));
                var sw = Stopwatch.StartNew(); var shot = false; var frames = 0; var paused = false;
                while (sw.Elapsed.TotalSeconds < 300 && (_runner.IsRunning || !_showingResult))
                {
                    await Task.Delay(frames < UiTest.Frames && shot ? 33 : 150);
                    if (!shot && _runner.IsRunning && _runner.ProgressPercent >= 15) { Snap(this, cap + "-transfer.png"); shot = true; }
                    if (shot && frames < UiTest.Frames && _runner.IsRunning && !_runner.IsPaused) Snap(this, $"{cap}-frame-{frames++:000}.png");
                    if (UiTest.Pause && !paused && shot && frames >= UiTest.Frames && _runner.IsRunning)
                    {
                        paused = true;
                        _runner.TogglePause(); await Task.Delay(700);
                        var o1 = _flowDestPaths.FirstOrDefault()?.StrokeDashOffset ?? double.NaN;
                        Snap(this, cap + "-paused.png"); await Task.Delay(1200);
                        var o2 = _flowDestPaths.FirstOrDefault()?.StrokeDashOffset ?? double.NaN;
                        File.WriteAllText(cap + "-pause.txt", $"timer activ in pauza={_flowTimer.IsEnabled} offset1={o1:0.###} offset2={o2:0.###} inghetat={o1 == o2}\n");
                        _runner.TogglePause(); await Task.Delay(900);
                        Snap(this, cap + "-resumed.png");
                        File.AppendAllText(cap + "-pause.txt", $"dupa reluare timer activ={_flowTimer.IsEnabled} offset={_flowDestPaths.FirstOrDefault()?.StrokeDashOffset:0.###}\n");
                    }
                }
                var secs = sw.Elapsed.TotalSeconds;
                probing = false; _flowTimer.Tick -= count; locked?.Dispose();
                await Task.Delay(800);
                Snap(this, cap + "-result.png");
                double[] l; lock (lag) l = lag.OrderBy(x => x).ToArray();
                File.WriteAllText(cap + "-perf.txt",
                    $"animatii={AnimationsAllowed} highContrast={HighContrast} durata_transfer_s={secs:0.00} ticuri={ticks} fps_mediu={(secs > 0 ? ticks / secs : 0):0.0} " +
                    $"timer_activ_dupa_rezultat={_flowTimer.IsEnabled} latenta_ui_ms_p50={(l.Length > 0 ? l[l.Length / 2] : 0):0.0} p95={(l.Length > 0 ? l[(int)(l.Length * 0.95)] : 0):0.0} max={(l.Length > 0 ? l[^1] : 0):0.0} " +
                    $"verdict={_runner.LastVerdict}\n");
            }
            Application.Current.Shutdown();
        };
    }

    private static void Snap(FrameworkElement el, string file)
    {
        el.UpdateLayout();
        var scale = UiTest.Dpi / 96.0;
        var bmp = new System.Windows.Media.Imaging.RenderTargetBitmap((int)(el.ActualWidth * scale), (int)(el.ActualHeight * scale), UiTest.Dpi, UiTest.Dpi, PixelFormats.Pbgra32);
        var bg = new DrawingVisual();
        using (var dc = bg.RenderOpen())
            dc.DrawRectangle((Brush)el.FindResource("WindowBackgroundBrush"), null, new Rect(0, 0, el.ActualWidth, el.ActualHeight));
        bmp.Render(bg); bmp.Render(el);
        var enc = new System.Windows.Media.Imaging.PngBitmapEncoder();
        enc.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(bmp));
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(file))!);
        using var fs = File.Create(file); enc.Save(fs);
    }
}

/// <summary>Mod de test UI (doar DEBUG): date sintetice, fara volume reale.
/// `--uitest &lt;folder&gt;` cu subfoldere prefixate (CF_, SD_, CARD_, SSD_, RAID_,
/// USB_, INT_, EXT_, DIR_); `--sources a,b` `--dests c,d` `--theme light|dark`
/// `--scale 1.5` (simulare DPI prin LayoutTransform) `--start`.</summary>
public static class UiTest
{
    public static string? Root { get; set; }
    public static AppTheme? Theme; public static double Dpi = 96; public static int W = 1240, H = 780;
    public static List<string> Sources = new(), Dests = new();
    public static bool Start, Settings, Pause; public static string? Capture, Lock; public static int Frames;

    public static void Parse(string[] args)
    {
        string? Val(string k) { var i = Array.IndexOf(args, k); return i >= 0 && i + 1 < args.Length ? args[i + 1] : null; }
        Root = Val("--uitest"); if (Root == null) return;
        Theme = Val("--theme") switch { "light" => AppTheme.Light, "dark" => AppTheme.Dark, _ => null };
        if (double.TryParse(Val("--dpi"), System.Globalization.CultureInfo.InvariantCulture, out var d)) Dpi = d;
        if (Val("--size") is string sz && sz.Split('x') is [var w, var h]) { W = int.Parse(w); H = int.Parse(h); }
        List<string> Paths(string? v) => (v ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries).Select(x => Path.Combine(Root!, x)).ToList();
        Sources = Paths(Val("--sources")); Dests = Paths(Val("--dests"));
        Start = args.Contains("--start"); Settings = args.Contains("--settings"); Capture = Val("--capture");
        Pause = args.Contains("--pause"); Frames = int.TryParse(Val("--frames"), out var fr) ? fr : 0;
        Lock = Val("--lock") is string lk ? Path.Combine(Root, lk) : null;
        if (Val("--anim") == "off") MainWindow.FlowAnimationsOverride = false;
        if (args.Contains("--hc")) MainWindow.FlowHighContrastOverride = true;
        // Izolare: jurnal separat, fara istoric/ejectare/notificari reale.
        StructuredLog.Shared = new StructuredLog(new StructuredLog.Config(Path.Combine(Root, "_log")));
        OffloadRunner.SideEffectsEnabled = false;
    }
    private static readonly (string Prefix, DeviceKind Kind)[] Table =
    {
        ("CF_", DeviceKind.CFexpress), ("SD_", DeviceKind.SdCard), ("CARD_", DeviceKind.MemoryCard), ("SSD_", DeviceKind.Ssd),
        ("RAID_", DeviceKind.Hdd), ("USB_", DeviceKind.UsbStick), ("INT_", DeviceKind.InternalVolume), ("EXT_", DeviceKind.ExternalDevice),
        ("DIR_", DeviceKind.Folder),
    };

    public static DeviceKind? DemoKind(string path)
    {
        if (Root == null || !path.StartsWith(Root, StringComparison.OrdinalIgnoreCase)) return null;
        var name = Path.GetFileName(path.TrimEnd('\\'));
        foreach (var (p, k) in Table) if (name.StartsWith(p, StringComparison.OrdinalIgnoreCase)) return k;
        return null;
    }

    public static string? DemoConnection(DeviceKind k) => k switch
    {
        DeviceKind.Ssd => "Thunderbolt / PCIe", DeviceKind.SdCard => "cititor SD", DeviceKind.InternalVolume => "intern",
        DeviceKind.Folder => null, _ => "USB",
    };

    public static string? DemoDisplay(string path)
    {
        if (DemoKind(path) == null) return null;
        var name = Path.GetFileName(path.TrimEnd('\\'));
        var i = name.IndexOf('_');
        return i >= 0 ? name[(i + 1)..] : name;
    }
}
#endif
