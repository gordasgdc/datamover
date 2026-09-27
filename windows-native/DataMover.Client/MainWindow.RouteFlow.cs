using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace DataMover.Client;

/// Traseul animat sursă → verificare → copii (echivalentul WPF al RouteView.swift).
/// Strict prezentare: citește starea runner-ului, nu o modifică. Timerul (max. 30 FPS) rulează
/// DOAR în transfer activ, cu animațiile Windows permise și fereastra vizibilă; altfel e oprit.
public partial class MainWindow
{
    private readonly DispatcherTimer _flowTimer = new(DispatcherPriority.Render) { Interval = RouteFlow.FrameInterval };
    private readonly Stopwatch _flowClock = new();
    private readonly List<Path> _flowDestPaths = new();
    private RouteStage _flowStage = RouteStage.Prepare;
    private string _flowSignature = "";
    private bool _flowLayoutQueued;
    /// Doar pentru teste UI: forțează animațiile oprite / High Contrast.
    internal static bool? FlowAnimationsOverride { get; set; }
    internal static bool? FlowHighContrastOverride { get; set; }

    private static bool HighContrast => FlowHighContrastOverride ?? SystemParameters.HighContrast;
    /// „Afișează animații în Windows” (SPI_GETCLIENTAREAANIMATION) și fără High Contrast.
    private static bool AnimationsAllowed => (FlowAnimationsOverride ?? SystemParameters.ClientAreaAnimation) && !HighContrast;
    private bool WindowShown => IsVisible && WindowState != WindowState.Minimized;

    private void InitRouteFlow()
    {
        _flowTimer.Tick += OnFlowTick;
        StateChanged += OnFlowWindowStateChanged;
        IsVisibleChanged += OnFlowVisibilityChanged;
        SystemParameters.StaticPropertyChanged += OnFlowSystemParametersChanged;
        RouteGrid.SizeChanged += OnFlowLayoutChanged;
        Closed += (_, _) => DisposeRouteFlow();
    }

    /// Dezabonare completă: timerul, evenimentele statice (altfel fereastra ar rămâne referită).
    private void DisposeRouteFlow()
    {
        _flowTimer.Stop();
        _flowTimer.Tick -= OnFlowTick;
        StateChanged -= OnFlowWindowStateChanged;
        IsVisibleChanged -= OnFlowVisibilityChanged;
        SystemParameters.StaticPropertyChanged -= OnFlowSystemParametersChanged;
        RouteGrid.SizeChanged -= OnFlowLayoutChanged;
        _flowClock.Stop();
    }

    private void OnFlowWindowStateChanged(object? s, EventArgs e) => UpdateFlowTimer();
    private void OnFlowVisibilityChanged(object s, DependencyPropertyChangedEventArgs e) => UpdateFlowTimer();
    private void OnFlowLayoutChanged(object s, SizeChangedEventArgs e) { _flowSignature = ""; QueueFlowLayout(); }
    private void OnFlowSystemParametersChanged(object? s, System.ComponentModel.PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(SystemParameters.HighContrast) or nameof(SystemParameters.ClientAreaAnimation))
        {
            _flowSignature = "";
            Dispatcher.BeginInvoke(QueueFlowLayout);
        }
    }

    /// Apelat la finalul RefreshRoute: actualizează etapa și reface curbele doar dacă s-a schimbat ceva.
    private void UpdateRouteFlow(RouteStage stage)
    {
        _flowStage = stage;
        QueueFlowLayout();
        UpdateFlowTimer();
    }

    private void QueueFlowLayout()
    {
        if (_flowLayoutQueued) return;
        _flowLayoutQueued = true;
        // După ce plăcile și-au calculat poziția (DispatcherPriority.Loaded rulează după layout).
        Dispatcher.BeginInvoke(DispatcherPriority.Loaded, () => { _flowLayoutQueued = false; BuildFlowPaths(); });
    }

    private void UpdateFlowTimer()
    {
        var animate = RouteFlow.ShouldAnimate(_flowStage, AnimationsAllowed, WindowShown);
        if (animate)
        {
            if (!_flowTimer.IsEnabled) { _flowClock.Start(); _flowTimer.Start(); }
        }
        else if (_flowTimer.IsEnabled || _flowClock.IsRunning)
        {
            _flowTimer.Stop();
            _flowClock.Stop();                    // Pauză: offsetul rămâne înghețat unde era
            if (_flowStage is RouteStage.Prepare or RouteStage.Result) _flowClock.Reset();
        }
    }

    private void OnFlowTick(object? s, EventArgs e)
    {
        var offset = RouteFlow.DashOffset(_flowClock.Elapsed.TotalSeconds);
        foreach (var p in _flowDestPaths) p.StrokeDashOffset = offset;
    }

    private Brush ToneBrush(FlowTone tone)
    {
        if (HighContrast)
            return tone switch
            {
                FlowTone.Active or FlowTone.Success => SystemColors.HighlightBrush,
                FlowTone.Offline => SystemColors.GrayTextBrush,
                _ => SystemColors.WindowTextBrush,
            };
        string key = tone switch
        {
            FlowTone.Success => "StatusSuccessBrush", FlowTone.Warning => "StatusWarningBrush", FlowTone.Error => "StatusErrorBrush",
            FlowTone.Offline => "TextDisabledBrush", FlowTone.Active => "SystemAccentColorPrimaryBrush", _ => "TextSecondaryBrush",
        };
        return TryFindResource(key) as Brush ?? TryFindResource("StatusWarningBrush") as Brush ?? Brushes.Gray;
    }

    private FlowTone ToneFor(string destPath)
    {
        var online = System.IO.Directory.Exists(destPath);
        var ctx = _runner.Contexts.FirstOrDefault(c => string.Equals(c.DestRoot, destPath, StringComparison.OrdinalIgnoreCase));
        var res = _runner.LastResults.FirstOrDefault(r => string.Equals(r.DestRoot, destPath, StringComparison.OrdinalIgnoreCase));
        return _flowStage == RouteStage.Result
            ? RouteFlow.DestinationTone(_flowStage, online, res?.FailCount ?? 0, res?.RecoveredCount ?? 0, res?.Cancelled ?? false, res != null)
            : RouteFlow.DestinationTone(_flowStage, online, ctx?.FailCount ?? 0, 0, false, false);
    }

    /// Ancora unei plăci (container din ItemsControl), în coordonatele RouteGrid.
    private Rect? TileRect(ItemsControl list, int index)
    {
        if (list.ItemContainerGenerator.ContainerFromIndex(index) is not FrameworkElement c || !c.IsVisible || c.ActualHeight <= 0) return null;
        var p = c.TransformToAncestor(RouteGrid).Transform(new Point(0, 0));
        return new Rect(p.X, p.Y, c.ActualWidth, Math.Max(0, c.ActualHeight - 10)); // 10 = marginea de jos a plăcii
    }

    private void BuildFlowPaths()
    {
        if (!IsLoaded || !VerifyNode.IsVisible) return;
        var node = new Rect(VerifyNode.TransformToAncestor(RouteGrid).Transform(new Point(0, 0)), VerifyNode.RenderSize);
        var dashed = RouteFlow.IsDashed(_flowStage, AnimationsAllowed);
        var sources = Enumerable.Range(0, _sources.Count).Select(i => TileRect(SourceTiles, i)).ToList();
        var dests = Enumerable.Range(0, _destinations.Count).Select(i => (Rect: TileRect(DestinationTiles, i), Tone: ToneFor(_destinations[i]))).ToList();

        var sig = $"{_flowStage}|{dashed}|{HighContrast}|{node}|" + string.Join(";", sources) + "|" + string.Join(";", dests.Select(d => $"{d.Rect}:{d.Tone}"));
        if (sig == _flowSignature) return;
        _flowSignature = sig;

        var offset = RouteFlow.DashOffset(_flowClock.Elapsed.TotalSeconds);
        RouteFlowLayer.Children.Clear();
        _flowDestPaths.Clear();
        var thickness = HighContrast ? 2.0 : 3.0;
        foreach (var r in sources.OfType<Rect>())
        {
            var sy = r.Top + r.Height / 2;
            RouteFlowLayer.Children.Add(Curve(r.Right + 4, sy, node.Left - 4, RouteFlow.NodeAnchorY(sy, node.Top, node.Bottom), ToneBrush(FlowTone.Neutral), thickness, false, 0));
        }
        foreach (var d in dests)
        {
            if (d.Rect is not Rect r) continue;
            var ey = r.Top + r.Height / 2;
            var path = Curve(node.Right + 4, RouteFlow.NodeAnchorY(ey, node.Top, node.Bottom), r.Left - 4, ey, ToneBrush(d.Tone), thickness, dashed, offset);
            RouteFlowLayer.Children.Add(path);
            if (dashed) _flowDestPaths.Add(path);
        }
    }

    private static Path Curve(double sx, double sy, double ex, double ey, Brush brush, double thickness, bool dashed, double offset)
    {
        var (c1x, c1y, c2x, c2y) = RouteFlow.Controls(sx, sy, ex, ey);
        var fig = new PathFigure { StartPoint = new Point(sx, sy), IsFilled = false };
        fig.Segments.Add(new BezierSegment(new Point(c1x, c1y), new Point(c2x, c2y), new Point(ex, ey), true));
        var geo = new PathGeometry(new[] { fig });
        geo.Freeze();
        var p = new Path
        {
            Data = geo, Stroke = brush, StrokeThickness = thickness,
            StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round, StrokeDashCap = PenLineCap.Round,
            SnapsToDevicePixels = true, IsHitTestVisible = false,
        };
        if (dashed) { p.StrokeDashArray = new DoubleCollection { RouteFlow.DashOn, RouteFlow.DashOff }; p.StrokeDashOffset = offset; }
        return p;
    }
}
