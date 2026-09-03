namespace DataMover.Core.Services;

/// <summary>
/// [2026-09-03] Port 1:1 al NamingTemplate.swift (Mac) — sablon
/// configurabil pentru numele folderului de destinatie.
///
/// DE CE: pana acum numele era fix — `&lt;data&gt;_&lt;Proiect&gt;_&lt;Card&gt;`. Fiecare
/// productie are insa propria conventie de denumire, impusa de casa de post
/// sau de arhiva. Cand aplicatia nu poate respecta conventia, operatorul
/// redenumeste manual folderele dupa fiecare card.
///
/// Sablonul implicit reproduce EXACT comportamentul vechi.
/// </summary>
public static class NamingTemplate
{
    public const string DefaultTemplate = "{data}_{proiect}_{card}";

    public static readonly string[] Tokens =
        { "{data}", "{ora}", "{proiect}", "{card}", "{camera}", "{operator}" };

    public sealed class Context
    {
        public string Project { get; set; } = "";
        public string Card { get; set; } = "";
        public string Camera { get; set; } = "";
        public string OperatorName { get; set; } = "";
        public DateTime Date { get; set; } = DateTime.Now;
    }

    public static string Render(string template, Context context) => Expand(template, context, true);

    /// Acelasi sablon, dar FARA partile care se schimba de la o rulare la
    /// alta (data/ora) — "miezul stabil", folosit ca sa recunoastem un
    /// transfer anterior al ACELUIASI card, inceput in alta zi.
    public static string StableCore(string template, Context context) => Expand(template, context, false);

    private static string Expand(string template, Context context, bool includeTimeTokens)
    {
        var result = string.IsNullOrWhiteSpace(template) ? DefaultTemplate : template;
        var replacements = new (string Token, string Value)[]
        {
            ("{data}", includeTimeTokens ? context.Date.ToString("yyyy-MM-dd") : ""),
            ("{ora}", includeTimeTokens ? context.Date.ToString("HH-mm") : ""),
            ("{proiect}", Fallback(context.Project, "Proiect")),
            ("{card}", Fallback(context.Card, "Card")),
            // Camera/operator raman GOALE daca nu sunt completate — spre
            // deosebire de proiect/card, care au implicite istorice.
            ("{camera}", Sanitize(context.Camera)),
            ("{operator}", Sanitize(context.OperatorName)),
        };
        foreach (var (token, value) in replacements)
            result = ReplaceIgnoreCase(result, token, value);
        return CleanUp(result);
    }

    private static string ReplaceIgnoreCase(string text, string token, string value)
    {
        int index;
        while ((index = text.IndexOf(token, StringComparison.OrdinalIgnoreCase)) >= 0)
            text = text.Remove(index, token.Length).Insert(index, value);
        return text;
    }

    private static string Fallback(string value, string implicitValue)
    {
        var trimmed = (value ?? "").Trim();
        return Sanitize(trimmed.Length == 0 ? implicitValue : trimmed);
    }

    /// Scoate ce nu are ce cauta intr-un nume de folder Windows si
    /// inlocuieste spatiile cu `_`, ca in comportamentul vechi.
    private static string Sanitize(string value)
    {
        var trimmed = (value ?? "").Trim();
        var forbidden = new[] { '/', '\\', ':', '*', '?', '"', '<', '>', '|' };
        foreach (var c in forbidden) trimmed = trimmed.Replace(c.ToString(), "");
        return trimmed.Replace(" ", "_");
    }

    /// Un token gol lasa in urma separatori duplicati (`__`) sau la capete
    /// (`_Proiect`), care arata a bug intr-un nume de folder livrat la
    /// arhiva.
    private static string CleanUp(string value)
    {
        var result = value;
        while (result.Contains("__")) result = result.Replace("__", "_");
        while (result.Contains("--")) result = result.Replace("--", "-");
        result = result.Trim('_', '-', ' ');
        return result.Length == 0 ? "Transfer" : result;
    }
}
