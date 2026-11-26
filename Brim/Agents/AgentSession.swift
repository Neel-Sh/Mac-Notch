import Foundation

/// One Claude Code session. Built from two sources that refine each other:
/// the session record Claude Code keeps in `~/.claude/sessions/<pid>.json` (always there),
/// and Brim's hook events (richer: the tool running, the prompt, the reply, permission asks).
struct AgentSession: Identifiable, Equatable {
    let id: String
    var pid: pid_t
    var cwd: URL
    var title: String?
    var phase: Phase
    var phaseSince: Date
    /// When the current stretch of work began. Survives thinking ↔ tool switches, so the clock doesn't restart.
    var workingSince: Date?
    var startedAt: Date
    var lastPrompt: String?
    var lastMessage: String?
    var toolsRun: Int
    var ask: PendingAsk?
    var isHeadless: Bool

    /// The time a row shows: how long this turn has been running, or how long it's been in its current state.
    var clockStart: Date { phase.isWorking ? (workingSince ?? phaseSince) : phaseSince }

    var projectName: String { cwd.lastPathComponent.isEmpty ? cwd.path : cwd.lastPathComponent }
    var displayTitle: String { title?.nilIfBlank ?? lastPrompt?.nilIfBlank ?? projectName }

    enum Phase: Equatable {
        case idle
        case thinking
        case tool(ToolActivity)
        case needsPermission
        case needsInput(String)
        case finished

        /// Ordered by how urgently the person should look.
        var urgency: Int {
            switch self {
            case .needsPermission: 4
            case .needsInput: 3
            case .finished: 2
            case .tool, .thinking: 1
            case .idle: 0
            }
        }

        var isWorking: Bool {
            switch self {
            case .thinking, .tool: true
            default: false
            }
        }

        var wantsAttention: Bool { urgency >= 3 }
    }
}

struct ToolActivity: Equatable {
    var name: String
    var detail: String

    var symbol: String {
        switch name {
        case "Bash": "terminal"
        case "Read": "doc.text"
        case "Edit", "MultiEdit", "NotebookEdit": "pencil"
        case "Write": "square.and.pencil"
        case "Grep", "Glob": "magnifyingglass"
        case "WebFetch", "WebSearch": "globe"
        case "Task", "Agent": "person.2"
        case "TodoWrite": "checklist"
        case "AskUserQuestion": "questionmark.bubble"
        default: name.hasPrefix("mcp__") ? "puzzlepiece.extension" : "wrench.and.screwdriver"
        }
    }

    var displayName: String {
        guard name.hasPrefix("mcp__") else { return name }
        return name.split(separator: "__").dropFirst().joined(separator: " · ")
    }

    /// A present-tense line for the island: "Editing AgentHub.swift".
    var sentence: String {
        let subject = detail.nilIfBlank.map { ($0 as NSString).lastPathComponent } ?? ""
        let verb: String = switch name {
        case "Bash": "Running"
        case "Read": "Reading"
        case "Edit", "MultiEdit", "NotebookEdit": "Editing"
        case "Write": "Writing"
        case "Grep", "Glob": "Searching"
        case "WebFetch": "Fetching"
        case "WebSearch": "Searching the web"
        case "Task", "Agent": "Delegating"
        case "TodoWrite": "Planning"
        default: displayName
        }
        if name == "Bash" { return detail.nilIfBlank ?? verb }
        return subject.isEmpty ? verb : "\(verb) \(subject)"
    }
}

/// Something a session is waiting on that Brim can answer from the island.
struct PendingAsk: Identifiable, Equatable {
    let id: UUID
    let tool: ToolActivity
    let command: String?
    let questions: [Question]
    let receivedAt: Date

    struct Question: Equatable {
        let text: String
        let header: String?
        let multiSelect: Bool
        let options: [String]
    }

    var isQuestion: Bool { !questions.isEmpty }
}

enum AskReply: Equatable {
    case allow
    case deny
    case answers([String])

    var wireLine: String {
        switch self {
        case .allow: return "allow"
        case .deny: return "deny"
        case .answers(let values):
            let data = (try? JSONSerialization.data(withJSONObject: ["answers": values])) ?? Data()
            return String(decoding: data, as: UTF8.self)
        }
    }
}

// MARK: - Transitions

extension AgentSession {
    init(record: SessionRecord, now: Date) {
        self.init(
            id: record.sessionID,
            pid: record.pid,
            cwd: record.cwd,
            title: record.name,
            phase: record.impliedPhase,
            phaseSince: record.statusUpdatedAt ?? now,
            workingSince: record.impliedPhase.isWorking ? (record.statusUpdatedAt ?? now) : nil,
            startedAt: record.startedAt ?? now,
            lastPrompt: nil,
            lastMessage: nil,
            toolsRun: 0,
            ask: nil,
            isHeadless: record.kind != "interactive"
        )
    }

    init(event: HookEvent, now: Date) {
        self.init(
            id: event.sessionID,
            pid: event.agentPID ?? 0,
            cwd: event.cwd ?? URL(fileURLWithPath: NSHomeDirectory()),
            title: nil,
            phase: .idle,
            phaseSince: now,
            workingSince: nil,
            startedAt: now,
            lastPrompt: nil,
            lastMessage: nil,
            toolsRun: 0,
            ask: nil,
            isHeadless: false
        )
    }

    /// The session file is coarse but authoritative about liveness and waiting.
    mutating func apply(_ record: SessionRecord, now: Date) {
        pid = record.pid
        cwd = record.cwd
        title = record.name ?? title
        let implied = record.impliedPhase
        let previous = phase
        switch (implied, phase) {
        case (.idle, let current) where current.isWorking:
            phase = .finished
        case (.idle, .finished), (.idle, .needsInput):
            break
        case (.thinking, .tool), (.tool, .tool):
            break // the hook knows which tool; keep it
        case (.needsPermission, .needsPermission):
            break
        case (.needsInput, .needsPermission) where ask != nil:
            break
        default:
            phase = implied
        }
        if !implied.wantsAttention { ask = nil }
        noteTransition(from: previous, now: now)
    }

    /// Hook events carry the detail. All hook-driven state changes go through here.
    mutating func apply(_ event: HookEvent, now: Date) {
        if let cwd = event.cwd { self.cwd = cwd }
        if let agentPID = event.agentPID, pid == 0 { pid = agentPID }
        let previous = phase

        switch event.kind {
        case .sessionStart:
            phase = .idle
        case .userPromptSubmit(let prompt):
            lastPrompt = prompt ?? lastPrompt
            lastMessage = nil
            toolsRun = 0
            ask = nil
            phase = .thinking
        case .preToolUse(let tool):
            ask = nil
            phase = .tool(tool)
        case .postToolUse:
            toolsRun += 1
            ask = nil
            phase = .thinking
        case .permissionRequest(let pending):
            ask = pending
            phase = .needsPermission
        case .notification(let message, let kind):
            if kind == "permission_prompt" {
                if ask == nil { phase = .needsPermission }
            } else {
                phase = .needsInput(message ?? "Waiting for you")
            }
        case .stop(let message):
            ask = nil
            lastMessage = message ?? lastMessage
            phase = .finished
        case .sessionEnd, .other:
            break
        }

        noteTransition(from: previous, now: now)
    }

    /// Phase changes from outside the event stream (an answer from the island, a timeout).
    mutating func setPhase(_ next: Phase, now: Date) {
        let previous = phase
        phase = next
        noteTransition(from: previous, now: now)
    }

    /// A turn runs from the prompt until Claude stops; waiting on an approval is part of it.
    private mutating func noteTransition(from previous: Phase, now: Date) {
        guard phase != previous else { return }
        phaseSince = now
        switch phase {
        case .thinking, .tool, .needsPermission:
            if workingSince == nil { workingSince = now }
        case .idle, .finished, .needsInput:
            workingSince = nil
        }
    }
}

extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
