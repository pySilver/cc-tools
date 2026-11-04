#!/usr/bin/env bash
# Reset Codex's context in the right-hand agterm pane between tasks.
#
# This is the one raw send peer-planning:exec makes into Codex's pane. Every message goes
# through agterm's pane mailbox (mailbox-chat.py say), which cannot deliver a slash command.
# The owner approved this raw /clear. It refuses unless Codex is idle with an empty composer,
# because a /clear during a turn discards Codex's work.
#
# After the /clear it also types a READY prompt. Codex registers a conversation for mail only
# when that conversation runs a prompt (mailbox-chat.py codex-hook, on SessionStart), so until
# then the mailbox keeps handing mail to the cleared thread. The reset counts as done once the
# registered thread id has changed.
#
# Exit 0: cleared, and the new conversation takes mail. Exit 2: refused, nothing typed.
# Exit 1: typed, but the reset or the new registration could not be confirmed; read the pane
# before continuing.
# --check runs every refusal check and exits 0 without typing, so setup can confirm Codex is idle
# and registered for mail.
set -uo pipefail

check_only=""
if [ "${1:-}" = "--check" ]; then
  check_only=yes
fi

target="${AGTERM_SESSION_ID:-}"
if [ -z "$target" ]; then
  echo "codex-clear: AGTERM_SESSION_ID is not set; not inside an agterm session" >&2
  exit 2
fi

# agtermctl never reads AGTERM_SOCKET itself; a bare call reaches the default socket, which can
# belong to another agterm instance than the one hosting this session.
socket=()
if [ -n "${AGTERM_SOCKET:-}" ]; then
  socket=(--socket "$AGTERM_SOCKET")
fi

window=()
if [ -n "${AGTERM_WINDOW_ID:-}" ]; then
  window=(--window "$AGTERM_WINDOW_ID")
fi

# The right pane's stable id, from agterm's tree of this session.
right_pane_id() {
  agtermctl tree --json ${window[@]+"${window[@]}"} ${socket[@]+"${socket[@]}"} 2>/dev/null | python3 -I -c '
import json, sys
def find(n, sid):
    if isinstance(n, dict):
        if n.get("id") == sid and "surfaces" in n:
            return n
        n = list(n.values())
    if isinstance(n, list):
        for c in n:
            hit = find(c, sid)
            if hit is not None:
                return hit
    return None
try:
    node = find(json.load(sys.stdin), sys.argv[1])
except ValueError:
    node = None
for s in (node or {}).get("surfaces") or []:
    if isinstance(s, dict) and s.get("kind") == "right" and s.get("paneID"):
        print(s["paneID"])
' "$target"
}

# The thread a live Codex registered for this pane's mail, or nothing. This reads
# mailbox-chat.py's registration file, <tmp>/agterm-mailbox-chat-<uid>/codex-<pane>.json,
# with the same liveness rule mailbox-chat.py applies before it hands mail over.
registered_thread() {
  python3 -I -c '
import json, os, sys, tempfile
path = os.path.join(tempfile.gettempdir(), "agterm-mailbox-chat-%d" % os.getuid(), "codex-%s.json" % sys.argv[1])
try:
    reg = json.load(open(path, encoding="utf-8"))
except (OSError, ValueError):
    sys.exit(0)
if not isinstance(reg, dict):
    sys.exit(0)
pid = reg.get("pid")
if reg.get("session") != sys.argv[2] or not reg.get("thread") or not isinstance(pid, int) or pid <= 1:
    sys.exit(0)
try:
    os.kill(pid, 0)
except ProcessLookupError:
    sys.exit(0)
except PermissionError:
    pass
print(reg["thread"])
' "$1" "$target"
}

read_pane() {
  agtermctl session text --target "$target" --pane right --lines "${1:-40}" ${socket[@]+"${socket[@]}"} 2>/dev/null \
    | sed 's/\x1b\[[0-9;]*m//g'
}

# The last composer line: Codex draws its prompt as "› <text>".
composer_line() {
  grep -E '^[[:space:]]*›' | tail -n 1 | sed -E 's/^[[:space:]]*›[[:space:]]?//'
}

pane="$(read_pane 40)"
if [ -z "$pane" ]; then
  echo "codex-clear: could not read the right pane; is Codex running in the split?" >&2
  exit 2
fi
if ! grep -q "Codex" <<<"$pane"; then
  echo "codex-clear: the right pane does not look like Codex; nothing typed" >&2
  exit 2
fi
if grep -qiE 'esc to interrupt|Working \(' <<<"$pane"; then
  echo "codex-clear: Codex is mid-turn; nothing typed" >&2
  exit 2
fi
if grep -qiE 'queued follow-up|\(y/n\)|\[y/N\]|approve|allow command|trust this' <<<"$pane"; then
  echo "codex-clear: Codex shows a queue or a prompt that needs the user; nothing typed" >&2
  exit 2
fi

composer="$(composer_line <<<"$pane")"
case "$composer" in
  "" | "Ask Codex to do anything") ;;
  *)
    echo "codex-clear: Codex's composer holds text ('$composer'); nothing typed" >&2
    exit 2
    ;;
esac

pane_id="$(right_pane_id)"
if [ -z "$pane_id" ]; then
  echo "codex-clear: could not find the right pane's id in agterm's tree; nothing typed" >&2
  exit 2
fi
old_thread="$(registered_thread "$pane_id")"
if [ -z "$old_thread" ]; then
  echo "codex-clear: no running Codex has registered the right pane for mail (mailbox-chat.py codex-hook); give Codex a prompt, or check its hook is installed and trusted; nothing typed" >&2
  exit 2
fi

if [ -n "$check_only" ]; then
  echo "codex-clear: Codex is idle with an empty composer and registered for mail"
  exit 0
fi

# Step 1: type the command without a newline; a newline in the same write does not submit.
printf '/clear' | agtermctl session type --stdin --target "$target" --pane right ${socket[@]+"${socket[@]}"} >/dev/null

typed=""
for _ in 1 2 3 4 5; do
  sleep 1
  if [ "$(read_pane 20 | composer_line)" = "/clear" ]; then
    typed=yes
    break
  fi
done
if [ -z "$typed" ]; then
  echo "codex-clear: typed '/clear' but the composer does not show it; read the pane" >&2
  exit 1
fi

# Step 2: submit on its own.
printf '\n' | agtermctl session type --stdin --target "$target" --pane right ${socket[@]+"${socket[@]}"} >/dev/null

cleared=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  sleep 1
  if read_pane 15 | grep -q "Context 0% used"; then
    cleared=yes
    break
  fi
done
if [ -z "$cleared" ]; then
  echo "codex-clear: submitted /clear but did not see 'Context 0% used'; read the pane" >&2
  exit 1
fi

# Step 3: a first prompt for the new conversation, so it registers for mail. It carries no topic.
ready="Answer with the single word READY."
printf '%s' "$ready" | agtermctl session type --stdin --target "$target" --pane right ${socket[@]+"${socket[@]}"} >/dev/null

typed=""
for _ in 1 2 3 4 5; do
  sleep 1
  if [ "$(read_pane 20 | composer_line)" = "$ready" ]; then
    typed=yes
    break
  fi
done
if [ -z "$typed" ]; then
  echo "codex-clear: cleared, then typed the READY prompt but the composer does not show it; read the pane" >&2
  exit 1
fi
printf '\n' | agtermctl session type --stdin --target "$target" --pane right ${socket[@]+"${socket[@]}"} >/dev/null

for _ in $(seq 1 60); do
  sleep 1
  new_thread="$(registered_thread "$pane_id")"
  if [ -n "$new_thread" ] && [ "$new_thread" != "$old_thread" ]; then
    echo "codex-clear: Codex context cleared; the new conversation takes mail"
    exit 0
  fi
done
echo "codex-clear: cleared and sent the READY prompt, but no new conversation registered for mail within 60s; mail still goes to the cleared thread; read the pane" >&2
exit 1
