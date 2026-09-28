# DataMover

Descarga verificada para producción de vídeo: la tarjeta se lee una sola vez y el
material se copia a la vez en varios discos independientes. Cada archivo recibe
su nombre final solo después de que el checksum de la copia coincida con el origen.

**Descarga y presentación: [gordas.dev/datamover](https://gordas.dev/datamover/)** · versión actual **2.17.1**

![DataMover en macOS durante una transferencia](docs/img/2.16/mac-transfer-dark-ro.webp)

## Qué hace

- Lee el origen una sola vez y escribe en paralelo en todos los destinos (discos externos, RAID, NAS, carpetas).
- Contrato de copia para cada archivo y cada copia: escritura → vaciado a disco → relectura y verificación. Un archivo sin verificar nunca aparece con su nombre final.
- Verificación con xxHash64 por defecto; MD5, SHA-1, SHA-256 o SHA-512 a elección.
- Reanudación tras una interrupción: los archivos ya confirmados no se vuelven a copiar y los incompletos se limpian.
- Informes de entrega por destino: PDF, HTML, CSV y MHL, con veredicto (verificado, con avisos, sin confirmar, cancelado).
- Interfaz en rumano, inglés y español, en macOS y Windows.

![DataMover en Windows durante una transferencia](docs/img/2.16/win-dark-1240-transfer.webp)

## Plataformas y requisitos

- **macOS 14 o posterior, Apple Silicon.** Paquete firmado con Developer ID y notarizado por Apple.
- **Windows 11, 64 bits (x64).** En Windows 11 ARM64 funciona mediante la emulación x64 del sistema.

## Instalación

**macOS.** Descarga `DataMover.dmg` desde [gordas.dev/datamover](https://gordas.dev/datamover/), ábrelo y ejecuta el instalador `.pkg`. La aplicación se instala en `/Applications`.

**Windows.** Descarga `DataMover-WPF-Windows.zip`, extrae el archivo y ejecuta `DataMoverSetup.exe`. La aplicación se instala en Program Files, con accesos directos.

> Por ahora, el instalador de Windows tiene una firma self-signed, no un certificado comercial Authenticode. SmartScreen puede mostrar «Windows protegió su PC» o «Editor desconocido». Si descargaste el archivo desde gordas.dev, elige **Más información → Ejecutar de todas formas**.

## Prueba y activación

- 7 días con todas las funciones, sin cuenta.
- Sin activación, al terminar la prueba cada transferencia se limita a 2 GB.
- La activación usa un código personal vinculado al ID del ordenador, que se obtiene con una donación para el desarrollo. Detalles en la aplicación y en [gordas.dev/datamover](https://gordas.dev/datamover/).

## Diagnóstico

El registro técnico se queda en tu ordenador; no se envía nada automáticamente. Para soporte, la aplicación puede crear una exportación de diagnóstico con las rutas y los datos personales ocultos, que envías solo si quieres.

## Para desarrolladores

- [CITESTE-MA.md](CITESTE-MA.md) — compilación, publicación, resolución de problemas (en rumano)
- [ARCHITECTURE.md](ARCHITECTURE.md) · [RELIABILITY.md](RELIABILITY.md) · [CHANGELOG.md](CHANGELOG.md)
- [support/JURNALE_SI_DIAGNOSTIC.md](support/JURNALE_SI_DIAGNOSTIC.md)

Idioma: [Română](README.md) · [English](README.en.md) · **Español**

## Licencia

Código fuente con [licencia MIT](LICENSE). Autor: Cristi Gordaș.
