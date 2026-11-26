import AppKit
import EventKit
import Observation

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String?
    let color: NSColor
    let meetingURL: URL?
    let calendarItemURL: URL?

    func isHappening(at date: Date) -> Bool { start <= date && date < end }
}

/// The weeks ahead from the Mac's calendars (iCloud, Google, Exchange: whatever Calendar.app shows).
@Observable
final class CalendarService {
    enum Access: Equatable { case unknown, granted, denied }

    private(set) var access: Access = .unknown
    private(set) var events: [CalendarEvent] = []
    var selectedDay: Date = Calendar.current.startOfDay(for: .now)

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var observer: Any?
    @ObservationIgnored fileprivate var isDemo = false

    /// How far ahead the day rail reaches: a week shows at once, two-finger scroll for the rest.
    static let span = 28

    var days: [Date] {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<Self.span).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
    }

    func events(on day: Date) -> [CalendarEvent] {
        events.filter { Calendar.current.isDate($0.start, inSameDayAs: day) || ($0.start < day && $0.end > day) }
    }

    /// What's next today, for the closed island and the status line.
    var nextEvent: CalendarEvent? {
        let now = Date.now
        return events.first { !$0.isAllDay && $0.end > now && Calendar.current.isDateInToday($0.start) }
    }

    func start() {
        access = Self.currentAccess
        if access == .granted { load() }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.load() }
        }
    }

    /// Asked the first time the Calendar page opens, never at launch.
    func requestAccessIfNeeded() {
        guard !isDemo, access == .unknown else { load(); return }
        Task {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            access = granted ? .granted : .denied
            if granted { load() }
        }
    }

    private static var currentAccess: Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .unknown
        default: .denied
        }
    }

    func load() {
        guard !isDemo, Self.currentAccess == .granted else { return }
        access = .granted
        let start = Calendar.current.startOfDay(for: .now)
        guard let end = Calendar.current.date(byAdding: .day, value: Self.span, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                CalendarEvent(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title?.nilIfBlank ?? "Untitled",
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    location: event.location?.nilIfBlank,
                    color: event.calendar.color ?? .systemBlue,
                    meetingURL: Self.meetingURL(in: [event.url?.absoluteString, event.location, event.notes]),
                    calendarItemURL: URL(string: "ical://ekevent/\(event.calendarItemExternalIdentifier ?? "")?method=show&options=more")
                )
            }
    }

    /// The video-call link in an invitation, if there is one.
    private static func meetingURL(in fields: [String?]) -> URL? {
        let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "facetime.apple.com", "whereby.com", "around.co"]
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        for text in fields.compactMap({ $0 }) {
            let matches = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
            if let url = matches.compactMap(\.url).first(where: { url in hosts.contains { url.host?.contains($0) == true } }) {
                return url
            }
        }
        return nil
    }

    func openInCalendar(_ event: CalendarEvent) {
        if let url = event.calendarItemURL, NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
    }
}

extension CalendarService {
    func loadDemo(_ demo: [CalendarEvent]) {
        isDemo = true
        access = .granted
        events = demo.sorted { $0.start < $1.start }
    }
}
