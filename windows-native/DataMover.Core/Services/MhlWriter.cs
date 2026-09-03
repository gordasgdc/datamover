using System.IO;
using System.Text;

namespace DataMover.Core.Services;

/// <summary>
/// [2026-09-03] Port 1:1 al MHLWriter.swift (Mac) — generator de fisier MHL
/// (Media Hash List, versiunea 1.1), standardul prin care un ofloader de
/// platou preda datele catre post-productie.
///
/// DE CE: pana acum DataMover producea CSV + PDF, adica rapoarte pe care le
/// citeste un OM. Un MHL e acelasi lucru, dar citit de MASINA: Silverstack,
/// YoYotta, ShotPut Pro, Resolve si orice casa de post pot re-verifica
/// automat, luni mai tarziu, ca fiecare fisier de pe LTO/NAS e bit-identic
/// cu ce a iesit din camera in ziua filmarii.
///
/// MEMORIE (Regula 21): intrarile NU se acumuleaza in RAM — fiecare `hash`
/// se scrie imediat intr-un fisier temporar `.part`, iar la Close() se
/// compune fisierul final (antet + corp). Corpul nu poate fi scris direct
/// in fisierul final pentru ca `creatorinfo` sta obligatoriu PRIMUL in
/// schema si contine `finishdate`, cunoscut abia la sfarsit.
/// </summary>
public sealed class MhlWriter : IDisposable
{
    /// Algoritmii acceptati de schema MHL 1.1. SHA-256/SHA-512 NU fac parte
    /// din standard — cu ele, verificarea si rapoartele CSV/PDF/HTML raman
    /// complete, doar MHL-ul nu se genereaza.
    public static string? ElementFor(VerificationModel model) => model switch
    {
        VerificationModel.Md5 => "md5",
        VerificationModel.Sha1 => "sha1",
        VerificationModel.XxHash64 => "xxhash64be",
        _ => null,
    };

    public static bool IsSupported(VerificationModel model) => ElementFor(model) != null;

    private readonly string _finalPath;
    private readonly string _partPath;
    private readonly string _hashElement;
    private readonly string _toolName;
    private readonly DateTime _startedAt;
    private StreamWriter? _part;

    public int EntryCount { get; private set; }

    private MhlWriter(string path, string element, string toolName, DateTime startedAt)
    {
        _finalPath = path;
        _partPath = path + ".part";
        _hashElement = element;
        _toolName = toolName;
        _startedAt = startedAt;
        _part = new StreamWriter(_partPath, append: false, Encoding.UTF8);
    }

    /// null daca algoritmul nu e in standardul MHL sau fisierul nu poate fi
    /// deschis — apelantul continua transferul normal, fara MHL.
    public static MhlWriter? TryCreate(string path, VerificationModel model, string toolName, DateTime startedAt)
    {
        var element = ElementFor(model);
        if (element == null) return null;
        try { return new MhlWriter(path, element, toolName, startedAt); }
        catch { return null; }
    }

    /// Un fisier verificat cu succes. Se apeleaza DOAR pentru fisierele cu
    /// status OK/SARIT — un MHL nu are voie sa contina un fisier care n-a
    /// trecut verificarea, altfel ar certifica date corupte.
    public void Add(string relPath, long size, DateTime? modified, string hashHex, DateTime hashedAt)
    {
        if (_part == null || string.IsNullOrEmpty(hashHex)) return;
        try
        {
            // Caile din MHL folosesc mereu `/`, indiferent de platforma —
            // altfel un MHL scris pe Windows n-ar putea fi verificat pe Mac.
            var normalized = relPath.Replace('\\', '/');
            _part.WriteLine("  <hash>");
            _part.WriteLine($"    <file>{Escape(normalized)}</file>");
            _part.WriteLine($"    <size>{size}</size>");
            if (modified.HasValue)
                _part.WriteLine($"    <lastmodificationdate>{Iso(modified.Value)}</lastmodificationdate>");
            _part.WriteLine($"    <{_hashElement}>{hashHex}</{_hashElement}>");
            _part.WriteLine($"    <hashdate>{Iso(hashedAt)}</hashdate>");
            _part.WriteLine("  </hash>");
            EntryCount++;
        }
        catch { /* o intrare pierduta nu opreste transferul */ }
    }

    /// Scrie fisierul MHL final. Intoarce calea lui, sau null daca n-a
    /// existat nicio intrare valida (nu lasam pe disc un MHL gol, care ar
    /// parea o certificare a zero fisiere).
    public string? Close(DateTime finishedAt)
    {
        try { _part?.Flush(); _part?.Dispose(); } catch { /* ignora */ }
        _part = null;
        try
        {
            if (EntryCount == 0) return null;
            var header = new StringBuilder();
            header.AppendLine("<?xml version=\"1.0\" encoding=\"UTF-8\"?>");
            header.AppendLine("<hashlist version=\"1.1\">");
            header.AppendLine("  <creatorinfo>");
            header.AppendLine($"    <name>{Escape(Environment.UserName)}</name>");
            header.AppendLine($"    <username>{Escape(Environment.UserName)}</username>");
            header.AppendLine($"    <hostname>{Escape(Environment.MachineName)}</hostname>");
            header.AppendLine($"    <tool>{Escape(_toolName)}</tool>");
            header.AppendLine($"    <startdate>{Iso(_startedAt)}</startdate>");
            header.AppendLine($"    <finishdate>{Iso(finishedAt)}</finishdate>");
            header.AppendLine("  </creatorinfo>");

            using (var output = new StreamWriter(_finalPath, append: false, Encoding.UTF8))
            {
                output.Write(header.ToString());
                using (var input = new StreamReader(_partPath, Encoding.UTF8))
                {
                    var buffer = new char[64 * 1024];
                    int read;
                    while ((read = input.Read(buffer, 0, buffer.Length)) > 0)
                        output.Write(buffer, 0, read);
                }
                output.WriteLine("</hashlist>");
            }
            return _finalPath;
        }
        catch { return null; }
        finally
        {
            try { if (File.Exists(_partPath)) File.Delete(_partPath); } catch { /* ignora */ }
        }
    }

    public void Dispose()
    {
        try { _part?.Dispose(); } catch { /* ignora */ }
        _part = null;
    }

    private static string Iso(DateTime value) => value.ToString("yyyy-MM-ddTHH:mm:sszzz");

    private static string Escape(string s) => s
        .Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;")
        .Replace("\"", "&quot;").Replace("'", "&apos;");
}
