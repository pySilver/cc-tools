#!/usr/bin/env bash
set -euo pipefail

# Resolve pyrefly, preferring the project's pinned install so the LSP's diagnostics match the
# type-check gate (`pyrefly check` in CI or a git hook). A global install can drift to a
# different version and disagree with the gate, so it is last.
#
# Claude Code exports ${CLAUDE_PROJECT_DIR} to LSP server subprocesses, so anchor the
# project-relative lookups to it rather than betting on the launch cwd. Fall back to the
# current directory when it is unset (e.g. invoking this script by hand).
root="${CLAUDE_PROJECT_DIR:-$PWD}"

# pyrefly discovers both its config (pyrefly.toml / pyproject.toml) and a project-root venv by
# walking up from the cwd, and the LSP subprocess cwd is undocumented — pin it to the root.
cd "$root" || {
  echo "[pyrefly-lsp] project root not found: ${root}" >&2
  exit 1
}

# 1. project venv — same pinned pyrefly the type-check gate uses [preferred]
if [ -x "${root}/.venv/bin/pyrefly" ]; then
  exec "${root}/.venv/bin/pyrefly" "$@"
fi

# 2. uv-managed project env — resolve it without activation and without an implicit sync
if command -v uv >/dev/null 2>&1 && [ -f "${root}/pyproject.toml" ]; then
  exec uv run --project "${root}" --no-sync pyrefly "$@"
fi

# 3. global fallback (version may differ from the project pin)
if command -v pyrefly >/dev/null 2>&1; then
  exec pyrefly "$@"
fi

echo "[pyrefly-lsp] pyrefly not found." >&2
echo "  Add pyrefly to the project's dev deps (preferred), or: uv tool install pyrefly" >&2
exit 1
