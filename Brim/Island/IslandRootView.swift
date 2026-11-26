import SwiftUI

struct IslandRootView: View {
    let controller: IslandController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var model: IslandModel { controller.model }

    var body: some View {
        let presentation = model.presentation
        let size = model.size

        island(presentation)
            .frame(width: size.width, height: size.height, alignment: .top)
            .frame(width: IslandLayout.panelSize.width, height: IslandLayout.panelSize.height, alignment: .top)
            .animation(shellAnimation(presentation), value: presentation)
            .animation(reduceMotion ? Motion.reduced : Motion.resize, value: size)
            .preferredColorScheme(.dark)
    }

    private func shellAnimation(_ presentation: IslandPresentation) -> Animation {
        if reduceMotion { return Motion.reduced }
        return presentation.isExpanded ? Motion.open : Motion.close
    }

    private func island(_ presentation: IslandPresentation) -> some View {
        let shape = IslandShape(
            bottomRadius: IslandLayout.bottomRadius(for: presentation, notch: model.notch),
            shoulder: IslandLayout.shoulder(for: presentation)
        )
        return ZStack(alignment: .top) {
            shape.fill(Theme.island, style: FillStyle(antialiased: true))
                .overlay {
                    // Drawn across the whole silhouette, shoulders included, so the flares match the page.
                    if case .open(let tab) = presentation {
                        PageBackdrop(controller: controller, tab: tab)
                            .transition(.opacity.animation(Motion.swap))
                    }
                }
            AttentionGlow(active: glowsForAttention)
            content(presentation)
                .padding(.horizontal, IslandLayout.shoulder(for: presentation))
            Grabber(visible: model.isPointerNear && !presentation.isExpanded)
                .frame(height: model.notch.height, alignment: .bottom)
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
    private func content(_ presentation: IslandPresentation) -> some View {
        switch presentation {
        case .resting:
            Color.clear
        case .wings:
            Wings(controller: controller)
                .transition(.opacity.animation(Motion.contentIn))
        case .peek(let id):
            if let session = controller.agents.sessions.first(where: { $0.id == id }) {
                AgentPeek(session: session, hub: controller.agents, dismiss: controller.endPeek)
                    .padding(.horizontal, 18)
                    .padding(.top, model.notch.height + 10)
                    .padding(.bottom, 14)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.settle)
            }
        case .open(let tab):
            OpenIsland(controller: controller, tab: tab)
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

    var body: some View {
        RadialGradient(
            colors: [Theme.attention.opacity(0.34), Theme.attention.opacity(0)],
            center: .bottom, startRadius: 0, endRadius: 240
        )
        .scaleEffect(x: 1.8, y: 1, anchor: .bottom)
        .opacity(active ? 1 : 0)
        .animation(Motion.swap, value: active)
    }
}

/// Live activity beside the notch: the most important thing on the left, its detail on the right.
private struct Wings: View {
    let controller: IslandController

    var body: some View {
        let notch = controller.model.notch
        let wing = IslandLayout.wingWidth(notch)
        HStack(spacing: 0) {
            left.frame(width: wing, height: notch.height)
            Spacer(minLength: notch.width)
            right.frame(width: wing, height: notch.height)
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

    var body: some View {
        let notch = controller.model.notch
        VStack(spacing: 0) {
            Color.clear.frame(height: notch.height + 6)

            HStack(spacing: 10) {
                // The tabs never give up width; the status line truncates instead, so a pill's
                // capsule always wraps its label.
                TabBar(selection: tab, badge: badge, select: controller.select)
                    .fixedSize()
                    .layoutPriority(1)
                Spacer(minLength: 12)
                StatusLine(controller: controller)
                    .truncationMode(.tail)
            }
            .frame(height: IslandLayout.headerHeight)
            .padding(.horizontal, 16)

            Rectangle()
                .fill(Theme.hairline)
                .frame(height: 1)
                .padding(.horizontal, 16)
                .padding(.top, 8)

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
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .id(tab)
            .transition(.opacity.animation(Motion.swap))
        }
    }

    private func badge(_ tab: IslandTab) -> Int? {
        switch tab {
        case .agents: controller.agents.attentionCount > 0 ? controller.agents.attentionCount : nil
        case .tasks: controller.tasks.openCount > 0 ? controller.tasks.openCount : nil
        case .shelf: controller.shelf.items.isEmpty ? nil : controller.shelf.items.count
        default: nil
        }
    }
}

private struct StatusLine: View {
    let controller: IslandController

    var body: some View {
        HStack(spacing: 6) {
            if let forecast = controller.weather.forecast {
                Image(systemName: WeatherCode.symbol(forecast.code, isDay: forecast.isDay))
                    .symbolRenderingMode(.multicolor)
                Text("\(Int(forecast.temperature.rounded()))°")
            }
            if let text = agentText {
                if controller.weather.forecast != nil { Text("·").foregroundStyle(Theme.tertiary) }
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
            ForEach(IslandTab.allCases) { tab in
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
