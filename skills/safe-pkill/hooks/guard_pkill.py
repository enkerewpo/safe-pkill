#!/usr/bin/env python3
"""Claude Code PreToolUse hook: block self-matching `pkill -f` / `pgrep -f`.

A Bash tool call runs inside a wrapper shell whose command line is the whole command,
and `ssh host '...'` runs the remote part inside `sh -c '...'`. A bare `pkill -f PATTERN`
therefore also matches (and kills) that wrapper -- the session dies, ssh exits 255.

Allowed: commands that go through spkill, and patterns using the bracket trick
(`pkill -f '[m]y_job'`), which cannot match their own command line.

Install (settings.json):
  "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command",
    "command": "python3 ~/.claude/skills/safe-pkill/hooks/guard_pkill.py"}]}]}
"""
import json
import re
import shlex
import sys

SPKILL = "~/.claude/skills/safe-pkill/spkill"
CALL = re.compile(r"(?<![\w./-])(pkill|pgrep)\b([^|;&\n`)]*)")


def risky(command: str) -> bool:
    for m in CALL.finditer(command):
        rest = m.group(2)
        try:
            words = shlex.split(rest, posix=True)
        except ValueError:
            words = rest.split()
        opts = [w for w in words if w.startswith("-") and not w.startswith("--")]
        full = any("f" in w[1:] for w in opts) or "--full" in words
        if not full:
            continue  # without -f only the process name is matched: no self-match
        pattern = [w for w in words if not w.startswith("-")]
        if pattern and "[" in pattern[-1] and "]" in pattern[-1]:
            continue  # bracket trick: '[m]y_job' does not match its own text
        return True
    return False


def main() -> int:
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    if data.get("tool_name") != "Bash":
        return 0
    cmd = (data.get("tool_input") or {}).get("command") or ""
    if "spkill" in cmd or not risky(cmd):
        return 0
    reason = (
        "Blocked: `pkill -f`/`pgrep -f` also matches the wrapper shell running this command "
        "(the Bash tool's shell, or `sh -c` behind ssh) and kills or finds itself; over ssh the "
        "session dies with exit 255. Use spkill instead:\n"
        f"  local:  {SPKILL} [-n] PATTERN\n"
        f"  remote: ssh HOST 'bash -s' -- [-n] PATTERN < {SPKILL}\n"
        "(-n lists without signalling, replacing pgrep -af). Or use the bracket trick: "
        "pkill -f '[m]y_job'."
    )
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
