// GENERAT din mac-native/Sources/DataMoverMac/Reporting/DeliveryReport.swift
// (texte + CSS), ca rapoartele Mac și Windows să spună exact același lucru.
// Regenerare: scripts/gen-report-strings.py. Nu edita manual.
namespace DataMover.Core.Services;

public static partial class DeliveryReportText
{
    public static readonly Dictionary<string, string[]> Strings = new()
    {
        ["doc"] = new[] { "Raport de livrare", "Delivery report", "Informe de entrega" },
        ["destination"] = new[] { "Destinație", "Destination", "Destino" },
        ["verdict.verified"] = new[] { "VERIFICAT", "VERIFIED", "VERIFICADO" },
        ["verdict.verifiedWithWarnings"] = new[] { "VERIFICAT, CU AVERTISMENTE", "VERIFIED, WITH WARNINGS", "VERIFICADO, CON AVISOS" },
        ["verdict.failed"] = new[] { "NECONFIRMAT", "NOT CONFIRMED", "NO CONFIRMADO" },
        ["verdict.cancelled"] = new[] { "ANULAT", "CANCELLED", "CANCELADO" },
        ["help.verified"] = new[] { "Toate fișierele (%d) au fost confirmate prin verificarea aleasă la această destinație.", "All files (%d) were confirmed by the selected verification at this destination.", "Todos los archivos (%d) se confirmaron con la verificación elegida en este destino." },
        ["help.verifiedWithWarnings"] = new[] { "Toate fișierele sunt confirmate. Reușite abia la reîncercare: %d — verifică cablul, cardul și discul.", "All files are confirmed. Succeeded only on retry: %d — check the cable, card and drive.", "Todos los archivos están confirmados. Correctos solo al reintentar: %d — revisa el cable, la tarjeta y el disco." },
        ["help.failed"] = new[] { "Fișiere neconfirmate la această destinație: %d. Nu formata cardul.", "Files not confirmed at this destination: %d. Do not format the card.", "Archivos sin confirmar en este destino: %d. No formatees la tarjeta." },
        ["help.cancelled"] = new[] { "Transferul a fost oprit înainte de final; lista nu este completă. Nu formata cardul.", "The transfer was stopped before it finished; the list is incomplete. Do not format the card.", "La transferencia se detuvo antes de terminar; la lista no está completa. No formatees la tarjeta." },
        ["f.project"] = new[] { "Proiect", "Project", "Proyecto" },
        ["f.card"] = new[] { "Card", "Card", "Tarjeta" },
        ["f.source"] = new[] { "Sursă", "Source", "Origen" },
        ["f.client"] = new[] { "Client", "Client", "Cliente" },
        ["f.operator"] = new[] { "Operator", "Operator", "Operador" },
        ["f.camera"] = new[] { "Cameră", "Camera", "Cámara" },
        ["f.started"] = new[] { "Început", "Started", "Inicio" },
        ["f.finished"] = new[] { "Terminat", "Finished", "Fin" },
        ["f.duration"] = new[] { "Durată", "Duration", "Duración" },
        ["f.verification"] = new[] { "Verificare", "Verification", "Verificación" },
        ["f.copies"] = new[] { "Copii în acest transfer", "Copies in this transfer", "Copias en esta transferencia" },
        ["f.mhl"] = new[] { "Fișier MHL", "MHL file", "Archivo MHL" },
        ["f.csv"] = new[] { "Listă completă (CSV)", "Full list (CSV)", "Lista completa (CSV)" },
        ["f.notes"] = new[] { "Note", "Notes", "Notas" },
        ["f.job"] = new[] { "ID job (suport)", "Job ID (support)", "ID de trabajo (soporte)" },
        ["s.confirmed"] = new[] { "Fișiere confirmate", "Files confirmed", "Archivos confirmados" },
        ["s.bytes"] = new[] { "Date confirmate", "Data confirmed", "Datos confirmados" },
        ["s.retried"] = new[] { "Reușite la reîncercare", "Succeeded on retry", "Correctos al reintentar" },
        ["s.failed"] = new[] { "Neconfirmate", "Not confirmed", "No confirmados" },
        ["s.skipped"] = new[] { "Sărite", "Skipped", "Omitidos" },
        ["files"] = new[] { "Fișiere", "Files", "Archivos" },
        ["files.sample"] = new[] { "Sunt afișate %d din %d fișiere: toate problemele și primele rânduri. Lista completă, cu checksum-urile întregi, e în CSV.", "Showing %d of %d files: every problem plus the first rows. The full list, with complete checksums, is in the CSV.", "Se muestran %d de %d archivos: todos los problemas y las primeras filas. La lista completa, con los checksums enteros, está en el CSV." },
        ["col.file"] = new[] { "Fișier", "File", "Archivo" },
        ["col.size"] = new[] { "Mărime", "Size", "Tamaño" },
        ["col.checksum"] = new[] { "Checksum", "Checksum", "Checksum" },
        ["col.status"] = new[] { "Status", "Status", "Estado" },
        ["cs.match"] = new[] { "sursă = copie", "source = copy", "origen = copia" },
        ["cs.differs"] = new[] { "sursă ≠ copie", "source ≠ copy", "origen ≠ copia" },
        ["st.ok"] = new[] { "Confirmat", "Confirmed", "Confirmado" },
        ["st.skip"] = new[] { "Sărit", "Skipped", "Omitido" },
        ["st.mismatch"] = new[] { "Checksum diferit", "Checksum mismatch", "Checksum distinto" },
        ["st.error"] = new[] { "Eroare", "Error", "Error" },
        ["st.retry"] = new[] { "la reîncercare", "on retry", "al reintentar" },
        ["footer.gen"] = new[] { "Generat de DataMover %@ la %@", "Generated by DataMover %@ on %@", "Generado por DataMover %@ el %@" },
        ["footer.page"] = new[] { "Pagina %d din %d", "Page %d of %d", "Página %d de %d" },
        ["footer.basis"] = new[] { "Verdictul și cifrele provin din motorul de verificare DataMover pentru această destinație.", "The verdict and figures come from the DataMover verification engine for this destination.", "El veredicto y las cifras proceden del motor de verificación de DataMover para este destino." },
    };

    public const string Css = """
@page { size: A4; margin: 14mm 14mm 16mm; }
* { box-sizing: border-box; }
body { margin: 0; background: #F4F5F7; color: #1A1D22; font: 13px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; }
.doc { max-width: 900px; margin: 24px auto; background: #fff; padding: 36px 40px; border: 1px solid #D5D9DE; }
.mono { font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace; font-size: 12px; }
header { display: flex; justify-content: space-between; align-items: center; border-bottom: 2px solid #1A1D22; padding-bottom: 10px; }
.brand { display: flex; align-items: center; gap: 8px; font-weight: 700; letter-spacing: .02em; }
.brand svg { width: 22px; height: 22px; }
.kind { font-size: 11px; letter-spacing: .12em; text-transform: uppercase; color: #5B6470; }
header img { max-height: 40px; max-width: 160px; }
h1 { font-size: 22px; margin: 18px 0 2px; word-break: break-word; }
.dest { color: #5B6470; word-break: break-all; margin: 0 0 16px; }
.verdict { display: grid; grid-template-columns: 44px 1fr; gap: 12px; align-items: center; border: 2px solid currentColor; border-left-width: 8px; padding: 12px 16px; margin: 0 0 18px; }
.verdict .sym { font-size: 30px; font-weight: 700; text-align: center; line-height: 1; }
.verdict b { display: block; font-size: 19px; letter-spacing: .04em; }
.verdict p { margin: 2px 0 0; color: #1A1D22; }
.v-verified { color: #1F7A45; } .v-verifiedWithWarnings { color: #9A6200; border-style: dashed; } .v-failed { color: #B42318; border-style: double; border-width: 4px 4px 4px 8px; } .v-cancelled { color: #5B6470; border-style: dotted; }
dl.grid { display: grid; grid-template-columns: 190px 1fr; gap: 4px 16px; margin: 0 0 18px; }
dl.grid dt { color: #5B6470; } dl.grid dd { margin: 0; word-break: break-word; }
.summary { display: flex; flex-wrap: wrap; border: 1px solid #D5D9DE; margin: 0 0 22px; }
.summary div { flex: 1 1 150px; padding: 10px 14px; border-right: 1px solid #D5D9DE; }
.summary div:last-child { border-right: 0; }
.summary span { display: block; color: #5B6470; font-size: 11px; text-transform: uppercase; letter-spacing: .06em; }
.summary b { font-size: 16px; }
.notes { border-left: 3px solid #B8691F; padding: 6px 12px; white-space: pre-wrap; margin: 0 0 18px; }
h2 { font-size: 15px; margin: 0 0 6px; }
.sample { color: #5B6470; margin: 0 0 8px; }
table { width: 100%; border-collapse: collapse; }
thead { display: table-header-group; }
th { text-align: left; font-size: 11px; text-transform: uppercase; letter-spacing: .06em; color: #5B6470; border-bottom: 1.5px solid #1A1D22; padding: 6px 6px; }
td { border-bottom: 1px solid #E3E6EA; padding: 6px 6px; vertical-align: top; }
tr { break-inside: avoid; page-break-inside: avoid; }
td.file { word-break: break-all; }
td.num { text-align: right; white-space: nowrap; }
td .sub { color: #5B6470; font-size: 11px; }
td .err { color: #B42318; font-size: 12px; }
.st { white-space: nowrap; font-weight: 600; }
.k-ok { color: #1F7A45; } .k-warn { color: #9A6200; } .k-fail { color: #B42318; } .k-skip { color: #5B6470; }
footer { margin-top: 22px; padding-top: 10px; border-top: 1px solid #D5D9DE; color: #5B6470; font-size: 11px; }
@media print { body { background: #fff; } .doc { margin: 0; padding: 0; border: 0; max-width: none; } }
@media (max-width: 640px) { .doc { padding: 20px 16px; margin: 0; } dl.grid { grid-template-columns: 1fr; } dl.grid dt { margin-top: 6px; } }
""";

    public const string MarkSvg = "<svg viewBox=\"150 150 724 724\" aria-hidden=\"true\"><path d=\"M232 512 H430 C505 512 520 392 598 392 H792 M430 512 C505 512 520 632 598 632 H792\" fill=\"none\" stroke=\"#B8691F\" stroke-width=\"72\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/><circle cx=\"430\" cy=\"512\" r=\"46\" fill=\"#1A1D22\"/></svg>";
}
