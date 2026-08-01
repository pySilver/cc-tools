# Changelog

This repo ships independent Claude Code plugins that are intentionally version-less — every commit to the marketplace is a new version, so users on auto-update always track the latest. Entries are therefore anchored by **release date**, newest first, and grouped by plugin.

## Unreleased

### Output styles

- add `output-styles/` — Claude Code output styles now live in this repo and are installed by symlink into `~/.claude/output-styles/`. Not plugins (an output style isn't a plugin component), so they're outside the marketplace catalog and get no `plugins[]` entry.
- `communication-style.md` (**Direct**): add a **Working relationship** section ahead of everything else. It states that Claude and the author are peers — both senior engineers, equal experience and skill — and makes the consequences explicit: hold your own opinion and state it, disagree openly and argue for the alternative, challenge a wrong premise mid-task (raise it once, then follow the decision), never claim unverified work works, and drop the cushioning on technical criticism. The existing rules already asked for bluntness, but bluntness read as a *tone* setting; the model still behaved as if the author's framing were beyond question. Naming the relationship is what makes real disagreement in-bounds.

### planning

- add `check-likelihood` skill — adjudicates a single risk an agent just raised, instead of a whole document. The two existing gates only score materialization in batch (`adr-review` over an ADR, the refine loop's arbiter over a round), so there was no way to challenge one claim mid-conversation — which is where the cost actually lands: an agent offers a fork ("decide between A and B, because X could happen"), X is true and unreachable here, and taking the fork buys permanent complexity for nothing. The skill writes the trigger sentence ("this bites when…"), searches artifact → rules → code → real scale for the invariant that settles it, and must quote a `file:line` or report that it found none. Three outcomes, deliberately distinct: **not established** (no statable condition — and it must not invent one, or it ends up grading its own invention), **scored** (with the quote), **unverified** (condition nameable, evidence unavailable — never silently rounded down to a low score). When the claim justifies a proposal it prices the fork on cost now vs. cost if it fires vs. cost of adding the guard later, landing on simple-path / take-the-fork / defer / **cannot say yet**; a deferral must name the observable signal that reopens it, and `cannot say yet` exists because an `unverified` score otherwise has no honest landing place — the "never guess low" rule is correct for scoring a risk and inverts when applied to pricing a fork, turning an unread file into permanent complexity. `Reachable` likewise requires having read the file that would hold the guard: a missing guard you never looked for is `unverified`, not evidence of absence. Budgeted to a triage at **5 file reads** — counted, not timed, since an agent can count files and cannot feel five minutes, so a clock in a skill is decoration. It predicts the candidate file list before opening anything; over budget it refuses to read inline and offers three options (delegate to a subagent that returns only the verdict, narrow to one named file, or accept `unverified`), because the cost of a 14-file read is not the wait — it is 14 files landing in the planning context the check was supposed to protect. Escalation for *independence* (score near a decision boundary, hard-to-reverse fork, self-grading with no external evidence) is a separate path from delegation for *volume*, and both are offered rather than spent silently. Triggers on `/planning:check-likelihood` and on the way skepticism actually gets typed — "how likely is that", "does that actually happen", "has that ever happened", "that sounds theoretical", "isn't that an edge case".
- **`materialization` scoring across both reviewers** — a 0–1 score answering "if this ships as written, how likely is it that the flagged issue actually bites?", orthogonal to `confidence` ("is the claim true?"). Both Codex and Claude-family reviewers produce an endless supply of technically-correct findings whose triggering conditions will realistically never occur, and neither `severity` (a rare bug is still severe *if* it fires) nor `confidence` can filter them. Now they get scored and filtered:
  - `refine-plan-against-codex`: Codex self-scores every finding from round 1; from round 4 the arbiter re-scores each one **blind to Codex's number** and its score overrides. Two thresholds with two jobs — `MATERIALIZATION_FLOOR` (env `REFINE_PLAN_MATERIALIZATION_FLOOR`, default `0.3`) keeps sub-floor findings out of the implementer, and `MATERIALIZATION_GATE` (env `REFINE_PLAN_MATERIALIZATION_GATE`, default `0.5`) is the bar a real `high`/`critical` must clear to keep the loop alive (below it, still fixed — just no extra round). Nothing is dropped silently: `↓Nm` appears on the codex-done line and in the summary table, the arbiter row gains an `m<max>` digest, and the convergence report names every gated finding with its score and the arbiter's condition sentence. Both prompts also separate *unverifiable* from *unlikely* — when the plan doesn't state the constraint that would settle a condition, the reviewer scores `1.0` and names the missing information instead of guessing low, since the floor filters before the implementer ever sees the finding. A missing or unparseable score reads as `1.0` everywhere, so an absent number never drops a finding and arbiter silence can never converge the loop — resuming a pre-materialization run behaves exactly as before. `state.py` reads the same floor env var, so `summary` / `detect-stuck` never disagree with the loop; `detect-stuck` consequently stops prompting about locations that only recur below a floor. New coverage in both the Python and bash suites (floor filtering, `_score` fail-safe direction, env override incl. garbage/out-of-range fallback, the `↓Nm` and `m<max>` digests).
  - `adr-review`: every Critical/Important finding must now carry a materialization score and the condition that triggers it. Two binding rules replace reviewer instinct — below `0.30` a finding is demoted to **FYI** whatever its severity, and a Critical needs `≥ 0.50`. `NEEDS REVISION` therefore requires at least one finding above the floor: an ADR whose findings are all Nit/FYI is `APPROVE` with a note, instead of being held up by a list of things that will never happen. Scoring splits into three explicit cases, because collapsing them is how a review buries a real finding: **can't name the condition** → not established, drop to FYI; **can name and check it** → score normally; **can name but can't check it** (it turns on a constraint the ADR doesn't state) → mark `materialization: unverified`, keep the severity, name what would settle it, and do *not* downgrade on a guess. The two hard rules apply to scored findings only, so an unverified finding keeps the decision open rather than waving it through — guessing low and guessing high are the same error, but only guessing low is silent.
- `refine-plan-against-codex`: lower the default Codex reasoning effort from `xhigh` to `high` in `run-codex.sh` — `high` is the intended default for our Codex calls; `xhigh` spent extra latency/tokens without proportional gain. The model default (`gpt-5.6-sol`) and the `CODEX_MODEL`/`CODEX_NO_OVERRIDES` escape hatches are unchanged.
- `adr-review`: pin the reviewer to `model: opus` (version-less alias, so it always resolves to the current Opus) instead of inheriting the session model. ADRs are usually authored by the session model (often Fable), so an inherited reviewer is the same model grading its own work — a fixed Opus reviewer gives an independent second perspective on the decision.

### research

- `web-research`: drop the stale `claude-opus-4-6[1m]` model pin — 1M context is standard on every current model, so the `[1m]` beta suffix no longer unlocks anything, and the dated pin held users on an aging model. The skill now inherits the session model like the rest of the marketplace.

## 2026-07-10 — Prose-drift arbiter, configurable codex model, basedpyright-lsp

### planning

- `refine-plan-against-codex`: make the codex model configurable — `run-codex.sh`'s default is now `gpt-5.6-sol` (was a hardcoded `gpt-5.5`), and the existing `CODEX_MODEL=<name>` escape hatch is promoted to a documented knob in the skill's portability assumptions and the README. Covered by a new hermetic wrapper test (`tests/test-planning-run-codex.sh`) that stubs `codex` and `git` on `PATH` and asserts the default, the `CODEX_MODEL` override, and `CODEX_NO_OVERRIDES=1`.
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
