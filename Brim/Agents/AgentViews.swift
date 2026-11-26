import SwiftUI

/// The Agents tab: every Claude Code session, most urgent first. Swipe a row away to hide it.
struct AgentsPage: View {
    let hub: AgentHub

    var body: some View {
        VStack(spacing: 8) {
            if !hub.hooksInstalled {
                HooksBanner(hub: hub)
            }
            if hub.ordered.isEmpty {
                EmptyAgents()
            } else {
                SwipeList(items: hub.ordered, actionTitle: "Hide", actionSymbol: "eye.slash") { session in
                    AgentRow(session: session, hub: hub)
                } onSwipe: { session in
                    hub.hide(session.id)
                }
            }
        }
    }
}

private struct EmptyAgents: View {
    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.tertiary)
            Text("No Claude Code sessions")
                .font(Theme.title(13))
                .foregroundStyle(Theme.secondary)
            Text("Start `claude` anywhere and it shows up here. Swipe a session left to hide it.")
                .font(Theme.body(11.5))
                .foregroundStyle(Theme.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HooksBanner: View {
    let hub: AgentHub

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.working)
            VStack(alignment: .leading, spacing: 1) {
                Text("Approve and follow along from here")
                    .font(Theme.title(12))
                Text("Adds Brim's hook to ~/.claude/settings.json. New sessions only.")
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 8)
            Button("Turn On") { hub.setHooksInstalled(true) }
                .buttonStyle(PillButtonStyle(kind: .primary))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous).fill(Theme.row))
    }
}

struct AgentRow: View {
    let session: AgentSession
    let hub: AgentHub
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { hub.focus(session) } label: { header }
                .buttonStyle(.plain)
                .help("Show in its window")

            if session.phase == .needsPermission, let ask = session.ask {
                AskControls(session: session, ask: ask, hub: hub, compact: true)
                    .transition(.materialize)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(hovering ? Color.white.opacity(0.04) : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .strokeBorder(session.phase.wantsAttention ? Theme.attention.opacity(0.35) : .clear, lineWidth: 1)
        )
        .onHover { hovering = $0 }
        .animation(Motion.swap, value: session.phase)
    }

    private var header: some View {
            HStack(spacing: 11) {
                StateMark(phase: session.phase, size: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayTitle)
                        .font(Theme.title(12.5))
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        if session.displayTitle != session.projectName {
                            Text(session.projectName)
                                .foregroundStyle(Theme.tertiary)
                        }
                        Text(session.phaseLine)
                            .foregroundStyle(session.phase.wantsAttention ? Theme.attention : Theme.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(Theme.body(11.5))
                }
                Spacer(minLength: 8)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Elapsed.short(since: session.clockStart, now: context.date))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.tertiary)
                }
                HostIcon(pid: session.pid)
            }
            .contentShape(Rectangle())
    }
}

extension AgentSession {
    var phaseLine: String {
        switch phase {
        case .idle: "Idle"
        case .thinking: "Thinking…"
        case .tool(let tool): tool.sentence
        case .needsPermission: ask.map { "Wants to use \($0.tool.displayName)" } ?? "Needs permission"
        case .needsInput(let message): message
        case .finished: lastMessage ?? "Finished"
        }
    }
}

struct HostIcon: View {
    let pid: pid_t
    var size: CGFloat = 18

    var body: some View {
        if pid > 0, let icon = TerminalFocus.icon(forAgentPID: pid) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        }
    }
}

/// Allow / Deny, or a question's options, for one pending ask.
struct AskControls: View {
    let session: AgentSession
    let ask: PendingAsk
    let hub: AgentHub
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let question = ask.questions.first, ask.questions.count == 1, !question.multiSelect {
                Text(question.text)
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.primary)
                    .lineLimit(2)
                VStack(spacing: 5) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { _, option in
                        Button {
                            hub.respond(to: session.id, with: .answers([option]))
                        } label: {
                            Text(option)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(OptionButtonStyle())
                    }
                }
            } else if ask.isQuestion {
                HStack {
                    Text("Claude has \(ask.questions.count == 1 ? "a question" : "\(ask.questions.count) questions") for you.")
                        .font(Theme.body(12))
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                    Button("Answer") { hub.focus(session) }
                        .buttonStyle(PillButtonStyle(kind: .primary))
                }
            } else {
                if let command = ask.command?.nilIfBlank ?? ask.tool.detail.nilIfBlank {
                    Text(command)
                        .font(Theme.mono)
                        .foregroundStyle(Theme.primary.opacity(0.9))
                        .lineLimit(compact ? 2 : 3)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
                        .textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    Button { hub.focus(session) } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(IconButtonStyle())
                    .help("Open the session")
                    Spacer()
                    Button("Deny") { hub.respond(to: session.id, with: .deny) }
                        .buttonStyle(PillButtonStyle(kind: .secondary))
                        .keyboardShortcut(.cancelAction)
                    Button("Allow") { hub.respond(to: session.id, with: .allow) }
                        .buttonStyle(PillButtonStyle(kind: .primary))
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}

private struct OptionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.primary)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.2 : 0.1))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Motion.tap, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// The peek card: opened just enough to answer one session, then gone.
struct AgentPeek: View {
    let session: AgentSession
    let hub: AgentHub
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                StateMark(phase: session.phase, size: 16)
                Text(headline)
                    .font(Theme.title(12.5))
                    .lineLimit(1)
                Text(session.projectName)
                    .font(Theme.body(11.5))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                Spacer()
                HostIcon(pid: session.pid, size: 16)
            }

            switch session.phase {
            case .needsPermission:
                if let ask = session.ask {
                    AskControls(session: session, ask: ask, hub: hub)
                } else {
                    jumpRow("Waiting in the terminal")
                }
            case .needsInput(let message):
                jumpRow(message)
            default:
                Text(session.lastMessage ?? session.lastPrompt ?? "Finished")
                    .font(Theme.body(12))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onTapGesture { hub.focus(session); dismiss() }
            }
        }
    }

    private var headline: String {
        switch session.phase {
        case .needsPermission: session.ask?.isQuestion == true ? "Claude has a question" : "Claude needs permission"
        case .needsInput: "Claude is waiting"
        case .finished: "Claude finished"
        default: session.displayTitle
        }
    }

    private func jumpRow(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(Theme.body(12))
                .foregroundStyle(Theme.secondary)
                .lineLimit(2)
            Spacer()
            Button("Open") { hub.focus(session); dismiss() }
                .buttonStyle(PillButtonStyle(kind: .primary))
        }
    }
}
