#!/bin/bash
# behavioral tests for refine-plan-against-codex's extract-sentinels.sh
# contract (references/README.md): scan for lines containing **load-bearing
# (case-insensitive); for each, collect every backtick-fenced span in a
# +/-1-line window; return unique sentinels one per line; empty if none.
# Hermetic — fixtures live under mktemp -d. No network, no codex.
#
# The fixtures below embed literal `backtick` spans inside single-quoted
# strings on purpose — they are markdown content, not shell command
# substitutions — so SC2016 is a false positive throughout this file.
# shellcheck disable=SC2016

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
EXTRACT="$REPO_ROOT/plugins/planning/skills/refine-plan-against-codex/references/extract-sentinels.sh"

passed=0
failed=0

# safety: verify dirs are under /tmp or $TMPDIR before allowing any rm operations
assert_temp_dir() {
    local dir="$1"
    local tmpbase="${TMPDIR:-/tmp}"
    tmpbase="${tmpbase%/}"
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

WORK_DIR="$(mktemp -d)"
assert_temp_dir "$WORK_DIR"

cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

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

# count how many times a whole line equals $2 in $1
assert_count() {
    local test_name="$1"
    local output="$2"
    local line="$3"
    local expected="$4"
    local n
    n="$(printf '%s\n' "$output" | grep -cxF -- "$line" || true)"
    if [ "$n" = "$expected" ]; then
        echo "  PASS: $test_name"
        passed=$((passed + 1))
    else
        echo "  FAIL: $test_name"
        echo "    expected $line to appear $expected time(s), got $n"
        echo "    actual: $(printf '%q' "$output")"
        failed=$((failed + 1))
    fi
}

echo "testing extract-sentinels.sh (refine-plan-against-codex)"
echo "========================================================"

# test 1: no **load-bearing marker -> empty output
echo ""
echo "test 1: no load-bearing marker"
p1="$WORK_DIR/none.md"
printf '%s\n' '- [ ] a plain task with a `code-span` but no marker' >"$p1"
assert_empty "no marker produces empty output" "$(bash "$EXTRACT" "$p1")"

# test 2: marker line with two backtick spans -> both captured
echo ""
echo "test 2: two sentinels on the marker line"
p2="$WORK_DIR/same-line.md"
printf '%s\n' '- [ ] keep it intact **load-bearing**: `a.py:42` and `BAR_CONST` must not move' >"$p2"
out2="$(bash "$EXTRACT" "$p2")"
assert_contains "captures a.py:42" "$out2" "a.py:42"
assert_contains "captures BAR_CONST" "$out2" "BAR_CONST"

# test 3: marker on one line, identifier on the next (within the +/-1 window)
echo ""
echo "test 3: identifier on the line after the marker"
p3="$WORK_DIR/next-line.md"
printf '%s\n' \
    '- [ ] a checkbox that wraps onto the next line **load-bearing**' \
    '      because `NEXT_LINE_ID` has to survive the edit' >"$p3"
out3="$(bash "$EXTRACT" "$p3")"
assert_contains "captures identifier on adjacent line" "$out3" "NEXT_LINE_ID"

# test 4: same sentinel under two markers -> emitted once
echo ""
echo "test 4: duplicate sentinel deduped"
p4="$WORK_DIR/dup.md"
printf '%s\n' \
    '- [ ] first **load-bearing** keep `DUP_ID`' \
    '- [ ] second **load-bearing** also `DUP_ID`' >"$p4"
out4="$(bash "$EXTRACT" "$p4")"
assert_count "DUP_ID emitted exactly once" "$out4" "DUP_ID" 1

# summary
echo ""
echo "========================================================"
echo "results: $passed passed, $failed failed"

if [ "$failed" -gt 0 ]; then
    exit 1
fi
