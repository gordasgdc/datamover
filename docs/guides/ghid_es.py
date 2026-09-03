# -*- coding: utf-8 -*-
"""Contenido de la guía en español. Ver _engine.py para los tipos de bloque."""

ES = {
    "cover_subtitle": "Guía de uso completa, paso a paso",
    "cover_version_label": "Versión",
    "cover_lang_label": "Español",
    "footer": "DataMover — Guía de uso",
    "title": "DataMover — Guía de uso",
    "subtitle": "Instalación, activación, cada opción explicada, resolución de problemas — por Cristi Gordas",
    "note": "Guía para la aplicación nativa de macOS (SwiftUI) y para la de Windows (WPF). Todo lo descrito "
            "aquí funciona igual en ambas plataformas, salvo donde se indique explícitamente.",
    "toc_title": "Índice",
    "sections": [

    {"h": "Qué es DataMover y para quién está hecho", "blocks": [
        ("p", "DataMover copia los archivos de una tarjeta de cámara (o de cualquier carpeta) a <b>varios "
              "destinos a la vez</b> y verifica, archivo por archivo, que lo que ha llegado es idéntico bit "
              "a bit a lo que había en la tarjeta. Al terminar deja la prueba junto a los datos: informes "
              "CSV, PDF y HTML, además de un archivo MHL que leen los programas profesionales de "
              "postproducción."),
        ("p", "Está pensado para el momento más arriesgado de un día de rodaje: justo antes de que alguien "
              "formatee la tarjeta. Hasta que no tengas la certeza de que el material llegó intacto a al "
              "menos dos sitios, esa tarjeta no se vacía."),
        ("img", ("ui-main-dark.png", "La ventana principal — Orígenes (izquierda), Discos detectados (centro), Destinos (derecha)")),
        ("h2", "Qué hace, en resumen"),
        ("ul", [
            "Copia a tantos destinos como quieras a la vez — todos se completan en paralelo, no uno tras otro.",
            "Verifica la integridad con xxHash64 (por defecto, el más rápido), MD5, SHA-1, SHA-256, SHA-512 o solo por tamaño.",
            "Escribe un archivo MHL (Media Hash List) junto a los datos — el certificado que leen Silverstack, YoYotta, ShotPut Pro y las casas de post.",
            "Genera informes CSV, PDF y HTML, con tu logo y los datos de producción en la cabecera.",
            "Reanuda una transferencia interrumpida exactamente donde se quedó (checkpoint).",
            "Reintenta por su cuenta los archivos fallidos antes de declarar un problema.",
            "Comprueba el espacio libre antes de copiar el primer byte.",
            "Descarga varias tarjetas seguidas, sin supervisión (cola de tarjetas).",
            "Reconoce las estructuras de tarjeta RED, ARRI, Sony, Panasonic, Canon y Blackmagic.",
            "Expulsa la tarjeta y te avisa cuando ha terminado.",
            "Interfaz completa en rumano, inglés y español, con tema claro u oscuro.",
        ]),
        ("info", ("Conviene saberlo", "El código fuente es público en GitHub bajo licencia MIT. Tras la "
                  "prueba gratuita, la aplicación compilada necesita un código de activación ligado a tu "
                  "ordenador — ver capítulo 4.")),
    ]},

    {"h": "Instalación en macOS", "blocks": [
        ("p", "La aplicación está firmada con un certificado Apple Developer ID, notarizada por Apple y "
              "sellada (stapled). Eso significa que macOS la acepta directamente, como cualquier aplicación "
              "distribuida comercialmente."),
        ("steps", [
            "Entra en <b>gordas.dev/datamover</b> y pulsa <b>Descargar para Mac</b>. Se descarga el archivo "
            "<b>DataMover-Mac.zip</b>.",
            "Abre el archivo comprimido (doble clic). Dentro hay tres archivos: el paquete de instalación "
            "<b>DataMover-2.11.1.pkg</b>, el desinstalador <b>Dezinstalare_DataMover.command</b> y esta "
            "guía en PDF.",
            "Doble clic en el archivo <b>.pkg</b>. Se abre el instalador de macOS.",
            "Lee y acepta los términos de licencia (<b>Agree</b>), luego pulsa <b>Continuar</b> e "
            "<b>Instalar</b>.",
            "Introduce tu contraseña de Mac cuando te la pida — es la de tu cuenta, no una de la aplicación. "
            "No se ve mientras la escribes; pulsa Intro al terminar.",
            "Listo. La aplicación queda instalada directamente en la carpeta <b>Aplicaciones</b>. La "
            "encuentras con Spotlight (⌘+Espacio, escribe «DataMover») o en Launchpad.",
        ]),
        ("ok", ("No hace falta ningún comando en el Terminal",
                "Al estar el paquete notarizado por Apple, <b>no</b> aparece el mensaje «la aplicación está "
                "dañada», <b>no</b> hay que hacer clic derecho → Abrir y <b>no</b> hay que ejecutar "
                "<i>xattr -cr</i>. Si alguna guía antigua dice lo contrario, esa información está obsoleta.")),
        ("h2", "Si la aplicación no se movió a Aplicaciones"),
        ("p", "Si alguna vez la abres desde otro sitio (por ejemplo desde Descargas), en el primer arranque "
              "te ofrecerá moverse a Aplicaciones. Responde <b>Sí</b> — de lo contrario macOS la ejecuta en "
              "un modo aislado en el que algunos permisos no funcionan bien."),
    ]},

    {"h": "Instalación en Windows", "blocks": [
        ("steps", [
            "Entra en <b>gordas.dev/datamover</b> y pulsa <b>Descargar para Windows</b>. Se descarga "
            "<b>DataMover-WPF-Windows.zip</b>.",
            "Clic derecho en el archivo comprimido → <b>Extraer todo…</b> → <b>Extraer</b>. No ejecutes el "
            "programa desde dentro del comprimido.",
            "Doble clic en <b>DataMoverSetup.exe</b>.",
            "Windows puede mostrar un aviso de SmartScreen («Windows protegió su PC»), porque la aplicación "
            "es nueva y aún no tiene historial de descargas. Pulsa <b>Más información</b> → <b>Ejecutar de "
            "todas formas</b>.",
            "Confirma la ventana de <b>Control de cuentas de usuario (UAC)</b> — la instalación necesita "
            "permisos de administrador para escribir en Archivos de programa.",
            "Marca <b>I accept the agreement</b> (acepto los términos) y pulsa <b>Next</b> hasta "
            "<b>Install</b>.",
            "Listo. Tienes accesos directos en el Escritorio y en el menú Inicio. La desinstalación se hace "
            "normalmente desde <b>Configuración → Aplicaciones → Aplicaciones instaladas</b>.",
        ]),
        ("info", ("Dónde se instala", "En <b>C:\\Program Files\\DataMover</b>. Es una zona protegida por "
                  "Windows, y por eso la instalación y las actualizaciones piden confirmación de "
                  "administrador.")),
    ]},

    {"h": "Prueba gratuita, activación y donación", "blocks": [
        ("p", "Desde el primer arranque tienes <b>7 días de prueba gratuita</b> con todas las funciones "
              "activas. Durante la prueba hay una única limitación, pensada para que puedas probar con "
              "libertad sin que la aplicación pueda usarse en producción indefinidamente sin activar:"),
        ("warn", ("Límite de 2 GB por transferencia durante la prueba",
                  "Una transferencia cuyo tamaño total supere los 2 GB no se inicia; recibes un mensaje "
                  "explícito con la opción de activar. El límite se aplica a la <b>suma de todos los "
                  "archivos</b> de una transferencia, no a cada archivo por separado.")),
        ("h2", "Cómo consigues el código de activación"),
        ("steps", [
            "Abre <b>Ajustes</b> (la rueda dentada de la barra inferior) y baja hasta <b>Perfil y "
            "licencia</b>. Allí verás el <b>ID del ordenador</b> (Machine ID), con un botón <b>Copiar</b> "
            "al lado.",
            "Pulsa <b>Activar…</b>. Se abre la ventana de activación con el ID ya rellenado.",
            "Pulsa el botón verde de <b>WhatsApp</b> — se abre una conversación conmigo, con tu ID ya "
            "escrito en el mensaje. Envíalo.",
            "Te respondo con un código de activación personal, generado para <b>ese</b> ordenador. El código "
            "no funciona en otra máquina, aunque se comparta.",
            "Pega el código en el campo <b>Código de licencia</b> y pulsa <b>Activar</b>. Ya está — la "
            "aplicación arranca con normalidad a partir de entonces.",
        ]),
        ("p", "Los <b>23 €</b> son una <b>donación</b>, no un precio de lista: me ayudan a cubrir los costes "
              "de desarrollo (suscripciones, herramientas, certificados) y a seguir manteniendo y mejorando "
              "la aplicación. Si en la aplicación ves otra cantidad, es una oferta activa en ese momento — "
              "la cantidad que aparece en la ventana de activación es siempre la correcta."),
        ("info", ("¿Has cambiado de ordenador?", "Necesitas un código nuevo, porque el antiguo está ligado al "
                  "ID de la máquina anterior. Escríbeme de nuevo por WhatsApp con el ID nuevo.")),
        ("p", "Una vez introducido, tu código de activación queda guardado y visible en <b>Ajustes → Perfil "
              "y licencia</b>, con un botón para copiarlo — así lo tienes a mano si reinstalas el sistema."),
    ]},

    {"h": "La ventana principal, zona por zona", "blocks": [
        ("img", ("ui-main-dark.png", "Las tres columnas y las barras superior e inferior")),
        ("h2", "Barra superior"),
        ("opt", (("Elemento", "Qué hace"), [
            ("Proyecto", "El nombre de la producción. Entra en el nombre de la carpeta de destino y en la cabecera de los informes. Vacío, se convierte en «Proiect»."),
            ("Tarjeta", "El nombre de la tarjeta que se descarga (A001, CAM-B-02…). También entra en el nombre de la carpeta. Vacío significa «Card»."),
            ("Versión", "El número de versión instalada, arriba a la derecha. Compruébalo al reportar un problema."),
            ("Signo de interrogación", "Abre esta guía en PDF, desde la propia aplicación."),
        ])),
        ("h2", "Columna ORÍGENES (izquierda)"),
        ("p", "De aquí se lee. Puedes añadir un origen de tres formas: arrastrando una carpeta desde "
              "Finder/Explorador sobre la caja, arrastrando un icono de disco de la columna central, o con "
              "el botón de añadir. Puedes poner varios orígenes a la vez — todos acaban en la <b>misma</b> "
              "carpeta de destino. Si quieres que cada tarjeta tenga su propia carpeta, usa la cola de "
              "tarjetas (capítulo 9)."),
        ("p", "Bajo cada origen aparece, cuando procede, el tipo de tarjeta reconocido y el número de clips "
              "— ver capítulo 10."),
        ("h2", "Columna DISCOS (centro)"),
        ("p", "Todos los volúmenes conectados con su espacio libre, actualizados automáticamente cada pocos "
              "segundos. Arrastra un icono a la izquierda para usarlo como origen, a la derecha como "
              "destino. El deslizador de arriba a la derecha agranda o reduce los iconos."),
        ("h2", "Columna DESTINOS (derecha)"),
        ("p", "Aquí se escribe. Añade tantos destinos como quieras — discos externos, NAS, carpetas locales. "
              "Todos se completan <b>en paralelo</b>, y cada uno recibe su propio juego completo de informes."),
        ("h2", "Barra inferior"),
        ("opt", (("Elemento", "Qué hace"), [
            ("Texto de estado", "Qué está haciendo la aplicación ahora mismo: porcentaje, archivos hechos del total, velocidad actual."),
            ("Reloj", "Abre el historial de copias — ver capítulo 12."),
            ("Rueda dentada", "Abre el panel de ajustes — capítulo 7."),
            ("Cancelar", "Detiene la transferencia en curso. Los archivos ya copiados y verificados se quedan en el destino."),
            ("Iniciar", "Inicia la transferencia. Solo se activa cuando tienes al menos un origen y un destino."),
        ])),
        ("p", "Mientras corre una transferencia, un flujo de texto estilo terminal bajo la barra de progreso "
              "muestra exactamente qué archivo se está copiando o verificando. Importa sobre todo con "
              "archivos de vídeo grandes, donde el porcentaje puede quedarse quieto decenas de segundos y "
              "parece que la aplicación se ha colgado."),
    ]},

    {"h": "Una transferencia completa, paso a paso", "blocks": [
        ("steps", [
            "Conecta la tarjeta y el disco (o discos) de destino.",
            "Añade la tarjeta a <b>Orígenes</b> y el disco a <b>Destinos</b>.",
            "Rellena <b>Proyecto</b> y <b>Tarjeta</b> en la barra superior. (Opcional, pero recomendado: "
            "aparecen en el nombre de la carpeta y en los informes.)",
            "Abre <b>Ajustes</b> y revisa el modelo de verificación y el resto de opciones — capítulo 7. Se "
            "conservan entre transferencias, así que normalmente se configuran una sola vez.",
            "Pulsa <b>Iniciar</b>.",
            "La aplicación comprueba primero si la transferencia cabe en el destino. Si no, te dice "
            "exactamente cuánto espacio hace falta y cuánto hay libre, y te deja decidir si continúas igual.",
            "Se crea la carpeta de destino y cada archivo se copia y se verifica inmediatamente.",
            "Al final, los archivos que hayan fallado se reintentan automáticamente una vez.",
            "Se escriben los informes (CSV, PDF, HTML) y el archivo MHL, y recibes una notificación del "
            "sistema y un sonido. Si marcaste la opción, la tarjeta se expulsa sola.",
        ]),
        ("h2", "Pausa, reanudar, cancelar"),
        ("p", "<b>Pausa</b> detiene la transferencia <b>entre</b> archivos — el archivo en curso termina de "
              "copiarse, así que no se pierde nada. <b>Continuar</b> retoma exactamente donde se quedó. "
              "<b>Cancelar</b> detiene definitivamente, pero todo lo ya copiado y verificado sigue siendo "
              "válido en el destino y se reconoce en una reanudación posterior."),
        ("h2", "Si la carpeta ya existe"),
        ("p", "Cuando inicias una transferencia hacia una carpeta que ya existe y contiene archivos, la "
              "aplicación te pregunta qué quieres hacer:"),
        ("opt", (("Opción", "Qué ocurre"), [
            ("Reanudar", "Continúa la transferencia existente. Los archivos ya copiados correctamente se verifican y se omiten, no se vuelven a copiar. Es la opción adecuada en la mayoría de los casos."),
            ("Carpeta nueva", "Crea una carpeta aparte, con un número añadido al nombre — no toca nada de lo existente."),
            ("Sobrescribir", "Vacía por completo la carpeta existente y empieza de cero. Irreversible."),
            ("Cancelar", "No inicia nada."),
        ])),
        ("info", ("Por qué importa",
                  "Una transferencia de varias horas que cruza la medianoche, o que se reanuda al día "
                  "siguiente, recibiría si no un nombre de carpeta nuevo (la fecha cambió) y volvería a "
                  "copiarlo todo para nada. La aplicación busca primero una carpeta existente del mismo "
                  "proyecto y tarjeta, sea cual sea su fecha.")),
    ]},

    {"h": "Todos los ajustes, uno por uno", "blocks": [
        ("p", "Todas las opciones siguientes están en un único panel, que se abre con la rueda dentada de la "
              "barra inferior. Se guardan solas, al instante — no hay botón «Guardar»."),
        ("img", ("ui-settings-dark.png", "El panel de ajustes, en tema oscuro")),
        ("h2", "Idioma y aspecto"),
        ("opt", (("Ajuste", "Explicación"), [
            ("Idioma", "Rumano, inglés o español. Cambia al instante, sin reiniciar."),
            ("Aspecto", "Sistema, Claro u Oscuro. Independiente del tema del sistema operativo — puedes mantener la aplicación oscura aunque el resto del ordenador esté en claro."),
        ])),
        ("h2", "Modelo de verificación"),
        ("p", "Es el algoritmo con el que la aplicación confirma que el archivo del destino es idéntico al de "
              "la tarjeta. Calcula una «huella» del original y otra de la copia; si coinciden, la copia es "
              "con certeza correcta."),
        ("opt", (("Modelo", "Cuándo usarlo"), [
            ("xxHash64", "<b>Por defecto y recomendado.</b> Es la elección estándar de los ofloaders profesionales. Para detectar una copia corrupta es tan bueno como MD5, pero varias veces más rápido — en una tarjeta de cientos de gigas, la verificación es la parte lenta, no la copia."),
            ("MD5", "Rápido y muy extendido. Elígelo si alguien de tu cadena de producción pide MD5 explícitamente."),
            ("SHA-1", "Algo más lento que MD5, igualmente aceptado por el estándar MHL."),
            ("SHA-256", "Más riguroso, adecuado para archivo a largo plazo. <b>No</b> puede escribirse en un archivo MHL (no forma parte del estándar)."),
            ("SHA-512", "El más riguroso y el más lento. Tampoco entra en el MHL."),
            ("Solo tamaño", "Compara solo el tamaño, sin leer el contenido. El más rápido pero el menos seguro — un archivo corrupto del mismo tamaño pasa desapercibido. No genera MHL."),
        ])),
        ("h2", "Exclusiones"),
        ("p", "Archivos que no quieres copiar. Escribe un nombre exacto (<i>Thumbs.db</i>) o una extensión "
              "que empiece por punto (<i>.tmp</i>), separados por comas. Los archivos ocultos (nombres que "
              "empiezan por punto) se omiten automáticamente de todos modos."),
        ("h2", "Comportamiento de la transferencia"),
        ("opt", (("Ajuste", "Explicación"), [
            ("Reanudar automáticamente desde un checkpoint existente", "Si una transferencia se interrumpió, la continúa donde se quedó en vez de empezar de cero. Déjalo activado."),
            ("Abrir automáticamente la carpeta de destino al finalizar", "Abre Finder/Explorador en la carpeta creada en cuanto la transferencia termina bien."),
            ("Generar archivo MHL", "Escribe el certificado de integridad junto a los datos. Ver capítulo 11. Requiere xxHash64, MD5 o SHA-1."),
            ("Reintentar automáticamente los archivos fallidos", "Al final de la transferencia, los archivos con error o discrepancia se copian una vez más. La mayoría de los fallos en rodaje son transitorios: tarjeta movida en el lector, cable rozado, disco externo dormido."),
            ("Expulsar la tarjeta automáticamente al terminar", "Expulsa la tarjeta con seguridad tras una transferencia <b>completamente limpia</b>. Una tarjeta con errores nunca se expulsa automáticamente — puede que aún haga falta repetir desde ella."),
            ("Iniciar automáticamente al insertar una tarjeta", "Modo sin supervisión: la tarjeta insertada entra directamente en la cola y la descarga empieza sola. Requiere al menos un destino elegido de antemano."),
        ])),
        ("warn", ("Expulsar en Windows requiere permisos de administrador",
                  "Si la aplicación no los tiene, la tarjeta <b>no</b> se expulsa y aparece un mensaje "
                  "explícito en el flujo de actividad que te dice que la retires a mano. Nunca des por hecho "
                  "que se expulsó sin ver la confirmación.")),
        ("h2", "Producción e informes"),
        ("p", "Estos campos son opcionales, pero convierten el informe de un registro técnico en un "
              "documento de entrega que puedes enviar tal cual al productor o a la casa de post. Los campos "
              "vacíos no aparecen en el informe."),
        ("opt", (("Campo", "Dónde aparece"), [
            ("Cliente", "En la cabecera de los informes PDF y HTML."),
            ("Operador / DIT", "En la cabecera — quién hizo la descarga."),
            ("Cámara", "En la cabecera y, si lo usas en la plantilla, en el nombre de la carpeta."),
            ("Notas de rodaje", "Un bloque de texto libre, destacado en el informe. Se vacía en cada arranque, por ser específico de una transferencia."),
            ("Logo", "Una imagen PNG o JPG, mostrada en la cabecera del informe PDF e incrustada en el informe HTML."),
        ])),
        ("h2", "Plantilla del nombre de carpeta"),
        ("p", "Decide cómo se llama la carpeta creada en el destino. Bajo el campo tienes siempre una "
              "<b>vista previa</b> del nombre resultante, con los datos rellenados en ese momento."),
        ("opt", (("Token", "Se sustituye por"), [
            ("{data}", "La fecha de hoy, como 2026-09-03."),
            ("{ora}", "La hora de inicio, como 14-30."),
            ("{proiect}", "Lo que hayas escrito en el campo Proyecto (o «Proiect»)."),
            ("{card}", "Lo que hayas escrito en el campo Tarjeta (o «Card»)."),
            ("{camera}", "La Cámara de la sección Producción. Queda vacío si no lo rellenaste."),
            ("{operator}", "El Operador / DIT de la sección Producción."),
        ])),
        ("p", "La plantilla por defecto es <b>{data}_{proiect}_{card}</b> y produce exactamente el nombre que "
              "usaban las versiones anteriores, así que no tienes que cambiar nada si te sirve. Los espacios "
              "se convierten en guiones bajos y los caracteres no permitidos en un nombre de carpeta se "
              "eliminan automáticamente."),
        ("h2", "Destino secundario en la nube"),
        ("p", "Opcionalmente, además de los destinos locales, el material puede subirse también a una cuenta "
              "en la nube (Google Drive, Dropbox y los demás servicios que admite <i>rclone</i>). Solo se "
              "suben los archivos que pasaron la verificación local. Las cuentas son las ya configuradas en "
              "Master Control Studio Pro — aquí no hay que configurar nada aparte."),
        ("h2", "E/S y memoria"),
        ("p", "Controlan con qué intensidad usa la aplicación el disco y la memoria. Los cuatro preajustes "
              "cubren casi todas las situaciones; los campos de abajo son para el ajuste fino."),
        ("opt", (("Ajuste", "Explicación"), [
            ("Eco / equipo modesto", "Para portátiles antiguos, o cuando estás montando a la vez."),
            ("Estándar", "El equilibrio recomendado para la mayoría de los casos."),
            ("Alto rendimiento", "Para discos rápidos (SSD, RAID) y un ordenador que no hace nada más."),
            ("Extremo / producción RAW", "Para transferencias muy grandes de material RAW en hardware potente."),
            ("Búfer de copia", "Cuánto se lee del disco de una vez. Más grande es más rápido con archivos grandes, pero ocupa más memoria."),
            ("Límite de RAM", "El techo de memoria por encima del cual la aplicación se frena sola para no ahogar al sistema."),
        ])),
        ("h2", "Perfiles de transferencia"),
        ("p", "Si trabajas en varias producciones con ajustes distintos, puedes guardar la combinación actual "
              "(orígenes, destinos, modelo de verificación, exclusiones, búfer, RAM) con un nombre y "
              "recargarla con un clic."),
        ("h2", "Perfil y licencia"),
        ("p", "Nombre y correo opcionales, el ID del ordenador y el código de licencia guardado, cada uno con "
              "botón de copiar. Desde aquí también compruebas manualmente si hay una versión nueva."),
    ]},

    {"h": "Qué encuentras en el destino al terminar", "blocks": [
        ("p", "En la carpeta creada en el destino, junto a los archivos copiados, quedan estos documentos:"),
        ("opt", (("Archivo", "Para qué sirve"), [
            ("offload_report_….csv", "La lista <b>completa</b> de archivos, con la huella del origen y del destino, el estado y el error si lo hubo. Se abre en Excel o Numbers. Es el documento de referencia cuando algo no está claro."),
            ("offload_report_….pdf", "El mismo informe, formateado para leer y enviar: cabecera con los datos de tu producción y tu logo, resumen con colores, y luego todos los problemas más una muestra de los archivos correctos."),
            ("offload_report_….html", "La misma información, pero se abre en cualquier navegador, incluso en el móvil, y se envía por WhatsApp o correo sin perder el formato."),
            ("….mhl", "El certificado de integridad que leen los programas. Ver capítulo 11."),
            ("offload_checkpoint.json", "Archivo técnico, usado internamente para poder reanudar una transferencia interrumpida. No lo borres mientras la transferencia no haya terminado."),
        ])),
        ("h2", "Cómo se lee el estado de un archivo"),
        ("opt", (("Estado", "Qué significa"), [
            ("OK", "Copiado y verificado con éxito. La huella del origen coincide con la de la copia."),
            ("SARIT (omitido)", "Ya existía en el destino, con el mismo tamaño, y la verificación confirmó que es idéntico. No se volvió a copiar."),
            ("OK (reintentado)", "Falló en el primer intento pero funcionó en el segundo. El archivo está bien — pero conviene mirar el cable, el lector o el disco."),
            ("NEPOTRIVIRE (discrepancia)", "La copia tiene una huella distinta del original. El archivo del destino <b>no</b> es de fiar."),
            ("EROARE (error)", "La copia no pudo hacerse en absoluto. El motivo exacto está en la columna de error del CSV."),
        ])),
        ("warn", ("La regla de oro",
                  "Nunca formatees una tarjeta antes de mirar el informe. Si ves aunque sea una sola "
                  "<b>discrepancia</b> o un solo <b>error</b>, ese material solo existe todavía en la tarjeta.")),
    ]},

    {"h": "La cola de tarjetas y el modo sin supervisión", "blocks": [
        ("p", "Al final de un día con varias cámaras se juntan seis u ocho tarjetas. La cola las descarga una "
              "tras otra, cada una en <b>su propia carpeta</b>, sin que estés al lado del ordenador."),
        ("steps", [
            "Añade la tarjeta a Orígenes y escribe su nombre en el campo <b>Tarjeta</b>.",
            "Pulsa <b>+ Añadir a la cola</b>. La tarjeta sale de Orígenes (ha pasado a la cola) y aparece en "
            "la lista de abajo.",
            "Repite con cada tarjeta.",
            "Pulsa <b>Iniciar cola</b>. Las tarjetas se descargan por turno; al terminar una empieza "
            "automáticamente la siguiente.",
        ]),
        ("info", ("Qué ocurre si pulsas Cancelar",
                  "Se detiene <b>toda</b> la cola, no solo la tarjeta en curso. Si has pulsado Cancelar, lo "
                  "razonable es suponer que no quieres que empiece de inmediato la siguiente tarjeta.")),
        ("h2", "Inicio automático al insertar una tarjeta"),
        ("p", "Con esa opción activada en Ajustes, cualquier tarjeta recién conectada entra sola en la cola y "
              "la descarga empieza sin pulsar nada. Debes tener al menos un destino elegido de antemano; si "
              "no, la aplicación no tendría dónde copiar. El nombre del volumen pasa a ser el nombre de la "
              "tarjeta."),
    ]},

    {"h": "Reconocimiento de tarjetas de cámara", "blocks": [
        ("p", "Al añadir un origen, la aplicación mira su estructura de carpetas y te dice qué ha reconocido "
              "y cuántos clips ha encontrado. Reconoce <b>RED</b>, <b>ARRI</b>, <b>Sony XDCAM</b> y "
              "<b>XAVC</b>, <b>Panasonic P2</b> y <b>AVCHD</b>, <b>Canon</b>, <b>Blackmagic BRAW</b>, y las "
              "tarjetas de foto/vídeo corrientes con carpeta DCIM."),
        ("p", "El reconocimiento es puramente informativo — nunca bloquea una transferencia. Su función es "
              "detectar a tiempo los dos errores clásicos de rodaje:"),
        ("opt", (("Aviso", "Qué significa y qué hacer"), [
            ("Parece una SUBCARPETA de la tarjeta", "Has añadido solo una parte de la tarjeta (por ejemplo únicamente la carpeta de clips). Copiado así, pierdes los archivos de metadatos sin los cuales el material no se reensambla correctamente en el montaje. Quita el origen y añade la <b>raíz</b> de la tarjeta."),
            ("Archivos de 0 bytes", "Hay clips vacíos — señal de tarjeta sacada demasiado pronto de la cámara, o de tarjeta defectuosa. Revisa esos clips en la cámara antes de formatear."),
            ("La tarjeta parece vacía", "No se encontró ningún archivo de medios. Comprueba que has añadido el volumen correcto."),
        ])),
    ]},

    {"h": "El archivo MHL — la entrega a postproducción", "blocks": [
        ("p", "Un <b>MHL</b> (Media Hash List) es un archivo que contiene, para cada archivo copiado, su "
              "huella digital, su tamaño y su fecha. Es el equivalente a un acta de entrega, pero leída por "
              "una <b>máquina</b>, no por una persona."),
        ("p", "Por qué importa: dentro de seis meses, alguien en post puede coger el archivo MHL, abrirlo en "
              "Silverstack, YoYotta, ShotPut Pro o una herramienta similar, y verificar automáticamente que "
              "cada archivo del NAS o de la cinta LTO es idéntico bit a bit a lo que salió de la cámara el "
              "día del rodaje. Sin MHL, esa comprobación no se puede hacer."),
        ("ul", [
            "Se escribe automáticamente en la raíz de la carpeta de destino, junto a los datos.",
            "Contiene rutas <b>relativas</b>, así que la carpeta puede moverse a otro disco sin invalidarlo.",
            "Contiene <b>solo</b> los archivos que pasaron la verificación. Un archivo dudoso no tiene sitio "
            "en un certificado.",
            "Requiere xxHash64, MD5 o SHA-1. Con SHA-256 o SHA-512 la transferencia y los informes siguen "
            "estando completos, pero no se genera MHL (esos dos no forman parte del estándar) — verás un "
            "mensaje explícito en el flujo de actividad.",
        ]),
        ("info", ("Compatibilidad Mac ↔ Windows",
                  "Un MHL escrito en Mac puede verificarse en Windows y viceversa: ambas versiones de la "
                  "aplicación producen exactamente la misma huella para el mismo archivo.")),
    ]},

    {"h": "Historial de copias", "blocks": [
        ("p", "El botón del reloj de la barra inferior abre la lista de todas las transferencias anteriores: "
              "fecha, nombre de la carpeta, origen y destino, y cuántos archivos salieron OK, omitidos o con "
              "problemas. Puedes borrar una entrada o todo el historial."),
        ("img", ("mac-ui-history.png", "Historial de copias, con apertura directa del origen y del destino")),
    ]},

    {"h": "Problemas y situaciones especiales", "blocks": [
        ("h2", "«Espacio insuficiente en el destino» y la transferencia no arranca"),
        ("p", "La aplicación calculó antes de empezar que el material no cabe, y te muestra exactamente "
              "cuánto espacio hace falta y cuánto hay libre. Libera espacio, elige otro destino, o pulsa "
              "<b>Continuar de todos modos</b> si sabes algo que la aplicación no sabe (por ejemplo que vas "
              "a liberar espacio mientras tanto). La comprobación tiene en cuenta los archivos ya copiados, "
              "así que reanudar al 90 % no se bloquea sin motivo."),
        ("h2", "macOS: «no tengo permiso», o errores al leer la tarjeta"),
        ("p", "macOS bloquea el acceso de las aplicaciones a ciertas carpetas y volúmenes hasta que se lo "
              "permites explícitamente. Cuando la aplicación se topa con ese error, muestra una ventana con "
              "un botón que abre directamente el panel adecuado de Ajustes del Sistema. Marca "
              "<b>DataMover</b> en <b>Acceso total al disco</b>, reinicia la aplicación y reanuda — los "
              "archivos ya copiados no se repiten."),
        ("h2", "Windows: «acceso denegado»"),
        ("p", "El archivo o la carpeta está protegido por Windows (a menudo pertenece a otro usuario o a una "
              "zona del sistema). La aplicación te ofrece reiniciarse con permisos de administrador — acepta "
              "la ventana de UAC que aparece."),
        ("h2", "Un archivo tiene el estado DISCREPANCIA"),
        ("p", "La copia difiere del original. La aplicación ya lo reintentó automáticamente una vez. Si sigue "
              "apareciendo, la causa es casi seguro física: cable, lector de tarjetas, puerto USB o la propia "
              "tarjeta. Prueba con otro cable y otro lector, y <b>no formatees la tarjeta</b>."),
        ("h2", "La transferencia se paró a medias"),
        ("p", "Comprueba qué pasó en el destino (disco desconectado, NAS caído, ordenador dormido). Inicia de "
              "nuevo la misma transferencia: con la reanudación activada, continúa exactamente donde se quedó."),
        ("h2", "Falta el informe PDF"),
        ("p", "Los informes CSV y HTML se escriben siempre; si solo falta el PDF, en la carpeta hay un archivo "
              "<i>offload_report_PDF_EROARE.txt</i> con el motivo exacto. Las causas habituales son el disco "
              "lleno o el destino desconectado justo al final."),
        ("h2", "El código de activación no funciona"),
        ("p", "Comprueba que lo copiaste entero, sin espacios de más al principio o al final. Un código está "
              "ligado a un solo ordenador: si cambiaste de máquina o reinstalaste el sistema, necesitas un "
              "código nuevo."),
    ]},

    {"h": "Actualizar la aplicación", "blocks": [
        ("p", "En cada arranque la aplicación comprueba discretamente si existe una versión nueva. Cuando la "
              "hay, aparece una ventana con el número de versión, un resumen de las novedades y dos botones: "
              "<b>Actualizar ahora</b> y <b>Más tarde</b>. La ventana aparece una sola vez por versión nueva."),
        ("p", "La actualización no es silenciosa: la aplicación descarga el paquete y luego <b>lanza el "
              "instalador</b>, que completas tú. En macOS te pide la contraseña del Mac; en Windows, la "
              "confirmación de administrador y la aceptación de la licencia. Puedes comprobarlo manualmente "
              "cuando quieras desde <b>Ajustes → Buscar actualizaciones</b>."),
        ("info", ("Si tienes una versión de Windows anterior a la 2.11.1",
                  "En esas versiones la actualización desde la aplicación fallaba. Descarga la versión actual "
                  "manualmente una sola vez, desde gordas.dev/datamover — a partir de ahí las "
                  "actualizaciones funcionan desde la propia aplicación.")),
    ]},

    {"h": "Desinstalación", "blocks": [
        ("h2", "macOS"),
        ("p", "En el archivo descargado está <b>Dezinstalare_DataMover.command</b>. Al hacer doble clic "
              "elimina por completo la aplicación y todo su rastro: preferencias, cachés, historial, la "
              "licencia guardada. También puedes arrastrar sin más la aplicación a la Papelera — pero "
              "entonces las preferencias se quedan en el disco."),
        ("h2", "Windows"),
        ("p", "<b>Configuración → Aplicaciones → Aplicaciones instaladas → DataMover → Desinstalar</b>. El "
              "desinstalador lo genera automáticamente el instalador y borra todo lo que instaló."),
    ]},

    {"h": "Licencia, apoyo y contacto", "blocks": [
        ("p", "El código fuente de DataMover está bajo licencia MIT y disponible íntegramente en GitHub. Usar "
              "la aplicación compilada, tras los 7 días de prueba, requiere un código de activación personal, "
              "ligado a un solo ordenador."),
        ("p", "El apoyo al proyecto se hace mediante <b>donación</b> — la cantidad de referencia son <b>23 €</b>, "
              "o la que se muestre en la ventana de activación si hay una oferta en ese momento. No es un "
              "precio de lista y no estás comprando un producto: estás contribuyendo a un proyecto "
              "independiente, ofrecido tal cual."),
        ("p", "Para activación, dudas o problemas, escríbeme por WhatsApp desde la propia ventana de "
              "activación de la aplicación — el mensaje ya lleva el ID de tu ordenador."),
    ]},
    ],
}
