import ServiceManagement
import SwiftUI

/// Brim's Settings window. Every control writes through `Preferences`, so the island follows live.
struct SettingsView: View {
    let delegate: AppDelegate
    /// `-settingsTab general|appearance|pages|agents` picks the tab Settings opens on, for screenshots.
    @State private var page = UserDefaults.standard.string(forKey: "settingsTab").flatMap(Page.init(rawValue:)) ?? .general

    private enum Page: String { case general, appearance, pages, agents }

    var body: some View {
        TabView(selection: $page) {
            Tab("General", systemImage: "gearshape", value: Page.general) {
                GeneralSettings(island: delegate.island)
            }
            Tab("Appearance", systemImage: "paintpalette", value: Page.appearance) {
                AppearanceSettings(island: delegate.island)
            }
            Tab("Pages", systemImage: "square.grid.2x2", value: Page.pages) {
                PagesSettings()
            }
            Tab("Claude Code", systemImage: "terminal", value: Page.agents) {
                AgentSettings(hub: delegate.agents)
            }
        }
        .frame(width: 540)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    let island: IslandController
    @Bindable private var prefs = Preferences.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("Opening") {
                Picker("Open the island on", selection: $prefs.openTrigger) {
                    ForEach(OpenTrigger.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if prefs.openTrigger == .hover {
                    LabeledContent {
                        Slider(value: $prefs.hoverDelay, in: 0...0.6) {
                            EmptyView()
                        } minimumValueLabel: {
                            Text("Instant").font(.caption).foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Text("Relaxed").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(width: 240)
                    } label: {
                        Text("Hover delay")
                        Text("\(Int((prefs.hoverDelay * 100).rounded()) * 10) ms before it opens")
                    }
                } else {
                    Text("Click the notch to open the island. Click anywhere else, or press Esc, to close it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Picker(selection: $prefs.shortcut) {
                    ForEach(ToggleShortcut.allCases) { Text($0.title).tag($0) }
                } label: {
                    Text("Keyboard shortcut")
                    Text("Opens and closes the island from any app.")
                }
                Toggle(isOn: $prefs.haptics) {
                    Text("Haptic feedback")
                    Text("A light tap on the trackpad as the island opens.")
                }
            }

            Section("Live activity") {
                Toggle(isOn: $prefs.wingsForMusic) {
                    Text("Now playing beside the notch")
                    Text("Album art and a level meter while music plays.")
                }
                Toggle(isOn: $prefs.wingsForAgents) {
                    Text("Working agents beside the notch")
                    Text("What your Claude Code sessions are doing, at a glance.")
                }
            }

            Section("System") {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section {
                HStack {
                    Text("Brim \(Bundle.main.shortVersion)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset All Settings…") { confirmReset = true }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Reset all of Brim's settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { withAnimation(Motion.resize) { prefs.resetToDefaults() } }
        } message: {
            Text("Appearance, position, pages and behaviour go back to how Brim started. Your tasks, shelf and Claude Code hook stay as they are.")
        }
    }
}

// MARK: - Appearance

private struct AppearanceSettings: View {
    let island: IslandController
    @Bindable private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    ForEach(IslandEdge.allCases) { edge in
                        ChoiceCard(title: edge.title, selected: prefs.edge == edge) {
                            withAnimation(Motion.resize) { prefs.edge = edge }
                        } preview: {
                            MiniScreen(edge: edge, compact: prefs.compact, glass: prefs.material == .glass)
                        }
                    }
                }
                .padding(.vertical, 4)
                if prefs.edge.isSide {
                    LabeledContent("Height on screen") {
                        Slider(value: $prefs.sideOffset, in: 0...1) {
                            EmptyView()
                        } minimumValueLabel: {
                            Image(systemName: "arrow.up.to.line").foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Image(systemName: "arrow.down.to.line").foregroundStyle(.secondary)
                        }
                        .frame(width: 240)
                    }
                }
            } header: {
                Text("Position")
            } footer: {
                Text(prefs.edge.isSide
                     ? "Docked to a side, Brim rests as a slim pill on the screen edge and grows out of it into a panel, its pages in a column along the edge."
                     : "Brim grows out of the notch, or out of the top centre on displays without one.")
                    .settingsFooter()
            }

            Section("Size") {
                HStack(spacing: 12) {
                    ChoiceCard(title: "Standard", selected: !prefs.compact) {
                        withAnimation(Motion.resize) { prefs.compact = false }
                    } preview: {
                        MiniScreen(edge: prefs.edge, compact: false, glass: prefs.material == .glass)
                    }
                    ChoiceCard(title: "Compact", selected: prefs.compact) {
                        withAnimation(Motion.resize) { prefs.compact = true }
                    } preview: {
                        MiniScreen(edge: prefs.edge, compact: true, glass: prefs.material == .glass)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                HStack(spacing: 12) {
                    ForEach(IslandMaterial.allCases) { material in
                        ChoiceCard(title: material.title, selected: prefs.material == material) {
                            withAnimation(Motion.swap) { prefs.material = material }
                        } preview: {
                            MiniScreen(edge: prefs.edge, compact: prefs.compact, glass: material == .glass)
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Material")
            } footer: {
                Text(prefs.material == .glass
                     ? "Solid black where it meets the bezel, fading into clear glass toward its edge."
                     : "Pure black, so the island and the notch read as one piece of hardware.")
                    .settingsFooter()
            }

            Section {
                HStack {
                    Text("See your changes on the real island.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Preview Island") { island.toggle() }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Pages

private struct PagesSettings: View {
    @Bindable private var prefs = Preferences.shared

    var body: some View {
        Form {
            Section {
                ForEach(IslandTab.allCases) { tab in
                    let visible = prefs.isVisible(tab)
                    Toggle(isOn: Binding(get: { visible }, set: { prefs.setVisible(tab, $0) })) {
                        Label {
                            Text(tab.title)
                        } icon: {
                            Group {
                                if tab == .agents { BotGlyph(size: 14) } else { Image(systemName: tab.symbol) }
                            }
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        }
                    }
                    .disabled(visible && prefs.visibleTabs.count == 1)
                }
            } header: {
                Text("Pages")
            } footer: {
                Text("Hidden pages leave the island's tab bar and the menu. At least one stays.")
                    .settingsFooter()
            }

            Section {
                Picker(selection: $prefs.homeTab) {
                    Text("Where I left off").tag(IslandTab?.none)
                    Divider()
                    ForEach(prefs.visibleTabs) { Text($0.title).tag(IslandTab?.some($0)) }
                } label: {
                    Text("Open on")
                    Text("The page the island shows when it opens.")
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Claude Code

private struct AgentSettings: View {
    let hub: AgentHub
    @Bindable private var prefs = Preferences.shared

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
                Text("Hook")
            }

            Section("When a session needs you") {
                Toggle(isOn: $prefs.peekOnAttention) {
                    Text("Peek out of the notch")
                    Text("Opens just enough to answer a permission request or see that a session finished.")
                }
                Toggle(isOn: $prefs.soundOnAttention) {
                    Text("Play a sound")
                    Text("A soft chime when a session asks for permission or input.")
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Pieces

private extension Text {
    func settingsFooter() -> some View {
        font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension Bundle {
    var shortVersion: String { object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
}

/// A picture with a caption that selects on click, like System Settings' appearance swatches.
private struct ChoiceCard<Preview: View>: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let preview: Preview
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                preview
                    .frame(height: 86)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .padding(3)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(hovered ? 0.22 : 0.1),
                                          lineWidth: selected ? 2.5 : 1)
                    }
                Text(title)
                    .font(.callout.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .frame(maxWidth: .infinity)
        .onHover { hovered = $0 }
        .animation(Motion.tap, value: selected)
        .animation(Motion.tap, value: hovered)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A tiny Mac screen with the island open on it, drawn in the style being chosen.
private struct MiniScreen: View {
    let edge: IslandEdge
    let compact: Bool
    let glass: Bool

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack(alignment: edge.alignment) {
                wallpaper
                VStack(spacing: 0) {
                    Rectangle().fill(.white.opacity(0.18)).frame(height: 5)
                    Spacer(minLength: 0)
                }
                island(in: size)
                    .padding(.top, edge.isSide ? 5 : 0)
            }
        }
    }

    private var wallpaper: some View {
        LinearGradient(colors: [Color(red: 0.16, green: 0.2, blue: 0.5), Color(red: 0.55, green: 0.3, blue: 0.62),
                                Color(red: 0.98, green: 0.58, blue: 0.42)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .bottomTrailing) {
                Circle().fill(Color(red: 1, green: 0.8, blue: 0.5).opacity(0.7)).frame(width: 46).blur(radius: 14).offset(x: 6, y: 10)
            }
    }

    private func island(in screen: CGSize) -> some View {
        let along: CGFloat = edge.isSide ? (compact ? 46 : 54) : (compact ? 66 : 86)
        let depth: CGFloat = edge.isSide ? (compact ? 36 : 44) : (compact ? 34 : 42)
        let width = edge.isSide ? depth : along
        let height = edge.isSide ? along : depth
        let shape = IslandShape(bottomRadius: 9, shoulder: 5, edge: edge)
        return ZStack {
            if glass {
                Color.clear.glassEffect(.clear, in: shape)
                shape.fill(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.45),
                                                  .init(color: .black.opacity(0.05), location: 1)],
                                          startPoint: edge.flushPoint, endPoint: edge.farPoint))
                shape.stroke(LinearGradient(colors: [.clear, .white.opacity(0.45)],
                                                  startPoint: edge.flushPoint, endPoint: edge.farPoint), lineWidth: 1.5)
            } else {
                shape.fill(.black)
            }
            lines(edge: edge)
                .padding(edge.isSide ? .vertical : .horizontal, 5)
        }
        .clipShape(shape)
        .frame(width: width, height: height)
    }

    /// Stand-ins for the page: a row of tabs and two lines of content.
    private func lines(edge: IslandEdge) -> some View {
        let ink = Color.white.opacity(0.5)
        return Group {
            if edge.isSide {
                let dots = VStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { _ in Circle().fill(ink.opacity(0.6)).frame(width: 4) }
                }
                let page = VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(ink).frame(width: 12, height: 3)
                    Capsule().fill(ink.opacity(0.6)).frame(width: 18, height: 3)
                    Capsule().fill(ink.opacity(0.6)).frame(width: 15, height: 3)
                }
                HStack(spacing: 6) {
                    if edge == .left { dots; page } else { page; dots }
                }
                .padding(.horizontal, 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .left ? .leading : .trailing)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 3) {
                        ForEach(0..<4, id: \.self) { _ in Circle().fill(ink.opacity(0.6)).frame(width: 4) }
                    }
                    Capsule().fill(ink).frame(width: compact ? 30 : 44, height: 3)
                    Capsule().fill(ink.opacity(0.6)).frame(width: compact ? 22 : 34, height: 3)
                }
                .padding(.top, compact ? 11 : 13)
                .padding(.leading, 9)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

private extension IslandEdge {
    var flushPoint: UnitPoint {
        switch self {
        case .top: .top
        case .left: .leading
        case .right: .trailing
        }
    }
    var farPoint: UnitPoint { UnitPoint(x: 1 - flushPoint.x, y: 1 - flushPoint.y) }
}
