using DataMover.Core.Models;
using QuestPDF.Fluent;
using QuestPDF.Helpers;
using QuestPDF.Infrastructure;

namespace DataMover.Core.Services;

/// Raportul de livrare PDF (QuestPDF, A4). Același model și aceleași texte ca
/// raportul HTML și ca varianta macOS (DeliveryReport); randarea diferă doar
/// tehnic. Tabelul își repetă antetul pe fiecare pagină, iar un rând nu se rupe
/// între pagini.
public static class PdfReport
{
    const string Ink = "#1A1D22", Dim = "#5B6470", Rule = "#D5D9DE", Band = "#F6F7F8", Amber = "#B8691F";

    static string KindColor(string k) => k switch { "ok" => "#1F7A45", "warn" => "#9A6200", "fail" => "#B42318", _ => Dim };
    static string VerdictColor(DestinationOutcome o) => o switch
    {
        DestinationOutcome.Verified => "#1F7A45", DestinationOutcome.VerifiedWithWarnings => "#9A6200",
        DestinationOutcome.Failed => "#B42318", _ => Dim,
    };

    public static void Write(DeliveryReport r, string path)
    {
        QuestPDF.Settings.License = LicenseType.Community;
        var vc = VerdictColor(r.Outcome);
        byte[]? logo = null;
        try { if (!string.IsNullOrWhiteSpace(r.LogoPath) && File.Exists(r.LogoPath)) logo = File.ReadAllBytes(r.LogoPath); }
        catch { /* raportul e mai important decât logo-ul */ }

        Document.Create(doc =>
        {
            doc.Page(page =>
            {
                page.Size(PageSizes.A4);
                page.Margin(15, Unit.Millimetre);
                page.DefaultTextStyle(x => x.FontSize(8.5f).FontColor(Ink));

                page.Header().PaddingBottom(8).BorderBottom(1.2f).BorderColor(Ink).PaddingBottom(6).Row(h =>
                {
                    h.ConstantItem(20).Height(20).Svg(DeliveryReportText.MarkSvg.Replace("#B8691F", Amber));
                    h.ConstantItem(6);
                    h.RelativeItem().AlignMiddle().Text("DataMover").FontSize(10).SemiBold();
                    if (logo != null) h.ConstantItem(110).Height(26).AlignRight().Image(logo).FitArea();
                    else h.RelativeItem().AlignRight().AlignMiddle().Text(r.T("doc").ToUpperInvariant()).FontSize(7.5f).SemiBold().FontColor(Dim);
                });

                page.Content().Column(col =>
                {
                    col.Item().PaddingTop(4).Text($"{r.T("doc")} — {r.FolderName}").FontSize(17).SemiBold();
                    col.Item().PaddingTop(2).Text($"{r.T("destination")}: {r.Destination}").FontFamily(Fonts.Consolas).FontSize(8).FontColor(Dim);

                    // Verdict: bordură + simbol + cuvânt — lizibil și alb-negru.
                    col.Item().PaddingTop(12).Border(r.Outcome == DestinationOutcome.Failed ? 2.4f : 1.4f).BorderColor(vc)
                        .BorderLeft(6).BorderColor(vc).Padding(10).Row(v =>
                        {
                            v.ConstantItem(44).AlignMiddle().AlignCenter().Text(r.VerdictSymbol).FontSize(26).Bold().FontColor(vc);
                            v.RelativeItem().Column(c =>
                            {
                                c.Item().Text(r.VerdictTitle).FontSize(15).SemiBold().FontColor(vc);
                                c.Item().PaddingTop(2).Text(r.VerdictHelp).FontSize(9);
                            });
                        });

                    col.Item().PaddingTop(12).Border(0.6f).BorderColor(Rule).Row(s =>
                    {
                        var fields = r.SummaryFields;
                        for (int i = 0; i < fields.Count; i++)
                        {
                            var cell = s.RelativeItem();
                            if (i > 0) cell = cell.BorderLeft(0.6f).BorderColor(Rule);
                            var f = fields[i];
                            cell.Padding(7).Column(c =>
                            {
                                c.Item().Text(f.Label.ToUpperInvariant()).FontSize(6.5f).SemiBold().FontColor(Dim);
                                c.Item().PaddingTop(3).Text(f.Value).FontSize(9.5f).SemiBold();
                            });
                        }
                    });

                    col.Item().PaddingTop(12).Table(t =>
                    {
                        t.ColumnsDefinition(c => { c.ConstantColumn(150); c.RelativeColumn(); });
                        foreach (var (l, v) in r.DetailFields)
                        {
                            t.Cell().PaddingBottom(2).Text(l).FontColor(Dim);
                            t.Cell().PaddingBottom(2).Text(v);
                        }
                    });

                    if (r.Notes.Length > 0)
                        col.Item().PaddingTop(8).BorderLeft(2.5f).BorderColor(Amber).PaddingLeft(10).Text($"{r.T("f.notes")}: {r.Notes}");

                    col.Item().PaddingTop(12).Text($"{r.T("files")} ({r.TotalFiles})").FontSize(11).SemiBold();
                    if (r.IsTruncated)
                        col.Item().PaddingTop(2).Text(r.F("files.sample", r.Rows.Count, r.TotalFiles)).FontSize(8).FontColor(Dim);

                    col.Item().PaddingTop(4).Table(t =>
                    {
                        t.ColumnsDefinition(c =>
                        {
                            c.ConstantColumn(22); c.RelativeColumn(4); c.ConstantColumn(54); c.ConstantColumn(142); c.RelativeColumn(2);
                        });
                        t.Header(hd =>
                        {
                            foreach (var label in new[] { "#", r.T("col.file"), r.T("col.size"), r.T("col.checksum"), r.T("col.status") })
                                hd.Cell().Background(Band).BorderBottom(0.9f).BorderColor(Ink).Padding(4)
                                    .Text(label.ToUpperInvariant()).FontSize(7).SemiBold().FontColor(Dim);
                        });
                        for (int i = 0; i < r.Rows.Count; i++)
                        {
                            var row = r.Rows[i]; var st = r.StatusText(row.Status);
                            IContainer Cell() => t.Cell().BorderBottom(0.6f).BorderColor(Rule).Padding(4);
                            Cell().AlignRight().Text((i + 1).ToString()).FontColor(Dim).FontSize(7.5f);
                            Cell().Column(c =>
                            {
                                c.Item().Text(row.File).FontFamily(Fonts.Consolas).FontSize(7.5f);
                                var m = r.MediaLine?.Invoke(row);
                                if (!string.IsNullOrEmpty(m)) c.Item().Text(m).FontSize(7).FontColor(Dim);
                                if (row.Error.Length > 0) c.Item().Text(row.Error).FontSize(7).FontColor("#B42318");
                            });
                            Cell().AlignRight().Text(r.Bytes(row.SizeBytes)).FontSize(7.5f);
                            Cell().Text(r.ChecksumText(row)).FontFamily(Fonts.Consolas).FontSize(7);
                            Cell().Text($"{DeliveryReport.SymbolForKind(st.Kind)} {st.Text}").FontSize(7.5f).SemiBold().FontColor(KindColor(st.Kind));
                        }
                    });
                });

                page.Footer().PaddingTop(6).BorderTop(0.6f).BorderColor(Rule).PaddingTop(4).Row(f =>
                {
                    f.RelativeItem().Column(c =>
                    {
                        c.Item().Text(r.FooterLine).FontSize(7).FontColor(Dim);
                        c.Item().Text(r.T("footer.basis")).FontSize(7).FontColor(Dim);
                    });
                    f.ConstantItem(90).AlignRight().Text(t =>
                    {
                        t.DefaultTextStyle(x => x.FontSize(7.5f).SemiBold().FontColor(Dim));
                        var parts = r.T("footer.page").Split("%d");
                        t.Span(parts[0]); t.CurrentPageNumber(); t.Span(parts.Length > 1 ? parts[1] : " / "); t.TotalPages();
                        if (parts.Length > 2) t.Span(parts[2]);
                    });
                });
            });
        }).GeneratePdf(path);
    }
}
