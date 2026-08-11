# refine-plan-against-codex — references

Helper scripts the orchestrator shells out to during a loop. All
scripts are idempotent and tolerant of repeated invocation.

**Execute-only**: the orchestrator invokes these via `bash` /
`python3`; do not read them into context during a run. The contracts
below + the `orchestration.md` reference are the loadable surface.
This README and `orchestration.md` are the only files in
`references/` that should be read directly.

Hard runtime dependency: `python3` (used by `state.py` and embedded
in `extract-sentinels.sh`).

## `run-codex.sh`

Codex invocation wrapper. **Fork** of the planning plugin's
`~/.claude/plugins/cache/umputun-cc-thingz/planning/3.7.1/skills/exec/scripts/run-codex.sh`,
owned here so the wedge-fix patch we maintain doesn't get clobbered by
plugin updates.

Subagent #1 invokes this script directly via `bash`; we deliberately
DON'T route through `thinking-tools:ask-codex` (one fewer plugin
dependency + fix durability).

Inherits the upstream's:
- `codex exec --sandbox read-only` invocation shape
- VCS detect (git vs hg) → adds `--skip-git-repo-check` for hg
- Default `-c` overrides (model, reasoning effort, project_doc context)
- `CODEX_NO_OVERRIDES=1` and `CODEX_MODEL=<name>` escape hatches (our
  default model is `gpt-5.6-sol`)

Adds:
- `set -euo pipefail` (upstream uses `set -e` only)
- Inlined VCS detect (upstream has a separate `detect-vcs.sh` helper;
  we keep the dependency surface at one file)
- The wedge fix (`exec codex ... </dev/null`) maintained at the source,
  with a comment explaining the failure mode it defends against.

Usage: `bash run-codex.sh '<prompt>'`. Output on stdout, exit code from
codex.

## `state.py`

State management. Per-run state lives **beside the plan** under
`<plan-dir>/.refine-plan-against-codex/`, gitignored via an
auto-written `.gitignore` (`*` content) on first init. Never
committed.

`REFINE_PLAN_STATE_ROOT` overrides the location. The previous
XDG / `~/.local/state` resolution was removed — state is the
project's, not the user's home dir's, and follows the plan file's
lifecycle.

Single `argparse`-driven program; subcommands:

| command | purpose |
| --- | --- |
| `state.py init <plan-path>` | Create root + `.gitignore` (if absent) + new run dir, write initial manifest. Print absolute state-dir path on stdout. |
| `state.py resume <plan-path>` | Print absolute state-dir path of the most recent `in_progress` run for this plan, or empty if none. |
| `state.py record-codex-start <state-dir> <round>` | Stamp round's codex start time. |
| `state.py record-codex-end <state-dir> <round> <findings-file> [<tokens>] [<tool-uses>]` | Stamp end + copy findings into `round-NN/findings.txt`. Computes elapsed. Token + tool-use args optional (parsed from the subagent return's `<usage>` block by the orchestrator); defaults are `0` so legacy callers keep working. |
| `state.py record-implementer-start <state-dir> <round>` | Stamp implementer start. |
| `state.py record-implementer-end <state-dir> <round> <summary-file> [<tokens>] [<tool-uses>]` | Stamp end + copy summary into `round-NN/implementer-summary.txt`. Token + tool-use args optional, same as codex-end. |
| `state.py record-arbiter-start <state-dir> <round>` | Stamp the round's prose-drift arbiter (subagent #3) start time. Only called on the hunt round (`ARBITER_FROM_ROUND`, default 1); verify rounds produce no findings to classify. |
| `state.py record-arbiter-end <state-dir> <round> <arbiter-file> [<tokens>] [<tool-uses>]` | Stamp end + copy the arbiter's classification JSON into `round-NN/arbiter.txt`. Computes elapsed. Token + tool-use args optional, same as codex-end. |
| `state.py finalize <state-dir> <status>` | Mark run terminal: one of `completed_clean`, `completed_verified`, `completed_converged`, `completed_design_handoff`, `completed_cap`, `aborted_codex_error`, `aborted_malformed_output`, `aborted_drift`, `aborted_implementer_noop`, `aborted_commit_failed`. `completed_verified` is the hunt-once loop's normal exit: every finding from the round-1 hunt was confirmed fixed by a verify round. `completed_clean` remains distinct — the round-1 hunt itself returned `approve` with no actionable findings, so nothing was ever fixed. `completed_converged` is the prose-drift gate's success exit (gap-5); `completed_design_handoff` is gap-7's, set when the user takes a design-level finding back to revise the plan by hand. The previous `aborted_state_corruption` status is retired — atomic `os.replace` on writes means a torn manifest is structurally impossible. |
| `state.py status <state-dir>` | Human-readable summary: total rounds, per-round elapsed, status, state-dir path, per-round findings/summary file paths. |
| `state.py summary <state-dir>` | Box-drawn table for the final report — one row per phase (codex / arbiter / implementer), severity-count Findings column (`<C> <H> <M> <L>`, lowercase enum from the JSON, plus a `↓<N>m` suffix counting findings the materialization floor removed; the arbiter row shows `<R>r <P>p` real-vs-prose plus `m<max>`, the highest materialization it gave a real finding, instead). Then tokens and elapsed. The arbiter row appears only when `round-NN/arbiter.txt` exists; its tokens fold into the Total. Used by the orchestrator per `orchestration.md`'s "Output (UX contract)" spec. |
| `state.py detect-stuck <state-dir>` | One line per `file:line_start` tuple codex has flagged in 2+ rounds (parsed from each round's JSON findings, filtered to `confidence >= 0.3` and `materialization >= MATERIALIZATION_FLOOR`). Empty output = no recurrence. Severity values are the lowercase enum. v1 matches exact `file:line_start`; content-similarity matching is a future improvement. |

`state.py` also exposes `parse_findings(findings_path)` as the
single shared parser used internally by both `summary` and
`detect-stuck` (the old `state.sh` maintained two divergent
regexes). Strategy: strip `` ```json `` fences → `json.loads` → on
schema match return structured findings; on JSON failure run a
degraded prose scan for `critical|high|medium|low` plus
`` `file:line` `` and write a `parse-warning.txt` next to
`findings.txt`; on total failure mark malformed so the orchestrator
finalizes `aborted_malformed_output` rather than passing garbage to
the implementer. Prose-path findings get a synthetic
`confidence`/`materialization` of `0.5` each — above both floors, since
codex's real scores are unrecoverable from a prose-only payload.

`CONFIDENCE_FLOOR = 0.3` is a documented constant — matches the
sibling `thinking-tools:ask-codex` noise floor; codex itself signals
low confidence below this. Findings below the floor are recorded but
excluded from the actionable set passed to the implementer and from
the clean / needs-attention decision.

`MATERIALIZATION_FLOOR` is the second, orthogonal floor — same
filtering role, different question. `confidence` asks "is this claim
true?", `materialization` asks "if the plan ships as written, how likely
is it that this actually bites?". Default `0.3`, overridable via
`REFINE_PLAN_MATERIALIZATION_FLOOR` (out-of-range or unparseable values
fall back to the default; `0` disables the filter). The orchestrator
reads the same env var, so its actionable set always matches
`summary` / `detect-stuck`. The companion `MATERIALIZATION_GATE`
(default `0.5`) is orchestrator-only — it decides termination, not
filtering — and is not defined here. Rationale and bands:
`orchestration.md` → "Materialization scoring (gap-6)".

`_score(finding, key)` is the shared reader for both 0-1 signals: an
absent or unparseable value reads as `1.0`, so a finding is never
dropped for a score nobody supplied (pre-materialization runs, degraded
prose payloads, a codex reply that omitted the field). An explicit `0`
still filters.

Per-run state shape:

```
<plan-dir>/.refine-plan-against-codex/
├── .gitignore           # contains `*`, auto-written on first init
└── <slug>-<UTC-ISO-compact>/
    ├── manifest.json    # all metadata (timestamps, status, plan sha256, round table)
    ├── round-01/                     # the hunt round
    │   ├── findings.txt              # codex's verbatim JSON for this round
    │   ├── parse-warning.txt         # only present when degraded fallback fired
    │   ├── arbiter.txt               # subagent #3's classification JSON (hunt round only)
    │   └── implementer-summary.txt   # subagent #2's report
    ├── round-02/                     # a verify round
    │   ├── verify.txt                # subagent #1b's verbatim {checks,parked} JSON
    │   ├── parked.txt                # this round's parked[] — reported, never fixed
    │   ├── findings.txt              # SYNTHESIZED: the still-open findings, so
    │   │                             # summary / detect-stuck keep working
    │   └── implementer-summary.txt
    └── ...
```

On a verify round `findings.txt` is written by the orchestrator, not by
codex: it holds the subset of the round-1 hunt that the verify pass
returned `fixed: false` for, carried over as the original finding
objects. That keeps `parse_findings`, `summary`, and `detect-stuck`
working with no changes, and sharpens what `detect-stuck` means — a
`file:line` recurring across verify rounds is a finding **the
implementer cannot fix**, not merely one codex keeps mentioning.

`manifest.json` `schema_version: 1` carries: `plan_path`, `plan_slug`,
`run_id`, `started_at`, `initial_plan_sha256`, `status`,
`current_round`, `rounds[]` (each with `round`, `codex_started_at`,
`codex_ended_at`, `codex_elapsed_seconds`, `codex_tokens`,
`codex_tool_uses`, `implementer_started_at`, `implementer_ended_at`,
`implementer_elapsed_seconds`, `implementer_tokens`,
`implementer_tool_uses`, and — on rounds the arbiter ran —
`arbiter_started_at`, `arbiter_ended_at`, `arbiter_elapsed_seconds`,
`arbiter_tokens`, `arbiter_tool_uses`), and on terminate `ended_at`.

Writes are atomic (`tempfile.NamedTemporaryFile` sibling +
`os.replace`) — a mid-write crash leaves the previous manifest intact.

## `extract-sentinels.sh`

Drift-guard sentinel extraction. Scans for lines containing
`**load-bearing` (case-insensitive). For each match, collects every
backtick-fenced span in a 3-line window (the match line ± 1) — fixes
the single-line miss when the marker is on the wrap line of a
multi-line checkbox while the load-bearing identifier sits on the
next line.

Returns unique sentinels, one per line; empty output if none found.

Usage: `extract-sentinels.sh <plan-path>`

The orchestrator then `grep -F`s each sentinel against the post-edit
plan to detect regressions. Empty output means no drift guard runs
(the plan has no pinned identifiers) — orchestrator should warn but
continue.

## `orchestration.md`

Loaded only when actively running the loop — output (UX contract),
stuck-finding detail, drift guard, full termination state catalog.
See [`orchestration.md`](./orchestration.md).
