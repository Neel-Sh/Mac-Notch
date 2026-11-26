import SwiftUI

struct IslandRootView: View {
    let controller: IslandController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var model: IslandModel { controller.model }

    var body: some View {
        let presentation = model.presentation
        let size = model.size
        let style = model.style
        let panel = IslandLayout.panelSize(style)

        island(presentation, style: style, size: size)
            .frame(width: size.width, height: size.height, alignment: .top)
            .frame(width: panel.width, height: panel.height, alignment: style.edge.alignment)
            .environment(\.islandStyle, style)
            .animation(shellAnimation(presentation), value: presentation)
            .animation(reduceMotion ? Motion.reduced : Motion.resize, value: size)
            .preferredColorScheme(.dark)
    }

    private func shellAnimation(_ presentation: IslandPresentation) -> Animation {
        if reduceMotion { return Motion.reduced }
        return presentation.isExpanded ? Motion.open : Motion.close
    }

    private func island(_ presentation: IslandPresentation, style: IslandStyle, size: CGSize) -> some View {
        let shape = IslandShape(
            bottomRadius: IslandLayout.bottomRadius(for: presentation, notch: model.notch, style: style),
            shoulder: IslandLayout.shoulder(for: presentation, style: style),
            edge: style.edge
        )
        let shoulder = IslandLayout.shoulder(for: presentation, style: style)
        return ZStack(alignment: .top) {
            IslandFill(shape: shape, style: style, notch: model.notch, size: size)
                .overlay {
                    // Drawn across the whole silhouette, shoulders included, so the flares match the page.
                    if case .open(let tab) = presentation {
                        PageBackdrop(controller: controller, tab: tab)
                            .transition(.opacity.animation(Motion.swap))
                    }
                }
            AttentionGlow(active: glowsForAttention, edge: style.edge)
            content(presentation, style: style)
                .padding(style.edge.isSide ? .vertical : .horizontal, shoulder)
            if !style.edge.isSide {
                Grabber(visible: model.isPointerNear && !presentation.isExpanded)
                    .frame(height: model.notch.height, alignment: .bottom)
            }
            if !presentation.isExpanded {
                // Closed, the whole island is one button: click to open (and the only way, in click mode).
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { controller.toggle() }
            }
        }
        .clipShape(shape, style: FillStyle(antialiased: true))
        .contentShape(shape)
    }

    /// S05's rim light: when something needs you, the island's lower edge carries the colour.
    private var glowsForAttention: Bool {
        guard case .peek(let id) = model.presentation,
              let session = controller.agents.sessions.first(where: { $0.id == id }) else { return false }
        return session.phase.wantsAttention
    }

    @ViewBuilder
    private func content(_ presentation: IslandPresentation, style: IslandStyle) -> some View {
        switch presentation {
        case .resting:
            Color.clear
        case .wings:
            Wings(controller: controller, edge: style.edge)
                .transition(.opacity.animation(Motion.contentIn))
        case .peek(let id):
            if let session = controller.agents.sessions.first(where: { $0.id == id }) {
                AgentPeek(session: session, hub: controller.agents, dismiss: controller.endPeek)
                    .padding(.horizontal, 18)
                    .padding(.top, style.edge.isSide ? 14 : model.notch.height + 10)
                    .padding(.bottom, 14)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.settle)
            }
        case .open(let tab):
            Group {
                if style.edge.isSide {
                    SideIsland(controller: controller, tab: tab, edge: style.edge)
                } else {
                    OpenIsland(controller: controller, tab: tab, compact: style.compact)
                }
            }
            .transition(.settle)
        }
    }
}

extension AnyTransition {
    /// Content settles in from just above once the shell has room for it, and is gone before the shell shrinks.
    static var settle: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.992, anchor: .top))
                .combined(with: .offset(y: -4))
                .animation(Motion.contentIn.delay(0.05)),
            removal: .opacity.animation(Motion.contentOut)
        )
    }
}

/// A short bar under the closed notch while the pointer rests on it: "this opens".
private struct Grabber: View {
    let visible: Bool
    var body: some View {
        Capsule()
            .fill(Color.white.opacity(visible ? 0.34 : 0))
            .frame(width: 30, height: 2.5)
            .padding(.bottom, 4)
            .animation(Motion.tap, value: visible)
    }
}

private struct AttentionGlow: View {
    let active: Bool
    let edge: IslandEdge

    var body: some View {
        // Lights the island's far edge: the bottom on the notch, the inner side when docked.
        let far: UnitPoint = switch edge {
        case .top: .bottom
        case .left: .trailing
        case .right: .leading
        }
        RadialGradient(
            colors: [Theme.attention.opacity(0.34), Theme.attention.opacity(0)],
            center: far, startRadius: 0, endRadius: 240
        )
        .scaleEffect(x: edge.isSide ? 1 : 1.8, y: edge.isSide ? 1.8 : 1, anchor: far)
        .opacity(active ? 1 : 0)
        .animation(Motion.swap, value: active)
    }
}

/// Live activity beside the notch: the most important thing on the left, its detail on the right.
private struct Wings: View {
    let controller: IslandController
    var edge: IslandEdge = .top

    var body: some View {
        let notch = controller.model.notch
        if edge.isSide {
            // Docked: a pill standing out of the edge, the same two marks stacked.
            VStack(spacing: 8) {
                left.frame(width: 26, height: 26)
                right.frame(width: 32, height: 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let wing = IslandLayout.wingWidth(notch, controller.model.style)
            HStack(spacing: 0) {
                left.frame(width: wing, height: notch.height)
                Spacer(minLength: notch.width)
                right.frame(width: wing, height: notch.height)
            }
        }
    }

    @ViewBuilder
    private var left: some View {
        if let lead = controller.agents.lead {
            StateMark(phase: lead.phase, size: 15)
        } else if controller.nowPlaying.isPlaying {
            Artwork(image: controller.nowPlaying.artwork, size: 20)
        }
    }

    @ViewBuilder
    private var right: some View {
        if let lead = controller.agents.lead {
            let attention = controller.agents.attentionCount
            if attention > 1 {
                Text("\(attention)")
                    .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Theme.attention)
            } else if case .tool(let tool) = lead.phase {
                Image(systemName: tool.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.working)
                    .contentTransition(.symbolEffect(.replace))
            } else if lead.phase.isWorking {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Elapsed.short(since: lead.clockStart, now: context.date))
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.working)
                }
            } else {
                HostIcon(pid: lead.pid, size: 16)
            }
        } else if controller.nowPlaying.isPlaying {
            Equalizer(playing: true, color: Color(nsColor: controller.nowPlaying.accent ?? .white))
        }
    }
}

/// A page's own backdrop (the Weather sky, the Music album wash), behind the whole open island.
private struct PageBackdrop: View {
    let controller: IslandController
    let tab: IslandTab

    var body: some View {
        Color.clear.overlay {
            if tab == .weather, let forecast = controller.weather.forecast {
                SkyBackdrop(forecast: forecast)
                    .transition(.opacity.animation(Motion.swap))
            } else if tab == .media, controller.nowPlaying.hasTrack, let artwork = controller.nowPlaying.artwork {
                ArtworkBackdrop(image: artwork)
                    .id(ObjectIdentifier(artwork))
                    .transition(.opacity.animation(Motion.swap))
            }
        }
        .clipped()
    }
}

private struct OpenIsland: View {
    let controller: IslandController
    let tab: IslandTab
    var compact = false

    var body: some View {
        let notch = controller.model.notch
        VStack(spacing: 0) {
            Color.clear.frame(height: notch.height + 6)

            HStack(spacing: 10) {
                // The tabs never give up width; the status line truncates instead, so a pill's
                // capsule always wraps its label.
                TabBar(selection: tab, badge: { tabBadge(controller, $0) }, select: controller.select)
                    .fixedSize()
                    .layoutPriority(1)
                Spacer(minLength: 12)
                if !compact {
                    StatusLine(controller: controller)
                        .truncationMode(.tail)
                }
            }
            .frame(height: IslandLayout.headerHeight)
            .padding(.horizontal, 16)

            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            PageContent(controller: controller, tab: tab)
        }
    }
}

/// Docked to a side: the page tabs in a column against the screen edge, a portrait page beside them.
private struct SideIsland: View {
    let controller: IslandController
    let tab: IslandTab
    let edge: IslandEdge

    var body: some View {
        let showsRail = Preferences.shared.visibleTabs.count > 1
        // The page keeps its distance from the outer round, and sits closer to the rail.
        let near: CGFloat = showsRail ? 6 : 18, far: CGFloat = 18
        let leading = edge == .left ? near : far, trailing = edge == .left ? far : near
        HStack(spacing: 0) {
            if showsRail, edge == .left { rail }
            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(tab.title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.primary)
                        .contentTransition(.opacity)
                        .fixedSize()
                    Spacer(minLength: 12)
                    // The Weather page already says the temperature, large.
                    StatusLine(controller: controller, showsWeather: tab != .weather)
                        .truncationMode(.tail)
                }
                .frame(height: 26)
                .padding(.leading, leading + 4)
                .padding(.trailing, trailing + 4)
                .padding(.top, IslandLayout.sideTop)

                PageContent(controller: controller, tab: tab,
                            inset: EdgeInsets(top: IslandLayout.sidePageTop, leading: leading,
                                              bottom: IslandLayout.sidePageBottom, trailing: trailing))
            }
            if showsRail, edge == .right { rail }
        }
    }

    private var rail: some View {
        TabRail(selection: tab, badge: { tabBadge(controller, $0) }, select: controller.select)
            .frame(width: IslandLayout.railWidth)
            .frame(maxHeight: .infinity)
    }
}

/// The docked panel's tabs: a capsule of page icons standing on the screen edge, the current one riding
/// a lighter pill.
private struct TabRail: View {
    let selection: IslandTab
    let badge: (IslandTab) -> Int?
    let select: (IslandTab) -> Void
    @Namespace private var pill

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Preferences.shared.visibleTabs) { tab in
                DockButton(tab: tab, selected: tab == selection, badge: badge(tab), pill: pill) { select(tab) }
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

private struct DockButton: View {
    let tab: IslandTab
    let selected: Bool
    let badge: Int?
    let pill: Namespace.ID
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if tab == .agents {
                    BotGlyph(size: 15)
                } else {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .frame(width: 36, height: IslandLayout.railButtonHeight)
            .foregroundStyle(selected ? Theme.primary : Theme.secondary)
            .background {
                if selected {
                    Capsule().fill(Color.white.opacity(0.16))
                        .matchedGeometryEffect(id: "selection", in: pill)
                } else if hovered {
                    Capsule().fill(Color.white.opacity(0.06))
                }
            }
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text("\(badge)")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.black.opacity(0.8))
                        .padding(.horizontal, 4)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(Capsule().fill(tab == .agents ? Theme.attention : Color.white.opacity(0.74)))
                        .offset(x: 1, y: -2)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .help(tab.title)
        .onHover { hovering in withAnimation(Motion.tap) { hovered = hovering } }
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The page itself, shared by the notch and side layouts.
private struct PageContent: View {
    let controller: IslandController
    let tab: IslandTab
    var inset = EdgeInsets(top: 10, leading: 16, bottom: 14, trailing: 16)

    var body: some View {
        Group {
                switch tab {
                case .agents: AgentsPage(hub: controller.agents)
                case .calendar: CalendarPage(service: controller.calendar)
                case .tasks: TasksPage(store: controller.tasks, model: controller.model)
                case .weather: WeatherPage(service: controller.weather)
                case .media: MediaPage(player: controller.nowPlaying)
                case .shelf: ShelfPage(shelf: controller.shelf, isDropTargeted: controller.model.isDropTargeted)
                }
            }
            .padding(inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .id(tab)
            .transition(.opacity.animation(Motion.swap))
    }
}

private func tabBadge(_ controller: IslandController, _ tab: IslandTab) -> Int? {
    switch tab {
    case .agents: controller.agents.attentionCount > 0 ? controller.agents.attentionCount : nil
    case .tasks: controller.tasks.openCount > 0 ? controller.tasks.openCount : nil
    case .shelf: controller.shelf.items.isEmpty ? nil : controller.shelf.items.count
    default: nil
    }
}

private struct StatusLine: View {
    let controller: IslandController
    var showsWeather = true

    var body: some View {
        HStack(spacing: 6) {
            if showsWeather, let forecast = controller.weather.forecast {
                Image(systemName: WeatherCode.symbol(forecast.code, isDay: forecast.isDay))
                    .symbolRenderingMode(.multicolor)
                Text("\(Int(forecast.temperature.rounded()))°")
            }
            if let text = agentText {
                if showsWeather, controller.weather.forecast != nil { Text("·").foregroundStyle(Theme.tertiary) }
                Text(text)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(Theme.secondary)
        .lineLimit(1)
    }

    private var agentText: String? {
        let hub = controller.agents
        if hub.attentionCount > 0 { return "\(hub.attentionCount) waiting on you" }
        if hub.workingCount > 0 { return "\(hub.workingCount) working" }
        if let next = controller.calendar.nextEvent {
            return next.isHappening(at: .now)
                ? "\(next.title) now"
                : "\(next.title) \(next.start.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))"
        }
        return nil
    }
}

private struct TabBar: View {
    let selection: IslandTab
    let badge: (IslandTab) -> Int?
    let select: (IslandTab) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Preferences.shared.visibleTabs) { tab in
                TabPill(tab: tab, selected: tab == selection, badge: badge(tab)) { select(tab) }
            }
        }
    }
}

private struct TabPill: View {
    let tab: IslandTab
    let selected: Bool
    let badge: Int?
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if tab == .agents {
                    BotGlyph(size: 13)
                } else {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 11, weight: .semibold))
                }
                if selected {
                    Text(tab.title)
                        .font(.system(size: 11, weight: .semibold))
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                }
                if let badge {
                    Text("\(badge)")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.black.opacity(0.8))
                        .padding(.horizontal, 4)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(Capsule().fill(tab == .agents ? Theme.attention : Color.white.opacity(0.74)))
                }
            }
            .padding(.horizontal, selected ? 10 : 8)
            .frame(minWidth: 30)
            .frame(height: 26)
            .foregroundStyle(selected ? Theme.primary : Theme.secondary)
            .background(Capsule().fill(Color.white.opacity(selected ? 0.13 : (hovered ? 0.06 : 0))))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tab.title)
        .onHover { hovering in withAnimation(Motion.tap) { hovered = hovering } }
        .animation(Motion.swap, value: selected)
    }
}

extension IslandEdge {
    /// Where the island sits inside its panel.
    var alignment: Alignment {
        switch self {
        case .top: .top
        case .left: .leading
        case .right: .trailing
        }
    }
}

/// The island's body. Black by default. As Liquid Glass it is solid black where it meets the bezel, so the
/// notch still vanishes into the hardware, and fades through its length into clear glass at the far edge.
private struct IslandFill: View {
    let shape: IslandShape
    let style: IslandStyle
    let notch: NotchMetrics
    let size: CGSize

    var body: some View {
        if style.glass {
            ZStack {
                Color.clear.glassEffect(.clear, in: shape)
                shape.fill(LinearGradient(stops: fade, startPoint: flush, endPoint: far))
                // Glass catches light where it thins out: a soft highlight along the clear edge.
                shape.stroke(LinearGradient(colors: [.white.opacity(0), .white.opacity(0.35)],
                                                  startPoint: flush, endPoint: far), lineWidth: 2)
            }
        } else {
            shape.fill(Theme.island, style: FillStyle(antialiased: true))
        }
    }

    private var flush: UnitPoint {
        switch style.edge {
        case .top: .top
        case .left: .leading
        case .right: .trailing
        }
    }

    private var far: UnitPoint { UnitPoint(x: 1 - flush.x, y: 1 - flush.y) }

    /// Solid for most of the way so text stays legible, then a long ease into clear.
    private var fade: [Gradient.Stop] {
        let length = style.edge.isSide ? size.width : size.height
        let solid = style.edge.isSide ? 0.45 : max(0.5, min(1, (notch.height + 40) / max(length, 1)))
        return [
            .init(color: .black, location: 0),
            .init(color: .black, location: solid),
            .init(color: .black.opacity(0.72), location: solid + (1 - solid) * 0.4),
            .init(color: .black.opacity(0.25), location: solid + (1 - solid) * 0.8),
            .init(color: .black.opacity(0.05), location: 1),
        ]
    }
}
