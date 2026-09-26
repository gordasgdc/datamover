import AppKit

/// Paleta raportului de livrare TIPĂRIT (document alb, A4) — separată de tema
/// aplicației: pe hârtie contează contrastul pe alb, nu tema Light/Dark.
/// Aceleași valori ca în CSS-ul raportului HTML și ca pe Windows (PdfReport.cs).
enum DMReportPalette {
    static let ink = NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1)
    static let dim = NSColor(srgbRed: 0.36, green: 0.39, blue: 0.44, alpha: 1)
    static let rule = NSColor(srgbRed: 0.84, green: 0.85, blue: 0.87, alpha: 1)
    static let band = NSColor(srgbRed: 0.965, green: 0.97, blue: 0.975, alpha: 1)
    static let amber = NSColor(srgbRed: 0.72, green: 0.41, blue: 0.12, alpha: 1)
    static let ok = NSColor(srgbRed: 0.12, green: 0.48, blue: 0.27, alpha: 1)
    static let warn = NSColor(srgbRed: 0.60, green: 0.38, blue: 0.0, alpha: 1)
    static let fail = NSColor(srgbRed: 0.71, green: 0.14, blue: 0.09, alpha: 1)
}
