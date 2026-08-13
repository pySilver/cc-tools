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
    /plugin install pyrefly-lsp@silver-cc-tools
    /plugin install tracking@silver-cc-tools
    /plugin install output-styles@silver-cc-tools

Test a plugin locally before installing:

    claude --plugin-dir plugins/planning

Validate the marketplace and a plugin:

    claude plugin validate .
    claude plugin validate ./plugins/planning

After install, components are namespaced by plugin: skills are invoked as `/planning:refine-plan-against-codex`, `/code-review:code-hygiene`, `/git:finalize-feature-branch`, `/research:web-research`. The `adr-review` agent is picked up automatically (or when you ask for it by name). `basedpyright-lsp` and `pyrefly-lsp` have no command to invoke — each registers a language server that activates automatically when you open a `.py`/`.pyi` file. They claim the same extensions, so **enable only one**: with both on, the first server registered wins and the other never starts. `output-styles` has no command either — it adds **Direct** to the `/config` → **Output style** picker, where you select it.

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

**output-styles** — the `Direct` output style:
```bash
cp plugins/output-styles/output-styles/direct.md ~/.claude/output-styles/
```

**basedpyright-lsp** / **pyrefly-lsp** — there's nothing to copy: a language server isn't a skill or agent, so it can't be dropped into `~/.claude`. Load one as a plugin directory instead:
```bash
claude --plugin-dir plugins/basedpyright-lsp
# or
claude --plugin-dir plugins/pyrefly-lsp
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
| [planning](#planning) | Pre-code design gates — ADR review, plan hardening against Codex, risk triage, decision briefs |
| [code-review](#code-review) | Find agentic code smells: needless complexity and AI-speak docstrings/comments |
| [git](#git) | Finalize a feature branch — rebase, squash to one commit, verify, push |
| [research](#research) | Grounded web research with source-quality discipline and inline citations |
| [basedpyright-lsp](#basedpyright-lsp) | Python LSP (basedpyright) for Claude — navigation + diagnostics, from the project's pinned venv |
| [pyrefly-lsp](#pyrefly-lsp) | Same, backed by [pyrefly](https://pyrefly.org/) instead — pick whichever your type-check gate runs |
| [tracking](#tracking) | Standing issue register (`docs/issues/`) + one project status board (`docs/STATUS.md`) |
| [output-styles](#output-styles) | **Direct** — peer-to-peer tone, plain English, choice-first, diagrams-first |

### planning

Quality gates that run *before* code is written: review the decision (ADR), then harden the plan — plus two tools for the moment a gate hands something back to you, one to test whether a raised risk is real and one to make the resulting fork readable.

| Component | Trigger | Description |
|-----------|---------|-------------|
| agent | `adr-review` | Reviews an Architecture Decision Record for decision quality before a plan is built on it |
| skill | `/planning:refine-plan-against-codex <plan.md>` | Hunt once, then verify-only rounds until every finding is confirmed fixed |
| skill | `/planning:check-likelihood [claim]` | Adjudicates one raised risk — how likely is it here, and is it worth the fork it justifies |
| skill | `/planning:decision-brief` | Rebuilds your context before you pick — one concrete failing run, why it became possible, the forks replayed against it, pointers last |

**adr-review** — a read-only agent that reviews the *decision*, not the implementation. It checks an ADR is actually decided (no hedging), that alternatives are weighed honestly (no strawmen), that consequences include the downsides, and that load-bearing decisions respect project invariants. Every finding is tagged and tied to a specific ADR section, and every Critical/Important finding carries a **materialization** score (0–1: how likely the flagged problem actually bites) plus the condition that triggers it — below 0.30 a finding is demoted to FYI and a Critical needs ≥ 0.50, so the review can't hold up a decision on true-but-never-happens findings. A condition the reviewer can name but cannot check is marked `unverified` rather than scored, which keeps the decision open instead of burying the finding at the floor. The verdict is APPROVE or NEEDS REVISION. If the ADR file is ambiguous, it lists `docs/adrs/` and asks rather than guessing.

> **Tuned for my setup.** It expects ADRs in `docs/adrs/YYYY-MM-DD-<task>.md` and reads project context from a `docs/adrs/*-dev-workflow.md`, the root `CLAUDE.md`, and `.claude/rules/*.md`. On a repo without those, it still reviews the ADR but the load-bearing checks lose their teeth. Adapt the paths in `agents/adr-review.md` to reuse it elsewhere.

**refine-plan-against-codex** — drives an external review of a single implementation plan, structured so that it **ends**. Round 1 hunts: a subagent runs Codex against the whole plan and returns structured JSON findings, an independent **arbiter** subagent classifies each one real-defect vs prose-nitpick and re-scores it blind, and what survives becomes a fixed list. Every round after that only **verifies** — scoped to the diff of the previous round's fixes, one question per open finding (is this addressed, yes or no), and structurally unable to add to the list. Anything else Codex notices goes to `parked[]`, reported at the end and never fixed inside the loop.

That shape is the point. A full re-review every round does not converge: "find what's wrong" is unbounded, each fix is new text to criticize, and a memory-wiped re-review resamples the artifact instead of working down a list. Measured on one plan (2026-08-04), worst-finding severity by round ran 0.42 → 0.48 → 0.86 — *rising*, because each round's best finding attacked the previous round's fix. Verify rounds keep that signal (they read exactly that diff, so a fix that reintroduces its own finding comes back `fixed: false`) and drop the part that made the loop endless. The open list only shrinks, so termination is by construction: `completed_verified` when it empties, `completed_cap` at the round budget (default 4, `REFINE_PLAN_MAX_ROUNDS`).

Findings carry two orthogonal scores — `confidence` ("is this claim true?") and **materialization** ("if the plan ships as written, how likely is it that this actually bites?"). Codex self-scores both; the arbiter re-scores materialization without seeing Codex's number and overrides it. Below 0.30 a finding is recorded but never fixed; a real high/critical below 0.50 gets fixed but no longer keeps the loop alive. Each finding also carries a **cause** and a `fix_kind` — Codex must ask what decision makes the condition possible before proposing anything, and say whether its fix is a *guard* (a lock, retry, or branch that holds the symptom down) or a *design* change (the condition only exists because of a choice the plan already made). The arbiter re-answers that independently, because Codex has an incentive to say "guard": a guard is the smaller edit and stays inside the implementer's licence. Design-level findings never reach the implementer — restructuring a plan is the opposite of the minimum-scope edit that rule exists to enforce — so they go to you, with four options. State and per-round commits live beside the plan. Run it *after* a plan draft exists and *before* execution.

> **Requirements:** the `codex` CLI on `PATH`, `python3`, and the plan in a git-tracked location. Codex is slow (2–5 min/round), so prefer running it unattended. Repo-agnostic otherwise; defaults to `docs/plans/*.md` (override with `PLAN_GLOB` or an explicit path). The codex model defaults to `gpt-5.6-sol` — set `CODEX_MODEL=<name>` to override. Tune the round budget with `REFINE_PLAN_MAX_ROUNDS` (default `4`) and the materialization thresholds with `REFINE_PLAN_MATERIALIZATION_FLOOR` (default `0.3`, `0` disables filtering) and `REFINE_PLAN_MATERIALIZATION_GATE` (default `0.5`).

**check-likelihood** — the ad-hoc counterpart to the two gates above. An agent hands you a fork — *"decide between A and B, because X could happen"* — and X is often true and also never going to happen here; taking the fork buys permanent complexity to defend against nothing. Point this at the single claim. It writes the trigger condition ("this bites when…"), then hunts the artifact, `.claude/rules/`, the code, and the real scale for the invariant that settles it, and returns a materialization score with the `file:line` it relied on — a score with no quote is a guess wearing a number. A condition it can name but cannot check comes back `unverified` rather than scored, so a missing answer never quietly becomes a low one. When the claim is attached to a proposal it also prices the fork — cost now vs. cost if it fires vs. **cost of adding the guard later**, usually the deciding number — and lands on **revisit the decision** / simple path / take the fork / defer with a named signal to revisit / **cannot say yet**. Before pricing any guard it asks what decision made the condition possible — often the honest answer is that an earlier choice is the cause, and changing it removes the failure mode instead of guarding against it, so that verdict is offered even when the guard is cheap. `Cannot say yet` is the landing for an `unverified` score: without it the "never guess low" rule — right for scoring a risk — pushes the agent into taking the fork, and an unread file quietly becomes permanent complexity. On greenfield, where the code doesn't exist yet and nothing can be read, a silent plan is treated as a finding about the plan (name the sentence that would settle it) rather than an automatic `unverified`, so the tool doesn't become a source of paralysis. Read-only, and budgeted to a triage rather than an audit: **5 file reads**, counted rather than timed, because an agent can count files and cannot feel five minutes. It predicts the file list before opening anything, and when the evidence turns out to be spread over a dozen files it stops and offers to hand the read to a subagent — the cost of a big read isn't the wait, it's a dozen files landing in the planning context you were trying to protect. Separately, it offers a fresh adversarial subagent or a Codex cross-check when the score sits near a decision boundary or the fork is hard to reverse, but never spends those minutes without asking.

> **Reacts to skepticism.** Besides `/planning:check-likelihood`, it triggers on the way you'd actually push back — "how likely is that", "does that actually happen", "has that ever happened", "that sounds theoretical", "isn't that an edge case" — so doubting a risk an agent raised runs the check instead of starting an argument. No requirements beyond the repo itself; the optional Codex escalation reuses `refine-plan-against-codex`'s wrapper.

**decision-brief** — the format an agent should use when it hands a fork back to you. You wrote the design while fully focused; by the time an agent hits a judgement call three days later, the plan and the ADR are gone from your head, and a verdict built out of section names and internal terms asks you to reload a whole design from a pointer before you can read the question. This fixes the shape. First settle the problem — name the guard you reached for and what it leaves in place, run `/planning:check-likelihood` or a root-cause tool if one is available, and say plainly when the verdict is judgement rather than a checked result. Then five parts, in order: **the story** (one concrete run in time order, real values not variable names, ending badly, with one clause saying whether it was reproduced or derived — the two read identically and only one is evidence); **the step back** (2–5 lines: why this became possible, asking why until the answer is a decision someone made rather than a line of code, plus how far the same cause reaches — then landing on *local*, *design*, or *unknown*); **the forks** (two to four, cheapest first, each with its cost now *and* its cost if added later, each **replaying** the same story to its new ending, each labelled *removes the cause* or *guards only*); **the recommendation** (one option, one question, answerable in one word, plus an offer to expand any fork — offering to re-explain costs you nothing, a pointer asks you to go read); and **the pointers last**, one line, never inside the story.

The step back is what makes the menu safe to answer. A readable fork is still the wrong question when the fork itself is the artifact of an earlier bad split, and from inside a list of options you cannot tell which kind you are looking at — so the brief has to say it. When it lands on **design**, revising that decision *is* one of the forks, costed and replayed like the rest, and if it is genuinely off the table (shipped, needs a migration, the release is Friday) that line goes where the fork would have been rather than being omitted, which would let the menu imply it was never available. The "how far does it reach" clause is the other half: two options look equally reasonable until you know the same choice has four other exits nobody has hit yet. Both directions are errors — a step back that relabels the defect line as the cause tells you nothing, and one that manufactures a design flaw so the section has something to say is worse, so *local* ("the plan was right, this build diverged from it") is a one-line answer the format expects most of the time.

It deliberately does *not* fire for a failure the agent can fix itself, a yes/no on a step just described, work done in this session, or anything small and reversible — a five-part brief on a two-minute fork spends the attention the format exists to protect. Two send checks: could you pick an option without opening the plan, the ADR, or the code — and can you tell whether picking from this menu is patching over something? In Claude Code, the story, the step back, and the forks go in the message and the choice goes to `AskUserQuestion`, where each option description carries *what we do + cost + removes or guards* — an option description that is itself a pointer defeats the whole thing.

> **Pairs with the `Direct` output style** (the [output-styles](#output-styles) plugin below). The style already says lead with the answer and skip trailing summaries; this skill is the documented exception — the story leads, and the closing question is the next action rather than a recap. Repo-agnostic; `/planning:check-likelihood` is used when present and skipped when not. It has eval coverage under [`plugins/planning/evals/`](plugins/planning/evals/) — one case that it fires with the right shape, and **two that it stays quiet**, because the failure mode of this format is over-firing.

### code-review

| Component | Trigger | Description |
|-----------|---------|-------------|
| skill | `/code-review:code-hygiene <app-path>` | Read-only scan for "agentic code smells" across a code app |

**code-hygiene** — finds code that is technically correct but needlessly complex, plus verbose, stale, or AI-speak docstrings and comments — the residue of AI review-fix loops. It discovers files, batches them, and runs parallel review agents that classify findings into 14 calibrated categories (tautological expressions, impossible-state guards, defensive dead code, comment-explains-WHAT-not-WHY, stale historical references, AI-speak, commented-out code, bare TODOs, and more). Output is a grouped, confidence-rated report. It is **read-only** — it reports for human review and never edits. TODO/FIXME markers are flagged, never deleted.

> **Tuned for my setup.** Built for Python/Django: it globs `.py` files, skips `migrations/` and tests, and several category exemptions assume Django models, Pydantic schemas, and `.claude/rules/` conventions. The category taxonomy is broadly useful, but the calibration is Python-specific.

### git

| Component | Trigger | Description |
|-----------|---------|-------------|
| skill | `/git:finalize-feature-branch [default-branch]` | Rebase onto the default branch, collapse to one commit, verify, merge into the default branch and push |

**finalize-feature-branch** — takes an approved feature branch to exactly one commit ahead of the default branch. It detects the default branch (or asks), previews what will change, fetches and rebases (resolving clean conflicts, aborting on unclear ones), collapses multiple commits via `git reset --soft` + commit (never interactive rebase), proposes a commit message derived from the branch name, verifies, then lands the branch. Each step confirms before acting. Repo-agnostic — plain git.

Two things it is opinionated about:

- **Landing defaults to merge, not publish.** The first offer is fast-forward the branch into the default branch locally and `git push origin <default>`; publishing the feature branch with `--force-with-lease` is the second option, for when a PR is wanted. The default branch is never force-pushed, and a rejected push stops the run rather than escalating.
- **The full test suite is skipped when the rebase pulled in nothing but documentation** — and only then. `reset --soft` rewrites history, not the tree, so the only thing that can break a verified branch is incoming upstream work; the skill diffs the pre-fetch merge-base against the new default-branch tip to see exactly what that was. A resolved conflict, no passing suite earlier in the session, or a single unclassifiable file all force a full run. `.md` is not automatically documentation: files under `tests/`, `requirements*.txt`, doctested `.rst`, and repos that ship markdown *as source* are named as never-docs. Anything left unclassified prompts a question instead of a guess, and a skip is always reported with its reason.

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

### pyrefly-lsp

| Component | Trigger | Description |
|-----------|---------|-------------|
| lsp | opening a `.py`/`.pyi` file | Registers a [pyrefly](https://pyrefly.org/) language server for Python |

**pyrefly-lsp** — the same idea as `basedpyright-lsp`, backed by **pyrefly** (Meta's Rust-based Python type checker and language server) instead. Same discovery order, anchored to the project root (`${CLAUDE_PROJECT_DIR}`, falling back to cwd):

1. `<root>/.venv/bin/pyrefly` — the project's pinned pyrefly (matches the gate). **Preferred.**
2. `uv run --project <root> --no-sync pyrefly` — when a `pyproject.toml` exists and `uv` is on `PATH`.
3. a global `pyrefly` on `PATH` — last resort (its version may differ from the project pin).
4. none found → exits non-zero with an install hint. It **never auto-installs**.

Started as `pyrefly lsp` (pyrefly speaks stdio by default — no `--stdio` flag). Unlike the basedpyright wrapper, this one `cd`s to the project root first: pyrefly discovers both its config (`pyrefly.toml` / `[tool.pyrefly]`) and a project-root venv by walking up from the cwd, and the LSP subprocess cwd isn't documented.

**Which one?** Match whatever runs as your type-check gate — the point of both plugins is that Claude's diagnostics don't disagree with the thing that blocks your commit. Pyrefly is much faster and still moving quickly; basedpyright has the deeper rule set and the pyright-compatible config. Don't run both: they declare the same `.py`/`.pyi` extensions, so the first registered wins, the other silently never starts, and `/plugin` shows a warning naming the winner.

> **Tuned for my setup.** Same assumptions as `basedpyright-lsp`: a `.venv/` and/or a `uv`-managed `pyproject.toml`. Adjust `bin/langserver.sh` for Poetry, conda, or a differently-named venv.

### tracking

Where side-quest findings and the work queue live, so neither derails the current task nor evaporates. Born from a repo audit that found six "active" plans of which zero were actionable — the cure is one board with a WIP limit, plus a register for the findings that are real but not today's job.

| Component | Trigger | Description |
|-----------|---------|-------------|
| skill | `/tracking:log-issue` | Capture a finding just discussed into `docs/issues/` — one file per entry, index row, delete-on-decision; self-initializes the register on first use |
| skill | `/tracking:status-board` | Create or update `docs/STATUS.md` — executing now, the ordered queue, owner gates, parked-with-trigger; wires a pointer + two WIP rules into `CLAUDE.md` on init |

**log-issue** — a defect, open decision, or follow-up surfaces mid-conversation; this writes it into a standing register instead of letting it derail the work or vanish. Entries pass a three-part admission gate (real and re-derivable from code; needs an owner decision or is deliberately deferred; not owned by a dated review — those keep their own registers), get a subsystem-prefixed ID, minimal frontmatter (`issue | open_decision | future_work` — deliberately no severity taxonomy or status machine: presence means open), and a body written for a reader without the conversation: the concrete failure run with real values, the misreading to prevent, options with costs, a recommendation. Files and symbols are cited, never line numbers (those rot). Entries are **deleted on resolution** — the outcome lives in the ADR, plan, or commit that records it; a resolved entry left in place reads as still-open. The project's own `docs/issues/README.md` is the authoritative contract: if a repo evolves its register format, the skill follows the repo, not its bundled template.

**status-board** — one screen answering "what is the state of this project": *Executing now* (max 1), *Next* (ordered), *Gated on owner*, *Parked* (every item carries a named re-entry trigger — a parked item with no trigger is forgetting with extra steps). The board carries **pointers, never copies** — a queue line links its ADR/plan/issue; the issue register gets one pointer line, never mirrored entries. Two standing rules ride with it and get wired into `CLAUDE.md` at init: a plan is written and refined only at queue front and executed immediately after (a refined-plan inventory is what rots), and the plans directory holds at most 2 files. Initialization reads the repo's actual state (plans dir, recent commits, any existing tracker) and **confirms the queue order with you before writing** — ordering is an owner decision. Update mode moves items between sections, keeps every line a pointer, and shows the diff.

> **Tuned for my setup.** Assumes the `docs/` layout (`docs/issues/`, `docs/plans/`, `docs/STATUS.md`, dated reviews under `docs/reviews/<date>/`) and a root `CLAUDE.md` to wire the board into. The register/board shapes are project-agnostic otherwise.

### output-styles

| Component | Trigger | Description |
|-----------|---------|-------------|
| output style | `/config` → **Output style** → **Direct** | Peer-to-peer tone, plain English, choice-first, diagrams-first |

Ships [`direct.md`](plugins/output-styles/output-styles/direct.md) as a Claude Code [output style](https://code.claude.com/docs/en/output-styles) — a system-prompt modification, not a skill, so there's nothing to invoke. Install the plugin, then pick **Direct** under `/config` → **Output style** (or set `"outputStyle": "Direct"` in a settings file). It takes effect on the next `/clear` or session, since the system prompt is read once at session start. `keep-coding-instructions: true` is set, so Claude's built-in software-engineering instructions stay in place and this layers on top.

`force-for-plugin` is deliberately **not** set: enabling the plugin offers the style, it doesn't impose it. If you want it applied automatically everywhere, add `force-for-plugin: true` to the frontmatter of your own copy — it overrides the user's `outputStyle` setting, which is why it isn't the shipped default.

**Direct** sets the working relationship first: Claude and I are both senior engineers, so it is told to hold its own opinion, disagree openly, challenge a wrong premise, and never soften a real problem — the point is to stop the model from treating me as an authority it can't argue with. On top of that: plain English and short replies, concrete `A:`/`B:` choices instead of guessing intent or pre-deciding, and a lead-with-a-diagram rule for anything structural (ASCII in chat, Mermaid in files and Artifacts, since chat clients don't render Mermaid).

A **Scope** section bounds all of it: these rules shape text written *for me to read*, and nothing else. Subagent prompts, plans, ADRs, commit messages, and anything under `docs/` keep full detail — exact errors, `file:line`, provenance, stated uncertainty. Brevity applied to text another agent consumes is information loss that never reaches a human to be noticed. Same axis as the diagram rule: the destination decides, not the topic.

> **Editing it.** Unlike a `SKILL.md`, an output style is part of the system prompt: edits need `/reload-plugins` (or a restart) *and* a `/clear` before they show up. To iterate on a fork of it without installing, run `claude --plugin-dir plugins/output-styles`.

## Development

Most of this repo is markdown, but the `refine-plan-against-codex` skill ships real executable code, so it has tests under [`tests/`](tests/) — black-box bash for `state.py`'s CLI, `extract-sentinels.sh`, and the `run-codex.sh` wrapper (`codex` and `git` are PATH stubs), plus a Python `unittest` for `state.py`'s parser internals. They're hermetic (no network, `codex`, or git needed):

```bash
bash tests/test-planning-refine-state.sh
bash tests/test-planning-extract-sentinels.sh
bash tests/test-planning-run-codex.sh
python3 tests/test-planning-state.py
```

GitHub Actions runs them — plus frontmatter, `shellcheck`, and manifest checks — on every push and PR (see [`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

Behaviour that only shows up when a model reads a skill is covered by eval cases instead, in the native `claude plugin eval` format under a plugin's own `evals/` directory ([`plugins/planning/evals/`](plugins/planning/evals/) so far):

```bash
claude plugin eval planning@silver-cc-tools        # + no-plugin baseline arm
claude plugin eval ./plugins/planning --ablation with-without
```

These are not in CI — they cost money and need a live agent. Targeting a plugin by name adds the baseline arm automatically; a path target needs `--ablation with-without`, and without a baseline a score says nothing about whether the skill changed anything.

## License

MIT — see [LICENSE](LICENSE).
