import SwiftUI

struct CalendarPage: View {
    let service: CalendarService
    @Environment(\.islandStyle) private var style

    var body: some View {
        switch service.access {
        case .granted:
            VStack(spacing: 12) {
                DayRail(service: service, stacked: style.edge.isSide)
                Agenda(service: service, events: service.events(on: service.selectedDay))
            }
        case .unknown:
            prompt("Show your calendar here", "Brim reads your calendars on this Mac. Nothing leaves it.", button: "Allow") {
                service.requestAccessIfNeeded()
            }
        case .denied:
            prompt("Brim can't see your calendars", "Allow it in System Settings › Privacy & Security › Calendars.", button: "Open") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    @ViewBuilder
    private func prompt(_ title: String, _ detail: String, button: String, action: @escaping () -> Void) -> some View {
        if style.edge.isSide {
            SidePrompt(symbol: "calendar", title: title, detail: detail, button: button, prominent: true, action: action)
        } else {
            widePrompt(title, detail, button: button, action: action)
        }
    }

    private func widePrompt(_ title: String, _ detail: String, button: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.tertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.title(12.5))
                Text(detail).font(Theme.body(11)).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Button(button, action: action).buttonStyle(PillButtonStyle(kind: .primary))
        }
        .frame(maxHeight: .infinity)
    }
}

/// Month on the left, the days as a rail: a week at a time, two-finger scroll for the weeks after.
/// A dot under a day means something's on. Docked, the month moves above the rail so the week gets the width.
private struct DayRail: View {
    let service: CalendarService
    var stacked = false
    @State private var firstVisible: Date?
    @State private var railFrame: CGRect = .zero
    @State private var wheel = WheelMonitor()

    private var today: Date { Calendar.current.startOfDay(for: .now) }
    /// The month of what's on screen, so it turns over as you scroll into the next one.
    private var shownMonth: Date { firstVisible ?? service.selectedDay }
    private var scrolledAway: Bool { firstVisible.map { !Calendar.current.isDate($0, inSameDayAs: today) } ?? false }

    private var offToday: Bool {
        scrolledAway || !Calendar.current.isDate(service.selectedDay, inSameDayAs: today)
    }

    var body: some View {
        Group {
            if stacked {
                VStack(spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(shownMonth.formatted(.dateTime.month(.wide)))
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .contentTransition(.numericText())
                            .animation(Motion.swap, value: shownMonth.formatted(.dateTime.month()))
                        Text(shownMonth.formatted(.dateTime.year()))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.tertiary)
                        Spacer(minLength: 8)
                        if offToday {
                            Button("Today", action: jumpToToday)
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(Theme.working)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, 4)
                    .animation(Motion.swap, value: offToday)
                    week.frame(height: 56)
                }
            } else {
                HStack(spacing: 12) {
                    monthColumn
                    Rectangle().fill(Theme.hairline).frame(width: 1, height: 38)
                    week
                }
                .frame(height: 56)
            }
        }
        .onAppear { wheel.start(in: { railFrame }, step: step) }
        .onDisappear { wheel.stop() }
    }

    private var monthColumn: some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(shownMonth.formatted(.dateTime.month(.abbreviated)))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                    .animation(Motion.swap, value: shownMonth.formatted(.dateTime.month()))
                if offToday {
                    Button("Today", action: jumpToToday)
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.working)
                        .transition(.opacity)
                } else {
                    Text(shownMonth.formatted(.dateTime.year()))
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.tertiary)
                        .transition(.opacity)
                }
            }
            .frame(width: 58, alignment: .leading)
            .animation(Motion.swap, value: scrolledAway)
    }

    private var week: some View {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 4) {
                    ForEach(service.days, id: \.self) { day in
                        DayCell(day: day,
                                selected: Calendar.current.isDate(day, inSameDayAs: service.selectedDay),
                                hasEvents: !service.events(on: day).isEmpty) {
                            withAnimation(Motion.swap) { service.selectedDay = day }
                        }
                        .containerRelativeFrame(.horizontal, count: 7, spacing: 4)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.never)
            .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
            .scrollPosition(id: $firstVisible, anchor: .leading)
            .scrollEdgeEffectStyle(.soft, for: .horizontal)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { railFrame = $0 }
    }

    /// Moves the rail a day for each notch of a vertical swipe or mouse wheel.
    private func step(_ days: Int) {
        let all = service.days
        let current = firstVisible.flatMap { day in all.firstIndex { Calendar.current.isDate($0, inSameDayAs: day) } } ?? 0
        let target = min(max(0, current + days), max(0, all.count - 7))
        guard target != current else { return }
        withAnimation(Motion.swap) { firstVisible = all[target] }
    }

    private func jumpToToday() {
        withAnimation(Motion.swap) {
            service.selectedDay = today
            firstVisible = today
        }
    }
}

/// A horizontal scroll view ignores vertical wheel motion. Over the rail, this turns it into days,
/// so a two-finger swipe in either direction (or a plain mouse wheel) moves through the weeks.
@MainActor
private final class WheelMonitor {
    private var monitor: Any?
    private var accumulated: CGFloat = 0
    private static let pointsPerDay: CGFloat = 36

    func start(in frame: @escaping () -> CGRect, step: @escaping (Int) -> Void) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let content = event.window?.contentView,
                  abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return event }
            let point = CGPoint(x: event.locationInWindow.x, y: content.bounds.height - event.locationInWindow.y)
            guard frame().contains(point) else { return event }
            if event.phase == .began { self.accumulated = 0 }
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * Self.pointsPerDay
            self.accumulated -= delta
            let days = Int(self.accumulated / Self.pointsPerDay)
            if days != 0 {
                self.accumulated -= CGFloat(days) * Self.pointsPerDay
                step(days)
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        accumulated = 0
    }
}

private struct DayCell: View {
    let day: Date
    let selected: Bool
    let hasEvents: Bool
    let action: () -> Void
    @State private var hovered = false

    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    /// The first of a month says which month, so the rail reads across the turn.
    private var startsMonth: Bool { Calendar.current.component(.day, from: day) == 1 }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(startsMonth ? day.formatted(.dateTime.month(.abbreviated)).uppercased()
                                 : day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(isToday ? Theme.working : (startsMonth ? Theme.secondary : Theme.tertiary))
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(selected ? Color.black : (isWeekend ? Theme.secondary : Theme.primary))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(selected ? Color.white : Color.white.opacity(hovered ? 0.08 : 0)))
                Circle()
                    .fill(hasEvents ? (selected ? Theme.primary : Theme.tertiary) : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Motion.tap) { hovered = hovering } }
        .animation(Motion.swap, value: selected)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var isWeekend: Bool { Calendar.current.isDateInWeekend(day) }
}

private struct Agenda: View {
    let service: CalendarService
    let events: [CalendarEvent]
    @Environment(\.islandStyle) private var style

    var body: some View {
        if events.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "sun.horizon")
                    .foregroundStyle(Theme.tertiary)
                Text(Calendar.current.isDateInToday(service.selectedDay) ? "Nothing else today." : "Nothing scheduled.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: style.edge.isSide ? .infinity : nil)
        } else {
            ScrollView(.vertical) {
                VStack(spacing: 6) {
                    ForEach(events) { event in
                        EventRow(event: event) { service.openInCalendar(event) }
                    }
                }
            }
            .scrollIndicators(.never)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .id(service.selectedDay)
            .transition(.opacity.animation(Motion.swap))
        }
    }
}

private struct EventRow: View {
    let event: CalendarEvent
    let open: () -> Void
    @State private var hovered = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let live = event.isHappening(at: context.date)
            HStack(spacing: 10) {
                Button(action: open) { details(live: live) }
                    .buttonStyle(.plain)
                    .help("Open in Calendar")
                if let url = event.meetingURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Join", systemImage: "video.fill")
                    }
                    .buttonStyle(PillButtonStyle(kind: live ? .primary : .secondary))
                } else if live {
                    Text("Now")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.done)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(hovered ? 0.09 : 0.05))
            )
            .onHover { hovering in withAnimation(Motion.tap) { hovered = hovering } }
        }
    }

    private func details(live: Bool) -> some View {
            HStack(spacing: 10) {
                Capsule()
                    .fill(Color(nsColor: event.color))
                    .frame(width: 3.5, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(Theme.title(12))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(timeText)
                        if let location = event.location, event.meetingURL == nil {
                            Text("·")
                            Text(location).lineLimit(1)
                        }
                    }
                    .font(Theme.body(10.5))
                    .foregroundStyle(live ? Theme.done : Theme.secondary)
                }
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
    }

    private var timeText: String {
        if event.isAllDay { return "All day" }
        let start = event.start.formatted(date: .omitted, time: .shortened)
        let end = event.end.formatted(date: .omitted, time: .shortened)
        return "\(start) – \(end)"
    }
}
