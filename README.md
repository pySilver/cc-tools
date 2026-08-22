# cc-tools

[![CI](https://github.com/pySilver/cc-tools/actions/workflows/ci.yml/badge.svg)](https://github.com/pySilver/cc-tools/actions/workflows/ci.yml)

A personal collection of [Claude Code](https://claude.ai/code) agents and skills, packaged as a marketplace of small, single-purpose plugins.

This is an opinionated set — it's the toolbox I actually use, grouped by what each tool is *for* rather than what it *is*. A few of these are honestly tuned to my own projects (Python/Django, an ADR + plan + exec workflow, a Context7 MCP), so they won't all drop cleanly into a different setup. I've flagged that per plugin below. Even where a tool doesn't fit you as-is, it might give you ideas for building your own.

## Install

Add the marketplace, then install the plugins you want:

    /plugin marketplace add pySilver/cc-tools

    /plugin install decide@silver-cc-tools
    /plugin install code-review@silver-cc-tools
    /plugin install git@silver-cc-tools
    /plugin install research@silver-cc-tools
    /plugin install basedpyright-lsp@silver-cc-tools
    /plugin install pyrefly-lsp@silver-cc-tools
    /plugin install tracking@silver-cc-tools
    /plugin install output-styles@silver-cc-tools

Test a plugin locally before installing:

    claude --plugin-dir plugins/decide

Validate the marketplace and a plugin:

    claude plugin validate .
    claude plugin validate ./plugins/decide

After install, components are namespaced by plugin: skills are invoked as `/decide:check-likelihood`, `/code-review:code-hygiene`, `/git:finalize-feature-branch`, `/research:web-research`. `basedpyright-lsp` and `pyrefly-lsp` have no command to invoke — each registers a language server that activates automatically when you open a `.py`/`.pyi` file. They claim the same extensions, so **enable only one**: with both on, the first server registered wins and the other never starts. `output-styles` has no command either — it adds **Direct** to the `/config` → **Output style** picker, where you select it.

<details>
<summary>Manual install (alternative)</summary>

Copy the files you want straight into your Claude Code config directory. Agents go under `~/.claude/agents/`, skills under `~/.claude/skills/`. Restart Claude Code afterward.

**decide** — `interview-me` + `check-likelihood` + `brief` skills:
```bash
cp -r plugins/decide/skills/interview-me ~/.claude/skills/
cp -r plugins/decide/skills/check-likelihood ~/.claude/skills/
cp -r plugins/decide/skills/brief ~/.claude/skills/
chmod +x ~/.claude/skills/check-likelihood/references/run-codex.sh
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

Note: installed manually, skills lose the `plugin:` namespace — invoke them by bare name (`/check-likelihood`, `/code-hygiene`, etc.).

</details>

## Updating

Plugin versions are intentionally omitted from the manifests, so every commit to this repo is a new version. The `/plugin` menu has two update paths:

- `/plugin` → **Marketplaces** → **Update marketplace** — pulls the latest catalog from the repo immediately. The reliable way to get updates.
- `/plugin` → **Installed** → **Update now** — uses a local cache that can lag. Use it as a fallback after updating the marketplace.

Enable `/plugin` → **Marketplaces** → **Enable auto-update** to refresh the catalog on each session start.

## Plugins

| Plugin | Description |
|--------|-------------|
| [decide](#decide) | Pre-code design gates — intent interviews, risk triage, decision briefs |
| [code-review](#code-review) | Find agentic code smells: needless complexity and AI-speak docstrings/comments |
| [git](#git) | Finalize a feature branch — rebase, squash to one commit, verify, push |
| [research](#research) | Grounded web research with source-quality discipline and inline citations |
| [basedpyright-lsp](#basedpyright-lsp) | Python LSP (basedpyright) for Claude — navigation + diagnostics, from the project's pinned venv |
| [pyrefly-lsp](#pyrefly-lsp) | Same, backed by [pyrefly](https://pyrefly.org/) instead — pick whichever your type-check gate runs |
| [tracking](#tracking) | Deferred-work backlog (`docs/backlog/`) + one project status board (`docs/STATUS.md`) |
| [output-styles](#output-styles) | **Direct** — peer-to-peer tone, plain English, choice-first, diagrams-first |

### decide

Three tools for the stretch *before* any code is written: one to find out what you actually want, one to test whether a raised risk is real, and one to make the resulting fork readable.

| Component | Trigger | Description |
|-----------|---------|-------------|
| skill | `/decide:interview-me` | Extracts what you actually want — one question at a time, each carrying the agent's own guess, until it can predict your answers |
| skill | `/decide:check-likelihood [claim]` | Adjudicates one raised risk — how likely is it here, and is it worth the fork it justifies |
| skill | `/decide:brief` | Rebuilds your context before you pick — one concrete failing run, why it became possible, the forks replayed against it, pointers last |

**interview-me** — the gate before anything gets drafted. What people ask for and what they want are different things: "build me a dashboard" is the conventional phrasing, not the problem, and the gap between the two is free to close now and expensive to close after code exists. The mechanism is one question at a time with the agent's **own guess attached** — you react to a wrong hypothesis far faster than you compose an answer from scratch, and attaching the guess is what forces the agent to commit to an assumption it can be visibly wrong about instead of quietly building on it. It opens with a one-sentence read of what you want and an honest confidence number, and every number under ~70% has to say what is still missing, so the score is a request for specific help rather than a mood. It listens for **want vs. should want** — "scalable", "clean architecture", "the standard approach" are answers that sound like a thoughtful answer instead of being one, and they get one probe: *if you didn't have to justify this to anyone, what would you actually want?* It closes with a six-line restate (Outcome / User / Why now / Success / Constraint / **Out of scope**) and an explicit yes — "whatever you think is best" is delegation, "sounds good" is ambiguous, and silence is not confirmation, so each of those re-asks instead of terminating. The stop condition is checkable rather than a vibe: *can I predict your reaction to the next three questions I would ask?* — with a floor, so several rounds of flat confidence ends the interview and reports that something foundational is missing rather than grinding on.

> **Produces intent, not a document.** The deliverable is a confirmed statement of intent that an ADR, a brainstorm, or a planner then consumes; it deliberately writes no file by default and defers to the host project's documentation conventions if you want it persisted, rather than inventing a directory to hold it. Needs a live user — it declines to run in CI, `/loop`, or an unattended plan executor and flags the underspecified ask as a blocker instead of guessing. Adapted from [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) (MIT); see [`NOTICE`](NOTICE) for what was kept and what changed.

**check-likelihood** — the ad-hoc counterpart to a batch review gate. An agent hands you a fork — *"decide between A and B, because X could happen"* — and X is often true and also never going to happen here; taking the fork buys permanent complexity to defend against nothing. Point this at the single claim. It writes the trigger condition ("this bites when…"), then hunts the artifact, `.claude/rules/`, the code, and the real scale for the invariant that settles it, and returns a materialization score with the `file:line` it relied on — a score with no quote is a guess wearing a number. A condition it can name but cannot check comes back `unverified` rather than scored, so a missing answer never quietly becomes a low one. When the claim is attached to a proposal it also prices the fork — cost now vs. cost if it fires vs. **cost of adding the guard later**, usually the deciding number — and lands on **revisit the decision** / simple path / take the fork / defer with a named signal to revisit / **cannot say yet**. Before pricing any guard it asks what decision made the condition possible — often the honest answer is that an earlier choice is the cause, and changing it removes the failure mode instead of guarding against it, so that verdict is offered even when the guard is cheap. `Cannot say yet` is the landing for an `unverified` score: without it the "never guess low" rule — right for scoring a risk — pushes the agent into taking the fork, and an unread file quietly becomes permanent complexity. On greenfield, where the code doesn't exist yet and nothing can be read, a silent plan is treated as a finding about the plan (name the sentence that would settle it) rather than an automatic `unverified`, so the tool doesn't become a source of paralysis. Read-only, and budgeted to a triage rather than an audit: **5 file reads**, counted rather than timed, because an agent can count files and cannot feel five minutes. It predicts the file list before opening anything, and when the evidence turns out to be spread over a dozen files it stops and offers to hand the read to a subagent — the cost of a big read isn't the wait, it's a dozen files landing in the planning context you were trying to protect. Separately, it offers a fresh adversarial subagent or a Codex cross-check when the score sits near a decision boundary or the fork is hard to reverse, but never spends those minutes without asking.

> **Reacts to skepticism.** Besides `/decide:check-likelihood`, it triggers on the way you'd actually push back — "how likely is that", "does that actually happen", "has that ever happened", "that sounds theoretical", "isn't that an edge case" — so doubting a risk an agent raised runs the check instead of starting an argument. No requirements beyond the repo itself; the optional Codex escalation goes through its own `references/run-codex.sh` and needs the `codex` CLI.

**brief** — the format an agent should use when it hands a fork back to you. You wrote the design while fully focused; by the time an agent hits a judgement call three days later, the plan and the ADR are gone from your head, and a verdict built out of section names and internal terms asks you to reload a whole design from a pointer before you can read the question. This fixes the shape. First settle the problem — name the guard you reached for and what it leaves in place, run `/decide:check-likelihood` or a root-cause tool if one is available, and say plainly when the verdict is judgement rather than a checked result. Then five parts, in order: **the story** (one concrete run in time order, real values not variable names, ending badly, with one clause saying whether it was reproduced or derived — the two read identically and only one is evidence); **the step back** (2–5 lines: why this became possible, asking why until the answer is a decision someone made rather than a line of code, plus how far the same cause reaches — then landing on *local*, *design*, or *unknown*); **the forks** (two to four, cheapest first, each with its cost now *and* its cost if added later, each **replaying** the same story to its new ending, each labelled *removes the cause* or *guards only*); **the recommendation** (one option, one question, answerable in one word, plus an offer to expand any fork — offering to re-explain costs you nothing, a pointer asks you to go read); and **the pointers last**, one line, never inside the story.

The step back is what makes the menu safe to answer. A readable fork is still the wrong question when the fork itself is the artifact of an earlier bad split, and from inside a list of options you cannot tell which kind you are looking at — so the brief has to say it. When it lands on **design**, revising that decision *is* one of the forks, costed and replayed like the rest, and if it is genuinely off the table (shipped, needs a migration, the release is Friday) that line goes where the fork would have been rather than being omitted, which would let the menu imply it was never available. The "how far does it reach" clause is the other half: two options look equally reasonable until you know the same choice has four other exits nobody has hit yet. Both directions are errors — a step back that relabels the defect line as the cause tells you nothing, and one that manufactures a design flaw so the section has something to say is worse, so *local* ("the plan was right, this build diverged from it") is a one-line answer the format expects most of the time.

It deliberately does *not* fire for a failure the agent can fix itself, a yes/no on a step just described, work done in this session, or anything small and reversible — a five-part brief on a two-minute fork spends the attention the format exists to protect. Two send checks: could you pick an option without opening the plan, the ADR, or the code — and can you tell whether picking from this menu is patching over something? In Claude Code, the story, the step back, and the forks go in the message and the choice goes to `AskUserQuestion`, where each option description carries *what we do + cost + removes or guards* — an option description that is itself a pointer defeats the whole thing.

> **Pairs with the `Direct` output style** (the [output-styles](#output-styles) plugin below). The style already says lead with the answer and skip trailing summaries; this skill is the documented exception — the story leads, and the closing question is the next action rather than a recap. Repo-agnostic; `/decide:check-likelihood` is used when present and skipped when not. It has eval coverage under [`plugins/decide/evals/`](plugins/decide/evals/) — one case that it fires with the right shape, and **two that it stays quiet**, because the failure mode of this format is over-firing.

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
- **From a worktree it lands on the remote instead.** If another worktree holds the default branch, the local merge is impossible — `git checkout` and `git fetch . HEAD:<default>` both refuse — so the first offer becomes `git push origin HEAD:<default>`, the same fast-forward one hop earlier. It never rewrites the ref behind the other checkout's back, and afterwards it reports that worktree as behind, offering to fast-forward it only when it is clean.
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
| skill | `/tracking:backlog [slug]` | Read, work, and append deferred-work items in `docs/backlog/` — one slug-named file per item, `worth: yes/later/no`, no index, `git rm` in the fixing commit |
| skill | `/tracking:status-board` | Create or update `docs/STATUS.md` — executing now, the ordered queue, owner gates, parked-with-trigger; wires a pointer + two WIP rules into `CLAUDE.md` on init |

**backlog** — a defect, open decision, or follow-up surfaces mid-conversation; this writes it into `docs/backlog/` instead of letting it derail the work or vanish, and reads it back later. One file per item, named by a slug that names the defect (`reopen-fallback-ignores-frontmost.md`) so it can be cited from a commit and dedupe is a filename check; **no index file** — the directory listing is the index. Three frontmatter fields: `worth: yes | later | no` (the triage call the list is ordered by — `later` must name the unknown that would settle it, `no` is kept deliberately so the next review that touches the file does not rediscover and re-argue it), `where: path` or `path:symbol` (never a line number — those rot), and `added` (never updated, so it reads as age). Items pass a three-part admission gate (real and re-derivable from code; not being done now; not owned by a dated review) and the body is written for a reader without the conversation: the concrete run with real values, the misreading to prevent, options with costs plus a recommendation for a `later`, and provenance. Reading the list verifies every `where` against the tree and reports stale anchors as stale rather than as work, then offers fix-a-named-item / drop / leave via `AskUserQuestion`; `/tracking:backlog <slug>` jumps to one item. Appending dedupes on `where` then slug, refuses to write onto a non-default branch without asking (a note on a feature branch gets swept into that PR or dies with it), checks the index for pre-existing staged work before offering to commit, and offers commit and push together. No checkbox, no resolved state: the item is `git rm`'d in the commit that lands its fix. Adapted from [umputun/cc-thingz](https://github.com/umputun/cc-thingz) (MIT); see [`NOTICE`](NOTICE) for what was kept and what changed.

**status-board** — one screen answering "what is the state of this project": *Executing now* (max 1), *Next* (ordered), *Gated on owner*, *Parked* (every item carries a named re-entry trigger — a parked item with no trigger is forgetting with extra steps). The board carries **pointers, never copies** — a queue line links its ADR/plan/issue; the issue register gets one pointer line, never mirrored entries. Two standing rules ride with it and get wired into `CLAUDE.md` at init: a plan is written and refined only at queue front and executed immediately after (a refined-plan inventory is what rots), and the plans directory holds at most 2 files. Initialization reads the repo's actual state (plans dir, recent commits, any existing tracker) and **confirms the queue order with you before writing** — ordering is an owner decision. Update mode moves items between sections, keeps every line a pointer, and shows the diff.

> **Tuned for my setup.** Assumes the `docs/` layout (`docs/backlog/`, `docs/plans/`, `docs/STATUS.md`, dated reviews under `docs/reviews/<date>/`) and a root `CLAUDE.md` to wire the board into. The backlog/board shapes are project-agnostic otherwise. `backlog` is Git-only by design.

### output-styles

| Component | Trigger | Description |
|-----------|---------|-------------|
| output style | `/config` → **Output style** → **Direct** | Peer-to-peer tone, plain English, choice-first, diagrams-first |

Ships [`direct.md`](plugins/output-styles/output-styles/direct.md) as a Claude Code [output style](https://code.claude.com/docs/en/output-styles) — a system-prompt modification, not a skill, so there's nothing to invoke. Install the plugin, then pick **Direct** under `/config` → **Output style** (or set `"outputStyle": "Direct"` in a settings file). It takes effect on the next `/clear` or session, since the system prompt is read once at session start. `keep-coding-instructions: true` is set, so Claude's built-in software-engineering instructions stay in place and this layers on top.

`force-for-plugin` is deliberately **not** set: enabling the plugin offers the style, it doesn't impose it. If you want it applied automatically everywhere, add `force-for-plugin: true` to the frontmatter of your own copy — it overrides the user's `outputStyle` setting, which is why it isn't the shipped default.

**Direct** sets the working relationship first: Claude and I are both senior engineers, so it is told to hold its own opinion, disagree openly, challenge a wrong premise, and never soften a real problem — the point is to stop the model from treating me as an authority it can't argue with. On top of that: plain English and short replies, concrete `A:`/`B:` choices instead of guessing intent or pre-deciding, and a lead-with-a-diagram rule for anything structural (ASCII in chat, Mermaid in files and Artifacts, since chat clients don't render Mermaid).

An **AI tells** section bans the wording tics of model-generated prose — AI vocabulary ("delve", "pivotal", "leverage"), "not just X, but Y", forced groups of three, synonym cycling, hedge stacks, filler, inline-header bullets that restate their own line, abstract metaphor nouns, and feeling-words where the mechanism should be. Cherry-picked from Cursor's [unslop](https://github.com/cursor/plugins/blob/main/pstack/skills/unslop/SKILL.md) skill; the "add soul" half and the blanket em-dash ban were deliberately left behind.

A **Scope** section bounds all of it: these rules shape text written *for me to read*, and nothing else. Subagent prompts, plans, ADRs, commit messages, and anything under `docs/` keep full detail — exact errors, `file:line`, provenance, stated uncertainty. Brevity applied to text another agent consumes is information loss that never reaches a human to be noticed. Same axis as the diagram rule: the destination decides, not the topic.

> **Editing it.** Unlike a `SKILL.md`, an output style is part of the system prompt: edits need `/reload-plugins` (or a restart) *and* a `/clear` before they show up. To iterate on a fork of it without installing, run `claude --plugin-dir plugins/output-styles`.

## Development

Most of this repo is markdown, but `check-likelihood` ships one executable helper, so it has a test under [`tests/`](tests/) — black-box bash for the `run-codex.sh` wrapper, with `codex` and `git` as PATH stubs. It's hermetic (no network, `codex`, or git needed):

```bash
bash tests/test-decide-run-codex.sh
```

GitHub Actions runs it — plus frontmatter, `shellcheck`, and manifest checks — on every push and PR (see [`.github/workflows/ci.yml`](.github/workflows/ci.yml)).

Behaviour that only shows up when a model reads a skill is covered by eval cases instead, in the native `claude plugin eval` format under a plugin's own `evals/` directory ([`plugins/decide/evals/`](plugins/decide/evals/) so far):

```bash
claude plugin eval decide@silver-cc-tools        # + no-plugin baseline arm
claude plugin eval ./plugins/decide --ablation with-without
```

These are not in CI — they cost money and need a live agent. Targeting a plugin by name adds the baseline arm automatically; a path target needs `--ablation with-without`, and without a baseline a score says nothing about whether the skill changed anything.

## License

MIT — see [LICENSE](LICENSE).
