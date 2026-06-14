#!/bin/bash
# black-box CLI tests for refine-plan-against-codex's state.py
# drives the subcommand surface end-to-end: init / resume / record-* /
# detect-stuck / summary / finalize. Hermetic — state is isolated via
# REFINE_PLAN_STATE_ROOT (state.py honors this env override) and all
# scratch lives under mktemp -d. No codex, no git, no network.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
STATE_PY="$REPO_ROOT/plugins/planning/skills/refine-plan-against-codex/references/state.py"

passed=0
failed=0

# safety: verify dirs are under /tmp or $TMPDIR before allowing any rm operations
assert_temp_dir() {
    local dir="$1"
    local tmpbase="${TMPDIR:-/tmp}"
    tmpbase="${tmpbase%/}"
    # also allow macOS-style /private/var/... that $TMPDIR may resolve to
    case "$dir" in
    "$tmpbase"/*) ;;
    /tmp/*) ;;
    /private/tmp/*) ;;
    /private/var/*) ;;
    /var/folders/*) ;;
    *)
        echo "FATAL: $dir is not under a recognised temp base, refusing to proceed" >&2
        exit 1
        ;;
    esac
}

PLAN_DIR="$(mktemp -d)"
STATE_ROOT="$(mktemp -d)"
assert_temp_dir "$PLAN_DIR"
assert_temp_dir "$STATE_ROOT"

cleanup() { rm -rf "$PLAN_DIR" "$STATE_ROOT"; }
trap cleanup EXIT

export REFINE_PLAN_STATE_ROOT="$STATE_ROOT"

assert_output() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: $test_name"
        passed=$((passed + 1))
    else
        echo "  FAIL: $test_name"
        echo "    expected: $(printf '%q' "$expected")"
        echo "    actual:   $(printf '%q' "$actual")"
        failed=$((failed + 1))
    fi
}

assert_contains() {
    local test_name="$1"
    local haystack="$2"
    local needle="$3"
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        echo "  PASS: $test_name"
        passed=$((passed + 1))
    else
        echo "  FAIL: $test_name"
        echo "    expected to contain: $(printf '%q' "$needle")"
        echo "    actual:              $(printf '%q' "$haystack")"
        failed=$((failed + 1))
    fi
}

assert_empty() {
    local test_name="$1"
    local actual="$2"
    if [ -z "$actual" ]; then
        echo "  PASS: $test_name"
        passed=$((passed + 1))
    else
        echo "  FAIL: $test_name"
        echo "    expected empty output"
        echo "    actual: $(printf '%q' "$actual")"
        failed=$((failed + 1))
    fi
}

assert_file() {
    local test_name="$1"
    local path="$2"
    if [ -f "$path" ]; then
        echo "  PASS: $test_name"
        passed=$((passed + 1))
    else
        echo "  FAIL: $test_name"
        echo "    expected file to exist: $(printf '%q' "$path")"
        failed=$((failed + 1))
    fi
}

assert_exit_nonzero() {
    local test_name="$1"
    local actual_rc="$2"
    if [ "$actual_rc" -ne 0 ]; then
        echo "  PASS: $test_name"
        passed=$((passed + 1))
    else
        echo "  FAIL: $test_name (expected non-zero exit, got 0)"
        failed=$((failed + 1))
    fi
}

# emit a needs-attention findings JSON for a single a.py:42 finding at the
# given confidence ($1 -> output path, $2 -> confidence)
write_findings() {
    cat >"$1" <<JSON
{"verdict":"needs-attention","summary":"s","findings":[{"severity":"high","file":"a.py","line_start":42,"line_end":42,"confidence":$2,"title":"t","body":"b","recommendation":"r"}],"next_steps":[]}
JSON
}

echo "testing state.py (refine-plan-against-codex)"
echo "============================================"

# fake plan with a date prefix so derive_slug strips it
PLAN="$PLAN_DIR/20260101-foo-bar.md"
echo "# foo bar plan" >"$PLAN"

# test 1: init
echo ""
echo "test 1: init creates state dir + manifest + gitignore"
STATE_DIR="$(python3 "$STATE_PY" init "$PLAN")"
if [ -d "$STATE_DIR" ]; then
    echo "  PASS: init prints an existing state-dir"
    passed=$((passed + 1))
else
    echo "  FAIL: init state-dir does not exist: $(printf '%q' "$STATE_DIR")"
    failed=$((failed + 1))
fi
assert_file "manifest.json present" "$STATE_DIR/manifest.json"
manifest="$(cat "$STATE_DIR/manifest.json")"
assert_contains "manifest status in_progress" "$manifest" '"status": "in_progress"'
assert_contains "manifest plan_slug strips date prefix" "$manifest" '"plan_slug": "foo-bar"'
assert_file "root .gitignore present" "$STATE_ROOT/.gitignore"
assert_output "gitignore contains '*'" "*" "$(cat "$STATE_ROOT/.gitignore")"

# test 2: resume returns the in-progress state-dir
echo ""
echo "test 2: resume finds the in-progress run"
assert_output "resume prints the in-progress state-dir" "$STATE_DIR" "$(python3 "$STATE_PY" resume "$PLAN")"

# test 3: record-codex-start / -end copies findings + records tokens
echo ""
echo "test 3: record-codex round 1"
python3 "$STATE_PY" record-codex-start "$STATE_DIR" 1
FIND1="$PLAN_DIR/findings-1.txt"
write_findings "$FIND1" 0.9
python3 "$STATE_PY" record-codex-end "$STATE_DIR" 1 "$FIND1" 100 5
assert_file "round-01/findings.txt copied" "$STATE_DIR/round-01/findings.txt"
assert_contains "manifest carries codex_tokens 100" "$(cat "$STATE_DIR/manifest.json")" '"codex_tokens": 100'

# test 4: record-implementer-start / -end copies summary
echo ""
echo "test 4: record-implementer round 1"
python3 "$STATE_PY" record-implementer-start "$STATE_DIR" 1
SUMM1="$PLAN_DIR/summary-1.txt"
echo "addressed the high finding in a.py" >"$SUMM1"
python3 "$STATE_PY" record-implementer-end "$STATE_DIR" 1 "$SUMM1" 50 3
assert_file "round-01/implementer-summary.txt copied" "$STATE_DIR/round-01/implementer-summary.txt"

# test 5: a second round with the SAME a.py:42 finding -> detect-stuck fires
echo ""
echo "test 5: detect-stuck on recurring high-confidence finding"
python3 "$STATE_PY" record-codex-start "$STATE_DIR" 2
FIND2="$PLAN_DIR/findings-2.txt"
write_findings "$FIND2" 0.9
python3 "$STATE_PY" record-codex-end "$STATE_DIR" 2 "$FIND2" 80 4
stuck_out="$(python3 "$STATE_PY" detect-stuck "$STATE_DIR")"
assert_contains "detect-stuck reports a.py:42 across rounds 1,2" "$stuck_out" "STUCK a.py:42 rounds: 1,2"

# test 6: same recurrence but below the confidence floor -> nothing
echo ""
echo "test 6: detect-stuck suppresses low-confidence recurrence"
# inline `VAR=val cmd` env-scoping (not an (export ...) subshell) so the
# isolated state root applies per-command without shellcheck SC2030/SC2031.
LOW_ROOT="$(mktemp -d)"
assert_temp_dir "$LOW_ROOT"
LOW_DIR="$(REFINE_PLAN_STATE_ROOT="$LOW_ROOT" python3 "$STATE_PY" init "$PLAN")"
g1="$PLAN_DIR/low-1.txt"
g2="$PLAN_DIR/low-2.txt"
write_findings "$g1" 0.2
write_findings "$g2" 0.2
REFINE_PLAN_STATE_ROOT="$LOW_ROOT" python3 "$STATE_PY" record-codex-end "$LOW_DIR" 1 "$g1" 10 1
REFINE_PLAN_STATE_ROOT="$LOW_ROOT" python3 "$STATE_PY" record-codex-end "$LOW_DIR" 2 "$g2" 10 1
low_stuck_out="$(REFINE_PLAN_STATE_ROOT="$LOW_ROOT" python3 "$STATE_PY" detect-stuck "$LOW_DIR")"
rm -rf "$LOW_ROOT"
assert_empty "detect-stuck silent below CONFIDENCE_FLOOR" "$low_stuck_out"

# test 6b: a round-4 arbiter pass (the gate only runs from round 4) — codex
# then record-arbiter-start/-end; arbiter.txt is copied + tokens stamped.
# Uses b.py:7, not a.py:42, so the detect-stuck assertions above are unaffected.
echo ""
echo "test 6b: record-arbiter on round 4"
python3 "$STATE_PY" record-codex-start "$STATE_DIR" 4
FIND4="$PLAN_DIR/findings-4.txt"
cat >"$FIND4" <<'JSON'
{"verdict":"needs-attention","summary":"s","findings":[{"severity":"high","file":"b.py","line_start":7,"line_end":7,"confidence":0.9,"title":"t","body":"b","recommendation":"r"}],"next_steps":[]}
JSON
python3 "$STATE_PY" record-codex-end "$STATE_DIR" 4 "$FIND4" 90 4
python3 "$STATE_PY" record-arbiter-start "$STATE_DIR" 4
ARB4="$PLAN_DIR/arbiter-4.txt"
cat >"$ARB4" <<'JSON'
{"classifications":[{"index":1,"class":"prose","reason":"wording only"}],"summary":"1 prose"}
JSON
python3 "$STATE_PY" record-arbiter-end "$STATE_DIR" 4 "$ARB4" 20 2
assert_file "round-04/arbiter.txt copied" "$STATE_DIR/round-04/arbiter.txt"
assert_contains "manifest carries arbiter_tokens 20" "$(cat "$STATE_DIR/manifest.json")" '"arbiter_tokens": 20'

# test 7: summary renders box-drawn table with expected rows
echo ""
echo "test 7: summary table"
summary_out="$(python3 "$STATE_PY" summary "$STATE_DIR")"
assert_contains "summary has 'Round 1 codex' row" "$summary_out" "Round 1 codex"
assert_contains "summary has 'Round 4 arbiter' row" "$summary_out" "Round 4 arbiter"
assert_contains "summary arbiter row shows 0r 1p digest" "$summary_out" "0r 1p"
assert_contains "summary has 'Total' row" "$summary_out" "Total"
assert_contains "summary uses box top-left corner" "$summary_out" "┌"
assert_contains "summary uses box vertical bar" "$summary_out" "│"

# test 8: finalize rejects an unknown status (exit 2, stderr names allowed set)
echo ""
echo "test 8: finalize rejects a bogus status"
set +e
bogus_err="$(python3 "$STATE_PY" finalize "$STATE_DIR" bogus-status 2>&1 >/dev/null)"
bogus_rc=$?
set -e
assert_exit_nonzero "finalize bogus-status exits non-zero" "$bogus_rc"
assert_contains "finalize error names the allowed set" "$bogus_err" "allowed:"

# test 8b: finalize accepts completed_converged (the prose-drift gate's status)
echo ""
echo "test 8b: finalize accepts completed_converged"
CONV_ROOT="$(mktemp -d)"
assert_temp_dir "$CONV_ROOT"
CONV_DIR="$(REFINE_PLAN_STATE_ROOT="$CONV_ROOT" python3 "$STATE_PY" init "$PLAN")"
REFINE_PLAN_STATE_ROOT="$CONV_ROOT" python3 "$STATE_PY" finalize "$CONV_DIR" completed_converged
conv_manifest="$(cat "$CONV_DIR/manifest.json")"
rm -rf "$CONV_ROOT"
assert_contains "finalize accepts completed_converged" "$conv_manifest" '"status": "completed_converged"'

# test 9: finalize with a valid terminal status updates the manifest
echo ""
echo "test 9: finalize completed_clean"
python3 "$STATE_PY" finalize "$STATE_DIR" completed_clean
assert_contains "manifest status -> completed_clean" "$(cat "$STATE_DIR/manifest.json")" '"status": "completed_clean"'

# test 10: resume is silent once the run is finalized
echo ""
echo "test 10: resume after finalize"
assert_empty "resume prints nothing for a finalized run" "$(python3 "$STATE_PY" resume "$PLAN")"

# summary
echo ""
echo "============================================"
echo "results: $passed passed, $failed failed"

if [ "$failed" -gt 0 ]; then
    exit 1
fi
