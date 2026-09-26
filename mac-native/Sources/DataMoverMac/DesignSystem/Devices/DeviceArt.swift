import SwiftUI

// MARK: - Familia de dispozitive DataMover
//
// Vectori ORIGINALI desenați în cod (SwiftUI Canvas) — nicio imagine externă,
// nicio licență terță. Scalabili la orice mărime și densitate (Retina/HiDPI:
// Canvas se rasterizează la rezoluția ecranului). Materiale coerente:
// aluminiu, grafit, carcasă mată, contacte aurii, LED cyan discret; lumina
// vine de sus-stânga. Starea NU se desenează în obiect (vezi `DeviceBadges`).

enum DeviceMaterials {
    struct Tone { let hi: Color, mid: Color, lo: Color }
    static func aluminium(_ dark: Bool) -> Tone {
        Tone(hi: Color(white: dark ? 0.90 : 0.97), mid: Color(white: dark ? 0.70 : 0.82), lo: Color(white: dark ? 0.44 : 0.58))
    }
    static func graphite(_ dark: Bool) -> Tone {
        Tone(hi: Color(white: dark ? 0.40 : 0.44), mid: Color(white: dark ? 0.22 : 0.26), lo: Color(white: dark ? 0.10 : 0.13))
    }
    static func matte(_ dark: Bool) -> Tone {
        Tone(hi: Color(white: dark ? 0.26 : 0.30), mid: Color(white: 0.14), lo: Color(white: 0.06))
    }
    static let gold = Gradient(colors: [Color(red: 0.96, green: 0.84, blue: 0.50), Color(red: 0.70, green: 0.54, blue: 0.22)])
    static let led = Color(red: 0.36, green: 0.86, blue: 0.96)
    static let cfBand = Gradient(colors: [Color(red: 0.72, green: 0.15, blue: 0.13), Color(red: 0.44, green: 0.07, blue: 0.07)])
    static let sdLabel = Gradient(colors: [Color(red: 0.17, green: 0.31, blue: 0.53), Color(red: 0.08, green: 0.14, blue: 0.28)])
}

struct DeviceArt: View {
    let kind: DeviceKind
    /// Lățimea obiectului; înălțimea = 0,78 × lățimea.
    var size: CGFloat = 160
    /// Offline: desaturat și atenuat — plus insigna „offline” separată.
    var dimmed = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { ctx, sz in
            let dark = scheme == .dark
            DeviceArt.drawShadow(&ctx, sz, kind, dark)
            switch kind {
            case .cfexpress: DeviceArt.card(&ctx, sz, dark, style: .cfexpress)
            case .sdCard: DeviceArt.sd(&ctx, sz, dark)
            case .memoryCard: DeviceArt.card(&ctx, sz, dark, style: .generic)
            case .ssd: DeviceArt.ssd(&ctx, sz, dark)
            case .hdd: DeviceArt.enclosure(&ctx, sz, dark)
            case .usbStick: DeviceArt.usb(&ctx, sz, dark)
            case .internalVolume: DeviceArt.laptop(&ctx, sz, dark)
            case .folder: DeviceArt.folder(&ctx, sz, dark)
            case .externalDevice: DeviceArt.unknownExternal(&ctx, sz, dark)
            }
        }
        .frame(width: size, height: size * 0.78)
        .saturation(dimmed ? 0 : 1)
        .opacity(dimmed ? 0.5 : 1)
        .accessibilityHidden(true) // numele și tipul sunt citite din textul de lângă obiect
    }

    // MARK: Umbră de contact

    static func drawShadow(_ ctx: inout GraphicsContext, _ sz: CGSize, _ kind: DeviceKind, _ dark: Bool) {
        let base: (y: CGFloat, w: CGFloat)? = {
            switch kind {
            case .cfexpress, .memoryCard: return (0.84, 0.50)
            case .sdCard: return (0.84, 0.40)
            case .ssd: return (0.76, 0.84)
            case .hdd: return (0.86, 0.62)
            case .usbStick: return (0.70, 0.58)
            case .internalVolume: return (0.74, 0.82)
            case .externalDevice: return (0.80, 0.70)
            case .folder: return nil
            }
        }()
        guard let base else { return }
        var s = ctx
        s.addFilter(.blur(radius: sz.width * 0.03))
        s.fill(Path(ellipseIn: CGRect(x: sz.width * (0.5 - base.w / 2), y: sz.height * base.y - sz.height * 0.035,
                                      width: sz.width * base.w, height: sz.height * 0.07)),
               with: .color(.black.opacity(dark ? 0.65 : 0.28)))
    }

    private static func vertical(_ t: DeviceMaterials.Tone, _ r: CGRect) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: [t.hi, t.mid, t.lo]), startPoint: CGPoint(x: r.midX, y: r.minY), endPoint: CGPoint(x: r.midX, y: r.maxY))
    }

    private static func specular(_ ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint, alpha: Double = 0.45) {
        ctx.stroke(Path { p in p.move(to: a); p.addLine(to: b) }, with: .color(.white.opacity(alpha)), lineWidth: 1)
    }

    // MARK: Carduri

    enum CardStyle { case cfexpress, generic }

    /// CFexpress B (bandă roșie, pini în margine) sau card de memorie generic
    /// (când sistemul nu poate spune ce fel de card e — fără bandă de marcă).
    static func card(_ ctx: inout GraphicsContext, _ sz: CGSize, _ dark: Bool, style: CardStyle) {
        let w = sz.width, h = sz.height
        var c = ctx
        c.translateBy(x: w / 2, y: h * 0.48); c.rotate(by: .degrees(-7)); c.translateBy(x: -w / 2, y: -h * 0.48)
        let body = CGRect(x: w * 0.25, y: h * 0.08, width: w * 0.50, height: h * 0.72)
        c.fill(Path(roundedRect: body, cornerRadius: w * 0.028), with: vertical(DeviceMaterials.matte(dark), body))
        c.stroke(Path(roundedRect: body.insetBy(dx: 0.5, dy: 0.5), cornerRadius: w * 0.028), with: .color(.white.opacity(0.20)), lineWidth: 1)
        specular(&c, from: CGPoint(x: body.minX + 5, y: body.minY + 2), to: CGPoint(x: body.maxX - 5, y: body.minY + 2))
        switch style {
        case .cfexpress:
            let band = CGRect(x: body.minX, y: body.minY + body.height * 0.16, width: body.width, height: body.height * 0.25)
            c.fill(Path(band), with: .linearGradient(DeviceMaterials.cfBand, startPoint: CGPoint(x: band.minX, y: band.minY),
                                                     endPoint: CGPoint(x: band.maxX, y: band.maxY)))
            c.draw(Text("CFexpress").font(.system(size: w * 0.056, weight: .heavy)).foregroundStyle(.white), at: CGPoint(x: band.midX, y: band.midY))
            c.draw(Text("B").font(.system(size: w * 0.075, weight: .bold)).foregroundStyle(.white.opacity(0.85)),
                   at: CGPoint(x: body.midX, y: body.minY + body.height * 0.62))
        case .generic:
            let label = CGRect(x: body.minX + body.width * 0.12, y: body.minY + body.height * 0.18, width: body.width * 0.76, height: body.height * 0.46)
            c.fill(Path(roundedRect: label, cornerRadius: 3), with: .color(Color(white: 0.30)))
            for i in 0..<3 {
                c.fill(Path(CGRect(x: label.minX + 6, y: label.minY + 8 + CGFloat(i) * label.height * 0.24, width: label.width * (0.7 - CGFloat(i) * 0.15), height: 2)),
                       with: .color(.white.opacity(0.35)))
            }
        }
        for i in 0..<9 {
            let px = body.minX + body.width * (0.12 + CGFloat(i) * 0.095)
            c.fill(Path(CGRect(x: px, y: body.maxY - body.height * 0.09, width: body.width * 0.05, height: body.height * 0.06)),
                   with: .linearGradient(DeviceMaterials.gold, startPoint: CGPoint(x: px, y: body.maxY - 10), endPoint: CGPoint(x: px, y: body.maxY)))
        }
    }

    static func sd(_ ctx: inout GraphicsContext, _ sz: CGSize, _ dark: Bool) {
        let w = sz.width, h = sz.height
        var c = ctx
        c.translateBy(x: w / 2, y: h * 0.46); c.rotate(by: .degrees(8)); c.translateBy(x: -w / 2, y: -h * 0.46)
        let r = CGRect(x: w * 0.31, y: h * 0.06, width: w * 0.38, height: h * 0.76)
        let cut = r.width * 0.22
        let path = Path { p in
            p.move(to: CGPoint(x: r.minX + 4, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX - cut, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY + cut))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 4))
            p.addQuadCurve(to: CGPoint(x: r.maxX - 4, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX + 4, y: r.maxY))
            p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - 4), control: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.minY + 4))
            p.addQuadCurve(to: CGPoint(x: r.minX + 4, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        }
        c.fill(path, with: vertical(DeviceMaterials.graphite(dark), r))
        c.stroke(path, with: .color(.white.opacity(0.22)), lineWidth: 1)
        let label = CGRect(x: r.minX + r.width * 0.10, y: r.minY + r.height * 0.28, width: r.width * 0.80, height: r.height * 0.58)
        c.fill(Path(roundedRect: label, cornerRadius: 3), with: .linearGradient(DeviceMaterials.sdLabel, startPoint: CGPoint(x: label.minX, y: label.minY),
                                                                                  endPoint: CGPoint(x: label.maxX, y: label.maxY)))
        c.draw(Text("SD").font(.system(size: w * 0.10, weight: .black)).foregroundStyle(.white.opacity(0.92)),
               at: CGPoint(x: label.midX, y: label.midY))
        for i in 0..<5 {
            let px = r.minX + r.width * (0.10 + CGFloat(i) * 0.12)
            c.fill(Path(CGRect(x: px, y: r.minY + 3, width: r.width * 0.075, height: r.height * 0.14)),
                   with: .linearGradient(DeviceMaterials.gold, startPoint: CGPoint(x: px, y: r.minY), endPoint: CGPoint(x: px, y: r.minY + 20)))
        }
        c.fill(Path(roundedRect: CGRect(x: r.minX - 3, y: r.minY + r.height * 0.18, width: 5, height: r.height * 0.14), cornerRadius: 1.5),
               with: .color(Color(white: 0.86)))
    }

    // MARK: Discuri externe

    /// SSD portabil din aluminiu: placă joasă, fețe în perspectivă, LED, USB-C.
    static func ssd(_ ctx: inout GraphicsContext, _ sz: CGSize, _ dark: Bool) {
        let w = sz.width, h = sz.height
        let front = CGRect(x: w * 0.10, y: h * 0.52, width: w * 0.80, height: h * 0.20)
        let depth = h * 0.26
        let top = Path { p in
            p.move(to: CGPoint(x: front.minX + w * 0.07, y: front.minY - depth))
            p.addLine(to: CGPoint(x: front.maxX + w * 0.03, y: front.minY - depth))
            p.addLine(to: CGPoint(x: front.maxX, y: front.minY))
            p.addLine(to: CGPoint(x: front.minX, y: front.minY))
            p.closeSubpath()
        }
        let al = DeviceMaterials.aluminium(dark)
        ctx.fill(top, with: .linearGradient(Gradient(colors: [al.hi, al.mid]), startPoint: CGPoint(x: front.minX, y: front.minY - depth),
                                             endPoint: CGPoint(x: front.maxX, y: front.minY)))
        ctx.stroke(top, with: .color(.white.opacity(0.7)), lineWidth: 0.8)
        ctx.fill(Path(roundedRect: front, cornerRadius: 4), with: vertical(DeviceMaterials.Tone(hi: al.mid, mid: al.lo, lo: Color(white: 0.30)), front))
        // Nervuri de răcire pe fața frontală.
        for i in 0..<4 {
            let y = front.minY + front.height * (0.22 + CGFloat(i) * 0.17)
            ctx.fill(Path(CGRect(x: front.minX + front.width * 0.14, y: y, width: front.width * 0.62, height: 1.2)), with: .color(.black.opacity(0.25)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: front.minX + front.width * 0.05, y: front.midY - 2.5, width: 5, height: 5)), with: .color(DeviceMaterials.led))
        var glow = ctx; glow.addFilter(.blur(radius: 3))
        glow.fill(Path(ellipseIn: CGRect(x: front.minX + front.width * 0.05 - 2, y: front.midY - 4.5, width: 9, height: 9)),
                  with: .color(DeviceMaterials.led.opacity(0.5)))
        ctx.fill(Path(roundedRect: CGRect(x: front.maxX - front.width * 0.14, y: front.midY - 3, width: front.width * 0.08, height: 6), cornerRadius: 3),
                 with: .color(.black.opacity(0.85)))
        specular(&ctx, from: CGPoint(x: front.minX + w * 0.08, y: front.minY - depth + 1.5), to: CGPoint(x: front.maxX, y: front.minY - depth + 1.5), alpha: 0.8)
    }

    /// HDD / RAID desktop: carcasă neagră cu sertare, fețe laterale, LED-uri.
    static func enclosure(_ ctx: inout GraphicsContext, _ sz: CGSize, _ dark: Bool) {
        let w = sz.width, h = sz.height
        let front = CGRect(x: w * 0.24, y: h * 0.12, width: w * 0.42, height: h * 0.74)
        let dx = w * 0.12, dy = h * 0.06
        let side = Path { p in
            p.move(to: CGPoint(x: front.maxX, y: front.minY)); p.addLine(to: CGPoint(x: front.maxX + dx, y: front.minY - dy))
            p.addLine(to: CGPoint(x: front.maxX + dx, y: front.maxY - dy)); p.addLine(to: CGPoint(x: front.maxX, y: front.maxY)); p.closeSubpath()
        }
        let top = Path { p in
            p.move(to: CGPoint(x: front.minX, y: front.minY)); p.addLine(to: CGPoint(x: front.minX + dx, y: front.minY - dy))
            p.addLine(to: CGPoint(x: front.maxX + dx, y: front.minY - dy)); p.addLine(to: CGPoint(x: front.maxX, y: front.minY)); p.closeSubpath()
        }
        let m = DeviceMaterials.matte(dark)
        ctx.fill(side, with: .linearGradient(Gradient(colors: [m.mid, m.lo]), startPoint: CGPoint(x: front.maxX, y: 0), endPoint: CGPoint(x: front.maxX + dx, y: 0)))
        ctx.fill(top, with: .color(m.hi))
        ctx.fill(Path(roundedRect: front, cornerRadius: 3), with: vertical(DeviceMaterials.Tone(hi: Color(white: 0.24), mid: Color(white: 0.13), lo: Color(white: 0.07)), front))
        ctx.stroke(Path(roundedRect: front, cornerRadius: 3), with: .color(.white.opacity(0.16)), lineWidth: 1)
        // Două sertare cu grilă și LED de activitate.
        for bay in 0..<2 {
            let r = CGRect(x: front.minX + front.width * 0.10, y: front.minY + front.height * (0.10 + CGFloat(bay) * 0.40),
                           width: front.width * 0.80, height: front.height * 0.34)
            ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(.black.opacity(0.55)))
            ctx.stroke(Path(roundedRect: r, cornerRadius: 2), with: .color(.white.opacity(0.10)), lineWidth: 1)
            for i in 0..<5 {
                ctx.fill(Path(CGRect(x: r.minX + r.width * 0.12, y: r.minY + r.height * (0.18 + CGFloat(i) * 0.14), width: r.width * 0.62, height: 1.6)),
                         with: .color(Color(white: 0.30)))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: r.maxX - r.width * 0.12, y: r.midY - 2, width: 4, height: 4)),
                     with: .color(bay == 0 ? DeviceMaterials.led : Color(white: 0.45)))
        }
        specular(&ctx, from: CGPoint(x: front.minX + 3, y: front.minY + 1.5), to: CGPoint(x: front.maxX - 3, y: front.minY + 1.5), alpha: 0.3)
    }

    static func usb(_ ctx: inout GraphicsContext, _ sz: CGSize, _ dark: Bool) {
        let w = sz.width, h = sz.height
        var c = ctx
        c.translateBy(x: w / 2, y: h * 0.48); c.rotate(by: .degrees(-16)); c.translateBy(x: -w / 2, y: -h * 0.48)
        let body = CGRect(x: w * 0.16, y: h * 0.38, width: w * 0.48, height: h * 0.21)
        let conn = CGRect(x: body.maxX - 1, y: body.minY + body.height * 0.14, width: w * 0.19, height: body.height * 0.72)
        c.fill(Path(conn), with: vertical(DeviceMaterials.aluminium(dark), conn))
        for i in 0..<2 {
            c.fill(Path(CGRect(x: conn.minX + conn.width * (0.30 + CGFloat(i) * 0.32), y: conn.minY + conn.height * 0.22,
                               width: conn.width * 0.16, height: conn.height * 0.22)), with: .color(.black.opacity(0.7)))
        }
        c.fill(Path(roundedRect: body, cornerRadius: body.height * 0.45), with: vertical(DeviceMaterials.matte(dark), body))
        c.stroke(Path(roundedRect: body, cornerRadius: body.height * 0.45), with: .color(.white.opacity(0.22)), lineWidth: 1)
        c.stroke(Path(ellipseIn: CGRect(x: body.minX + body.height * 0.25, y: body.midY - body.height * 0.18,
                                        width: body.height * 0.36, height: body.height * 0.36)), with: .color(Color(white: 0.6)), lineWidth: 1.5)
        specular(&c, from: CGPoint(x: body.minX + body.height * 0.8, y: body.minY + 2), to: CGPoint(x: body.maxX - 6, y: body.minY + 2))
    }

    /// Volum intern: laptopul care conține discul (nu un „disc intern” abstract).
    static func laptop(_ ctx: inout GraphicsContext, _ sz: CGSize, _ dark: Bool) {
        let w = sz.width, h = sz.height
        let screen = CGRect(x: w * 0.19, y: h * 0.10, width: w * 0.62, height: h * 0.54)
        let al = DeviceMaterials.aluminium(dark)
        ctx.fill(Path(roundedRect: screen, cornerRadius: 6), with: vertical(al, screen))
        let panel = screen.insetBy(dx: w * 0.018, dy: w * 0.018)
        ctx.fill(Path(roundedRect: panel, cornerRadius: 3), with: .linearGradient(Gradient(colors: [Color(white: 0.22), Color(white: 0.05)]),
                                                                                   startPoint: CGPoint(x: panel.minX, y: panel.minY), endPoint: CGPoint(x: panel.maxX, y: panel.maxY)))
        ctx.fill(Path { p in
            p.move(to: CGPoint(x: panel.minX, y: panel.minY)); p.addLine(to: CGPoint(x: panel.minX + panel.width * 0.45, y: panel.minY))
            p.addLine(to: CGPoint(x: panel.minX, y: panel.minY + panel.height * 0.7)); p.closeSubpath()
        }, with: .color(.white.opacity(0.07)))
        let base = Path { p in
            p.move(to: CGPoint(x: w * 0.10, y: screen.maxY + 2)); p.addLine(to: CGPoint(x: w * 0.90, y: screen.maxY + 2))
            p.addLine(to: CGPoint(x: w * 0.86, y: screen.maxY + h * 0.08)); p.addLine(to: CGPoint(x: w * 0.14, y: screen.maxY + h * 0.08)); p.closeSubpath()
        }
        ctx.fill(base, with: .linearGradient(Gradient(colors: [al.hi, al.lo]), startPoint: CGPoint(x: w / 2, y: screen.maxY), endPoint: CGPoint(x: w / 2, y: screen.maxY + h * 0.08)))
    }

    /// Folder ales manual: intenționat plat — e o locație, nu un obiect fizic.
    static func folder(_ ctx: inout GraphicsContext, _ sz: CGSize, _ dark: Bool) {
        let w = sz.width, h = sz.height
        let r = CGRect(x: w * 0.22, y: h * 0.24, width: w * 0.56, height: h * 0.52)
        let tab = Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.minY + 6)); p.addLine(to: CGPoint(x: r.minX, y: r.minY - h * 0.06 + 4))
            p.addQuadCurve(to: CGPoint(x: r.minX + 4, y: r.minY - h * 0.06), control: CGPoint(x: r.minX, y: r.minY - h * 0.06))
            p.addLine(to: CGPoint(x: r.minX + r.width * 0.34, y: r.minY - h * 0.06)); p.addLine(to: CGPoint(x: r.minX + r.width * 0.42, y: r.minY)); p.closeSubpath()
        }
        let ink = dark ? Color(white: 0.80) : Color(white: 0.28)
        ctx.stroke(tab, with: .color(ink), lineWidth: max(1.2, w * 0.011))
        ctx.stroke(Path(roundedRect: r, cornerRadius: 4), with: .color(ink), lineWidth: max(1.2, w * 0.011))
        ctx.stroke(Path { p in p.move(to: CGPoint(x: r.minX + 10, y: r.minY + r.height * 0.3)); p.addLine(to: CGPoint(x: r.maxX - 10, y: r.minY + r.height * 0.3)) },
                   with: .color(ink.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
    }

    /// Dispozitiv extern necunoscut: carcasă neutră cu cablu — fără marcă,
    /// fără sertare, fără LED de tip. Nu pretinde nimic despre conținut.
    static func unknownExternal(_ ctx: inout GraphicsContext, _ sz: CGSize, _ dark: Bool) {
        let w = sz.width, h = sz.height
        let body = CGRect(x: w * 0.22, y: h * 0.26, width: w * 0.48, height: h * 0.50)
        let g = DeviceMaterials.graphite(dark)
        ctx.fill(Path(roundedRect: body, cornerRadius: w * 0.04), with: vertical(g, body))
        ctx.stroke(Path(roundedRect: body.insetBy(dx: 0.5, dy: 0.5), cornerRadius: w * 0.04), with: .color(.white.opacity(0.22)), lineWidth: 1)
        ctx.stroke(Path(roundedRect: body.insetBy(dx: w * 0.05, dy: w * 0.05), cornerRadius: w * 0.02),
                   with: .color(.white.opacity(0.14)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        // Cablu care iese spre dreapta.
        var cable = Path()
        cable.move(to: CGPoint(x: body.maxX, y: body.midY + body.height * 0.18))
        cable.addCurve(to: CGPoint(x: w * 0.90, y: h * 0.40), control1: CGPoint(x: body.maxX + w * 0.08, y: body.midY + body.height * 0.2),
                       control2: CGPoint(x: w * 0.80, y: h * 0.40))
        ctx.stroke(cable, with: .color(Color(white: dark ? 0.55 : 0.35)), style: StrokeStyle(lineWidth: max(2, w * 0.018), lineCap: .round))
        ctx.fill(Path(roundedRect: CGRect(x: w * 0.86, y: h * 0.37, width: w * 0.07, height: h * 0.06), cornerRadius: 2), with: vertical(DeviceMaterials.aluminium(dark), body))
        specular(&ctx, from: CGPoint(x: body.minX + 6, y: body.minY + 2), to: CGPoint(x: body.maxX - 6, y: body.minY + 2))
    }
}
