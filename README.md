# safe-pkill

An agent skill (Claude Code and other [skills](https://skills.sh)-compatible agents) plus a tiny tool, `spkill`, for the most common way agents shoot themselves in the foot on remote machines:

```bash
ssh box 'pkill -f train.py; echo done'   # → exit 255, "done" never prints
```

On Linux (procps-ng), `pkill -f PATTERN` matches the full command line of **every** process, including the `sh -c 'pkill -f train.py; …'` that ssh started for you. It kills its own session. The agent's local Bash tool has the same problem, because it wraps each command in a shell whose argv is the command. `pgrep -af PATTERN` likewise "finds" its own wrapper, so "wait until it stops" loops never end.

## What's inside

| Path | What |
|---|---|
| `skills/safe-pkill/SKILL.md` | The skill: when it applies, rules, usage |
| `skills/safe-pkill/spkill` | Single-file bash tool: `pkill -f` / `pgrep -af` that excludes itself, all ancestors and its own children; SIGTERM by default, waits for exit, refuses SIGKILL unless `--kill-9` |
| `skills/safe-pkill/hooks/guard_pkill.py` | Optional Claude Code PreToolUse hook that blocks bare `pkill -f` / `pgrep -f` and points at `spkill` |
| `tests/run.sh` | Reproduces the trap and checks the tool and hook (Linux and macOS) |

## Install

```bash
npx skills add enkerewpo/safe-pkill -g     # global: ~/.claude/skills/safe-pkill (paths below assume this)
```

Without `-g` it goes into the project (`.agents/skills/safe-pkill`); adjust the paths accordingly. Or copy `skills/safe-pkill/` into `~/.claude/skills/`.

## Use

```bash
S=~/.claude/skills/safe-pkill/spkill
$S -n 'train\.py'                                # list (replaces pgrep -af)
$S -w 30 'train\.py'                             # SIGTERM, wait up to 30 s
ssh box 'bash -s' -- -w 30 'train\.py' < $S      # remote: nothing to install there
```

Exit status: `0` matched and exited · `1` no match · `2` usage error · `3` still alive after `-w`.

### Optional guard hook

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash",
        "hooks": [{ "type": "command", "command": "python3 ~/.claude/skills/safe-pkill/hooks/guard_pkill.py" }] }
    ]
  }
}
```

The hook allows the bracket trick (`pkill -f '[t]rain\.py'`), name-only `pkill name`, and anything that goes through `spkill`. It is a plain text check, so it can also block a command that only *mentions* `pkill -f` inside a string, for example `sed` editing a file that contains it. Use a file-editing tool for that case.

## 中文说明

Linux 上 `pkill -f 模式` 会匹配所有进程的完整命令行。通过 `ssh 主机 '…'` 或 agent 的 Bash 工具执行时，外层 shell 自己的命令行里就带着这个模式，于是把自己所在的会话也杀掉了：ssh 返回 255，后面的命令不再执行。`pgrep -af` 同理，会把外层 shell 当成"目标还在运行"。

`spkill` 按命令行匹配，但排除自身、全部祖先进程和自己的子进程。默认发 SIGTERM 并等待退出；不加 `--kill-9` 不允许 SIGKILL，因为对正在做 GPU 或设备驱动调用的进程用 SIGKILL，可能留下无法回收的 D 状态进程。远端无需安装：`ssh 主机 'bash -s' -- 模式 < spkill`。

## License

MIT © 2026 wheatfox
