import Foundation

/// The command Brim registers in Claude Code's hooks, and where it lives.
///
/// Perl because it ships with macOS, starts in milliseconds and has a Unix socket client and a
/// JSON codec in core. It always exits 0 and prints nothing unless Brim answered a permission ask,
/// so with Brim quit the hook is a no-op and Claude Code carries on as if it were not there.
enum HookScript {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Brim", isDirectory: true)
    }

    static var installedURL: URL { directory.appendingPathComponent("claude-hook.pl") }
    static var socketURL: URL { directory.appendingPathComponent("agent.sock") }

    static var command: String { "'\(installedURL.path)'" }

    static func install() throws {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try Data(source.utf8).write(to: installedURL, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installedURL.path)
    }

    static func remove() {
        try? FileManager.default.removeItem(at: installedURL)
    }

    static let source = #"""
    #!/usr/bin/perl
    # Brim's Claude Code hook. Rewritten by Brim on every install.
    use strict;
    use warnings;
    use IO::Socket::UNIX;
    use JSON::PP;
    open STDERR, '>', '/dev/null';

    my $path = $ENV{BRIM_AGENT_SOCKET} // "$ENV{HOME}/Library/Application Support/Brim/agent.sock";
    my $raw = do { local $/; <STDIN> } // '';
    my $json = JSON::PP->new->utf8->canonical;
    my $in = eval { $json->decode($raw) };
    exit 0 unless ref $in eq 'HASH';

    sub line {
        my ($value, $limit) = @_;
        return undef unless defined $value && !ref $value;
        $value =~ s/\s+/ /g;
        $value =~ s/^ | $//g;
        return length($value) > $limit ? substr($value, 0, $limit - 1) . "\x{2026}" : $value;
    }

    my $event = $in->{hook_event_name} // '';
    my $input = ref $in->{tool_input} eq 'HASH' ? $in->{tool_input} : {};
    my %out = (
        event => $event,
        session_id => line($in->{session_id}, 200),
        cwd => line($in->{cwd}, 1000),
        agent_pid => getppid(),
        tool_name => line($in->{tool_name}, 100),
        summary => line($input->{description} // $input->{file_path} // $input->{url}
            // $input->{pattern} // $input->{query} // $input->{command} // $input->{prompt}, 300),
        command => line($input->{command}, 1000),
        prompt => line($in->{prompt}, 500),
        message => line($in->{message}, 300),
        notification_type => line($in->{notification_type}, 100),
        last_message => line($in->{last_assistant_message}, 600),
    );

    my $asked = $input->{questions};
    if (ref $asked eq 'ARRAY' && @$asked && @$asked <= 4
        && !grep { ref $_ ne 'HASH' || ref $_->{options} ne 'ARRAY' || !@{$_->{options}} || @{$_->{options}} > 4 } @$asked) {
        $out{questions} = [map { {
            question => $_->{question},
            header => line($_->{header}, 40),
            multi_select => $_->{multiSelect} ? JSON::PP::true : JSON::PP::false,
            options => [map { ref $_ eq 'HASH' ? line($_->{label}, 100) : undef } @{$_->{options}}],
        } } @$asked];
    }

    my $socket = IO::Socket::UNIX->new(Type => SOCK_STREAM(), Peer => $path) or exit 0;
    $socket->autoflush(1);
    print {$socket} $json->encode(\%out), "\n" or exit 0;
    exit 0 unless $event eq 'PermissionRequest';

    # Held until Brim answers, or closes because the session moved on without it.
    my $reply = <$socket>;
    exit 0 unless defined $reply;
    $reply =~ s/\s+$//;
    my $decision;
    if ($reply eq 'allow') {
        $decision = { behavior => 'allow' };
    } elsif ($reply eq 'deny') {
        $decision = { behavior => 'deny', message => 'Declined from Brim.' };
    } elsif ($reply =~ /^\{/ && ref $asked eq 'ARRAY') {
        my $parsed = eval { $json->decode($reply) };
        my $given = ref $parsed eq 'HASH' ? $parsed->{answers} : undef;
        exit 0 unless ref $given eq 'ARRAY' && @$given == @$asked;
        my %answers;
        for my $i (0 .. $#$asked) {
            my ($question, $value) = ($asked->[$i]{question}, $given->[$i]);
            exit 0 unless defined $question && defined $value && !ref $value && length $value;
            $answers{$question} = $value;
        }
        $decision = { behavior => 'allow', updatedInput => { %$input, answers => \%answers } };
    }
    exit 0 unless $decision;
    print $json->encode({
        hookSpecificOutput => { hookEventName => 'PermissionRequest', decision => $decision },
    });
    exit 0;
    """#
}

/// Adds and removes Brim's entries in `~/.claude/settings.json`. Idempotent: install first strips
/// any entry whose command names Brim's script, so running it twice converges on one copy.
enum HookInstaller {
    static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "PermissionRequest", "Notification", "Stop", "SessionEnd",
    ]

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    enum Failure: LocalizedError {
        case unreadableSettings
        var errorDescription: String? { "~/.claude/settings.json isn't a JSON object, so Brim left it alone." }
    }

    static var isInstalled: Bool {
        guard let settings = try? readSettings() else { return false }
        return containsBrim(settings)
    }

    static func install() throws {
        try HookScript.install()
        try writeSettings(addingBrim(to: try readSettings()))
    }

    static func uninstall() throws {
        try writeSettings(removingBrim(from: try readSettings()))
        HookScript.remove()
    }

    // MARK: Pure edits (tested)

    /// The settings with exactly one copy of Brim's hooks, whatever was there before. Everything else is kept.
    static func addingBrim(to settings: [String: Any], command: String = HookScript.command) -> [String: Any] {
        var settings = settings
        var hooks = stripped(settings["hooks"] as? [String: Any] ?? [:])
        for event in events {
            var handler: [String: Any] = ["type": "command", "command": command]
            handler["timeout"] = event == "PermissionRequest" ? 3600 : 5
            var group: [String: Any] = ["hooks": [handler]]
            if ["PreToolUse", "PostToolUse", "PermissionRequest"].contains(event) { group["matcher"] = "*" }
            hooks[event] = (hooks[event] as? [[String: Any]] ?? []) + [group]
        }
        settings["hooks"] = hooks
        return settings
    }

    /// The settings with every Brim handler removed, and any group or event that leaves empty.
    static func removingBrim(from settings: [String: Any]) -> [String: Any] {
        var settings = settings
        let hooks = stripped(settings["hooks"] as? [String: Any] ?? [:])
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        return settings
    }

    static func containsBrim(_ settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { groups in
            (groups as? [[String: Any]] ?? []).contains { group in
                (group["hooks"] as? [[String: Any]] ?? []).contains(where: isBrimHandler)
            }
        }
    }

    private static func isBrimHandler(_ handler: [String: Any]) -> Bool {
        (handler["command"] as? String)?.contains("Application Support/Brim/claude-hook.pl") == true
    }

    private static func stripped(_ hooks: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { result[event] = value; continue }
            let kept: [[String: Any]] = groups.compactMap { group in
                var group = group
                let handlers = (group["hooks"] as? [[String: Any]] ?? []).filter { !isBrimHandler($0) }
                if handlers.isEmpty { return nil }
                group["hooks"] = handlers
                return group
            }
            if !kept.isEmpty { result[event] = kept }
        }
        return result
    }

    private static func readSettings() throws -> [String: Any] {
        guard let data = try? Data(contentsOf: settingsURL), !data.isEmpty else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.unreadableSettings
        }
        return object
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: settingsURL.path) {
            let backup = settingsURL.appendingPathExtension("brim-backup")
            try? manager.removeItem(at: backup)
            try? manager.copyItem(at: settingsURL, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }
}
