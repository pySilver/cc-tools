#!/bin/bash
# behavioral tests for refine-plan-against-codex's run-codex.sh wrapper
# contract (references/README.md): invokes `codex exec --sandbox read-only`
# with a default model of gpt-5.6-sol; CODEX_MODEL=<name> overrides the
# default; CODEX_NO_OVERRIDES=1 skips the -c overrides entirely; the
# prompt passes through as the final argument.
# Hermetic — `codex` and `git` are PATH stubs under mktemp -d, so neither
# real binary is needed. No network.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
RUN_CODEX="$REPO_ROOT/plugins/planning/skills/refine-plan-against-codex/references/run-codex.sh"

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

# PATH stubs: `codex` prints its argv one arg per line so assertions can
# match whole args; `git` answers the wrapper's `git rev-parse --git-dir`
# VCS probe with success so the test doesn't depend on a real checkout.
STUB_BIN="$WORK_DIR/bin"
mkdir -p "$STUB_BIN"
cat >"$STUB_BIN/codex" <<'EOF'
#!/bin/bash
printf '%s\n' "$@"
EOF
cat >"$STUB_BIN/git" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$STUB_BIN/codex" "$STUB_BIN/git"

# run_wrapper [VAR=value ...] — invoke the wrapper with the stub PATH and
# a fixed prompt; extra env assignments are passed through to `env`.
# CODEX_MODEL/CODEX_NO_OVERRIDES are unset first so values exported by the
# invoking shell can't leak in — only the "$@" assignments reach the wrapper.
run_wrapper() {
    env -u CODEX_MODEL -u CODEX_NO_OVERRIDES \
        PATH="$STUB_BIN:$PATH" "$@" bash "$RUN_CODEX" 'review the plan'
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

assert_not_contains() {
    local test_name="$1"
    local haystack="$2"
    local needle="$3"
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        echo "  FAIL: $test_name"
        echo "    expected NOT to contain: $(printf '%q' "$needle")"
        echo "    actual:                  $(printf '%q' "$haystack")"
        failed=$((failed + 1))
    else
        echo "  PASS: $test_name"
        passed=$((passed + 1))
    fi
}

echo "testing run-codex.sh (refine-plan-against-codex)"
echo "========================================================"

# test 1: default invocation shape — default model, read-only sandbox,
# prompt passed through
echo ""
echo "test 1: default model and invocation shape"
out1="$(run_wrapper)"
assert_contains "defaults to gpt-5.6-sol" "$out1" "model=gpt-5.6-sol"
assert_contains "runs codex exec" "$out1" "exec"
assert_contains "read-only sandbox" "$out1" "read-only"
assert_contains "prompt passed through" "$out1" "review the plan"

# test 2: CODEX_MODEL overrides the default
echo ""
echo "test 2: CODEX_MODEL override"
out2="$(run_wrapper CODEX_MODEL=custom-model)"
assert_contains "override model used" "$out2" "model=custom-model"
assert_not_contains "default model absent" "$out2" "model=gpt-5.6-sol"

# test 3: CODEX_NO_OVERRIDES=1 drops the -c overrides entirely
echo ""
echo "test 3: CODEX_NO_OVERRIDES=1"
out3="$(run_wrapper CODEX_NO_OVERRIDES=1)"
assert_not_contains "no model override passed" "$out3" "model="
assert_contains "prompt still passed through" "$out3" "review the plan"

# summary
echo ""
echo "========================================================"
echo "results: $passed passed, $failed failed"

if [ "$failed" -gt 0 ]; then
    exit 1
fi
