#!/usr/bin/env bash
# Reproduces the pkill -f self-kill and checks that spkill avoids it. Linux and macOS.
set -u
S="$(cd "$(dirname "$0")/.." && pwd)/skills/safe-pkill/spkill"
H="$(cd "$(dirname "$0")/.." && pwd)/skills/safe-pkill/hooks/guard_pkill.py"
fail=0; ok() { echo "ok   $1"; }; bad() { echo "FAIL $1"; fail=1; }
TAG="spk_test_$$"

# 1. the trap: a wrapper shell that carries the pattern gets killed by pkill -f
nohup bash -c "exec -a $TAG sleep 300" >/dev/null 2>&1 &
sleep 0.3
sh -c "pkill -f $TAG; echo survived" > /tmp/$TAG.out 2>&1
if grep -q survived /tmp/$TAG.out; then
  echo "note: this pkill excludes its own ancestors (BSD/macOS); the trap is Linux procps-ng"
else
  ok "pkill -f kills its own wrapper (the bug this tool exists for)"
fi
pkill -f "[s]pk_test_$$" 2>/dev/null; sleep 0.2

# 2. spkill from the same kind of wrapper: target dies, wrapper survives
nohup bash -c "exec -a $TAG sleep 300" >/dev/null 2>&1 &
sleep 0.3
out=$(sh -c "\"$S\" -q -w 3 $TAG; echo rc=\$?; echo survived")
echo "$out" | grep -q survived && ok "spkill wrapper survives" || bad "spkill wrapper survives"
echo "$out" | grep -q "rc=0" && ok "spkill terminated the target" || bad "spkill terminated the target ($out)"

# 3. dry run lists nothing once the target is gone (wrapper not reported)
sh -c "\"$S\" -n $TAG" >/dev/null; [ $? = 1 ] && ok "no false match on own wrapper" || bad "no false match on own wrapper"

# 4. SIGKILL refused without --kill-9
"$S" -s KILL nothing_zz >/dev/null 2>&1; [ $? = 2 ] && ok "SIGKILL refused by default" || bad "SIGKILL refused by default"

# 5. hook decisions
dec() { python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$1" | python3 "$H"; }
[ -n "$(dec "ssh h 'pkill -f job; echo x'")" ] && ok "hook blocks pkill -f over ssh" || bad "hook blocks pkill -f over ssh"
[ -n "$(dec "pgrep -af job")" ] && ok "hook blocks pgrep -af" || bad "hook blocks pgrep -af"
[ -z "$(dec "pkill -f '[j]ob'")" ] && ok "hook allows bracket trick" || bad "hook allows bracket trick"
[ -z "$(dec "pkill job")" ] && ok "hook allows name-only pkill" || bad "hook allows name-only pkill"
[ -z "$(dec "ssh h 'bash -s' -- job < spkill")" ] && ok "hook allows spkill" || bad "hook allows spkill"
rm -f /tmp/$TAG.out
exit $fail
