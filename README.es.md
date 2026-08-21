# DataMover

[🇷🇴 Rumano](README.md) | [🇬🇧 Inglés](README.en.md) | [🇪🇸 Español](README.es.md)

**Offload verificado para equipos de producción de video**

<!-- Cuando tengas un video demo, reemplaza VIDEO_ID con el ID real de YouTube:
[![Video Demo](https://img.youtube.com/vi/VIDEO_ID/0.jpg)](https://youtu.be/VIDEO_ID) -->

## 📸 Capturas de pantalla

UI nativa de macOS (SwiftUI) — orígenes, discos y destinos en un único diseño de 3 columnas:

| Ventana principal | Ajustes de copia |
|--------------------|-------------------|
| ![Ventana principal](docs/img/mac-ui-main.png) | ![Ajustes de copia](docs/img/mac-ui-settings.png) |

| Historial de copias | Guía de uso integrada |
|----------------------|-------------------------|
| ![Historial](docs/img/mac-ui-history.png) | ![Guia](docs/img/mac-ui-help.png) |

## ✅ Características

- 📂 Copia simultánea a **cualquier número de destinos** (unidades externas, NAS, carpetas locales)
- 🔒 **Verificación de integridad**, a elegir: MD5, SHA-1, SHA-256, SHA-512, o solo tamaño
- 🌙 **Tema oscuro** — perfecto para trabajar de noche
- 📊 **Informes profesionales** CSV + PDF (en tabla), con estado codificado por colores (OK / Discrepancia / Error) y marca de tiempo exacta
- 🔄 **Reanudación automática** en caso de errores (checkpoint) — continúa desde donde quedó
- 🕐 **Historial de copias** — ver y eliminar entradas individuales o todas (Mac)
- 🖥️ **Modo Monitor** en la bandeja del sistema — detecta automáticamente las tarjetas insertadas (Windows)
- 📈 **Barras de progreso por destino** con velocidad actual (MB/s) y botón de acceso rápido a la carpeta
- 💡 **Tooltips/guía integrada** para todos los ajustes avanzados
- ⌨️ **Atajos de teclado** para las acciones principales
- 📝 **Registro centralizado** para auditoría a largo plazo
- 🚀 **Copia paralela** — todos los destinos se completan simultáneamente
- 🏷️ **Nombramiento automático** de carpetas: `Fecha_Proyecto_Tarjeta`
- 🌍 **Localización completa** RO/EN/ES
- 🔌 **Compatible** con macOS (UI nativa SwiftUI, Apple Silicon + Intel) y Windows 10/11
- 🗑️ **Exclusiones personalizables** — puedes excluir archivos o extensiones

## 🚀 Descarga

Descarga la última versión desde [Releases](https://github.com/gordasgdc/datamover/releases)

| Plataforma | Archivo | Descripción |
|------------|---------|-------------|
| **Mac** | `DataMover-Mac.zip` | `DataMover.app` nativa (SwiftUI) + guías PDF (RO/EN/ES) |
| **Windows** | `DataMover-Windows.zip` | `DataMover.exe` + guías PDF (RO/EN/ES) |

## 📖 Instalación rápida

### Mac
1. Descarga `DataMover-Mac.zip` y extráelo
2. Arrastra `DataMover.app` a `/Applications`
3. En la primera ejecución, clic derecho sobre la app → `Open` → confirma (solo una vez, esta firmada ad-hoc sin cuenta de Apple Developer de pago)

### Windows
1. Descarga `DataMover-Windows.zip` y extrae el contenido
2. Ejecuta `DataMover.exe`
3. Si SmartScreen advierte, haz clic en "More info" → "Run anyway"

## 📝 Documentación completa

Consulta [CITESTE-MA.md](CITESTE-MA.md) (solo en rumano por ahora) para instrucciones detalladas de instalación, compilación, publicación de versiones y solución de problemas.

## 👤 Creado por

**Cristi Gordas** (@gordasgdc)

- 🌐 [GitHub](https://github.com/gordasgdc/datamover)
- 📘 [Facebook](https://web.facebook.com/cristiGDC)
- 🎥 [YouTube](https://www.youtube.com/@cristigordas)

Los mismos enlaces también están disponibles directamente en la app, desde la ventana **"Acerca de..."** en la esquina superior izquierda.

## 🙏 Apoya el proyecto

Si esta aplicación te ha sido útil:
- ⭐ Dale una **Star** en GitHub
- 🔗 **Compártela** con colegas de la industria
- 💬 **Deja tu opinión** o una sugerencia

## 📄 Licencia

Este proyecto se distribuye bajo la [Licencia MIT](LICENSE).
