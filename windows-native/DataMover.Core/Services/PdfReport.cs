using DataMover.Core.Models;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace DataMover.Core.Services;

/// <summary>
/// Raport PDF per destinatie - port C# al pdf_report.py (Mac/Python
/// foloseau deja reportlab; QuestPDF e echivalentul .NET, licenta
/// Community, gratuita pentru acest proiect). Lipsea complet in clientul
/// WPF nou - semnalat de Cristi dupa primul test real pe Windows
/// (2026-08-28): "nu-mi creeaza acel fisier PDF". `rows` e ESANTIONUL
/// plafonat (DestinationJob._sampleRows, PdfSampleLimit) - lista completa
/// ramane in CSV (Regula 21), PDF-ul nu tine in RAM fiecare fisier al
/// unui transfer urias.
/// </summary>
public static class PdfReport
{
    private static readonly Dictionary<string, string> StatusColors = new()
    {
        ["OK"] = "#1a7a34",
        ["SARIT"] = "#7a6a1a",
        ["NEPOTRIVIRE"] = "#b8860b",
        ["EROARE"] = "#b02a2a",
    };

    public static string Generate(
        string targetRoot, string destination, string folderName,
        IReadOnlyList<ReportRow> rows, DateTime startedAt, DateTime finishedAt,
        int okCount, int skipCount, int failCount, bool cancelled,
        string verificationLabel, string? truncatedNote,
        ProductionMeta? meta = null, int recoveredCount = 0, string? mhlPath = null)
    {
        meta ??= new ProductionMeta();
        QuestPDF.Settings.License = LicenseType.Community;

        var timestamp = finishedAt.ToString("yyyy-MM-dd_HH-mm-ss");
        var path = Path.Combine(targetRoot, $"offload_report_{timestamp}.pdf");
        var total = okCount + skipCount + failCount;
        var statusText = cancelled ? "ANULAT DE UTILIZATOR" : "FINALIZAT";
        var duration = $"{(finishedAt - startedAt).TotalSeconds:0.0} secunde";

        Document.Create(container =>
        {
            container.Page(page =>
            {
                page.Size(PageSizes.A4);
                page.Margin(18, Unit.Millimetre);
                page.DefaultTextStyle(x => x.FontSize(9));

                page.Header().Row(headerRow =>
                {
                    headerRow.RelativeItem().Column(col =>
                    {
                        col.Item().Text("Raport offload – DataMover").FontSize(18).Bold();
                        col.Item().PaddingTop(4).Text($"Destinatie: {destination}");
                        col.Item().Text($"Folder creat: {folderName}");
                        // [2026-09-03] Campurile de productie completate de
                        // user (Client, Camera, Operator…) - cele goale nu
                        // se deseneaza deloc, vezi ProductionMeta.HeaderFields.
                        var brandingFields = meta.HeaderFields();
                        if (brandingFields.Count > 0)
                            col.Item().Text(string.Join("   |   ", brandingFields.Select(f => $"{f.Label}: {f.Value}")));
                        col.Item().Text($"Model de verificare: {verificationLabel}");
                        col.Item().Text($"Inceput: {startedAt:yyyy-MM-dd HH:mm:ss}");
                        col.Item().Text($"Finalizat: {finishedAt:yyyy-MM-dd HH:mm:ss}");
                        col.Item().Text($"Durata: {duration}");
                        col.Item().Text($"Status sesiune: {statusText}");
                        if (!string.IsNullOrEmpty(mhlPath))
                            col.Item().Text($"MHL: {Path.GetFileName(mhlPath)}");
                        var summary = $"Total fisiere: {total}   OK: {okCount}   Sarite: {skipCount}   Probleme: {failCount}";
                        if (recoveredCount > 0) summary += $"   Recuperate la reincercare: {recoveredCount}";
                        col.Item().PaddingTop(6).Text(summary).Bold();
                        if (!string.IsNullOrEmpty(meta.Notes))
                            col.Item().PaddingTop(2).Text($"Note: {meta.Notes}").Italic().FontSize(8);
                        if (!string.IsNullOrEmpty(truncatedNote))
                            col.Item().Text(truncatedNote).Italic().FontSize(8);
                    });

                    // Logo-ul productiei, in dreapta sus. Un raport care
                    // ajunge la client trebuie sa arate ca vine de la o
                    // firma, nu dintr-un utilitar generic. Orice problema la
                    // citirea imaginii e ignorata - raportul se genereaza
                    // oricum, fara logo.
                    if (!string.IsNullOrWhiteSpace(meta.LogoPath) && File.Exists(meta.LogoPath))
                    {
                        try
                        {
                            var bytes = File.ReadAllBytes(meta.LogoPath);
                            headerRow.ConstantItem(110).AlignRight().AlignTop().Height(45).Image(bytes).FitArea();
                        }
                        catch { /* raportul e mai important decat logo-ul */ }
                    }
                });

                page.Content().PaddingTop(10).Table(table =>
                {
                    table.ColumnsDefinition(c =>
                    {
                        c.RelativeColumn(4);
                        c.RelativeColumn(1.5f);
                        c.RelativeColumn(1.8f);
                        c.RelativeColumn(3);
                    });

                    table.Header(h =>
                    {
                        h.Cell().Background("#2b2b2b").Padding(4).Text("Fisier").FontColor(Colors.White).FontSize(9);
                        h.Cell().Background("#2b2b2b").Padding(4).Text("Marime").FontColor(Colors.White).FontSize(9);
                        h.Cell().Background("#2b2b2b").Padding(4).Text("Status").FontColor(Colors.White).FontSize(9);
                        h.Cell().Background("#2b2b2b").Padding(4).Text("Verificare sursa").FontColor(Colors.White).FontSize(9);
                    });

                    foreach (var row in rows)
                    {
                        var color = StatusColors.GetValueOrDefault(row.Status, "#333333");
                        table.Cell().BorderBottom(0.5f).BorderColor("#cccccc").Padding(3).Text(row.File).FontSize(8);
                        table.Cell().BorderBottom(0.5f).BorderColor("#cccccc").Padding(3).Text(FormatBytes(row.SizeBytes)).FontSize(8);
                        table.Cell().BorderBottom(0.5f).BorderColor("#cccccc").Padding(3).Text(row.Status).FontColor(color).FontSize(8).Bold();
                        table.Cell().BorderBottom(0.5f).BorderColor("#cccccc").Padding(3).Text(Truncate(row.SrcHash, 24)).FontSize(8);
                    }
                });

                page.Footer().AlignCenter().Text(t =>
                {
                    t.CurrentPageNumber();
                    t.Span(" / ");
                    t.TotalPages();
                });
            });
        }).GeneratePdf(path);

        return path;
    }

    private static string Truncate(string s, int max) => s.Length <= max ? s : s[..max];

    private static string FormatBytes(long bytes)
    {
        double b = bytes;
        string[] units = { "B", "KB", "MB", "GB", "TB" };
        int i = 0;
        while (b >= 1024 && i < units.Length - 1) { b /= 1024; i++; }
        return $"{b:0.0} {units[i]}";
    }
}
