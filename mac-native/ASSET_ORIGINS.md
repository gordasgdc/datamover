# Originea activelor vizuale — DataMover (macOS)

| Activ | Unde | Origine | Licență |
|---|---|---|---|
| Familia de dispozitive (card CFexpress, card SD, card de memorie generic, SSD extern, HDD/RAID extern, stick USB, volum intern, folder ales manual, dispozitiv extern necunoscut) | `Sources/DataMoverMac/DesignSystem/Devices/DeviceArt.swift` | Desenate în cod (SwiftUI `Canvas`: trasee, gradiente de material, umbre de contact), create pentru DataMover. Nicio imagine rasterizată, nicio sursă externă. | Proprii (GDC), aceeași licență ca restul codului |
| Pictograme de stare și acțiune (online/offline, avertisment, verificare, rapoarte) | `DeviceBadges.swift`, `IncidentPanel.swift`, `RouteView.swift` | SF Symbols (Apple), folosite prin API-ul sistemului | Licența SF Symbols / Apple SDK — doar în aplicații pentru platformele Apple |
| Pictograma aplicației | `AppIcon.icns` | Neschimbată în acest lot | — |

Mockup-urile raster de explorare (Codex D/E, conceptele A/B/C) NU sunt incluse în produs; stau în afara git (`design-review/`, `~/Developer/_design-studio/`).
Tipul afișat pentru un volum vine din `MediaClassifier` (fapte de sistem); desenul nu afirmă un model sau o marcă de hardware.
