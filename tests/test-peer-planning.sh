#!/usr/bin/env bash
# peer-planning exec: the run-record scripts. log-event.py refuses a run.start that a later reader
# cannot use, and run-records.py lists a repository's landed runs, skipping a run whose record it
# cannot read instead of aborting the listing, and codex-clear.sh, against a fake agtermctl, refuses
# a Codex not registered for mail and confirms the new conversation's registration after a clear.
# Everything happens in a throwaway clone; no agterm session is touched.
set -euo pipefail

cd "$(dirname "$0")/.."
SCRIPTS=$PWD/plugins/peer-planning/skills/exec/scripts
# Resolved through pwd -P: run-records.py prints paths as `git worktree list` resolves them, and on
# macOS mktemp answers under /var while git answers under /private/var.
WORK=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
# The real interpreter, resolved before HOME moves: a version-manager shim reads its config from HOME.
# The scripts then run with -E -s, which keeps the machine's PYTHONPATH and user site out; -I would
# also drop the scripts' own directory, where run-records.py imports run_index from. -B leaves no
# __pycache__ in the plugin.
PY=$(python3 -I -c 'import sys; print(sys.executable)')
export HOME="$WORK/home" TMPDIR="$WORK/tmp"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
unset AGT_SOCKET AGTERM_SOCKET AGT_SESSION_PWD AGTERM_SESSION_ID
mkdir -p "$HOME" "$TMPDIR"

fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }
py() { "$PY" -E -s -B "$@"; }

# ---- log-event.py ----
RUN=$WORK/run
mkdir "$RUN"
full=(plan=docs/plans/2026-10-20-plan.md tasks:=3 work_path=/w branch=plan executor=implementer session=S)
if py "$SCRIPTS/log-event.py" "$RUN" run.start "${full[@]}"; then
  pass "log-event accepts a run.start with every field"
else
  fail "log-event accepts a run.start with every field"
fi

set +e
err=$(py "$SCRIPTS/log-event.py" "$RUN" run.start session=S tasks:=3 2>&1)
code=$?
set -e
if [ "$code" != 0 ] && [[ $err == *"needs plan, work_path, branch, executor"* ]]; then
  pass "log-event refuses a run.start without its fields and names them"
else
  fail "log-event refuses a run.start without its fields: exit $code: $err"
fi

set +e
err=$(py "$SCRIPTS/log-event.py" "$RUN" run.start plan=/abs/plan.md "${full[@]:1}" 2>&1)
code=$?
set -e
if [ "$code" != 0 ] && [[ $err == *"path from the repository root"* ]]; then
  pass "log-event refuses an absolute plan path"
else
  fail "log-event refuses an absolute plan path: exit $code: $err"
fi

if [ "$(wc -l < "$RUN/events.jsonl")" -eq 1 ] && [ "$(wc -l < "$RUN/events.js")" -eq 1 ]; then
  pass "a refused record reaches neither events.jsonl nor events.js"
else
  fail "a refused record reaches neither events.jsonl nor events.js: $(cat "$RUN/events.jsonl")"
fi

if py "$SCRIPTS/log-event.py" "$RUN" task.start task:=1 title=t discuss:=false; then
  pass "log-event requires nothing of other events"
else
  fail "log-event requires nothing of other events"
fi

# ---- run-records.py ----
# A remote whose default branch holds the archived plan, cloned so origin/HEAD is set, and three
# runs in the clone: one landed, one still without run.end, and one logged the way the skill's
# setup step once said, run.start without the plan path.
git init -q -b main "$WORK/src"
mkdir -p "$WORK/src/docs/plans/completed"
echo plan > "$WORK/src/docs/plans/completed/2026-10-20-landed.md"
git -C "$WORK/src" add -A
git -C "$WORK/src" commit -qm 'archive the plan'
git clone -q "$WORK/src" "$WORK/clone"
CLONE=$WORK/clone
run() { mkdir -p "$CLONE/.peer-planning/$1"; printf '%s\n' "${@:2}" > "$CLONE/.peer-planning/$1/events.jsonl"; }
start='{"ts": "2026-10-20T16:40:14Z", "event": "run.start", "plan": "docs/plans/2026-10-20-landed.md", "tasks": 2, "work_path": "/w", "branch": "landed", "executor": "implementer", "session": "S"}'
end='{"ts": "2026-10-20T17:00:00Z", "event": "run.end"}'
run landed "$start" "$end"
run open "$start"
run noplan '{"ts": "2026-10-20T16:40:14Z", "event": "run.start", "session": "597105B6-93B3-4EDF-86E7-6B73060F361C", "tasks": 18}' "$end"

set +e
out=$(cd "$CLONE" && py "$SCRIPTS/run-records.py" --landed 2>"$WORK/landed.err")
code=$?
set -e
if [ "$code" = 0 ]; then
  pass "--landed exits 0 with an unreadable run present"
else
  fail "--landed exits 0 with an unreadable run present: exit $code: $(cat "$WORK/landed.err")"
fi
if [ "$(printf '%s\n' "$out" | grep -c .)" -eq 1 ] && [[ $out == "$CLONE/.peer-planning/landed"$'\t'*$'\t2026-10-20-landed.md' ]]; then
  pass "--landed lists the landed run alone"
else
  fail "--landed lists the landed run alone: $out"
fi
if grep -q '\.peer-planning/noplan: its run.start names no repository-relative plan' "$WORK/landed.err"; then
  pass "--landed names the unreadable run on stderr"
else
  fail "--landed names the unreadable run on stderr: $(cat "$WORK/landed.err")"
fi

set +e
(cd "$CLONE" && py "$SCRIPTS/run-records.py" --remove "$CLONE/.peer-planning/noplan") >/dev/null 2>&1
code=$?
set -e
if [ "$code" != 0 ] && [ -d "$CLONE/.peer-planning/noplan" ]; then
  pass "--remove refuses the unreadable run"
else
  fail "--remove refuses the unreadable run: exit $code"
fi

if out=$(cd "$CLONE" && py "$SCRIPTS/run-records.py" --remove "$CLONE/.peer-planning/landed" 2>&1) && [ ! -d "$CLONE/.peer-planning/landed" ]; then
  pass "--remove deletes the landed run"
else
  fail "--remove deletes the landed run: $out"
fi

# ---- codex-clear.sh ----
# A fake agtermctl stands in for agterm: it serves a tree with a right pane, a Codex pane whose
# composer holds what was typed since the last newline, and it records every write. A submitted
# READY prompt re-registers the pane under a new thread, as mailbox-chat.py's codex-hook would.
FAKE=$WORK/fake-bin
mkdir -p "$FAKE"
ln -s "$PY" "$FAKE/python3"
CC=$WORK/codex-clear
mkdir -p "$CC"
cat >"$FAKE/agtermctl" <<'FAKECTL'
#!/usr/bin/env bash
set -euo pipefail
state=$FAKE_STATE
case "$1 ${2:-}" in
  "tree --json")
    printf '{"windows":[{"sessions":[{"id":"%s","surfaces":[{"kind":"left","paneID":"PANE-L"},{"kind":"right","paneID":"PANE-R"}]}]}]}\n' "$AGTERM_SESSION_ID"
    ;;
  "session text")
    printf 'OpenAI Codex\n'
    if [ -f "$state/cleared" ]; then printf 'Context 0%% used\n'; fi
    printf '› %s\n' "$(cat "$state/composer" 2>/dev/null || true)"
    ;;
  "session type")
    input=$(cat; printf x)
    input=${input%x}
    printf '%s\0' "$input" >>"$state/typed"
    if [ "$input" = $'\n' ]; then
      submitted=$(cat "$state/composer" 2>/dev/null || true)
      : >"$state/composer"
      if [ "$submitted" = /clear ]; then touch "$state/cleared"; fi
      if [ "$submitted" = "Answer with the single word READY." ] && [ -n "${FAKE_REREGISTER:-}" ]; then
        printf '{"session":"%s","thread":"thread-new","pid":%s}' "$AGTERM_SESSION_ID" "$FAKE_PID" >"$FAKE_REG"
      fi
    else
      printf '%s' "$input" >>"$state/composer"
    fi
    ;;
  *) echo "fake agtermctl: unexpected $*" >&2; exit 64 ;;
esac
FAKECTL
chmod +x "$FAKE/agtermctl"

REGDIR=$TMPDIR/agterm-mailbox-chat-$(id -u)
REG=$REGDIR/codex-PANE-R.json
mkdir -p "$REGDIR"
register() { printf '{"session":"S-1","thread":"%s","pid":%s}' "$1" "$2" >"$REG"; }
codex_clear() {
  rm -rf "$CC/state" && mkdir -p "$CC/state"
  set +e
  out=$(PATH="$FAKE:$PATH" AGTERM_SESSION_ID=S-1 FAKE_STATE="$CC/state" FAKE_REG="$REG" FAKE_PID=$$ \
    bash "$SCRIPTS/codex-clear.sh" "$@" 2>&1)
  code=$?
  set -e
}
typed() { tr '\0' '|' <"$CC/state/typed" 2>/dev/null | sed 's/\n/\\n/g'; }

rm -f "$REG"
codex_clear --check
if [ "$code" = 2 ] && [[ $out == *"no running Codex has registered"* ]] && [ ! -f "$CC/state/typed" ]; then
  pass "codex-clear --check refuses a Codex not registered for mail, typing nothing"
else
  fail "codex-clear --check refuses a Codex not registered for mail: exit $code: $out"
fi

dead=$("$PY" -c 'import subprocess; p = subprocess.Popen(["true"]); p.wait(); print(p.pid)')
register thread-old "$dead"
codex_clear --check
if [ "$code" = 2 ] && [[ $out == *"no running Codex has registered"* ]]; then
  pass "codex-clear --check ignores a registration whose Codex has exited"
else
  fail "codex-clear --check ignores a registration whose Codex has exited: exit $code: $out"
fi

register thread-old $$
codex_clear --check
if [ "$code" = 0 ] && [ ! -f "$CC/state/typed" ]; then
  pass "codex-clear --check passes an idle, registered Codex without typing"
else
  fail "codex-clear --check passes an idle, registered Codex: exit $code: $out"
fi

register thread-old $$
FAKE_REREGISTER=1 codex_clear
expected=$'/clear|\n|Answer with the single word READY.|\n|'
if [ "$code" = 0 ] && [ "$(tr '\0' '|' <"$CC/state/typed")" = "$expected" ] && grep -q thread-new "$REG"; then
  pass "codex-clear types /clear and a READY prompt, and returns once a new thread registers"
else
  fail "codex-clear clears and re-registers: exit $code: $out; typed: $(typed)"
fi

if [ -d "$SCRIPTS/__pycache__" ]; then
  fail "the scripts left no __pycache__ in the plugin"
else
  pass "the scripts left no __pycache__ in the plugin"
fi

[ "$fails" -eq 0 ] || { printf '%d failure(s)\n' "$fails"; exit 1; }
