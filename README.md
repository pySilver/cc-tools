# cc-tools

[![CI](https://github.com/pySilver/cc-tools/actions/workflows/ci.yml/badge.svg)](https://github.com/pySilver/cc-tools/actions/workflows/ci.yml)

A personal collection of [Claude Code](https://claude.ai/code) agents and skills, packaged as a marketplace of small, single-purpose plugins.

This is an opinionated set — it's the toolbox I actually use, grouped by what each tool is *for* rather than what it *is*. A few of these are honestly tuned to my own projects (Python/Django, an ADR + plan + exec workflow, a Context7 MCP), so they won't all drop cleanly into a different setup. I've flagged that per plugin below. Even where a tool doesn't fit you as-is, it might give you ideas for building your own.

## Install

Add the marketplace, then install the plugins you want:

    /plugin marketplace add pySilver/cc-tools

    /plugin install planning@silver-cc-tools
    /plugin install code-review@silver-cc-tools
    /plugin install git@silver-cc-tools
    /plugin install research@silver-cc-tools
    /plugin install basedpyright-lsp@silver-cc-tools

Test a plugin locally before installing:

    claude --plugin-dir plugins/planning

Validate the marketplace and a plugin:

    claude plugin validate .
    claude plugin validate ./plugins/planning

After install, components are namespaced by plugin: skills are invoked as `/planning:refine-plan-against-codex`, `/code-review:code-hygiene`, `/git:finalize-feature-branch`, `/research:web-research`. The `adr-review` agent is picked up automatically (or when you ask for it by name). `basedpyright-lsp` has no command to invoke — it registers a language server that activates automatically when you open a `.py`/`.pyi` file.

<details>
<summary>Manual install (alternative)</summary>

Copy the files you want straight into your Claude Code config directory. Agents go under `~/.claude/agents/`, skills under `~/.claude/skills/`. Restart Claude Code afterward.

**planning** — `adr-review` agent + `refine-plan-against-codex` skill:
```bash
cp plugins/planning/agents/adr-review.md ~/.claude/agents/
cp -r plugins/planning/skills/refine-plan-against-codex ~/.claude/skills/
chmod +x ~/.claude/skills/refine-plan-against-codex/references/*.sh \
         ~/.claude/skills/refine-plan-against-codex/references/state.py
```

**code-review** — `code-hygiene` skill:
```bash
cp -r plugins/code-review/skills/code-hygiene ~/.claude/skills/
```

**git** — `finalize-feature-branch` skill:
```bash
cp -r plugins/git/skills/finalize-feature-branch ~/.claude/skills/
```

**research** — `web-research` skill:
```bash
cp -r plugins/research/skills/web-research ~/.claude/skills/
```

**basedpyright-lsp** — there's nothing to copy: a language server isn't a skill or agent, so it can't be dropped into `~/.claude`. Load it as a plugin directory instead:
```bash
claude --plugin-dir plugins/basedpyright-lsp
```

Note: installed manually, skills lose the `plugin:` namespace — invoke them by bare name (`/refine-plan-against-codex`, `/code-hygiene`, etc.).

</details>

## Updating

Plugin versions are intentionally omitted from the manifests, so every commit to this repo is a new version. The `/plugin` menu has two update paths:

- `/plugin` → **Marketplaces** → **Update marketplace** — pulls the latest catalog from the repo immediately. The reliable way to get updates.
- `/plugin` → **Installed** → **Update now** — uses a local cache that can lag. Use it as a fallback after updating the marketplace.

Enable `/plugin` → **Marketplaces** → **Enable auto-update** to refresh the catalog on each session start.

## Plugins

| Plugin | Description |
|--------|-------------|
| [planning](#planning) | Pre-code design gates — ADR review + iterative plan hardening against Codex |
| [code-review](#code-review) | Find agentic code smells: needless complexity and AI-speak docstrings/comments |
| [git](#git) | Finalize a feature branch — rebase, squash to one commit, verify, push |
| [research](#research) | Grounded web research with source-quality discipline and inline citations |
| [basedpyright-lsp](#basedpyright-lsp) | Python LSP (basedpyright) for Claude — navigation + diagnostics, from the project's pinned venv |

### planning

Quality gates that run *before* code is written: review the decision (ADR), then harden the plan.

| Component | Trigger | Description |
|-----------|---------|-------------|
| agent | `adr-review` | Reviews an Architecture Decision Record for decision quality before a plan is built on it |
| skill | `/planning:refine-plan-against-codex <plan.md>` | Review → fix → review loop on a plan file until Codex stops finding issues |

**adr-review** — a read-only agent that reviews the *decision*, not the implementation. It checks an ADR is actually decided (no hedging), that alternatives are weighed honestly (no strawmen), that consequences include the downsides, and that load-bearing decisions respect project invariants. Every finding is tagged and tied to a specific ADR section; the verdict is APPROVE or NEEDS REVISION. If the ADR file is ambiguous, it lists `docs/adrs/` and asks rather than guessing.

> **Tuned for my setup.** It expects ADRs in `docs/adrs/YYYY-MM-DD-<task>.md` and reads project context from a `docs/adrs/*-dev-workflow.md`, the root `CLAUDE.md`, and `.claude/rules/*.md`. On a repo without those, it still reviews the ADR but the load-bearing checks lose their teeth. Adapt the paths in `agents/adr-review.md` to reuse it elsewhere.

**refine-plan-against-codex** — drives an iterative external review of a single implementation plan. Each round spawns two isolated subagents: one runs Codex against the plan and returns structured JSON findings, the other applies only those findings (strict scope, no drift). State and per-round commits live beside the plan; the loop terminates on a clean `approve` verdict, a no-op/stuck detection, or a 20-round cap. Run it *after* a plan draft exists and *before* execution.

> **Requirements:** the `codex` CLI on `PATH`, `python3`, and the plan in a git-tracked location. Codex is slow (2–5 min/round), so prefer running it unattended. Repo-agnostic otherwise; defaults to `docs/plans/*.md` (override with `PLAN_GLOB` or an explicit path).

### code-review

| Component | Trigger | Description |
|-----------|---------|-------------|
| skill | `/code-review:code-hygiene <app-path>` | Read-only scan for "agentic code smells" across a code app |

**code-hygiene** — finds code that is technically correct but needlessly complex, plus verbose, stale, or AI-speak docstrings and comments — the residue of AI review-fix loops. It discovers files, batches them, and runs parallel review agents that classify findings into 14 calibrated categories (tautological expressions, impossible-state guards, defensive dead code, comment-explains-WHAT-not-WHY, stale historical references, AI-speak, commented-out code, bare TODOs, and more). Output is a grouped, confidence-rated report. It is **read-only** — it reports for human review and never edits. TODO/FIXME markers are flagged, never deleted.

> **Tuned for my setup.** Built for Python/Django: it globs `.py` files, skips `migrations/` and tests, and several category exemptions assume Django models, Pydantic schemas, and `.claude/rules/` conventions. The category taxonomy is broadly useful, but the calibration is Python-specific.

### git

| Component | Trigger | Description |
|-----------|---------|-------------|
| skill | `/git:finalize-feature-branch [default-branch]` | Rebase onto the default branch, collapse to one commit, verify, optionally push |

**finalize-feature-branch** — takes an approved feature branch to exactly one commit ahead of the default branch. It detects the default branch (or asks), previews what will change, fetches and rebases (resolving clean conflicts, aborting on unclear ones), collapses multiple commits via `git reset --soft` + commit (never interactive rebase), proposes a commit message derived from the branch name, runs the project's tests/linter, then offers a `--force-with-lease` push. Each step confirms before acting. Repo-agnostic — plain git.

### research

| Component | Trigger | Description |
|-----------|---------|-------------|
| skill | `/research:web-research <question>` | Grounded web research with source-quality heuristics and inline citations |

**web-research** — answers questions from current, citable sources. It scopes the question, searches with precise terms (parallel queries for distinct angles), fetches primary sources with focused extraction, cross-checks claims that matter (versions, advisories, prices, breaking changes — one source is a lead, two is a fact), and cites sources inline. It prefers official docs, RFCs, and release notes over SEO aggregators and undated tutorials, and reports the answer rather than narrating the search.

> **Note:** prefers a Context7 MCP for library/framework docs and `gh` for GitHub URLs when available, falling back to plain web search otherwise.

### basedpyright-lsp

| Component | Trigger | Description |
|-----------|---------|-------------|
| lsp | opening a `.py`/`.pyi` file | Registers a [basedpyright](https://docs.basedpyright.com/) language server for Python |

**basedpyright-lsp** — gives Claude a Python language server (go-to-definition, find-references, hover, document/workspace symbols, call hierarchy, plus diagnostics) backed by **basedpyright**, the pyright fork. There's no command to run; the server starts when a Python file is opened.

**Why this exists.** Diagnostics are *already* covered twice over — by the editor's own LSP while a file is open, and by the git hook that runs basedpyright as the type-check gate at commit. What's missing is **navigation for Claude in terminal-only sessions** (no editor attached): jumping to a definition, finding references, walking a call hierarchy. That's this plugin's unique value. The catch is that diagnostics must not *disagree* with the gate, so the server is sourced from the **same pinned basedpyright** the gate uses rather than a global install that can drift to a different version.

It resolves the server binary in priority order, anchored to the project root (`${CLAUDE_PROJECT_DIR}`, falling back to cwd):

1. `<root>/.venv/bin/basedpyright-langserver` — the project's pinned basedpyright (matches the gate). **Preferred.**
2. `uv run --project <root> --no-sync basedpyright-langserver` — when a `pyproject.toml` exists and `uv` is on `PATH`; resolves the project env without activating it and without an implicit sync.
3. a global `basedpyright-langserver` on `PATH` — last resort (its version may differ from the project pin).
4. none found → exits non-zero with an install hint. It **never auto-installs** — adding basedpyright to the project's dev deps is your call, not the plugin's.

Replaces `pyright-lsp@claude-plugins-official` (which hardcodes `pyright-langserver` and looks it up on `PATH` only — it never finds a `basedpyright` that lives in a project venv). Disable any pyright/basedpyright LSP from another marketplace before enabling this one.

> **Tuned for my setup.** Assumes a project venv at `.venv/` and/or a `uv`-managed `pyproject.toml`, and a basedpyright type-check gate to agree with. On a non-uv project with no `.venv`, only the global fallback applies — adjust `bin/langserver.sh` for other layouts (Poetry, conda, a differently-named venv).

## Development

Most of this repo is markdown, but the `refine-plan-against-codex` skill ships real executable code, so it has tests under [`tests/`](tests/) — black-box bash for `state.py`'s CLI and `extract-sentinels.sh`, plus a Python `unittest` for `state.py`'s parser internals. They're hermetic (no network, `codex`, or git needed):

```bash
bash tests/test-planning-refine-state.sh
bash tests/test-planning-extract-sentinels.sh
python3 tests/test-planning-state.py
```

GitHub Actions runs them — plus frontmatter, `shellcheck`, and manifest checks — on every push and PR (see [`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

## License

MIT — see [LICENSE](LICENSE).
