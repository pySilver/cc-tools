#!/usr/bin/env bash
# Reset Codex's context in the right-hand agterm pane between tasks.
#
# This is the one raw send peer-planning:exec makes into Codex's pane; every message goes
# through peer-chat.py, which prefixes "Chat from Claude:" and so cannot deliver a
# slash command. The owner approved this raw /clear. It refuses unless Codex is idle
# with an empty composer, because a /clear during a turn discards Codex's work.
#
# Exit 0: cleared and verified. Exit 2: refused, nothing typed.
# Exit 1: typed, but the reset could not be confirmed; read the pane before continuing.
# --check runs every refusal check and exits 0 without typing, so setup can confirm Codex is idle.
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

if [ -n "$check_only" ]; then
  echo "codex-clear: Codex is idle with an empty composer"
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

for _ in 1 2 3 4 5 6 7 8 9 10; do
  sleep 1
  if read_pane 15 | grep -q "Context 0% used"; then
    echo "codex-clear: Codex context cleared"
    exit 0
  fi
done
echo "codex-clear: submitted /clear but did not see 'Context 0% used'; read the pane" >&2
exit 1
