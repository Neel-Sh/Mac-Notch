import AppKit
import Observation

/// Where the island lives.
nonisolated enum IslandEdge: String, CaseIterable, Identifiable {
    case top, left, right
    var id: Self { self }

    var title: String {
        switch self {
        case .top: "Notch"
        case .left: "Left edge"
        case .right: "Right edge"
        }
    }

    var isSide: Bool { self != .top }
}

enum IslandMaterial: String, CaseIterable, Identifiable {
    case black, glass
    var id: Self { self }
    var title: String { self == .black ? "Black" : "Liquid Glass" }
}

enum OpenTrigger: String, CaseIterable, Identifiable {
    case hover, click
    var id: Self { self }
    var title: String { self == .hover ? "Hover" : "Click" }
}

/// A global shortcut that opens and closes the island from anywhere.
enum ToggleShortcut: String, CaseIterable, Identifiable {
    case off, optionCommandB, controlOptionSpace, controlCommandN
    var id: Self { self }

    var title: String {
        switch self {
        case .off: "None"
        case .optionCommandB: "⌥⌘B"
        case .controlOptionSpace: "⌃⌥Space"
        case .controlCommandN: "⌃⌘N"
        }
    }
}

/// Everything the island's look depends on, in one value so layout can be a pure function of it.
nonisolated struct IslandStyle: Equatable {
    var edge: IslandEdge = .top
    var compact = false
    var glass = false
}

/// Brim's settings. Each one is stored in UserDefaults the moment it changes, and every view reading
/// one follows it live, so the island restyles itself while Settings is open.
@Observable
final class Preferences {
    static let shared = Preferences()

    @ObservationIgnored private let defaults = UserDefaults.standard
    /// While reading settings in, don't write them back: a `-pref.edge left` launch argument stays one launch.
    @ObservationIgnored private var isLoading = false

    /// Demo mode never saves anything, so a recording that restyles the island leaves your settings alone.
    @ObservationIgnored private let isDemo = UserDefaults.standard.bool(forKey: "demo")

    private func save(_ value: Any?, forKey key: String) {
        guard !isLoading, !isDemo else { return }
        defaults.set(value, forKey: key)
    }

    // Appearance
    var compact: Bool { didSet { save(compact, forKey: Key.compact) } }
    var material: IslandMaterial { didSet { save(material.rawValue, forKey: Key.material) } }
    var edge: IslandEdge { didSet { save(edge.rawValue, forKey: Key.edge) } }
    /// For the side edges: 0 is the top of the screen, 1 the bottom.
    var sideOffset: Double { didSet { save(sideOffset, forKey: Key.sideOffset) } }

    // Behaviour
    var openTrigger: OpenTrigger { didSet { save(openTrigger.rawValue, forKey: Key.openTrigger) } }
    /// How long the pointer rests on the island before it opens, in seconds.
    var hoverDelay: Double { didSet { save(hoverDelay, forKey: Key.hoverDelay) } }
    var haptics: Bool { didSet { save(haptics, forKey: Key.haptics) } }
    var shortcut: ToggleShortcut { didSet { save(shortcut.rawValue, forKey: Key.shortcut) } }

    // Live activity
    var wingsForMusic: Bool { didSet { save(wingsForMusic, forKey: Key.wingsForMusic) } }
    var wingsForAgents: Bool { didSet { save(wingsForAgents, forKey: Key.wingsForAgents) } }
    var peekOnAttention: Bool { didSet { save(peekOnAttention, forKey: Key.peekOnAttention) } }
    var soundOnAttention: Bool { didSet { save(soundOnAttention, forKey: Key.soundOnAttention) } }

    // Pages
    var hiddenTabs: Set<IslandTab> {
        didSet { save(hiddenTabs.map(\.rawValue).sorted(), forKey: Key.hiddenTabs) }
    }
    /// The page a hover opens on. Nil: wherever you left it.
    var homeTab: IslandTab? { didSet { save(homeTab?.rawValue, forKey: Key.homeTab) } }

    var style: IslandStyle { IslandStyle(edge: edge, compact: compact, glass: material == .glass) }

    var visibleTabs: [IslandTab] { IslandTab.allCases.filter { !hiddenTabs.contains($0) } }

    func isVisible(_ tab: IslandTab) -> Bool { !hiddenTabs.contains(tab) }

    /// Hide or show a page. The last visible page can't be hidden.
    func setVisible(_ tab: IslandTab, _ visible: Bool) {
        if visible {
            hiddenTabs.remove(tab)
        } else if visibleTabs.count > 1 {
            hiddenTabs.insert(tab)
            if homeTab == tab { homeTab = nil }
        }
    }

    func resetToDefaults() {
        for key in Key.all { defaults.removeObject(forKey: key) }
        load()
    }

    private init() {
        compact = false; material = .black; edge = .top; sideOffset = 0.5
        openTrigger = .hover; hoverDelay = 0.12; haptics = true; shortcut = .off
        wingsForMusic = true; wingsForAgents = true; peekOnAttention = true; soundOnAttention = false
        hiddenTabs = []; homeTab = nil
        load()
    }

    private func load() {
        isLoading = true
        defer { isLoading = false }
        let d = defaults
        compact = d.bool(forKey: Key.compact)
        material = d.string(forKey: Key.material).flatMap(IslandMaterial.init(rawValue:)) ?? .black
        edge = d.string(forKey: Key.edge).flatMap(IslandEdge.init(rawValue:)) ?? .top
        sideOffset = d.object(forKey: Key.sideOffset) as? Double ?? 0.5
        openTrigger = d.string(forKey: Key.openTrigger).flatMap(OpenTrigger.init(rawValue:)) ?? .hover
        hoverDelay = d.object(forKey: Key.hoverDelay) as? Double ?? 0.12
        haptics = d.object(forKey: Key.haptics) as? Bool ?? true
        shortcut = d.string(forKey: Key.shortcut).flatMap(ToggleShortcut.init(rawValue:)) ?? .off
        wingsForMusic = d.object(forKey: Key.wingsForMusic) as? Bool ?? true
        wingsForAgents = d.object(forKey: Key.wingsForAgents) as? Bool ?? true
        peekOnAttention = d.object(forKey: Key.peekOnAttention) as? Bool ?? true
        soundOnAttention = d.bool(forKey: Key.soundOnAttention)
        hiddenTabs = Set((d.stringArray(forKey: Key.hiddenTabs) ?? []).compactMap(IslandTab.init(rawValue:)))
        if hiddenTabs.count >= IslandTab.allCases.count { hiddenTabs = [] }
        homeTab = d.string(forKey: Key.homeTab).flatMap(IslandTab.init(rawValue:))
    }

    private enum Key {
        static let compact = "pref.compact"
        static let material = "pref.material"
        static let edge = "pref.edge"
        static let sideOffset = "pref.sideOffset"
        static let openTrigger = "pref.openTrigger"
        static let hoverDelay = "pref.hoverDelay"
        static let haptics = "pref.haptics"
        static let shortcut = "pref.shortcut"
        static let wingsForMusic = "pref.wingsForMusic"
        static let wingsForAgents = "pref.wingsForAgents"
        static let peekOnAttention = "pref.peekOnAttention"
        static let soundOnAttention = "pref.soundOnAttention"
        static let hiddenTabs = "pref.hiddenTabs"
        static let homeTab = "pref.homeTab"
        static let all = [compact, material, edge, sideOffset, openTrigger, hoverDelay, haptics, shortcut,
                          wingsForMusic, wingsForAgents, peekOnAttention, soundOnAttention, hiddenTabs, homeTab]
    }
}
