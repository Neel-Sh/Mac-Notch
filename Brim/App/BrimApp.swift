import AppKit
import ServiceManagement
import SwiftUI

@main
struct BrimApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Brim", systemImage: "capsule.tophalf.filled") {
            MenuContent(delegate: delegate)
        }
        Settings {
            SettingsView(hub: delegate.agents)
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
        Button("Open Agents") { delegate.island.open(.agents) }
        Button("Calendar") { delegate.island.open(.calendar) }
        Button("Tasks") { delegate.island.open(.tasks) }
        Button("Weather") { delegate.island.open(.weather) }
        Button("Shelf") { delegate.island.open(.shelf) }
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

struct SettingsView: View {
    let hub: AgentHub
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { hub.hooksInstalled }, set: { hub.setHooksInstalled($0) })) {
                    Text("Live detail and approvals")
                    Text("Adds one hook to ~/.claude/settings.json so Brim can show what each session is doing and let you Allow or Deny from the notch. Takes effect in new sessions. Turning it off removes exactly what Brim added.")
                }
                if let error = hub.lastError {
                    Text(error).foregroundStyle(.red)
                }
            } header: {
                Text("Claude Code")
            }
            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            } header: {
                Text("General")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
