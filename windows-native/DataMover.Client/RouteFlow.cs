namespace DataMover.Client;

/// Etapa traseului, derivată din starea runner-ului (doar prezentare).
public enum RouteStage { Prepare, Running, Paused, Result }

/// Tonul unui traseu sursă/verificare → copie, din starea reală a destinației.
public enum FlowTone { Neutral, Active, Success, Warning, Error, Offline }

/// Logica pură a animației traseului (fără WPF): testată în CoreChecks.
/// Echivalentul Windows al `RouteView.connectors` de pe macOS: fluxul punctat se mișcă
/// doar cât transferul rulează; la Pauză rămâne înghețat; în Pregătire și Rezultat liniile sunt
/// continue. Nimic de aici nu citește sau influențează motorul de copiere.
public static class RouteFlow
{
    public const double MaxFps = 30;
    /// Linie punctată în unități de grosime (WPF StrokeDashArray). Capetele rotunde adaugă o grosime
    /// fiecărui segment: 1 plin + 2,5 gol se vede ca puncte scurte, dese — spațiile dintre plăci
    /// sunt înguste pe Windows, iar un model lung ar lăsa o singură liniuță vizibilă.
    public const double DashOn = 1, DashOff = 2.5, Period = DashOn + DashOff;
    /// Viteza fluxului, în unități de grosime pe secundă (≈ 24 px/s la grosimea 3, ca pe macOS).
    public const double UnitsPerSecond = 8;

    public static TimeSpan FrameInterval => TimeSpan.FromSeconds(1 / MaxFps);

    public static RouteStage StageOf(bool running, bool paused, bool hasResult) =>
        running ? (paused ? RouteStage.Paused : RouteStage.Running) : hasResult ? RouteStage.Result : RouteStage.Prepare;

    /// Timer activ doar dacă se vede ceva care se mișcă: transfer în curs, animații permise
    /// (Windows „Afișează animații”, fără High Contrast) și fereastră vizibilă, neminimizată.
    public static bool ShouldAnimate(RouteStage stage, bool animationsAllowed, bool windowVisible) =>
        stage == RouteStage.Running && animationsAllowed && windowVisible;

    /// Punctat în transfer (inclusiv pauză, înghețat); continuu în Pregătire și Rezultat.
    public static bool IsDashed(RouteStage stage, bool animationsAllowed) =>
        animationsAllowed && stage is RouteStage.Running or RouteStage.Paused;

    /// Offsetul liniei punctate după `elapsedSeconds` de mișcare efectivă (fără pauze).
    /// Negativ = punctele avansează dinspre sursă spre copie. Periodic, în (-Period, 0].
    public static double DashOffset(double elapsedSeconds)
    {
        if (elapsedSeconds <= 0 || double.IsNaN(elapsedSeconds)) return 0;
        var o = (elapsedSeconds * UnitsPerSecond) % Period;
        return o == 0 ? 0 : -o;
    }

    public static FlowTone DestinationTone(RouteStage stage, bool online, int failCount, int recoveredCount, bool cancelled, bool hasResultForDest)
    {
        if (stage == RouteStage.Result && hasResultForDest)
            return cancelled ? FlowTone.Neutral : failCount > 0 ? FlowTone.Error : recoveredCount > 0 ? FlowTone.Warning : FlowTone.Success;
        if (!online) return FlowTone.Offline;
        if (stage is RouteStage.Running or RouteStage.Paused) return failCount > 0 ? FlowTone.Error : FlowTone.Active;
        return FlowTone.Neutral;
    }

    /// Curba Bézier orizontală dintre două ancore (ca pe macOS): punctele de control la jumătatea distanței.
    public static (double C1x, double C1y, double C2x, double C2y) Controls(double sx, double sy, double ex, double ey)
    {
        var dx = (ex - sx) * 0.5;
        return (sx + dx, sy, ex - dx, ey);
    }

    /// Unde atinge traseul nodul de verificare: la înălțimea capătului celălalt, limitată la marginile
    /// nodului (cu `inset`). Traseele formează un evantai din latura nodului, fără curbe verticale abrupte.
    public static double NodeAnchorY(double otherY, double nodeTop, double nodeBottom, double inset = 14)
    {
        var lo = nodeTop + inset; var hi = nodeBottom - inset;
        if (hi < lo) return (nodeTop + nodeBottom) / 2;
        return Math.Clamp(otherY, lo, hi);
    }
}
