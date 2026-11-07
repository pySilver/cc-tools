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
#
# --model MODEL --reasoning EFFORT also switches the reviewer seat, right after the /clear and
# before the READY prompt: it types "/model MODEL --reasoning=EFFORT" and waits for Codex to
# confirm. A switch survives /clear, so it is typed only when the seat changes. The owner approved
# this line on 2026-11-07, at this boundary only.
#
# --resets reads how many usage-limit resets are left and prints the number. The count is shown
# only on Codex's /usage screen, under "Redeem reset", the same screen that redeems one. So this
# types /usage, then 2, reads the count and leaves with Esc twice: it never sends Enter there,
# because redeeming takes the owner's instruction. Exit codes as above.
set -uo pipefail

check_only=""
read_resets=""
model=""
reasoning=""
while [ $# -gt 0 ]; do
  case "$1" in
    --check) check_only=yes ;;
    --resets) read_resets=yes ;;
    --model) model="${2:-}"; shift ;;
    --reasoning) reasoning="${2:-}"; shift ;;
    *)
      echo "codex-clear: unknown argument '$1'" >&2
      exit 2
      ;;
  esac
  shift
done
if { [ -n "$model" ] && [ -z "$reasoning" ]; } || { [ -z "$model" ] && [ -n "$reasoning" ]; }; then
  echo "codex-clear: --model and --reasoning go together" >&2
  exit 2
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

send() {
  printf '%s' "$1" | agtermctl session type --stdin --target "$target" --pane right ${socket[@]+"${socket[@]}"} >/dev/null
}

# Type a command without a newline, since a newline in the same write does not submit, and
# wait until the composer shows it.
type_command() {
  send "$1"
  for _ in 1 2 3 4 5; do
    sleep 1
    if [ "$(read_pane 20 | composer_line)" = "$1" ]; then
      return 0
    fi
  done
  return 1
}

if [ -n "$read_resets" ]; then
  if ! type_command "/usage"; then
    echo "codex-clear: typed '/usage' but the composer does not show it; read the pane" >&2
    exit 1
  fi
  send $'\n'
  menu=""
  for _ in 1 2 3 4 5 6 7 8; do
    sleep 1
    if read_pane 15 | grep -q "Redeem reset"; then
      menu=yes
      break
    fi
  done
  if [ -z "$menu" ]; then
    echo "codex-clear: /usage did not show 'Redeem reset'; read the pane" >&2
    exit 1
  fi
  send "2"
  count=""
  for _ in 1 2 3 4 5 6 7 8; do
    sleep 1
    screen="$(read_pane 15)"
    # "1 usage limit reset available." or "3 usage limit resets available."
    count="$(grep -oE '[0-9]+ usage limit resets? available' <<<"$screen" | grep -oE '^[0-9]+' | tail -n 1)"
    if [ -z "$count" ] && grep -qiE 'no usage limit resets?' <<<"$screen"; then
      count=0
    fi
    if [ -n "$count" ]; then
      break
    fi
  done
  send $'\e'
  sleep 1
  send $'\e'
  sleep 1
  case "$(read_pane 20 | composer_line)" in
    "" | "Ask Codex to do anything") ;;
    *)
      echo "codex-clear: left the reset screen but the composer is not empty; read the pane" >&2
      exit 1
      ;;
  esac
  if [ -z "$count" ]; then
    echo "codex-clear: the reset screen showed no count; read the pane" >&2
    exit 1
  fi
  echo "$count"
  exit 0
fi

# Step 1: type /clear and see it in the composer.
if ! type_command "/clear"; then
  echo "codex-clear: typed '/clear' but the composer does not show it; read the pane" >&2
  exit 1
fi

# Step 2: submit on its own.
send $'\n'

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

# Step 3, only with --model: switch the seat while the new conversation is still empty.
if [ -n "$model" ]; then
  switch="/model $model --reasoning=$reasoning"
  if ! type_command "$switch"; then
    echo "codex-clear: cleared, then typed '$switch' but the composer does not show it; read the pane" >&2
    exit 1
  fi
  send $'\n'
  switched=""
  for _ in 1 2 3 4 5 6 7 8; do
    sleep 1
    # After a /clear the confirmation sits at the top of a mostly blank screen, so read it all.
    if read_pane 80 | grep -qF "Model changed to $model $reasoning"; then
      switched=yes
      break
    fi
  done
  if [ -z "$switched" ]; then
    echo "codex-clear: cleared and submitted '$switch', but Codex did not confirm the change; read the pane" >&2
    exit 1
  fi
fi

# Step 4: a first prompt for the new conversation, so it registers for mail. It carries no topic.
ready="Answer with the single word READY."
if ! type_command "$ready"; then
  echo "codex-clear: cleared, then typed the READY prompt but the composer does not show it; read the pane" >&2
  exit 1
fi
send $'\n'

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
