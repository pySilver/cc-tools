# Changelog

This repo ships independent Claude Code plugins that are intentionally version-less — every commit to the marketplace is a new version, so users on auto-update always track the latest. Entries are therefore anchored by **release date**, newest first, and grouped by plugin.

## Unreleased

### basedpyright-lsp

- add `basedpyright-lsp` plugin — registers a [basedpyright](https://docs.basedpyright.com/) Python language server for Claude (navigation + diagnostics) via a discovery wrapper that prefers the project's pinned `.venv` install over `uv run --no-sync`, then a global binary; never auto-installs. Self-hosted replacement for `pyright-lsp@claude-plugins-official`, which can't find a basedpyright that lives in a project venv.

### Marketplace

- rename marketplace `cc-tools` → `silver-cc-tools` — avoids a name collision when adding; install is now `<plugin>@silver-cc-tools` (plugin names unchanged). Re-add the marketplace under the new name to keep getting updates.

### Tooling

- add test suite (`state.py` CLI + parse internals, `extract-sentinels`) and GitHub Actions CI (frontmatter, shellcheck, manifest validation, shell + python tests)

## 2026-05-21 — Initial release

First marketplace release. Agents and skills collected from `~/.claude` and packaged into four domain plugins.

### planning

- add `adr-review` agent — reviews an ADR for decision quality before a plan is built on it
- add `refine-plan-against-codex` skill — iterative review → fix → review loop on a plan file against Codex

### code-review

- add `code-hygiene` skill — read-only scan for agentic code smells and AI-speak docstrings/comments

### git

- add `finalize-feature-branch` skill — rebase onto default, collapse to one commit, verify, optionally push

### research

- add `web-research` skill — grounded web research with source-quality heuristics and inline citations
