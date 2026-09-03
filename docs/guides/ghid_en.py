# -*- coding: utf-8 -*-
"""English guide content. See _engine.py for block types."""

EN = {
    "cover_subtitle": "Complete step-by-step user guide",
    "cover_version_label": "Version",
    "cover_lang_label": "English",
    "footer": "DataMover — User guide",
    "title": "DataMover — User guide",
    "subtitle": "Installation, activation, every option explained, troubleshooting — by Cristi Gordas",
    "note": "Guide for the native macOS app (SwiftUI) and the Windows app (WPF). Everything described here "
            "works identically on both platforms, except where explicitly noted.",
    "toc_title": "Contents",
    "sections": [

    {"h": "What DataMover is, and who it is for", "blocks": [
        ("p", "DataMover copies files from a camera card (or any folder) to <b>several destinations at "
              "once</b> and verifies, file by file, that what arrived is bit-for-bit identical to what was "
              "on the card. When it finishes, it leaves the proof next to your data: CSV, PDF and HTML "
              "reports, plus an MHL file that professional post-production software can read."),
        ("p", "It is built for the riskiest moment of a shooting day: the one right before somebody "
              "formats the card. Until you are certain the footage arrived intact in at least two places, "
              "that card must not be wiped."),
        ("img", ("ui-main-dark.png", "The main window — Sources (left), detected Disks (centre), Destinations (right)")),
        ("h2", "What it does, in short"),
        ("ul", [
            "Copies to any number of destinations simultaneously — they all fill in parallel, not one after another.",
            "Verifies integrity with xxHash64 (default, the fastest), MD5, SHA-1, SHA-256, SHA-512, or by size only.",
            "Writes an MHL (Media Hash List) file next to the data — the certificate read by Silverstack, YoYotta, ShotPut Pro and post houses.",
            "Generates CSV, PDF and HTML reports, with your logo and production details in the header.",
            "Resumes an interrupted transfer exactly where it stopped (checkpoint).",
            "Retries failed files on its own before declaring a problem.",
            "Checks free space before copying the first byte.",
            "Offloads several cards back to back, unattended (card queue).",
            "Recognises RED, ARRI, Sony, Panasonic, Canon and Blackmagic card structures.",
            "Ejects the card and notifies you when it is done.",
            "Full interface in Romanian, English and Spanish, in a light or dark theme.",
        ]),
        ("info", ("Worth knowing", "The source code is public on GitHub under the MIT licence. After the free "
                  "trial, the compiled app needs an activation code tied to your computer — see chapter 4.")),
    ]},

    {"h": "Installing on macOS", "blocks": [
        ("p", "The app is signed with an Apple Developer ID certificate, notarised by Apple and stapled. "
              "That means macOS accepts it directly, like any commercially distributed application."),
        ("steps", [
            "Go to <b>gordas.dev/datamover</b> and click <b>Download for Mac</b>. You get a "
            "<b>DataMover-Mac.zip</b> file.",
            "Open the archive (double-click). Inside are three files: the installer package "
            "<b>DataMover-2.11.1.pkg</b>, the uninstaller <b>Dezinstalare_DataMover.command</b>, "
            "and this guide as a PDF.",
            "Double-click the <b>.pkg</b> file. The macOS installer opens.",
            "Read and accept the licence terms (<b>Agree</b>), then click <b>Continue</b> and <b>Install</b>.",
            "Enter your Mac password when asked — it is your account password, not an app password. It stays "
            "invisible while you type; press Enter when done.",
            "Done. The app is installed straight into your <b>Applications</b> folder. Find it with Spotlight "
            "(⌘+Space, type “DataMover”) or in Launchpad.",
        ]),
        ("ok", ("No Terminal command needed",
                "Because the package is notarised by Apple, you will <b>not</b> see a “the app is damaged” "
                "message, you do <b>not</b> need to right-click → Open, and you do <b>not</b> need to run "
                "<i>xattr -cr</i>. If an older guide tells you otherwise, that information is out of date.")),
        ("h2", "If the app was not moved to Applications"),
        ("p", "If you ever launch it from somewhere else (from Downloads, for instance), it will offer to "
              "move itself to Applications on first launch. Answer <b>Yes</b> — otherwise macOS runs it in "
              "an isolated mode where some permissions do not work correctly."),
    ]},

    {"h": "Installing on Windows", "blocks": [
        ("steps", [
            "Go to <b>gordas.dev/datamover</b> and click <b>Download for Windows</b>. You get "
            "<b>DataMover-WPF-Windows.zip</b>.",
            "Right-click the archive → <b>Extract All…</b> → <b>Extract</b>. Do not run the program from "
            "inside the archive.",
            "Double-click <b>DataMoverSetup.exe</b>.",
            "Windows may show a SmartScreen warning (“Windows protected your PC”), because the app is new "
            "and has no download history yet. Click <b>More info</b> → <b>Run anyway</b>.",
            "Confirm the <b>User Account Control (UAC)</b> prompt — installing requires administrator "
            "rights to write into Program Files.",
            "Tick <b>I accept the agreement</b>, then <b>Next</b> until <b>Install</b>.",
            "Done. You get Desktop and Start menu shortcuts. Uninstalling works normally from "
            "<b>Settings → Apps → Installed apps</b>.",
        ]),
        ("info", ("Where it installs", "Into <b>C:\\Program Files\\DataMover</b>. That is a Windows-protected "
                  "area, which is why installation and updates ask for administrator confirmation.")),
    ]},

    {"h": "Free trial, activation and the donation", "blocks": [
        ("p", "From first launch you get a <b>7-day free trial</b> with every feature enabled. During the "
              "trial there is exactly one limitation, designed so you can test freely without the app being "
              "usable in production indefinitely without activation:"),
        ("warn", ("2 GB per-transfer cap during the trial",
                  "A transfer whose total size exceeds 2 GB will not start; you get an explicit message with "
                  "the option to activate. The cap applies to the <b>sum of all files</b> in one transfer, "
                  "not to each file individually.")),
        ("h2", "How to get your activation code"),
        ("steps", [
            "Open <b>Settings</b> (the gear in the bottom bar) and scroll to <b>Profile &amp; Licence</b>. "
            "There you will find your <b>Machine ID</b>, with a <b>Copy</b> button next to it.",
            "Click <b>Activate…</b>. The activation window opens with the ID already filled in.",
            "Press the green <b>WhatsApp</b> button — it opens a conversation with me, with your ID already "
            "written into the message. Send it.",
            "I reply with a personal activation code, generated for <b>that</b> computer. The code will not "
            "work on any other machine, even if it is passed around.",
            "Paste the code into the <b>Licence code</b> field and press <b>Activate</b>. That is it — the "
            "app starts normally from then on.",
        ]),
        ("p", "The <b>€23</b> is a <b>donation</b>, not a list price: it helps me cover development costs "
              "(subscriptions, tools, certificates) and keep maintaining and improving the app. If the app "
              "shows a different amount, that is a promotion running at the time — the amount shown in the "
              "activation window is always the correct one."),
        ("info", ("Changed computers?", "You need a new code, because the old one is tied to the old machine "
                  "ID. Message me again on WhatsApp with the new ID.")),
        ("p", "Once entered, your activation code stays saved and visible under <b>Settings → Profile &amp; "
              "Licence</b>, with a copy button — so you have it at hand if you reinstall your system."),
    ]},

    {"h": "The main window, area by area", "blocks": [
        ("img", ("ui-main-dark.png", "The three columns and the top and bottom bars")),
        ("h2", "Top bar"),
        ("opt", (("Element", "What it does"), [
            ("Project", "The production name. It goes into the destination folder name and the report header. Left empty, it becomes “Proiect”."),
            ("Card", "The name of the card being offloaded (A001, CAM-B-02…). It also goes into the folder name. Empty means “Card”."),
            ("Version", "The installed version number, top right. Check it when reporting a problem."),
            ("Question mark", "Opens this PDF guide, straight from the app."),
        ])),
        ("h2", "SOURCES column (left)"),
        ("p", "This is what gets read. You can add a source three ways: drag a folder from Finder/Explorer "
              "onto the box, drag a disk icon from the middle column, or use the add button. You can add "
              "several sources at once — they all land in the <b>same</b> destination folder. If you want "
              "each card in its own folder, use the card queue (chapter 9)."),
        ("p", "Under each source, where applicable, you will see the recognised card type and the clip "
              "count — see chapter 10."),
        ("h2", "DISKS column (centre)"),
        ("p", "Every connected volume with its free space, refreshed automatically every few seconds. Drag "
              "an icon left to use it as a source, right to use it as a destination. The slider at the top "
              "right makes the icons bigger or smaller."),
        ("h2", "DESTINATIONS column (right)"),
        ("p", "This is what gets written. Add as many destinations as you like — external drives, NAS, local "
              "folders. They all fill <b>in parallel</b>, and each one gets its own complete set of reports."),
        ("h2", "Bottom bar"),
        ("opt", (("Element", "What it does"), [
            ("Status text", "What the app is doing right now: percentage, files done out of total, current speed."),
            ("Clock", "Opens the copy history — see chapter 12."),
            ("Gear", "Opens the settings panel — chapter 7."),
            ("Cancel", "Stops the running transfer. Files already copied and verified stay at the destination."),
            ("Start", "Starts the transfer. Enabled only when you have at least one source and one destination."),
        ])),
        ("p", "While a transfer runs, a terminal-style feed under the progress bar shows exactly which file "
              "is being copied or verified. That matters most with large video files, where the percentage "
              "can sit still for tens of seconds and the app looks frozen."),
    ]},

    {"h": "A complete transfer, step by step", "blocks": [
        ("steps", [
            "Connect the card and the destination drive (or drives).",
            "Add the card to <b>Sources</b> and the drive to <b>Destinations</b>.",
            "Fill in <b>Project</b> and <b>Card</b> in the top bar. (Optional, but recommended: they appear "
            "in the folder name and in the reports.)",
            "Open <b>Settings</b> and check the verification model and the other options — chapter 7. They "
            "persist between transfers, so usually you set them once.",
            "Press <b>Start</b>.",
            "The app first checks whether the transfer fits at the destination. If not, it tells you exactly "
            "how much space is needed and how much is free, and lets you decide whether to continue anyway.",
            "The destination folder is created, then each file is copied and immediately verified.",
            "At the end, any failed files are automatically retried once.",
            "The reports (CSV, PDF, HTML) and the MHL file are written, then you get a system notification "
            "and a sound. If you enabled the option, the card ejects itself.",
        ]),
        ("h2", "Pause, resume, cancel"),
        ("p", "<b>Pause</b> stops the transfer <b>between</b> files — the file in progress finishes copying, "
              "so nothing is lost. <b>Continue</b> picks up exactly where it left off. <b>Cancel</b> stops "
              "for good, but everything already copied and verified stays valid at the destination and is "
              "recognised on a later resume."),
        ("h2", "If the folder already exists"),
        ("p", "When you start a transfer into a folder that already exists and contains files, the app asks "
              "what you want to do:"),
        ("opt", (("Option", "What happens"), [
            ("Resume", "Continues the existing transfer. Files already copied correctly are verified and skipped, not copied again. This is the right choice most of the time."),
            ("New folder", "Creates a separate folder with a number appended — nothing existing is touched."),
            ("Overwrite", "Empties the existing folder completely and starts from scratch. Irreversible."),
            ("Cancel", "Starts nothing."),
        ])),
        ("info", ("Why this matters",
                  "A multi-hour transfer that crosses midnight, or is resumed the next day, would otherwise "
                  "get a new folder name (the date changed) and copy everything again for nothing. The app "
                  "first looks for an existing folder for the same project and card, whatever its date.")),
    ]},

    {"h": "Every setting, one by one", "blocks": [
        ("p", "All the options below live in a single panel, opened with the gear in the bottom bar. They "
              "save themselves immediately — there is no “Save” button."),
        ("img", ("ui-settings-light.png", "The settings panel, light theme")),
        ("h2", "Language and appearance"),
        ("opt", (("Setting", "Explanation"), [
            ("Language", "Romanian, English or Spanish. Changes immediately, no restart."),
            ("Appearance", "System, Light or Dark. Independent of your operating system theme — you can keep the app dark even if the rest of the computer is light."),
        ])),
        ("h2", "Verification model"),
        ("p", "This is the algorithm the app uses to confirm that the file at the destination is identical "
              "to the one on the card. It computes a “fingerprint” of the source and one of the copy; if the "
              "two match, the copy is definitely correct."),
        ("opt", (("Model", "When to use it"), [
            ("xxHash64", "<b>Default and recommended.</b> It is the standard choice of professional offloaders. For catching a corrupted copy it is as good as MD5, but several times faster — on a card of hundreds of gigabytes, verification is the slow part, not copying."),
            ("MD5", "Fast and very widely used. Choose it if somebody in your production chain explicitly asks for MD5."),
            ("SHA-1", "Slightly slower than MD5, still accepted by the MHL standard."),
            ("SHA-256", "More rigorous, suitable for long-term archiving. It <b>cannot</b> be written into an MHL file (it is not part of the standard)."),
            ("SHA-512", "The most rigorous and the slowest. Likewise not part of MHL."),
            ("Size only", "Compares only the file size, without reading its contents. Fastest but least safe — a corrupted file of the same size passes unnoticed. Produces no MHL."),
        ])),
        ("h2", "Exclusions"),
        ("p", "Files you do not want copied. Enter either an exact name (<i>Thumbs.db</i>) or an extension "
              "starting with a dot (<i>.tmp</i>), separated by commas. Hidden files (names starting with a "
              "dot) are skipped automatically anyway."),
        ("h2", "Transfer behaviour"),
        ("opt", (("Setting", "Explanation"), [
            ("Resume automatically from an existing checkpoint", "If a transfer was interrupted, continue where it stopped instead of starting over. Leave it on."),
            ("Automatically open the destination folder when the transfer finishes", "Opens Finder/Explorer on the created folder as soon as the transfer completes successfully."),
            ("Generate MHL file", "Writes the integrity certificate next to the data. See chapter 11. Requires xxHash64, MD5 or SHA-1."),
            ("Automatically retry failed files", "At the end of the transfer, failed or mismatched files are copied once more. Most on-set failures are transient: card nudged in the reader, cable touched, external drive asleep."),
            ("Eject card automatically when done", "Safely ejects the card after a <b>completely clean</b> transfer. A card with errors is never ejected automatically — you may still need to re-run from it."),
            ("Start automatically when a card is inserted", "Unattended mode: an inserted card goes straight into the queue and the offload starts by itself. Requires at least one destination chosen beforehand."),
        ])),
        ("warn", ("Ejecting on Windows requires administrator rights",
                  "If the app does not have them, the card is <b>not</b> ejected and an explicit message "
                  "appears in the activity feed telling you to remove it manually. Never assume it ejected "
                  "without seeing the confirmation.")),
        ("h2", "Production and reports"),
        ("p", "These fields are optional, but they turn the report from a technical log into a handover "
              "document you can send as-is to the producer or the post house. Fields left empty do not "
              "appear in the report at all."),
        ("opt", (("Field", "Where it appears"), [
            ("Client", "In the PDF and HTML report headers."),
            ("Operator / DIT", "In the header — who performed the offload."),
            ("Camera", "In the header and, if you use it in the template, in the folder name."),
            ("Shoot notes", "A free-text block, highlighted in the report. It clears on every app launch, being specific to one transfer."),
            ("Logo", "A PNG or JPG image, shown in the PDF report header and embedded into the HTML report."),
        ])),
        ("h2", "Folder name template"),
        ("p", "Decides what the destination folder is called. Below the field you always see a <b>live "
              "preview</b> of the resulting name, using the data filled in at that moment."),
        ("opt", (("Token", "Is replaced with"), [
            ("{data}", "Today's date, as 2026-09-03."),
            ("{ora}", "The start time, as 14-30."),
            ("{proiect}", "Whatever you typed in the Project field (or “Proiect”)."),
            ("{card}", "Whatever you typed in the Card field (or “Card”)."),
            ("{camera}", "The Camera from the Production section. Stays empty if you did not fill it in."),
            ("{operator}", "The Operator / DIT from the Production section."),
        ])),
        ("p", "The default template is <b>{data}_{proiect}_{card}</b> and produces exactly the name used by "
              "earlier versions, so you do not have to change anything if you are happy with it. Spaces "
              "become underscores, and characters that are illegal in a folder name are removed "
              "automatically."),
        ("h2", "Secondary Cloud destination"),
        ("p", "Optionally, alongside the local destinations, the footage can also be uploaded to a cloud "
              "account (Google Drive, Dropbox and the other services <i>rclone</i> supports). Only files "
              "that passed local verification are uploaded. The accounts are the ones already configured in "
              "Master Control Studio Pro — nothing separate to set up here."),
        ("h2", "I/O and memory"),
        ("p", "These control how aggressively the app uses disk and memory. The four presets cover almost "
              "every situation; the fields below them are for fine-tuning."),
        ("opt", (("Setting", "Explanation"), [
            ("Eco / low-end system", "For older laptops, or when you are editing at the same time."),
            ("Standard", "The recommended balance for most situations."),
            ("High performance", "For fast drives (SSD, RAID) and a computer doing nothing else."),
            ("Extreme / RAW production", "For very large RAW transfers on powerful hardware."),
            ("Copy buffer", "How much is read from disk at once. Larger means faster on big files, but more memory used."),
            ("RAM limit", "The memory ceiling above which the app slows itself down so it does not choke the system."),
        ])),
        ("h2", "Transfer profiles"),
        ("p", "If you work on several productions with different settings, you can save the current "
              "combination (sources, destinations, verification model, exclusions, buffer, RAM) under a name "
              "and reload it with one click."),
        ("h2", "Profile and licence"),
        ("p", "Optional name and email, your Machine ID and the saved licence code, each with a copy button. "
              "This is also where you check manually for a new version."),
    ]},

    {"h": "What you find at the destination afterwards", "blocks": [
        ("p", "In the folder created at the destination, next to the copied files, you will find:"),
        ("opt", (("File", "What it is for"), [
            ("offload_report_….csv", "The <b>complete</b> list of files, with the source and destination fingerprints, the status and the error if there was one. Opens in Excel or Numbers. This is the reference document when something is unclear."),
            ("offload_report_….pdf", "The same report, formatted for reading and sending: header with your production details and logo, a colour-coded summary, then every problem plus a sample of the successful files."),
            ("offload_report_….html", "The same information, but it opens in any browser including on a phone, and can be sent over WhatsApp or email without losing its formatting."),
            ("….mhl", "The machine-readable integrity certificate. See chapter 11."),
            ("offload_checkpoint.json", "A technical file used internally so an interrupted transfer can resume. Do not delete it while the transfer is unfinished."),
        ])),
        ("h2", "How to read a file's status"),
        ("opt", (("Status", "Meaning"), [
            ("OK", "Copied and verified successfully. The source fingerprint matches the copy."),
            ("SARIT (skipped)", "Already existed at the destination, same size, and verification confirmed it is identical. It was not copied again."),
            ("OK (retried)", "It failed on the first attempt but succeeded on the second. The file is good — but it is worth looking at the cable, reader or drive."),
            ("NEPOTRIVIRE (mismatch)", "The copy has a different fingerprint from the source. The file at the destination is <b>not</b> trustworthy."),
            ("EROARE (error)", "The copy could not be made at all. The exact reason is in the error column of the CSV."),
        ])),
        ("warn", ("The golden rule",
                  "Never format a card before looking at the report. If you see even a single "
                  "<b>mismatch</b> or <b>error</b>, that footage still exists only on the card.")),
    ]},

    {"h": "The card queue and unattended mode", "blocks": [
        ("p", "At the end of a multi-camera day you end up with six to eight cards. The queue offloads them "
              "one after another, each into <b>its own folder</b>, without you sitting next to the computer."),
        ("steps", [
            "Add the card to Sources and type its name into the <b>Card</b> field.",
            "Press <b>+ Add to queue</b>. The card leaves Sources (it has been handed to the queue) and "
            "appears in the list below.",
            "Repeat for each card.",
            "Press <b>Start queue</b>. The cards offload in turn; when one finishes, the next starts "
            "automatically.",
        ]),
        ("info", ("What happens if you press Cancel",
                  "The <b>whole</b> queue stops, not just the current card. If you pressed Cancel, the "
                  "reasonable assumption is that you do not want the next card starting immediately.")),
        ("h2", "Starting automatically when a card is inserted"),
        ("p", "With that option enabled in Settings, any newly connected card goes into the queue by itself "
              "and the offload starts without you pressing anything. You must have at least one destination "
              "chosen beforehand, otherwise the app would have nowhere to copy to. The volume name becomes "
              "the card name."),
    ]},

    {"h": "Camera card recognition", "blocks": [
        ("p", "When you add a source, the app looks at its folder structure and tells you what it recognised "
              "and how many clips it found. It knows <b>RED</b>, <b>ARRI</b>, <b>Sony XDCAM</b> and "
              "<b>XAVC</b>, <b>Panasonic P2</b> and <b>AVCHD</b>, <b>Canon</b>, <b>Blackmagic BRAW</b>, and "
              "ordinary photo/video cards with a DCIM folder."),
        ("p", "Recognition is purely informative — it never blocks a transfer. Its job is to catch the two "
              "classic on-set mistakes early:"),
        ("opt", (("Warning", "What it means and what to do"), [
            ("Looks like a SUBFOLDER of the card", "You added only part of the card (just the clips folder, for example). Copied like that, you lose the metadata files without which the footage cannot be reassembled correctly in the edit. Remove the source and add the <b>root</b> of the card."),
            ("Zero-byte files", "There are empty clips — a sign of a card pulled from the camera too early, or a failing card. Check those clips in the camera before formatting."),
            ("The card looks empty", "No media files were found. Check that you added the right volume."),
        ])),
    ]},

    {"h": "The MHL file — handing over to post", "blocks": [
        ("p", "An <b>MHL</b> (Media Hash List) is a file containing, for every copied file, its digital "
              "fingerprint, size and date. It is the equivalent of a handover certificate, but read by a "
              "<b>machine</b> rather than a person."),
        ("p", "Why it matters: six months from now, somebody in post can take the MHL file, open it in "
              "Silverstack, YoYotta, ShotPut Pro or a similar tool, and automatically verify that every file "
              "on the NAS or the LTO tape is bit-for-bit identical to what came out of the camera on the "
              "shooting day. Without an MHL, that check cannot be done."),
        ("ul", [
            "Written automatically into the root of the destination folder, next to the data.",
            "Contains <b>relative</b> paths, so the folder can be moved to another drive without invalidating it.",
            "Contains <b>only</b> files that passed verification. An unsafe file has no place in a certificate.",
            "Requires xxHash64, MD5 or SHA-1. With SHA-256 or SHA-512 the transfer and the reports are still "
            "complete, but no MHL is generated (those two are not part of the standard) — you will see an "
            "explicit message in the activity feed.",
        ]),
        ("info", ("Mac ↔ Windows compatibility",
                  "An MHL written on a Mac can be verified on Windows and vice versa: both versions of the "
                  "app produce exactly the same fingerprint for the same file.")),
    ]},

    {"h": "Copy history", "blocks": [
        ("p", "The clock button in the bottom bar opens the list of all previous transfers: date, folder "
              "name, source and destination, and how many files came out OK, skipped or with problems. You "
              "can delete a single entry or the whole history."),
        ("img", ("mac-ui-history.png", "Copy history, with direct opening of source and destination")),
    ]},

    {"h": "Problems and special situations", "blocks": [
        ("h2", "“Not enough space at destination” and the transfer will not start"),
        ("p", "The app worked out before starting that the footage does not fit, and shows you exactly how "
              "much space is needed and how much is free. Free up space, choose another destination, or "
              "press <b>Continue anyway</b> if you know something the app does not (that you will free space "
              "in the meantime, for instance). The check accounts for files already copied, so resuming at "
              "90% is not blocked for nothing."),
        ("h2", "macOS: “no permission”, or errors reading the card"),
        ("p", "macOS blocks apps from certain folders and volumes until you explicitly allow them. When the "
              "app hits this kind of error, it shows a dialog with a button that opens the right panel in "
              "System Settings. Tick <b>DataMover</b> under <b>Full Disk Access</b>, then restart the app "
              "and resume — files already copied are not repeated."),
        ("h2", "Windows: “access denied”"),
        ("p", "The file or folder is protected by Windows (often it belongs to another user or to a system "
              "area). The app offers to restart with administrator rights — accept the UAC prompt that "
              "appears."),
        ("h2", "A file has the MISMATCH status"),
        ("p", "The copy differs from the source. The app has already retried it once automatically. If it "
              "still shows up, the cause is almost certainly physical: cable, card reader, USB port, or the "
              "card itself. Try a different cable and a different reader, and <b>do not format the card</b>."),
        ("h2", "The transfer stopped halfway"),
        ("p", "Check what happened at the destination (drive disconnected, NAS down, computer asleep). Start "
              "the same transfer again: with resume enabled, it continues exactly where it stopped."),
        ("h2", "The PDF report is missing"),
        ("p", "The CSV and HTML reports are always written; if only the PDF is missing, the folder contains "
              "an <i>offload_report_PDF_EROARE.txt</i> file with the exact reason. Common causes are a full "
              "disk or a destination disconnected right at the end."),
        ("h2", "The activation code does not work"),
        ("p", "Check that you copied it in full, with no extra spaces at the start or end. A code is tied to "
              "one computer: if you changed machines or reinstalled your system, you need a new code."),
    ]},

    {"h": "Updating the app", "blocks": [
        ("p", "At every launch the app quietly checks whether a new version exists. When there is one, you "
              "get a window with the version number, a summary of what is new, and two buttons: <b>Update "
              "now</b> and <b>Later</b>. The window appears once per new version."),
        ("p", "The update is not silent: the app downloads the package and then <b>launches the installer</b>, "
              "which you complete yourself. On macOS you are asked for your Mac password; on Windows, for "
              "administrator confirmation and licence acceptance. You can check manually at any time from "
              "<b>Settings → Check for updates</b>."),
        ("info", ("If you are on a Windows version older than 2.11.1",
                  "In those versions the in-app update failed. Download the current version manually once, "
                  "from gordas.dev/datamover — from then on updates work straight from the app.")),
    ]},

    {"h": "Uninstalling", "blocks": [
        ("h2", "macOS"),
        ("p", "The downloaded archive contains <b>Dezinstalare_DataMover.command</b>. Double-clicking it "
              "removes the app completely along with every trace: preferences, caches, history, the saved "
              "licence. You can also simply drag the app to the Trash — but then the preferences stay on disk."),
        ("h2", "Windows"),
        ("p", "<b>Settings → Apps → Installed apps → DataMover → Uninstall</b>. The uninstaller is generated "
              "automatically by the installer and removes everything it installed."),
    ]},

    {"h": "Licence, support and contact", "blocks": [
        ("p", "DataMover's source code is MIT-licensed and fully available on GitHub. Using the compiled "
              "app after the 7-day trial requires a personal activation code, tied to a single computer."),
        ("p", "Supporting the project is done through a <b>donation</b> — the reference amount is <b>€23</b>, "
              "or whatever is shown in the activation window if a promotion is running. It is not a list "
              "price and you are not buying a product: you are contributing to an independent project, "
              "provided as is."),
        ("p", "For activation, questions or problems, message me on WhatsApp straight from the app's "
              "activation window — the message already carries your Machine ID."),
    ]},
    ],
}
