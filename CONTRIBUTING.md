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

`scripts/media.sh` regenerates every README image and recording from demo mode, staged on a desktop wallpaper so nothing from your Mac is captured. Rerun it when a change alters how a page looks (`scripts/media.sh shots` for the screenshots alone). It needs Screen Recording allowed for your terminal, `ffmpeg`, and `python3` with Pillow.

Launch arguments that help while working on a page:

| Argument | What it does |
| --- | --- |
| `-demo YES` | Made-up content. Nothing is read from your Mac and nothing is saved. |
| `-openTab <page>` | Opens the island on `agents`, `calendar`, `tasks`, `weather`, `media` or `shelf`. |
| `-pref.edge left`, `-pref.compact YES`, `-pref.material glass` | Overrides a setting for this launch only. |
| `-openSettings YES -settingsTab <tab>` | Opens Settings on `general`, `appearance`, `pages` or `agents`. |
| `-demoPeek YES`, `-demoTour YES`, `-demoStyleTour YES` | Shows an approval, or plays the island through its pages or its styles. |

`scripts/check-hook-script.sh` checks that the Perl hook Brim installs into Claude Code still compiles. CI runs it and the tests on every pull request.

## How the code is laid out

| Folder | What lives there |
| --- | --- |
| `Brim/Island` | The panel over the notch, its shape, motion tokens, layout and the tab bar |
| `Brim/Agents` | Claude Code sessions: session files, the hook script and its socket server, approvals |
| `Brim/Calendar`, `Tasks`, `Weather`, `Media`, `Shelf` | One folder per tab: its data source and its page |
| `Brim/App` | App entry, settings, and the made-up content behind demo mode |
| `BrimTests` | Unit tests for the logic that doesn't need a screen |
| `scripts` | Install, the hook check, and the README screenshots and recordings |

## Conventions

- Every animation uses a token from `Motion` in `Brim/Island/IslandShape.swift`. No inline curves.
- Every size the island takes comes from `IslandLayout`, so drawing and hit testing can't disagree.
- External formats (Claude Code's session files, hook events, Open-Meteo) are parsed once, at the edge, into typed values.
- Anything that changes `~/.claude/settings.json` must leave every entry Brim didn't add exactly as it was. `HookInstallerTests` holds that line.
- Check visual changes in the running app, not only in the build.

## Commits and pull requests

Commit messages follow `type(scope): subject`, for example `fix(agents): keep the turn clock running across tool calls`. Keep each pull request to one change, and fill in the template. Add a line to `CHANGELOG.md` under Unreleased for anything a user would notice.
