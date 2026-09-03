# -*- coding: utf-8 -*-
"""Continutul ghidului RO. Vezi _engine.py pentru tipurile de blocuri."""

RO = {
    "cover_subtitle": "Ghid complet de utilizare, pas cu pas",
    "cover_version_label": "Versiunea",
    "cover_lang_label": "Română",
    "footer": "DataMover — Ghid de utilizare",
    "title": "DataMover — Ghid de utilizare",
    "subtitle": "Instalare, activare, fiecare opțiune explicată, depanare — de Cristi Gordas",
    "note": "Ghid pentru aplicația nativă macOS (SwiftUI) și pentru aplicația Windows (WPF). "
            "Tot ce vezi aici există identic pe ambele platforme, cu excepția locurilor marcate explicit.",
    "toc_title": "Cuprins",
    "sections": [

    # ----------------------------------------------------------------- 1
    {"h": "Ce este DataMover și pentru cine e făcut", "blocks": [
        ("p", "DataMover copiază fișierele de pe un card de filmare (sau de pe orice folder) către "
              "<b>mai multe destinații deodată</b> și verifică, fișier cu fișier, că ce a ajuns la "
              "destinație este identic bit cu bit cu ce era pe card. La final îți lasă lângă date "
              "documentele care dovedesc asta: rapoarte CSV, PDF și HTML, plus un fișier MHL pe care "
              "îl citesc programele profesionale de post-producție."),
        ("p", "Este făcut pentru momentul cel mai riscant dintr-o zi de filmare: acela în care cineva "
              "urmează să formateze cardul. Până când nu ai certitudinea că materialul a ajuns intact "
              "în cel puțin două locuri, cardul nu trebuie golit."),
        ("img", ("ui-main-dark.png", "Fereastra principală — Surse (stânga), Discuri detectate (centru), Destinații (dreapta)")),
        ("h2", "Ce face, pe scurt"),
        ("ul", [
            "Copiază simultan către oricâte destinații — toate se completează în paralel, nu una după alta.",
            "Verifică integritatea cu xxHash64 (implicit, cel mai rapid), MD5, SHA-1, SHA-256, SHA-512 sau doar prin dimensiune.",
            "Scrie un fișier MHL (Media Hash List) lângă date — certificatul citit de Silverstack, YoYotta, ShotPut Pro și casele de post.",
            "Generează rapoarte CSV, PDF și HTML, cu logo-ul și datele producției tale în antet.",
            "Reia automat un transfer întrerupt, exact de unde a rămas (checkpoint).",
            "Reîncearcă singur fișierele care au eșuat, înainte de a declara o problemă.",
            "Verifică spațiul liber înainte de a copia primul octet.",
            "Descarcă mai multe carduri la rând, nesupravegheat (coadă de carduri).",
            "Recunoaște structura cardurilor RED, ARRI, Sony, Panasonic, Canon și Blackmagic.",
            "Ejectează cardul și te anunță când a terminat.",
            "Interfață completă în română, engleză și spaniolă, cu temă deschisă sau întunecată.",
        ]),
        ("info", ("De reținut", "Codul sursă e public pe GitHub sub licență MIT. Aplicația compilată are "
                  "nevoie, după proba gratuită, de un cod de activare legat de calculatorul tău — vezi capitolul 4.")),
    ]},

    # ----------------------------------------------------------------- 2
    {"h": "Instalarea pe macOS", "blocks": [
        ("p", "Aplicația este semnată cu un certificat Apple Developer ID, notarizată de Apple și "
              "„ștampilată” (stapled). Asta înseamnă că macOS o acceptă direct, ca pe orice aplicație "
              "cumpărată din comerț."),
        ("steps", [
            "Intră pe <b>gordas.dev/datamover</b> și apasă butonul <b>Descarcă pentru Mac</b>. "
            "Se descarcă un fișier <b>DataMover-Mac.zip</b>.",
            "Deschide arhiva (dublu-click). Înăuntru găsești trei fișiere: pachetul de instalare "
            "<b>DataMover-2.11.1.pkg</b>, dezinstalatorul <b>Dezinstalare_DataMover.command</b> "
            "și acest ghid în PDF.",
            "Dublu-click pe fișierul <b>.pkg</b>. Se deschide programul de instalare al macOS.",
            "Citește și acceptă termenii de licență (butonul <b>Agree</b>), apoi apasă <b>Continuă</b> "
            "și <b>Instalează</b>.",
            "Introdu parola de Mac atunci când ți se cere — e parola contului tău, nu una a aplicației. "
            "Nu se vede pe ecran în timp ce o tastezi; apasă Enter la final.",
            "Gata. Aplicația este instalată direct în folderul <b>Aplicații</b>. O găsești cu Spotlight "
            "(⌘+Space, scrii „DataMover”) sau în Launchpad.",
        ]),
        ("ok", ("Nu ai nevoie de nicio comandă în Terminal",
                "Pachetul fiind notarizat de Apple, <b>nu</b> apare mesajul „aplicația e deteriorată”, "
                "<b>nu</b> trebuie să dai click-dreapta → Open și <b>nu</b> trebuie să rulezi "
                "<i>xattr -cr</i>. Dacă vreun ghid mai vechi îți spune altceva, acea informație este depășită.")),
        ("h2", "Dacă aplicația nu a fost mutată în Aplicații"),
        ("p", "Dacă ajungi vreodată să pornești aplicația din altă parte (de exemplu direct din Descărcări), "
              "la prima lansare te întreabă dacă vrei să o mute în Aplicații. Răspunde <b>Da</b> — altfel "
              "macOS o rulează într-un mod izolat în care unele permisiuni nu funcționează corect."),
    ]},

    # ----------------------------------------------------------------- 3
    {"h": "Instalarea pe Windows", "blocks": [
        ("steps", [
            "Intră pe <b>gordas.dev/datamover</b> și apasă butonul <b>Descarcă pentru Windows</b>. "
            "Se descarcă <b>DataMover-WPF-Windows.zip</b>.",
            "Click-dreapta pe arhivă → <b>Extract All…</b> (Extrage tot) → <b>Extract</b>. "
            "Nu rula programul direct din interiorul arhivei.",
            "Dublu-click pe <b>DataMoverSetup.exe</b>.",
            "Windows poate afișa un avertisment SmartScreen („Windows protected your PC”), pentru că "
            "aplicația e nouă și încă nu are un istoric de descărcări. Apasă <b>More info</b> → "
            "<b>Run anyway</b>.",
            "Confirmă fereastra <b>Control cont utilizator (UAC)</b> — instalarea are nevoie de drepturi "
            "de administrator ca să scrie în Program Files.",
            "Bifează <b>I accept the agreement</b> (accept termenii), apoi <b>Next</b> până la "
            "<b>Install</b>.",
            "Gata. Ai scurtături pe Desktop și în meniul Start. Dezinstalarea se face normal, din "
            "<b>Setări → Aplicații → Aplicații instalate</b>.",
        ]),
        ("info", ("Unde se instalează", "În <b>C:\\Program Files\\DataMover</b>. Aceasta este o zonă protejată "
                  "de Windows — de aceea instalarea și actualizările cer confirmare de administrator.")),
    ]},

    # ----------------------------------------------------------------- 4
    {"h": "Proba gratuită, activarea și donația", "blocks": [
        ("p", "De la prima pornire ai <b>7 zile de probă gratuită</b>, cu toate funcțiile active. "
              "În perioada de probă există o singură limitare, gândită ca să poți testa în voie fără ca "
              "aplicația să poată fi folosită productiv la nesfârșit fără activare:"),
        ("warn", ("Plafon de 2 GB per transfer în versiunea de probă",
                  "Un transfer a cărui dimensiune totală depășește 2 GB nu pornește și primești un mesaj "
                  "explicit, cu opțiunea de a activa licența. Plafonul se aplică pe <b>suma tuturor "
                  "fișierelor</b> dintr-un transfer, nu pe fiecare fișier în parte.")),
        ("h2", "Cum obții codul de activare"),
        ("steps", [
            "Deschide <b>Setări</b> (roata dințată din bara de jos) și derulează până la secțiunea "
            "<b>Profil &amp; Licență</b>. Acolo vezi <b>ID-ul calculatorului</b> (Machine ID), cu un "
            "buton <b>Copiază</b> lângă el.",
            "Apasă <b>Activează…</b>. Se deschide fereastra de activare, cu ID-ul deja completat.",
            "Apasă butonul verde de <b>WhatsApp</b> — se deschide o conversație cu mine, cu ID-ul tău "
            "deja scris în mesaj. Trimite-l.",
            "Îți răspund cu codul de activare personal, generat pentru <b>acel</b> calculator. Codul nu "
            "funcționează pe alt calculator, chiar dacă e distribuit mai departe.",
            "Lipește codul în câmpul <b>Cod licență</b> și apasă <b>Activează</b>. Gata — aplicația "
            "pornește normal de fiecare dată, fără să mai ceară nimic.",
        ]),
        ("p", "Suma de <b>23 €</b> este o <b>donație</b> de susținere, nu un preț de listă: mă ajută să "
              "acopăr costurile de dezvoltare (abonamente, unelte, certificate) și să continui să întrețin "
              "și să îmbunătățesc aplicația. Dacă în aplicație vezi o altă sumă, este o ofertă activă în "
              "acel moment — suma afișată în fereastra de activare este întotdeauna cea corectă."),
        ("info", ("Ai schimbat calculatorul?", "Ai nevoie de un cod nou, pentru că vechiul cod e legat de "
                  "ID-ul mașinii vechi. Scrie-mi din nou pe WhatsApp, cu noul ID.")),
        ("p", "Codul de activare, odată introdus, rămâne salvat și vizibil în <b>Setări → Profil &amp; "
              "Licență</b>, cu un buton de copiere — ca să îl ai la îndemână dacă reinstalezi sistemul."),
    ]},

    # ----------------------------------------------------------------- 5
    {"h": "Fereastra principală, zonă cu zonă", "blocks": [
        ("img", ("ui-main-dark.png", "Cele trei coloane și barele de sus și de jos")),
        ("h2", "Bara de sus"),
        ("opt", (("Element", "Ce face"), [
            ("Proiect", "Numele producției. Intră în numele folderului creat la destinație și în antetul rapoartelor. Dacă îl lași gol, se folosește cuvântul „Proiect”."),
            ("Card", "Numele cardului descărcat (de exemplu A001, CAM-B-02). Intră și el în numele folderului. Gol înseamnă „Card”."),
            ("Versiune", "Numărul versiunii instalate, în dreapta sus. Verifică-l când raportezi o problemă."),
            ("Semnul întrebării", "Deschide acest ghid în PDF, direct din aplicație."),
        ])),
        ("h2", "Coloana SURSE (stânga)"),
        ("p", "De aici se citește. Poți adăuga o sursă în trei feluri: tragi un folder din Finder/Explorer "
              "peste casetă, tragi o pictogramă de disc din coloana din mijloc, sau apeși butonul de "
              "adăugare. Poți pune mai multe surse deodată — toate ajung în <b>același</b> folder la "
              "destinație. Dacă vrei ca fiecare card să aibă folderul lui, folosește coada de carduri "
              "(capitolul 9)."),
        ("p", "Sub fiecare sursă apare, dacă e cazul, tipul de card recunoscut și numărul de clipuri — "
              "vezi capitolul 10."),
        ("h2", "Coloana DISCURI (centru)"),
        ("p", "Toate volumele conectate, cu spațiul liber al fiecăruia, împrospătate automat la fiecare "
              "câteva secunde. Trage o pictogramă spre stânga ca să o folosești ca sursă, spre dreapta ca "
              "destinație. Cursorul din dreapta sus mărește sau micșorează pictogramele."),
        ("h2", "Coloana DESTINAȚII (dreapta)"),
        ("p", "Aici se scrie. Poți adăuga oricâte destinații — discuri externe, NAS, foldere locale. "
              "Toate se completează <b>în paralel</b>, nu una după alta, iar fiecare primește propriul set "
              "complet de rapoarte."),
        ("h2", "Bara de jos"),
        ("opt", (("Element", "Ce face"), [
            ("Textul de stare", "Ce face aplicația chiar acum: procent, câte fișiere din câte, viteza curentă."),
            ("Ceasul", "Deschide istoricul copierilor — vezi capitolul 12."),
            ("Roata dințată", "Deschide panoul de setări — capitolul 7."),
            ("Anulează", "Oprește transferul în curs. Fișierele deja copiate și verificate rămân la destinație."),
            ("Start", "Pornește transferul. E activ doar când ai cel puțin o sursă și o destinație."),
        ])),
        ("p", "În timpul unui transfer, sub bara de progres apare un flux de text în stil terminal, care "
              "arată exact ce fișier se copiază sau se verifică în acel moment. E util mai ales la fișiere "
              "video mari, unde procentul poate sta pe loc zeci de secunde și pare că aplicația s-a blocat."),
    ]},

    # ----------------------------------------------------------------- 6
    {"h": "Un transfer complet, pas cu pas", "blocks": [
        ("steps", [
            "Conectează cardul și discul (sau discurile) de destinație.",
            "Adaugă cardul în <b>Surse</b> și discul în <b>Destinații</b>.",
            "Scrie <b>Proiect</b> și <b>Card</b> în bara de sus. (Opțional, dar recomandat: apar în numele "
            "folderului și în rapoarte.)",
            "Deschide <b>Setări</b> și verifică modelul de verificare și restul opțiunilor — capitolul 7. "
            "Se rețin de la un transfer la altul, deci de obicei le setezi o singură dată.",
            "Apasă <b>Start</b>.",
            "Aplicația verifică întâi dacă transferul încape la destinație. Dacă nu, îți spune exact de cât "
            "spațiu e nevoie și cât e liber, și te lasă să alegi dacă continui totuși.",
            "Se creează folderul de destinație, apoi fiecare fișier este copiat și imediat verificat.",
            "La final, fișierele care au eșuat sunt reîncercate automat o dată.",
            "Se scriu rapoartele (CSV, PDF, HTML) și fișierul MHL, apoi primești o notificare de sistem "
            "și un sunet. Dacă ai bifat opțiunea, cardul se ejectează singur.",
        ]),
        ("h2", "Pauză, reluare, anulare"),
        ("p", "Butonul de <b>Pauză</b> oprește transferul <b>între</b> fișiere — fișierul aflat în lucru "
              "își termină copierea, deci nu se pierde nimic. La <b>Continuă</b>, se reia exact de unde a "
              "rămas. <b>Anulează</b> oprește definitiv, dar tot ce a fost deja copiat și verificat rămâne "
              "valid la destinație și e recunoscut la o reluare ulterioară."),
        ("h2", "Dacă folderul există deja"),
        ("p", "Când pornești un transfer către un folder care există deja și conține fișiere, aplicația "
              "te întreabă ce vrei să faci:"),
        ("opt", (("Opțiune", "Ce se întâmplă"), [
            ("Reia", "Continuă transferul existent. Fișierele deja copiate corect sunt verificate și sărite, nu recopiate. Aceasta e alegerea potrivită în majoritatea cazurilor."),
            ("Folder nou", "Creează un folder separat, cu un număr adăugat la nume — nu atinge nimic din ce există."),
            ("Suprascrie", "Golește complet folderul existent și pornește de la zero. Ireversibil."),
            ("Renunță", "Nu pornește nimic."),
        ])),
        ("info", ("De ce contează",
                  "Un transfer de mai multe ore care trece peste miezul nopții, sau reluat a doua zi, ar "
                  "primi altfel un nume de folder nou (data s-a schimbat) și ar recopia totul degeaba. "
                  "Aplicația caută întâi un folder existent al aceluiași proiect și card, indiferent de dată.")),
    ]},

    # ----------------------------------------------------------------- 7
    {"h": "Toate setările, una câte una", "blocks": [
        ("p", "Toate opțiunile de mai jos stau într-un singur panou, deschis cu roata dințată din bara de "
              "jos. Se salvează singure, imediat — nu există buton „Salvează”."),
        ("img", ("ui-settings-dark.png", "Panoul de setări, în temă întunecată")),
        ("h2", "Limbă și aspect"),
        ("opt", (("Setare", "Explicație"), [
            ("Limba", "Română, engleză sau spaniolă. Se schimbă imediat, fără repornire."),
            ("Aspect", "Sistem, Luminos sau Întunecat. Independent de tema sistemului de operare — poți ține aplicația întunecată chiar dacă restul calculatorului e luminos."),
        ])),
        ("h2", "Model de verificare"),
        ("p", "Acesta este algoritmul cu care aplicația confirmă că fișierul ajuns la destinație e identic "
              "cu cel de pe card. Se calculează o „amprentă” a fișierului sursă și una a copiei; dacă cele "
              "două coincid, copia e sigur corectă."),
        ("opt", (("Model", "Când îl folosești"), [
            ("xxHash64", "<b>Implicit și recomandat.</b> Este alegerea standard a ofloaderelor profesionale. La detectarea unei copieri corupte e la fel de bun ca MD5, dar de câteva ori mai rapid — pe un card de sute de GB, verificarea e etapa care durează, nu copierea."),
            ("MD5", "Rapid și foarte răspândit. Alege-l dacă cineva din lanțul tău de producție cere explicit MD5."),
            ("SHA-1", "Puțin mai lent decât MD5, acceptat tot în standardul MHL."),
            ("SHA-256", "Mai riguros, potrivit pentru arhivare pe termen lung. <b>Nu</b> poate fi scris într-un fișier MHL (nu face parte din standard)."),
            ("SHA-512", "Cel mai riguros și cel mai lent. La fel, nu intră în MHL."),
            ("Doar dimensiune", "Compară doar mărimea fișierului, fără să-i citească conținutul. Cel mai rapid, dar cel mai puțin sigur — un fișier corupt care are aceeași mărime trece neobservat. Nu produce MHL."),
        ])),
        ("h2", "Excluderi"),
        ("p", "Fișiere pe care nu vrei să le copiezi. Scrii fie un nume exact (<i>Thumbs.db</i>), fie o "
              "extensie care începe cu punct (<i>.tmp</i>), separate prin virgulă. Fișierele ascunse "
              "(cele al căror nume începe cu punct) sunt oricum sărite automat."),
        ("h2", "Comportamentul transferului"),
        ("opt", (("Setare", "Explicație"), [
            ("Reia automat dintr-un checkpoint existent", "Dacă un transfer a fost întrerupt, îl continuă de unde a rămas în loc să ia totul de la capăt. Lasă-l bifat."),
            ("Deschide automat folderul destinație la finalizare", "Deschide Finder/Explorer pe folderul creat, imediat ce transferul s-a încheiat cu bine."),
            ("Generează fișier MHL", "Scrie certificatul de integritate lângă date. Vezi capitolul 11. Necesită xxHash64, MD5 sau SHA-1."),
            ("Reîncearcă automat fișierele eșuate", "La finalul transferului, fișierele cu eroare sau nepotrivire se copiază încă o dată. Majoritatea eșecurilor de pe platou sunt trecătoare: card mișcat în cititor, cablu atins, disc extern adormit."),
            ("Ejectează cardul automat la final", "Scoate cardul în siguranță după un transfer <b>complet curat</b>. Un card cu erori nu se ejectează niciodată automat — s-ar putea să mai fie nevoie de o reluare de pe el."),
            ("Pornește automat la introducerea unui card", "Modul nesupravegheat: cardul introdus intră direct în coadă și descărcarea începe singură. Necesită cel puțin o destinație aleasă dinainte."),
        ])),
        ("warn", ("Ejectarea pe Windows cere drepturi de administrator",
                  "Dacă aplicația nu le are, cardul <b>nu</b> se ejectează, iar în fluxul de activitate apare "
                  "un mesaj explicit care îți spune să îl scoți manual. Nu presupune niciodată că s-a "
                  "ejectat fără să vezi confirmarea.")),
        ("h2", "Producție și rapoarte"),
        ("p", "Aceste câmpuri sunt opționale, dar transformă raportul dintr-un log tehnic într-un document "
              "de predare care poate fi trimis ca atare producătorului sau casei de post. Câmpurile lăsate "
              "goale nu apar deloc în raport."),
        ("opt", (("Câmp", "Unde apare"), [
            ("Client", "În antetul rapoartelor PDF și HTML."),
            ("Operator / DIT", "În antet — cine a făcut descărcarea."),
            ("Cameră", "În antet și, dacă îl folosești în șablon, în numele folderului."),
            ("Note de filmare", "Un bloc de text liber, scos în evidență în raport. Se golește după fiecare pornire a aplicației, fiind specific unui transfer anume."),
            ("Logo", "O imagine PNG sau JPG, afișată în antetul raportului PDF și încorporată în raportul HTML."),
        ])),
        ("h2", "Șablon nume folder"),
        ("p", "Decide cum se numește folderul creat la destinație. Sub câmp vezi permanent o "
              "<b>previzualizare</b> a numelui care va rezulta, cu datele completate în acel moment."),
        ("opt", (("Token", "Se înlocuiește cu"), [
            ("{data}", "Data de azi, în formatul 2026-09-03."),
            ("{ora}", "Ora de început, în formatul 14-30."),
            ("{proiect}", "Ce ai scris în câmpul Proiect (sau „Proiect”)."),
            ("{card}", "Ce ai scris în câmpul Card (sau „Card”)."),
            ("{camera}", "Camera din secțiunea Producție. Rămâne gol dacă nu l-ai completat."),
            ("{operator}", "Operatorul / DIT din secțiunea Producție."),
        ])),
        ("p", "Șablonul implicit este <b>{data}_{proiect}_{card}</b> și produce exact numele folosit de "
              "versiunile anterioare, deci nu trebuie să schimbi nimic dacă ești mulțumit de el. Spațiile "
              "devin liniuță de subliniere, iar caracterele interzise într-un nume de folder sunt eliminate "
              "automat."),
        ("h2", "Destinație secundară Cloud"),
        ("p", "Opțional, pe lângă destinațiile locale, materialul poate fi urcat și într-un cont de cloud "
              "(Google Drive, Dropbox și celelalte servicii acceptate de <i>rclone</i>). Se urcă doar "
              "fișierele care au trecut verificarea locală. Conturile sunt cele configurate deja în "
              "Master Control Studio Pro — nu trebuie configurat nimic separat aici."),
        ("h2", "I/O și memorie"),
        ("p", "Aceste setări controlează cât de agresiv folosește aplicația discul și memoria. Cele patru "
              "preseturi acoperă aproape toate situațiile; câmpurile de dedesubt sunt pentru reglaj fin."),
        ("opt", (("Setare", "Explicație"), [
            ("Eco / Sistem slab", "Pentru laptopuri mai vechi sau când lucrezi în paralel cu montajul."),
            ("Standard", "Echilibrul recomandat pentru majoritatea situațiilor."),
            ("Performanță înaltă", "Pentru discuri rapide (SSD, RAID) și un calculator care nu face altceva."),
            ("Extrem / Producție RAW", "Pentru transferuri foarte mari de material RAW, pe hardware puternic."),
            ("Buffer copiere", "Cât citește dintr-o dată de pe disc. Mai mare înseamnă mai rapid pe fișiere mari, dar mai multă memorie ocupată."),
            ("Limită RAM", "Plafonul de memorie peste care aplicația încetinește singură, ca să nu sufoce sistemul."),
        ])),
        ("h2", "Profile de transfer"),
        ("p", "Dacă lucrezi la mai multe producții cu setări diferite, poți salva combinația curentă "
              "(surse, destinații, model de verificare, excluderi, buffer, RAM) sub un nume și să o reîncarci "
              "dintr-un click."),
        ("h2", "Profil și licență"),
        ("p", "Nume și email opționale, ID-ul calculatorului și codul de licență salvat, fiecare cu buton "
              "de copiere. Tot de aici verifici manual dacă există o versiune nouă."),
    ]},

    # ----------------------------------------------------------------- 8
    {"h": "Ce găsești la destinație după transfer", "blocks": [
        ("p", "În folderul creat la destinație, lângă fișierele copiate, rămân următoarele documente:"),
        ("opt", (("Fișier", "La ce folosește"), [
            ("offload_report_….csv", "Lista <b>completă</b> a fișierelor, cu amprenta sursei și a destinației, statusul și eroarea, dacă a existat. Se deschide în Excel sau Numbers. Acesta e documentul de referință când ceva nu e clar."),
            ("offload_report_….pdf", "Același raport, formatat pentru citit și trimis: antet cu datele producției și logo-ul tău, rezumat colorat, apoi toate problemele plus un eșantion din fișierele reușite."),
            ("offload_report_….html", "Aceeași informație, dar se deschide în orice browser, inclusiv pe telefon, și se trimite pe WhatsApp sau email fără să-și piardă formatarea."),
            ("….mhl", "Certificatul de integritate citit de programe. Vezi capitolul 11."),
            ("offload_checkpoint.json", "Fișier tehnic, folosit intern ca să poată fi reluat un transfer întrerupt. Nu îl șterge cât timp transferul nu s-a terminat."),
        ])),
        ("h2", "Cum citești statusul unui fișier"),
        ("opt", (("Status", "Ce înseamnă"), [
            ("OK", "Copiat și verificat cu succes. Amprenta sursei coincide cu a copiei."),
            ("SĂRIT", "Exista deja la destinație, cu aceeași dimensiune, și verificarea a confirmat că e identic. Nu a fost recopiat."),
            ("OK (reîncercat)", "A eșuat la prima încercare, dar a doua a reușit. Fișierul e bun — dar merită să te uiți la cablu, cititor sau disc."),
            ("NEPOTRIVIRE", "Copia are altă amprentă decât sursa. Fișierul de la destinație <b>nu</b> este de încredere."),
            ("EROARE", "Copierea nu a putut fi făcută deloc. Motivul exact e scris în coloana de eroare din CSV."),
        ])),
        ("warn", ("Regula de aur",
                  "Nu formata niciodată cardul înainte de a te uita în raport. Dacă vezi chiar și un singur "
                  "<b>NEPOTRIVIRE</b> sau <b>EROARE</b>, materialul acela încă există doar pe card.")),
    ]},

    # ----------------------------------------------------------------- 9
    {"h": "Coada de carduri și modul nesupravegheat", "blocks": [
        ("p", "La finalul unei zile cu mai multe camere se adună 6–8 carduri. Coada le descarcă unul după "
              "altul, fiecare în <b>propriul folder</b>, fără să stai lângă calculator."),
        ("steps", [
            "Adaugă cardul în Surse și scrie-i numele în câmpul <b>Card</b>.",
            "Apasă <b>+ Adaugă în coadă</b>. Cardul dispare din Surse (a fost predat cozii) și apare în "
            "lista de dedesubt.",
            "Repetă pentru fiecare card.",
            "Apasă <b>Pornește coada</b>. Cardurile se descarcă pe rând; la finalul fiecăruia începe "
            "automat următorul.",
        ]),
        ("info", ("Ce se întâmplă dacă apeși Anulează",
                  "Se oprește <b>toată</b> coada, nu doar cardul curent. Dacă ai apăsat Anulează, "
                  "presupunerea firească e că nu vrei să înceapă imediat următorul card.")),
        ("h2", "Pornirea automată la introducerea unui card"),
        ("p", "Cu opțiunea bifată în Setări, orice card nou conectat intră singur în coadă și descărcarea "
              "începe fără să apeși nimic. Trebuie să ai cel puțin o destinație aleasă dinainte; altfel "
              "aplicația nu ar avea unde să copieze. Numele cardului devine numele volumului."),
    ]},

    # ----------------------------------------------------------------- 10
    {"h": "Recunoașterea cardurilor de cameră", "blocks": [
        ("p", "Când adaugi o sursă, aplicația se uită la structura ei de foldere și îți spune ce a "
              "recunoscut și câte clipuri a găsit. Sunt recunoscute cardurile <b>RED</b>, <b>ARRI</b>, "
              "<b>Sony XDCAM</b> și <b>XAVC</b>, <b>Panasonic P2</b> și <b>AVCHD</b>, <b>Canon</b>, "
              "<b>Blackmagic BRAW</b>, precum și cardurile foto/video obișnuite cu folder DCIM."),
        ("p", "Recunoașterea este pur informativă — nu blochează niciodată transferul. Rolul ei este să "
              "prindă din timp cele două greșeli clasice de pe platou:"),
        ("opt", (("Avertisment", "Ce înseamnă și ce faci"), [
            ("Pare a fi un SUBFOLDER al cardului", "Ai adăugat doar o parte din card (de exemplu doar folderul cu clipuri). Copiat așa, pierzi fișierele de metadate fără de care materialul nu se mai reasamblează corect în montaj. Șterge sursa și adaugă <b>rădăcina</b> cardului."),
            ("Fișiere de 0 octeți", "Există clipuri goale — semn de card scos prea devreme din cameră sau de card defect. Verifică acele clipuri în cameră înainte de a formata."),
            ("Cardul pare gol", "Nu s-a găsit niciun fișier media. Verifică dacă ai adăugat volumul corect."),
        ])),
    ]},

    # ----------------------------------------------------------------- 11
    {"h": "Fișierul MHL — predarea către post-producție", "blocks": [
        ("p", "Un <b>MHL</b> (Media Hash List) este un fișier care conține, pentru fiecare fișier copiat, "
              "amprenta lui digitală, dimensiunea și data. Este echivalentul unui proces-verbal de predare, "
              "dar citit de <b>mașină</b>, nu de om."),
        ("p", "De ce contează: peste șase luni, cineva din post-producție poate lua fișierul MHL, îl poate "
              "deschide în Silverstack, YoYotta, ShotPut Pro sau alt program similar, și poate verifica "
              "automat că fiecare fișier de pe NAS sau de pe banda LTO este identic bit cu bit cu ce a ieșit "
              "din cameră în ziua filmării. Fără MHL, această verificare nu se poate face."),
        ("ul", [
            "Se scrie automat în rădăcina folderului de destinație, lângă date.",
            "Conține căi <b>relative</b>, deci folderul poate fi mutat pe alt disc fără să se invalideze.",
            "Conține <b>doar</b> fișierele care au trecut verificarea. Un fișier nesigur nu are ce căuta "
            "într-un certificat.",
            "Necesită xxHash64, MD5 sau SHA-1. Cu SHA-256 sau SHA-512, transferul și rapoartele rămân "
            "complete, dar MHL-ul nu se generează (aceste două nu fac parte din standard) — vei vedea un "
            "mesaj explicit în fluxul de activitate.",
        ]),
        ("info", ("Compatibilitate Mac ↔ Windows",
                  "Un MHL scris pe Mac poate fi verificat pe Windows și invers: ambele versiuni ale "
                  "aplicației produc exact aceeași amprentă pentru același fișier.")),
    ]},

    # ----------------------------------------------------------------- 12
    {"h": "Istoricul copierilor", "blocks": [
        ("p", "Butonul cu ceas din bara de jos deschide lista tuturor transferurilor anterioare: data, "
              "numele folderului, sursa și destinația, și câte fișiere au ieșit OK, sărite sau cu probleme. "
              "Poți șterge o singură intrare sau tot istoricul."),
        ("img", ("mac-ui-history.png", "Istoricul copierilor, cu deschidere directă a sursei și a destinației")),
    ]},

    # ----------------------------------------------------------------- 13
    {"h": "Probleme și situații speciale", "blocks": [
        ("h2", "„Spațiu insuficient la destinație” și transferul nu pornește"),
        ("p", "Aplicația a calculat înainte de start că materialul nu încape și îți arată exact de cât "
              "spațiu e nevoie și cât e liber. Eliberează spațiu, alege altă destinație, sau apasă "
              "<b>Continuă oricum</b> dacă știi ceva ce aplicația nu știe (de exemplu că vei elibera spațiu "
              "între timp). Verificarea ține cont de fișierele deja copiate, deci o reluare la 90% nu e "
              "blocată degeaba."),
        ("h2", "macOS: „nu am permisiunea” sau erori la citirea cardului"),
        ("p", "macOS blochează accesul aplicațiilor la anumite foldere și volume până când le dai voie "
              "explicit. Când aplicația întâlnește acest tip de eroare, îți arată o fereastră cu un buton "
              "care deschide direct panoul potrivit din Setări de sistem. Bifează <b>DataMover</b> la "
              "<b>Acces total la disc</b>, apoi repornește aplicația și reia transferul — fișierele deja "
              "copiate nu se iau de la capăt."),
        ("h2", "Windows: „acces refuzat”"),
        ("p", "Fișierul sau folderul e protejat de Windows (deseori aparține altui utilizator sau unei zone "
              "de sistem). Aplicația îți oferă să repornească cu drepturi de administrator — acceptă "
              "fereastra UAC care apare."),
        ("h2", "Un fișier are statusul NEPOTRIVIRE"),
        ("p", "Copia diferă de sursă. Aplicația a reîncercat deja automat o dată. Dacă tot apare, cauza e "
              "aproape sigur fizică: cablu, cititor de carduri, port USB sau chiar cardul. Încearcă alt "
              "cablu și alt cititor, și <b>nu formata cardul</b>."),
        ("h2", "Transferul s-a oprit la jumătate"),
        ("p", "Verifică ce s-a întâmplat cu destinația (disc deconectat, NAS căzut, calculator adormit). "
              "Pornește din nou același transfer: cu reluarea activă, continuă exact de unde a rămas."),
        ("h2", "Raportul PDF lipsește"),
        ("p", "Rapoartele CSV și HTML se scriu întotdeauna; dacă lipsește doar PDF-ul, în folder găsești un "
              "fișier <i>offload_report_PDF_EROARE.txt</i> cu motivul exact. Cauzele obișnuite sunt discul "
              "plin sau destinația deconectată chiar la final."),
        ("h2", "Codul de activare nu funcționează"),
        ("p", "Verifică să-l fi copiat complet, fără spații în plus la început sau la sfârșit. Un cod e legat "
              "de un singur calculator: dacă ai schimbat mașina sau ai reinstalat sistemul, ai nevoie de un "
              "cod nou."),
    ]},

    # ----------------------------------------------------------------- 14
    {"h": "Actualizarea aplicației", "blocks": [
        ("p", "La fiecare pornire, aplicația verifică discret dacă există o versiune nouă. Când există, "
              "primești o fereastră cu numărul versiunii, un rezumat al noutăților și două butoane: "
              "<b>Actualizează acum</b> și <b>Mai târziu</b>. Fereastra apare o singură dată per versiune."),
        ("p", "Actualizarea nu este silențioasă: aplicația descarcă pachetul și apoi <b>pornește programul "
              "de instalare</b>, pe care îl duci tu la capăt. Pe macOS ți se cere parola de Mac; pe Windows, "
              "confirmarea de administrator și acceptarea licenței. Poți verifica manual oricând, din "
              "<b>Setări → Verifică actualizări</b>."),
        ("info", ("Dacă ai o versiune mai veche de 2.11.1 pe Windows",
                  "În acele versiuni actualizarea din aplicație eșua. Descarcă o singură dată versiunea "
                  "curentă manual, de pe gordas.dev/datamover — de atunci încolo actualizările funcționează "
                  "direct din aplicație.")),
    ]},

    # ----------------------------------------------------------------- 15
    {"h": "Dezinstalare", "blocks": [
        ("h2", "macOS"),
        ("p", "În arhiva descărcată există fișierul <b>Dezinstalare_DataMover.command</b>. Dublu-click pe "
              "el șterge complet aplicația și toate urmele ei: preferințe, cache, istoric, licența salvată. "
              "Dacă preferi, poți muta pur și simplu aplicația la Coșul de gunoi — dar atunci preferințele "
              "rămân pe disc."),
        ("h2", "Windows"),
        ("p", "<b>Setări → Aplicații → Aplicații instalate → DataMover → Dezinstalează</b>. Programul de "
              "dezinstalare este generat automat de installer și curăță tot ce a instalat."),
    ]},

    # ----------------------------------------------------------------- 16
    {"h": "Licență, susținere și contact", "blocks": [
        ("p", "Codul sursă al DataMover este licențiat MIT și disponibil integral pe GitHub. Folosirea "
              "aplicației compilate, după cele 7 zile de probă, are nevoie de un cod de activare personal, "
              "legat de un singur calculator."),
        ("p", "Susținerea proiectului se face prin <b>donație</b> — suma de referință este <b>23 €</b>, sau "
              "cea afișată în fereastra de activare dacă există o ofertă în acel moment. Nu este un preț de "
              "listă și nu cumperi un produs: contribui la un proiect independent, oferit ca atare."),
        ("p", "Pentru activare, întrebări sau probleme, scrie-mi pe WhatsApp direct din fereastra de "
              "activare a aplicației — mesajul vine deja cu ID-ul calculatorului tău completat."),
    ]},
    ],
}
