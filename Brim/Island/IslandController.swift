import AppKit
import SwiftUI

/// A borderless panel over the notch. Its frame never moves: all motion happens in SwiftUI inside it,
/// and clicks on its transparent parts fall through to whatever is underneath.
final class IslandPanel: NSPanel {
    init(frame: NSRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        acceptsMouseMovedEvents = true
        appearance = NSAppearance(named: .darkAqua)
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
    }

    /// Key, so SwiftUI controls receive clicks; non-activating, so Brim never steals the active app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow { makeKey() }
        super.sendEvent(event)
    }
}

/// Rejects every point outside the island, so the empty panel around it never eats a click.
final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var hitRect: CGRect = .zero
    var onDragChange: ((Bool) -> Void)?
    var onDropFiles: (([URL]) -> Void)?

    func acceptFileDrops() { registerForDraggedTypes([.fileURL]) }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        onDragChange?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { .copy }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onDragChange?(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                          options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        onDropFiles?(urls)
        onDragChange?(false)
        return !urls.isEmpty
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let y = isFlipped ? local.y : bounds.height - local.y
        guard hitRect.contains(CGPoint(x: local.x, y: y)) else { return nil }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@Observable
final class IslandController {
    let model = IslandModel()
    let agents: AgentHub
    let calendar: CalendarService
    let tasks: TaskStore
    let weather: WeatherService
    let nowPlaying: NowPlaying
    let shelf: ShelfStore
    let prefs = Preferences.shared

    @ObservationIgnored private var panel: IslandPanel?
    @ObservationIgnored private var hosting: IslandHostingView<IslandRootView>?
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var openTask: Task<Void, Never>?
    @ObservationIgnored private var closeWatch: Task<Void, Never>?
    @ObservationIgnored private var peekTask: Task<Void, Never>?
    @ObservationIgnored private var tightenTask: Task<Void, Never>?
    @ObservationIgnored private var lastPresentation: IslandPresentation = .resting
    @ObservationIgnored private lazy var hotKey = HotKey { [weak self] in self?.toggle() }

    init(agents: AgentHub, calendar: CalendarService, tasks: TaskStore, weather: WeatherService,
         nowPlaying: NowPlaying, shelf: ShelfStore) {
        self.agents = agents
        self.calendar = calendar
        self.tasks = tasks
        self.weather = weather
        self.nowPlaying = nowPlaying
        self.shelf = shelf
    }

    func start() {
        model.liveActivity = { [weak self] in
            guard let self else { return false }
            return (self.prefs.wingsForAgents && self.agents.lead != nil)
                || (self.prefs.wingsForMusic && self.nowPlaying.isPlaying)
        }
        model.contentHeight = { [weak self] tab in self?.contentHeight(for: tab) ?? 160 }
        agents.onAttention = { [weak self] session in
            guard let self else { return }
            if self.prefs.soundOnAttention, session.phase.wantsAttention { NSSound(named: "Glass")?.play() }
            if self.prefs.peekOnAttention { self.peek(session) }
        }

        buildPanel()
        installMonitors()
        observeState()
        observePreferences()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.buildPanel() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel?.orderFrontRegardless() }
        }
    }

    /// Each page's natural height, from what it's showing right now.
    private func contentHeight(for tab: IslandTab) -> CGFloat {
        if prefs.edge.isSide { return sideContentHeight(for: tab) }
        switch tab {
        case .agents:
            let rows = agents.ordered
            let banner: CGFloat = agents.hooksInstalled ? 0 : 62
            guard !rows.isEmpty else { return banner + 84 }
            let asks = rows.count { $0.ask != nil && $0.phase == .needsPermission }
            return banner + CGFloat(rows.count) * 54 + CGFloat(asks) * 88
        case .tasks:
            return 34 + 8 + (tasks.items.isEmpty ? 18 : CGFloat(tasks.items.count) * 41 + 4)
        case .calendar:
            guard calendar.access == .granted else { return 60 }
            let count = calendar.events(on: calendar.selectedDay).count
            return 56 + 12 + 8 + (count == 0 ? 44 : CGFloat(min(count, 4)) * 50 - 6)
        case .weather:
            return weather.forecast == nil ? 70 : 226
        case .media:
            return nowPlaying.hasTrack ? MediaPage.artworkSize + 8 : 110
        case .shelf:
            if shelf.items.isEmpty && shelf.history.isEmpty { return 110 }
            let header: CGFloat = 28 + 10
            if shelf.showsRecents && !model.isDropTargeted {
                let rows = CGFloat(max(1, min(shelf.history.count, ShelfPage.visibleRecents)))
                return header + rows * (ShelfPage.recentRowHeight + 7) + 4
            }
            return header + (shelf.items.isEmpty ? 92 : 74 + 10 + 74)
        }
    }

    /// The same, for the portrait layouts of the docked panel.
    private func sideContentHeight(for tab: IslandTab) -> CGFloat {
        let prompt: CGFloat = 156
        switch tab {
        case .agents:
            let rows = agents.ordered
            let banner: CGFloat = agents.hooksInstalled ? 0 : 124
            guard !rows.isEmpty else { return banner + 120 }
            let asks = rows.count { $0.ask != nil && $0.phase == .needsPermission }
            return banner + CGFloat(rows.count) * 55 + CGFloat(asks) * 90 + 4
        case .tasks:
            let composer: CGFloat = 10 + 38
            guard !tasks.items.isEmpty else { return 116 + composer }
            return 28 + 10 + CGFloat(tasks.items.count) * 44 + 4 + composer
        case .calendar:
            guard calendar.access == .granted else { return prompt }
            let count = calendar.events(on: calendar.selectedDay).count
            return 28 + 8 + 56 + 12 + (count == 0 ? 64 : CGFloat(min(count, 5)) * 50 - 6)
        case .weather:
            guard weather.forecast != nil else { return prompt }
            let days: CGFloat = prefs.compact ? 4 : 5
            return 74 + 14 + 62 + 16 + days * 24 - 5 + 16 + 50
        case .media:
            return nowPlaying.hasTrack ? MediaPage.portraitArtwork(compact: prefs.compact) + 142 : 130
        case .shelf:
            if shelf.items.isEmpty && shelf.history.isEmpty { return prompt }
            let header: CGFloat = 28 + 10
            if shelf.showsRecents && !model.isDropTargeted {
                let rows = CGFloat(max(2, min(shelf.history.count, 6)))
                return header + rows * (ShelfPage.recentRowHeight + 7) + 4
            }
            guard !shelf.items.isEmpty else { return header + 120 }
            let columns = prefs.compact ? 3 : 4
            let rows = min((shelf.items.count + (model.isDropTargeted ? 1 : 0) + columns - 1) / columns, 3)
            return header + CGFloat(rows) * 88 + 4 + 10 + 74
        }
    }

    // MARK: Panel

    private static var targetScreen: NSScreen? {
        NSScreen.screens.first { ($0.auxiliaryTopLeftArea?.width ?? 0) > 0 } ?? NSScreen.main
    }

    private func buildPanel() {
        guard let screen = Self.targetScreen else { return }
        model.notch = NotchMetrics.of(screen)

        let style = prefs.style
        let size = IslandLayout.panelSize(style)
        let origin: NSPoint
        switch style.edge {
        case .top:
            let midX: CGFloat
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea, left.width > 0 {
                midX = (left.maxX + right.minX) / 2
            } else {
                midX = screen.frame.midX
            }
            origin = NSPoint(x: midX - size.width / 2, y: screen.frame.maxY - size.height)
        case .left, .right:
            // Centred on the chosen point along the edge, kept clear of the menu bar and the screen's foot.
            let visible = screen.visibleFrame
            let low = visible.minY + size.height / 2, high = visible.maxY - size.height / 2
            let midY = high >= low ? high - (high - low) * min(max(prefs.sideOffset, 0), 1) : visible.midY
            let x = style.edge == .left ? screen.frame.minX : screen.frame.maxX - size.width
            origin = NSPoint(x: x, y: midY - size.height / 2)
        }
        let frame = screen.backingAlignedRect(NSRect(origin: origin, size: size), options: .alignAllEdgesNearest)

        if let panel {
            panel.setFrame(frame, display: true)
        } else {
            let panel = IslandPanel(frame: frame)
            let hosting = IslandHostingView(rootView: IslandRootView(controller: self))
            hosting.sizingOptions = []
            hosting.frame = NSRect(origin: .zero, size: size)
            hosting.autoresizingMask = [.width, .height]
            hosting.acceptFileDrops()
            hosting.onDragChange = { [weak self] inside in self?.dragChanged(inside) }
            hosting.onDropFiles = { [weak self] urls in
                withAnimation(Motion.swap) { self?.shelf.add(urls) }
            }
            panel.contentView = hosting
            panel.orderFrontRegardless()
            self.panel = panel
            self.hosting = hosting
        }
        hosting?.hitRect = rect(for: model.presentation)
    }

    /// The island inside the panel, top-left origin.
    private func rect(for presentation: IslandPresentation) -> CGRect {
        let page: IslandTab = if case .open(let shown) = presentation { shown } else { model.tab }
        let size = model.size(for: presentation, page: page)
        let panel = IslandLayout.panelSize(prefs.style)
        let origin: CGPoint = switch prefs.edge {
        case .top: CGPoint(x: (panel.width - size.width) / 2, y: 0)
        case .left: CGPoint(x: 0, y: (panel.height - size.height) / 2)
        case .right: CGPoint(x: panel.width - size.width, y: (panel.height - size.height) / 2)
        }
        return CGRect(origin: origin, size: size)
    }

    /// The island in screen coordinates, for pointer tests.
    private func screenRect(for presentation: IslandPresentation) -> CGRect {
        guard let panel else { return .zero }
        let local = rect(for: presentation)
        return CGRect(x: panel.frame.minX + local.minX, y: panel.frame.maxY - local.maxY,
                      width: local.width, height: local.height)
    }

    // MARK: State plumbing

    /// Moving or resizing the island rebuilds its panel; the shortcut re-registers; hidden pages give way.
    private func observePreferences() {
        withObservationTracking {
            _ = prefs.edge
            _ = prefs.compact
            _ = prefs.sideOffset
            _ = prefs.shortcut
            _ = prefs.hiddenTabs
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.preferencesChanged()
                self.observePreferences()
            }
        }
        preferencesChanged()
    }

    private func preferencesChanged() {
        buildPanel()
        hotKey.set(prefs.shortcut)
        if !prefs.isVisible(model.tab), let first = prefs.visibleTabs.first { model.tab = first }
    }

    private func observeState() {
        withObservationTracking {
            _ = model.presentation
            _ = model.size
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.presentationChanged()
                self.observeState()
            }
        }
    }

    private func presentationChanged() {
        let presentation = model.presentation
        let previous = lastPresentation
        lastPresentation = presentation

        // The hit region covers every shape the island passes through, then tightens once settled.
        hosting?.hitRect = rect(for: presentation).union(rect(for: previous))
        tightenTask?.cancel()
        tightenTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self else { return }
            self.hosting?.hitRect = self.rect(for: self.model.presentation)
        }

        // Leaving the Agents page means its finished sessions have been seen.
        if previous == .open(.agents), presentation != previous { agents.acknowledgeFinished() }
        if previous != presentation {
            if case .open(.weather) = presentation { weather.refresh() }
            if case .open(.calendar) = presentation { calendar.load() }
        }

        if !presentation.isExpanded, panel?.isKeyWindow == true {
            // Hand the keyboard back to the app the person was using.
            panel?.resignKey()
            NSWorkspace.shared.frontmostApplication?.activate()
        }
    }

    // MARK: Pointer

    private func installMonitors() {
        let moved: (NSEvent) -> Void = { [weak self] _ in self?.pointerMoved() }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in
            MainActor.assumeIsolated { moved(event) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in
            MainActor.assumeIsolated { moved(event) }
            return event
        }) { monitors.append(local) }
        if let clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.clickedOutside() }
        }) { monitors.append(clicks) }
        if let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { self?.close() }
            return nil
        }) { monitors.append(escape) }
    }

    /// Opening needs intent: the pointer rests on the notch for 120ms. Closing is handled by `watchForExit`.
    private func pointerMoved() {
        guard !model.isHovering else { return }
        let presentation = model.presentation
        let target = presentation.isExpanded ? screenRect(for: presentation) : restingTarget(presentation)
        let inside = target.contains(NSEvent.mouseLocation)

        if model.isPointerNear != (inside && !presentation.isExpanded) {
            withAnimation(Motion.tap) { model.isPointerNear = inside && !presentation.isExpanded }
        }
        guard inside, prefs.openTrigger == .hover else { openTask?.cancel(); openTask = nil; return }
        guard openTask == nil else { return }
        let delay = Int(prefs.hoverDelay * 1000)
        openTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.openTask = nil
            withAnimation(Motion.open) {
                if let home = self.prefs.homeTab, self.prefs.isVisible(home) { self.model.tab = home }
                self.model.isPointerNear = false
                self.model.isHovering = true
            }
            self.didOpen()
            self.watchForExit()
        }
    }

    /// Where the pointer has to be to wake the closed island. A docked pill is thin, so its zone is generous.
    private func restingTarget(_ presentation: IslandPresentation) -> CGRect {
        let rect = screenRect(for: presentation)
        return prefs.edge.isSide ? rect.insetBy(dx: -8, dy: -12) : rect.insetBy(dx: -6, dy: -4)
    }

    private func didOpen() {
        guard prefs.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    /// Close only after the pointer has been outside for 420ms straight, with a 6pt margin,
    /// and never while a text field is being edited. Small slips past the edge are forgiven.
    private func watchForExit() {
        closeWatch?.cancel()
        closeWatch = Task { [weak self] in
            var outsideSince: ContinuousClock.Instant?
            let clock = ContinuousClock()
            while !Task.isCancelled {
                guard let self, self.model.isHovering else { return }
                let region = self.screenRect(for: self.model.presentation).insetBy(dx: -6, dy: -6)
                if region.contains(NSEvent.mouseLocation) || self.model.isEditing || self.model.isDropTargeted {
                    outsideSince = nil
                } else if let since = outsideSince {
                    if since.duration(to: clock.now) >= .milliseconds(420) {
                        withAnimation(Motion.close) { self.model.isHovering = false }
                        return
                    }
                } else {
                    outsideSince = clock.now
                }
                try? await Task.sleep(for: .milliseconds(70))
            }
        }
    }

    private func clickedOutside() {
        guard model.presentation.isExpanded, model.isOpenedByClick || model.isEditing else { return }
        guard !screenRect(for: model.presentation).contains(NSEvent.mouseLocation) else { return }
        close()
    }

    // MARK: Actions

    func open(_ tab: IslandTab) {
        let wasExpanded = model.presentation.isExpanded
        withAnimation(Motion.open) {
            model.tab = prefs.isVisible(tab) ? tab : (prefs.visibleTabs.first ?? tab)
            model.isOpenedByClick = true
            model.isPointerNear = false
        }
        if !wasExpanded { didOpen() }
    }

    /// Clicking the closed island, or the global shortcut.
    func toggle() {
        if model.presentation.isExpanded, case .open = model.presentation {
            close()
        } else {
            panel?.makeKey()
            open(prefs.homeTab ?? model.tab)
        }
    }

    func close() {
        closeWatch?.cancel()
        withAnimation(Motion.close) {
            model.isOpenedByClick = false
            model.isEditing = false
            model.isHovering = false
        }
    }

    /// A file drag over the island opens the shelf; it stays open (hovered) after the drop.
    private func dragChanged(_ inside: Bool) {
        withAnimation(Motion.open) {
            model.isDropTargeted = inside
            if inside {
                model.tab = .shelf
                model.isHovering = true
            }
        }
        if inside { watchForExit() }
    }

    func select(_ tab: IslandTab) {
        withAnimation(Motion.swap) { model.tab = tab }
    }

    func peek(_ session: AgentSession) {
        peekTask?.cancel()
        let height: CGFloat = switch (session.phase, session.ask) {
        case (.needsPermission, let ask?) where ask.isQuestion && ask.questions.count == 1:
            // The docked panel is narrower, so the question itself usually takes its second line.
            CGFloat(100 + ask.questions[0].options.count * 37) + (prefs.edge.isSide ? 16 : 0)
        case (.needsPermission, let ask?):
            // Room for a command that wraps onto a second or third line.
            128 + CGFloat(min(((ask.command ?? ask.tool.detail).count - 1) / commandColumns, 2)) * 17
        default: 86
        }
        withAnimation(Motion.open) {
            model.peekHeight = height
            model.peekSessionID = session.id
        }
        if session.phase == .needsPermission {
            // An ask stays until it's settled anywhere: here, or in the terminal.
            peekTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard let self else { return }
                    let live = self.agents.sessions.first { $0.id == session.id }
                    if live?.phase != .needsPermission { self.endPeek(); return }
                }
            }
        } else {
            peekTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(session.phase == .finished ? 5 : 8))
                guard !Task.isCancelled else { return }
                self?.endPeek()
            }
        }
    }

    /// Roughly how many monospaced characters fit on one line of a peeked command.
    private var commandColumns: Int {
        guard prefs.edge.isSide else { return 62 }
        return prefs.compact ? 34 : 40
    }

    func endPeek() {
        peekTask?.cancel()
        withAnimation(Motion.close) { model.peekSessionID = nil }
    }
}
