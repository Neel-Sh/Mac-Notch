# Contributing to Brim

## Build and test

You need Xcode 26 or later on macOS 26 or later.

```bash
xcodebuild test -project Brim.xcodeproj -scheme Brim -derivedDataPath build/DerivedData
```

To try a change without your own sessions, calendar or location, run in demo mode:

```bash
open build/DerivedData/Build/Products/Debug/Brim.app --args -demo YES -openTab agents
```

`scripts/screenshots.sh` and `scripts/record-demo.sh` regenerate the README images from demo mode. Rerun them when a change alters how a page looks.

`scripts/check-hook-script.sh` checks that the Perl hook Brim installs into Claude Code still compiles. CI runs both on every pull request.

## How the code is laid out

| Folder | What lives there |
| --- | --- |
| `Brim/Island` | The panel over the notch, its shape, motion tokens, layout and the tab bar |
| `Brim/Agents` | Claude Code sessions: session files, the hook script and its socket server, approvals |
| `Brim/Calendar`, `Tasks`, `Weather`, `Media`, `Shelf` | One folder per tab: its data source and its page |
| `Brim/App` | App entry, settings, and the made-up content behind demo mode |
| `BrimTests` | Unit tests for the logic that doesn't need a screen |
| `scripts` | Hook check, screenshots and the demo recording |

## Conventions

- Every animation uses a token from `Motion` in `Brim/Island/IslandShape.swift`. No inline curves.
- Every size the island takes comes from `IslandLayout`, so drawing and hit testing can't disagree.
- External formats (Claude Code's session files, hook events, Open-Meteo) are parsed once, at the edge, into typed values.
- Anything that changes `~/.claude/settings.json` must leave every entry Brim didn't add exactly as it was. `HookInstallerTests` holds that line.
- Check visual changes in the running app, not only in the build.

## Commits and pull requests

Commit messages follow `type(scope): subject`, for example `fix(agents): keep the turn clock running across tool calls`. Keep each pull request to one change, and fill in the template.
