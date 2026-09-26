using System.Globalization;
using System.Windows;
using System.Windows.Media;
using DataMover.Core.Domain;
using Wpf.Ui.Appearance;

namespace DataMover.Client.Controls;

/// <summary>
/// Familia de dispozitive DataMover pe Windows — vectori ORIGINALI desenati in
/// cod (OnRender), aceleasi siluete ca pe macOS (DeviceArt.swift), fara imagini
/// externe. Independente de DPI: WPF randeaza vectorii la scara monitorului.
/// Starea (rol, online, activitate, avertisment) NU se deseneaza aici — e afisata
/// separat, ca insigne text + simbol.
/// </summary>
public sealed class DeviceArtView : FrameworkElement
{
    public static readonly DependencyProperty KindProperty = DependencyProperty.Register(
        nameof(Kind), typeof(DeviceKind), typeof(DeviceArtView),
        new FrameworkPropertyMetadata(DeviceKind.ExternalDevice, FrameworkPropertyMetadataOptions.AffectsRender));
    public static readonly DependencyProperty DimmedProperty = DependencyProperty.Register(
        nameof(Dimmed), typeof(bool), typeof(DeviceArtView),
        new FrameworkPropertyMetadata(false, FrameworkPropertyMetadataOptions.AffectsRender));

    public DeviceKind Kind { get => (DeviceKind)GetValue(KindProperty); set => SetValue(KindProperty, value); }
    public bool Dimmed { get => (bool)GetValue(DimmedProperty); set => SetValue(DimmedProperty, value); }

    public DeviceArtView()
    {
        ApplicationThemeManager.Changed += (_, _) => InvalidateVisual();
    }

    private static bool IsDark => ApplicationThemeManager.GetAppTheme() == ApplicationTheme.Dark;

    private static Brush V(Color a, Color b, Color c) =>
        new LinearGradientBrush(new GradientStopCollection { new(a, 0), new(b, 0.55), new(c, 1) }, 90);
    private static Color G(byte v) => Color.FromRgb(v, v, v);
    private static readonly Brush Gold = new LinearGradientBrush(Color.FromRgb(245, 214, 128), Color.FromRgb(178, 138, 56), 90);
    private static readonly Brush Led = new SolidColorBrush(Color.FromRgb(92, 219, 245));
    private static readonly Pen Edge = new(new SolidColorBrush(Color.FromArgb(56, 255, 255, 255)), 1);
    private static readonly Pen Spec = new(new SolidColorBrush(Color.FromArgb(120, 255, 255, 255)), 1);

    protected override Size MeasureOverride(Size s) =>
        new(double.IsInfinity(s.Width) ? 120 : s.Width, double.IsInfinity(s.Height) ? 94 : s.Height);

    protected override void OnRender(DrawingContext dc)
    {
        double w = ActualWidth, h = ActualHeight;
        if (w <= 0 || h <= 0) return;
        // Scena 120 x 94, centrata si scalata uniform.
        double scale = Math.Min(w / 120, h / 94);
        dc.PushTransform(new TranslateTransform((w - 120 * scale) / 2, (h - 94 * scale) / 2));
        dc.PushTransform(new ScaleTransform(scale, scale));
        if (Dimmed) dc.PushOpacity(0.45);
        Shadow(dc);
        switch (Kind)
        {
            case DeviceKind.CFexpress: Card(dc, true); break;
            case DeviceKind.MemoryCard: Card(dc, false); break;
            case DeviceKind.SdCard: Sd(dc); break;
            case DeviceKind.Ssd: Ssd(dc); break;
            case DeviceKind.Hdd: Enclosure(dc); break;
            case DeviceKind.UsbStick: Usb(dc); break;
            case DeviceKind.InternalVolume: Laptop(dc); break;
            case DeviceKind.Folder: Folder(dc); break;
            default: Unknown(dc); break;
        }
        if (Dimmed) dc.Pop();
        dc.Pop(); dc.Pop();
    }

    private void Shadow(DrawingContext dc)
    {
        if (Kind == DeviceKind.Folder) return;
        var brush = new RadialGradientBrush(Color.FromArgb((byte)(IsDark ? 150 : 70), 0, 0, 0), Colors.Transparent);
        dc.DrawEllipse(brush, null, new Point(60, 84), 44, 5);
    }

    private static void Rotated(DrawingContext dc, double deg, Point c, Action draw)
    {
        dc.PushTransform(new RotateTransform(deg, c.X, c.Y)); draw(); dc.Pop();
    }

    private void Card(DrawingContext dc, bool cfexpress) => Rotated(dc, -7, new Point(60, 45), () =>
    {
        var body = new Rect(31, 8, 58, 70);
        dc.DrawRoundedRectangle(V(G(78), G(36), G(15)), Edge, body, 3, 3);
        dc.DrawLine(Spec, new Point(35, 9.5), new Point(85, 9.5));
        if (cfexpress)
        {
            var band = new Rect(31, 20, 58, 17);
            dc.DrawRectangle(new LinearGradientBrush(Color.FromRgb(184, 38, 33), Color.FromRgb(112, 18, 18), 0), null, band);
            Text(dc, "CFexpress", 7, FontWeights.Heavy, Brushes.White, new Point(60, 28.5));
            Text(dc, "B", 9, FontWeights.Bold, Brushes.WhiteSmoke, new Point(60, 52));
        }
        else
        {
            dc.DrawRoundedRectangle(new SolidColorBrush(G(76)), null, new Rect(38, 20, 44, 32), 2, 2);
            for (int i = 0; i < 3; i++) dc.DrawRectangle(new SolidColorBrush(Color.FromArgb(90, 255, 255, 255)), null, new Rect(43, 26 + i * 8, 30 - i * 7, 2));
        }
        for (int i = 0; i < 9; i++) dc.DrawRectangle(Gold, null, new Rect(35 + i * 5.6, 69, 2.9, 4.5));
    });

    private void Sd(DrawingContext dc) => Rotated(dc, 8, new Point(60, 45), () =>
    {
        var g = new StreamGeometry();
        using (var c = g.Open())
        {
            c.BeginFigure(new Point(41, 6), true, true);
            c.LineTo(new Point(70, 6), true, false); c.LineTo(new Point(79, 15), true, false);
            c.LineTo(new Point(79, 78), true, false); c.LineTo(new Point(41, 78), true, false);
        }
        dc.DrawGeometry(V(G((byte)(IsDark ? 102 : 112)), G(58), G(30)), Edge, g);
        dc.DrawRoundedRectangle(new LinearGradientBrush(Color.FromRgb(44, 79, 135), Color.FromRgb(20, 36, 72), 45), null, new Rect(45, 26, 30, 42), 2, 2);
        Text(dc, "SD", 12, FontWeights.Black, Brushes.White, new Point(60, 47));
        for (int i = 0; i < 5; i++) dc.DrawRectangle(Gold, null, new Rect(45 + i * 4.6, 9, 2.8, 10));
        dc.DrawRoundedRectangle(new SolidColorBrush(G(220)), null, new Rect(38, 20, 4, 10), 1, 1);
    });

    private void Ssd(DrawingContext dc)
    {
        var top = new StreamGeometry();
        using (var c = top.Open())
        {
            c.BeginFigure(new Point(20, 25), true, true);
            c.LineTo(new Point(111, 25), true, false); c.LineTo(new Point(108, 49), true, false); c.LineTo(new Point(12, 49), true, false);
        }
        dc.DrawGeometry(new LinearGradientBrush(G((byte)(IsDark ? 230 : 247)), G((byte)(IsDark ? 178 : 209)), 90), new Pen(new SolidColorBrush(Color.FromArgb(180, 255, 255, 255)), 0.8), top);
        var front = new Rect(12, 49, 96, 19);
        dc.DrawRoundedRectangle(V(G(190), G(142), G(76)), null, front, 3, 3);
        for (int i = 0; i < 4; i++) dc.DrawRectangle(new SolidColorBrush(Color.FromArgb(64, 0, 0, 0)), null, new Rect(26, 53 + i * 3.3, 60, 1.1));
        dc.DrawEllipse(new SolidColorBrush(Color.FromArgb(120, 92, 219, 245)), null, new Point(18, 58.5), 4, 4);
        dc.DrawEllipse(Led, null, new Point(18, 58.5), 2.2, 2.2);
        dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(220, 0, 0, 0)), null, new Rect(94, 56, 8, 5), 2.5, 2.5);
    }

    private void Enclosure(DrawingContext dc)
    {
        var front = new Rect(29, 10, 50, 71);
        var side = new StreamGeometry();
        using (var c = side.Open())
        {
            c.BeginFigure(new Point(79, 10), true, true);
            c.LineTo(new Point(93, 4), true, false); c.LineTo(new Point(93, 75), true, false); c.LineTo(new Point(79, 81), true, false);
        }
        var top = new StreamGeometry();
        using (var c = top.Open())
        {
            c.BeginFigure(new Point(29, 10), true, true);
            c.LineTo(new Point(43, 4), true, false); c.LineTo(new Point(93, 4), true, false); c.LineTo(new Point(79, 10), true, false);
        }
        dc.DrawGeometry(new LinearGradientBrush(G(36), G(14), 0), null, side);
        dc.DrawGeometry(new SolidColorBrush(G((byte)(IsDark ? 66 : 77))), null, top);
        dc.DrawRoundedRectangle(V(G(61), G(33), G(18)), Edge, front, 2, 2);
        for (int bay = 0; bay < 2; bay++)
        {
            var r = new Rect(34, 17 + bay * 28.5, 40, 24);
            dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(140, 0, 0, 0)), new Pen(new SolidColorBrush(Color.FromArgb(26, 255, 255, 255)), 1), r, 1.5, 1.5);
            for (int i = 0; i < 5; i++) dc.DrawRectangle(new SolidColorBrush(G(76)), null, new Rect(39, r.Y + 4 + i * 3.4, 25, 1.4));
            dc.DrawEllipse(bay == 0 ? Led : new SolidColorBrush(G(115)), null, new Point(69, r.Y + 12), 1.8, 1.8);
        }
    }

    private void Usb(DrawingContext dc) => Rotated(dc, -16, new Point(60, 45), () =>
    {
        dc.DrawRectangle(V(G(235), G(200), G(142)), null, new Rect(76, 39.5, 23, 14));
        dc.DrawRectangle(new SolidColorBrush(Color.FromArgb(180, 0, 0, 0)), null, new Rect(83, 43, 4, 3.5));
        dc.DrawRectangle(new SolidColorBrush(Color.FromArgb(180, 0, 0, 0)), null, new Rect(91, 43, 4, 3.5));
        dc.DrawRoundedRectangle(V(G(78), G(36), G(15)), Edge, new Rect(19, 36, 58, 20), 9, 9);
        dc.DrawEllipse(null, new Pen(new SolidColorBrush(G(153)), 1.5), new Point(29, 46), 3.5, 3.5);
        dc.DrawLine(Spec, new Point(36, 37.5), new Point(71, 37.5));
    });

    private void Laptop(DrawingContext dc)
    {
        var screen = new Rect(23, 9, 74, 51);
        dc.DrawRoundedRectangle(V(G((byte)(IsDark ? 230 : 247)), G(200), G(140)), null, screen, 5, 5);
        dc.DrawRoundedRectangle(new LinearGradientBrush(G(56), G(13), 45), null, new Rect(25.5, 11.5, 69, 46), 2.5, 2.5);
        var baseG = new StreamGeometry();
        using (var c = baseG.Open())
        {
            c.BeginFigure(new Point(12, 61), true, true);
            c.LineTo(new Point(108, 61), true, false); c.LineTo(new Point(103, 68), true, false); c.LineTo(new Point(17, 68), true, false);
        }
        dc.DrawGeometry(new LinearGradientBrush(G(240), G(150), 90), null, baseG);
    }

    private void Folder(DrawingContext dc)
    {
        var ink = new Pen(new SolidColorBrush(IsDark ? G(204) : G(72)), 1.6);
        var g = new StreamGeometry();
        using (var c = g.Open())
        {
            c.BeginFigure(new Point(27, 27), false, false);
            c.LineTo(new Point(27, 18), true, false); c.LineTo(new Point(49, 18), true, false); c.LineTo(new Point(55, 23), true, false);
        }
        dc.DrawGeometry(null, ink, g);
        dc.DrawRoundedRectangle(null, ink, new Rect(27, 23, 67, 49), 3, 3);
        dc.DrawLine(new Pen(ink.Brush, 1) { DashStyle = new DashStyle(new double[] { 3, 3 }, 0) }, new Point(35, 38), new Point(86, 38));
    }

    private void Unknown(DrawingContext dc)
    {
        var body = new Rect(26, 24, 58, 47);
        dc.DrawRoundedRectangle(V(G(IsDark ? (byte)102 : (byte)112), G(58), G(30)), Edge, body, 5, 5);
        dc.DrawRoundedRectangle(null, new Pen(new SolidColorBrush(Color.FromArgb(36, 255, 255, 255)), 1) { DashStyle = new DashStyle(new double[] { 4, 3 }, 0) },
            new Rect(32, 30, 46, 35), 2, 2);
        var cable = new StreamGeometry();
        using (var c = cable.Open())
        {
            c.BeginFigure(new Point(84, 56), false, false);
            c.BezierTo(new Point(95, 56), new Point(96, 38), new Point(107, 38), true, false);
        }
        dc.DrawGeometry(null, new Pen(new SolidColorBrush(IsDark ? G(140) : G(90)), 2.2) { StartLineCap = PenLineCap.Round }, cable);
        dc.DrawRoundedRectangle(new SolidColorBrush(G(200)), null, new Rect(104, 35, 8, 6), 1.5, 1.5);
    }

    private static void Text(DrawingContext dc, string s, double size, FontWeight weight, Brush brush, Point center)
    {
        var ft = new FormattedText(s, CultureInfo.InvariantCulture, FlowDirection.LeftToRight,
            new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, weight, FontStretches.Normal), size, brush, 1.25);
        dc.DrawText(ft, new Point(center.X - ft.Width / 2, center.Y - ft.Height / 2));
    }
}
