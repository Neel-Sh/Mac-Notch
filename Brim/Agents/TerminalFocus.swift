import AppKit
import Darwin

/// Brings the app hosting a Claude Code session to the front: walk up from the agent's pid to the
/// first process that is a regular app (claude → zsh → Terminal, or → Code Helper → Code).
enum TerminalFocus {
    static func hostApp(forAgentPID pid: pid_t) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<12 where current > 1 {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                return app
            }
            guard let parent = parentPID(of: current), parent != current else { return nil }
            current = parent
        }
        return nil
    }

    static func activate(agentPID: pid_t, cwd: URL) {
        guard let app = hostApp(forAgentPID: agentPID) else { return }
        app.activate(options: [.activateAllWindows])
        raiseWindow(of: app, matching: cwd.lastPathComponent)
    }

    /// With Accessibility granted, raise the window whose title names the project. Without it, activation alone.
    private static func raiseWindow(of app: NSRunningApplication, matching name: String) {
        guard AXIsProcessTrusted(), !name.isEmpty else { return }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        for window in windows {
            var title: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
            if let title = title as? String, title.localizedCaseInsensitiveContains(name) {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                return
            }
        }
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    static func icon(forAgentPID pid: pid_t) -> NSImage? {
        hostApp(forAgentPID: pid)?.icon
    }
}
