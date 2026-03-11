#!/usr/bin/env python3
"""Removes ClawGotchi hooks from Claude Code settings."""

import json
import os
import signal

SETTINGS_PATH = os.path.expanduser("~/.claude/settings.json")
HOOKS_DIR = os.path.expanduser("~/.claude/hooks")
HOOK_SCRIPT = os.path.join(HOOKS_DIR, "clawgotchi-hook.py")
APP_PATH_FILE = os.path.join(HOOKS_DIR, "clawgotchi-app-path")

HOOK_EVENTS = [
    "PreToolUse", "PostToolUse", "PermissionRequest",
    "Notification", "Stop", "SessionStart", "SessionEnd",
]


def main():
    # Kill running app
    try:
        os.system("pkill -x ClawGotchi 2>/dev/null")
        print("  Stopped ClawGotchi app")
    except Exception:
        pass

    # Remove hook script
    for f in [HOOK_SCRIPT, APP_PATH_FILE]:
        if os.path.exists(f):
            os.remove(f)
            print(f"  Removed {f}")

    # Clean hooks from settings
    if os.path.exists(SETTINGS_PATH):
        try:
            with open(SETTINGS_PATH) as f:
                settings = json.load(f)
        except (json.JSONDecodeError, IOError):
            print(f"  WARNING: Could not parse {SETTINGS_PATH}")
            return

        hooks = settings.get("hooks", {})
        changed = False

        for event in HOOK_EVENTS:
            existing = hooks.get(event, [])
            filtered = [
                rule for rule in existing
                if not any("clawgotchi-hook.py" in h.get("command", "") for h in rule.get("hooks", []))
            ]
            if len(filtered) != len(existing):
                changed = True
                if filtered:
                    hooks[event] = filtered
                else:
                    del hooks[event]

        if changed:
            settings["hooks"] = hooks
            with open(SETTINGS_PATH, "w") as f:
                json.dump(settings, f, indent=2)
            print(f"  Cleaned hooks from {SETTINGS_PATH}")

    # Clean tmp files
    for f in [
        "/tmp/clawgotchi-events.jsonl",
        "/tmp/clawgotchi-pending.json",
        "/tmp/clawgotchi-response.json",
        "/tmp/clawgotchi-sessions.json",
    ]:
        if os.path.exists(f):
            os.remove(f)

    print()
    print("  ClawGotchi uninstalled!")
    print("  You can safely delete this folder now.")


if __name__ == "__main__":
    main()
