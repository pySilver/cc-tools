# refine-plan-against-codex — orchestration reference

Detail loaded only when the orchestrator is actively running a loop.
SKILL.md keeps the load-bearing core (orchestration pseudocode + both
verbatim subagent prompts); everything below is reference-grade.

## Table of contents

- [Output (UX contract)](#output-ux-contract)
  - [Per-round lines](#per-round-lines)
  - [Final summary](#final-summary)
  - [Mid-run progress](#mid-run-progress)
- [Stuck-finding detection (gap-4)](#stuck-finding-detection-gap-4)
- [Drift guard](#drift-guard)
- [Termination states](#termination-states)

## Output (UX contract)

The orchestrator's job is to be **quiet plumbing and loud milestones**.
The user has limited attention; long waits between subagent calls are
unavoidable, but noise during them is not. Stick to this contract:

**Never print**:
- Raw codex JSON / prose findings (50-150 lines per round) — they live
  on disk in the round dir; print a digest instead.
- Raw implementer prose summary — parse for edit locations, print one
  line.
- Raw `state.py` command outputs — batch state.py calls in single Bash
  invocations with `>/dev/null` so the user sees one bash call per
  phase, not five.
- Bash command itself for state.py / extract-sentinels.sh — use the
  Bash tool's `description` field to summarise; the user doesn't need
  to read the literal shell.

### Per-round lines

**Always print exactly 3 lines per round**, in order:

1. **Round-start** (before spawning subagent #1):
   ```
   ─ Round N starting (HH:MM:SS) ──── codex review (~2-5 min)
   ```

2. **Codex-done** (after subagent #1 returns, before spawning #2):
   ```
   ─ Round N done (MmSSs) ──── X findings: 1C 2H 0M 1L · top: <file:line> <one-line>
     full: <state-dir>/round-NN/findings.txt
   ```
   Severity counts come from the parsed JSON `findings[]` (filtered to
   `confidence >= 0.3`); the "top" line is the highest-severity
   actionable finding's `file:line_start` + `title`/recommendation
   trimmed to one line. Full JSON is never printed; the path is.

3. **Round-end** (after implementer + drift + commit, all in one line):
   ```
     impl MmSSs · X/N addressed at <edit-locations> · drift OK · commit <sha>
   ```
   `<edit-locations>` comes from parsing the implementer's summary
   paragraph for `file:line` patterns. `drift OK` becomes
   `drift FAIL: <s>` on a sentinel regression. `commit <sha>` is the
   short SHA + first line of the message.

### Final summary

At termination (clean, cap, or aborted): one verdict line, the
box-table from `state.py summary <state-dir>`, then the trailing
metadata block.

```
═══ <verdict> ═══

<output of: ./references/state.py summary <state-dir>>

Plan:        <plan-path>
State:       <state-dir>
Commits:     <first>..<last> (N commits on <branch>)
→ <next-action>
```

The table from `state.py summary` looks like:

```
┌──────────────────────────────────┬─────────────┬─────────┬──────────┐
│ Phase                            │ Findings    │ Tokens  │ Elapsed  │
├──────────────────────────────────┼─────────────┼─────────┼──────────┤
│ Round 1 codex                    │ 1C 1H 1M 0L │ 34k     │ 1m 21s   │
│ Round 1 implementer              │ 3/3 addr    │ 33k     │ 1m 18s   │
├──────────────────────────────────┼─────────────┼─────────┼──────────┤
│ Round 2 codex                    │ No find.    │ 22k     │ 47s      │
├──────────────────────────────────┼─────────────┼─────────┼──────────┤
│ Total                            │             │ 89k     │ 3m 26s   │
└──────────────────────────────────┴─────────────┴─────────┴──────────┘
```

Severity counts (`1C 1H 1M 0L`) are auto-derived by `state.py summary`
from the per-round `findings.txt` JSON (after the
`confidence >= 0.3` actionable filter). Tokens are what the
orchestrator captured from each subagent return's `<usage>` block.
`state.py status` remains available for the simpler human-readable
shape — useful for quick scripted parsing.

`<verdict>` is `"Plan hardened across N rounds"` (clean), `"Cap
reached after N rounds, M unresolved findings"` (cap), or
`"Aborted: <reason>"` (any aborted_*). `<next-action>` is
`"ready for /planning:exec"` on clean, or remediation guidance for the
abort case.

Don't re-derive numbers from memory — `state.py summary` reads the
manifest, which is the source of truth.

### Mid-run progress

If a codex call genuinely exceeds the typical 5-min range, do NOT
print poll updates ("still running..."). The round-start line already
set expectations; injecting noise during the wait is what the
operator dislikes. Codex's hard timeout (`CODEX_TIMEOUT`, default
20 min) is the upper bound the operator can rely on.

## Stuck-finding detection (gap-4)

After each codex round, `./references/state.py detect-stuck
<state-dir>` scans all completed rounds' `findings.txt` JSON for
`file:line_start` tuples that codex has flagged in **2 or more
rounds**. The shape (regardless of severity drift between rounds) is
the load-bearing signal: codex keeps finding the same place, which
means the implementer's previous fix didn't actually satisfy codex.
Continuing the loop without intervention typically burns the
iteration cap on the same finding.

Output format (one line per recurring location):

```
STUCK <path>:<line> rounds: <r1>,<r2>,... severity: <s1>,<s2>,...
```

Severity values are the lowercase enum
(`critical|high|medium|low`). Empty output = no recurrence detected,
proceed normally.

When non-empty AND `iter >= 2`, the orchestrator surfaces to the user
with three options:

- **expand scope** — let the implementer break the "findings are the
  only license" rule for the stuck items (e.g. patch a schema or
  rename a related file).
- **terminate** — finalize `completed_cap`; accept the recurring
  finding as a known limitation needing manual triage.
- **continue** — trust the loop; useful when the operator has context
  that the next round will resolve it.

**Known limitation (v1)**: detection matches exact `file:line_start`
from the JSON. If the plan grows/shrinks between rounds and the same
conceptual finding moves to a different line, the match misses. The
fix is content-similarity matching (hash + cluster findings text),
but it's deferred — in practice the line numbers stay stable enough
across rounds because implementer edits are minimum-scope.

## Drift guard

Before committing each round:

1. **Extract sentinels mechanically** via
   `./references/extract-sentinels.sh <plan-path>`. The script scans
   every line containing `**load-bearing` (case-insensitive) and
   collects backtick-fenced spans in a **3-line window (the match
   line ± 1)** so the marker can sit on the wrap line of a multi-line
   checkbox while the load-bearing identifier lives on the adjacent
   line. Returns unique sentinels, one per line; empty output if none
   found.
2. `grep -F -q "$sentinel" <plan-path>` for each sentinel. Any
   disappearance surfaces to the user immediately: "round N regressed
   `<string>` — abort, override, or revert the round?"
3. If the user overrides, continue the loop; if abort, `state.py
   finalize $state_dir aborted_drift` and exit with the regression
   noted; if revert, `git revert --no-edit HEAD` and re-prompt (they
   decide whether to re-run from there).

Empty sentinels (no `**load-bearing` markers in the plan) is
informational, not an error — warn the user that no drift guard will
run this round, then continue. Authors who want guarded identifiers
should place them in backticks within ±1 line of the
`**load-bearing` marker.

No external `load-bearing.txt` sidecar — drift between plan and
sidecar is the obvious failure mode. The convention lives in the
plan, and the backtick-fenced spans within the marker window are the
load-bearing identifiers.

## Termination states

All terminal states call `./references/state.py finalize <state-dir>
<status>` so a later `state.py status <state-dir>` shows the outcome.

- **Clean** (`completed_clean`): parsed codex JSON has
  `verdict == "approve"` AND the actionable findings list
  (`confidence >= 0.3`) is empty → report total rounds. User sees
  `"Plan hardened across N rounds; ready for /planning:exec."`
- **Cap** (`completed_cap`): `iter == MAX_ITER` without a clean codex
  result → report the unresolved findings list and recommend manual
  triage. Do NOT silently continue past the cap.
- **Codex error** (`aborted_codex_error`): subagent #1 returned
  `CODEX_ERROR: ...` (CLI errored, timed out, output started with
  `Error:` / `command not found`, or the script exited non-zero) →
  surface the cause to the user and abort without committing.
  Re-runs use the resume prompt.
- **Malformed output** (`aborted_malformed_output`): `parse_findings`
  could not recover a structured result from JSON, fenced JSON, or
  the degraded prose fallback (`critical|high|medium|low` +
  `` `file:line` `` scan). Treats unparseable output as fatal rather
  than passing garbage to the implementer. Causes: codex paraphrasing,
  subagent disobeying the verbatim-return contract, or codex
  returning a chat-style preamble. Surface the first 200 chars of the
  raw output to the user so they can diagnose.
- **Drift abort** (`aborted_drift`): user chose to abort after a
  sentinel regression — exit with the regression note; user fixes
  manually before re-running.
- **Implementer no-op** (`aborted_implementer_noop`): plan SHA-256 is
  identical before and after the implementer subagent runs. Next
  round would see the same plan, codex would return the same
  findings, loop would burn the iteration cap. Causes: implementer
  refused all findings as out-of-scope, or hit a tool error and
  silently exited. Surface to user so they can investigate.
- **Commit failed** (`aborted_commit_failed`): `git commit` returned
  non-zero (pre-commit hook rejected, plan not in a tracked location,
  or other git error) AND the user chose abort over retry. Round's
  edits are applied but uncommitted in the working tree — user
  resolves manually.
- **User interrupt**: the previous in-progress state-dir stays as-is
  (`status` remains `in_progress`). Re-running the skill detects it
  via `state.py resume <plan-path>` and prompts: "Resume from round
  N+1, or start fresh?" Resume picks up at the next round with the
  plan in whatever state the last round left it (per-round commits
  make this cheap — completed rounds are already saved to git).
  Fresh marks the prior run `aborted_drift` and starts a new run
  from round 1.

The previous `aborted_state_corruption` status is retired: atomic
`os.replace` writes in `Manifest.save()` make a torn manifest
structurally impossible, so the punt has no operational role.
