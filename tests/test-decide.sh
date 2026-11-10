#!/usr/bin/env bash
# decide:gate's shadow log, offline: gate-log.py records the judge's verdict and the user's answer
# in the git directory (never the work tree), refuses an unknown verdict and an answer to a
# question it never logged, and reports both side by side. Then decide:panel's cast.py: the cast
# resolves from one layer (project, then user, then built-in), a checkout that predates its
# default branch's cast is refused, init copies a cast down, and run-dir makes a folder git ignores.
set -euo pipefail

cd "$(dirname "$0")/.."
LOG=$PWD/plugins/decide/skills/gate/scripts/gate-log.py
WORK=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
PY=$(python3 -I -c 'import sys; print(sys.executable)')
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
git -C "$WORK" init -q

fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }
gate() { "$PY" -B "$LOG" "$@" --repo "$WORK"; }
status_of() { set +e; "$@" >/dev/null 2>&1; local code=$?; set -e; echo "$code"; }

gate ask --id 001-size --question "Which size?" --verdict held --cite "no ruling covers it"
gate ask --id 002-gmc --question "May an approved promotion be edited?" --verdict decided --cite "promotions-follow-merchant-center.md"
gate answer --id 002-gmc --answer "only the end time"
if [ -f "$WORK/.git/decide-gate.jsonl" ] && [ -z "$(git -C "$WORK" status --porcelain --untracked-files=all)" ]; then
  pass "the log lives in the git directory, not the work tree"
else
  fail "the log lives in the git directory, not the work tree"
fi
if [ "$(status_of gate ask --id 003 --question q --verdict maybe)" = 1 ]; then pass "an unknown verdict is refused"; else fail "an unknown verdict is refused"; fi
if [ "$(status_of gate answer --id 404 --answer x)" = 1 ]; then pass "an answer to a question never logged is refused"; else fail "an answer to a question never logged is refused"; fi
out=$(gate report)
if grep -q 'owner: only the end time' <<<"$out" && grep -q 'owner: (not answered yet)' <<<"$out" && grep -q '2 questions, 1 answered' <<<"$out"; then
  pass "the report puts each verdict beside its answer and counts them"
else
  fail "the report puts each verdict beside its answer: $out"
fi
if [ -d "$(dirname "$LOG")/__pycache__" ]; then fail "the script left no __pycache__"; else pass "the script left no __pycache__"; fi

CAST=$PWD/plugins/decide/skills/panel/scripts/cast.py
PANEL=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$WORK" "$PANEL"' EXIT
export HOME=$PANEL/home
mkdir -p "$HOME"
commit() { git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m "$2"; }
cast() { "$PY" -B "$CAST" "$@"; }
layer_of() { cast --repo "$1" | "$PY" -c 'import json, sys; c = json.load(sys.stdin); print(c["layer"], len(c["personas"]))'; }

REPO=$PANEL/repo
git init -q -b main "$REPO"
commit "$REPO" "start"
if [ "$(layer_of "$REPO")" = "built-in 3" ]; then pass "with no project or user cast, the built-in cast of three answers"; else fail "built-in fallback: $(layer_of "$REPO")"; fi

mkdir -p "$HOME/.config/personas/cast"
printf '# Index\n' >"$HOME/.config/personas/cast/README.md"
if [ "$(layer_of "$REPO")" = "built-in 3" ]; then pass "an index with no persona file is not a cast"; else fail "an index alone counted as a cast"; fi
printf '# Reader\n' >"$HOME/.config/personas/cast/reader.md"
if [ "$(layer_of "$REPO")" = "user 1" ]; then pass "the user's cast replaces the built-in one whole"; else fail "user layer: $(layer_of "$REPO")"; fi

git -C "$REPO" branch old
mkdir -p "$REPO/.personas/cast"
printf '# Shopper\n' >"$REPO/.personas/cast/shopper.md"
printf '# Merchant\n' >"$REPO/.personas/cast/merchant.md"
if [ "$(layer_of "$REPO")" = "project 2" ]; then pass "the project's cast replaces the user's whole"; else fail "project layer: $(layer_of "$REPO")"; fi

git -C "$REPO" add .personas
commit "$REPO" "cast"
git -C "$REPO" worktree add -q "$PANEL/old" old
refusal=$(cast --repo "$PANEL/old" 2>&1 || true)
if [ "$(status_of cast --repo "$PANEL/old")" = 1 ] && grep -q 'rebase or merge main' <<<"$refusal"; then
  pass "a worktree branched before the default branch's cast is refused, not given the user's cast"
else
  fail "a stale worktree was not refused"
fi

FRESH=$PANEL/fresh
git init -q -b main "$FRESH"
cast init --repo "$FRESH" >/dev/null
if [ -f "$FRESH/.personas/cast/reader.md" ] && [ -f "$FRESH/.personas/cast/README.md" ] && [ "$(layer_of "$FRESH")" = "project 1" ]; then
  pass "init copies the cast that resolves into the project"
else
  fail "init did not copy the resolved cast"
fi
if [ "$(status_of cast init --repo "$FRESH")" = 1 ]; then pass "init refuses a project that already has a cast"; else fail "init overwrote a project cast"; fi

dir=$(cast run-dir pack-size --repo "$REPO")
if [ -d "$dir" ] && [ "$(basename "$dir")" = "$(date +%Y-%m-%d)-pack-size" ] && [ -z "$(git -C "$REPO" status --porcelain --untracked-files=all)" ]; then
  pass "run-dir makes a dated folder that git status never shows"
else
  fail "run-dir: $dir; status: $(git -C "$REPO" status --porcelain --untracked-files=all)"
fi
if [ "$(status_of cast run-dir pack-size --repo "$REPO")" = 1 ]; then pass "run-dir refuses a folder that already exists"; else fail "run-dir reused a folder"; fi
if [ -d "$(dirname "$CAST")/__pycache__" ]; then fail "cast.py left no __pycache__"; else pass "cast.py left no __pycache__"; fi

[ "$fails" -eq 0 ] || { printf '%d failure(s)\n' "$fails"; exit 1; }
