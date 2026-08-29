#!/usr/bin/env python3
"""Genereaza cele 3 ghiduri PDF (RO/EN/ES) pentru DataMover, din continutul
definit mai jos — nu mai depinde de patch-uri manuale peste PDF-uri vechi.
Ruleaza cu: pip install reportlab pillow && python3 generate_guides.py

[REDESENAT 2026-08-29] Versiunea veche era text simplu negru-pe-alb, fara
coperta, fara nicio imagine a aplicatiei reale — Cristi a cerut explicit
"aspect profesional, vizual", acelasi standard deja aplicat ghidului GDC
Plugin Manager (vezi gdc-plugin-manager-catalog-vendor/installer/generate_pdf.py,
acelasi tipar de coperta + bara de accent + footer paginat, portat aici).
Accentul dublu al brandului DataMover (vezi docs/index.html) e pastrat
identic: amber pentru "transfer/copiere", verde pentru "verificare" —
verdele ramane folosit STRICT semantic (checkmark-uri, stare verificata),
nu ca accent primar de titlu, aliniat cu Regula 16 din CLAUDE.md.
"""
import os
from PIL import Image as PILImage
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm, cm
from reportlab.lib.enums import TA_LEFT
from reportlab.lib import colors
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, ListFlowable, ListItem, Table, TableStyle,
    Image, PageBreak,
)

HERE = os.path.dirname(os.path.abspath(__file__))
IMG_DIR = os.path.join(HERE, "..", "img")
APP_VERSION = "2.7.2"

# Arial (nu Helvetica standard-14) - WinAnsiEncoding-ul fonturilor standard
# PDF nu are glyph-uri pentru diacriticele romanesti (ă/ș/ț), ies ca patrate
# goale fara font TTF embedat. Acelasi fix deja aplicat in
# gdc-plugin-manager-catalog-vendor/installer/generate_pdf.py.
pdfmetrics.registerFont(TTFont("Arial", "/System/Library/Fonts/Supplemental/Arial.ttf"))
pdfmetrics.registerFont(TTFont("Arial-Bold", "/System/Library/Fonts/Supplemental/Arial Bold.ttf"))
pdfmetrics.registerFont(TTFont("Arial-Italic", "/System/Library/Fonts/Supplemental/Arial Italic.ttf"))

ACCENT = colors.HexColor("#c97a2e")       # amber/cupru — transfer, brand primar (Regula 16)
ACCENT_LIGHT = colors.HexColor("#fbeee0")
GREEN = colors.HexColor("#2f9e5c")         # STRICT semantic — verificare reusita
INK = colors.HexColor("#1a1a1a")
INK_DARK = colors.HexColor("#14161a")
GREY = colors.HexColor("#555555")
MAX_IMG_W = 16 * cm


def styles():
    ss = getSampleStyleSheet()
    ss.add(ParagraphStyle("CoverApp", fontName="Arial-Bold", fontSize=27, textColor=colors.white, leading=31))
    ss.add(ParagraphStyle("CoverSub", fontName="Arial", fontSize=13, textColor=colors.HexColor("#f2cfa8"), spaceBefore=6))
    ss.add(ParagraphStyle("CoverVer", fontName="Arial", fontSize=10, textColor=colors.HexColor("#c7cbd1"), spaceBefore=4))
    ss.add(ParagraphStyle("GTitle", parent=ss["Title"], fontName="Arial-Bold", fontSize=22, textColor=INK, spaceAfter=4, alignment=TA_LEFT))
    ss.add(ParagraphStyle("GSubtitle", parent=ss["Normal"], fontName="Arial", fontSize=11, textColor=GREY, spaceAfter=2))
    ss.add(ParagraphStyle("GNote", parent=ss["Normal"], fontSize=9, textColor=GREY, spaceAfter=18, fontName="Arial-Italic"))
    ss.add(ParagraphStyle("H1", parent=ss["Heading1"], fontName="Arial-Bold", fontSize=15, textColor=ACCENT, spaceBefore=18, spaceAfter=8))
    ss.add(ParagraphStyle("H2", parent=ss["Heading2"], fontName="Arial-Bold", fontSize=12, spaceBefore=12, spaceAfter=6))
    ss.add(ParagraphStyle("Body", parent=ss["Normal"], fontName="Arial", fontSize=10.2, leading=14.5, spaceAfter=6))
    ss.add(ParagraphStyle("GBullet", parent=ss["Normal"], fontName="Arial", fontSize=10.2, leading=14.5))
    ss.add(ParagraphStyle("Caption", fontName="Arial-Italic", fontSize=8.5, textColor=GREY, spaceBefore=3, spaceAfter=10, alignment=1))
    ss.add(ParagraphStyle("Mono", parent=ss["Normal"], fontName="Courier", fontSize=9.5, textColor=colors.HexColor("#1a1a1a"),
                           backColor=colors.HexColor("#f2f2f2"), leftIndent=6, spaceBefore=4, spaceAfter=8))
    return ss


def screenshot(ss, filename, caption_text):
    """Sare peste discret daca fisierul lipseste local — ghidul tot se
    genereaza, doar fara acea imagine (vezi acelasi tipar in GDCPluginManager)."""
    path = os.path.join(IMG_DIR, filename)
    if not os.path.exists(path):
        return []
    with PILImage.open(path) as im:
        w, h = im.size
    target_w = min(MAX_IMG_W, w / 2)  # capturi retina ~2x — evita supra-scalare
    scaled_h = target_w * h / w
    img = Image(path, width=target_w, height=scaled_h)
    img.hAlign = "CENTER"
    return [img, Paragraph(caption_text, ss["Caption"])]


def _cover_canvas(canvas, doc):
    canvas.saveState()
    w, h = A4
    band_h = 8.5 * cm
    canvas.setFillColor(INK_DARK)
    canvas.rect(0, h - band_h, w, band_h, fill=1, stroke=0)
    canvas.setFillColor(ACCENT)
    canvas.rect(0, h - band_h - 0.18 * cm, w, 0.18 * cm, fill=1, stroke=0)
    canvas.restoreState()


def _content_canvas(canvas, doc, footer_text):
    canvas.saveState()
    w, h = A4
    canvas.setFillColor(ACCENT)
    canvas.rect(0, h - 0.4 * cm, w, 0.4 * cm, fill=1, stroke=0)
    canvas.setFont("Arial", 8)
    canvas.setFillColor(GREY)
    canvas.drawString(2 * cm, 1.2 * cm, footer_text)
    canvas.drawRightString(w - 2 * cm, 1.2 * cm, f"{canvas.getPageNumber()}")
    canvas.restoreState()


def build(lang, out_path, content):
    ss = styles()
    doc = SimpleDocTemplate(out_path, pagesize=A4,
                             leftMargin=22 * mm, rightMargin=22 * mm, topMargin=20 * mm, bottomMargin=18 * mm,
                             title=content["title"], author="Cristi Gordas")
    flow = [
        Spacer(1, 3.4 * cm),
        Paragraph("DataMover", ss["CoverApp"]),
        Paragraph(content["cover_subtitle"], ss["CoverSub"]),
        Spacer(1, 3.2 * cm),
        Paragraph(f"{content['cover_version_label']} {APP_VERSION}", ss["CoverVer"]),
        Paragraph(content["cover_lang_label"], ss["CoverVer"]),
        PageBreak(),
        Paragraph(content["title"], ss["GTitle"]),
        Paragraph(content["subtitle"], ss["GSubtitle"]),
        Paragraph(content["note"], ss["GNote"]),
    ]

    for section in content["sections"]:
        flow.append(Paragraph(section["h"], ss["H1"]))
        for block in section["blocks"]:
            kind = block[0]
            if kind == "p":
                flow.append(Paragraph(block[1], ss["Body"]))
            elif kind == "h2":
                flow.append(Paragraph(block[1], ss["H2"]))
            elif kind == "ul":
                items = [ListItem(Paragraph(t, ss["GBullet"]), leftIndent=12, bulletColor=ACCENT) for t in block[1]]
                flow.append(ListFlowable(items, bulletType="bullet", start="-", leftIndent=14, spaceAfter=8))
            elif kind == "code":
                flow.append(Paragraph(block[1], ss["Mono"]))
            elif kind == "img":
                flow.extend(screenshot(ss, block[1][0], block[1][1]))
            elif kind == "table":
                label_style = ParagraphStyle("TLabel", parent=ss["Body"], textColor=ACCENT, fontName="Arial-Bold", spaceAfter=0)
                cell_style = ParagraphStyle("TCell", parent=ss["Body"], spaceAfter=0)
                rows = [[Paragraph(label, label_style), Paragraph(text, cell_style)] for label, text in block[1]]
                avail_width = doc.width
                t = Table(rows, colWidths=[38 * mm, avail_width - 38 * mm])
                t.setStyle(TableStyle([
                    ("VALIGN", (0, 0), (-1, -1), "TOP"),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
                    ("TOPPADDING", (0, 0), (-1, -1), 4),
                    ("LEFTPADDING", (0, 0), (-1, -1), 0),
                    ("RIGHTPADDING", (0, 0), (-1, -1), 4),
                    ("LINEBELOW", (0, 0), (-1, -2), 0.4, colors.HexColor("#dddddd")),
                ]))
                flow.append(t)
                flow.append(Spacer(1, 8))

    doc.build(flow,
               onFirstPage=lambda c, d: _cover_canvas(c, d),
               onLaterPages=lambda c, d: _content_canvas(c, d, content["footer"]))
    print(f"OK: {out_path}")


# ---------------------------------------------------------------------------
# RO
# ---------------------------------------------------------------------------
RO = {
    "cover_subtitle": "Ghid complet de utilizare",
    "cover_version_label": "Versiunea",
    "cover_lang_label": "Română",
    "footer": "DataMover — Ghid de utilizare",
    "title": "DataMover — Ghid de utilizare",
    "subtitle": "Instalare, activare, functionalitati, depanare — de Cristi Gordas",
    "note": "Ghid actualizat pentru UI-ul nativ macOS (SwiftUI) si aplicatia Windows (WPF).",
    "sections": [
        {"h": "1. Ce este DataMover", "blocks": [
            ("p", "DataMover e o aplicatie de offload verificat pentru echipele de productie video — "
                  "copiaza fisiere de pe carduri video catre mai multe destinatii simultan (drive-uri "
                  "externe, NAS, foldere locale), cu verificare de integritate la fiecare pas."),
            ("img", ("mac-ui-main.png", "Fereastra principala (Mac) — surse, discuri detectate, destinatii")),
            ("h2", "Ce poate face"),
            ("ul", [
                "Copiere simultana catre oricate destinatii — toate se completeaza in paralel, nu pe rand.",
                "Verificare integritate la alegere: MD5, SHA-1, SHA-256, SHA-512, sau doar dimensiune.",
                "Rapoarte CSV + PDF (in tabel), cu status per fisier (OK / Nepotrivire / Eroare) si timestamp exact.",
                "Reluare automata la erori (checkpoint) — continua de unde a ramas, nu ia totul de la capat.",
                "Istoric copieri — vezi toate transferurile anterioare, poti sterge o intrare sau tot istoricul.",
                "Panou de Dependinte <font color='#c0392b'>&#9679;</font>/<font color='#2f9e5c'>&#9679;</font> (Windows) — verifica automat componentele de sistem necesare rapoartelor PDF.",
                "Denumire automata a folderelor: Data_Proiect_Card.",
                "Ghid de utilizare integrat direct in aplicatie (Mac).",
                "Tema deschisa/intunecata la alegere, interfata completa in romana, engleza si spaniola.",
            ]),
            ("p", "Nota: codul sursa e disponibil pe GitHub sub licenta MIT — dar aplicatia compilata are "
                  "nevoie de un cod de activare, legat de calculatorul tau, ca sa poata porni dupa proba "
                  "gratuita. Vezi sectiunea 3."),
        ]},
        {"h": "2. Instalare", "blocks": [
            ("h2", "macOS"),
            ("p", "Descarca DataMover-Mac.zip din pagina de Releases, dezarhiveaza si muta DataMover.app "
                  "in /Applications (drag & drop)."),
            ("p", "La prima deschidere, macOS poate avertiza ca aplicatia e de la un dezvoltator "
                  "neidentificat — normal pentru aplicatii semnate ad-hoc, fara cont Apple Developer platit. "
                  "Click-dreapta pe aplicatie, apoi Open, si confirma. Se face o singura data."),
            ("h2", "Windows"),
            ("p", "Descarca DataMover-WPF-Windows.zip (clientul nou, recomandat) sau DataMover-Windows.zip "
                  "(clientul clasic), dezarhiveaza si ruleaza installer-ul — Adaugă/Elimină Programe "
                  "il dezinstaleaza curat, dupa nevoie."),
        ]},
        {"h": "3. Activare", "blocks": [
            ("p", "Ai 7 zile de proba gratuita de la prima lansare, cu toate functiile active. Dupa proba, "
                  "aplicatia are nevoie de un cod de activare personal ca sa continue sa porneasca."),
            ("table", [
                ("Pasul 1", "Apasa „Activeaza licenta” din bara de sus a aplicatiei — oricand, in timpul probei sau dupa."),
                ("Pasul 2", "In fereastra de activare vezi ID-ul calculatorului tau (buton Copiaza langa el) si un buton verde de WhatsApp — apasa-l ca sa ma contactezi direct, cu ID-ul copiat, pentru donatie (activare)."),
                ("Pasul 3", "Iti trimit inapoi codul de activare personal, legat exact de calculatorul tau — nu va functiona pe alt calculator, chiar daca il distribui."),
                ("Pasul 4", "Introduci codul primit in campul „Cod licenta” si apesi Activeaza. Aplicatia porneste normal de fiecare data, fara sa mai ceara codul din nou."),
            ]),
            ("p", "Cei 23 € sunt o donatie — ma ajuta sa acopar costurile de "
                  "dezvoltare si sa continui sa intretin si imbunatatesc aplicatia."),
            ("p", "Nota: daca schimbi calculatorul, ai nevoie de un cod nou — scrie-mi din nou pe WhatsApp."),
        ]},
        {"h": "4. Functionalitatile, explicate", "blocks": [
            ("h2", "Verificare integritate"),
            ("p", "Alegi algoritmul potrivit nevoii tale: MD5 si SHA-1 sunt rapide, SHA-256 si SHA-512 sunt "
                  "mai riguroase (utile pentru arhivare pe termen lung). Optiunea „doar dimensiune” e "
                  "cea mai rapida, pentru situatii unde viteza conteaza mai mult decat certitudinea absoluta."),
            ("img", ("mac-ui-settings.png", "Setari de copiere — model de verificare, excluderi, buffer/RAM")),
            ("h2", "Reluare automata (checkpoint)"),
            ("p", "Daca un transfer e intrerupt (card scos, eroare de retea la NAS etc.), DataMover reia "
                  "exact de unde a ramas la urmatoarea incercare — nu retrimite fisierele deja copiate si "
                  "verificate cu succes."),
            ("h2", "Istoric copieri"),
            ("p", "Butonul cu ceas din footer deschide o fereastra cu toate copierile anterioare: data, "
                  "numele folderului, sursa si destinatia, cate fisiere OK/sarite/esuate. Poti sterge o "
                  "intrare anume sau tot istoricul."),
            ("img", ("mac-ui-history.png", "Istoricul copierilor, cu deschidere directa a sursei/destinatiei")),
            ("h2", "<font color=\"#2f9e5c\">●</font> Panoul de Dependinte (Windows)"),
            ("p", "Butonul „Profil” din footer arata o lista de componente de sistem verificate automat, "
                  "fiecare cu un punct <font color=\"#2f9e5c\">verde</font> (prezenta, totul e in regula) sau "
                  "<font color=\"#c0392b\">rosu</font> (lipseste). Daca vezi rosu (de exemplu Visual C++ "
                  "Redistributable, necesar rapoartelor PDF), apasa butonul „Instaleaza” de langa el — se "
                  "deschide direct pagina oficiala de descarcare a componentei lipsa. Dupa ce o instalezi, "
                  "apasa „Reverifica” din acelasi panou — nu trebuie sa repornesti aplicatia."),
            ("h2", "Rapoarte CSV + PDF"),
            ("p", "Fiecare transfer genereaza un raport cu status per fisier (OK / Nepotrivire / Eroare), "
                  "util pentru evidenta si pentru dovada ca materialul a ajuns intact la destinatie."),
        ]},
        {"h": "5. Probleme frecvente si solutii", "blocks": [
            ("h2", "macOS spune ca aplicatia e „deteriorata”"),
            ("p", "Normal pentru aplicatii semnate ad-hoc — click-dreapta pe aplicatie, Open, confirma. "
                  "Daca tot nu porneste, ruleaza in Terminal:"),
            ("code", "xattr -cr /Applications/DataMover.app"),
            ("h2", "Codul de activare nu functioneaza"),
            ("p", "Verifica sa-l fi copiat complet, fara spatii la inceput/sfarsit. Un cod e legat de UN "
                  "singur calculator — daca ai schimbat masina, ai nevoie de un cod nou."),
            ("h2", "Raportul PDF lipseste (Windows)"),
            ("p", "Verifica indicatorul din panoul „Profil” (sectiunea 4 de mai sus) — daca Visual C++ "
                  "Redistributable arata rosu, instaleaza-l de acolo, apoi reincearca transferul. CSV-ul "
                  "se genereaza oricum, indiferent de acest indicator."),
            ("h2", "Transferul se opreste la jumatate"),
            ("p", "Verifica conexiunea la destinatie (NAS/retea) — DataMover reia automat de unde a ramas "
                  "la urmatoarea incercare, daca ai lasat activata reluarea din setari."),
        ]},
        {"h": "6. Licenta", "blocks": [
            ("p", "Codul sursa al DataMover e licentiat MIT — disponibil integral pe GitHub. Utilizarea "
                  "aplicatiei compilate, dupa proba gratuita de 7 zile, necesita un cod de activare "
                  "personal (donatie de 23 €), legat de un singur calculator."),
        ]},
    ],
}

# ---------------------------------------------------------------------------
# EN
# ---------------------------------------------------------------------------
EN = {
    "cover_subtitle": "Complete user guide",
    "cover_version_label": "Version",
    "cover_lang_label": "English",
    "footer": "DataMover — User Guide",
    "title": "DataMover — User Guide",
    "subtitle": "Install, activate, features, troubleshooting — by Cristi Gordas",
    "note": "Guide updated for the native macOS UI (SwiftUI) and the Windows app (WPF).",
    "sections": [
        {"h": "1. What is DataMover", "blocks": [
            ("p", "DataMover is a verified offload app for video production teams — it copies files from "
                  "video cards to multiple destinations at once (external drives, NAS, local folders), "
                  "with integrity verification at every step."),
            ("img", ("mac-ui-main.png", "Main window (Mac) — sources, detected drives, destinations")),
            ("h2", "What it can do"),
            ("ul", [
                "Simultaneous copy to any number of destinations — all complete in parallel, not one by one.",
                "Integrity verification, your choice: MD5, SHA-1, SHA-256, SHA-512, or size-only.",
                "CSV + PDF reports (table layout), with per-file status (OK / Mismatch / Error) and exact timestamp.",
                "Automatic resume on errors (checkpoint) — continues from where it left off, no full restarts.",
                "Copy history — see every past transfer, delete one entry or the whole history.",
                "Dependency panel <font color='#c0392b'>&#9679;</font>/<font color='#2f9e5c'>&#9679;</font> (Windows) — automatically checks system components needed by PDF reports.",
                "Automatic folder naming: Date_Project_Card.",
                "Built-in user guide inside the app (Mac).",
                "Light/Dark theme, your choice — full interface in Romanian, English and Spanish.",
            ]),
            ("p", "Note: the source code is available on GitHub under the MIT license — but the compiled "
                  "app needs an activation code, tied to your computer, to keep running after the free "
                  "trial. See section 3."),
        ]},
        {"h": "2. Installation", "blocks": [
            ("h2", "macOS"),
            ("p", "Download DataMover-Mac.zip from the Releases page, extract it and drag DataMover.app "
                  "into /Applications."),
            ("p", "On first launch, macOS may warn that the app is from an unidentified developer — normal "
                  "for ad-hoc signed apps without a paid Apple Developer account. Right-click the app, "
                  "choose Open, and confirm. One-time only."),
            ("h2", "Windows"),
            ("p", "Download DataMover-WPF-Windows.zip (new client, recommended) or DataMover-Windows.zip "
                  "(classic client), extract it and run the installer — Add/Remove Programs uninstalls it "
                  "cleanly when needed."),
        ]},
        {"h": "3. Activation", "blocks": [
            ("p", "You get a 7-day free trial from first launch, with every feature unlocked. After the "
                  "trial, the app needs a personal activation code to keep starting."),
            ("table", [
                ("Step 1", "Tap “Activate license” in the app's top bar — anytime, during the trial or after."),
                ("Step 2", "The activation window shows your computer's ID (with a Copy button) and a green WhatsApp button — tap it to contact me directly, with the ID copied, to purchase."),
                ("Step 3", "I send you back your personal activation code, tied exactly to your computer — it won't work on another machine, even if shared."),
                ("Step 4", "Paste the code you received into the “License code” field and tap Activate. The app now starts normally every time, without asking for the code again."),
            ]),
            ("p", "The 23 € is a donation, not a list price — it helps me cover development costs and "
                  "keep maintaining and improving the app."),
            ("p", "Note: if you switch computers, you'll need a new code — message me again on WhatsApp."),
        ]},
        {"h": "4. Features, explained", "blocks": [
            ("h2", "Integrity verification"),
            ("p", "Pick the algorithm that fits your needs: MD5 and SHA-1 are fast, SHA-256 and SHA-512 "
                  "are more rigorous (useful for long-term archiving). “Size only” is the fastest "
                  "option, for cases where speed matters more than absolute certainty."),
            ("img", ("mac-ui-settings.png", "Copy settings — verification model, exclusions, buffer/RAM")),
            ("h2", "Automatic resume (checkpoint)"),
            ("p", "If a transfer is interrupted (card removed, network error to a NAS, etc.), DataMover "
                  "picks up exactly where it left off on the next attempt — it doesn't re-send files "
                  "already copied and successfully verified."),
            ("h2", "Copy history"),
            ("p", "The clock button in the footer opens a window with every past copy job: date, folder "
                  "name, source and destination, and OK/skipped/failed counts. You can delete a single "
                  "entry or the entire history."),
            ("img", ("mac-ui-history.png", "Copy history, with direct source/destination opening")),
            ("h2", "<font color=\"#2f9e5c\">●</font> Dependency panel (Windows)"),
            ("p", "The “Profile” button in the footer shows a list of automatically checked system "
                  "components, each with a <font color=\"#2f9e5c\">green</font> dot (present, all good) or a "
                  "<font color=\"#c0392b\">red</font> one (missing). If you see red (for example the Visual "
                  "C++ Redistributable, needed by PDF reports), tap the “Install” button next to it — it "
                  "opens the official download page for that missing component directly. After installing "
                  "it, tap “Recheck” in the same panel — no need to restart the app."),
            ("h2", "CSV + PDF reports"),
            ("p", "Every transfer generates a report with per-file status (OK / Mismatch / Error), useful "
                  "for record-keeping and as proof the material arrived intact at its destination."),
        ]},
        {"h": "5. Common issues and fixes", "blocks": [
            ("h2", "macOS says the app is “damaged”"),
            ("p", "Normal for ad-hoc signed apps — right-click the app, choose Open, and confirm. If it "
                  "still won't launch, run this in Terminal:"),
            ("code", "xattr -cr /Applications/DataMover.app"),
            ("h2", "The activation code doesn't work"),
            ("p", "Check that you copied it completely, with no leading/trailing spaces. A code is tied to "
                  "ONE computer — if you switched machines, you'll need a new code."),
            ("h2", "The PDF report is missing (Windows)"),
            ("p", "Check the indicator in the “Profile” panel (section 4 above) — if the Visual C++ "
                  "Redistributable shows red, install it from there, then retry the transfer. The CSV "
                  "report is always generated regardless of this indicator."),
            ("h2", "The transfer stops halfway"),
            ("p", "Check the connection to the destination (NAS/network) — DataMover automatically resumes "
                  "from where it left off on the next attempt, if resume is enabled in settings."),
        ]},
        {"h": "6. License", "blocks": [
            ("p", "DataMover's source code is MIT licensed — fully available on GitHub. Using the compiled "
                  "app, after the 7-day free trial, requires a personal activation code (23 € "
                  "donation), tied to a single computer."),
        ]},
    ],
}

# ---------------------------------------------------------------------------
# ES
# ---------------------------------------------------------------------------
ES = {
    "cover_subtitle": "Guia completa de uso",
    "cover_version_label": "Version",
    "cover_lang_label": "Español",
    "footer": "DataMover — Guia de uso",
    "title": "DataMover — Guia de uso",
    "subtitle": "Instalacion, activacion, funciones, solucion de problemas — por Cristi Gordas",
    "note": "Guia actualizada para la UI nativa de macOS (SwiftUI) y la app de Windows (WPF).",
    "sections": [
        {"h": "1. Que es DataMover", "blocks": [
            ("p", "DataMover es una aplicacion de offload verificado para equipos de produccion de video "
                  "— copia archivos desde tarjetas de video a varios destinos a la vez (unidades "
                  "externas, NAS, carpetas locales), con verificacion de integridad en cada paso."),
            ("img", ("mac-ui-main.png", "Ventana principal (Mac) — origenes, discos detectados, destinos")),
            ("h2", "Que puede hacer"),
            ("ul", [
                "Copia simultanea a cualquier numero de destinos — todos se completan en paralelo, no uno a uno.",
                "Verificacion de integridad, a elegir: MD5, SHA-1, SHA-256, SHA-512, o solo tamano.",
                "Informes CSV + PDF (en tabla), con estado por archivo (OK / Discrepancia / Error) y marca de tiempo exacta.",
                "Reanudacion automatica en caso de errores (checkpoint) — continua desde donde quedo, sin empezar de cero.",
                "Historial de copias — ve todas las transferencias anteriores, elimina una entrada o todo el historial.",
                "Panel de Dependencias <font color='#c0392b'>&#9679;</font>/<font color='#2f9e5c'>&#9679;</font> (Windows) — comprueba automaticamente los componentes de sistema necesarios para los informes PDF.",
                "Nombramiento automatico de carpetas: Fecha_Proyecto_Tarjeta.",
                "Guia de uso integrada directamente en la app (Mac).",
                "Tema claro/oscuro a elegir, interfaz completa en rumano, ingles y espanol.",
            ]),
            ("p", "Nota: el codigo fuente esta disponible en GitHub bajo licencia MIT — pero la app "
                  "compilada necesita un codigo de activacion, vinculado a tu ordenador, para seguir "
                  "funcionando despues de la prueba gratuita. Ver seccion 3."),
        ]},
        {"h": "2. Instalacion", "blocks": [
            ("h2", "macOS"),
            ("p", "Descarga DataMover-Mac.zip desde la pagina de Releases, extraelo y arrastra "
                  "DataMover.app a /Applications."),
            ("p", "En la primera ejecucion, macOS puede avisar que la app es de un desarrollador no "
                  "identificado — normal para apps firmadas ad-hoc, sin cuenta de Apple Developer de "
                  "pago. Clic derecho sobre la app, elige Open, y confirma. Solo una vez."),
            ("h2", "Windows"),
            ("p", "Descarga DataMover-WPF-Windows.zip (cliente nuevo, recomendado) o DataMover-Windows.zip "
                  "(cliente clasico), extraelo y ejecuta el instalador — Agregar o quitar programas lo "
                  "desinstala limpiamente cuando haga falta."),
        ]},
        {"h": "3. Activacion", "blocks": [
            ("p", "Tienes 7 dias de prueba gratuita desde el primer inicio, con todas las funciones "
                  "activas. Despues de la prueba, la app necesita un codigo de activacion personal para "
                  "seguir arrancando."),
            ("table", [
                ("Paso 1", "Pulsa “Activar licencia” en la barra superior de la app — en cualquier momento, durante la prueba o despues."),
                ("Paso 2", "La ventana de activacion muestra el ID de tu ordenador (con boton Copiar) y un boton verde de WhatsApp — pulsalo para contactarme directamente, con el ID copiado, para comprar."),
                ("Paso 3", "Te envio de vuelta tu codigo de activacion personal, vinculado exactamente a tu ordenador — no funcionara en otro equipo, aunque lo compartas."),
                ("Paso 4", "Introduce el codigo recibido en el campo “Codigo de licencia” y pulsa Activar. La app arranca normalmente cada vez, sin volver a pedir el codigo."),
            ]),
            ("p", "Los 23 € son una donacion, no un precio de lista — me ayudan a cubrir los costes de "
                  "desarrollo y a seguir manteniendo y mejorando la aplicacion."),
            ("p", "Nota: si cambias de ordenador, necesitaras un codigo nuevo — escribeme de nuevo por "
                  "WhatsApp."),
        ]},
        {"h": "4. Funciones, explicadas", "blocks": [
            ("h2", "Verificacion de integridad"),
            ("p", "Elige el algoritmo segun tu necesidad: MD5 y SHA-1 son rapidos, SHA-256 y SHA-512 son "
                  "mas rigurosos (utiles para archivo a largo plazo). “Solo tamano” es la opcion "
                  "mas rapida, para cuando la velocidad importa mas que la certeza absoluta."),
            ("img", ("mac-ui-settings.png", "Ajustes de copia — modelo de verificacion, exclusiones, buffer/RAM")),
            ("h2", "Reanudacion automatica (checkpoint)"),
            ("p", "Si una transferencia se interrumpe (tarjeta extraida, error de red en un NAS, etc.), "
                  "DataMover continua exactamente desde donde quedo en el siguiente intento — no vuelve a "
                  "enviar archivos ya copiados y verificados correctamente."),
            ("h2", "Historial de copias"),
            ("p", "El boton de reloj en el pie abre una ventana con todas las copias anteriores: fecha, "
                  "nombre de la carpeta, origen y destino, y los recuentos OK/omitidos/fallidos. Puedes "
                  "eliminar una entrada especifica o todo el historial."),
            ("img", ("mac-ui-history.png", "Historial de copias, con apertura directa de origen/destino")),
            ("h2", "<font color=\"#2f9e5c\">●</font> Panel de Dependencias (Windows)"),
            ("p", "El boton “Perfil” del pie muestra una lista de componentes de sistema comprobados "
                  "automaticamente, cada uno con un punto <font color=\"#2f9e5c\">verde</font> (presente, "
                  "todo correcto) o <font color=\"#c0392b\">rojo</font> (falta). Si ves rojo (por ejemplo "
                  "Visual C++ Redistributable, necesario para los informes PDF), pulsa el boton “Instalar” "
                  "de al lado — se abre directamente la pagina oficial de descarga del componente que "
                  "falta. Despues de instalarlo, pulsa “Volver a comprobar” en el mismo panel — no hace "
                  "falta reiniciar la aplicacion."),
            ("h2", "Informes CSV + PDF"),
            ("p", "Cada transferencia genera un informe con el estado por archivo (OK / Discrepancia / "
                  "Error), util para llevar registro y como prueba de que el material llego intacto a su "
                  "destino."),
        ]},
        {"h": "5. Problemas frecuentes y soluciones", "blocks": [
            ("h2", "macOS dice que la app esta “danada”"),
            ("p", "Normal para apps firmadas ad-hoc — clic derecho sobre la app, Open, confirma. Si aun "
                  "asi no abre, ejecuta esto en Terminal:"),
            ("code", "xattr -cr /Applications/DataMover.app"),
            ("h2", "El codigo de activacion no funciona"),
            ("p", "Comprueba que lo copiaste completo, sin espacios al principio o al final. Un codigo "
                  "esta vinculado a UN solo ordenador — si cambiaste de equipo, necesitas un codigo nuevo."),
            ("h2", "Falta el informe PDF (Windows)"),
            ("p", "Comprueba el indicador en el panel “Perfil” (seccion 4 arriba) — si Visual C++ "
                  "Redistributable aparece en rojo, instalalo desde alli y vuelve a intentar la "
                  "transferencia. El CSV siempre se genera, sin importar este indicador."),
            ("h2", "La transferencia se detiene a la mitad"),
            ("p", "Comprueba la conexion al destino (NAS/red) — DataMover reanuda automaticamente desde "
                  "donde quedo en el siguiente intento, si dejaste activada la reanudacion en los "
                  "ajustes."),
        ]},
        {"h": "6. Licencia", "blocks": [
            ("p", "El codigo fuente de DataMover tiene licencia MIT — disponible integramente en GitHub. "
                  "El uso de la app compilada, tras la prueba gratuita de 7 dias, requiere un codigo de "
                  "activacion personal (donacion de 23 €), vinculado a un unico ordenador."),
        ]},
    ],
}


if __name__ == "__main__":
    build("ro", os.path.join(HERE, "DataMover_Ghid_RO.pdf"), RO)
    build("en", os.path.join(HERE, "DataMover_Guide_EN.pdf"), EN)
    build("es", os.path.join(HERE, "DataMover_Guia_ES.pdf"), ES)
