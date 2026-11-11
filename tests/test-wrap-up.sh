#!/usr/bin/env bash
# Tests for git/wrap-up's offload-mirror.py, the cleanup of a worktree's mirror on mybaze's
# second test machine. ssh and docker are fakes on PATH: the fake ssh runs the remote script
# locally under a throwaway HOME, and the fake docker keeps the database list in a file.
# Then keep-records.py, the copy into the workflow ledger that comes before any removal, over a
# throwaway repository and worktree.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/plugins/git/skills/wrap-up/scripts/offload-mirror.py"
PYTHON=$(command -v python3)
WORK=$(cd "$(mktemp -d)" && pwd -P)
SLEEPER=""
cleanup() {
  if [ -n "$SLEEPER" ]; then kill "$SLEEPER" 2>/dev/null || true; fi
  rm -rf "$WORK"
}
trap cleanup EXIT

fail() { printf 'FAIL %s\n' "$1"; exit 1; }
ok() { printf 'ok   %s\n' "$1"; }
field() { "$PYTHON" -c 'import json,sys; v=json.load(sys.stdin)[sys.argv[1]]; print(v if isinstance(v,str) else json.dumps(v))' "$1"; }

# The worktree name and remote name of a real mirror, computed by mybaze's own code.
NAME=mybaze_a_full_suite_runs_on_the_pc_while_df507c91bb96
REMOTE=mybaze_offload_9a6c9c2578bf

BIN="$WORK/bin"; mkdir -p "$BIN" "$WORK/home"
DBFILE="$WORK/dbs"
export FAKE_HOME="$WORK/home" DBFILE

cat > "$BIN/docker" <<'EOF'
#!/usr/bin/env bash
# docker exec mybaze.postgres-test psql ... | dropdb ... NAME
[ "$1" = exec ] && [ "$2" = mybaze.postgres-test ] || { echo "unexpected docker call: $*" >&2; exit 9; }
case "$3" in
  psql) cat "$DBFILE" ;;
  dropdb) db="${!#}"; grep -vx -- "$db" "$DBFILE" > "$DBFILE.new" || true; mv "$DBFILE.new" "$DBFILE" ;;
  *) exit 9 ;;
esac
EOF

write_ssh() {
  cat > "$BIN/ssh" <<EOF
#!/usr/bin/env bash
$1
EOF
  chmod +x "$BIN/ssh" "$BIN/docker"
}

# The working fake: run the "bash -lc SCRIPT" argument locally, without a login shell, so the
# fake docker stays first on PATH.
# shellcheck disable=SC2016  # expands inside the fake ssh, not here
LOCAL_SSH='last="${!#}"; eval "set -- $last"; HOME="$FAKE_HOME" exec bash -c "$3"'

run() { PATH="$BIN:$PATH" "$PYTHON" "$SCRIPT" "$@"; }

# 1. The remote name matches mybaze's remote_name for a real worktree, with or without test_.
write_ssh "$LOCAL_SSH"
out=$(MYBAZE_SUITE_REMOTE='' run inspect "$NAME")
[ "$(field remote_name <<<"$out")" = "$REMOTE" ] || fail "remote name: $out"
out=$(MYBAZE_SUITE_REMOTE='' run inspect "test_$NAME")
[ "$(field remote_name <<<"$out")" = "$REMOTE" ] || fail "remote name with test_: $out"
ok "remote name matches mybaze's offload.remote_name"

# 2. Unset or empty: skipped, and ssh is never called.
write_ssh 'echo called > "'"$WORK"'/ssh-called"; exit 1'
out=$(env -u MYBAZE_SUITE_REMOTE PATH="$BIN:$PATH" "$PYTHON" "$SCRIPT" inspect "$NAME")
[ "$(field status <<<"$out")" = skipped ] || fail "unset: $out"
out=$(MYBAZE_SUITE_REMOTE=" " run remove "$NAME")
[ "$(field status <<<"$out")" = skipped ] || fail "empty: $out"
[ ! -e "$WORK/ssh-called" ] || fail "ssh was called while the variable was unset"
ok "unset or empty MYBAZE_SUITE_REMOTE skips without contacting anything"

# 3. A login that prints a browser check URL and waits ends at the timeout, unopened.
write_ssh 'echo "To authenticate, visit: https://login.tailscale.com/a/abc123" >&2; sleep 30'
start=$(date +%s)
out=$(MYBAZE_SUITE_REMOTE=pc run inspect "$NAME" --timeout 2)
[ $(( $(date +%s) - start )) -lt 10 ] || fail "browser check was not bounded"
[ "$(field status <<<"$out")" = unreachable ] || fail "browser check: $out"
grep -q 'browser login check' <<<"$out" || fail "browser check detail: $out"
grep -q 'login.tailscale.com' <<<"$out" && fail "the URL leaked into the result: $out"
ok "a browser login check is bounded, reported, and its URL not passed on"

# 4. ssh failing on its own is unreachable.
write_ssh 'echo "ssh: connect to host pc port 22: Connection refused" >&2; exit 255'
out=$(MYBAZE_SUITE_REMOTE=pc run remove "$NAME")
[ "$(field status <<<"$out")" = unreachable ] || fail "ssh 255: $out"
ok "an ssh failure is unreachable"

# 5. inspect lists the mirror and exactly its databases; remove drops only those.
write_ssh "$LOCAL_SSH"
MIRROR="$FAKE_HOME/mybaze-offload/$REMOTE"; mkdir -p "$MIRROR/sub" "$FAKE_HOME/mybaze-offload/mybaze_offload_000000000000"
printf '%s\n' postgres "test_$REMOTE" "test_${REMOTE}_gw0" "test_${REMOTE}_gw7" \
  "test_${REMOTE}_gwx" "test_${REMOTE}2" test_mybaze_offload_000000000000 > "$DBFILE"
out=$(MYBAZE_SUITE_REMOTE=pc run inspect "$NAME")
[ "$(field status <<<"$out")" = present ] || fail "inspect: $out"
[ "$(field databases <<<"$out")" = "[\"test_$REMOTE\", \"test_${REMOTE}_gw0\", \"test_${REMOTE}_gw7\"]" ] || fail "inspect databases: $out"
ok "inspect finds the mirror and exactly its databases"

# 6. A pytest whose working directory is in the mirror makes both commands touch nothing.
(cd "$MIRROR/sub" && exec -a pytest sleep 30) &
SLEEPER=$!
sleep 0.5
out=$(MYBAZE_SUITE_REMOTE=pc run remove "$NAME")
[ "$(field status <<<"$out")" = busy ] || fail "busy: $out"
if [ ! -d "$MIRROR" ] || ! grep -qx "test_$REMOTE" "$DBFILE"; then fail "a busy mirror was touched"; fi
kill "$SLEEPER"; wait "$SLEEPER" 2>/dev/null || true; SLEEPER=""
ok "a live run in the mirror leaves everything in place"

out=$(MYBAZE_SUITE_REMOTE=pc run remove "$NAME")
[ "$(field status <<<"$out")" = removed ] || fail "remove: $out"
[ "$(field dropped <<<"$out")" = "[\"test_$REMOTE\", \"test_${REMOTE}_gw0\", \"test_${REMOTE}_gw7\"]" ] || fail "dropped: $out"
[ ! -e "$MIRROR" ] || fail "mirror still there"
[ -d "$FAKE_HOME/mybaze-offload/mybaze_offload_000000000000" ] || fail "another mirror was removed"
[ "$(tr '\n' ' ' < "$DBFILE")" = "postgres test_${REMOTE}_gwx test_${REMOTE}2 test_mybaze_offload_000000000000 " ] || fail "wrong databases left: $(cat "$DBFILE")"
ok "remove deletes the mirror and drops only its databases"

out=$(MYBAZE_SUITE_REMOTE=pc run inspect "$NAME")
[ "$(field status <<<"$out")" = absent ] || fail "after remove: $out"
ok "inspect reports absent afterwards"

# ---- keep-records.py ----
# A throwaway repository with a worktree for branch feat/a. MAIN holds make's msgs/ for the plan
# and three revmux tasks of the branch, matched by its slug, by task.md's branch: and by
# plan-<NAME>; WORKTREE holds the exec run record and two tasks, one of them the same task as MAIN's
# with an identical 01-initial and a different 02-after-fix. Every round carries an agents/ log
# and an input/ file that must not be kept.
KEEP="$ROOT/plugins/git/skills/wrap-up/scripts/keep-records.py"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
MAIN="$WORK/repo"
git init -q -b main "$MAIN"
git -C "$MAIN" commit -q --allow-empty -m base
WT="$MAIN/.claude/worktrees/wt-a"
git -C "$MAIN" worktree add -q -b feat/a "$WT"
LEDGER="$MAIN/.git/workflow-ledger"
STEM=2026-11-11-a

q() { "$PYTHON" -c 'import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))' "$1"; }
mkround() {  # TREE TASK ROUND MANIFEST
  local d="$1/.revmux/tasks/$2/$3"
  mkdir -p "$d/stages" "$d/agents" "$d/input"
  printf '%s' "$4" >"$d/manifest.json"
  printf '{"findings": []}' >"$d/findings.json"
  printf '{"round": "%s"}' "$3" >"$d/stages/1-found.json"
  printf 'agent log\n' >"$d/agents/fable.log"
  printf 'scope\n' >"$d/input/scope.md"
}
task_md() { mkdir -p "$1/.revmux/tasks/$2" && printf -- '---\n%s\n---\n' "$3" >"$1/.revmux/tasks/$2/task.md"; }
ledger_files() { (cd "$LEDGER" && find . -type f | sort | tr '\n' ' '); }
keep() { "$PYTHON" -B "$KEEP" "$@"; }

mkdir -p "$MAIN/.peer-planning/$STEM/msgs" "$WT/.peer-planning/$STEM/msgs"
printf 'plan argument\n' >"$MAIN/.peer-planning/$STEM/msgs/001-claude-plan.md"
printf '{"event": "run.start"}\n{"event": "run.end"}\n' >"$WT/.peer-planning/$STEM/events.jsonl"
printf 'progress a\n' >"$WT/.peer-planning/$STEM/progress.md"
printf 'mail\n' >"$WT/.peer-planning/$STEM/msgs/002-codex.md"
printf '<html>' >"$WT/.peer-planning/$STEM/monitor.html"

mkround "$MAIN" feat-a 01-initial '{"run": "01"}'
mkround "$MAIN" feat-a 02-after-fix '{"run": "02 main"}'
mkround "$MAIN" feat-a 03-hygiene ''
mkdir -p "$MAIN/.revmux/tasks/feat-a/04-grill-me/agents"
task_md "$MAIN" custom 'branch: feat/a'
mkround "$MAIN" custom 01-x '{"run": "x"}'
mkround "$MAIN" plan-wt-a 01-plan '{"run": "night"}'
task_md "$MAIN" other $'# branch: feat/a\nbranch: feat/b'
mkround "$MAIN" other 01-initial '{"run": "other"}'
mkround "$WT" feat-a 01-initial '{"run": "01"}'
mkround "$WT" feat-a 02-after-fix '{"run": "02 worktree"}'
mkround "$WT" feat-a 05-security '{"run": "05"}'
mkround "$WT" "$STEM" 01-plan '{"run": "plan"}'

args=(--main "$MAIN" --worktree "$WT" --branch feat/a --name wt-a --plan-stem "$STEM")
out=$(keep inspect "${args[@]}")
got=$(q '[(t["tree"], t["id"], t["matched_by"], t["rounds"], t["unfinished"]) for t in d["tasks"]]' <<<"$out")
want="[('main', 'custom', 'branch', 1, []), ('main', 'feat-a', 'branch slug', 2, ['03-hygiene', '04-grill-me']), ('main', 'plan-wt-a', 'plan-NAME', 1, []), ('worktree', '$STEM', 'plan stem', 1, []), ('worktree', 'feat-a', 'branch slug', 3, [])]"
[ "$got" = "$want" ] || fail "inspect tasks: $got"
[ "$(q '[(r["tree"], r["files"]) for r in d["runs"]]' <<<"$out")" = "[('worktree', ['events.jsonl', 'progress.md'])]" ] \
  || fail "inspect runs: $out"
[ "$(field ledger <<<"$out")" = "$LEDGER" ] || fail "inspect ledger: $out"
[ ! -e "$LEDGER" ] || fail "inspect wrote to the ledger"
ok "inspect finds the branch's tasks in both trees by every rule, and the run record in WORKTREE"

out=$(keep copy "${args[@]}") || fail "copy exited non-zero: $out"
[ "$(field status <<<"$out")" = kept ] || fail "copy: $out"
hashed=$(q '[r["ledger"] for r in d["rounds"] if "renamed_from" in r][0].rsplit("/", 1)[1]' <<<"$out")
[[ $hashed =~ ^02-after-fix~[0-9a-f]{8}$ ]] || fail "the worktree's 02-after-fix name: $hashed"
round_files() { printf './revmux/%s/findings.json ./revmux/%s/manifest.json ./revmux/%s/stages/1-found.json ' "$1" "$1" "$1"; }
want="$(round_files "$STEM/01-plan")$(round_files custom/01-x)$(round_files feat-a/01-initial)$(round_files feat-a/02-after-fix)$(round_files "feat-a/$hashed")$(round_files feat-a/05-security)$(round_files plan-wt-a/01-plan)./runs/$STEM/events.jsonl ./runs/$STEM/progress.md "
[ "$(ledger_files)" = "$want" ] || fail "ledger files: $(ledger_files)"
ok "copy keeps the run record and the finished rounds' manifest, findings and stages, and nothing else"

[ "$(cat "$LEDGER/runs/$STEM/progress.md")" = "progress a" ] || fail "run record copied from the wrong tree"
ok "the run record is copied from WORKTREE when only WORKTREE holds events.jsonl"

[ "$(cat "$LEDGER/revmux/feat-a/02-after-fix/manifest.json")" = '{"run": "02 main"}' ] \
  && [ "$(cat "$LEDGER/revmux/feat-a/$hashed/manifest.json")" = '{"run": "02 worktree"}' ] \
  || fail "the two 02-after-fix rounds"
[ "$(q '[r["renamed_from"] for r in d["rounds"] if "renamed_from" in r]' <<<"$out")" = "['$LEDGER/revmux/feat-a/02-after-fix']" ] \
  || fail "renamed_from: $out"
[ "$(q '[(r["tree"], r["result"]) for r in d["rounds"] if r["task"] == "feat-a" and r["round"] == "01-initial"]' <<<"$out")" \
  = "[('main', 'copied'), ('worktree', 'already kept')]" ] || fail "identical 01-initial: $out"
ok "a round both trees hold keeps both copies when they differ, under a digest name, and one when they match"

[ "$(q '[(s["tree"], s["round"]) for s in d["skipped"]]' <<<"$out")" = "[('main', '03-hygiene'), ('main', '04-grill-me')]" ] \
  || fail "skipped: $out"
ok "an unfinished round, with manifest.json empty or missing, is skipped and named"

before=$(cd "$LEDGER" && find . -type f -exec shasum {} + | sort)
out=$(keep copy "${args[@]}") || fail "second copy exited non-zero: $out"
[ "$(q 'sorted({r["result"] for r in d["runs"] + d["rounds"]})' <<<"$out")" = "['already kept']" ] || fail "second copy: $out"
[ "$(cd "$LEDGER" && find . -type f -exec shasum {} + | sort)" = "$before" ] || fail "the second copy changed the ledger"
ok "a second copy writes nothing and leaves the ledger as it was"

# Branch feat/b has no worktree and its run record in MAIN; task "other" names it in task.md.
STEM_B=2026-11-11-b
mkdir -p "$MAIN/.peer-planning/$STEM_B"
printf '{"event": "run.start"}\n' >"$MAIN/.peer-planning/$STEM_B/events.jsonl"
out=$(keep copy --main "$MAIN" --branch feat/b --plan-stem "$STEM_B") || fail "copy feat/b: $out"
[ "$(q '[(r["tree"], r["result"]) for r in d["runs"]]' <<<"$out")" = "[('main', 'copied')]" ] || fail "feat/b run: $out"
[ "$(cd "$LEDGER/runs/$STEM_B" && find . -type f)" = ./events.jsonl ] || fail "feat/b run files"
[ -f "$LEDGER/revmux/other/01-initial/manifest.json" ] || fail "feat/b task other not kept"
ok "a run record in MAIN is kept, without a progress.md it never had"

# A copy that cannot be written fails loudly, keeps nothing half-written, and the wrap-up stops on
# its exit status.
mkround "$MAIN" feat-c 01-initial '{"run": "c"}'
mkdir -p "$LEDGER/revmux" && : >"$LEDGER/revmux/feat-c"
set +e
out=$(keep copy --main "$MAIN" --branch feat/c)
code=$?
set -e
[ "$code" = 1 ] && [ "$(field status <<<"$out")" = failed ] || fail "failing copy: exit $code: $out"
[ "$(q '[(r["round"], r["result"], bool(r["error"])) for r in d["rounds"]]' <<<"$out")" = "[('01-initial', 'failed', True)]" ] \
  || fail "failing copy entry: $out"
[ -z "$(find "$LEDGER" -name '.*' -mindepth 1)" ] || fail "a staging directory was left: $(find "$LEDGER" -name '.*')"
ok "a copy that fails exits 1, names the round and its error, and leaves no staging directory"

set +e
out=$(keep inspect --main "$WORK/not-a-repo" --branch feat/a)
code=$?
set -e
[ "$code" = 1 ] && [ "$(field status <<<"$out")" = error ] || fail "not a checkout: exit $code: $out"
ok "a MAIN that is not a git checkout is an error"

[ ! -d "$ROOT/plugins/git/skills/wrap-up/scripts/__pycache__" ] || fail "the script left __pycache__ in the plugin"
ok "the script left no __pycache__ in the plugin"
