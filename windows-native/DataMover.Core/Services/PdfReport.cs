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

                // [M4, 2026-09-06] Randuri "DIT" - thumbnail real (Shell COM,
                // vezi ThumbnailExtractor) + metadate video (rezolutie/fps/
                // codec/canale audio, vezi MediaInspector) + status Pass/Fail
                // colorat, in loc de tabelul text simplu de pana acum.
                // Extragerea ruleaza DOAR aici (la generarea raportului, pe
                // esantionul deja plafonat), niciodata in timpul copierii -
                // motorul de transfer (FanOutCopier) ramane complet neatins.
                page.Content().PaddingTop(10).Column(col =>
                {
                    foreach (var row in rows)
                    {
                        var color = StatusColors.GetValueOrDefault(row.Status, "#333333");
                        var media = MediaInspector.Probe(row.DestPath);
                        var thumbBytes = ThumbnailExtractor.ThumbnailJpegBytes(row.DestPath, 120, 68);

                        col.Item().PaddingBottom(6).BorderBottom(0.5f).BorderColor("#cccccc").Row(r =>
                        {
                            r.ConstantItem(60).Height(34).Background("#e0e0e0").Element(e =>
                            {
                                if (thumbBytes != null) e.Image(thumbBytes).FitArea();
                            });
                            r.RelativeItem().PaddingLeft(8).Column(c =>
                            {
                                c.Item().Row(rr =>
                                {
                                    rr.RelativeItem().Text(row.File).FontSize(9).Bold();
                                    rr.AutoItem().Text(row.Status).FontColor(color).FontSize(8).Bold();
                                });
                                var metaParts = new List<string> { FormatBytes(row.SizeBytes) };
                                if (media != null)
                                {
                                    if (media.ResolutionText != null) metaParts.Add(media.ResolutionText);
                                    if (media.FrameRate != null) metaParts.Add($"{media.FrameRate:0.00} fps");
                                    if (media.VideoCodec != null) metaParts.Add(media.VideoCodec);
                                    if (media.AudioChannels != null) metaParts.Add($"{media.AudioChannels}ch audio");
                                }
                                c.Item().Text(string.Join("  ·  ", metaParts)).FontSize(8).FontColor("#666666");
                                if (!string.IsNullOrEmpty(row.Error))
                                    c.Item().Text(Truncate(row.Error, 90)).FontSize(8).FontColor("#b02a2a");
                            });
                        });
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
