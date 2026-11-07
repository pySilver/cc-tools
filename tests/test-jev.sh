#!/usr/bin/env bash
# jev and the backlog triage built on it, offline. jev refuses a bad spec, an input past Jev's
# accurate range (exit 3, nothing sent) and a missing key; triage.py, against a fake jev, judges
# only what changed, never sends a worth: no item, re-checks a waiting item only when the default
# branch moves, and lists an item jev refuses as too long instead of cutting it.
# Everything happens in a throwaway repository; nothing reaches the network.
set -euo pipefail

cd "$(dirname "$0")/.."
JEV=$PWD/plugins/jev/bin/jev
TRIAGE=$PWD/plugins/tracking/skills/backlog/scripts/triage.py
WORK=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
PY=$(python3 -I -c 'import sys; print(sys.executable)')
export HOME="$WORK/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
mkdir -p "$HOME"

fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }
exit_of() { set +e; "$@" >/dev/null 2>&1; local code=$?; set -e; echo "$code"; }

# ---- jev ----
spec='{"state":"s","questions":{"q":{"instructions":"pick","choices":{"a":"first","b":"second"}}}}'
if [ "$(exit_of "$PY" -B "$JEV" check - <<<"$spec")" = 0 ]; then pass "jev check accepts a well-formed spec"; else fail "jev check accepts a well-formed spec"; fi
one_choice='{"state":"s","questions":{"q":{"instructions":"pick","choices":{"a":"only"}}}}'
if [ "$(exit_of "$PY" -B "$JEV" check - <<<"$one_choice")" = 1 ]; then pass "jev refuses a question with one choice"; else fail "jev refuses a question with one choice"; fi
long_state=$("$PY" -c 'print("x" * 33000)')
long='{"state":"'"$long_state"'","questions":{"q":{"instructions":"pick","choices":{"a":"first","b":"second"}}}}'
if [ "$(exit_of "$PY" -B "$JEV" check - <<<"$long")" = 3 ]; then pass "jev refuses an input over 32,000 bytes with exit 3"; else fail "jev refuses an input over 32,000 bytes with exit 3"; fi
if [ "$(exit_of env -u OPENROUTER_API_KEY "$PY" -B "$JEV" - <<<"$spec")" = 1 ]; then pass "jev fails loudly without OPENROUTER_API_KEY"; else fail "jev fails loudly without OPENROUTER_API_KEY"; fi

# ---- triage.py against a fake jev ----
# The fake answers "waiting" for an item whose text says "production traffic", "owner" for one
# that says "TOO-LONG" is refused with exit 3, and "agent" otherwise. It logs each call's state.
FAKE=$WORK/fake-jev
cat >"$FAKE" <<'FAKEJEV'
#!/usr/bin/env python3
import json, os, sys
spec = json.load(sys.stdin)
with open(os.environ["FAKE_LOG"], "a") as log:
    log.write(json.dumps(spec["state"]) + "\n")
if "TOO-LONG" in spec["state"]:
    print("jev: the input is 40000 bytes, over Jev's 32000", file=sys.stderr)
    sys.exit(3)
choice = "waiting" if "production traffic" in spec["state"] and "traffic is live" not in spec["state"] else "agent"
print(json.dumps({"answers": {"triage": {"choice": choice, "confidence": 0.9, "probabilities": {choice: 0.9}}}}))
FAKEJEV
chmod +x "$FAKE"
export JEV_BIN=$FAKE FAKE_LOG=$WORK/calls.log

REPO=$WORK/repo
mkdir -p "$REPO/docs/backlog"
git -C "$REPO" init -q -b master
item() { printf -- '---\nworth: %s\nadded: 2026-11-07\n---\n# %s\n\n%s\n' "$2" "$1" "$3" >"$REPO/docs/backlog/$1.md"; }
item fix-it yes "A defect with a clear fix."
item wait-for-traffic later "Waits for production traffic."
item rejected no "Decided against."
item huge yes "TOO-LONG"
git -C "$REPO" add -A && git -C "$REPO" commit -qm items
triage() { "$PY" -B "$TRIAGE" "$@" --repo "$REPO" 2>&1; }
verdict() { "$PY" -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]].get("verdict","unjudged"))' "$REPO/.git/backlog-triage.json" "$1"; }
calls() { wc -l <"$FAKE_LOG" | tr -d ' '; }

: >"$FAKE_LOG"
triage refresh >/dev/null
if [ "$(verdict fix-it)" = agent ] && [ "$(verdict wait-for-traffic)" = waiting ] && [ "$(verdict rejected)" = decided ]; then
  pass "triage sorts the items, with worth: no as decided"
else
  fail "triage sorts the items: fix-it=$(verdict fix-it) wait=$(verdict wait-for-traffic) rejected=$(verdict rejected)"
fi
if [ "$(calls)" = 3 ] && ! grep -q 'Decided against' "$FAKE_LOG"; then pass "a worth: no item is never sent to jev"; else fail "a worth: no item is never sent to jev ($(calls) calls)"; fi
if [ "$(verdict huge)" = unjudged ] && triage report | grep -q 'over Jev'; then pass "an item jev refuses as too long is listed as not judged, with the reason"; else fail "an item jev refuses as too long is listed as not judged"; fi

: >"$FAKE_LOG"
triage refresh >/dev/null
# Nothing changed, so nothing is sent: a too-long item would only be refused again until its text changes.
if [ "$(calls)" = 0 ]; then pass "a second refresh with nothing changed sends nothing"; else fail "a second refresh with nothing changed sends nothing ($(calls) calls)"; fi

: >"$FAKE_LOG"
item fix-it yes "A defect with a clear fix, now described better."
triage refresh >/dev/null
if grep -q 'described better' "$FAKE_LOG" && ! grep -q 'Waits for production' "$FAKE_LOG"; then pass "an edited item is judged again, an unchanged waiting one is not"; else fail "an edited item is judged again, an unchanged waiting one is not"; fi

: >"$FAKE_LOG"
git -C "$REPO" commit -q --allow-empty -m "feat: traffic is live"
triage refresh >/dev/null
if grep -q 'Waits for production' "$FAKE_LOG" && grep -q 'traffic is live' "$FAKE_LOG" && [ "$(verdict wait-for-traffic)" = agent ]; then
  pass "a waiting item is re-checked with the new commits once the default branch moves"
else
  fail "a waiting item is re-checked once the default branch moves: verdict $(verdict wait-for-traffic)"
fi

rm "$REPO/docs/backlog/fix-it.md"
triage refresh >/dev/null
if [ "$("$PY" -c 'import json,sys; print("fix-it" in json.load(open(sys.argv[1])))' "$REPO/.git/backlog-triage.json")" = False ]; then
  pass "a removed item's verdict is dropped"
else
  fail "a removed item's verdict is dropped"
fi

if ! git -C "$REPO" status --porcelain --untracked-files=all | grep -q backlog-triage; then
  pass "the verdicts never appear in the work tree"
else
  fail "the verdicts never appear in the work tree"
fi

[ "$fails" -eq 0 ] || { printf '%d failure(s)\n' "$fails"; exit 1; }
