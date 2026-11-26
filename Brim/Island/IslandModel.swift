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
/// On the notch the island hangs from the top edge; docked to a side it grows out of that edge instead.
enum IslandLayout {
    static let shoulder: CGFloat = 18
    static let openRadius: CGFloat = 30
    static let headerHeight: CGFloat = 26
    /// Side docking: the column of page tabs against the screen edge.
    static let railWidth: CGFloat = 54
    static let sideRadius: CGFloat = 34

    static func panelSize(_ style: IslandStyle) -> CGSize {
        style.edge.isSide
            ? CGSize(width: railWidth + sideWidth(style) + 24, height: sideHeight(style) + shoulder * 2 + 24)
            : CGSize(width: 780, height: 480)
    }

    static func openWidth(_ style: IslandStyle) -> CGFloat { style.compact ? 500 : 600 }
    static func peekWidth(_ style: IslandStyle) -> CGFloat { style.compact ? 410 : 460 }
    static func maxContentHeight(_ style: IslandStyle) -> CGFloat {
        if style.edge.isSide { return sideHeight(style) - sideChrome }
        return style.compact ? 240 : 300
    }
    /// Side docking: the page beside the rail, and the tallest the panel gets. It hugs each page's
    /// content and grows from its middle, so the rail of tabs stays put while the page changes.
    static func sideWidth(_ style: IslandStyle) -> CGFloat { style.compact ? 304 : 340 }
    static func sideHeight(_ style: IslandStyle) -> CGFloat { style.compact ? 456 : 504 }
    /// Side docking: everything around a page's content. Its title row and the breathing room that
    /// keeps the content off the rounded corners.
    static let sideTop: CGFloat = 8
    static let sidePageTop: CGFloat = 12
    static let sidePageBottom: CGFloat = 16
    static let sideChrome: CGFloat = sideTop + headerHeight + sidePageTop + sidePageBottom
    static let railButtonHeight: CGFloat = 38
    static func railHeight(tabs: Int) -> CGFloat {
        tabs > 1 ? CGFloat(tabs) * railButtonHeight + CGFloat(tabs - 1) * 2 + 8 : 0
    }

    static func wingWidth(_ notch: NotchMetrics, _ style: IslandStyle) -> CGFloat {
        notch.height + (style.compact ? 6 : 20)
    }

    /// Everything above an open page's content: the notch band, the tab row and its hairline.
    static func chromeHeight(_ notch: NotchMetrics, _ style: IslandStyle) -> CGFloat {
        notch.height + 6 + headerHeight + 9
    }

    static func size(for presentation: IslandPresentation, notch: NotchMetrics, style: IslandStyle, tabCount: Int,
                     pointerNear: Bool, peekHeight: CGFloat, contentHeight: CGFloat) -> CGSize {
        let content = min(contentHeight, maxContentHeight(style))
        guard style.edge.isSide else {
            return switch presentation {
            case .resting: CGSize(width: notch.width, height: notch.height)
            case .wings: CGSize(width: notch.width + wingWidth(notch, style) * 2, height: notch.height)
            case .peek: CGSize(width: peekWidth(style) + shoulder * 2, height: notch.height + peekHeight)
            case .open: CGSize(width: openWidth(style) + shoulder * 2, height: chromeHeight(notch, style) + content + 16)
            }
        }
        // Docked: width is depth out of the edge, height runs along it (flares included).
        // A sliver of a pill at rest, a rounder one for live activity, then the panel.
        let flare = shoulder(for: presentation, style: style) * 2
        return switch presentation {
        case .resting: CGSize(width: pointerNear ? 10 : 7, height: (style.compact ? 60 : 72) + flare)
        case .wings: CGSize(width: 36, height: (style.compact ? 78 : 86) + flare)
        case .peek: CGSize(width: sideWidth(style), height: peekHeight + 4 + flare)
        case .open:
            CGSize(width: railWidth + sideWidth(style),
                   height: max(sideChrome + content, railHeight(tabs: tabCount) + 24) + flare)
        }
    }

    static func bottomRadius(for presentation: IslandPresentation, notch: NotchMetrics, style: IslandStyle) -> CGFloat {
        // Docked and closed, the shape clamps this to its depth: the outside is a full round.
        if style.edge.isSide { return presentation.isExpanded ? sideRadius : 18 }
        if presentation.isExpanded { return openRadius }
        return min(notch.height / 3, 11)
    }

    static func shoulder(for presentation: IslandPresentation, style: IslandStyle) -> CGFloat {
        if presentation.isExpanded { return shoulder }
        // Docked, even the closed pill flares a little where it leaves the bezel.
        guard style.edge.isSide else { return 0 }
        return presentation == .wings ? 7 : 3
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

    var style: IslandStyle { Preferences.shared.style }

    var presentation: IslandPresentation {
        if isDropTargeted { return .open(.shelf) }
        if isHovering || isOpenedByClick || isEditing { return .open(tab) }
        if let peekSessionID { return .peek(peekSessionID) }
        return liveActivity() ? .wings : .resting
    }

    var size: CGSize {
        let page: IslandTab = if case .open(let shown) = presentation { shown } else { tab }
        return size(for: presentation, page: page)
    }

    func size(for presentation: IslandPresentation, page: IslandTab) -> CGSize {
        IslandLayout.size(for: presentation, notch: notch, style: style, tabCount: Preferences.shared.visibleTabs.count,
                          pointerNear: isPointerNear, peekHeight: peekHeight, contentHeight: contentHeight(page))
    }
}
