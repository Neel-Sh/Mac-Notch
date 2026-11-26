import AppKit
import Observation

/// Every live Claude Code session on this Mac, kept current from session files and hook events.
@Observable
final class AgentHub {
    private(set) var sessions: [AgentSession] = []
    private(set) var hooksInstalled = HookInstaller.isInstalled
    var lastError: String?

    /// Fires when a session newly needs the person or just finished, so the island can peek.
    @ObservationIgnored var onAttention: ((AgentSession) -> Void)?

    @ObservationIgnored private let server = HookServer()
    @ObservationIgnored private var held: [String: HeldConnection] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var hookOnly: Set<String> = []
    /// Sessions swiped away. They come back on their own the next time they need you or start working.
    private var hidden: Set<String> = []

    private static let sessionsDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/sessions", isDirectory: true)

    /// Sessions sorted for display: what needs you first, then what's working, then the rest.
    var ordered: [AgentSession] {
        sessions.filter { !hidden.contains($0.id) }.sorted {
            ($0.phase.urgency, $0.phaseSince) > ($1.phase.urgency, $1.phaseSince)
        }
    }

    var attentionCount: Int { ordered.count { $0.phase.wantsAttention } }
    var workingCount: Int { ordered.count { $0.phase.isWorking } }

    /// The single session that best represents the hub in the closed island.
    var lead: AgentSession? { ordered.first { $0.phase != .idle } }

    func start() {
        server.onEvent = { [weak self] event, connection in self?.receive(event, held: connection) }
        server.onHeldClosed = { [weak self] sessionID in self?.heldClosed(sessionID) }
        if hooksInstalled {
            try? HookScript.install() // keep the script on disk in sync with this build
        }
        try? FileManager.default.createDirectory(at: HookScript.directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        server.start(at: HookScript.socketURL)
        scanSessionFiles()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scanSessionFiles() }
        }
    }

    func stop() {
        timer?.invalidate()
        for connection in held.values { connection.release() }
        held.removeAll()
        server.stop()
    }

    // MARK: Hooks setup

    func setHooksInstalled(_ install: Bool) {
        do {
            if install { try HookInstaller.install() } else { try HookInstaller.uninstall() }
            hooksInstalled = HookInstaller.isInstalled
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: Answering

    func respond(to sessionID: String, with reply: AskReply) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        held.removeValue(forKey: sessionID)?.reply(reply)
        sessions[index].ask = nil
        sessions[index].setPhase(.thinking, now: .now)
    }

    func focus(_ session: AgentSession) {
        TerminalFocus.activate(agentPID: session.pid, cwd: session.cwd)
    }

    func hide(_ sessionID: String) {
        hidden.insert(sessionID)
        held.removeValue(forKey: sessionID)?.release()
    }

    /// The person has looked at the island: finished sessions have delivered their news.
    func acknowledgeFinished() {
        for index in sessions.indices where sessions[index].phase == .finished {
            sessions[index].setPhase(.idle, now: .now)
        }
    }

    // MARK: Sources

    private func receive(_ event: HookEvent, held connection: HeldConnection?) {
        let now = Date.now
        if case .sessionEnd = event.kind {
            remove(event.sessionID)
            return
        }

        // A newer ask replaces the old one; progress means the old ask was settled in the terminal.
        if connection != nil || event.settlesAsk {
            held.removeValue(forKey: event.sessionID)?.release()
        }
        if let connection { held[event.sessionID] = connection }

        if let index = sessions.firstIndex(where: { $0.id == event.sessionID }) {
            let before = sessions[index].phase
            sessions[index].apply(event, now: now)
            announceIfNeeded(sessions[index], was: before)
        } else {
            var session = AgentSession(event: event, now: now)
            session.apply(event, now: now)
            hookOnly.insert(session.id)
            sessions.append(session)
            announceIfNeeded(session, was: .idle)
        }
    }

    private func heldClosed(_ sessionID: String) {
        guard held[sessionID] != nil else { return } // we replied; already handled
        held[sessionID] = nil
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }) else { return }
        // The terminal settled it. Fall back to whatever the session file says next.
        sessions[index].ask = nil
        if sessions[index].phase == .needsPermission { sessions[index].setPhase(.thinking, now: .now) }
    }

    private func scanSessionFiles() {
        let now = Date.now
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: Self.sessionsDirectory, includingPropertiesForKeys: nil
        )) ?? []
        var seen: Set<String> = []

        for url in urls where url.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: url),
                let record = SessionRecord(data: data),
                kill(record.pid, 0) == 0
            else { continue }
            seen.insert(record.sessionID)
            hookOnly.remove(record.sessionID)

            if let index = sessions.firstIndex(where: { $0.id == record.sessionID }) {
                let before = sessions[index]
                var updated = before
                updated.apply(record, now: now)
                if updated != before {
                    sessions[index] = updated
                    announceIfNeeded(updated, was: before.phase)
                }
            } else {
                sessions.append(AgentSession(record: record, now: now))
            }
        }

        // "Finished" is news, not a state to sit in: after a few minutes it settles to idle.
        for index in sessions.indices where sessions[index].phase == .finished
            && now.timeIntervalSince(sessions[index].phaseSince) > 60 {
            sessions[index].setPhase(.idle, now: now)
        }

        // Drop sessions whose process is gone. Hook-only sessions live until their process dies.
        for session in sessions where !seen.contains(session.id) {
            if hookOnly.contains(session.id), session.pid > 0, kill(session.pid, 0) == 0 { continue }
            remove(session.id)
        }
    }

    private func remove(_ sessionID: String) {
        held.removeValue(forKey: sessionID)?.release()
        hookOnly.remove(sessionID)
        hidden.remove(sessionID)
        sessions.removeAll { $0.id == sessionID }
    }

    private func announceIfNeeded(_ session: AgentSession, was previous: AgentSession.Phase) {
        let woke = (session.phase.isWorking && !previous.isWorking) || (session.phase.wantsAttention && !previous.wantsAttention)
        if woke { hidden.remove(session.id) }
        let rises = session.phase.urgency > previous.urgency || (session.ask != nil && previous != .needsPermission)
        guard rises, session.phase.urgency >= 2 else { return }
        onAttention?(session)
    }
}
