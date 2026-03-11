# Claumagotchi

A Tamagotchi-style desktop companion for [Claude Code](https://docs.anthropic.com/en/docs/claude-code). It floats above your windows and shows you what Claude is doing across all your sessions — thinking, done, or waiting for permission. You can approve or deny tool requests directly from the widget.

## Requirements

- macOS 14+
- Swift 5.10+ (comes with Xcode or Xcode Command Line Tools)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI

## Install

```bash
git clone https://github.com/user/ClawGotchi.git ~/ClawGotchi
cd ~/ClawGotchi
make install
```

That's it. The app will auto-launch every time you start a Claude Code session.

To launch manually:

```bash
open ClawGotchi.app
```

## How it works

Claumagotchi uses Claude Code's [hooks system](https://docs.anthropic.com/en/docs/claude-code/hooks) to monitor sessions. A Python hook script receives events from Claude Code and writes them to `/tmp/clawgotchi-events.jsonl`. The SwiftUI app watches that file and updates the display in real time.

```
Claude Code  -->  Hook (Python)  -->  /tmp/*.jsonl  -->  SwiftUI App
                       |                                      |
                  Permission? -----> /tmp/pending.json -----> Show UI
                       ^                                      |
                       +--------  /tmp/response.json  <-------+
```

### States

| State | What it means |
|-------|--------------|
| **THINKING...** | Claude is actively working (tool calls, reasoning) |
| **DONE!** | Claude finished and is waiting for your next message |
| **NEEDS YOU!** | Claude needs permission to use a tool |

### Buttons

Three buttons in an inverted-V layout:

- **Left** (deny) — reject the permission request
- **Right** (allow) — approve the permission request
- **Center** (go to conversation) — switch to your terminal

## Menu bar

Click the egg icon in your menu bar for:

- **Allow / Deny** — handle permissions without touching the widget
- **Go to Conversation** — jump to your terminal
- **Enable/Disable Auto-Accept** — automatically approve all permission requests
- **Enable/Disable Sounds** — toggle notification sounds
- **Show / Hide** — toggle the floating widget
- **Quit**

## Settings

Settings persist across restarts:

- **Auto-Accept** — approve all tool permissions automatically (off by default)
- **Sounds** — play a chime when Claude finishes or needs permission (on by default)

## Uninstall

```bash
cd ~/ClawGotchi
make uninstall
```

This removes the hooks from Claude Code settings, stops the app, and cleans up temp files. You can then delete the folder.

## Project structure

```
ClawGotchi/
  Package.swift          # Swift package manifest
  Makefile               # build / install / uninstall
  build.sh               # Builds the .app bundle
  setup.py               # Registers hooks with Claude Code
  uninstall.py           # Removes hooks and cleans up
  Sources/
    ClawGotchiApp.swift   # App entry, menu bar, window config
    ClaudeMonitor.swift   # State machine, file watcher, event processing
    ContentView.swift     # Egg shell UI, buttons, pixel title
    ScreenView.swift      # LCD screen, pixel character sprites
  hooks/
    clawgotchi-hook.py    # Claude Code hook script (installed to ~/.claude/hooks/)
```

## License

MIT
