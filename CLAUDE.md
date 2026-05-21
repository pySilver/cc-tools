# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A **Claude Code plugin marketplace** — a catalog, not an application. It distributes the author's personal agents and skills as installable plugins. There is no build step and no application runtime; the "code" is plugin manifests plus skill/agent markdown (and a few helper scripts inside one skill).

## Architecture

- `.claude-plugin/marketplace.json` (repo root) is the catalog. Its `name` is `cc-tools`; each entry in `plugins[]` points at a plugin via a **relative `source` path** (`./plugins/<name>`). Relative sources only resolve when the marketplace is added from git (e.g. `pySilver/cc-tools`), not from a raw `marketplace.json` URL.
- Each plugin lives in `plugins/<name>/` with its own `.claude-plugin/plugin.json` and an `agents/` and/or `skills/` directory. Plugins are grouped **by domain**, not by component type:
  - `planning` — `adr-review` agent + `refine-plan-against-codex` skill (pre-code design gates)
  - `code-review` — `code-hygiene` skill
  - `git` — `finalize-feature-branch` skill
  - `research` — `web-research` skill
- Skills are `skills/<skill>/SKILL.md` (YAML frontmatter: `name`, `description`, optional `allowed-tools`, `model`, `disable-model-invocation`). Agents are `agents/<agent>.md` (frontmatter: `name`, `description`, `model`, `tools`, `color`).
- After install, skills are namespaced as `/<plugin>:<skill>` (e.g. `/code-review:code-hygiene`); agents are referenced by bare name (`adr-review`).

## Load-bearing invariant: plugins are intentionally version-less

The `plugin.json` files **deliberately omit `version`**. For a git-hosted marketplace this means *every commit is a new version*, so users on auto-update always track the latest. Consequences to respect:

- **Do not add a `version` field** unless deliberately switching to pinned releases — and if you do, you must bump it on *every* release or installed users will never see updates (Claude Code skips a plugin whose version is unchanged).
- `CHANGELOG.md` is therefore **date-anchored, newest first** (not version-headed like typical changelogs). New work goes under `## Unreleased`, grouped by plugin.

## When adding or changing a plugin/skill/agent

Four things must stay in sync — changing the files alone is not enough:

1. the plugin directory under `plugins/<name>/`
2. the `plugins[]` array in `.claude-plugin/marketplace.json`
3. `README.md` — the plugins overview table **and** the per-plugin section
4. `CHANGELOG.md` — an entry under `## Unreleased`

## Commands

```bash
# Validate the marketplace manifest (checks marketplace.json only)
claude plugin validate .

# Validate a single plugin (checks plugin.json + skill/agent frontmatter)
claude plugin validate ./plugins/<name>

# Run/test a plugin locally without installing it
claude --plugin-dir plugins/<name>

# Install path for end users
/plugin marketplace add pySilver/cc-tools
/plugin install <name>@cc-tools
```

The "no version specified" warning from `claude plugin validate ./plugins/<name>` is expected and intended — see the version-less invariant above.

## Testing

The one substantial piece of executable code — `refine-plan-against-codex`'s `state.py` plus its `extract-sentinels.sh` — has a flat `tests/` suite of black-box bash scripts (assert helpers + hermetic `mktemp -d` dirs) and one Python `unittest` file for `state.py`'s parse internals. All tests are hermetic: no network, no `codex`, no git required.

```bash
bash tests/test-planning-refine-state.sh        # state.py CLI lifecycle (init/resume/record/detect-stuck/summary/finalize)
bash tests/test-planning-extract-sentinels.sh   # extract-sentinels.sh behavior
python3 tests/test-planning-state.py            # parse_findings / _actionable / derive_slug
```

`state.py` is **execute-only and not modified by the tests** — the Python test imports it read-only by path via `importlib`; the bash test isolates state with `REFINE_PLAN_STATE_ROOT`. `.github/workflows/ci.yml` runs these on every push to `main` and on every PR, alongside markdown-frontmatter validation, `shellcheck`, and a portable manifest check (the `claude` CLI isn't on GH runners).

## Bundled tools assume the author's external projects — do not "generalize" them unasked

Several tools hardcode conventions from the author's own repos. These paths are intentional, not bugs:

- `adr-review` reads `docs/adrs/YYYY-MM-DD-*.md`, a `docs/adrs/*-dev-workflow.md`, and `.claude/rules/*.md`.
- `code-hygiene` is Python/Django-specific (globs `.py`, skips `migrations/`, has Django/Pydantic exemptions).
- `web-research` prefers a Context7 MCP and `gh` when present.
- `refine-plan-against-codex` requires the `codex` CLI and `python3`, and its `references/*.sh` + `state.py` are **execute-only** — do not read them into context during a run; their contracts live in `references/README.md`.

## Repo hygiene

`.gitignore` excludes `.claude/` (local Claude Code state, including `settings.local.json`) and `.DS_Store`. The `.claude-plugin/` directories are *not* ignored — they are the manifests.
