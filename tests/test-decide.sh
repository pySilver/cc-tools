#!/usr/bin/env bash
# decide:gate's shadow log, offline: gate-log.py records the judge's verdict and the user's answer
# in the git directory (never the work tree), refuses an unknown verdict and an answer to a
# question it never logged, and reports both side by side. Then decide:panel's cast.py: the cast
# resolves from one layer (project, then user, then built-in), a checkout older than its default
# branch's cast reads that cast, init copies a cast down, and run-dir makes a folder git ignores.
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
git init -q --bare "$PANEL/origin.git"
git -C "$REPO" remote add origin "$PANEL/origin.git"
git -C "$REPO" push -q origin main
git -C "$REPO" remote set-head origin main
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

# The cast lands on local main only; origin/HEAD still names a main without it.
git -C "$REPO" add .personas
commit "$REPO" "cast"
git -C "$REPO" worktree add -q "$PANEL/old" old
source_of() { cast --repo "$1" | "$PY" -c 'import json, sys; c = json.load(sys.stdin); print(c["layer"], c["source"].split(" at ")[0], len(c["personas"]))'; }
if [ "$(source_of "$PANEL/old")" = "project main 2" ] && [ ! -e "$PANEL/old/.personas" ]; then
  pass "a worktree older than the cast reads it from the local default branch before it is pushed"
else
  fail "stale worktree, cast unpushed: $(source_of "$PANEL/old")"
fi
git -C "$REPO" push -q origin main
if [ "$(source_of "$PANEL/old")" = "project main 2" ] && [ -z "$(git -C "$PANEL/old" status --porcelain --untracked-files=all)" ]; then
  pass "after the push it still reads the default branch's cast, and leaves the worktree clean"
else
  fail "stale worktree, cast pushed: $(source_of "$PANEL/old")"
fi
git -C "$REPO" branch -q -m main trunk
git -C "$REPO" remote set-head origin -d
git -C "$REPO" push -q origin trunk
git -C "$REPO" push -q origin --delete main
git -C "$REPO" fetch -q --prune origin
if [ "$(source_of "$PANEL/old")" = "project trunk 2" ]; then pass "a default branch named trunk is found without origin/HEAD"; else fail "trunk: $(source_of "$PANEL/old")"; fi

# A persona edit lands on the remote from another clone; the local branch is left behind.
git clone -q -b trunk "$PANEL/origin.git" "$PANEL/other"
printf '# Shopper, edited\n' >"$PANEL/other/.personas/cast/shopper.md"
git -C "$PANEL/other" add .personas
commit "$PANEL/other" "edit shopper"
git -C "$PANEL/other" push -q origin trunk
git -C "$REPO" fetch -q origin
shopper=$(cast --repo "$PANEL/old" | "$PY" -c 'import json, sys; print([p["path"] for p in json.load(sys.stdin)["personas"] if p["stem"] == "shopper"][0])')
if [ "$(source_of "$PANEL/old")" = "project origin/trunk 2" ] && grep -q 'edited' "$shopper"; then
  pass "when the local default branch is behind the remote one, the remote's newer cast is read"
else
  fail "local behind remote: $(source_of "$PANEL/old"), $(head -1 "$shopper")"
fi
refusal=$(cast init --repo "$PANEL/old" 2>&1 || true)
if [ "$(status_of cast init --repo "$PANEL/old")" = 1 ] && grep -q 'rebase onto it' <<<"$refusal"; then
  pass "init refuses a worktree whose default branch already has a cast"
else
  fail "init in a stale worktree: $refusal"
fi
if [ "$(status_of cast --repo "$PANEL/no-such-dir")" = 1 ]; then pass "a --repo that does not exist is refused"; else fail "a missing --repo was accepted"; fi

FRESH=$PANEL/fresh
git init -q -b main "$FRESH"
cast init --repo "$FRESH" >/dev/null
if [ -f "$FRESH/.personas/cast/reader.md" ] && [ -f "$FRESH/.personas/cast/README.md" ] && [ "$(layer_of "$FRESH")" = "project 1" ]; then
  pass "init copies the cast that resolves into the project"
else
  fail "init did not copy the resolved cast"
fi
if [ "$(status_of cast init --repo "$FRESH")" = 1 ]; then pass "init refuses a project that already has a cast"; else fail "init overwrote a project cast"; fi
README_ONLY=$PANEL/readme-only
git init -q -b main "$README_ONLY"
mkdir -p "$README_ONLY/.personas/cast"
printf '# Ours\n' >"$README_ONLY/.personas/cast/README.md"
if [ "$(status_of cast init --repo "$README_ONLY")" = 1 ] && grep -q '^# Ours$' "$README_ONLY/.personas/cast/README.md"; then
  pass "init refuses a cast folder that holds only an index, and leaves it as it was"
else
  fail "init overwrote an index"
fi

dir=$(cast run-dir pack-size --repo "$REPO")
if [ -d "$dir" ] && [ "$(basename "$dir")" = "$(date +%Y-%m-%d)-pack-size" ] && [ -z "$(git -C "$REPO" status --porcelain --untracked-files=all)" ]; then
  pass "run-dir makes a dated folder that git status never shows"
else
  fail "run-dir: $dir; status: $(git -C "$REPO" status --porcelain --untracked-files=all)"
fi
if [ "$(status_of cast run-dir pack-size --repo "$REPO")" = 1 ]; then pass "run-dir refuses a folder that already exists"; else fail "run-dir reused a folder"; fi
if [ -d "$(dirname "$CAST")/__pycache__" ]; then fail "cast.py left no __pycache__"; else pass "cast.py left no __pycache__"; fi

[ "$fails" -eq 0 ] || { printf '%d failure(s)\n' "$fails"; exit 1; }
