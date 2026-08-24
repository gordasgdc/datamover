# DataMover

[Rumano](README.md) | [Inglés](README.en.md) | [Español](README.es.md)

**Offload verificado para equipos de producción de video**

## Capturas de pantalla

UI nativa de macOS (SwiftUI) — orígenes, discos y destinos en un único diseño de 3 columnas.

| Ventana principal | Ajustes de copia |
|--------------------|-------------------|
| ![Ventana principal](docs/img/mac-ui-main.png) | ![Ajustes de copia](docs/img/mac-ui-settings.png) |

| Historial de copias | Guía de uso integrada |
|----------------------|-------------------------|
| ![Historial](docs/img/mac-ui-history.png) | ![Guia](docs/img/mac-ui-help.png) |

## Características

- Copia simultánea a cualquier número de destinos (unidades externas, NAS, carpetas locales)
- Verificación de integridad, a elegir: MD5, SHA-1, SHA-256, SHA-512, o solo tamaño
- Tema oscuro
- Informes CSV + PDF (en tabla), con estado por archivo (OK / Discrepancia / Error) y marca de tiempo exacta
- Reanudación automática en caso de errores (checkpoint) — continúa desde donde quedó
- Historial de copias — ver y eliminar entradas individuales o todas (Mac)
- Modo Monitor en la bandeja del sistema — detecta automáticamente las tarjetas insertadas (Windows)
- Barras de progreso por destino, con velocidad actual (MB/s) y acceso rápido a la carpeta
- Guía de uso integrada
- Atajos de teclado para las acciones principales
- Registro centralizado para auditoría a largo plazo
- Copia paralela — todos los destinos se completan simultáneamente
- Nombramiento automático de carpetas: `Fecha_Proyecto_Tarjeta`
- Localización completa RO/EN/ES
- Compatible con macOS (UI nativa SwiftUI, Apple Silicon + Intel) y Windows 10/11
- Exclusiones personalizables — archivos o extensiones

## Descarga

Descarga la última versión desde [Releases](https://github.com/gordasgdc/datamover/releases).

| Plataforma | Archivo | Descripción |
|------------|---------|-------------|
| Mac | `DataMover-Mac.zip` | `DataMover.app` nativa (SwiftUI) + guías PDF (RO/EN/ES) |
| Windows | `DataMover-Windows.zip` | `DataMover.exe` + guías PDF (RO/EN/ES) |

## Instalación rápida

### Mac
1. Descarga `DataMover-Mac.zip` y extráelo
2. Doble clic en `Instaleaza_DataMover.command` (incluido en el archivo) — mueve automáticamente `DataMover.app` a `/Applications` (con confirmación) si aún no está ahí, elimina el aviso habitual de Gatekeeper y abre la app. Alternativa (sin mover automáticamente a Applications): clic derecho sobre `DataMover.app` → `Open` → confirma (la app está firmada ad-hoc, sin cuenta de Apple Developer de pago)

### Windows
1. Descarga `DataMover-Windows.zip` y extrae el contenido
2. Ejecuta `DataMover.exe`
3. Si SmartScreen advierte, haz clic en "More info" → "Run anyway"

## Documentación completa

Consulta [CITESTE-MA.md](CITESTE-MA.md) (solo en rumano por ahora) para instrucciones detalladas de instalación, compilación, publicación de versiones y solución de problemas.

## Autor

**Cristi Gordas** ([@gordasgdc](https://github.com/gordasgdc))

Contacto y enlaces disponibles directamente en la app, en la ventana "Activar licencia".

## Licencia

Este proyecto se distribuye bajo la [Licencia MIT](LICENSE).
