#!/usr/bin/env python3
"""Genereaza cele 3 ghiduri PDF (RO/EN/ES) pentru DataMover, din continutul
definit mai jos — nu mai depinde de patch-uri manuale peste PDF-uri vechi.
Ruleaza cu: pip install reportlab && python3 generate_guides.py
"""
import os
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import mm
from reportlab.lib.enums import TA_LEFT
from reportlab.lib import colors
from reportlab.platypus import (
    SimpleDocTemplate, Paragraph, Spacer, ListFlowable, ListItem, Table, TableStyle
)

HERE = os.path.dirname(os.path.abspath(__file__))

GREEN = colors.HexColor("#2f9e5c")
GREY = colors.HexColor("#555555")

def styles():
    ss = getSampleStyleSheet()
    ss.add(ParagraphStyle("GTitle", parent=ss["Title"], fontSize=24, spaceAfter=4, alignment=TA_LEFT))
    ss.add(ParagraphStyle("GSubtitle", parent=ss["Normal"], fontSize=11, textColor=GREY, spaceAfter=2))
    ss.add(ParagraphStyle("GNote", parent=ss["Normal"], fontSize=9, textColor=GREY, spaceAfter=18, fontName="Helvetica-Oblique"))
    ss.add(ParagraphStyle("H1", parent=ss["Heading1"], fontSize=15, textColor=GREEN, spaceBefore=18, spaceAfter=8))
    ss.add(ParagraphStyle("H2", parent=ss["Heading2"], fontSize=12, spaceBefore=12, spaceAfter=6))
    ss.add(ParagraphStyle("Body", parent=ss["Normal"], fontSize=10.2, leading=14.5, spaceAfter=6))
    ss.add(ParagraphStyle("GBullet", parent=ss["Normal"], fontSize=10.2, leading=14.5))
    ss.add(ParagraphStyle("Mono", parent=ss["Normal"], fontName="Courier", fontSize=9.5, textColor=colors.HexColor("#1a1a1a"),
                           backColor=colors.HexColor("#f2f2f2"), leftIndent=6, spaceBefore=4, spaceAfter=8))
    return ss


def build(lang, out_path, content):
    ss = styles()
    doc = SimpleDocTemplate(out_path, pagesize=A4,
                             leftMargin=22*mm, rightMargin=22*mm, topMargin=20*mm, bottomMargin=18*mm,
                             title=content["title"], author="Cristi Gordas")
    story = []
    story.append(Paragraph(content["title"], ss["GTitle"]))
    story.append(Paragraph(content["subtitle"], ss["GSubtitle"]))
    story.append(Paragraph(content["note"], ss["GNote"]))

    for section in content["sections"]:
        story.append(Paragraph(section["h"], ss["H1"]))
        for block in section["blocks"]:
            kind = block[0]
            if kind == "p":
                story.append(Paragraph(block[1], ss["Body"]))
            elif kind == "h2":
                story.append(Paragraph(block[1], ss["H2"]))
            elif kind == "ul":
                items = [ListItem(Paragraph(t, ss["GBullet"]), leftIndent=12, bulletColor=GREEN) for t in block[1]]
                story.append(ListFlowable(items, bulletType="bullet", start="-", leftIndent=14, spaceAfter=8))
            elif kind == "code":
                story.append(Paragraph(block[1], ss["Mono"]))
            elif kind == "table":
                label_style = ParagraphStyle("TLabel", parent=ss["Body"], textColor=GREEN, fontName="Helvetica-Bold", spaceAfter=0)
                cell_style = ParagraphStyle("TCell", parent=ss["Body"], spaceAfter=0)
                rows = [[Paragraph(label, label_style), Paragraph(text, cell_style)] for label, text in block[1]]
                avail_width = doc.width
                t = Table(rows, colWidths=[38*mm, avail_width - 38*mm])
                t.setStyle(TableStyle([
                    ("VALIGN", (0, 0), (-1, -1), "TOP"),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 8),
                    ("TOPPADDING", (0, 0), (-1, -1), 4),
                    ("LEFTPADDING", (0, 0), (-1, -1), 0),
                    ("RIGHTPADDING", (0, 0), (-1, -1), 4),
                    ("LINEBELOW", (0, 0), (-1, -2), 0.4, colors.HexColor("#dddddd")),
                ]))
                story.append(t)
                story.append(Spacer(1, 8))

    doc.build(story)
    print(f"OK: {out_path}")


# ---------------------------------------------------------------------------
# RO
# ---------------------------------------------------------------------------
RO = {
    "title": "DataMover — Ghid de utilizare",
    "subtitle": "Instalare, activare, functionalitati, depanare — de Cristi Gordas",
    "note": "Ghid actualizat pentru UI-ul nativ macOS (SwiftUI) si aplicatia Windows.",
    "sections": [
        {"h": "1. Ce este DataMover", "blocks": [
            ("p", "DataMover e o aplicatie de offload verificat pentru echipele de productie video — "
                  "copiaza fisiere de pe carduri video catre mai multe destinatii simultan (drive-uri "
                  "externe, NAS, foldere locale), cu verificare de integritate la fiecare pas."),
            ("h2", "Ce poate face"),
            ("ul", [
                "Copiere simultana catre oricate destinatii — toate se completeaza in paralel, nu pe rand.",
                "Verificare integritate la alegere: MD5, SHA-1, SHA-256, SHA-512, sau doar dimensiune.",
                "Rapoarte CSV + PDF (in tabel), cu status per fisier (OK / Nepotrivire / Eroare) si timestamp exact.",
                "Reluare automata la erori (checkpoint) — continua de unde a ramas, nu ia totul de la capat.",
                "Istoric copieri (Mac) — vezi toate transferurile anterioare, poti sterge o intrare sau tot istoricul.",
                "Mod Monitorizare in system tray (Windows) — detecteaza automat cardurile introduse.",
                "Denumire automata a folderelor: Data_Proiect_Card.",
                "Ghid de utilizare integrat direct in aplicatie (Mac).",
                "Tema intunecata, interfata completa in romana, engleza si spaniola.",
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
            ("p", "Descarca DataMover-Windows.zip, dezarhiveaza. Contine DataMover.exe, gata de rulat direct "
                  "— nu necesita instalare separata."),
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
            ("h2", "Reluare automata (checkpoint)"),
            ("p", "Daca un transfer e intrerupt (card scos, eroare de retea la NAS etc.), DataMover reia "
                  "exact de unde a ramas la urmatoarea incercare — nu retrimite fisierele deja copiate si "
                  "verificate cu succes."),
            ("h2", "Istoric copieri (Mac)"),
            ("p", "Butonul cu ceas din footer deschide o fereastra cu toate copierile anterioare: data, "
                  "numele folderului, sursa si destinatia, cate fisiere OK/sarite/esuate. Poti sterge o "
                  "intrare anume sau tot istoricul."),
            ("h2", "Mod Monitorizare (Windows)"),
            ("p", "Ruleaza in system tray, detecteaza automat cand introduci un card nou, si te anunta — "
                  "util daca transferi des, pe parcursul unei zile de filmare."),
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
            ("h2", "Nu pot scrie text in campurile Proiect/Card"),
            ("p", "Foloseste intotdeauna DataMover.app din /Applications (nu binarul brut din interiorul "
                  "arhivei) — asa fereastra primeste corect focus de tastatura."),
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
    "title": "DataMover — User Guide",
    "subtitle": "Install, activate, features, troubleshooting — by Cristi Gordas",
    "note": "Guide updated for the native macOS UI (SwiftUI) and the Windows app.",
    "sections": [
        {"h": "1. What is DataMover", "blocks": [
            ("p", "DataMover is a verified offload app for video production teams — it copies files from "
                  "video cards to multiple destinations at once (external drives, NAS, local folders), "
                  "with integrity verification at every step."),
            ("h2", "What it can do"),
            ("ul", [
                "Simultaneous copy to any number of destinations — all complete in parallel, not one by one.",
                "Integrity verification, your choice: MD5, SHA-1, SHA-256, SHA-512, or size-only.",
                "CSV + PDF reports (table layout), with per-file status (OK / Mismatch / Error) and exact timestamp.",
                "Automatic resume on errors (checkpoint) — continues from where it left off, no full restarts.",
                "Copy history (Mac) — see every past transfer, delete one entry or the whole history.",
                "Monitor Mode in the system tray (Windows) — automatically detects inserted cards.",
                "Automatic folder naming: Date_Project_Card.",
                "Built-in user guide inside the app (Mac).",
                "Dark theme, full interface in Romanian, English and Spanish.",
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
            ("p", "Download DataMover-Windows.zip and extract it. It contains DataMover.exe, ready to run "
                  "directly — no separate installation needed."),
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
            ("h2", "Automatic resume (checkpoint)"),
            ("p", "If a transfer is interrupted (card removed, network error to a NAS, etc.), DataMover "
                  "picks up exactly where it left off on the next attempt — it doesn't re-send files "
                  "already copied and successfully verified."),
            ("h2", "Copy history (Mac)"),
            ("p", "The clock button in the footer opens a window with every past copy job: date, folder "
                  "name, source and destination, and OK/skipped/failed counts. You can delete a single "
                  "entry or the entire history."),
            ("h2", "Monitor Mode (Windows)"),
            ("p", "Runs in the system tray, automatically detects when you insert a new card, and notifies "
                  "you — handy if you transfer often over the course of a shooting day."),
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
            ("h2", "I can't type in the Project/Card fields"),
            ("p", "Always use DataMover.app from /Applications (not the raw binary inside the archive) — "
                  "that's what lets the window receive keyboard focus correctly."),
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
    "title": "DataMover — Guia de uso",
    "subtitle": "Instalacion, activacion, funciones, solucion de problemas — por Cristi Gordas",
    "note": "Guia actualizada para la UI nativa de macOS (SwiftUI) y la app de Windows.",
    "sections": [
        {"h": "1. Que es DataMover", "blocks": [
            ("p", "DataMover es una aplicacion de offload verificado para equipos de produccion de video "
                  "— copia archivos desde tarjetas de video a varios destinos a la vez (unidades "
                  "externas, NAS, carpetas locales), con verificacion de integridad en cada paso."),
            ("h2", "Que puede hacer"),
            ("ul", [
                "Copia simultanea a cualquier numero de destinos — todos se completan en paralelo, no uno a uno.",
                "Verificacion de integridad, a elegir: MD5, SHA-1, SHA-256, SHA-512, o solo tamano.",
                "Informes CSV + PDF (en tabla), con estado por archivo (OK / Discrepancia / Error) y marca de tiempo exacta.",
                "Reanudacion automatica en caso de errores (checkpoint) — continua desde donde quedo, sin empezar de cero.",
                "Historial de copias (Mac) — ve todas las transferencias anteriores, elimina una entrada o todo el historial.",
                "Modo Monitor en la bandeja del sistema (Windows) — detecta automaticamente las tarjetas insertadas.",
                "Nombramiento automatico de carpetas: Fecha_Proyecto_Tarjeta.",
                "Guia de uso integrada directamente en la app (Mac).",
                "Tema oscuro, interfaz completa en rumano, ingles y espanol.",
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
            ("p", "Descarga DataMover-Windows.zip y extraelo. Contiene DataMover.exe, listo para "
                  "ejecutar directamente — no necesita instalacion aparte."),
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
            ("h2", "Reanudacion automatica (checkpoint)"),
            ("p", "Si una transferencia se interrumpe (tarjeta extraida, error de red en un NAS, etc.), "
                  "DataMover continua exactamente desde donde quedo en el siguiente intento — no vuelve a "
                  "enviar archivos ya copiados y verificados correctamente."),
            ("h2", "Historial de copias (Mac)"),
            ("p", "El boton de reloj en el pie abre una ventana con todas las copias anteriores: fecha, "
                  "nombre de la carpeta, origen y destino, y los recuentos OK/omitidos/fallidos. Puedes "
                  "eliminar una entrada especifica o todo el historial."),
            ("h2", "Modo Monitor (Windows)"),
            ("p", "Se ejecuta en la bandeja del sistema, detecta automaticamente cuando insertas una "
                  "tarjeta nueva, y te avisa — util si transfieres a menudo durante un dia de rodaje."),
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
            ("h2", "No puedo escribir en los campos Proyecto/Tarjeta"),
            ("p", "Usa siempre DataMover.app desde /Applications (no el binario suelto dentro del "
                  "archivo) — asi la ventana recibe correctamente el foco del teclado."),
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
