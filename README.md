# Brim

[![CI](https://github.com/Neel-Sh/Mac-Notch/actions/workflows/ci.yml/badge.svg)](https://github.com/Neel-Sh/Mac-Notch/actions/workflows/ci.yml)

A command center for Claude Code, living in your Mac's notch.

- **Agents.** Every Claude Code session on your Mac (terminal, IDE or the Claude app), with its title, what it's doing, and how long the current turn has run. The session that needs you comes first. Swipe a row left with two fingers to hide it.
- **Approvals.** When a session asks permission, the notch opens just enough to show the exact command, with **Allow** and **Deny**. Single-choice questions from Claude show up as buttons.
- **Calendar.** The week as a rail of days, with the selected day's events below. Video calls get a **Join** button.
- **Tasks.** Quick notes and to-dos that survive a restart.
- **Weather.** Current conditions, rain chance, humidity, wind, the next hours and five days. Rain, snow, mist and stars are drawn inside the island.
- **Music.** Music and Spotify, with artwork and transport controls.
- **Shelf.** Drag files onto the notch to park them, then AirDrop, copy, turn images into a PDF, or drag them back out.

## Build

Requires macOS 26 or later. Open `Brim.xcodeproj` in Xcode 26 or later and run. To build from the command line:

```bash
xcodebuild -project Brim.xcodeproj -scheme Brim -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Brim.app
```

Run the tests with `xcodebuild test -project Brim.xcodeproj -scheme Brim`. See [CONTRIBUTING.md](CONTRIBUTING.md) for how the code is laid out.

Pass `--args -openTab agents` (or `calendar`, `tasks`, `weather`, `media`, `shelf`) to open the island on launch.

## How it talks to Claude Code

- **Session list, no setup.** Claude Code writes each live session's status to `~/.claude/sessions/<pid>.json`. Brim reads those files once a second.
- **Live detail and approvals, opt-in.** Turning this on (from the banner or in Settings) adds one Perl hook to `~/.claude/settings.json` and saves a backup of the file first. Turning it off removes only what Brim added.
  - The hook sends each event to Brim over a Unix socket at `~/Library/Application Support/Brim/agent.sock`.
  - For a permission request, it waits for your click.
  - If Brim isn't running, the hook prints nothing and exits 0, so Claude Code behaves exactly as if the hook weren't there.

## Icon

`Brim.icon` is an Icon Composer document, so you can open it in Icon Composer to edit the Liquid Glass layers.
