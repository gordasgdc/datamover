using System.IO;
using System.Text;
using DataMover.Core.Models;

namespace DataMover.Core.Services;

/// <summary>
/// [2026-09-03] Port 1:1 al ProductionMeta.swift (Mac) — metadatele
/// productiei, atasate unui transfer.
///
/// DE CE: raportul unui offload nu e un log tehnic, e un DOCUMENT DE
/// PREDARE — ajunge la producator, la casa de post, uneori la asigurator.
/// Un raport care spune doar "1240 fisiere OK" nu identifica nimic: nu se
/// stie al cui e proiectul, cine a facut descarcarea, de pe ce camera.
/// Aceleasi campuri alimenteaza si sablonul de denumire (NamingTemplate).
/// </summary>
public sealed class ProductionMeta
{
    public string Project { get; set; } = "";
    public string Card { get; set; } = "";
    public string Client { get; set; } = "";
    public string OperatorName { get; set; } = "";
    public string Camera { get; set; } = "";
    public string Notes { get; set; } = "";
    /// Cale catre un fisier imagine (PNG/JPG) folosit ca logo in antetul
    /// rapoartelor. Gol = fara logo, raportul ramane la fel de valid.
    public string LogoPath { get; set; } = "";

    /// Perechile completate, gata de afisat in antetul unui raport. Campurile
    /// goale NU apar deloc — un raport cu "Client: —" arata neterminat.
    public List<(string Label, string Value)> HeaderFields()
    {
        var fields = new List<(string, string)>();
        if (Project.Length > 0) fields.Add(("Proiect", Project));
        if (Client.Length > 0) fields.Add(("Client", Client));
        if (Card.Length > 0) fields.Add(("Card", Card));
        if (Camera.Length > 0) fields.Add(("Camera", Camera));
        if (OperatorName.Length > 0) fields.Add(("Operator / DIT", OperatorName));
        return fields;
    }
}

/// <summary>
/// Raport HTML — a doua forma a aceluiasi raport, alaturi de CSV si PDF.
/// Se deschide in orice browser, pe orice telefon, fara cititor de PDF, si
/// poate fi trimis pe WhatsApp/email fara sa-si piarda formatarea.
/// </summary>
public static class HtmlReport
{
    public static bool Write(string path, string destination, string folderName, IReadOnlyList<ReportRow> rows,
        ProductionMeta meta, DateTime startedAt, DateTime finishedAt,
        int okCount, int skipCount, int failCount, int recoveredCount,
        bool cancelled, string verificationLabel, string? mhlPath, string? truncatedNote, string appVersion)
    {
        try
        {
            var html = new StringBuilder();
            html.AppendLine("<!doctype html>");
            html.AppendLine("<html lang=\"ro\"><head><meta charset=\"utf-8\">");
            html.AppendLine("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">");
            html.AppendLine($"<title>Raport offload — {Escape(folderName)}</title>");
            html.AppendLine(@"<style>
:root { color-scheme: dark; }
body { margin:0; padding:24px; background:#14161A; color:#EDEFF2; font: 14px/1.5 'Segoe UI', Roboto, sans-serif; }
.wrap { max-width: 1100px; margin: 0 auto; }
header { display:flex; align-items:center; gap:16px; border-bottom:1px solid #2A2F36; padding-bottom:16px; }
header img { max-height:56px; max-width:200px; }
h1 { font-size:20px; margin:0 0 4px; }
.sub { color:#9AA3AE; font-size:13px; }
.meta { display:grid; grid-template-columns:repeat(auto-fit,minmax(200px,1fr)); gap:8px 24px; margin:18px 0; }
.meta div span { color:#9AA3AE; display:block; font-size:11px; text-transform:uppercase; letter-spacing:.04em; }
.cards { display:flex; flex-wrap:wrap; gap:12px; margin:18px 0; }
.card { background:#1A1D22; border:1px solid #2A2F36; border-radius:8px; padding:12px 16px; min-width:110px; }
.card b { display:block; font-size:22px; }
.ok b { color:#4ADE80; } .skip b { color:#9AA3AE; } .fail b { color:#F87171; } .rec b { color:#D08C40; }
.notes { background:#1A1D22; border-left:3px solid #D08C40; padding:10px 14px; border-radius:4px; white-space:pre-wrap; }
table { width:100%; border-collapse:collapse; margin-top:16px; font-size:12px; }
th { text-align:left; color:#9AA3AE; font-weight:600; border-bottom:1px solid #2A2F36; padding:6px 8px; }
td { padding:6px 8px; border-bottom:1px solid #20242A; word-break:break-all; }
.s-ok { color:#4ADE80; } .s-fail { color:#F87171; } .s-skip { color:#9AA3AE; }
footer { margin-top:24px; color:#6B737D; font-size:11px; }
@media (max-width:700px){ body{padding:14px} table{font-size:11px} }
</style></head><body><div class=""wrap"">");

            html.Append("<header>");
            var logo = LogoDataUri(meta.LogoPath);
            if (logo != null) html.Append($"<img src=\"{logo}\" alt=\"logo\">");
            html.Append("<div><h1>Raport de descărcare (offload)</h1>");
            html.Append($"<div class=\"sub\">{Escape(folderName)} → {Escape(destination)}</div></div></header>");

            html.Append("<div class=\"meta\">");
            foreach (var (label, value) in meta.HeaderFields())
                html.Append($"<div><span>{Escape(label)}</span>{Escape(value)}</div>");
            html.Append($"<div><span>Început</span>{startedAt:yyyy-MM-dd HH:mm:ss}</div>");
            html.Append($"<div><span>Terminat</span>{finishedAt:yyyy-MM-dd HH:mm:ss}</div>");
            html.Append($"<div><span>Verificare</span>{Escape(verificationLabel)}</div>");
            if (mhlPath != null)
                html.Append($"<div><span>MHL</span>{Escape(Path.GetFileName(mhlPath))}</div>");
            html.Append("</div>");

            html.Append("<div class=\"cards\">");
            html.Append($"<div class=\"card ok\"><b>{okCount}</b>copiate OK</div>");
            html.Append($"<div class=\"card skip\"><b>{skipCount}</b>sărite</div>");
            html.Append($"<div class=\"card fail\"><b>{failCount}</b>probleme</div>");
            if (recoveredCount > 0)
                html.Append($"<div class=\"card rec\"><b>{recoveredCount}</b>recuperate la reîncercare</div>");
            html.Append("</div>");

            if (cancelled)
                html.Append("<p class=\"s-fail\"><b>Transfer anulat de utilizator — lista de mai jos nu este completă.</b></p>");
            if (meta.Notes.Length > 0)
                html.Append($"<div class=\"notes\">{Escape(meta.Notes)}</div>");

            html.Append("<table><thead><tr><th>Fișier</th><th>Mărime</th><th>Sursă</th><th>Destinație</th><th>Status</th><th>Eroare</th></tr></thead><tbody>");
            foreach (var row in rows)
            {
                var cls = row.Status.StartsWith("OK") ? "s-ok" : (row.Status.StartsWith("SARIT") ? "s-skip" : "s-fail");
                html.Append($"<tr><td>{Escape(row.File)}</td><td>{FormatBytes(row.SizeBytes)}</td>");
                html.Append($"<td>{Escape(Short(row.SrcHash))}</td><td>{Escape(Short(row.DstHash))}</td>");
                html.Append($"<td class=\"{cls}\">{Escape(row.Status)}</td><td>{Escape(row.Error)}</td></tr>");
            }
            html.Append("</tbody></table>");

            if (truncatedNote != null)
                html.Append($"<p class=\"sub\">{Escape(truncatedNote)}</p>");
            html.Append($"<footer>Generat de DataMover {Escape(appVersion)} — gordas.dev</footer>");
            html.Append("</div></body></html>");

            File.WriteAllText(path, html.ToString(), Encoding.UTF8);
            return true;
        }
        catch { return false; }
    }

    /// Logo-ul se INCORPOREAZA in HTML ca data URI. Un `img src="fisier"`
    /// ar functiona doar cat timp raportul sta langa imaginea originala —
    /// exact ce nu se intampla cand raportul e trimis pe email sau mutat.
    private static string? LogoDataUri(string path)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(path) || !File.Exists(path)) return null;
            var data = File.ReadAllBytes(path);
            // Limita de bun-simt: un logo de zeci de MB ar umfla fiecare raport.
            if (data.Length > 3 * 1024 * 1024) return null;
            var ext = Path.GetExtension(path).ToLowerInvariant();
            var mime = ext is ".jpg" or ".jpeg" ? "image/jpeg" : (ext == ".gif" ? "image/gif" : "image/png");
            return $"data:{mime};base64,{Convert.ToBase64String(data)}";
        }
        catch { return null; }
    }

    private static string Short(string hash) => hash.Length > 20 ? hash[..20] + "…" : hash;

    private static string FormatBytes(long bytes)
    {
        double b = bytes;
        string[] units = { "B", "KB", "MB", "GB", "TB" };
        int i = 0;
        while (b >= 1024 && i < units.Length - 1) { b /= 1024; i++; }
        return $"{b:0.0} {units[i]}";
    }

    private static string Escape(string s) => (s ?? "")
        .Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;");
}
