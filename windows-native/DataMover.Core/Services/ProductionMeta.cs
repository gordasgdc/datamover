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
