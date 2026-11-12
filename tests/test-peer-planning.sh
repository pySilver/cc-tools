#!/usr/bin/env bash
# peer-planning exec: the run-record scripts. log-event.py refuses a run.start that a later reader
# cannot use, and run-records.py lists a repository's landed runs, skipping a run whose record it
# cannot read instead of aborting the listing and keeping a run's events.jsonl and progress.md in
# the workflow ledger before it removes the run, and codex-clear.sh, against a fake agtermctl, refuses
# a Codex not registered for mail, confirms the new conversation's registration after a clear and
# returns only once the READY turn has ended. reviewer-seat.py takes make's or exec's seat from
# models.toml, re-applies a seat other than Codex's configured default at every clear without calling
# it a switch, and holds a model the owner kept. model-check.py compares the session, the agent
# definitions and Codex's pane with models.toml.
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

# The ledger is the clone's git directory. A file where its runs/ directory belongs makes the copy
# fail, and then nothing may be removed.
LEDGER=$CLONE/.git/workflow-ledger
printf 'progress\n' >"$CLONE/.peer-planning/landed/progress.md"
mkdir -p "$CLONE/.peer-planning/landed/msgs" && printf 'm\n' >"$CLONE/.peer-planning/landed/msgs/001-codex-plan.md"
mkdir -p "$LEDGER" && : >"$LEDGER/runs"
set +e
err=$(cd "$CLONE" && py "$SCRIPTS/run-records.py" --remove "$CLONE/.peer-planning/landed" 2>&1)
code=$?
set -e
if [ "$code" != 0 ] && [[ $err == *"could not keep"*"nothing was removed"* ]] && [ -f "$CLONE/.peer-planning/landed/events.jsonl" ]; then
  pass "--remove refuses to remove a run it could not keep in the ledger"
else
  fail "--remove refuses to remove a run it could not keep in the ledger: exit $code: $err"
fi
rm "$LEDGER/runs"

if out=$(cd "$CLONE" && py "$SCRIPTS/run-records.py" --remove "$CLONE/.peer-planning/landed" 2>&1) && [ ! -d "$CLONE/.peer-planning/landed" ]; then
  pass "--remove deletes the landed run"
else
  fail "--remove deletes the landed run: $out"
fi
if [ "$(cat "$LEDGER/runs/landed/events.jsonl")" = "$start"$'\n'"$end" ] \
  && [ "$(cat "$LEDGER/runs/landed/progress.md")" = progress ] \
  && [ "$(cd "$LEDGER/runs/landed" && find . -mindepth 1 | sort | tr '\n' ' ')" = "./events.jsonl ./progress.md " ] \
  && [[ $out == *"kept events.jsonl, progress.md in $LEDGER/runs/landed"* ]]; then
  pass "--remove first keeps events.jsonl and progress.md, and nothing else, in the ledger"
else
  fail "--remove keeps the run's analysis files in the ledger: $out; $(find "$LEDGER" | sort)"
fi

# ---- codex-clear.sh ----
# A fake agtermctl stands in for agterm: it serves a tree with a right pane, a Codex pane whose
# composer holds what was typed since the last newline, and it records every write. A submitted
# READY prompt re-registers the pane under a new thread, as mailbox-chat.py's codex-hook would, and
# with FAKE_BUSY=N the pane then reads as mid-turn for N more reads. A submitted /model line shows
# Codex's confirmation, and FAKE_STATUS is the status line the pane shows.
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
    if [ -f "$state/model" ]; then printf 'Model changed to %s\n' "$(cat "$state/model")"; fi
    if [ -f "$state/cleared" ]; then printf 'Context 0%% used\n'; fi
    busy=$(cat "$state/busy" 2>/dev/null || echo 0)
    if [ "$busy" -gt 0 ]; then
      printf '• Working (3s • esc to interrupt)\n'
      echo $((busy - 1)) >"$state/busy"
    fi
    printf '› %s\n' "$(cat "$state/composer" 2>/dev/null || true)"
    if [ -n "${FAKE_STATUS:-}" ]; then printf '  %s\n' "$FAKE_STATUS"; fi
    ;;
  "session type")
    input=$(cat; printf x)
    input=${input%x}
    printf '%s\0' "$input" >>"$state/typed"
    if [ "$input" = $'\n' ]; then
      submitted=$(cat "$state/composer" 2>/dev/null || true)
      : >"$state/composer"
      if [ "$submitted" = /clear ]; then touch "$state/cleared"; fi
      case "$submitted" in
        "/model "*)
          set -- $submitted
          printf '%s %s' "$2" "${3#--reasoning=}" >"$state/model"
          ;;
      esac
      if [ "$submitted" = "Answer with the single word READY." ] && [ -n "${FAKE_REREGISTER:-}" ]; then
        printf '{"session":"%s","thread":"thread-new","pid":%s}' "$AGTERM_SESSION_ID" "$FAKE_PID" >"$FAKE_REG"
        echo "${FAKE_BUSY:-0}" >"$state/busy"
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

register thread-old $$
FAKE_REREGISTER=1 FAKE_BUSY=3 codex_clear
if [ "$code" = 0 ] && [ "$(cat "$CC/state/busy")" = 0 ]; then
  pass "codex-clear returns only once Codex has finished answering the READY prompt"
else
  fail "codex-clear waits out the READY turn: exit $code: $out; busy left: $(cat "$CC/state/busy" 2>/dev/null)"
fi

register thread-old $$
FAKE_REREGISTER=1 codex_clear --model gpt-6.1-sol --reasoning xhigh
expected=$'/clear|\n|/model gpt-6.1-sol --reasoning=xhigh|\n|Answer with the single word READY.|\n|'
if [ "$code" = 0 ] && [ "$(tr '\0' '|' <"$CC/state/typed")" = "$expected" ]; then
  pass "codex-clear --model types the switch between /clear and READY and waits for its confirmation"
else
  fail "codex-clear --model switches the seat: exit $code: $out; typed: $(typed)"
fi

set +e
code_out=$(bash "$SCRIPTS/codex-clear.sh" --model gpt-6.1-sol 2>&1)
code=$?
set -e
if [ "$code" = 2 ]; then
  pass "codex-clear refuses --model without --reasoning, typing nothing"
else
  fail "codex-clear refuses --model without --reasoning with exit 2: exit $code: $code_out"
fi

# ---- reviewer-seat.py ----
# A fake CODEX_HOME holds config.toml, the model a cleared Codex starts on.
seat_home=$WORK/codex-home
mkdir -p "$seat_home"
seat() {
  CODEX_HOME=$seat_home py "$SCRIPTS/reviewer-seat.py" "$@" \
    | "$PY" -I -c 'import json,sys; d=json.load(sys.stdin); print(d["seat"], d["model"], d["effort"])'
}
check_seat() {
  local want=$1 label=$2 got
  shift 2
  got=$(seat "$@" 2>&1) || true
  if [ "$got" = "$want" ]; then pass "reviewer-seat: $label"; else fail "reviewer-seat: $label: got '$got'"; fi
}
check_seat "codex gpt-6.1-sol xhigh" "make's seat is Sol at xhigh" make
check_seat "codex gpt-6.1-sol high" "exec's seat is Sol at high" exec
check_seat "opus opus high" "with Codex down, the seat is an Opus subagent" exec --codex-down "no answer"
for bad in "" "plan" "--keep"; do
  if CODEX_HOME=$seat_home py "$SCRIPTS/reviewer-seat.py" ${bad:+"$bad"} >/dev/null 2>&1; then
    fail "reviewer-seat refuses a first argument other than make or exec: '$bad'"
  else
    pass "reviewer-seat refuses a first argument other than make or exec: '$bad'"
  fi
done
# The clear after a switch: the pane runs the seat, and a /clear would return it to config.toml's
# default. The pane's status line comes from the fake agtermctl.
printf 'model = "gpt-6-astra"\nmodel_reasoning_effort = "high"\n' >"$seat_home/config.toml"
seat_clear() {
  local status=$1
  shift
  mkdir -p "$CC/state"
  PATH="$FAKE:$PATH" AGTERM_SESSION_ID=S-1 FAKE_STATE="$CC/state" FAKE_STATUS="$status" \
    CODEX_HOME=$seat_home py "$SCRIPTS/reviewer-seat.py" "$@" \
    | "$PY" -I -c 'import json,sys; d=json.load(sys.stdin); print(d["switch"], "|" + d["clear_flags"] + "|")'
}
check_clear() {
  local want=$1 label=$2 got
  shift 2
  got=$(seat_clear "$@" 2>&1) || true
  if [ "$got" = "$want" ]; then pass "reviewer-seat: $label"; else fail "reviewer-seat: $label: got '$got'"; fi
}
sol_xhigh_status="GPT-6.1-Sol xhigh · ~/p · Context 2% used · weekly 12% left"
sol_high_status="GPT-6.1-Sol high · ~/p · Context 2% used · weekly 12% left"
astra_status="GPT-6-Astra high · ~/p · Context 2% used · weekly 48% left"
check_clear "True |--model gpt-6.1-sol --reasoning high|" \
  "a pane on the configured Astra moving to exec's seat is a switch, and the clear carries it" \
  "$astra_status" exec
check_clear "True |--model gpt-6.1-sol --reasoning high|" \
  "a pane left on make's seat moves to exec's seat at exec's setup clear" "$sol_xhigh_status" exec
check_clear "False |--model gpt-6.1-sol --reasoning high|" \
  "a pane already on exec's seat is no switch, but every clear still re-applies it" "$sol_high_status" exec
check_clear "False |--model gpt-6.1-sol --reasoning xhigh|" \
  "a pane already on make's seat is no switch" "$sol_xhigh_status" make
check_clear "False ||" "the Opus seat carries nothing to a clear" "$astra_status" exec --codex-down "no answer"
printf 'model = "gpt-6.1-sol"\nmodel_reasoning_effort = "high"\n' >"$seat_home/config.toml"
check_clear "False ||" "exec's seat on a pane whose default is that seat needs a plain clear" "$sol_high_status" exec
rm "$seat_home/config.toml"
check_clear "False |--model gpt-6.1-sol --reasoning high|" \
  "with no configured default, every clear carries the seat" "$sol_high_status" exec
printf 'model = \n' >"$seat_home/config.toml"
set +e
toml_out=$(PATH="$FAKE:$PATH" AGTERM_SESSION_ID=S-1 FAKE_STATE="$CC/state" FAKE_STATUS="$astra_status" \
  CODEX_HOME=$seat_home py "$SCRIPTS/reviewer-seat.py" exec 2>&1)
code=$?
set -e
if [ "$code" = 1 ] && [[ $toml_out == *"is not valid TOML"* ]]; then
  pass "reviewer-seat fails loudly on a config.toml that is not TOML"
else
  fail "reviewer-seat fails loudly on a config.toml that is not TOML: exit $code: $toml_out"
fi
rm "$seat_home/config.toml"

check_seat "kept gpt-6-astra high" "a model the owner kept holds the seat" exec --keep "gpt-6-astra high"
check_seat "opus opus high" "Codex down replaces a kept model with the Opus seat" \
  exec --keep "gpt-6-astra high" --codex-down "no answer"
for bad in "gpt-6.1-sol" "unknown unknown"; do
  if CODEX_HOME=$seat_home py "$SCRIPTS/reviewer-seat.py" exec --keep "$bad" >/dev/null 2>&1; then
    fail "reviewer-seat refuses --keep '$bad'"
  else
    pass "reviewer-seat refuses --keep '$bad'"
  fi
done
printf 'model = "gpt-6-astra"\nmodel_reasoning_effort = "high"\n' >"$seat_home/config.toml"
check_clear "False ||" "a kept model that is the configured default needs a plain clear" \
  "$astra_status" exec --keep "gpt-6-astra high"
check_clear "False |--model gpt-6.1-sol --reasoning xhigh|" \
  "a kept model on its pane is no switch, and every clear puts it back" \
  "$sol_xhigh_status" exec --keep "gpt-6.1-sol xhigh"

# ---- model-check.py ----
# A fake config dir holds this session's transcript and the agent definitions; the project has
# none of its own, so the definitions come from the config dir.
MC=$WORK/model-check
mkdir -p "$MC/config/projects/-p" "$MC/config/agents" "$MC/project"
transcript() {
  : >"$MC/config/projects/-p/S-MC.jsonl"
  for entry in "$@"; do printf '%s\n' "$entry" >>"$MC/config/projects/-p/S-MC.jsonl"; done
}
printf -- '---\nname: implementer\nmodel: opus\neffort: high\n---\nbody\n' >"$MC/config/agents/implementer.md"
printf -- '---\nname: closer\nmodel: opus\n---\nbody\n' >"$MC/config/agents/closer.md"
check_model() {
  local want=$1 label=$2 got
  shift 2
  got=$(CLAUDE_CONFIG_DIR=$MC/config CLAUDE_CODE_SESSION_ID=S-MC \
    py "$PWD/plugins/peer-planning/scripts/model-check.py" "$@" --project "$MC/project" 2>&1 \
    | "$PY" -I -c 'import json,sys; d=json.load(sys.stdin); print(d["differs"], *[r["row"] + "=" + r["current"] + ("" if r["matches"] else "!") for r in d["rows"]])' 2>&1) || true
  if [ "$got" = "$want" ]; then pass "model-check: $label"; else fail "model-check: $label: got '$got'"; fi
}
opus='{"type":"assistant","effort":"high","message":{"model":"claude-opus-5-5"}}'
fable='{"type":"assistant","effort":"high","message":{"model":"claude-fable-5-2"}}'
synthetic='{"type":"assistant","message":{"model":"<synthetic>"}}'
transcript "$fable" "$opus" "$synthetic"
check_model "False session=claude-opus-5-5 high executor/implementer=opus high" \
  "the newest real assistant message gives the session's model, past a synthetic one" \
  exec --agent executor=implementer
transcript "$opus" "$fable"
check_model "True session=claude-fable-5-2 high!" "Fable as exec's orchestrator differs" exec
check_model "False session=claude-fable-5-2 high" "Fable as make's planner matches" make
printf 'notes\nMODEL ACCEPTED session claude-fable-5-2 high\n' >"$MC/progress.md"
check_model "False session=claude-fable-5-2 high" "a value the owner accepted for the run matches" \
  exec --accepted "$MC/progress.md"
transcript "$opus"
check_model "True session=claude-opus-5-5 high closer/closer=opus unset!" \
  "a definition with no effort line differs" exec --agent closer=closer
mkdir -p "$MC/project/.claude/agents"
printf -- '---\nname: closer\nmodel: sonnet\neffort: high\n---\n' >"$MC/project/.claude/agents/closer.md"
check_model "True session=claude-opus-5-5 high closer/closer=sonnet high!" \
  "the project's definition comes before the user's" exec --agent closer=closer
check_model "True session=claude-opus-5-5 high executor/worker=unknown unknown!" \
  "a definition that exists nowhere is a row that differs, not an exit" exec --agent executor=worker
printf '%s' '{"seat":"codex","model":"gpt-6.1-sol","effort":"high","reason":"the exec seat in models.toml","pane_model":"gpt-6-astra high"}' >"$MC/seat.json"
check_model "True session=claude-opus-5-5 high codex=gpt-6-astra high!" \
  "a pane on another model than the seat differs" exec --seat "$MC/seat.json"
# shellcheck disable=SC2016 # the backticks are the text under test
printf -- '- `MODEL ACCEPTED codex gpt-6-astra high`\n' >"$MC/progress-codex.md"
check_model "False session=claude-opus-5-5 high codex=gpt-6-astra high" \
  "a pane model the owner kept, written as a list item in backticks, matches" \
  exec --seat "$MC/seat.json" --accepted "$MC/progress-codex.md"
printf '%s' '{"seat":"codex","model":"gpt-6.1-sol","effort":"high","reason":"the exec seat in models.toml","pane_model":""}' >"$MC/blind.json"
check_model "True session=claude-opus-5-5 high codex=unknown unknown!" \
  "a pane whose status line was not read differs as unknown" exec --seat "$MC/blind.json"
transcript "$fable"
printf '%s' '{"seat":"codex","model":"gpt-6.1-sol","effort":"xhigh","reason":"the make seat in models.toml","pane_model":"gpt-6.1-sol xhigh"}' >"$MC/make-seat.json"
check_model "False session=claude-fable-5-2 high codex=gpt-6.1-sol xhigh" \
  "a pane on make's seat matches in make" make --seat "$MC/make-seat.json"
transcript "$opus"
# The picker's own output for a kept model, apostrophes and all, goes through the file unharmed.
CODEX_HOME=$seat_home py "$SCRIPTS/reviewer-seat.py" exec --keep "gpt-6.1-sol xhigh" >"$MC/kept.json"
check_model "True session=claude-opus-5-5 high codex=unknown unknown!" \
  "the picker's kept-seat JSON reads from its file" exec --seat "$MC/kept.json"
printf '%s' '{"seat":"kept","model":"gpt-6.1-sol","effort":"xhigh","reason":"kept","pane_model":"gpt-6.1-sol xhigh"}' >"$MC/kept-pane.json"
check_model "False session=claude-opus-5-5 high codex=gpt-6.1-sol xhigh" \
  "a pane on the model the owner kept matches" exec --seat "$MC/kept-pane.json"
printf '%s' '{"seat":"opus","model":"opus","effort":"high"}' >"$MC/opus.json"
check_model "False session=claude-opus-5-5 high" "the Opus seat has no pane row" exec --seat "$MC/opus.json"
printf -- '---\nname: builder\neffort: high\n---\n' >"$MC/config/agents/some-file.md"
check_model "True session=claude-opus-5-5 high executor/builder=inherit high!" \
  "a definition is found by its name line, and one with no model line differs" exec --agent executor=builder
for bad in "exec --agent executor" "exec --seat" "exec --agent nosuchrole=implementer" "exec --seat $MC/progress.md" "plan"; do
  # shellcheck disable=SC2086 # each case is a word list on purpose
  if CLAUDE_CONFIG_DIR=$MC/config CLAUDE_CODE_SESSION_ID=S-MC \
    py "$PWD/plugins/peer-planning/scripts/model-check.py" $bad >/dev/null 2>&1; then
    fail "model-check refuses '$bad' with exit 1"
  else
    pass "model-check refuses '$bad' with exit 1"
  fi
done
got=$(CLAUDE_CONFIG_DIR=$MC/config CLAUDE_CODE_SESSION_ID=S-MISSING \
  py "$PWD/plugins/peer-planning/scripts/model-check.py" make --project "$MC/project" 2>&1 \
  | "$PY" -I -c 'import json,sys; r=json.load(sys.stdin)["rows"][0]; print(r["current"], "|", r["note"])' 2>&1) || true
if [[ $got == "unknown unknown | no transcript for session S-MISSING"* ]]; then
  pass "model-check: a session with no transcript is unknown, with the reason"
else
  fail "model-check: a session with no transcript is unknown: got '$got'"
fi

# ---- branch-overlap.py ----
# A bare origin, a main clone, and two plan worktrees that both change shared.txt. Commit dates
# are set so plan-a starts before plan-b, which makes plan-b the later plan.
OV=$WORK/overlap
mkdir -p "$OV"
git init -q --bare -b master "$OV/origin.git"
git clone -q "$OV/origin.git" "$OV/main" 2>/dev/null
commit_at() { GIT_AUTHOR_DATE=$1 GIT_COMMITTER_DATE=$1 git -C "$2" commit -qam "$3"; }
printf 'one\n' >"$OV/main/shared.txt"
printf 'base\n' >"$OV/main/other.txt"
git -C "$OV/main" add . && commit_at 2026-11-01T10:00:00 "$OV/main" base
git -C "$OV/main" push -q origin master
git -C "$OV/main" remote set-head origin master
git -C "$OV/main" worktree add -q -b plan-a "$OV/a" origin/master
git -C "$OV/main" worktree add -q -b plan-b "$OV/b" origin/master
printf 'one\na\n' >"$OV/a/shared.txt" && commit_at 2026-11-02T10:00:00 "$OV/a" "plan a"
printf 'one\nb\n' >"$OV/b/shared.txt" && commit_at 2026-11-03T10:00:00 "$OV/b" "plan b"
overlap() { py "$SCRIPTS/branch-overlap.py" "$@"; }
field() { "$PY" -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1"; }

got=$(overlap "$OV/b" | field '[(o["branch"], o["later"], o["files"]) for o in d["overlaps"]]')
if [ "$got" = "[('plan-a', 'this', ['shared.txt'])]" ]; then
  pass "branch-overlap finds the other open plan changing the same file, and calls this one later"
else
  fail "branch-overlap finds the shared file and the later plan: $got"
fi
got=$(overlap "$OV/a" --paths other.txt | field '[(o["branch"], o["later"]) for o in d["overlaps"]]')
if [ "$got" = "[('plan-b', 'plan-b')]" ]; then
  pass "from the earlier plan, the other branch is the later one"
else
  fail "from the earlier plan, the other branch is the later one: $got"
fi

printf 'base\nmoved\n' >"$OV/main/other.txt" && commit_at 2026-11-04T10:00:00 "$OV/main" "master moves"
git -C "$OV/main" push -q origin master
got=$(overlap "$OV/a" --rebase | field '(d["rebased"], d["behind"])')
if [ "$got" = "(True, 0)" ] && git -C "$OV/a" merge-base --is-ancestor origin/master HEAD; then
  pass "branch-overlap --rebase brings a clean branch up to the default branch"
else
  fail "branch-overlap --rebase on a clean branch: $got"
fi

printf 'one\nmaster\n' >"$OV/main/shared.txt" && commit_at 2026-11-05T10:00:00 "$OV/main" "master edits shared"
git -C "$OV/main" push -q origin master
got=$(overlap "$OV/b" --rebase | field '(d["rebased"], d["conflicts"])')
if [ "$got" = "('conflict', ['shared.txt'])" ] && [ -z "$(git -C "$OV/b" status --porcelain)" ] \
  && ! [ -d "$(git -C "$OV/b" rev-parse --git-path rebase-merge)" ]; then
  pass "a conflicting rebase is aborted and reported, leaving the branch as it was"
else
  fail "a conflicting rebase is aborted and reported: $got"
fi

if [ -d "$SCRIPTS/__pycache__" ]; then
  fail "the scripts left no __pycache__ in the plugin"
else
  pass "the scripts left no __pycache__ in the plugin"
fi

[ "$fails" -eq 0 ] || { printf '%d failure(s)\n' "$fails"; exit 1; }
