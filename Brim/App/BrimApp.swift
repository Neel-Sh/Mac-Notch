import AppKit
import SwiftUI

@main
struct BrimApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Brim", systemImage: "capsule.tophalf.filled") {
            MenuContent(delegate: delegate)
        }
        Settings {
            SettingsView(delegate: delegate)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let agents = AgentHub()
    let calendar = CalendarService()
    let tasks = TaskStore()
    let weather = WeatherService()
    let nowPlaying = NowPlaying()
    let shelf = ShelfStore()
    lazy var island = IslandController(agents: agents, calendar: calendar, tasks: tasks, weather: weather,
                                       nowPlaying: nowPlaying, shelf: shelf)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Unit tests host inside the app; don't take over the notch or the agent socket while they run.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        if UserDefaults.standard.bool(forKey: "demo") {
            DemoContent.load(into: self)
        } else {
            agents.start()
            nowPlaying.start()
            weather.start()
            calendar.start()
        }
        island.start()
        if UserDefaults.standard.bool(forKey: "demoPeek"), let first = agents.sessions.first {
            island.peek(first)
        }
        if UserDefaults.standard.bool(forKey: "demoTour") {
            Task { await DemoContent.tour(island) }
        }
        if UserDefaults.standard.bool(forKey: "demoStyleTour") {
            Task { await DemoContent.styleTour(island) }
        }
        // `-openSettings YES` shows the Settings window on launch, for screenshots.
        if UserDefaults.standard.bool(forKey: "openSettings") {
            Task { DemoContent.openSettings() }
        }
        // `-openTab agents|calendar|tasks|weather|media|shelf` opens the island on launch, for screenshots and testing.
        if let tab = UserDefaults.standard.string(forKey: "openTab").flatMap(IslandTab.init(rawValue:)) {
            island.open(tab)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        agents.stop()
    }
}

private struct MenuContent: View {
    let delegate: AppDelegate
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ForEach(Preferences.shared.visibleTabs) { tab in
            Button(tab == .agents ? "Open Agents" : tab.title) { delegate.island.open(tab) }
        }
        Divider()
        Button("Settings…") {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
        Button("Quit Brim") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
