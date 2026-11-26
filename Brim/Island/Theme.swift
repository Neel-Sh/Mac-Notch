import SwiftUI

/// Design tokens. Black island, charcoal rows, one accent per state.
enum Theme {
    static let island = Color.black
    // Auri's ladder: one white at many opacities, nothing else.
    static let row = Color.white.opacity(0.06)
    static let rowHover = Color.white.opacity(0.09)
    static let hairline = Color.white.opacity(0.09)
    static let primary = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.58)
    static let tertiary = Color.white.opacity(0.38)

    /// Claude's warm coral, for work in progress.
    static let working = Color(red: 0.851, green: 0.467, blue: 0.341)
    static let attention = Color(red: 1.0, green: 0.702, blue: 0.251)
    static let done = Color(red: 0.188, green: 0.820, blue: 0.345)
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.40)

    static let rowRadius: CGFloat = 14
    static let inset: CGFloat = 14

    static func title(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .semibold) }
    static func body(_ size: CGFloat = 12) -> Font { .system(size: size) }
    static let mono = Font.system(size: 11.5, design: .monospaced)
    static let caption = Font.system(size: 11, weight: .medium)
}

extension AgentSession.Phase {
    var tint: Color {
        switch self {
        case .needsPermission, .needsInput: Theme.attention
        case .finished: Theme.done
        case .thinking, .tool: Theme.working
        case .idle: Theme.tertiary
        }
    }
}

/// S11's vocabulary: one circular silhouette, a different interior for each state.
struct StateMark: View {
    let phase: AgentSession.Phase
    var size: CGFloat = 16
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            switch phase {
            case .idle:
                Circle().strokeBorder(Theme.tertiary, lineWidth: size * 0.12)
            case .thinking, .tool:
                SpinningSegments(color: Theme.working, lineWidth: size * 0.13, spins: !reduceMotion)
            case .needsPermission, .needsInput:
                Circle().fill(Theme.attention)
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.black.opacity(0.82))
            case .finished:
                Circle().fill(Theme.done)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.5, weight: .heavy))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .contentTransition(.symbolEffect(.replace))
        .accessibilityLabel(phase.accessibilityLabel)
    }
}

private struct SpinningSegments: View {
    let color: Color
    let lineWidth: CGFloat
    let spins: Bool

    var body: some View {
        TimelineView(.animation(paused: !spins)) { context in
            let angle = spins ? context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4 * 360 : 0
            ZStack {
                Circle().stroke(color.opacity(0.25), style: StrokeStyle(lineWidth: lineWidth, dash: [2.2, 2.6]))
                Circle()
                    .trim(from: 0, to: 0.38)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [2.2, 2.6]))
                    .rotationEffect(.degrees(angle))
            }
            .padding(lineWidth / 2)
        }
    }
}

extension AgentSession.Phase {
    var accessibilityLabel: String {
        switch self {
        case .idle: "Idle"
        case .thinking: "Thinking"
        case .tool(let tool): tool.sentence
        case .needsPermission: "Needs permission"
        case .needsInput(let message): message
        case .finished: "Finished"
        }
    }
}

/// A pill button with immediate press feedback (on press, not release).
struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, quiet }
    var kind: Kind = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(height: 28)
            .foregroundStyle(kind == .primary ? Color.black : Theme.primary)
            .background(Capsule().fill(fill))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.tap, value: configuration.isPressed)
            .contentShape(Capsule())
    }

    private var fill: Color {
        switch kind {
        case .primary: .white
        case .secondary: Color.white.opacity(0.12)
        case .quiet: .clear
        }
    }
}

struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 28
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Theme.primary)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.18 : 0.09)))
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.tap, value: configuration.isPressed)
            .contentShape(Circle())
    }
}

/// Materialize instead of fade: blur, scale and opacity arrive together.
struct Materialize: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        content
            .opacity(active ? 0 : 1)
            .blur(radius: active ? 8 : 0)
            .scaleEffect(active ? 0.96 : 1, anchor: .top)
    }
}

extension AnyTransition {
    static var materialize: AnyTransition {
        .modifier(active: Materialize(active: true), identity: Materialize(active: false))
    }
}

enum Elapsed {
    static func short(since date: Date, now: Date = .now) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }

    static func clock(since date: Date, now: Date = .now) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Brim's agent mark: a small bot, drawn at SF Symbols' stroke weight (there's no robot glyph).
struct BotGlyph: View {
    var size: CGFloat = 13
    var weight: CGFloat = 1.5

    var body: some View {
        Canvas { context, canvasSize in
            let s = canvasSize.width
            let line = weight * s / 13
            // Antenna
            var antenna = Path()
            antenna.move(to: CGPoint(x: s * 0.5, y: s * 0.2))
            antenna.addLine(to: CGPoint(x: s * 0.5, y: s * 0.06))
            context.stroke(antenna, with: .foreground, style: StrokeStyle(lineWidth: line, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: s * 0.5 - line, y: s * 0.02 - line * 0.5, width: line * 2, height: line * 2)),
                         with: .foreground)
            // Head
            let head = CGRect(x: s * 0.1, y: s * 0.22, width: s * 0.8, height: s * 0.62)
            context.stroke(Path(roundedRect: head, cornerRadius: s * 0.2, style: .continuous),
                           with: .foreground, lineWidth: line)
            // Ears
            for x in [s * 0.02, s * 0.98] {
                var ear = Path()
                ear.move(to: CGPoint(x: x, y: s * 0.46))
                ear.addLine(to: CGPoint(x: x, y: s * 0.62))
                context.stroke(ear, with: .foreground, style: StrokeStyle(lineWidth: line, lineCap: .round))
            }
            // Eyes
            for x in [s * 0.36, s * 0.64] {
                context.fill(Path(roundedRect: CGRect(x: x - line * 0.75, y: s * 0.44, width: line * 1.5, height: s * 0.17),
                                  cornerRadius: line * 0.75), with: .foreground)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Agents")
    }
}
