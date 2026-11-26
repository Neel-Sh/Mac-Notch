import Foundation
import Testing
@testable import Brim

@MainActor
struct AgentSessionTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func event(_ json: String) -> HookEvent {
        HookEvent(line: Data(json.utf8), now: start)!
    }

    private func session() -> AgentSession {
        let first = event(#"{"event":"SessionStart","session_id":"s1","cwd":"/tmp/project"}"#)
        var session = AgentSession(event: first, now: start)
        session.apply(first, now: start)
        return session
    }

    @Test func clockKeepsRunningAcrossToolSwitches() {
        var s = session()
        s.apply(event(#"{"event":"UserPromptSubmit","session_id":"s1","prompt":"fix it"}"#), now: start)
        s.apply(event(#"{"event":"PreToolUse","session_id":"s1","tool_name":"Bash","summary":"ls"}"#), now: start + 5)
        s.apply(event(#"{"event":"PostToolUse","session_id":"s1"}"#), now: start + 12)
        s.apply(event(#"{"event":"PreToolUse","session_id":"s1","tool_name":"Read","summary":"a.swift"}"#), now: start + 20)

        #expect(s.clockStart == start)
        #expect(s.toolsRun == 1)
        #expect(s.phase == .tool(ToolActivity(name: "Read", detail: "a.swift")))
    }

    @Test func waitingOnApprovalIsPartOfTheTurn() {
        var s = session()
        s.apply(event(#"{"event":"UserPromptSubmit","session_id":"s1"}"#), now: start)
        s.apply(event(#"{"event":"PermissionRequest","session_id":"s1","tool_name":"Bash","command":"rm -rf build"}"#), now: start + 3)
        #expect(s.phase == .needsPermission)
        #expect(s.ask?.command == "rm -rf build")

        s.apply(event(#"{"event":"PostToolUse","session_id":"s1"}"#), now: start + 9)
        #expect(s.ask == nil)
        #expect(s.clockStart == start)
    }

    @Test func stopFinishesAndClearsTheClock() {
        var s = session()
        s.apply(event(#"{"event":"UserPromptSubmit","session_id":"s1"}"#), now: start)
        s.apply(event(#"{"event":"Stop","session_id":"s1","last_message":"All done."}"#), now: start + 30)

        #expect(s.phase == .finished)
        #expect(s.lastMessage == "All done.")
        #expect(s.workingSince == nil)
        #expect(s.clockStart == start + 30)
    }

    @Test func sessionFileGoingIdleAfterWorkMeansFinished() throws {
        var s = session()
        s.apply(event(#"{"event":"UserPromptSubmit","session_id":"s1"}"#), now: start)
        let idle = try #require(SessionRecord(data: Data(#"{"pid":1,"sessionId":"s1","cwd":"/tmp/project","status":"idle"}"#.utf8)))
        s.apply(idle, now: start + 40)
        #expect(s.phase == .finished)
    }

    @Test func sessionFileShellKeepsTheHooksToolDetail() throws {
        var s = session()
        s.apply(event(#"{"event":"PreToolUse","session_id":"s1","tool_name":"Bash","summary":"make test"}"#), now: start)
        let shell = try #require(SessionRecord(data: Data(#"{"pid":1,"sessionId":"s1","cwd":"/tmp/project","status":"shell"}"#.utf8)))
        s.apply(shell, now: start + 2)
        #expect(s.phase == .tool(ToolActivity(name: "Bash", detail: "make test")))
    }
}
