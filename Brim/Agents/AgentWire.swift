import Foundation

// External formats, parsed once at the boundary. Everything past here uses typed values.

/// `~/.claude/sessions/<pid>.json`, written by Claude Code itself. Private format: decode leniently.
struct SessionRecord: Equatable {
    let pid: pid_t
    let sessionID: String
    let cwd: URL
    let name: String?
    let kind: String?
    let status: String
    let waitingFor: String?
    let startedAt: Date?
    let statusUpdatedAt: Date?

    init?(data: Data) {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let pid = object["pid"] as? Int,
            let sessionID = object["sessionId"] as? String,
            let cwd = object["cwd"] as? String
        else { return nil }
        self.pid = pid_t(pid)
        self.sessionID = sessionID
        self.cwd = URL(fileURLWithPath: cwd)
        self.name = (object["name"] as? String)?.nilIfBlank
        self.kind = object["kind"] as? String
        self.status = object["status"] as? String ?? "idle"
        self.waitingFor = object["waitingFor"] as? String
        self.startedAt = (object["startedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
        self.statusUpdatedAt = (object["statusUpdatedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    var impliedPhase: AgentSession.Phase {
        switch status {
        case "busy": .thinking
        case "shell": .tool(ToolActivity(name: "Bash", detail: ""))
        case "waiting":
            waitingFor?.contains("permission") == true ? .needsPermission : .needsInput(waitingFor?.capitalizedFirst ?? "Waiting for you")
        default: .idle
        }
    }
}

/// One line from Brim's hook script.
struct HookEvent {
    let sessionID: String
    let cwd: URL?
    let agentPID: pid_t?
    let kind: Kind

    enum Kind {
        case sessionStart
        case userPromptSubmit(String?)
        case preToolUse(ToolActivity)
        case postToolUse
        case permissionRequest(PendingAsk)
        case notification(message: String?, kind: String?)
        case stop(String?)
        case sessionEnd
        case other
    }

    /// Events that mean the session moved past any pending ask.
    var settlesAsk: Bool {
        switch kind {
        case .userPromptSubmit, .preToolUse, .postToolUse, .stop: true
        default: false
        }
    }

    var isBlocking: Bool {
        if case .permissionRequest = kind { return true }
        return false
    }

    init?(line: Data, now: Date = .now) {
        guard
            let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
            let sessionID = object["session_id"] as? String, !sessionID.isEmpty,
            let event = object["event"] as? String
        else { return nil }
        self.sessionID = sessionID
        self.cwd = (object["cwd"] as? String).map { URL(fileURLWithPath: $0) }
        self.agentPID = (object["agent_pid"] as? Int).map { pid_t($0) }

        let tool = ToolActivity(
            name: object["tool_name"] as? String ?? "Tool",
            detail: object["summary"] as? String ?? ""
        )
        switch event {
        case "SessionStart": kind = .sessionStart
        case "UserPromptSubmit": kind = .userPromptSubmit(object["prompt"] as? String)
        case "PreToolUse": kind = .preToolUse(tool)
        case "PostToolUse", "PostToolUseFailure": kind = .postToolUse
        case "PermissionRequest":
            let questions = (object["questions"] as? [[String: Any]] ?? []).compactMap { raw -> PendingAsk.Question? in
                guard let text = raw["question"] as? String else { return nil }
                return PendingAsk.Question(
                    text: text,
                    header: raw["header"] as? String,
                    multiSelect: raw["multi_select"] as? Bool ?? false,
                    options: (raw["options"] as? [Any] ?? []).compactMap { $0 as? String }
                )
            }
            kind = .permissionRequest(PendingAsk(
                id: UUID(), tool: tool, command: object["command"] as? String,
                questions: questions, receivedAt: now
            ))
        case "Notification":
            kind = .notification(message: object["message"] as? String, kind: object["notification_type"] as? String)
        case "Stop": kind = .stop(object["last_message"] as? String)
        case "SessionEnd": kind = .sessionEnd
        default: kind = .other
        }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
