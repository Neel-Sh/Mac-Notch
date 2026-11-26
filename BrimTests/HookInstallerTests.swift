import Foundation
import Testing
@testable import Brim

/// Brim edits the person's ~/.claude/settings.json, so these pin down that it touches only its own entries.
@MainActor
struct HookInstallerTests {
    private let command = "'/Users/me/Library/Application Support/Brim/claude-hook.pl'"

    private var existing: [String: Any] {
        [
            "model": "opus",
            "hooks": [
                "PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "my-linter"]]]],
            ],
        ]
    }

    @Test func installAddsEveryEventAndKeepsTheirSettings() {
        let settings = HookInstaller.addingBrim(to: existing, command: command)
        let hooks = settings["hooks"] as? [String: Any] ?? [:]

        #expect(settings["model"] as? String == "opus")
        #expect(Set(hooks.keys) == Set(HookInstaller.events))
        #expect(HookInstaller.containsBrim(settings))
        let preToolUse = hooks["PreToolUse"] as? [[String: Any]] ?? []
        #expect(preToolUse.count == 2, "the person's own PreToolUse hook survives")
    }

    @Test func installingTwiceLeavesOneCopy() {
        let once = HookInstaller.addingBrim(to: existing, command: command)
        let twice = HookInstaller.addingBrim(to: once, command: command)
        let groups = (twice["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]] ?? []
        #expect(groups.count == 1)
    }

    @Test func uninstallRestoresTheOriginal() {
        let installed = HookInstaller.addingBrim(to: existing, command: command)
        let removed = HookInstaller.removingBrim(from: installed)

        #expect(!HookInstaller.containsBrim(removed))
        let hooks = removed["hooks"] as? [String: Any] ?? [:]
        #expect(Set(hooks.keys) == ["PreToolUse"])
        #expect(removed["model"] as? String == "opus")
    }

    @Test func uninstallDropsAnEmptyHooksKey() {
        let installed = HookInstaller.addingBrim(to: [:], command: command)
        #expect(HookInstaller.removingBrim(from: installed)["hooks"] == nil)
    }
}
