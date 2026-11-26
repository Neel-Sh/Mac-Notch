import AppKit

/// Made-up content for screenshots and recordings: `open Brim.app --args -demo YES -openTab agents`.
/// Every name, project, place and event here is fictional, and none of it is saved.
enum DemoContent {
    static func load(into delegate: AppDelegate) {
        let now = Date.now
        delegate.agents.loadDemo(sessions(now: now))
        delegate.weather.loadDemo(forecast(now: now))
        delegate.calendar.loadDemo(events(now: now))
        delegate.tasks.loadDemo(tasks(now: now))
        delegate.shelf.loadDemo(shelfFiles)
        delegate.nowPlaying.loadDemo(title: "Golden Hour Drive", artist: "The Night Shift",
                                     album: "Coastline", artwork: artwork())
    }

    /// Plays the island through its states on its own, for the README recording (`-demoTour YES`).
    static func tour(_ island: IslandController) async {
        func wait(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }
        await wait(1.6)
        if let ask = island.agents.sessions.first { island.peek(ask) }
        await wait(2.6)
        island.endPeek()
        await wait(1.2)
        island.open(.agents)
        for tab in [IslandTab.calendar, .weather, .tasks, .shelf] {
            await wait(2.2)
            island.select(tab)
        }
        await wait(2.2)
        island.close()
    }

    /// The terminal the sessions appear to run in, when one is open, so rows get a real app icon.
    private static var hostPID: pid_t {
        let ids = ["com.mitchellh.ghostty", "com.apple.Terminal", "com.googlecode.iterm2", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92"]
        return NSWorkspace.shared.runningApplications.first { ids.contains($0.bundleIdentifier ?? "") }?.processIdentifier ?? 0
    }

    static func sessions(now: Date) -> [AgentSession] {
        func session(_ id: String, _ title: String, _ project: String, _ phase: AgentSession.Phase,
                     since minutes: Double, working: Double? = nil, message: String? = nil, ask: PendingAsk? = nil) -> AgentSession {
            AgentSession(id: id, pid: hostPID, cwd: URL(fileURLWithPath: "/Users/demo/Code/\(project)"), title: title,
                         phase: phase, phaseSince: now - minutes * 60,
                         workingSince: working.map { now - $0 * 60 }, startedAt: now - 3600,
                         lastPrompt: title, lastMessage: message, toolsRun: 14, ask: ask, isHeadless: false)
        }
        let ask = PendingAsk(id: UUID(), tool: ToolActivity(name: "Bash", detail: "Run the test suite"),
                             command: "xcodebuild test -scheme Orbit -destination 'platform=iOS Simulator,name=iPhone 17'",
                             questions: [], receivedAt: now - 20)
        return [
            session("demo-1", "Add offline sync to the iOS app", "Orbit", .needsPermission, since: 0.3, working: 9, ask: ask),
            session("demo-2", "Move billing to usage-based pricing", "ledger-api",
                    .tool(ToolActivity(name: "Edit", detail: "src/pricing/PricingEngine.ts")), since: 0.2, working: 4),
            session("demo-3", "Draft the launch announcement", "marketing-site", .thinking, since: 0.1, working: 2),
            session("demo-4", "Fix the flaky checkout test", "storefront", .finished, since: 0.5,
                    message: "Fixed a race in CartStore. All 212 tests pass."),
            session("demo-5", "Tidy up the auth middleware", "gateway", .idle, since: 26),
        ]
    }

    static func forecast(now: Date) -> Forecast {
        let calendar = Calendar.current
        let hour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let temps: [Double] = [11, 11, 10, 10, 9, 9, 9]
        let codes = [63, 63, 61, 61, 3, 3, 2]
        let hours = temps.indices.map {
            Forecast.Hour(time: hour + Double($0) * 3600, temperature: temps[$0], code: codes[$0], isDay: true, rainChance: [80, 70, 60, 40, 20, 10, 10][$0])
        }
        let today = calendar.startOfDay(for: now)
        let days: [(Double, Double, Int, Int)] = [(8, 13, 63, 70), (7, 14, 61, 40), (9, 17, 2, 10), (10, 16, 3, 20), (8, 12, 61, 60)]
        return Forecast(
            place: "Cupertino", temperature: 11, feelsLike: 9, humidity: 88, windKmh: 18, rainChanceNow: 80,
            sunrise: today + 7 * 3600, sunset: today + 17 * 3600, code: 63, isDay: true, hours: hours,
            days: days.enumerated().map { index, day in
                Forecast.Day(date: today + Double(index) * 86_400, low: day.0, high: day.1, code: day.2, rainChance: day.3)
            },
            fetchedAt: now
        )
    }

    static func events(now: Date) -> [CalendarEvent] {
        let today = Calendar.current.startOfDay(for: now)
        let meet = URL(string: "https://meet.google.com/abc-defg-hij")
        let zoom = URL(string: "https://zoom.us/j/1234567890")
        func event(_ title: String, day: Int, _ start: Double, _ length: Double, _ color: NSColor,
                   location: String? = nil, url: URL? = nil) -> CalendarEvent {
            let begin = today + Double(day) * 86_400 + start * 3600
            return CalendarEvent(id: UUID().uuidString, title: title, start: begin, end: begin + length * 3600,
                                 isAllDay: false, location: location, color: color, meetingURL: url, calendarItemURL: nil)
        }
        // Today's first event is happening now, so the screenshot shows the live state.
        let current = Double(Calendar.current.component(.hour, from: now))
        return [
            event("Design review", day: 0, current, 1, .systemPurple, url: meet),
            event("Pairing with Maya", day: 0, current + 1.5, 1, .systemOrange, location: "Studio B"),
            event("Ship Brim 0.2", day: 0, current + 3, 1, .systemBlue, url: zoom),
            event("1:1 with Alex", day: 1, 10, 0.5, .systemGreen, url: zoom),
            event("Dentist", day: 3, 9, 1, .systemRed, location: "Main St"),
            event("Offsite planning", day: 4, 14, 2, .systemPurple),
        ]
    }

    static func tasks(now: Date) -> [TaskItem] {
        [
            TaskItem(id: UUID(), text: "Reply to Sam about the launch post", isDone: false, createdAt: now - 60),
            TaskItem(id: UUID(), text: "Renew the brim.app domain", isDone: false, createdAt: now - 120),
            TaskItem(id: UUID(), text: "Try the new icon in Icon Composer", isDone: false, createdAt: now - 180),
            TaskItem(id: UUID(), text: "Book flights for the offsite", isDone: true, createdAt: now - 600, doneAt: now - 300),
        ]
    }

    static var shelfFiles: [URL] {
        let folder = URL(fileURLWithPath: "/System/Library/Desktop Pictures")
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".heic") }
            .sorted()
            .prefix(3)
        return names.map { folder.appendingPathComponent($0) }
    }

    /// Album art drawn on the fly, so the repo ships no third-party artwork.
    static func artwork() -> NSImage {
        NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 1, green: 0.55, blue: 0.3, alpha: 1),
                                NSColor(red: 0.85, green: 0.25, blue: 0.45, alpha: 1),
                                NSColor(red: 0.25, green: 0.15, blue: 0.45, alpha: 1)])?
                .draw(in: rect, angle: -70)
            NSColor(white: 1, alpha: 0.85).setFill()
            NSBezierPath(ovalIn: NSRect(x: 105, y: 150, width: 90, height: 90)).fill()
            return true
        }
    }
}
