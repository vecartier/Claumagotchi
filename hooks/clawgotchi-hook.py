#!/usr/bin/env python3
"""ClawGotchi hook — forwards Claude Code events, handles permissions, auto-launches app."""

import json
import os
import subprocess
import sys
import time
import uuid

EVENT_FILE = "/tmp/clawgotchi-events.jsonl"
PENDING_FILE = "/tmp/clawgotchi-pending.json"
RESPONSE_FILE = "/tmp/clawgotchi-response.json"
SESSIONS_FILE = "/tmp/clawgotchi-sessions.json"
APP_PATH_FILE = os.path.expanduser("~/.claude/hooks/clawgotchi-app-path")


def get_app_path():
    """Read app path from config file, fall back to common locations."""
    if os.path.exists(APP_PATH_FILE):
        with open(APP_PATH_FILE) as f:
            path = f.read().strip()
            if os.path.exists(path):
                return path
    # Fallback: search common locations
    for candidate in [
        os.path.expanduser("~/Desktop/ClawGotchi/ClawGotchi.app"),
        os.path.expanduser("~/ClawGotchi/ClawGotchi.app"),
        os.path.expanduser("~/Projects/ClawGotchi/ClawGotchi.app"),
        os.path.expanduser("~/Developer/ClawGotchi/ClawGotchi.app"),
    ]:
        if os.path.exists(candidate):
            return candidate
    return None

PERMISSION_TIMEOUT = 55  # seconds (hook timeout is 60s)

EVENT_MAP = {
    "PreToolUse": "pre_tool",
    "PostToolUse": "post_tool",
    "PostToolUseFailure": "post_tool_error",
    "PermissionRequest": "permission",
    "Notification": "notification",
    "Stop": "stop",
    "SessionStart": "session_start",
    "SessionEnd": "session_end",
}


def write_event(event_type, tool="", extra=None):
    """Append an event to the events file, truncating if it exceeds 50KB."""
    # Truncate: keep only last 20 lines when file exceeds 50KB
    try:
        if os.path.exists(EVENT_FILE) and os.path.getsize(EVENT_FILE) > 50 * 1024:
            with open(EVENT_FILE, "r") as f:
                lines = f.readlines()
            with open(EVENT_FILE, "w") as f:
                f.writelines(lines[-20:])
    except OSError:
        pass

    out = {"event": event_type, "tool": tool, "ts": int(time.time())}
    if extra:
        out.update(extra)
    with open(EVENT_FILE, "a") as f:
        f.write(json.dumps(out) + "\n")


def track_session(session_id, action):
    """Track active sessions."""
    sessions = {}
    if os.path.exists(SESSIONS_FILE):
        try:
            with open(SESSIONS_FILE) as f:
                sessions = json.load(f)
        except (json.JSONDecodeError, IOError):
            sessions = {}

    if action == "start":
        sessions[session_id] = int(time.time())
    elif action == "end":
        sessions.pop(session_id, None)

    # Clean stale sessions (older than 2 hours)
    now = int(time.time())
    sessions = {k: v for k, v in sessions.items() if now - v < 7200}

    with open(SESSIONS_FILE, "w") as f:
        json.dump(sessions, f)


def ensure_app_running():
    """Launch ClawGotchi if not already running."""
    result = subprocess.run(["pgrep", "-x", "ClawGotchi"], capture_output=True)
    if result.returncode != 0:
        app_path = get_app_path()
        if app_path:
            subprocess.Popen(["open", app_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def handle_permission(data):
    """Handle PermissionRequest — block and wait for user response from app."""
    tool = data.get("tool_name", "")
    tool_input = data.get("tool_input", {})
    req_id = uuid.uuid4().hex[:8]

    # Write pending request file (BEFORE events file so app can read it)
    pending = {
        "id": req_id,
        "tool": tool,
        "input": tool_input,
        "ts": int(time.time()),
    }
    with open(PENDING_FILE, "w") as f:
        json.dump(pending, f)

    # Write event for display
    write_event("permission", tool=tool)

    # Poll for response
    start = time.time()
    while time.time() - start < PERMISSION_TIMEOUT:
        if os.path.exists(RESPONSE_FILE):
            try:
                with open(RESPONSE_FILE) as f:
                    resp = json.load(f)
                if resp.get("id") == req_id:
                    # Clean up
                    try:
                        os.remove(RESPONSE_FILE)
                    except OSError:
                        pass
                    try:
                        os.remove(PENDING_FILE)
                    except OSError:
                        pass

                    decision = resp.get("decision", "allow")
                    output = {
                        "hookSpecificOutput": {
                            "hookEventName": "PermissionRequest",
                            "decision": {
                                "behavior": decision,
                                "message": f"{'Approved' if decision == 'allow' else 'Denied'} via ClawGotchi",
                            },
                        }
                    }
                    print(json.dumps(output))
                    return
            except (json.JSONDecodeError, KeyError, IOError):
                pass
        time.sleep(0.3)

    # Timeout — clean up and let normal prompt appear
    try:
        os.remove(PENDING_FILE)
    except OSError:
        pass
    write_event("permission_timeout")


def main():
    try:
        data = json.loads(sys.stdin.read())
    except (json.JSONDecodeError, EOFError):
        return

    event_name = data.get("hook_event_name", "")
    session_id = data.get("session_id", "")

    # Auto-launch app on session start
    if event_name == "SessionStart":
        ensure_app_running()
        track_session(session_id, "start")

    if event_name == "SessionEnd":
        track_session(session_id, "end")

    # Permission requests get special handling (blocking)
    if event_name == "PermissionRequest":
        handle_permission(data)
        return

    # Everything else: just log the event
    mapped = EVENT_MAP.get(event_name)
    if not mapped:
        return

    out = {"event": mapped, "tool": data.get("tool_name", ""), "ts": int(time.time())}

    if event_name == "Notification":
        out["type"] = data.get("notification_type", "")

    with open(EVENT_FILE, "a") as f:
        f.write(json.dumps(out) + "\n")


if __name__ == "__main__":
    main()
