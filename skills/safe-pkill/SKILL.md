---
name: safe-pkill
description: Kill or find processes by command-line pattern without killing your own shell. Use whenever you would run `pkill -f`, `pgrep -f`/`pgrep -af`, or `ps | grep | kill` — locally or over ssh — to stop a background job, a server, a training run, a monitor script, or to check whether one is still running. Bare `pkill -f PATTERN` matches the wrapper shell that carries PATTERN in its own command line (the agent's Bash tool shell, or `sh -c` behind `ssh host '...'`) and kills it — ssh exits 255 and the rest of the command never runs.
---

# safe-pkill

## Why

Every agent Bash call and every `ssh host 'cmd'` runs inside a wrapper shell whose command line *is* the command. So

```bash
ssh box 'pkill -f train.py; echo done'   # kills its own `sh -c` → ssh exit 255, "done" never prints
pgrep -af train.py || echo stopped        # finds its own wrapper → "still running" forever
```

This is Linux (procps-ng) behaviour, which is what you get on servers, containers and Jetson/embedded boards. BSD/macOS `pkill` excludes its own ancestors by default, but `ssh linux-host '...'` still runs the Linux one.

Symptoms: `Exit code 255` from ssh right after a `pkill -f`, half-executed command chains, or a pgrep loop that never sees the job stop.

## The tool: `spkill`

`spkill` is a single bash script next to this file. It matches the full command line like `pkill -f`, but excludes **itself, every ancestor, and its own children**. It sends SIGTERM by default, waits for the processes to exit, and refuses SIGKILL unless you pass `--kill-9`. SIGKILL on a process that is inside a GPU or device-driver call can leave an unkillable D-state zombie holding the device.

```bash
S=~/.claude/skills/safe-pkill/spkill        # or wherever this skill is installed

# local
$S -n 'train\.py'                          # list only (replaces pgrep -af)
$S 'train\.py'                             # SIGTERM, wait up to 5 s, report survivors

# remote — nothing to install; the script is streamed over stdin
ssh box 'bash -s' -- -n 'train\.py' < $S
ssh box 'bash -s' -- -w 30 'train\.py' < $S
ssh box 'sudo bash -s' -- -u root 'nginx: master' < $S   # needs passwordless sudo
```

| Option | Meaning |
|---|---|
| `-n`, `-l` | list matches, send nothing |
| `-s SIG` | TERM (default), INT, HUP, USR1, USR2, QUIT |
| `-w SEC` | wait up to SEC for exit (default 5; `0` = don't wait) |
| `-u USER` | only that user's processes |
| `--kill-9` | allow SIGKILL |
| `-q` | quiet |

Exit status: `0` matched (and all exited); `1` no match; `2` usage error; `3` still alive after `-w`.

The pattern is an extended regex on the full command line, the same as `pkill -f`.

## Rules

1. Never write a bare `pkill -f` / `pgrep -f` in a Bash tool call or inside `ssh '...'`. Use `spkill`.
2. If `spkill` is unavailable, use the bracket trick, which cannot match its own text: `pkill -f '[t]rain\.py'`, `pgrep -af '[t]rain\.py'`.
3. Check with `-n` first when the pattern is broad (`python`, `node`, `java`). A forked subshell of your own script can carry the pattern in its argv. It is not an ancestor, so it will be listed. That is usually what you want, because it is the job's parent.
4. Default to SIGTERM and `-w`. Escalate to `--kill-9` only for processes that are not touching a GPU or device and that ignored SIGTERM.
5. Stop a parent orchestrator before its children, or it will respawn them.

## Optional guard hook (Claude Code)

`hooks/guard_pkill.py` is a PreToolUse hook. It blocks bare `pkill -f` / `pgrep -f` / `--full` and points the agent at `spkill`. It lets through the bracket trick, name-only `pkill name`, and anything that uses `spkill`. Add it to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "python3 ~/.claude/skills/safe-pkill/hooks/guard_pkill.py" }
        ]
      }
    ]
  }
}
```
