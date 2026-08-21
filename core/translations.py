"""
translations.py
----------------
Traduceri pentru interfata DataMover (RO/EN/ES). Fisier fara
dependinte externe - doar date + o functie mica de ajutor.

Acopera: bara de sus, etichete de sectiuni, tooltip-uri, mesaje de
eroare/confirmare, fereastra "Despre", meniul Help si mesajele de
self-update.

NU acopera liniile interne de jurnal generate de offload_engine.py in
timpul copierii (ex. "Copiere: nume_fisier.jpg") - acelea raman in
romana, fiind generate pe un thread separat, fara acces direct la limba
curenta a interfetei. O extindere ulterioara ar putea trece limba si
catre motorul de copiere, daca e nevoie.
"""

TRANSLATIONS = {
    "ro": {
        "app_title": "DataMover",
        "trial_badge": "🕐 Proba: {days} zile ramase",
        "activate_now": "Activeaza licenta...",
        "dark_mode": "Tema intunecata",
        "about": "Despre...",
        "check_updates": "🔍 Verifica actualizari",
        "history": "🕘 Istoric",
        "history_title": "Istoric sesiuni",
        "history_empty": "Nicio sesiune de offload inca. Dupa prima copiere, apare aici.",
        "history_col_date": "Data",
        "history_col_project": "Proiect",
        "history_col_card": "Card",
        "history_col_dest": "Destinatii",
        "history_col_model": "Model verificare",
        "history_col_result": "Rezultat",
        "history_result": "{ok} OK, {fail} probleme",
        "history_result_cancelled": "Anulat ({ok} OK)",
        "start_monitor": "Porneste modul Monitorizare...",
        "resume": "Reia ultima copiere neterminata...",
        "language": "Limba",
        "help_menu": "Help",
        "help_guide": "Ghid DataMover...",
        "help_about": "Despre DataMover...",

        "source_label": "Sursa (card / drive de offload)",
        "source_volumes": "Volume detectate automat:",
        "source_refresh": "Reimprospateaza",
        "source_manual": "Alege manual...",
        "source_dnd": "(sau trage un folder aici din Finder)",
        "source_dnd_unavailable": "(drag-and-drop indisponibil - vezi CITESTE-MA.md pentru activare)",

        "meta_label": "Denumire automata folder (Data_Proiect_Card)",
        "meta_project": "Nume proiect:",
        "meta_card": "Eticheta card:",
        "meta_clear": "Proiect nou",

        "opts_label": "Optiuni de copiere",
        "opts_security": "Model de securitate (verificare):",
        "opts_exclusions": "Exclude fisiere/extensii (separate prin virgula):",
        "opts_skip": "Sari peste fisiere deja identice la destinatie (economiseste timp la re-rulari)",
        "opts_eject": "Ejecteaza cardul sursa dupa finalizare (doar pe Mac)",

        "dest_label": "Destinatii (poti adauga oricate, copiere simultana)",
        "dest_add": "Adauga destinatie...",
        "dest_remove": "Sterge selectia",
        "preset_label": "Presetare:",
        "preset_save": "Salveaza ca presetare",
        "preset_delete": "Sterge presetarea",
        "preset_name_prompt": "Nume presetare (ex. \"Standard\", \"Arhiva client X\"):",
        "preset_applied": "Presetare aplicata: {name}",
        "preset_saved": "Presetare salvata: {name}",
        "preset_none_selected": "Alege intai o presetare din lista.",
        "preset_delete_confirm": "Stergi definitiv presetarea \"{name}\"?",
        "dest_dnd": "(sau trage unul sau mai multe foldere aici din Finder)",
        "dest_dnd_unavailable": "(drag-and-drop indisponibil - vezi CITESTE-MA.md pentru activare)",

        "progress_global": "Progres global",
        "progress_inactive": "Inactiv",
        "progress_preparing": "Se pregateste...",
        "progress_copy": "Copiere",
        "progress_verify": "Verificare",
        "progress_per_dest": "Progres per destinatie",
        "progress_placeholder": "(apar aici cand incepe o copiere)",
        "progress_waiting": "In asteptare...",

        "action_start": "Incepe offload-ul",
        "action_cancel": "Anuleaza",

        "log_label": "Jurnal",
        "btn_open_folder": "📂",

        "tooltip_verification": ("Modelul de securitate stabileste cum se verifica fiecare fisier dupa copiere:\n\n"
                                  "- Doar dimensiune: cel mai rapid, dar nu detecteaza coruperi subtile ale datelor.\n"
                                  "- MD5: rapid, standard in industrie.\n"
                                  "- SHA-1: putin mai lent, ceva mai sigur decat MD5.\n"
                                  "- SHA-256: recomandat pentru arhivare pe termen lung.\n"
                                  "- SHA-512: maxim de siguranta, dar cel mai lent."),
        "tooltip_exclusions": ("Lista de fisiere/extensii care NU vor fi copiate, separate prin virgula.\n\n"
                                "Poti folosi nume exacte (ex: Thumbs.db) sau extensii (ex: .tmp, .wav).\n"
                                "Fisierele ascunse de sistem (care incep cu punct) sunt excluse automat, "
                                "indiferent de aceasta lista."),
        "tooltip_skip": ("Daca e bifat, la o re-rulare peste acelasi folder de destinatie, fisierele "
                          "deja copiate SI verificate corect nu mai sunt recopiate - doar re-verificate "
                          "rapid (dimensiune identica) sau sarite. Util cand o copiere a fost intrerupta "
                          "si vrei sa completezi restul fara sa iei totul de la capat."),

        "verification_size_only": "Doar dimensiune fisier (fara checksum - cel mai rapid, mai putin sigur)",
        "verification_md5": "MD5 (rapid - standard in industrie)",
        "verification_sha1": "SHA-1 (echilibrat - putin mai sigur decat MD5)",
        "verification_sha256": "SHA-256 (sigur - recomandat pentru arhivare pe termen lung)",
        "verification_sha512": "SHA-512 (maxim de siguranta - cel mai lent)",

        "msg_error_title": "Eroare",
        "msg_warning_title": "Atentie",
        "msg_drop_source_only": "Te rog trage un folder (nu un fisier individual).",
        "msg_drop_dest_only": "Te rog trage unul sau mai multe foldere (nu fisiere individuale).",
        "msg_source_error": "Alege un folder sursa valid.",
        "msg_dest_error": "Adauga cel putin o destinatie.",
        "msg_no_files": "Nu am gasit niciun fisier relevant in sursa selectata (sau toate au fost excluse).",
        "msg_confirm_exit": "Un offload este in curs. Sigur vrei sa inchizi aplicatia? Copierea in desfasurare va fi intrerupta.",
        "msg_confirm_cancel": "Sigur vrei sa anulezi offload-ul in curs?",
        "msg_offload_cancelled_title": "DataMover",
        "msg_offload_cancelled": "Offload-ul a fost anulat.",
        "msg_offload_complete_ok": "Offload complet, toate fisierele verificate cu succes.",
        "msg_offload_complete_problems": ("Offload complet, dar cu {count} probleme. Verifica jurnalul si rapoartele PDF/CSV.\n\n"
                                           "Poti folosi 'Reia ultima copiere neterminata...' ca sa reincerci doar fisierele cu probleme."),
        "msg_space_warning_title": "Spatiu insuficient",
        "msg_space_warning": ("Spatiu liber insuficient pe urmatoarele destinatii:\n\n{details}\n\n"
                               "Vrei sa continui oricum?"),
        "msg_resume_title": "Reia copierea",
        "msg_resume_none_title": "Reluare",
        "msg_resume_none": "Nu am gasit nicio copiere neterminata pentru proiectul/cardul curent.",
        "msg_resume_details": ("Am gasit urmatoarele copieri neterminate:\n\n{details}\n\n"
                                "Vrei sa incepi offload-ul acum, reluand automat de unde a ramas "
                                "(fisierele deja verificate corect NU vor fi recopiate)?"),
        "msg_monitor_no_dest": ("Modul Monitorizare foloseste ultimele destinatii SALVATE. "
                                 "Adauga cel putin o destinatie si porneste un offload manual o data, "
                                 "apoi incearca din nou."),
        "msg_monitor_missing_exe": ("Nu gasesc executabilul 'DataMover Monitor' langa aplicatie.\n\n"
                                     "Verifica sa fi extras TOT continutul arhivei descarcate (.zip) - "
                                     "aplicatia principala si 'DataMover Monitor' trebuie sa ramana "
                                     "in acelasi folder, nu doar aplicatia mutata separat."),
        "msg_monitor_error": "Nu am putut porni modul Monitorizare: {error}",
        "msg_monitor_ready_title": "Modul Monitorizare",
        "msg_monitor_ready": ("Modulul de monitorizare a fost pornit intr-un proces separat "
                               "(iconita in system tray / menu bar). Poti inchide aceasta fereastra - "
                               "monitorizarea continua sa ruleze in fundal."),
        "msg_update_available_title": "Actualizare disponibila",
        "msg_update_available": ("Versiune noua disponibila: {version}\n\nCe este nou:\n{changes}\n\n"
                                  "Doresti sa descarci si sa instalezi acum? Aplicatia se va inchide si reporni automat."),
        "msg_update_mandatory": "Aceasta actualizare este obligatorie.\n\n",
        "msg_update_source_only": ("Este disponibila versiunea {version} (tu rulezi din sursa, versiunea curenta "
                                    "e {current}).\n\nCe e nou:\n{changes}\n\n"
                                    "Actualizarea automata functioneaza doar in aplicatia compilata (.app/.exe). "
                                    "Din sursa, actualizezi manual cu 'git pull'."),
        "msg_no_update": "Ai deja ultima versiune ({version}).",
        "msg_update_download_error": "Descarcare esuata: {error}",
        "msg_update_install_error": "Actualizare esuata: {error}",

        "about_title": "Despre DataMover",
        "about_version": "Versiune {version}",
        "about_creator": "Creat de {name}",
        "about_description": "Offload verificat de fisiere media, pentru Mac si Windows.",
        "about_close": "Inchide",
    },

    "en": {
        "app_title": "DataMover",
        "trial_badge": "🕐 Trial: {days} days left",
        "activate_now": "Activate license...",
        "dark_mode": "Dark theme",
        "about": "About...",
        "check_updates": "🔍 Check for updates",
        "history": "🕘 History",
        "history_title": "Session history",
        "history_empty": "No offload sessions yet. After your first copy, it'll show up here.",
        "history_col_date": "Date",
        "history_col_project": "Project",
        "history_col_card": "Card",
        "history_col_dest": "Destinations",
        "history_col_model": "Verification model",
        "history_col_result": "Result",
        "history_result": "{ok} OK, {fail} problems",
        "history_result_cancelled": "Cancelled ({ok} OK)",
        "start_monitor": "Start Monitor mode...",
        "resume": "Resume last incomplete copy...",
        "language": "Language",
        "help_menu": "Help",
        "help_guide": "DataMover Guide...",
        "help_about": "About DataMover...",

        "source_label": "Source (card / offload drive)",
        "source_volumes": "Detected volumes:",
        "source_refresh": "Refresh",
        "source_manual": "Choose manually...",
        "source_dnd": "(or drag a folder here from Finder)",
        "source_dnd_unavailable": "(drag-and-drop unavailable - see CITESTE-MA.md to enable it)",

        "meta_label": "Auto folder naming (Date_Project_Card)",
        "meta_project": "Project name:",
        "meta_card": "Card label:",
        "meta_clear": "New project",

        "opts_label": "Copy options",
        "opts_security": "Security model (verification):",
        "opts_exclusions": "Exclude files/extensions (comma-separated):",
        "opts_skip": "Skip already identical files at destination (saves time on re-runs)",
        "opts_eject": "Eject source card after completion (Mac only)",

        "dest_label": "Destinations (add as many as you like, copied simultaneously)",
        "dest_add": "Add destination...",
        "dest_remove": "Remove selected",
        "preset_label": "Preset:",
        "preset_save": "Save as preset",
        "preset_delete": "Delete preset",
        "preset_name_prompt": "Preset name (e.g. \"Standard\", \"Client X archive\"):",
        "preset_applied": "Preset applied: {name}",
        "preset_saved": "Preset saved: {name}",
        "preset_none_selected": "Pick a preset from the list first.",
        "preset_delete_confirm": "Permanently delete the preset \"{name}\"?",
        "dest_dnd": "(or drag one or more folders here from Finder)",
        "dest_dnd_unavailable": "(drag-and-drop unavailable - see CITESTE-MA.md to enable it)",

        "progress_global": "Global progress",
        "progress_inactive": "Inactive",
        "progress_preparing": "Preparing...",
        "progress_copy": "Copy",
        "progress_verify": "Verify",
        "progress_per_dest": "Progress per destination",
        "progress_placeholder": "(appear here when a copy starts)",
        "progress_waiting": "Waiting...",

        "action_start": "Start offload",
        "action_cancel": "Cancel",

        "log_label": "Log",
        "btn_open_folder": "📂",

        "tooltip_verification": ("The security model determines how each file is verified after copying:\n\n"
                                  "- Size only: fastest, but doesn't detect subtle data corruption.\n"
                                  "- MD5: fast, industry standard.\n"
                                  "- SHA-1: a bit slower, somewhat more secure than MD5.\n"
                                  "- SHA-256: recommended for long-term archiving.\n"
                                  "- SHA-512: maximum security, but the slowest."),
        "tooltip_exclusions": ("List of files/extensions that will NOT be copied, comma-separated.\n\n"
                                "You can use exact names (e.g. Thumbs.db) or extensions (e.g. .tmp, .wav).\n"
                                "Hidden system files (starting with a dot) are excluded automatically, "
                                "regardless of this list."),
        "tooltip_skip": ("If checked, on a re-run over the same destination folder, files already "
                          "copied AND correctly verified are not recopied - just re-verified quickly "
                          "(same size) or skipped. Useful when a copy was interrupted and you want to "
                          "finish the rest without starting over."),

        "verification_size_only": "File size only (no checksum - fastest, least secure)",
        "verification_md5": "MD5 (fast - industry standard)",
        "verification_sha1": "SHA-1 (balanced - a bit more secure than MD5)",
        "verification_sha256": "SHA-256 (secure - recommended for long-term archiving)",
        "verification_sha512": "SHA-512 (maximum security - slowest)",

        "msg_error_title": "Error",
        "msg_warning_title": "Warning",
        "msg_drop_source_only": "Please drag a folder (not an individual file).",
        "msg_drop_dest_only": "Please drag one or more folders (not individual files).",
        "msg_source_error": "Choose a valid source folder.",
        "msg_dest_error": "Add at least one destination.",
        "msg_no_files": "No relevant files found in the selected source (or all were excluded).",
        "msg_confirm_exit": "An offload is in progress. Are you sure you want to quit? The ongoing copy will be interrupted.",
        "msg_confirm_cancel": "Are you sure you want to cancel the ongoing offload?",
        "msg_offload_cancelled_title": "DataMover",
        "msg_offload_cancelled": "The offload was cancelled.",
        "msg_offload_complete_ok": "Offload complete, all files verified successfully.",
        "msg_offload_complete_problems": ("Offload complete, but with {count} problems. Check the log and the PDF/CSV reports.\n\n"
                                           "You can use 'Resume last incomplete copy...' to retry only the problem files."),
        "msg_space_warning_title": "Insufficient space",
        "msg_space_warning": ("Insufficient free space on the following destinations:\n\n{details}\n\n"
                               "Do you want to continue anyway?"),
        "msg_resume_title": "Resume copy",
        "msg_resume_none_title": "Resume",
        "msg_resume_none": "No incomplete copy found for the current project/card.",
        "msg_resume_details": ("Found the following incomplete copies:\n\n{details}\n\n"
                                "Do you want to start the offload now, automatically resuming from where "
                                "it left off (already-verified files will NOT be recopied)?"),
        "msg_monitor_no_dest": ("Monitor mode uses the last SAVED destinations. "
                                 "Add at least one destination and run a manual offload once, "
                                 "then try again."),
        "msg_monitor_missing_exe": ("Can't find the 'DataMover Monitor' executable next to the app.\n\n"
                                     "Make sure you extracted the ENTIRE downloaded archive (.zip) - "
                                     "the main app and 'DataMover Monitor' need to stay in the same "
                                     "folder, not just the app moved separately."),
        "msg_monitor_error": "Could not start Monitor mode: {error}",
        "msg_monitor_ready_title": "Monitor mode",
        "msg_monitor_ready": ("Monitor mode was started in a separate process "
                               "(icon in the system tray / menu bar). You can close this window - "
                               "monitoring keeps running in the background."),
        "msg_update_available_title": "Update available",
        "msg_update_available": ("New version available: {version}\n\nWhat's new:\n{changes}\n\n"
                                  "Do you want to download and install it now? The app will quit and restart automatically."),
        "msg_update_mandatory": "This update is mandatory.\n\n",
        "msg_update_source_only": ("Version {version} is available (you're running from source, current "
                                    "version is {current}).\n\nWhat's new:\n{changes}\n\n"
                                    "Automatic updates only work in the compiled app (.app/.exe). "
                                    "From source, update manually with 'git pull'."),
        "msg_no_update": "You already have the latest version ({version}).",
        "msg_update_download_error": "Download failed: {error}",
        "msg_update_install_error": "Update failed: {error}",

        "about_title": "About DataMover",
        "about_version": "Version {version}",
        "about_creator": "Created by {name}",
        "about_description": "Verified media file offload, for Mac and Windows.",
        "about_close": "Close",
    },

    "es": {
        "app_title": "DataMover",
        "trial_badge": "🕐 Prueba: {days} días restantes",
        "activate_now": "Activar licencia...",
        "dark_mode": "Tema oscuro",
        "about": "Acerca de...",
        "check_updates": "🔍 Buscar actualizaciones",
        "history": "🕘 Historial",
        "history_title": "Historial de sesiones",
        "history_empty": "Aun no hay sesiones de offload. Despues de la primera copia, aparecera aqui.",
        "history_col_date": "Fecha",
        "history_col_project": "Proyecto",
        "history_col_card": "Tarjeta",
        "history_col_dest": "Destinos",
        "history_col_model": "Modelo de verificacion",
        "history_col_result": "Resultado",
        "history_result": "{ok} OK, {fail} problemas",
        "history_result_cancelled": "Cancelado ({ok} OK)",
        "start_monitor": "Iniciar modo Monitor...",
        "resume": "Reanudar ultima copia incompleta...",
        "language": "Idioma",
        "help_menu": "Ayuda",
        "help_guide": "Guia de DataMover...",
        "help_about": "Acerca de DataMover...",

        "source_label": "Fuente (tarjeta / unidad de offload)",
        "source_volumes": "Volumenes detectados:",
        "source_refresh": "Actualizar",
        "source_manual": "Elegir manualmente...",
        "source_dnd": "(o arrastra una carpeta aqui desde Finder)",
        "source_dnd_unavailable": "(arrastrar y soltar no disponible - ver CITESTE-MA.md para activarlo)",

        "meta_label": "Nombre automatico de carpeta (Fecha_Proyecto_Tarjeta)",
        "meta_project": "Nombre del proyecto:",
        "meta_card": "Etiqueta de tarjeta:",
        "meta_clear": "Proyecto nuevo",

        "opts_label": "Opciones de copia",
        "opts_security": "Modelo de seguridad (verificacion):",
        "opts_exclusions": "Excluir archivos/extensiones (separados por comas):",
        "opts_skip": "Saltar archivos ya identicos en el destino (ahorra tiempo en re-ejecuciones)",
        "opts_eject": "Expulsar la tarjeta origen al finalizar (solo Mac)",

        "dest_label": "Destinos (agrega los que quieras, copia simultanea)",
        "dest_add": "Agregar destino...",
        "dest_remove": "Eliminar seleccion",
        "preset_label": "Preajuste:",
        "preset_save": "Guardar como preajuste",
        "preset_delete": "Eliminar preajuste",
        "preset_name_prompt": "Nombre del preajuste (ej. \"Estandar\", \"Archivo cliente X\"):",
        "preset_applied": "Preajuste aplicado: {name}",
        "preset_saved": "Preajuste guardado: {name}",
        "preset_none_selected": "Elige primero un preajuste de la lista.",
        "preset_delete_confirm": "Eliminar definitivamente el preajuste \"{name}\"?",
        "dest_dnd": "(o arrastra una o mas carpetas aqui desde Finder)",
        "dest_dnd_unavailable": "(arrastrar y soltar no disponible - ver CITESTE-MA.md para activarlo)",

        "progress_global": "Progreso global",
        "progress_inactive": "Inactivo",
        "progress_preparing": "Preparando...",
        "progress_copy": "Copiando",
        "progress_verify": "Verificando",
        "progress_per_dest": "Progreso por destino",
        "progress_placeholder": "(aparecen aqui cuando comienza una copia)",
        "progress_waiting": "Esperando...",

        "action_start": "Iniciar offload",
        "action_cancel": "Cancelar",

        "log_label": "Registro",
        "btn_open_folder": "📂",

        "tooltip_verification": ("El modelo de seguridad determina como se verifica cada archivo despues de copiar:\n\n"
                                  "- Solo tamano: el mas rapido, pero no detecta corrupcion sutil de datos.\n"
                                  "- MD5: rapido, estandar en la industria.\n"
                                  "- SHA-1: un poco mas lento, algo mas seguro que MD5.\n"
                                  "- SHA-256: recomendado para archivar a largo plazo.\n"
                                  "- SHA-512: maxima seguridad, pero el mas lento."),
        "tooltip_exclusions": ("Lista de archivos/extensiones que NO se copiaran, separados por comas.\n\n"
                                "Puedes usar nombres exactos (ej. Thumbs.db) o extensiones (ej. .tmp, .wav).\n"
                                "Los archivos ocultos del sistema (que empiezan con punto) se excluyen "
                                "automaticamente, sin importar esta lista."),
        "tooltip_skip": ("Si esta marcado, en una re-ejecucion sobre la misma carpeta de destino, los "
                          "archivos ya copiados Y verificados correctamente no se recopian - solo se "
                          "re-verifican rapido (mismo tamano) o se saltan. Util cuando una copia se "
                          "interrumpio y quieres terminar el resto sin empezar de nuevo."),

        "verification_size_only": "Solo tamano de archivo (sin checksum - el mas rapido, menos seguro)",
        "verification_md5": "MD5 (rapido - estandar en la industria)",
        "verification_sha1": "SHA-1 (equilibrado - algo mas seguro que MD5)",
        "verification_sha256": "SHA-256 (seguro - recomendado para archivar a largo plazo)",
        "verification_sha512": "SHA-512 (maxima seguridad - el mas lento)",

        "msg_error_title": "Error",
        "msg_warning_title": "Atencion",
        "msg_drop_source_only": "Arrastra una carpeta (no un archivo individual).",
        "msg_drop_dest_only": "Arrastra una o mas carpetas (no archivos individuales).",
        "msg_source_error": "Elige una carpeta de origen valida.",
        "msg_dest_error": "Agrega al menos un destino.",
        "msg_no_files": "No se encontraron archivos relevantes en el origen seleccionado (o todos fueron excluidos).",
        "msg_confirm_exit": "Hay un offload en curso. ¿Seguro que quieres cerrar la aplicacion? La copia en curso se interrumpira.",
        "msg_confirm_cancel": "¿Seguro que quieres cancelar el offload en curso?",
        "msg_offload_cancelled_title": "DataMover",
        "msg_offload_cancelled": "El offload fue cancelado.",
        "msg_offload_complete_ok": "Offload completo, todos los archivos verificados con exito.",
        "msg_offload_complete_problems": ("Offload completo, pero con {count} problemas. Revisa el registro y los informes PDF/CSV.\n\n"
                                           "Puedes usar 'Reanudar ultima copia incompleta...' para reintentar solo los archivos con problemas."),
        "msg_space_warning_title": "Espacio insuficiente",
        "msg_space_warning": ("Espacio libre insuficiente en los siguientes destinos:\n\n{details}\n\n"
                               "¿Quieres continuar de todas formas?"),
        "msg_resume_title": "Reanudar copia",
        "msg_resume_none_title": "Reanudar",
        "msg_resume_none": "No se encontro ninguna copia incompleta para el proyecto/tarjeta actual.",
        "msg_resume_details": ("Se encontraron las siguientes copias incompletas:\n\n{details}\n\n"
                                "¿Quieres iniciar el offload ahora, reanudando automaticamente desde donde "
                                "quedo (los archivos ya verificados NO se recopiaran)?"),
        "msg_monitor_no_dest": ("El modo Monitor usa los ultimos destinos GUARDADOS. "
                                 "Agrega al menos un destino y ejecuta un offload manual una vez, "
                                 "luego intenta de nuevo."),
        "msg_monitor_missing_exe": ("No encuentro el ejecutable 'DataMover Monitor' junto a la aplicacion.\n\n"
                                     "Verifica haber extraido TODO el contenido del archivo descargado (.zip) - "
                                     "la app principal y 'DataMover Monitor' deben quedar en la misma "
                                     "carpeta, no solo la app movida por separado."),
        "msg_monitor_error": "No se pudo iniciar el modo Monitor: {error}",
        "msg_monitor_ready_title": "Modo Monitor",
        "msg_monitor_ready": ("El modo Monitor se inicio en un proceso separado "
                               "(icono en la bandeja del sistema / barra de menus). Puedes cerrar esta "
                               "ventana - el monitoreo sigue funcionando en segundo plano."),
        "msg_update_available_title": "Actualizacion disponible",
        "msg_update_available": ("Nueva version disponible: {version}\n\nNovedades:\n{changes}\n\n"
                                  "¿Quieres descargarla e instalarla ahora? La app se cerrara y reiniciara automaticamente."),
        "msg_update_mandatory": "Esta actualizacion es obligatoria.\n\n",
        "msg_update_source_only": ("La version {version} esta disponible (estas ejecutando desde el codigo "
                                    "fuente, la version actual es {current}).\n\nNovedades:\n{changes}\n\n"
                                    "Las actualizaciones automaticas solo funcionan en la app compilada "
                                    "(.app/.exe). Desde el codigo fuente, actualiza manualmente con 'git pull'."),
        "msg_no_update": "Ya tienes la ultima version ({version}).",
        "msg_update_download_error": "Descarga fallida: {error}",
        "msg_update_install_error": "Actualizacion fallida: {error}",

        "about_title": "Acerca de DataMover",
        "about_version": "Version {version}",
        "about_creator": "Creado por {name}",
        "about_description": "Offload verificado de archivos multimedia, para Mac y Windows.",
        "about_close": "Cerrar",
    },
}


def get_text(lang, key, **kwargs):
    """Returneaza textul tradus pentru o cheie, inlocuind parametrii
    {nume} din text. Cade automat pe romana daca limba sau cheia nu
    exista, si pe cheia bruta daca nici macar romana n-o are (nu ar
    trebui sa se intample, dar nu blocheaza interfata daca se intampla)."""
    lang_dict = TRANSLATIONS.get(lang, TRANSLATIONS["ro"])
    text = lang_dict.get(key, TRANSLATIONS["ro"].get(key, key))
    if kwargs:
        try:
            text = text.format(**kwargs)
        except (KeyError, ValueError):
            pass
    return text
