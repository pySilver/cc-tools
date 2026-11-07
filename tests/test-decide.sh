#!/usr/bin/env bash
# decide:gate's shadow log, offline: gate-log.py records the judge's verdict and the user's answer
# in the git directory (never the work tree), refuses an unknown verdict and an answer to a
# question it never logged, and reports both side by side.
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

[ "$fails" -eq 0 ] || { printf '%d failure(s)\n' "$fails"; exit 1; }
