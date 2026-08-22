# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A **Claude Code plugin marketplace** — a catalog, not an application. It distributes the author's personal agents and skills as installable plugins. There is no build step and no application runtime; the "code" is plugin manifests plus skill/agent markdown (and a few helper scripts inside one skill).

## Architecture

- `.claude-plugin/marketplace.json` (repo root) is the catalog. Its `name` is `silver-cc-tools`; each entry in `plugins[]` points at a plugin via a **relative `source` path** (`./plugins/<name>`). Relative sources only resolve when the marketplace is added from git (e.g. `pySilver/cc-tools`), not from a raw `marketplace.json` URL.
- Each plugin lives in `plugins/<name>/` with its own `.claude-plugin/plugin.json` and an `agents/`, `skills/`, and/or `output-styles/` directory. Plugins are grouped **by domain**, not by component type:
  - `decide` — `interview-me`, `check-likelihood`, `brief` skills (decision gates: a human has to make a call)
  - `code-review` — `code-hygiene` skill
  - `git` — `finalize-feature-branch` skill
  - `research` — `web-research` skill
  - `tracking` — `backlog`, `status-board` skills
  - `basedpyright-lsp` / `pyrefly-lsp` — one `.lsp.json` each, no skill or agent
  - `output-styles` — the `Direct` output style (the one exception to by-domain grouping: a style is a system-prompt change with no domain, so it is grouped by component type)
- **Every `plugin.json` here is metadata only — component paths are auto-discovered, never declared.** A manifest listing no `skills`/`agents`/`outputStyles` field is correct, not broken: those fields *replace* the default `skills/`, `agents/`, `output-styles/` directories, so adding one that points at the default path is a no-op. Don't "fix" a manifest by declaring what is already found.
- Skills are `skills/<skill>/SKILL.md` (YAML frontmatter: `name`, `description`, optional `allowed-tools`, `model`, `disable-model-invocation`). Agents are `agents/<agent>.md` (frontmatter: `name`, `description`, `model`, `tools`, `color`).
- After install, skills are namespaced as `/<plugin>:<skill>` (e.g. `/code-review:code-hygiene`); agents are referenced by bare name. `disable-model-invocation: true` (used by `finalize-feature-branch`) blocks *Claude* from auto-triggering a skill — the user's `/<plugin>:<skill>` still resolves and runs.

## Output styles ship as a plugin, not a symlink

`output-styles/` **is** an official plugin component type (default dir `output-styles/`, manifest override `outputStyles`), so `plugins/output-styles/output-styles/direct.md` is a normal plugin like any other — it gets a `plugin.json`, a `plugins[]` entry, and the full four-way sync below. Do not reintroduce the old symlink-into-`~/.claude/output-styles/` install path.

Two things about output styles that differ from skills:

- The style's name in the `/config` picker comes from its frontmatter `name:` (`Direct`), **not** from the file name or the plugin name. Output styles are not namespaced by plugin.
- `force-for-plugin: true` would apply the style automatically to anyone who enables the plugin, overriding their own `outputStyle` setting. It is deliberately unset — enabling the plugin offers the style, it does not impose it.

## Load-bearing invariant: plugins are intentionally version-less

The `plugin.json` files **deliberately omit `version`**. For a git-hosted marketplace this means *every commit is a new version*, so users on auto-update always track the latest. Consequences to respect:

- **Do not add a `version` field** unless deliberately switching to pinned releases — and if you do, you must bump it on *every* release or installed users will never see updates (Claude Code skips a plugin whose version is unchanged).
- `CHANGELOG.md` is therefore **date-anchored, newest first** (not version-headed like typical changelogs). New work goes under `## Unreleased`, grouped by plugin.

## When adding or changing a plugin/skill/agent/output-style

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
/plugin install <name>@silver-cc-tools
```

The "no version specified" warning from `claude plugin validate ./plugins/<name>` is expected and intended — see the version-less invariant above.

## Testing

The one piece of executable code — `check-likelihood`'s `run-codex.sh` wrapper — has a black-box bash test under `tests/` (assert helpers + a hermetic `mktemp -d` dir). It is hermetic: no network, no `codex`, no git required, since the test stubs `codex` and `git` on `PATH`.

```bash
bash tests/test-decide-run-codex.sh           # run-codex.sh model default + CODEX_MODEL/CODEX_NO_OVERRIDES overrides
```

Skill *behaviour* — what a model actually does when a skill loads — is covered by eval cases instead, in the native `claude plugin eval` format at `plugins/<name>/evals/<case>/case.yaml` (schema 1.1). Only `planning` has them so far. They are **not** in CI (they cost money and need a live agent):

```bash
claude plugin eval decide@silver-cc-tools                    # adds no-plugin baseline arm
claude plugin eval ./plugins/decide --ablation with-without  # path target needs the flag
```

When adding cases for a skill whose risk is *over-firing*, write the negative cases too — a suite that only checks the shape appears will score an over-firing skill as perfect. See `plugins/decide/evals/README.md`.

`run-codex.sh` is **execute-only and not modified by its test** — the test stubs `codex` and `git` on `PATH` and asserts the invocation shape. `.github/workflows/ci.yml` runs it on every push to `main` and on every PR, alongside markdown-frontmatter validation, `shellcheck`, and a portable manifest check (the `claude` CLI isn't on GH runners).

## Bundled tools assume the author's external projects — do not "generalize" them unasked

Several tools hardcode conventions from the author's own repos. These paths are intentional, not bugs:

- `code-hygiene` is Python/Django-specific (globs `.py`, skips `migrations/`, has Django/Pydantic exemptions).
- `web-research` prefers a Context7 MCP and `gh` when present.
- `check-likelihood`'s optional Codex escalation requires the `codex` CLI, and its `references/run-codex.sh` is **execute-only** — do not read it into context during a check; its contract lives in `references/README.md`.

## Repo hygiene

`NOTICE` at the repo root carries the attributions that vendored MIT work requires — currently `decide/interview-me` and `tracking/backlog`. When adopting a skill from another repo, add its notice there and say in the skill's own README prose what was changed, rather than presenting adapted work as original.

`.gitignore` excludes `.claude/` (local Claude Code state, including `settings.local.json`) and `.DS_Store`. The `.claude-plugin/` directories are *not* ignored — they are the manifests.
