import Foundation
import Testing
@testable import Brim

@MainActor
struct WireFormatTests {
    @Test func sessionRecordReadsClaudeCodesFile() throws {
        let json = #"{"pid":42,"sessionId":"abc","cwd":"/Users/me/app","name":"Ship it","kind":"interactive","status":"waiting","waitingFor":"permission prompt","statusUpdatedAt":1795667174536}"#
        let record = try #require(SessionRecord(data: Data(json.utf8)))
        #expect(record.pid == 42)
        #expect(record.name == "Ship it")
        #expect(record.impliedPhase == .needsPermission)
    }

    @Test func sessionRecordRejectsMissingFields() {
        #expect(SessionRecord(data: Data(#"{"pid":1}"#.utf8)) == nil)
        #expect(SessionRecord(data: Data("not json".utf8)) == nil)
    }

    @Test func permissionRequestCarriesQuestions() throws {
        let json = #"{"event":"PermissionRequest","session_id":"s","tool_name":"AskUserQuestion","questions":[{"question":"Which?","header":"Pick","multi_select":false,"options":["A","B"]}]}"#
        let event = try #require(HookEvent(line: Data(json.utf8)))
        #expect(event.isBlocking)
        guard case .permissionRequest(let ask) = event.kind else {
            Issue.record("expected a permission request")
            return
        }
        #expect(ask.isQuestion)
        #expect(ask.questions.first?.options == ["A", "B"])
    }

    @Test func onlyProgressSettlesAnAsk() throws {
        func kind(_ name: String) throws -> HookEvent {
            try #require(HookEvent(line: Data(#"{"event":"\#(name)","session_id":"s"}"#.utf8)))
        }
        #expect(try kind("PostToolUse").settlesAsk)
        #expect(try kind("Stop").settlesAsk)
        #expect(try !kind("Notification").settlesAsk)
    }

    @Test func repliesMatchWhatTheHookScriptExpects() throws {
        #expect(AskReply.allow.wireLine == "allow")
        #expect(AskReply.deny.wireLine == "deny")
        let data = Data(AskReply.answers(["Yes"]).wireLine.utf8)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: [String]])
        #expect(object["answers"] == ["Yes"])
    }
}
