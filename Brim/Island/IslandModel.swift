import AppKit
import Observation

enum IslandTab: String, CaseIterable, Identifiable {
    case agents, calendar, tasks, weather, media, shelf
    var id: Self { self }

    /// Agents draws its own bot mark; SF Symbols has no robot.
    var symbol: String {
        switch self {
        case .agents: ""
        case .calendar: "calendar"
        case .tasks: "checklist"
        case .weather: "cloud.sun.fill"
        case .media: "music.note"
        case .shelf: "tray.full.fill"
        }
    }

    var title: String {
        switch self {
        case .agents: "Agents"
        case .calendar: "Calendar"
        case .tasks: "Tasks"
        case .weather: "Weather"
        case .media: "Music"
        case .shelf: "Shelf"
        }
    }
}

/// What the island is showing. Derived from inputs, never stored, so it can't drift.
enum IslandPresentation: Equatable {
    case resting            // a plain notch
    case wings              // live activity tucked beside the notch
    case peek(String)       // a session asking for you, opened just enough to answer
    case open(IslandTab)

    var isExpanded: Bool {
        switch self {
        case .peek, .open: true
        default: false
        }
    }
}

/// Where the notch is on this screen.
struct NotchMetrics: Equatable {
    var width: CGFloat
    var height: CGFloat

    static func of(_ screen: NSScreen) -> NotchMetrics {
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           left.width > 0, right.width > 0 {
            let height = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : max(left.height, right.height)
            return NotchMetrics(width: right.minX - left.maxX, height: height)
        }
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        return NotchMetrics(width: 184, height: max(24, min(menuBar, 37)))
    }
}

/// The one place island sizes come from. Drawing and hit testing both read it.
enum IslandLayout {
    static let panelSize = CGSize(width: 780, height: 480)
    static let openWidth: CGFloat = 600
    static let peekWidth: CGFloat = 460
    static let shoulder: CGFloat = 18
    static let openRadius: CGFloat = 30
    static let headerHeight: CGFloat = 26
    static let maxContentHeight: CGFloat = 300

    static func wingWidth(_ notch: NotchMetrics) -> CGFloat { notch.height + 20 }

    /// Everything above an open page's content: the notch band, the tab row and its hairline.
    static func chromeHeight(_ notch: NotchMetrics) -> CGFloat { notch.height + 6 + headerHeight + 9 }

    static func size(for presentation: IslandPresentation, notch: NotchMetrics, peekHeight: CGFloat, contentHeight: CGFloat) -> CGSize {
        switch presentation {
        case .resting: CGSize(width: notch.width, height: notch.height)
        case .wings: CGSize(width: notch.width + wingWidth(notch) * 2, height: notch.height)
        case .peek: CGSize(width: peekWidth + shoulder * 2, height: notch.height + peekHeight)
        case .open:
            CGSize(width: openWidth + shoulder * 2,
                   height: chromeHeight(notch) + min(contentHeight, maxContentHeight) + 16)
        }
    }

    static func bottomRadius(for presentation: IslandPresentation, notch: NotchMetrics) -> CGFloat {
        presentation.isExpanded ? openRadius : min(notch.height / 3, 11)
    }

    static func shoulder(for presentation: IslandPresentation) -> CGFloat {
        presentation.isExpanded ? shoulder : 0
    }
}

@Observable
final class IslandModel {
    var notch = NotchMetrics(width: 184, height: 32)
    var isHovering = false
    var isOpenedByClick = false
    var tab: IslandTab = .agents
    var peekSessionID: String?
    var peekHeight: CGFloat = 130
    /// While typing, the island must not collapse from under the cursor.
    var isEditing = false
    /// The pointer is on the closed notch: show the grabber that says "I open".
    var isPointerNear = false
    /// Files are being dragged over the island: open the shelf and hold it open.
    var isDropTargeted = false

    /// Whether anything deserves the wings. Reads observable sources, so it's tracked.
    @ObservationIgnored var liveActivity: () -> Bool = { false }
    /// How tall each page wants to be. Reads observable sources, so it's tracked.
    @ObservationIgnored var contentHeight: (IslandTab) -> CGFloat = { _ in 160 }

    var presentation: IslandPresentation {
        if isDropTargeted { return .open(.shelf) }
        if isHovering || isOpenedByClick || isEditing { return .open(tab) }
        if let peekSessionID { return .peek(peekSessionID) }
        return liveActivity() ? .wings : .resting
    }

    var size: CGSize {
        let page: IslandTab = if case .open(let shown) = presentation { shown } else { tab }
        return IslandLayout.size(for: presentation, notch: notch, peekHeight: peekHeight, contentHeight: contentHeight(page))
    }
}
