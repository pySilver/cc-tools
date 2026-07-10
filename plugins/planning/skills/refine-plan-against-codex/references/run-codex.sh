#!/usr/bin/env bash
#
# run-codex.sh — codex wrapper owned by the refine-plan-against-codex
# skill. Forked from the planning plugin's wrapper
# (~/.claude/plugins/cache/umputun-cc-thingz/planning/3.7.1/skills/exec/
# scripts/run-codex.sh) on 2026-05-18 because the wedge-fix patch we
# maintain on the upstream file gets clobbered by plugin updates.
# Owning the file here means plugin updates don't touch it and the fix
# survives.
#
# What this script does:
#   - Invokes `codex exec` with --sandbox read-only and our default
#     model / reasoning-effort / project-doc settings.
#   - Detects git vs hg and passes --skip-git-repo-check for hg (codex
#     refuses to run in non-git checkouts without it).
#   - Closes stdin before invoking codex to defend against a known wedge:
#     codex prints "Reading additional input from stdin..." and ~1 in 5
#     invocations hangs at 0 CPU when the calling shell's stdin is a
#     non-tty pipe. `</dev/null` costs nothing on the happy path and
#     eliminates the wedge.
#
# Escape hatches:
#   CODEX_NO_OVERRIDES=1   skip the -c overrides (for corporate codex
#                          proxies that reject the model_provider switch)
#   CODEX_MODEL=<name>     override the default model (gpt-5.6-sol)
#   CODEX_TIMEOUT=<sec>    override the hard wall-clock timeout (default
#                          1200s / 20 min, ~4× the documented 2-5 min
#                          typical max). Wedges hit this cap and exit
#                          124 cleanly; the subagent translates that to
#                          CODEX_ERROR: timeout in the orchestrator.
#
# Usage: run-codex.sh '<prompt>'
# Output: codex's response on stdout. Exit code: codex's (or 124 on timeout).

set -euo pipefail

prompt="${1:?usage: $0 '<prompt>'}"

# Inline VCS detect — small enough that a second helper file isn't worth
# the dependency surface. Precedence: git first, hg second.
if git rev-parse --git-dir >/dev/null 2>&1; then
    vcs=git
elif command -v hg >/dev/null 2>&1 && hg root >/dev/null 2>&1; then
    vcs=hg
else
    echo "$0: not inside a git or hg checkout" >&2
    exit 1
fi

args=("exec")
[[ "$vcs" = "hg" ]] && args+=("--skip-git-repo-check")
args+=("--sandbox" "read-only")

if [[ "${CODEX_NO_OVERRIDES:-}" != 1 ]]; then
    args+=(
        "-c" "model=${CODEX_MODEL:-gpt-5.6-sol}"
        "-c" "model_reasoning_effort=xhigh"
        "-c" "stream_idle_timeout_ms=3600000"
        "-c" "project_doc=$HOME/.claude/CLAUDE.md"
        "-c" "project_doc=./CLAUDE.md"
    )
fi

# Two-layer wedge defense:
# 1. stdin → /dev/null so codex's "Reading additional input from
#    stdin..." path gets EOF instead of blocking on a stdin read.
#    `exec </dev/null` on this shell propagates to whatever timeout
#    wrapper and to codex itself (stdin inheritance chain).
# 2. A wall-clock timeout so a stuck codex (0-CPU hang past the typical
#    2-5 min range) exits 124 cleanly instead of leaving the operator
#    staring at a hung spinner indefinitely. Default 1200s = 20 min
#    (~4× the documented upper bound); overridable via CODEX_TIMEOUT.
exec </dev/null

codex_timeout="${CODEX_TIMEOUT:-1200}"

# Prefer GNU timeout (Linux native, macOS via `brew install coreutils`
# either as `timeout` or `gtimeout`). Fall back to a Python wrapper that
# matches GNU timeout's exit-124-on-timeout convention — Python 3 is
# always available on dev machines and `subprocess.run(..., timeout=)`
# has been in stdlib since 3.3.
if command -v timeout >/dev/null 2>&1; then
    exec timeout --foreground "${codex_timeout}s" codex "${args[@]}" "$prompt"
elif command -v gtimeout >/dev/null 2>&1; then
    exec gtimeout --foreground "${codex_timeout}s" codex "${args[@]}" "$prompt"
else
    exec python3 -c '
import subprocess, sys
t = int(sys.argv[1])
try:
    sys.exit(subprocess.run(sys.argv[2:], timeout=t).returncode)
except subprocess.TimeoutExpired:
    sys.exit(124)
' "${codex_timeout}" codex "${args[@]}" "$prompt"
fi
