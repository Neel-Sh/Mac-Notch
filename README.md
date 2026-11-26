<div align="center">

<img src="assets/icon-preview.png" alt="Brim app icon" width="128" height="128">

# Brim

**Your Claude Code sessions, in the notch.**

Brim turns the black strip at the top of your MacBook into a command center for Claude Code: what every session is doing, which one needs you, and Allow or Deny without leaving what you're working on. Your calendar, tasks, weather, music and a file shelf are there too.

[![CI](https://github.com/Neel-Sh/Mac-Notch/actions/workflows/ci.yml/badge.svg)](https://github.com/Neel-Sh/Mac-Notch/actions/workflows/ci.yml)
![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

<img src="assets/demo.gif" alt="Brim: an approval request opens from the notch, then the island shows agents, calendar, weather with rain falling inside it, tasks and the file shelf" width="760">

<sub>Recorded in Brim's demo mode. Every name, project and event is made up.</sub>

</div>

---

## Why

Claude Code is at its best when you hand it something and go do something else. Then it stops to ask permission for a command, and you don't notice for twenty minutes. Brim watches every session on your Mac, from the terminal, your editor or the Claude app, and taps you on the shoulder from the one place on the screen that's always visible and never in the way.

## Features

### 🤖 Agents: every session at a glance

<img src="assets/screenshots/agents.png" alt="The Agents tab listing five Claude Code sessions: one asking to run xcodebuild with Allow and Deny buttons, one finished, two working, one idle" width="680">

Each Claude Code session shows its title, its project, and what it's doing right now ("Editing PricingEngine.ts", "Thinking…"). A clock shows how long the current turn has been running. Whatever needs you sorts to the top.

- **No setup.** Brim reads the session files Claude Code already keeps, so sessions appear the moment you start `claude`.
- **Jump to it.** Click a session to bring its terminal, editor or Claude window to the front.
- **Swipe to hide.** Two fingers left on a row hides a session you don't care about. It comes back when it starts working or needs you.
- **The status marks** keep one round shape for every state: an outline when idle, a turning ring while working, amber when it needs you, a green check when it's done. "Done" fades back to idle after a minute, or once you've seen it.

### ✋ Approvals from the notch

<img src="assets/screenshots/approval.png" alt="The notch opened just enough to show 'Claude needs permission' with the command and Deny and Allow buttons, glowing amber along its edge" width="560">

When a session asks permission, the notch opens just enough to show the exact command, glowing amber along its edge, with **Allow** and **Deny**. Single-choice questions from Claude appear as buttons you can click. Answer in the terminal instead and the notch steps aside on its own.

Approvals come from a small hook that you turn on with one click. See [How it works](#how-it-works).

### 🏝️ Live activity beside the notch

<img src="assets/screenshots/wings.png" alt="The closed notch with an amber mark on the left and a terminal icon on the right" width="420">

Closed, the island grows just past the notch to show the most important thing going on: the lead session's state and what it's running, or how many sessions are waiting on you. With music playing, it shows the artwork and bars that move only while something is actually playing.

### 📅 Calendar

<img src="assets/screenshots/calendar.png" alt="The Calendar tab: a week of days across the top and today's events below, with a Join button on a video call" width="680">

The week as a row of days, with dots on the days that have something on. Tap a day to see its events in each calendar's colour, with the meeting happening now marked live. Zoom, Meet, Teams and Webex invitations get a **Join** button. It reads every calendar the Mac's Calendar app shows.

### 🌧️ Weather

<img src="assets/screenshots/weather.png" alt="The Weather tab: 11° and rain in Cupertino, rain chance, humidity, feels-like and wind, five days of temperature bars and the next seven hours, with rain streaks falling inside the island" width="680">

Current conditions, rain chance, humidity, feels-like and wind. Five days of temperature bars on one shared scale, coloured by temperature, with a dot on today's bar where it is right now. Below, the next seven hours.

The weather is drawn inside the island: rain falls and splashes on its bottom edge, snow drifts, mist rolls through, and clear nights twinkle. All of it holds still when Reduce Motion is on.

### ✅ Tasks

<img src="assets/screenshots/tasks.png" alt="The Tasks tab: a field to add a task and four tasks, one checked off" width="680">

A quick place for notes and to-dos that doesn't need its own window. Type, press Return, check it off. Swipe or right-click to delete. Tasks survive a restart.

### 🎵 Music

<img src="assets/screenshots/music.png" alt="The Music tab: album artwork, track title and artist, with previous, pause and next buttons" width="680">

What's playing in Music or Spotify, with artwork and playback controls. Click the artwork to open the player.

### 📥 Shelf

<img src="assets/screenshots/shelf.png" alt="The Shelf tab holding three images, with AirDrop, Copy, Make PDF and Show in Finder" width="680">

Drag files onto the notch and they wait on the shelf until you know where they go. AirDrop them, copy them, turn a stack of images into one PDF, or drag them back out. The shelf survives a restart.

## Made to feel like part of macOS

- **Physical motion.** The island opens and closes on critically damped springs, so it never wobbles. Content fades out before the shape shrinks, so text is never squeezed, and new content settles in from just above.
- **Forgiving pointer.** It opens after a 120 ms pause on the notch and closes only after the pointer has been away for 420 ms, so a brush past the edge doesn't snap it shut. It stays open while you type, and Escape closes it.
- **The real notch shape.** Brim is flush with the bezel, with continuous corners, and its top corners curve outward into the menu bar when open.
- **Never in the way.** Clicks next to the island pass straight through to the app underneath, and Brim never takes focus from the app you're using.
- **Accessible.** It respects Reduce Motion, controls have labels, and states use shape as well as colour.

## How it works

```mermaid
flowchart LR
    CC["Claude Code"] -->|writes session status| SF["~/.claude/sessions/*.json"]
    SF -->|read once a second| B["Brim"]
    CC -->|"hook events (opt-in)"| H["claude-hook.pl"]
    H -->|Unix socket| B
    B -->|Allow / Deny| H
    H -->|decision JSON| CC
```

- **Session list.** Claude Code writes each live session's status to `~/.claude/sessions/<pid>.json`. Brim reads those files, so the session list needs no setup.
- **Live detail and approvals.** These need one hook. Press **Turn On** in the Agents tab, or use Settings.
  - Brim adds a small Perl script to `~/.claude/settings.json`, after saving a backup to `settings.json.brim-backup`.
  - The script forwards each event to Brim over a Unix socket that only your user can open.
  - For a permission request, the script waits for your click and hands the answer back to Claude Code in its own `PermissionRequest` format.
- **If Brim isn't running,** the hook prints nothing and exits, so Claude Code behaves exactly as if it weren't there.
- **Turning it off** removes exactly the entries Brim added. Every other hook you have is left as it was, and [tests](BrimTests/HookInstallerTests.swift) check that.

## Privacy

Brim has no account, no analytics and no server.

| What | Where it goes |
| --- | --- |
| Claude Code sessions, prompts, commands | Stay on your Mac. The hook talks only to Brim, over a local socket. |
| Calendar events | Read on your Mac through EventKit. Never sent anywhere. |
| Tasks and shelf | Saved in `~/Library/Application Support/Brim`. |
| Location | Rounded to about 1 km and sent to [Open-Meteo](https://open-meteo.com) for the forecast, every 20 minutes. Only after you allow location, which Brim first asks for when you open Weather. |

## Requirements

- A Mac running **macOS 26 or later**. A notch is best, but Brim also works without one.
- **Xcode 26 or later** to build.
- **[Claude Code](https://claude.com/claude-code)** for the Agents tab.

## Install

Brim isn't in a signed release yet, so build it from source:

```bash
git clone https://github.com/Neel-Sh/Mac-Notch.git
cd Mac-Notch
xcodebuild -project Brim.xcodeproj -scheme Brim -configuration Release -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Release/Brim.app
```

You can also open `Brim.xcodeproj` in Xcode and press ⌘R. To keep it, drag `Brim.app` into `/Applications` and turn on **Open at login** in Settings. Settings is in the menu bar under the half-capsule icon.

### Permissions Brim asks for

| Permission | When | Why |
| --- | --- | --- |
| Location | First time you open Weather | The forecast where you are |
| Calendars | First time you open Calendar | Your events |
| Automation (Music, Spotify) | First time a track plays | Artwork and playback controls |
| Accessibility (optional) | Never asked for. Grant it yourself if you want it. | Raising the exact window a session runs in, not just its app |

## Development

```bash
# Run the unit tests
xcodebuild test -project Brim.xcodeproj -scheme Brim

# Check the Claude Code hook script compiles
scripts/check-hook-script.sh

# Run with made-up data, for screenshots or a quick look
open build/DerivedData/Build/Products/Debug/Brim.app --args -demo YES -openTab weather

# Regenerate the README screenshots and the demo recording
scripts/screenshots.sh
scripts/record-demo.sh
```

`-openTab` takes `agents`, `calendar`, `tasks`, `weather`, `media` or `shelf`. Demo mode never reads your sessions, calendar or location, and never saves anything.

[CONTRIBUTING.md](CONTRIBUTING.md) covers how the code is laid out and its conventions.

## Roadmap

- Answer multi-question and multi-select prompts from the notch
- Transcribe audio and video dropped on the shelf
- An island on every display, not just the built-in one
- A signed, notarized download

Ideas and bug reports are welcome in [Issues](https://github.com/Neel-Sh/Mac-Notch/issues).

## Acknowledgements

Brim learned a lot from two notch apps: [Isleta](https://github.com/rahulashwinhira/rahuls-dynamic-island), whose notes on notch windows and Claude Code hooks saved many dead ends, and [Auri](https://github.com/Neel-Sh/Auridesktop), whose open-and-close timing Brim's motion is tuned after.

## License

MIT. See [LICENSE](LICENSE).
