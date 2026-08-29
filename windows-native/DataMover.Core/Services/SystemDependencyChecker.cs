using System.Runtime.Versioning;

namespace DataMover.Core.Services;

/// Manager Modular de Dependinte (Regula 4, CLAUDE.md) - port al modelului
/// din GDCPluginManagerWin/SystemDependencyChecker.cs. DataMover e
/// self-contained (`dotnet publish -r win-x64 --self-contained` - .NET 8
/// e bundle-uit, nu depinde de un runtime instalat separat), dar
/// QuestPDF (raportul PDF, PdfReport.cs) foloseste SkiaSharp - binare
/// native care leaga la Visual C++ Redistributable, ACELASI risc real
/// deja documentat pentru GDCPluginManagerWin. Panoul ramane pregatit
/// modular chiar daca azi orice masina Windows 10/11 normala il arata
/// verde - scopul e sa nu fie nevoie de o sesiune de debugging cand
/// cineva ruleaza pe o instalare minimala/Server Core fara el.
public sealed record DependencyItem(
    string Id, string Name, bool IsPresent, string? DownloadUrl,
    bool IsOptional, string Detail);

[SupportedOSPlatform("windows")]
public static class SystemDependencyChecker
{
    public static IReadOnlyList<DependencyItem> CheckAll() =>
    [
        CheckVCRedist(),
    ];

    public static bool AllRequiredPresent(IReadOnlyList<DependencyItem> items) =>
        items.Where(i => !i.IsOptional).All(i => i.IsPresent);

    /// SkiaSharp (folosit de QuestPDF pentru raportul PDF al fiecarui
    /// transfer, vezi PdfReport.cs) are nevoie de Visual C++ Redistributable
    /// - nu vine implicit pe orice instalare Windows (ex. Server Core,
    /// instalari minimale). Fara el, generarea PDF-ului esueaza tacut
    /// (transferul continua, doar raportul PDF lipseste - CSV-ul ramane
    /// intotdeauna generat, vezi DestinationJob.Run()).
    private static DependencyItem CheckVCRedist()
    {
        var systemDir = Environment.GetFolderPath(Environment.SpecialFolder.System);
        var present = File.Exists(Path.Combine(systemDir, "vcruntime140.dll"));
        return new DependencyItem("vc-redist", "Visual C++ Redistributable", present,
            "https://aka.ms/vs/17/release/vc_redist.x64.exe",
            IsOptional: false,
            Detail: present
                ? "Detectat - raportul PDF al transferurilor poate fi generat."
                : "Lipseste - raportul PDF (QuestPDF/SkiaSharp) va esua silentios; CSV-ul tot se genereaza normal.");
    }
}
