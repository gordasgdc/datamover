using System.Globalization;
using System.Text;
using DataMover.Core.Models;

namespace DataMover.Core.Services;

/// Verdictul unei destinații — aceeași regulă ca pe macOS (DestinationOutcome.evaluate)
/// și ca ecranul Rezultat din clientul WPF.
public enum DestinationOutcome { Verified, VerifiedWithWarnings, Failed, Cancelled }

/// Raportul de livrare (PDF + HTML): port 1:1 al
/// mac-native/Sources/DataMoverMac/Reporting/DeliveryReport.swift. Textele și CSS-ul
/// sunt generate din sursa Swift (DeliveryReportText.g.cs). Fără miniaturi: raportul
/// nu conține nimic din conținutul fișierelor media.
public sealed class DeliveryReport
{
    public string Lang { get; set; } = "ro";
    public string AppVersion { get; set; } = "";
    public DateTimeOffset GeneratedAt { get; set; } = DateTimeOffset.Now;
    public string FolderName { get; set; } = "";
    public string SourceName { get; set; } = "";
    public string Destination { get; set; } = "";
    public string Project { get; set; } = "";
    public string Card { get; set; } = "";
    public string Client { get; set; } = "";
    public string OperatorName { get; set; } = "";
    public string Camera { get; set; } = "";
    public string Notes { get; set; } = "";
    public string LogoPath { get; set; } = "";
    public DateTimeOffset StartedAt { get; set; }
    public DateTimeOffset FinishedAt { get; set; }
    public string Verification { get; set; } = "";
    public int CopyCount { get; set; } = 1;
    public int OkCount { get; set; }
    public int SkipCount { get; set; }
    public int FailCount { get; set; }
    public int RecoveredCount { get; set; }
    public long BytesConfirmed { get; set; }
    public bool Cancelled { get; set; }
    public string? MhlFile { get; set; }
    public string? CsvFile { get; set; }
    public string JobId { get; set; } = "";
    public IReadOnlyList<ReportRow> Rows { get; set; } = Array.Empty<ReportRow>();
    public Func<ReportRow, string?>? MediaLine { get; set; }

    public int TotalFiles => OkCount + SkipCount + FailCount;
    public bool IsTruncated => Rows.Count < TotalFiles;
    public DestinationOutcome Outcome => Evaluate(FailCount, RecoveredCount, Cancelled);

    public static DestinationOutcome Evaluate(int failCount, int recoveredCount, bool cancelled) =>
        cancelled ? DestinationOutcome.Cancelled
        : failCount > 0 ? DestinationOutcome.Failed
        : recoveredCount > 0 ? DestinationOutcome.VerifiedWithWarnings
        : DestinationOutcome.Verified;

    /// Limba raportului: ro/en/es din limba interfeței Windows, altfel română (limba aplicației).
    public static string LangFromCulture(CultureInfo c) => c.TwoLetterISOLanguageName switch { "en" => "en", "es" => "es", _ => "ro" };

    // MARK: texte

    public string T(string key)
    {
        if (!DeliveryReportText.Strings.TryGetValue(key, out var v)) return key;
        return v[Lang switch { "en" => 1, "es" => 2, _ => 0 }];
    }
    /// Înlocuiește %d / %@ în ordine (formatul comun cu sursa Swift).
    public string F(string key, params object[] args)
    {
        var s = T(key); var sb = new StringBuilder(); int a = 0;
        for (int i = 0; i < s.Length; i++)
        {
            if (s[i] == '%' && i + 1 < s.Length && (s[i + 1] == 'd' || s[i + 1] == '@'))
            { sb.Append(a < args.Length ? Convert.ToString(args[a++], CultureInfo.InvariantCulture) : ""); i++; }
            else sb.Append(s[i]);
        }
        return sb.ToString();
    }

    static string OutcomeKey(DestinationOutcome o) => o switch
    {
        DestinationOutcome.Verified => "verified", DestinationOutcome.VerifiedWithWarnings => "verifiedWithWarnings",
        DestinationOutcome.Failed => "failed", _ => "cancelled",
    };
    public string VerdictTitle => T("verdict." + OutcomeKey(Outcome));
    public string VerdictSymbol => Outcome switch
    {
        DestinationOutcome.Verified => "✓", DestinationOutcome.VerifiedWithWarnings => "!", DestinationOutcome.Failed => "✕", _ => "–",
    };
    public string VerdictHelp => Outcome switch
    {
        DestinationOutcome.Verified => F("help.verified", OkCount),
        DestinationOutcome.VerifiedWithWarnings => F("help.verifiedWithWarnings", RecoveredCount),
        DestinationOutcome.Failed => F("help.failed", FailCount),
        _ => T("help.cancelled"),
    };
    public string OutcomeCss => "v-" + OutcomeKey(Outcome);

    /// Statusul brut al motorului, tradus. CSV-ul păstrează valoarea brută (contractul lui).
    public (string Text, string Kind) StatusText(string raw)
    {
        bool retry = raw.Contains("reîncercat");
        (string, string) b = raw.StartsWith("OK") ? (T("st.ok"), retry ? "warn" : "ok")
            : raw.StartsWith("SARIT") ? (T("st.skip"), "skip")
            : raw.StartsWith("NEPOTRIVIRE") ? (T("st.mismatch"), "fail")
            : (T("st.error"), "fail");
        return (retry ? $"{b.Item1}, {T("st.retry")}" : b.Item1, b.Item2);
    }
    public static string SymbolForKind(string k) => k switch { "ok" => "✓", "warn" => "!", "skip" => "–", _ => "✕" };

    public string ChecksumText(ReportRow r)
    {
        if (r.SrcHash.Length == 0 && r.DstHash.Length == 0) return "—";
        if (r.SrcHash.Length > 0 && r.SrcHash == r.DstHash) return $"{ShortHash(r.SrcHash)}\n{T("cs.match")}";
        return $"{ShortHash(r.SrcHash.Length == 0 ? r.DstHash : r.SrcHash)}\n{T("cs.differs")}";
    }
    public static string ShortHash(string h) => h.Length > 16 ? h[..16] + "…" : h;

    // MARK: formatare deterministă

    public string Bytes(long b)
    {
        string[] u = { "B", "KB", "MB", "GB", "TB" }; double v = b; int i = 0;
        while (v >= 1000 && i < u.Length - 1) { v /= 1000; i++; }
        var s = i == 0 ? ((long)v).ToString(CultureInfo.InvariantCulture) : v.ToString("0.0", CultureInfo.InvariantCulture);
        if (Lang != "en") s = s.Replace('.', ',');
        return $"{s} {u[i]}";
    }
    public string Grouped(long n) => n.ToString("#,0", CultureInfo.InvariantCulture).Replace(",", Lang == "en" ? "," : ".");
    public static string Date(DateTimeOffset d) => d.ToString("yyyy-MM-dd HH:mm:ss zzz", CultureInfo.InvariantCulture);
    public string Duration
    {
        get
        {
            var s = Math.Max(0, (int)Math.Round((FinishedAt - StartedAt).TotalSeconds));
            return $"{s / 3600:00}:{s % 3600 / 60:00}:{s % 60:00}";
        }
    }

    public List<(string Label, string Value)> DetailFields
    {
        get
        {
            var f = new List<(string, string)>();
            void Add(string k, string? v) { if (!string.IsNullOrWhiteSpace(v)) f.Add((T(k), v!)); }
            Add("f.project", Project); Add("f.card", Card); Add("f.source", SourceName);
            Add("f.client", Client); Add("f.operator", OperatorName); Add("f.camera", Camera);
            Add("f.started", Date(StartedAt)); Add("f.finished", Date(FinishedAt)); Add("f.duration", Duration);
            Add("f.verification", Verification); Add("f.copies", CopyCount.ToString(CultureInfo.InvariantCulture));
            Add("f.mhl", MhlFile); Add("f.csv", CsvFile); Add("f.job", JobId);
            return f;
        }
    }
    public List<(string Label, string Value)> SummaryFields
    {
        get
        {
            var s = new List<(string, string)>
            {
                (T("s.confirmed"), $"{OkCount} / {TotalFiles}"),
                (T("s.bytes"), $"{Bytes(BytesConfirmed)} ({Grouped(BytesConfirmed)} B)"),
            };
            if (RecoveredCount > 0) s.Add((T("s.retried"), RecoveredCount.ToString(CultureInfo.InvariantCulture)));
            s.Add((T("s.failed"), FailCount.ToString(CultureInfo.InvariantCulture)));
            if (SkipCount > 0) s.Add((T("s.skipped"), SkipCount.ToString(CultureInfo.InvariantCulture)));
            return s;
        }
    }
    public string FooterLine => F("footer.gen", AppVersion, Date(GeneratedAt));

    // MARK: HTML (aceeași structură ca pe macOS)

    static string E(string s) => (s ?? "").Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;");

    public string Html(string? logoDataUri = null)
    {
        var h = new StringBuilder();
        h.Append($"<!doctype html>\n<html lang=\"{Lang}\"><head><meta charset=\"utf-8\">");
        h.Append("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">");
        h.Append($"<title>{E(T("doc"))} — {E(FolderName)}</title><style>{DeliveryReportText.Css}</style></head><body><div class=\"doc\">");
        h.Append($"<header><div class=\"brand\">{DeliveryReportText.MarkSvg}DataMover</div>");
        h.Append(logoDataUri != null ? $"<img src=\"{logoDataUri}\" alt=\"\">" : $"<div class=\"kind\">{E(T("doc"))}</div>");
        h.Append("</header>");
        h.Append($"<h1>{E(T("doc"))} — {E(FolderName)}</h1>");
        h.Append($"<p class=\"dest mono\">{E(T("destination"))}: {E(Destination)}</p>");
        h.Append($"<section class=\"verdict {OutcomeCss}\" role=\"status\"><div class=\"sym\" aria-hidden=\"true\">{VerdictSymbol}</div>");
        h.Append($"<div><b>{E(VerdictTitle)}</b><p>{E(VerdictHelp)}</p></div></section>");
        h.Append("<div class=\"summary\">");
        foreach (var (l, v) in SummaryFields) h.Append($"<div><span>{E(l)}</span><b>{E(v)}</b></div>");
        h.Append("</div><dl class=\"grid\">");
        foreach (var (l, v) in DetailFields) h.Append($"<dt>{E(l)}</dt><dd>{E(v)}</dd>");
        h.Append("</dl>");
        if (Notes.Length > 0) h.Append($"<div class=\"notes\"><b>{E(T("f.notes"))}</b>\n{E(Notes)}</div>");
        h.Append($"<h2>{E(T("files"))} ({TotalFiles})</h2>");
        if (IsTruncated) h.Append($"<p class=\"sample\">{E(F("files.sample", Rows.Count, TotalFiles))}</p>");
        h.Append($"<table><thead><tr><th>#</th><th>{E(T("col.file"))}</th><th>{E(T("col.size"))}</th><th>{E(T("col.checksum"))}</th><th>{E(T("col.status"))}</th></tr></thead><tbody>");
        for (int i = 0; i < Rows.Count; i++)
        {
            var r = Rows[i]; var st = StatusText(r.Status);
            h.Append($"<tr><td class=\"num\">{i + 1}</td><td class=\"file mono\">{E(r.File)}");
            var m = MediaLine?.Invoke(r);
            if (!string.IsNullOrEmpty(m)) h.Append($"<div class=\"sub\">{E(m)}</div>");
            if (r.Error.Length > 0) h.Append($"<div class=\"err\">{E(r.Error)}</div>");
            h.Append($"</td><td class=\"num\">{E(Bytes(r.SizeBytes))}</td><td class=\"mono\">{E(ChecksumText(r)).Replace("\n", "<br>")}</td>");
            h.Append($"<td class=\"st k-{st.Kind}\">{SymbolForKind(st.Kind)} {E(st.Text)}</td></tr>");
        }
        h.Append("</tbody></table>");
        h.Append($"<footer>{E(FooterLine)}<br>{E(T("footer.basis"))}</footer></div></body></html>\n");
        return h.ToString();
    }

    public static string? LogoDataUri(string path)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(path) || !File.Exists(path)) return null;
            var data = File.ReadAllBytes(path);
            if (data.Length > 3 * 1024 * 1024) return null;
            var ext = Path.GetExtension(path).ToLowerInvariant();
            var mime = ext is ".jpg" or ".jpeg" ? "image/jpeg" : ext == ".gif" ? "image/gif" : "image/png";
            return $"data:{mime};base64,{Convert.ToBase64String(data)}";
        }
        catch { return null; }
    }
}
