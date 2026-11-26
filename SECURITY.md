# Security

Brim adds a hook to Claude Code and answers permission requests, so a bug in that path matters. If you find one, please report it privately through [GitHub's private vulnerability reporting](https://github.com/Neel-Sh/Mac-Notch/security/advisories/new) rather than in a public issue.

Worth reporting:

- Anything that lets another user or process answer a permission request through Brim's socket
- Brim changing `~/.claude/settings.json` beyond the entries it adds
- The hook changing a tool's input other than filling in answers you chose

You'll hear back within a week.
