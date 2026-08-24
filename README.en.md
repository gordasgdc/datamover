# DataMover

[Romanian](README.md) | [English](README.en.md) | [Spanish](README.es.md)

**Verified offload for video production teams**

## Screenshots

Native macOS UI (SwiftUI) — sources, disks and destinations in a single 3-column layout.

| Main window | Copy settings |
|-------------|---------------|
| ![Main window](docs/img/mac-ui-main.png) | ![Copy settings](docs/img/mac-ui-settings.png) |

| Copy history | Built-in user guide |
|--------------|----------------------|
| ![History](docs/img/mac-ui-history.png) | ![Guide](docs/img/mac-ui-help.png) |

## Features

- Simultaneous copy to any number of destinations (external drives, NAS, local folders)
- Integrity verification, your choice: MD5, SHA-1, SHA-256, SHA-512, or size-only
- Dark theme
- CSV + PDF reports (table layout), with per-file status (OK / Mismatch / Error) and exact timestamp
- Automatic resume on errors (checkpoint) — continues from where it left off
- Copy history — view and delete individual or all entries (Mac)
- Monitor Mode in the system tray — automatically detects inserted cards (Windows)
- Per-destination progress bars, with current speed (MB/s) and quick folder access
- Built-in user guide
- Keyboard shortcuts for the main actions
- Centralized log for long-term auditing
- Parallel copy — all destinations complete simultaneously
- Automatic folder naming: `Date_Project_Card`
- Full localization RO/EN/ES
- Support for macOS (native SwiftUI UI, Apple Silicon + Intel) and Windows 10/11
- Customizable exclusions — files or extensions

## Download

Download the latest version from [Releases](https://github.com/gordasgdc/datamover/releases).

| Platform | File | Description |
|----------|------|-------------|
| Mac | `DataMover-Mac.zip` | Native `DataMover.app` (SwiftUI) + PDF guides (RO/EN/ES) |
| Windows | `DataMover-Windows.zip` | `DataMover.exe` + PDF guides (RO/EN/ES) |

## Quick install

### Mac
1. Download `DataMover-Mac.zip` and extract it
2. Double-click `Instaleaza_DataMover.command` (included in the archive) — automatically moves `DataMover.app` into `/Applications` (with confirmation) if it isn't there yet, clears the usual Gatekeeper warning, and opens the app. Alternative (no automatic move to Applications): right-click `DataMover.app` → `Open` → confirm (the app is ad-hoc signed, without a paid Apple Developer account)

### Windows
1. Download `DataMover-Windows.zip` and extract the contents
2. Run `DataMover.exe`
3. If SmartScreen warns you, click "More info" → "Run anyway"

## Full documentation

See [CITESTE-MA.md](CITESTE-MA.md) (Romanian only for now) for detailed install, build, release, and troubleshooting instructions.

## Author

**Cristi Gordas** ([@gordasgdc](https://github.com/gordasgdc))

Contact and links are available directly in the app, in the "Activate license" window.

## License

This project is distributed under the [MIT License](LICENSE).
