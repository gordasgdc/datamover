import Foundation

// Chei adăugate la redesign-ul 2026-09-26 (stări, preflight, monitor,
// rezultat, Settings). Tabel separat ca să nu umflăm `Localization.swift`;
// `L.t` caută în ambele. Verificat de `LocalizationTests`: orice cheie are
// RO/EN/ES și niciun specificator nu diferă între limbi.
extension L {
    static let extraTable: [String: [AppLanguage: String]] = [
        // Faze
        "phase.idle": [.ro: "Inactiv", .en: "Idle", .es: "Inactivo"],
        "phase.preparing": [.ro: "Pregătire", .en: "Preparing", .es: "Preparando"],
        "phase.copying": [.ro: "Copiere și verificare", .en: "Copying and verifying", .es: "Copiando y verificando"],
        "phase.verifying": [.ro: "Verificare", .en: "Verifying", .es: "Verificando"],
        "phase.reporting": [.ro: "Rapoarte", .en: "Reporting", .es: "Informes"],
        "phase.finished": [.ro: "Finalizat", .en: "Finished", .es: "Terminado"],
        "phase.preparing.step": [.ro: "Pregătire", .en: "Prepare", .es: "Preparar"],
        "phase.copying.step": [.ro: "Copiere · flush · verificare", .en: "Copy · flush · verify", .es: "Copia · flush · verificación"],
        "phase.reporting.step": [.ro: "Rapoarte și MHL", .en: "Reports and MHL", .es: "Informes y MHL"],
        "phase.finished.step": [.ro: "Rezultat", .en: "Result", .es: "Resultado"],

        // Adâncimea verificării
        "depth.sizeOnly": [.ro: "Doar numărul de octeți (fără checksum)", .en: "Byte count only (no checksum)", .es: "Solo número de bytes (sin checksum)"],
        "depth.streamChecksum": [.ro: "Checksum în flux: sursa și fiecare copie, calculate din aceleași date la scriere", .en: "In-stream checksum: source and each copy, computed from the same data while writing", .es: "Checksum en flujo: origen y cada copia, calculados de los mismos datos al escribir"],
        "depth.readBack": [.ro: "Checksum în flux + recitire separată a fiecărei copii", .en: "In-stream checksum + separate re-read of each copy", .es: "Checksum en flujo + relectura separada de cada copia"],

        // Verdicte
        "outcome.success": [.ro: "Transfer verificat", .en: "Transfer verified", .es: "Transferencia verificada"],
        "outcome.successWithWarnings": [.ro: "Verificat, cu avertismente", .en: "Verified, with warnings", .es: "Verificado, con avisos"],
        "outcome.partialFailure": [.ro: "Eșec parțial", .en: "Partial failure", .es: "Fallo parcial"],
        "outcome.failure": [.ro: "Transfer eșuat", .en: "Transfer failed", .es: "Transferencia fallida"],
        "outcome.cancelled": [.ro: "Transfer anulat", .en: "Transfer cancelled", .es: "Transferencia cancelada"],
        "outcomeHelp.success": [.ro: "Fiecare fișier a trecut verificarea aleasă la fiecare destinație.", .en: "Every file passed the selected verification at every destination.", .es: "Cada archivo superó la verificación elegida en cada destino."],
        "outcomeHelp.successWithWarnings": [.ro: "Toate fișierele sunt confirmate, dar unele au reușit abia la reîncercare. Verifică cablul, cardul și discurile.", .en: "All files are confirmed, but some only succeeded on retry. Check the cable, card and drives.", .es: "Todos los archivos están confirmados, pero algunos solo tras reintentar. Revisa el cable, la tarjeta y los discos."],
        "outcomeHelp.partialFailure": [.ro: "Cel puțin o destinație are fișiere neconfirmate. Nu formata cardul. Destinațiile marcate verificat sunt sigure.", .en: "At least one destination has unconfirmed files. Do not format the card. Destinations marked verified are safe.", .es: "Al menos un destino tiene archivos sin confirmar. No formatees la tarjeta. Los destinos marcados como verificados son seguros."],
        "outcomeHelp.failure": [.ro: "Nicio destinație nu are o copie completă confirmată. Nu formata cardul; vezi detaliile și reia transferul.", .en: "No destination has a complete confirmed copy. Do not format the card; check the details and resume the transfer.", .es: "Ningún destino tiene una copia completa confirmada. No formatees la tarjeta; revisa los detalles y reanuda la transferencia."],
        "outcomeHelp.cancelled": [.ro: "Transferul a fost oprit. Fișierele confirmate până acum sunt păstrate; pornește din nou ca să reiei.", .en: "The transfer was stopped. Files confirmed so far are kept; start again to resume.", .es: "La transferencia se detuvo. Los archivos confirmados se conservan; inicia de nuevo para reanudar."],
        "destOutcome.verified": [.ro: "Verificat", .en: "Verified", .es: "Verificado"],
        "destOutcome.verifiedWithWarnings": [.ro: "Verificat, cu avertismente", .en: "Verified, with warnings", .es: "Verificado, con avisos"],
        "destOutcome.failed": [.ro: "Neconfirmat", .en: "Not confirmed", .es: "No confirmado"],
        "destOutcome.cancelled": [.ro: "Anulat", .en: "Cancelled", .es: "Cancelado"],
        "dest.disconnected": [.ro: "Deconectată", .en: "Disconnected", .es: "Desconectado"],
        "dest.inProgress": [.ro: "În lucru", .en: "In progress", .es: "En curso"],
        "dest.withErrors": [.ro: "Cu erori", .en: "With errors", .es: "Con errores"],
        "dest.remove": [.ro: "Elimină destinația", .en: "Remove destination", .es: "Quitar destino"],

        // Preflight
        "preflight.blockedStatus": [.ro: "Pornire blocată de preflight — vezi avertismentele.", .en: "Start blocked by preflight — see the warnings.", .es: "Inicio bloqueado por la comprobación previa — mira los avisos."],
        "preflight.noSources": [.ro: "Nicio sursă selectată.", .en: "No source selected.", .es: "Ningún origen seleccionado."],
        "preflight.noDestinations": [.ro: "Nicio destinație selectată.", .en: "No destination selected.", .es: "Ningún destino seleccionado."],
        "preflight.sourceMissing": [.ro: "Sursa nu mai există (card scos?).", .en: "The source no longer exists (card removed?).", .es: "El origen ya no existe (¿tarjeta extraída?)."],
        "preflight.destinationMissing": [.ro: "Destinația nu mai există (disc deconectat?).", .en: "The destination no longer exists (drive disconnected?).", .es: "El destino ya no existe (¿disco desconectado?)."],
        "preflight.destinationNotWritable": [.ro: "Destinația nu permite scrierea.", .en: "The destination is not writable.", .es: "El destino no permite escritura."],
        "preflight.destinationNotDirectory": [.ro: "Destinația nu e un folder.", .en: "The destination is not a folder.", .es: "El destino no es una carpeta."],
        "preflight.destinationInsideSource": [.ro: "Destinația se află în interiorul sursei.", .en: "The destination is inside the source.", .es: "El destino está dentro del origen."],
        "preflight.sourceInsideDestination": [.ro: "Sursa se află în interiorul destinației.", .en: "The source is inside the destination.", .es: "El origen está dentro del destino."],
        "preflight.sameAsSource": [.ro: "Destinația este chiar sursa.", .en: "The destination is the source itself.", .es: "El destino es el propio origen."],
        "preflight.duplicateDestination": [.ro: "Aceeași destinație e adăugată de două ori.", .en: "The same destination is added twice.", .es: "El mismo destino está añadido dos veces."],
        "preflight.nestedDestinations": [.ro: "O destinație se află în interiorul alteia.", .en: "One destination is inside another.", .es: "Un destino está dentro de otro."],
        "preflight.sameVolumeAsSource": [.ro: "Destinația e pe același disc cu sursa — nu e o copie de siguranță independentă.", .en: "The destination is on the same drive as the source — not an independent backup.", .es: "El destino está en el mismo disco que el origen — no es una copia de seguridad independiente."],
        "preflight.symlinkSource": [.ro: "Sursa este un link simbolic; se copiază conținutul țintei.", .en: "The source is a symbolic link; the target's content is copied.", .es: "El origen es un enlace simbólico; se copia el contenido del destino del enlace."],

        // Pregătire
        "prep.title": [.ro: "Ce va porni", .en: "What will run", .es: "Qué se ejecutará"],
        "prep.source": [.ro: "Sursă", .en: "Source", .es: "Origen"],
        "prep.destinations": [.ro: "Destinații", .en: "Destinations", .es: "Destinos"],
        "prep.folder": [.ro: "Folder rezultat", .en: "Result folder", .es: "Carpeta resultante"],
        "prep.method": [.ro: "Verificare", .en: "Verification", .es: "Verificación"],
        "prep.notes": [.ro: "Note", .en: "Notes", .es: "Notas"],
        "prep.noSource": [.ro: "Trage un card sau un folder în coloana Surse.", .en: "Drag a card or folder into the Sources column.", .es: "Arrastra una tarjeta o carpeta a la columna Orígenes."],
        "prep.noDestination": [.ro: "Trage un disc în coloana Destinații.", .en: "Drag a drive into the Destinations column.", .es: "Arrastra un disco a la columna Destinos."],
        "prep.free": [.ro: "%@ liberi din %@", .en: "%@ free of %@", .es: "%@ libres de %@"],
        "prep.freeShort": [.ro: "%@ liberi", .en: "%@ free", .es: "%@ libres"],
        "prep.weakVerification": [.ro: "Verificare slabă", .en: "Weak verification", .es: "Verificación débil"],

        "prep.checks": [.ro: "Verificări", .en: "Checks", .es: "Comprobaciones"],
        "prep.check.noOverlap": [.ro: "Sursa și destinațiile nu se suprapun", .en: "Source and destinations do not overlap", .es: "Origen y destinos no se solapan"],
        "prep.check.spaceOk": [.ro: "Spațiu suficient la fiecare destinație", .en: "Enough space at every destination", .es: "Espacio suficiente en cada destino"],
        "prep.check.spaceLow": [.ro: "Spațiu insuficient — pornirea va cere confirmare", .en: "Not enough space — starting will ask for confirmation", .es: "Espacio insuficiente — el inicio pedirá confirmación"],
        "prep.check.checksum": [.ro: "Fiecare copie e comparată cu sursa prin checksum", .en: "Every copy is compared with the source by checksum", .es: "Cada copia se compara con el origen por checksum"],
        "prep.state.ready": [.ro: "Gata de pornire", .en: "Ready to start", .es: "Listo para iniciar"],
        "prep.state.warnings": [.ro: "Gata, cu avertismente", .en: "Ready, with warnings", .es: "Listo, con avisos"],
        "prep.state.blocked": [.ro: "Blocat", .en: "Blocked", .es: "Bloqueado"],
        "prep.state.incomplete": [.ro: "Incomplet", .en: "Incomplete", .es: "Incompleto"],

        // Monitor
        "monitor.phase": [.ro: "Faza", .en: "Phase", .es: "Fase"],
        "monitor.total": [.ro: "Progres total", .en: "Total progress", .es: "Progreso total"],
        "monitor.currentFile": [.ro: "Fișier curent", .en: "Current file", .es: "Archivo actual"],
        "monitor.read": [.ro: "Citire sursă", .en: "Source read", .es: "Lectura del origen"],
        "monitor.write": [.ro: "Scriere totală", .en: "Total write", .es: "Escritura total"],
        "monitor.copies": [.ro: "%d copii simultane", .en: "%d simultaneous copies", .es: "%d copias simultáneas"],
        "monitor.eta": [.ro: "Timp rămas", .en: "Time remaining", .es: "Tiempo restante"],
        "monitor.elapsed": [.ro: "scurs", .en: "elapsed", .es: "transcurrido"],
        "monitor.data": [.ro: "Date procesate", .en: "Data processed", .es: "Datos procesados"],
        "monitor.files": [.ro: "Fișiere × destinații", .en: "Files × destinations", .es: "Archivos × destinos"],
        "monitor.memory": [.ro: "Memorie aplicație", .en: "App memory", .es: "Memoria de la app"],
        "monitor.confirmed": [.ro: "%d fișiere confirmate · %@", .en: "%d files confirmed · %@", .es: "%d archivos confirmados · %@"],
        "monitor.failedFiles": [.ro: "%d neconfirmate", .en: "%d not confirmed", .es: "%d sin confirmar"],

        // Rezultat
        "result.filesConfirmed": [.ro: "Fișiere confirmate", .en: "Files confirmed", .es: "Archivos confirmados"],
        "result.acrossDestinations": [.ro: "însumat pe destinații", .en: "summed across destinations", .es: "sumados en todos los destinos"],
        "result.notConfirmed": [.ro: "Neconfirmate", .en: "Not confirmed", .es: "Sin confirmar"],
        "result.duration": [.ro: "Durată", .en: "Duration", .es: "Duración"],
        "result.newTransfer": [.ro: "Transfer nou", .en: "New transfer", .es: "Nueva transferencia"],
        "result.openFolder": [.ro: "Deschide folderul", .en: "Open folder", .es: "Abrir carpeta"],
        "result.ok": [.ro: "confirmate", .en: "confirmed", .es: "confirmados"],
        "result.skipped": [.ro: "deja existente", .en: "already present", .es: "ya existentes"],
        "result.failed": [.ro: "neconfirmate", .en: "not confirmed", .es: "sin confirmar"],
        "result.recovered": [.ro: "recuperate la reîncercare", .en: "recovered on retry", .es: "recuperados al reintentar"],

        // Jurnal
        "log.title": [.ro: "Jurnal tehnic", .en: "Technical log", .es: "Registro técnico"],
        "log.filter": [.ro: "Filtrează", .en: "Filter", .es: "Filtrar"],
        "log.copy": [.ro: "Copiază", .en: "Copy", .es: "Copiar"],
        "log.toggleHint": [.ro: "Arată sau ascunde jurnalul", .en: "Shows or hides the log", .es: "Muestra u oculta el registro"],

        // Settings
        "settings.open": [.ro: "Setări", .en: "Settings", .es: "Ajustes"],
        "settingsTab.general": [.ro: "General", .en: "General", .es: "General"],
        "settingsTab.verification": [.ro: "Verificare", .en: "Verification", .es: "Verificación"],
        "settingsTab.reports": [.ro: "Rapoarte", .en: "Reports", .es: "Informes"],
        "settingsTab.performance": [.ro: "Performanță", .en: "Performance", .es: "Rendimiento"],
        "settingsTab.cloud": [.ro: "Cloud", .en: "Cloud", .es: "Nube"],
        "settingsTab.account": [.ro: "Cont", .en: "Account", .es: "Cuenta"],
        "settings.readBack": [.ro: "Recitește destinația de pe disc după copiere", .en: "Read the destination back from disk after copying", .es: "Releer el destino del disco tras copiar"],
        "settings.readBackHelp": [.ro: "Mai lent: după copiere, fiecare destinație se citește încă o dată prin sistemul de fișiere, cerând ocolirea memoriei cache (F_NOCACHE), iar rezultatul se compară separat cu sursa. Paginile deja în memorie sau cache-ul intern al discului pot servi totuși citirea; dacă volumul refuză F_NOCACHE, jurnalul o spune.", .en: "Slower: after copying, each destination is read again through the file system, asking to bypass the cache (F_NOCACHE), and the result is compared with the source separately. Pages already in memory or the drive's own cache may still serve the read; if the volume refuses F_NOCACHE, the log says so.", .es: "Más lento: tras copiar, cada destino se vuelve a leer a través del sistema de archivos, pidiendo evitar la caché (F_NOCACHE), y el resultado se compara con el origen por separado. Las páginas ya en memoria o la caché interna del disco pueden servir igualmente la lectura; si el volumen rechaza F_NOCACHE, el registro lo indica."],
        "settings.resumeHelp": [.ro: "Un checkpoint făcut cu alt algoritm sau pentru alt folder e ignorat; fișierele lipsă sau modificate se recopiază.", .en: "A checkpoint made with another algorithm or for another folder is ignored; missing or changed files are copied again.", .es: "Un checkpoint hecho con otro algoritmo o para otra carpeta se ignora; los archivos que faltan o cambiaron se vuelven a copiar."],
        "settings.exclusionsHelp": [.ro: "Fișierele ascunse (care încep cu punct) sunt mereu excluse.", .en: "Hidden files (starting with a dot) are always excluded.", .es: "Los archivos ocultos (que empiezan por punto) siempre se excluyen."],
        "settings.ejectWhenDoneHelp2": [.ro: "Doar când fiecare destinație are o copie confirmată. La orice eroare sau anulare, cardul rămâne montat.", .en: "Only when every destination has a confirmed copy. On any error or cancellation, the card stays mounted.", .es: "Solo cuando cada destino tiene una copia confirmada. Ante cualquier error o cancelación, la tarjeta queda montada."],
        "settings.ioHelp": [.ro: "Buffer mai mic = mai puțină memorie. Limita RAM face pauză între fișiere când memoria aplicației o depășește.", .en: "Smaller buffer = less memory. The RAM limit pauses between files when the app's memory exceeds it.", .es: "Búfer menor = menos memoria. El límite de RAM pausa entre archivos cuando la memoria de la app lo supera."],
        "settings.cloudAccount": [.ro: "Cont", .en: "Account", .es: "Cuenta"],
        "settings.logo": [.ro: "Logo în rapoarte", .en: "Logo in reports", .es: "Logo en los informes"],
        "settings.remove": [.ro: "Elimină", .en: "Remove", .es: "Quitar"],
        "settings.show": [.ro: "Arată", .en: "Show", .es: "Mostrar"],
        "settings.hide": [.ro: "Ascunde", .en: "Hide", .es: "Ocultar"],
        "settings.licenseStatus": [.ro: "Stare licență", .en: "License status", .es: "Estado de la licencia"],
        "settings.version": [.ro: "Versiune", .en: "Version", .es: "Versión"],
        "profiles.delete": [.ro: "Șterge profil", .en: "Delete profile", .es: "Eliminar perfil"],

        // Temă
        "theme.system": [.ro: "Sistem", .en: "System", .es: "Sistema"],
        "theme.light": [.ro: "Luminos", .en: "Light", .es: "Claro"],
        "theme.dark": [.ro: "Întunecat", .en: "Dark", .es: "Oscuro"],
    ]
}
