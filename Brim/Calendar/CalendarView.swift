import SwiftUI

struct CalendarPage: View {
    let service: CalendarService

    var body: some View {
        switch service.access {
        case .granted:
            VStack(spacing: 10) {
                DayRail(service: service)
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

    private func prompt(_ title: String, _ detail: String, button: String, action: @escaping () -> Void) -> some View {
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

/// Month on the left, the week as a rail of days. A dot under a day means something's on.
private struct DayRail: View {
    let service: CalendarService

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(service.selectedDay.formatted(.dateTime.month(.abbreviated)))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(service.selectedDay.formatted(.dateTime.year()))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
            }
            .frame(width: 58, alignment: .leading)

            Rectangle().fill(Theme.hairline).frame(width: 1, height: 38)

            HStack(spacing: 4) {
                ForEach(service.days, id: \.self) { day in
                    DayCell(day: day,
                            selected: Calendar.current.isDate(day, inSameDayAs: service.selectedDay),
                            hasEvents: !service.events(on: day).isEmpty) {
                        withAnimation(Motion.swap) { service.selectedDay = day }
                    }
                }
            }
        }
    }
}

private struct DayCell: View {
    let day: Date
    let selected: Bool
    let hasEvents: Bool
    let action: () -> Void
    @State private var hovered = false

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.weekday(.narrow)))
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(isToday ? Theme.working : Theme.tertiary)
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 15, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(selected ? Color.black : Theme.primary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(selected ? Color.white : Color.white.opacity(hovered ? 0.08 : 0)))
                Circle()
                    .fill(hasEvents ? Theme.secondary : .clear)
                    .frame(width: 3.5, height: 3.5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(Motion.tap) { hovered = hovering } }
        .animation(Motion.swap, value: selected)
    }
}

private struct Agenda: View {
    let service: CalendarService
    let events: [CalendarEvent]

    var body: some View {
        if events.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "sun.horizon")
                    .foregroundStyle(Theme.tertiary)
                Text(Calendar.current.isDateInToday(service.selectedDay) ? "Nothing else today." : "Nothing scheduled.")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
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
