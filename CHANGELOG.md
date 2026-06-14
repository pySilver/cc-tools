# Changelog

This repo ships independent Claude Code plugins that are intentionally version-less — every commit to the marketplace is a new version, so users on auto-update always track the latest. Entries are therefore anchored by **release date**, newest first, and grouped by plugin.

## Unreleased

### planning

- `refine-plan-against-codex`: add a **prose-drift arbiter gate** (gap-5) that stops the loop once Codex's findings turn editorial. From round 4 (env `REFINE_PLAN_ARBITER_FROM_ROUND`, default `4`) a third independent subagent reads the plan and classifies each finding as a real defect vs a prose nitpick — needed because Codex inflates wording critiques to `high` severity, so severity/confidence can't distinguish them. A round with no real `high`/`critical` defects auto-terminates as the new `completed_converged` state and prints a report naming exactly which findings were editorial (real `high`/`critical` always keep the loop alive); prose findings are also dropped from the implementer so they never mutate the plan. Set `REFINE_PLAN_ARBITER_FROM_ROUND=1` to arbiter every round or force one more round on an already-converged plan. `state.py` gains `record-arbiter-start`/`record-arbiter-end`, the `completed_converged` status, and an arbiter row in the summary table — all covered by the test suites. (The gate's decision logic lives in the orchestrator prose contract, like the skill's other gaps, so it is not unit-tested.)

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
