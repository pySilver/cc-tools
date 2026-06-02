#!/usr/bin/env bash
set -euo pipefail

# Resolve basedpyright-langserver, preferring the project's pinned install so the LSP's
# diagnostics match the type-check gate (a git hook runs the same basedpyright). A global
# install can drift to a different version and disagree with the gate, so it is last.
#
# Claude Code exports ${CLAUDE_PROJECT_DIR} to LSP server subprocesses, so anchor the
# project-relative lookups to it rather than betting on the launch cwd. Fall back to the
# current directory when it is unset (e.g. invoking this script by hand).
root="${CLAUDE_PROJECT_DIR:-$PWD}"

# 1. project venv — same pinned basedpyright the type-check gate uses [preferred]
if [ -x "${root}/.venv/bin/basedpyright-langserver" ]; then
  exec "${root}/.venv/bin/basedpyright-langserver" "$@"
fi

# 2. uv-managed project env — resolve it without activation and without an implicit sync
if command -v uv >/dev/null 2>&1 && [ -f "${root}/pyproject.toml" ]; then
  exec uv run --project "${root}" --no-sync basedpyright-langserver "$@"
fi

# 3. global fallback (version may differ from the project pin)
if command -v basedpyright-langserver >/dev/null 2>&1; then
  exec basedpyright-langserver "$@"
fi

echo "[basedpyright-lsp] basedpyright-langserver not found." >&2
echo "  Add basedpyright to the project's dev deps (preferred), or: uv tool install basedpyright" >&2
exit 1
