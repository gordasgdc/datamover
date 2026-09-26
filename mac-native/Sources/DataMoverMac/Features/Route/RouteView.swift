import SwiftUI
import UniformTypeIdentifiers

// MARK: - Traseul: sursă → verificare → destinații
//
// Același obiect vizual în toate cele trei etape (Prepare, Transfer, Result);
// se schimbă doar ce spune fiecare capăt și nodul din mijloc. Conectorii se
// desenează din pozițiile REALE ale obiectelor (anchor preferences), deci nu
// se rup la redimensionare, la 1–4 destinații sau la stivuire verticală.

enum RouteStage: Equatable { case prepare, transfer, result }

struct RouteEndpoint: Identifiable {
    var id: String { path }
    let path: String
    let name: String
    let media: MediaClass?
    let role: RouteRole
    var online = true
    var warning = false
    var activity: DeviceActivity = .idle
    /// Cifra mare (B): „612 GB”, „2,1 TB”, „58%”, „214”.
    var figure: String = "—"
    var figureCaption: String = ""
    var detail: String = ""
    var secondary: String = ""
    var capacity: (total: Int64, used: Int64, incoming: Int64)? = nil
    var progress: Double? = nil
    var outcome: DestinationOutcome? = nil
    var reports: [(label: String, path: String)] = []

    var kind: DeviceKind { media?.kind ?? .externalDevice }
}

struct RouteNodeModel {
    var stage: RouteStage
    var method: String
    var phaseText: String = ""
    var percent: Int? = nil
    var rateText: String? = nil
    var etaText: String? = nil
    var verdict: TransferOutcome? = nil
    var status: DMStatus = .neutral
}

private struct EndpointAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Cadrele zonelor de drop, în spațiul „root” — ca tragerea din raftul de
/// dispozitive să știe unde a căzut.
struct RouteZoneFrames: Equatable { var sources: CGRect = .zero; var destinations: CGRect = .zero }
struct RouteZoneKey: PreferenceKey {
    static let defaultValue = RouteZoneFrames()
    static func reduce(value: inout RouteZoneFrames, nextValue: () -> RouteZoneFrames) {
        let n = nextValue()
        if n.sources != .zero { value.sources = n.sources }
        if n.destinations != .zero { value.destinations = n.destinations }
    }
}

private struct RouteCompactKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// Traseul e în modul orizontal compact (coloane înguste).
    var routeCompact: Bool {
        get { self[RouteCompactKey.self] }
        set { self[RouteCompactKey.self] = newValue }
    }
}

struct RouteView: View {
    let stage: RouteStage
    let sources: [RouteEndpoint]
    let destinations: [RouteEndpoint]
    let node: RouteNodeModel
    var animateFlow = false
    var dropHighlight: (sources: Bool, destinations: Bool) = (false, false)
    var onRemove: ((String) -> Void)? = nil
    var onDropSources: (([NSItemProvider]) -> Bool)? = nil
    var onDropDestinations: (([NSItemProvider]) -> Bool)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let mode = RouteLayout.mode(width: geo.size.width)
            let density = RouteLayout.density(mode: mode, height: geo.size.height,
                                              sources: max(sources.count, 1), destinations: max(destinations.count, 1))
            ScrollView(.vertical) {
                Group {
                    switch mode {
                    case .horizontal: horizontal(density, compact: false)
                    case .compactHorizontal: horizontal(density, compact: true)
                    case .stacked: stacked(density)
                    }
                }
                .frame(minHeight: geo.size.height, alignment: .center)
                .padding(.horizontal, DM.Space.xl)
                .padding(.vertical, DM.Space.l)
                .backgroundPreferenceValue(EndpointAnchorKey.self) { anchors in
                    GeometryReader { g in connectors(anchors: anchors, proxy: g, mode: mode) }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: Compoziții

    private func horizontal(_ d: RouteLayout.Density, compact: Bool) -> some View {
        HStack(alignment: .center, spacing: 0) {
            sourceZone(d, axis: .vertical)
                .frame(width: compact ? DM.Layout.routeSourceColumnCompact : DM.Layout.routeSourceColumn)
            Spacer(minLength: compact ? DM.Layout.routeMinGapCompact : DM.Layout.routeMinGap)
            nodeView(compact: compact).frame(width: compact ? DM.Layout.routeNodeWidthCompact : DM.Layout.routeNodeWidth)
            Spacer(minLength: compact ? DM.Layout.routeMinGapCompact : DM.Layout.routeMinGap)
            destinationZone(d, grid: false)
                .frame(width: compact ? DM.Layout.routeDestinationColumnCompact : DM.Layout.routeDestinationColumn)
        }
        .environment(\.routeCompact, compact)
    }

    private func stacked(_ d: RouteLayout.Density) -> some View {
        VStack(spacing: DM.Space.xl) {
            sourceZone(d, axis: .horizontal)
            nodeView(compact: false)
            destinationZone(d, grid: true)
        }
    }

    private func sourceZone(_ d: RouteLayout.Density, axis: Axis) -> some View {
        let content = Group {
            if sources.isEmpty {
                slot(textKey: "route.slot.source")
            } else {
                ForEach(Array(sources.enumerated()), id: \.element.id) { _, e in
                    EndpointView(endpoint: e, stage: stage, density: d, sourceCount: sources.count, onRemove: onRemove)
                }
            }
        }
        return Group {
            if axis == .vertical { VStack(alignment: .leading, spacing: DM.Space.l) { content } }
            else { HStack(alignment: .top, spacing: DM.Space.xl) { content } }
        }
        .padding(DM.Space.s)
        .dmDropHighlight(dropHighlight.sources)
        .background(zoneReader { RouteZoneFrames(sources: $0) })
        .onDrop(of: [.fileURL, .volume], isTargeted: nil) { onDropSources?($0) ?? false }
    }

    private func destinationZone(_ d: RouteLayout.Density, grid: Bool) -> some View {
        let items = Group {
            ForEach(destinations) { e in
                EndpointView(endpoint: e, stage: stage, density: d, sourceCount: sources.count, onRemove: onRemove)
            }
            if stage == .prepare && destinations.count < 4 {
                slot(textKey: destinations.isEmpty ? "route.slot.destination" : "route.slot.addCopy")
            }
        }
        return Group {
            if grid {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: DM.Layout.routeSourceColumn), spacing: DM.Space.l, alignment: .top)],
                          alignment: .leading, spacing: DM.Space.l) { items }
            } else {
                VStack(alignment: .leading, spacing: destinations.count > 2 ? DM.Space.m : DM.Space.xl) { items }
            }
        }
        .padding(DM.Space.s)
        .dmDropHighlight(dropHighlight.destinations)
        .background(zoneReader { RouteZoneFrames(destinations: $0) })
        .onDrop(of: [.fileURL, .volume], isTargeted: nil) { onDropDestinations?($0) ?? false }
    }

    private func zoneReader(_ make: @escaping (CGRect) -> RouteZoneFrames) -> some View {
        GeometryReader { g in Color.clear.preference(key: RouteZoneKey.self, value: make(g.frame(in: .named("root")))) }
    }

    private func slot(textKey: String) -> some View {
        RoundedRectangle(cornerRadius: DM.Radius.l)
            .strokeBorder(DM.textTertiary, style: StrokeStyle(lineWidth: DM.Layout.hairline, dash: [5, 4]))
            .frame(maxWidth: DM.Layout.routeSourceColumn)
            .frame(height: DM.Layout.slotHeight)
            .overlay(Text(L.t(textKey)).font(DM.Font.label).foregroundStyle(DM.textSecondary)
                .multilineTextAlignment(.center).padding(DM.Space.m))
            .accessibilityElement(children: .combine)
    }

    // MARK: Nodul de verificare

    private func nodeView(compact: Bool) -> some View {
        let block = compact ? DM.Layout.routeNodeBlockCompact : DM.Layout.routeNodeBlock
        return VStack(spacing: DM.Space.s) {
            ZStack {
                RoundedRectangle(cornerRadius: DM.Radius.l + 6)
                    .fill(LinearGradient(colors: [DM.surface, DM.surfaceSunken], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: DM.Radius.l + 6).strokeBorder(node.status == .neutral ? DM.border : node.status.color,
                                                                                      lineWidth: node.status == .neutral ? DM.Layout.hairline : DM.Layout.routeConnector))
                    .dmElevation()
                VStack(spacing: DM.Space.xs) {
                    Image(systemName: nodeSymbol).font(.system(size: DM.IconSize.banner, weight: .semibold))
                        .foregroundStyle(node.status == .neutral ? DM.accent : node.status.color)
                    if let percent = node.percent {
                        Text("\(percent)%").font(DM.Font.figureCompact)
                    }
                }
            }
            .frame(width: block, height: block)
            .anchorPreference(key: EndpointAnchorKey.self, value: .bounds) { ["node": $0] }

            Text(node.phaseText).font(DM.Font.label.weight(.semibold)).multilineTextAlignment(.center)
            Text(node.method).font(DM.Font.detail).foregroundStyle(DM.textSecondary).multilineTextAlignment(.center)
            if let r = node.rateText { Text(r).font(DM.Font.mono).foregroundStyle(DM.textSecondary) }
            if let eta = node.etaText { Text(eta).font(DM.Font.detail).foregroundStyle(DM.textTertiary) }
        }
        .accessibilityElement(children: .combine)
    }

    private var nodeSymbol: String {
        switch node.stage {
        case .prepare: return "checkmark.shield"
        case .transfer: return "arrow.triangle.2.circlepath"
        case .result: return node.status.symbol
        }
    }

    // MARK: Conectori

    @ViewBuilder
    private func connectors(anchors: [String: Anchor<CGRect>], proxy: GeometryProxy, mode: RouteLayout.Mode) -> some View {
        if let nodeA = anchors["node"] {
            let n = proxy[nodeA]
            TimelineView(.animation(minimumInterval: 1 / 30, paused: !(animateFlow && !reduceMotion))) { t in
                let phase = animateFlow && !reduceMotion ? CGFloat(t.date.timeIntervalSinceReferenceDate * 24).truncatingRemainder(dividingBy: 20) : 0
                Canvas { ctx, _ in
                    for s in sources { if let a = anchors[s.id] { draw(&ctx, from: proxy[a], to: n, mode: mode, color: DM.textSecondary, phase: 0, dashed: false) } }
                    for d in destinations {
                        guard let a = anchors[d.id] else { continue }
                        let color: Color = d.outcome.map { DMStatus($0).color } ?? (d.online ? DM.accent : DM.textTertiary)
                        draw(&ctx, from: n, to: proxy[a], mode: mode, color: color, phase: -phase, dashed: animateFlow)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func draw(_ ctx: inout GraphicsContext, from a: CGRect, to b: CGRect, mode: RouteLayout.Mode,
                      color: Color, phase: CGFloat, dashed: Bool) {
        var p = Path()
        if mode != .stacked {
            let s = CGPoint(x: a.maxX + 6, y: a.midY), e = CGPoint(x: b.minX - 6, y: b.midY)
            let dx = (e.x - s.x) * 0.5
            p.move(to: s); p.addCurve(to: e, control1: CGPoint(x: s.x + dx, y: s.y), control2: CGPoint(x: e.x - dx, y: e.y))
        } else {
            let s = CGPoint(x: a.midX, y: a.maxY + 6), e = CGPoint(x: b.midX, y: b.minY - 6)
            let dy = (e.y - s.y) * 0.5
            p.move(to: s); p.addCurve(to: e, control1: CGPoint(x: s.x, y: s.y + dy), control2: CGPoint(x: e.x, y: e.y - dy))
        }
        let style = StrokeStyle(lineWidth: DM.Layout.routeConnector, lineCap: .round, dash: dashed ? [10, 10] : [], dashPhase: phase)
        ctx.stroke(p, with: .color(color), style: style)
    }

    fileprivate static func anchorID(_ e: RouteEndpoint) -> String { e.id }
}

// MARK: - Un capăt al traseului

struct EndpointView: View {
    let endpoint: RouteEndpoint
    let stage: RouteStage
    let density: RouteLayout.Density
    var sourceCount = 1
    var onRemove: ((String) -> Void)? = nil

    @Environment(\.routeCompact) private var routeCompact
    private var e: RouteEndpoint { endpoint }
    private var sourceWidth: CGFloat { routeCompact ? DM.Layout.routeSourceColumnCompact : DM.Layout.routeSourceColumn }
    private var destinationWidth: CGFloat { routeCompact ? DM.Layout.routeDestinationColumnCompact : DM.Layout.routeDestinationColumn }
    private var isSource: Bool { if case .source = e.role { return true } else { return false } }

    var body: some View {
        // Sursele: obiectul deasupra textului (coloana e îngustă); destinațiile:
        // obiectul în stânga. Conectorul se ancorează pe tot capătul, deci
        // nu trece niciodată prin text.
        let layout = isSource
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DM.Space.s))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DM.Space.m))
        layout {
            DeviceArt(kind: e.kind, size: RouteLayout.deviceWidth(density), dimmed: !e.online)
            info
        }
        .anchorPreference(key: EndpointAnchorKey.self, value: .bounds) { [e.id: $0] }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: DM.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                DeviceBadges(role: e.role, online: e.online, activity: e.activity, warning: e.warning, sourceCount: sourceCount)
                Spacer(minLength: 0)
                if stage == .prepare, let onRemove {
                    Button { onRemove(e.path) } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(DM.textTertiary)
                        .help(L.t("route.remove"))
                        .accessibilityLabel(L.t("route.remove") + " " + e.name)
                }
            }
            Text(e.name).font(DM.Font.deviceName).lineLimit(2).truncationMode(.middle).help(e.path)
            Text(kindLine).font(DM.Font.detail).foregroundStyle(DM.textSecondary).lineLimit(2)
            // Cifra mare nu se rupe niciodată; eticheta trece dedesubt dacă nu încape.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: DM.Space.xs) { figureText; captionText }
                VStack(alignment: .leading, spacing: 0) { figureText; captionText }
            }
            if let p = e.progress {
                ProgressView(value: p).tint(e.outcome.map { DMStatus($0).color } ?? DM.accent)
                    .frame(maxWidth: DM.Layout.endpointBarWidth)
            } else if let c = e.capacity {
                DMCapacityBar(total: c.total, free: c.total - c.used, incoming: c.incoming)
                    .frame(maxWidth: DM.Layout.endpointBarWidth)
            }
            if !e.secondary.isEmpty {
                Text(e.secondary).font(DM.Font.detail).foregroundStyle(DM.textTertiary).lineLimit(2)
            }
            if let outcome = e.outcome {
                DMStatusBadge(status: DMStatus(outcome), text: L.t("destOutcome.\(outcome.rawValue)"))
            }
            if let first = e.reports.first {
                // Folderul pe un rând, rapoartele pe al doilea; butoanele nu se
                // comprimă niciodată (textul lor rămâne întreg).
                VStack(alignment: .leading, spacing: DM.Space.xs) {
                    Button { NSWorkspace.shared.open(URL(fileURLWithPath: first.path)) } label: {
                        Label(first.label, systemImage: "folder")
                    }
                    .fixedSize()
                    HStack(spacing: DM.Space.xs) {
                        ForEach(e.reports.dropFirst(), id: \.path) { r in
                            Button(r.label) { NSWorkspace.shared.open(URL(fileURLWithPath: r.path)) }.fixedSize()
                        }
                    }
                }
                .controlSize(.small)
            }
        }
        .frame(maxWidth: isSource ? sourceWidth : destinationWidth - RouteLayout.deviceWidth(density) - DM.Space.m,
               alignment: .leading)
    }

    private var figureText: some View {
        Text(e.figure).font(density == .large ? DM.Font.figure : DM.Font.figureCompact)
            .lineLimit(1).fixedSize(horizontal: true, vertical: false)
    }
    private var captionText: some View {
        Text(e.figureCaption).font(DM.Font.detail).foregroundStyle(DM.textSecondary).lineLimit(1)
    }

    private var kindLine: String {
        var parts = [L.t(e.kind.labelKey)]
        if let c = e.media?.connectionKey { parts.append(L.t(c)) }
        if !e.detail.isEmpty { parts.append(e.detail) }
        return parts.joined(separator: " · ")
    }

    private var accessibilitySummary: String {
        [e.name, kindLine, e.figure + " " + e.figureCaption, e.secondary].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
