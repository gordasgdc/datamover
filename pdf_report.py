"""
pdf_report.py
-------------
Genereaza un raport PDF profesional pentru fiecare offload: antet cu
detalii despre destinatie/folder/data, un tabel cu toate fisierele
(status colorat), si un sumar final.

Necesita libraria "reportlab" (pip3 install reportlab).
"""

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import (
    SimpleDocTemplate, Table, TableStyle, Paragraph, Spacer
)


STATUS_COLORS = {
    "OK": colors.HexColor("#1a7a34"),
    "SARIT (identic)": colors.HexColor("#7a6a1a"),
    "NEPOTRIVIRE": colors.HexColor("#b8860b"),
    "EROARE": colors.HexColor("#b02a2a"),
}


def _format_size(num_bytes):
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if num_bytes < 1024.0:
            return f"{num_bytes:.1f} {unit}"
        num_bytes /= 1024.0
    return f"{num_bytes:.1f} PB"


def generate_pdf_report(output_path, destination, folder_name, rows,
                         started_at, finished_at, ok_count, skip_count,
                         fail_count, cancelled=False, verification_label=""):
    styles = getSampleStyleSheet()
    title_style = ParagraphStyle(
        "TitleDataMover", parent=styles["Title"], fontSize=18, spaceAfter=4
    )
    meta_style = ParagraphStyle(
        "MetaDataMover", parent=styles["Normal"], fontSize=9, textColor=colors.HexColor("#444444")
    )
    small_style = ParagraphStyle(
        "SmallDataMover", parent=styles["Normal"], fontSize=8
    )

    doc = SimpleDocTemplate(
        output_path, pagesize=A4,
        leftMargin=18 * mm, rightMargin=18 * mm,
        topMargin=16 * mm, bottomMargin=16 * mm,
        title="Raport offload DataMover",
    )

    elements = []
    elements.append(Paragraph("Raport offload &ndash; DataMover", title_style))

    status_text = "ANULAT DE UTILIZATOR" if cancelled else "FINALIZAT"
    duration = ""
    if started_at and finished_at:
        secs = (finished_at - started_at).total_seconds()
        duration = f"{secs:.1f} secunde"

    meta_lines = [
        f"<b>Destinatie:</b> {destination}",
        f"<b>Folder creat:</b> {folder_name}",
        f"<b>Model de verificare:</b> {verification_label or '-'}",
        f"<b>Inceput:</b> {started_at.strftime('%Y-%m-%d %H:%M:%S') if started_at else '-'}",
        f"<b>Finalizat:</b> {finished_at.strftime('%Y-%m-%d %H:%M:%S') if finished_at else '-'}",
        f"<b>Durata:</b> {duration}",
        f"<b>Status sesiune:</b> {status_text}",
    ]
    for line in meta_lines:
        elements.append(Paragraph(line, meta_style))
    elements.append(Spacer(1, 8))

    total = len(rows)
    summary = (
        f"<b>Total fisiere:</b> {total} &nbsp;&nbsp; "
        f"<b>OK:</b> {ok_count} &nbsp;&nbsp; "
        f"<b>Sarite:</b> {skip_count} &nbsp;&nbsp; "
        f"<b>Probleme:</b> {fail_count}"
    )
    elements.append(Paragraph(summary, styles["Heading4"]))
    elements.append(Spacer(1, 10))

    # tabel cu fisiere
    table_data = [["Fisier", "Marime", "Status", "Verificare sursa (prescurtat)"]]
    for row in rows:
        verif_raw = row.get("verificare_sursa") or ""
        verif_short = verif_raw[:20]
        table_data.append([
            Paragraph(row["fisier"], small_style),
            _format_size(row.get("marime_bytes", 0) or 0),
            row["status"],
            verif_short,
        ])

    col_widths = [70 * mm, 22 * mm, 28 * mm, 45 * mm]
    table = Table(table_data, colWidths=col_widths, repeatRows=1)

    style_commands = [
        ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#2b2b2b")),
        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
        ("FONTSIZE", (0, 0), (-1, 0), 9),
        ("FONTSIZE", (0, 1), (-1, -1), 8),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#cccccc")),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#f5f5f5")]),
    ]
    for i, row in enumerate(rows, start=1):
        color = STATUS_COLORS.get(row["status"], colors.black)
        style_commands.append(("TEXTCOLOR", (2, i), (2, i), color))

    table.setStyle(TableStyle(style_commands))
    elements.append(table)

    doc.build(elements)
