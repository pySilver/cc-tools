---
name: refine-plan-against-codex
description: >
  Refine an implementation-plan markdown file against Codex with a loop
  that terminates: one hunt round produces a finite list of findings, and
  every later round only verifies that the applied fixes closed them —
  scoped to the fix diff and structurally unable to add new findings.
  Anything else Codex notices is parked and reported, never fixed inside
  the loop. Use AFTER `/planning:make` produces a draft and BEFORE
  `/planning:exec` begins execution. Activates on "refine against codex",
  "refine plan with codex", "loop codex review", "harden plan with codex",
  or when preparing a plan that defines a wire contract, multi-step state
  mutation, a new API endpoint, a cross-layer fixture, or anything the
  host repo's plan-review discipline doc (if any) flags as load-bearing.
---

# refine-plan-against-codex

Drives an external review of a single plan file — **hunt once, then
verify** — so the loop ends on a list going empty rather than on the
reviewer running out of things to say.

## Hunt once, then verify

**Round 1 hunts. Every later round only verifies.** This is the shape of
the loop and the reason it ends.

A full re-review of the plan every round does not converge. Three things
compound: "find what's wrong" is an unbounded generative task, so a
determined reviewer always returns something; each fix is new text, so
round N+1 legitimately has new material that round N created; and a
memory-wiped full re-review resamples the whole artifact rather than
working down a list. Measured on the brand-membership-propagation plan
(2026-08-04), worst-finding severity by round ran `0.42 → 0.48 → 0.86` —
**rising**, because each round's best finding attacked the previous
round's fix. That is a diverging process, and no filter fixes a
diverging process.

So round 1 produces a finite list, and rounds 2+ are scoped to the diff
of the previous round's fixes with one question per item: is this
finding addressed, yes or no. They are structurally unable to add to the
list. Anything else codex notices goes to `parked[]` — reported at the
end, never fixed inside the loop. The list only shrinks, so the loop
terminates by construction: `completed_verified` when it empties,
`completed_cap` at the round budget (default 4).

What that keeps: the highest-value finding class from the old shape was
"round N's fix is wrong", and the verify round reads exactly that diff.
That class has two halves, and they exit through different channels. A
fix that **fails its own finding** comes back as `fixed: false` and stays
on the list. A fix that **succeeds and introduces a different defect**
cannot — the list may only shrink — so it goes to `parked[]`, which is
why the verify prompt tells codex to look hardest at the text a fix
added. Measured (2026-08-11, canonical-cluster-cutover): a fix correctly
closed its finding and, in the section it added, wrote a lock order that
contradicted the plan's own invariant; the verify round returned
`fixed: true` with an empty `parked[]`, the loop exited
`completed_verified`, and a later re-hunt found it at once. The prompt
said "a defect UNRELATED to any listed finding", and a defect inside a
fix's own text is not unrelated — so the wording steered codex away from
the one place worth looking.

What it drops: "round 3 notices something unrelated in a section nobody
touched" — which is the behaviour that made the loop endless.

**So read `completed_verified` as "every listed finding is closed",
never as "the artifact is clean."** The list going empty is a property of
the list, not of the plan.

As a plan grows codex also inflates **prose nitpicks**
(re-interpretations of the plan's wording, not defects in what gets
built) to `high` severity — so severity alone can't tell a real defect
from editorial drift. An independent **arbiter** subagent classifies
each finding real-vs-prose. It runs on the hunt round and only there:
round 1 is the only round that produces findings, so it is the only
round with anything to triage. When the hunt surfaces no real
`high`/`critical` defects — only prose nitpicks and/or minor findings —
the loop **auto-terminates as `completed_converged`** and reports
exactly which findings were editorial.

Editorial drift is one of two ways a finding wastes a round. The other
is a finding that is **real but will never bite** — a defect that only
materializes under a conjunction of conditions the plan already makes
unlikely. Every finding therefore carries a **materialization** score
(0-1: "if this plan ships as written, how likely is it that this
actually bites?") alongside `confidence` ("is this claim true?"). Codex
self-scores it on the hunt round; the arbiter then re-scores it
independently and the arbiter's number wins. Two thresholds use it:

- **`MATERIALIZATION_FLOOR`** (0.3) — below it a finding is recorded but
  never sent to the implementer, exactly like sub-floor confidence.
- **`MATERIALIZATION_GATE`** (0.5) — a real `high`/`critical` finding
  only keeps the loop alive if it clears this. Findings between the
  floor and the gate still get fixed; they just no longer buy another
  round.

> Output format, termination states, stuck-finding detail, prose-drift
> arbiter gate, materialization scoring, and drift-guard mechanics: see
> `references/orchestration.md`. The references/ scripts
> (`run-codex.sh`, `extract-sentinels.sh`, `state.py`) are execute-only —
> do not read them into context during a run; their contracts are in
> `references/README.md`.

## Portability assumptions

This skill is repo-agnostic but assumes the host environment provides:

- The `codex` CLI on `PATH` (see `references/run-codex.sh` for the exact
  invocation shape and env-var escape hatches).
- `python3` on `PATH` — hard dependency for `references/state.py` and
  `references/extract-sentinels.sh`.
- The plan file lives in a git-tracked location so per-round commits
  work. Non-git checkouts trigger codex's `--skip-git-repo-check`
  automatically in the wrapper, but the orchestrator's per-round
  commits will fail.
- Optional: `CODEX_MODEL` — the model `references/run-codex.sh` passes
  to `codex exec` (default `gpt-5.6-sol`). Set it in the invoking
  environment to pin a different model.
- Optional: a project plan-glob convention. The default is
  `docs/plans/*.md`; override by passing an explicit path. If your repo
  stores plans elsewhere, set `PLAN_GLOB` in the invoking environment or
  always pass an explicit path.
- Optional: a `**load-bearing` sentinel convention in the plan. Without
  it, the drift guard is a no-op and only prints a warning. Details in
  `references/orchestration.md`.
- Optional: `REFINE_PLAN_MAX_ROUNDS` (default `4`) — the round budget:
  one hunt plus three verify passes. It is a budget, not a fallback;
  under hunt-once the loop's normal exit is `completed_verified`, and the
  cap is what stops a finding the implementer cannot fix from running
  forever. Raise it only when a plan legitimately needs more fix attempts
  per finding, never in the hope that another hunt round will help.
- Optional: `REFINE_PLAN_ARBITER_FROM_ROUND` (default `1`) — the round
  the prose-drift arbiter runs and can terminate the loop. Round 1 is the
  only round that produces findings, so the default is the only value
  that makes sense; a higher number disables the arbiter entirely.
  Details under "Subagent #3".
- Optional: `REFINE_PLAN_MATERIALIZATION_FLOOR` (default `0.3`) and
  `REFINE_PLAN_MATERIALIZATION_GATE` (default `0.5`) — the two
  materialization thresholds. `state.py` reads the same
  `..._FLOOR` var, so its `summary` / `detect-stuck` output always
  agrees with the loop's actionable set; the gate is orchestrator-only.
  A value outside `0.0-1.0`, or an unparseable one, falls back to the
  default. Raise the floor to be stricter about unlikely findings; set
  it to `0` to disable materialization filtering entirely. Details in
  `references/orchestration.md`.

## When to use

Run AFTER `/planning:make` produces a draft and BEFORE `/planning:exec`
begins execution. Skip for trivial plans (<3 tasks, no contract surface).

**Cost note**: Codex is slow (2-5 min per call). At the default 4-round
budget that is ~20 minutes of codex time worst case, plus the hunt
round's arbiter. Most runs finish in 2-3 rounds. Budget accordingly and
prefer running unattended.

## Inputs

`/refine-plan-against-codex <path-to-plan>.md`. If no path is given, ask
the user which plan (or default to the most recently modified file under
the project's plan glob — `${PLAN_GLOB:-docs/plans/*.md}` — and confirm
before proceeding). If MULTIPLE paths are given, refuse — the loop is
per-file; ask which one to refine.

## Orchestration

When this skill is invoked, **you (the main agent in this conversation)
run the loop**. Spawn subagents via the `Agent` tool sequentially — await
each before the next step. The loop body is not external code; it is your
job description.

State lives beside the plan under `.refine-plan-against-codex/`
(gitignored via an auto-written `.gitignore` on first init).
`REFINE_PLAN_STATE_ROOT` overrides. The previous XDG /
`~/.local/state` resolution was removed — state is the project's, not
the user's home dir's.

Use the helpers under `./references/` for state, timing, drift guard,
and resume — see `./references/README.md` for the full API.

```
# Resume check FIRST — never silently overwrite a prior in-progress run.
existing = $(./references/state.py resume <plan-path>)
if existing:
    ask user: "Resume run <existing/manifest.json::run_id> from round N+1, or start fresh?"
    on "fresh" → state.py finalize $existing aborted_drift; state_dir = state.py init <plan-path>
    on "resume" → state_dir = $existing; iter = manifest.current_round
else:
    state_dir = $(./references/state.py init <plan-path>)
    iter = 0

MAX_ITER = int($REFINE_PLAN_MAX_ROUNDS or 4)   # 1 hunt + 3 verify
CONFIDENCE_FLOOR = 0.3                                  # matches state.py
MATERIALIZATION_FLOOR = float($REFINE_PLAN_MATERIALIZATION_FLOOR or 0.3)  # matches state.py
MATERIALIZATION_GATE  = float($REFINE_PLAN_MATERIALIZATION_GATE  or 0.5)
#   FLOOR filters (a sub-floor finding is recorded, never fixed);
#   GATE terminates (a real high/critical below it no longer keeps the
#   loop alive, but is still fixed). Two knobs, two jobs.
ARBITER_FROM_ROUND = int($REFINE_PLAN_ARBITER_FROM_ROUND or 1)
#   Round 1 is the only round that may ADD findings, so it is the only
#   round with anything to triage. Default 1 — the arbiter runs on the
#   hunt and never again. (Historically 4, back when every round was a
#   full re-review; see "Hunt once, then verify".)

open_findings = []   # the hunt list. Set once in round 1; only shrinks.
parked        = []   # noticed on verify rounds; reported, never fixed.

while iter < MAX_ITER:
    iter += 1                                           # rounds are 1-indexed in state
    plan_sha_before = sha256(<plan-path>)               # gap-2 baseline
    print round-start line
    state.py record-codex-start  $state_dir $iter

    if iter > 1:
        # ── VERIFY round ────────────────────────────────────────────
        # Scope is the previous round's fix diff, NOT the plan. Codex is
        # structurally unable to grow the list: it answers fixed/not-fixed
        # per open finding, and anything else it notices goes to parked[].
        fix_diff = git show of round (iter-1)'s commit (plan pathspec only)
        subagent_return = verify_codex_subagent(open_findings, fix_diff)  # subagent #1b
        raw_output, c_tokens, c_tool_uses = parse_subagent_return(subagent_return)
        write raw_output to $state_dir/round-NN/verify.txt
        if raw_output.startswith("CODEX_ERROR:"):
            state.py finalize $state_dir aborted_codex_error
            report_and_abort(raw_output)
        checks, new_parked = read_verify_json(raw_output)
        # Fail safe on a bad reply: treat every open finding as still
        # unfixed. Never mark fixed on a parse failure — that would end
        # the loop on a defect nobody checked.
        if not checks or any(i not in checks for i in range(1, len(open_findings) + 1)):
            checks = {i: False for i in range(1, len(open_findings) + 1)}
            warn("verify output unparseable/incomplete; treating all findings as unfixed")
        parked += new_parked
        write new_parked to $state_dir/round-NN/parked.txt
        open_findings = [f for i, f in enumerate(open_findings, 1) if not checks[i]]
        # Synthesize this round's findings.txt from the ORIGINAL finding
        # objects that are still open, in codex's schema. state.py's
        # summary / detect-stuck / parse_findings then keep working
        # unchanged, and detect-stuck now means exactly "the implementer
        # cannot fix this one" — which is the signal worth having.
        write {"verdict": "needs-attention" if open_findings else "approve",
               "summary": "verify round <iter>",
               "findings": open_findings, "next_steps": []} to /tmp/findings-current.txt
        state.py record-codex-end $state_dir $iter /tmp/findings-current.txt $c_tokens $c_tool_uses
        if len(open_findings) == 0:
            state.py finalize $state_dir completed_verified
            print verified report: every hunted finding, the round it was
                  fixed in, and the full parked[] list with the reminder
                  that nothing in it was acted on
            break
        actionable = open_findings
        run_stuck_check(iter)           # still runs: a finding that survives
                                        # two verify rounds is one the
                                        # implementer cannot fix, which is
                                        # exactly what gap-4 is for
        skip to IMPLEMENTER             # but not the hunt-only stages —
                                        # clean check, arbiter, and design
                                        # routing all need new findings, and
                                        # a verify round produces none

    # ── HUNT round (iter == 1) ──────────────────────────────────────
    subagent_return = ask_codex_subagent(<plan-path>)   # subagent #1
    raw_output, c_tokens, c_tool_uses = parse_subagent_return(subagent_return)
    write raw_output to /tmp/findings-current.txt
    state.py record-codex-end    $state_dir $iter /tmp/findings-current.txt $c_tokens $c_tool_uses
    if raw_output.startswith("CODEX_ERROR:"):
        state.py finalize $state_dir aborted_codex_error
        report_and_abort(raw_output)
    # gap-1: JSON schema validation. Valid = parse_findings returns a
    # non-malformed result with verdict in {approve, needs-attention}
    # and findings being a list. Anything else (paraphrase, gibberish,
    # "Sure, I'll review now…") is a hard abort — passing garbage to
    # the implementer is worse than stopping. parse_findings also
    # rescues a salvageable prose payload via its degraded fallback;
    # malformed means even that failed.
    parsed = parse_findings($state_dir/round-NN/findings.txt)   # from state.py
    if parsed.malformed:
        state.py finalize $state_dir aborted_malformed_output
        report_and_abort(f"CODEX_ERROR: malformed output\n{raw_output[:200]}")
    actionable = [f for f in parsed.findings
                    if f.confidence    >= CONFIDENCE_FLOOR
                    and f.materialization >= MATERIALIZATION_FLOOR]
    unlikely   = [f for f in parsed.findings                 # reported, never fixed
                    if f.confidence    >= CONFIDENCE_FLOOR
                    and f.materialization <  MATERIALIZATION_FLOOR]
    #   A missing or unparseable score reads as 1.0 (state.py `_score`) —
    #   an absent number must never silently drop a finding. Report
    #   len(unlikely) on the codex-done line; never drop it silently.
    # Clean detection: verdict approve AND no actionable findings.
    if parsed.verdict == "approve" and len(actionable) == 0:
        state.py finalize $state_dir completed_clean
        break
    run_stuck_check(iter)   # gap-4, no-op on the hunt round (needs 2 rounds
                            # of findings to compare); defined once, called
                            # from both paths:
    #   stuck = $(state.py detect-stuck $state_dir)
    #   if stuck non-empty AND iter >= 2:
    #       ask user: "<stuck details>; expand scope, terminate
    #                  (completed_cap), or continue the loop?"
    #       on "expand scope" → append a scope-expansion note to the
    #                           implementer prompt for this round (allowing
    #                           edits beyond the strict "findings are the
    #                           only license" rule for the stuck items)
    #       on "terminate"   → state.py finalize $state_dir completed_cap; break
    #       on "continue"    → proceed normally (won't re-ask on the same set
    #                           until a new file:line recurs)
    # gap-5 + gap-6: prose-drift arbiter gate, and the arbiter's independent
    # materialization re-score. Codex inflates prose nitpicks to `high` and
    # over-reports issues that can only bite under absurd conditions, so
    # severity alone distinguishes neither — an independent arbiter
    # (subagent #3) classifies AND re-scores each finding. Under hunt-once
    # this is round 1's gate and runs exactly once: it is the only round
    # that produces findings, so it is the only round with anything to
    # triage. Detail in references/orchestration.md.
    if iter >= ARBITER_FROM_ROUND and len(actionable) > 0:
        state.py record-arbiter-start $state_dir $iter
        arbiter_return = arbiter_subagent(<plan-path>, actionable)   # subagent #3
        arbiter_raw, a_tokens, a_tool_uses = parse_subagent_return(arbiter_return)
        write arbiter_raw to /tmp/arbiter-current.txt
        state.py record-arbiter-end $state_dir $iter /tmp/arbiter-current.txt $a_tokens $a_tool_uses
        # Read the arbiter JSON yourself (see "Subagent #3" for the steps);
        # build classes = {index: "real"|"prose"} and mater = {index: 0.0-1.0}.
        # On any parse/shape failure OR a missing index, fail safe: treat all
        # as real AND discard every arbiter score (never drop a real finding
        # or trigger a false convergence on a broken arbiter reply).
        classes, mater, arb_fix_kind = read_arbiter_json(arbiter_raw)
        if not classes or any(i not in classes for i in range(1, len(actionable) + 1)):
            classes = {i: "real" for i in range(1, len(actionable) + 1)}
            mater   = {}
            arb_fix_kind = {}    # fall back to codex's fix_kind, do not invent one
            warn("arbiter output unparseable/incomplete; treating all findings as real this round")
        # The arbiter's materialization OVERRIDES codex's, for both the floor
        # and the gate. An index the arbiter left unscored reads as 1.0 —
        # never 0 — so arbiter silence can neither drop a finding nor end the
        # loop.
        is_real  = lambda i: classes.get(i, "real") == "real"
        m        = lambda i: mater.get(i, 1.0)
        real     = [f for i, f in enumerate(actionable, 1)
                      if is_real(i) and m(i) >= MATERIALIZATION_FLOOR]
        prose    = [f for i, f in enumerate(actionable, 1) if not is_real(i)]
        arb_unlikely = [f for i, f in enumerate(actionable, 1)  # real, but sub-floor
                      if is_real(i) and m(i) <  MATERIALIZATION_FLOOR]
        blocking = [f for i, f in enumerate(actionable, 1)
                      if is_real(i) and f.severity in ("critical", "high")
                      and m(i) >= MATERIALIZATION_GATE]
        #   `unlikely` (codex's own floor drops) and `arb_unlikely` (the
        #   arbiter's) stay separate — the codex-done line reports both, and
        #   conflating them hides which reviewer made the call.
        if len(blocking) == 0:
            # Convergence: nothing left that is real AND high/critical AND
            # likely to bite. Auto-terminate (the report, not a prompt, is
            # how the operator decides next).
            state.py finalize $state_dir completed_converged
            print convergence report (see references/orchestration.md
                "Convergence report"): the prose findings (file:line,
                severity, title, arbiter reason), the real-but-unlikely
                findings with their arbiter materialization, any leftover
                real low/medium findings, and the one-more-round hint.
            break
        actionable = real   # implementer fixes real defects that clear the
                            # floor; prose and sub-floor unlikely are dropped.
                            # A real finding between FLOOR and GATE is still
                            # fixed — the gate only governs termination.
        #   The arbiter's fix_kind overrides codex's, same as its score.
        for i, f in enumerate(actionable, 1):
            f.fix_kind = arb_fix_kind.get(i, f.fix_kind)
    # gap-7: design-level findings. A finding whose fix is "change a decision
    # the plan already made" is outside the implementer's licence by
    # construction — subagent #2 is told findings are its only licence to
    # edit, and restructuring a plan is not a minimum-scope edit. Route it to
    # the user instead of letting either agent decide alone.
    design = [f for f in actionable if f.fix_kind == "design"]
    guards = [f for f in actionable if f.fix_kind != "design"]
    if design:
        print the design findings: file:line, title, `cause`, and the plan
              section the fix would change
        ask user: "<N> finding(s) say the fix is a design change, not a guard.
                   Revise the plan yourself, let the implementer apply them
                   this round, treat them as guards, or ignore them?"
        on "revise myself" → state.py finalize $state_dir completed_design_handoff
                             print the design findings + next step; break
        on "let implementer" → guards += design   # explicit scope expansion,
                               and note it in the round's commit message
        on "treat as guards" → guards += design   # codex's guard recommendation
                               stands; the cause is knowingly left in place
        on "ignore"         → drop them this round (codex will re-raise; the
                               gap-4 stuck check may then prompt on them)
    actionable = guards
    open_findings = actionable   # the hunt list, frozen. Verify rounds may
                                 # only remove from it; nothing ever adds.

    IMPLEMENTER:
    print codex-done line (severity counts + ↓len(unlikely) + top finding;
          on the hunt round also the arbiter digest with len(prose) and
          len(arb_unlikely); on verify rounds instead print
          "<fixed>/<total> verified, <len(open_findings)> open,
          <len(new_parked)> parked" — see references/orchestration.md)
    state.py record-implementer-start $state_dir $iter
    # Pass the implementer the ACTIONABLE JSON findings (recommendation
    # + file:line_start-line_end), not the raw codex prose / JSON.
    impl_return = apply_findings_subagent(<plan-path>, actionable)  # subagent #2
    summary, i_tokens, i_tool_uses = parse_subagent_return(impl_return)
    write summary to /tmp/summary-current.txt
    state.py record-implementer-end   $state_dir $iter /tmp/summary-current.txt $i_tokens $i_tool_uses
    # gap-2: if the implementer made no actual edits, the next round
    # would see the same plan, codex would return the same findings,
    # and the loop would burn the iteration cap.
    plan_sha_after = sha256(<plan-path>)
    if plan_sha_after == plan_sha_before:
        state.py finalize $state_dir aborted_implementer_noop
        report_and_abort("implementer made no changes to the plan; loop would burn the cap")
    run_drift_guard(<plan-path>)                        # references/extract-sentinels.sh + grep -F
    if drift regression and user chose abort:
        state.py finalize $state_dir aborted_drift; break
    commit_rc = commit_round(<plan-path>, $iter, findings_summary)
    # commit_round uses: git add -- <plan-path> && git commit -m …
    # NEVER `git add -A` / `git add .` — state lives beside the plan,
    # gitignored, but pathspec is the suspenders to that belt.
    if commit_rc != 0:
        # gap-3: pre-commit hook failed (or plan not in a tracked location).
        ask user: "commit failed (<stderr>); fix and retry, or abort?"
        on retry → re-run commit_round; on abort → state.py finalize $state_dir aborted_commit_failed
    print round-end line
# Natural cap exit only — an early break (clean / converged / stuck /
# drift / abort) already finalized, so guard on the live manifest status
# to avoid clobbering it when convergence/abort lands exactly at the cap.
if iter == MAX_ITER and (state.py status $state_dir shows status == in_progress):
    state.py finalize $state_dir completed_cap
# Last-fix hole: every cap exit (completed_cap — natural cap or the stuck
# prompt's "terminate") ends the loop right after applying a fix no round
# ever reviewed. Since later rounds attack earlier rounds' fixes, that
# unreviewed fix is the one most likely to be wrong. One scoped
# delta-check — not a full round, and its findings are REPORTED, never
# applied (applying would recreate the same hole one fix later).
#   Still needed under hunt-once, and more so: the loop is now 4 rounds
#   instead of 20, so a cap exit is a likelier ending. A verify round
#   checks the previous fix but not its own, and this closes that.
#   `completed_verified` does NOT get one — its last round applied no fix.
if state.py status $state_dir shows status == completed_cap:
    last_diff = git show of the final round's commit (plan pathspec only)
    spawn subagent #1 once more with a scoped prompt: review ONLY the
        edits in <last_diff> as a change to <plan-path> — do they
        introduce a new defect or regress an earlier fix? Same JSON
        schema and neutrality rules as the per-round prompt.
    print its findings verbatim in the final report for the user to
        triage; do NOT invoke the implementer on them.
print final summary (from state.py status / summary)
```

**`parse_subagent_return(text)`** extracts three things from the Agent
tool's return:
- The agent's actual response body (everything before the trailing
  `agentId:` / `<usage>` block).
- `total_tokens` — regex `<usage>[\s\S]*?total_tokens:\s*(\d+)`.
- `tool_uses` — regex `<usage>[\s\S]*?tool_uses:\s*(\d+)`.

Both numeric values default to `0` when absent (older Agent return
shapes or parse failures), so token-tracking is best-effort — never
blocks the loop. Pass them to `state.py record-*-end` as the optional
4th and 5th positional args.

## Subagent #1 — codex-asker

Spawn with `subagent_type: general-purpose`. The subagent's only job is
to invoke our own `./references/run-codex.sh` wrapper (NOT the upstream
planning plugin's `thinking-tools:ask-codex`) and return the output
verbatim, isolating codex's long output from the orchestrator's context
window.

**Why our own wrapper, not `thinking-tools:ask-codex`**: the upstream
`run-codex.sh` (in the planning plugin's cache dir) has a known stdin
wedge — codex prints "Reading additional input from stdin..." and ~1 in
5 invocations hangs at 0 CPU when the calling shell's stdin is a
non-tty pipe. The fix is `</dev/null` on the codex invocation;
maintaining it locally on the upstream file means plugin updates clobber
the patch. Owning a copy at `./references/run-codex.sh` means the fix is
durable AND this skill is one fewer plugin dependency. The wrapper's
header comment documents the wedge and the fix.

**Why JSON, not prose**: aligns the on-disk findings with the sibling
`thinking-tools:ask-codex` schema, retires fragile severity-regex
parsing, and lets `state.py parse_findings` apply the
`CONFIDENCE_FLOOR = 0.3` filter (codex's own low-confidence
noise-floor) plus the `MATERIALIZATION_FLOOR = 0.3` filter (codex's own
"true but it will never bite" floor). Unlike the sibling, we retain a
degraded prose fallback
inside `parse_findings` so a malformed JSON payload still has a
recovery path before the loop aborts.

**Fresh codex invocation per round is deliberate, not a perf
oversight.** `./references/run-codex.sh` spawns a fresh `codex` process
each call, so codex sees the plan from scratch each round with no
memory of prior responses. Same "context discipline" argument as the
subagent split below — each codex review is unbiased by what codex
said last round, which prevents codex from drifting into "this is fine,
I already said it was fine." Interactive codex sessions (one process,
multi-prompt) are faster per iteration but lose this property. Do NOT
"optimize" this to a long-lived codex session — `codex exec resume
<id> | --last` makes it easy and it is still wrong.

Under hunt-once the argument gets sharper, because rounds 2+ ask *did
the fix work?* A resumed session would be grading the fix it
recommended, and both ways it can fail are bad: talked into its own
recommendation, it marks a finding fixed that is not, and the loop exits
`completed_verified` on a live defect with nobody the wiser; defensive
about its original framing, it rejects adequate fixes until the cap. The
first is silent, which decides it. What a session would legitimately buy
— the verifier knowing what the finding meant — is bought instead by
passing the finding's own `body` and `instance` into the verify prompt
(see subagent #1b).

**Prompt contract (verbatim — substitute `<SKILL_DIR>` and `<PLAN_PATH>`
only; the orchestrator knows both):**

> Run this shell command and capture its full stdout:
>
> `bash <SKILL_DIR>/references/run-codex.sh 'Review the implementation plan at <PLAN_PATH> and return findings as a single JSON object — no prose, no preamble, no trailing commentary. Schema: {"verdict":"approve"|"needs-attention","summary":"string","findings":[{"severity":"critical"|"high"|"medium"|"low","title":"string","body":"string","file":"string","line_start":int,"line_end":int,"confidence":0.0-1.0,"materialization":0.0-1.0,"materialization_reason":"string","instance":"string","cause":"string","fix_kind":"guard"|"design","recommendation":"string"}],"next_steps":["string", ...]}. Set verdict to "approve" with an empty findings array if you have no findings: {"verdict":"approve","summary":"…","findings":[],"next_steps":[]}. Cite file paths and line ranges from the plan you are reviewing. Use confidence < 0.3 to mark a finding as low-confidence noise — the orchestrator will record it but not act on it. `confidence` and `materialization` are different axes and must be scored separately: confidence is "how sure am I this claim is true?", materialization is "if this plan is built exactly as written, how likely is it that this issue actually bites?". Score materialization as the probability the triggering conditions actually occur: >0.7 = it bites on the normal path or the first realistic input; 0.3-0.7 = it needs a specific but plausible condition (an error path, a concurrent write, a large input); <0.3 = it needs an unlikely conjunction of conditions, a scenario the plan already rules out, or a scale this system will not reach. A finding can be certainly true (confidence 0.95) and still almost never bite (materialization 0.1) — score that honestly instead of inflating it, and put the triggering condition in one sentence in materialization_reason. If the plan does not state the constraint that would settle whether that condition can occur, do NOT guess it low: score materialization 1.0 and say in materialization_reason what you would need to see. Guessing low and guessing high are the same error, and a low score is what stops the issue being fixed. Put in `instance` one concrete run that ends badly, in time order, with real values invented where needed — "worker 2 picks up order 8814 while worker 1 is still writing it", not "two workers race on a row"; a condition is checkable, an instance is checkable and imaginable. Before proposing a fix, ask what makes the condition possible and keep asking until the answer is a decision the plan already made rather than a missing line of code; put that decision in `cause` (empty string if it does not trace to one). Then set `fix_kind`: "guard" if your recommendation adds a check, retry, lock, flag, or branch that holds the symptom down, "design" if it removes the cause by changing a decision the plan already made. Prefer naming the design fix when the cause is a plan decision — a guard leaves the flaw in place and is carried forever. Return ONLY the JSON object.'`
>
> Return ONLY the script's stdout, exactly as codex emitted it — do NOT
> paraphrase, summarize, wrap in extra fences, or add your own
> commentary. Preserve the JSON object byte-for-byte.
>
> If the script exits non-zero, times out, prints an error to stderr,
> or codex's output starts with `Error:` / `command not found`, return
> the literal string `CODEX_ERROR: <one-line cause from stderr or exit
> code>` and nothing else. The orchestrator handles this case
> (transport-level — orthogonal to the JSON contract above).
>
> Do NOT propose fixes. Do NOT modify any file. You are only a
> transport.

**Keep the review prompt neutral.** Substitute the two placeholders and
change nothing else — never add framing like "over-planning is a defect
here" or "a prior pass verified this design" (measured: a framed round
returned approve with zero findings; the identical file under the
neutral prompt returned three, including a high). Scope discipline
belongs in the orchestrator's triage, never in codex's prompt.

Rationale: structured JSON gives the implementer typed `severity`,
exact `line_start`/`line_end` ranges, an explicit `recommendation`
field, and two orthogonal filter signals — `confidence` (is the claim
true?) and `materialization` (does it ever bite?). The `CODEX_ERROR:`
sentinel is the transport-failure channel — distinct from JSON
parse failure, which the orchestrator catches downstream via
`parse_findings`.

**This prompt runs on round 1 only.** Round 2 onward uses the verify
prompt below.

## Subagent #1b — verifier (rounds 2+)

Same spawn shape and the same `run-codex.sh` transport as subagent #1;
only the prompt and the return schema differ. It is a **separate
subagent per round**, so it has no memory of previous verify rounds —
the open-findings list is passed in, which is the only state it needs.

The reason this exists is termination. A full re-review of a changed
plan resamples the whole artifact every round: the list does not shrink,
it gets redrawn, and each fix adds new text to criticize. Measured on
the brand-membership-propagation plan (2026-08-04), worst-finding
severity by round ran `0.42 → 0.48 → 0.86` — rising, because each
round's best finding attacked the previous round's fix. That is a
diverging process, and no filter fixes a diverging process. Scoping
rounds 2+ to the fix diff and forbidding additions makes the list
monotonically shrink, so the loop terminates by construction.

**Prompt contract (verbatim — substitute the two placeholders only):**

> Run this shell command and capture its full stdout:
>
> `bash <SKILL_DIR>/references/run-codex.sh 'You are verifying fixes, not reviewing a plan. Below are findings raised in an earlier review — each with the concrete failure run its author said it would cause — and the diff that was applied to address them. For EACH numbered finding, decide whether that specific finding is now addressed by the diff, and return `fixed` true or false with one sentence of `why`. Judge only the finding in front of you. Where a finding carries a `bites when` line, that run is the test: answer whether the diff makes THAT run impossible, and say so in `why` — do not settle for "the edit resembles the recommendation", because an edit can match the wording and leave the run intact. You may NOT add findings to this list and you must NOT re-review the plan — the list is fixed and can only shrink. Mark `fixed: false` when the edit does not address the finding, when it addresses it in a way that reintroduces the same defect elsewhere, or when you cannot tell from the diff; do not mark a finding fixed on the assumption that a plausible edit worked. If the diff introduces a defect — whether unrelated to every listed finding, or created by a fix itself and living inside the very text that fix added — or you notice anything else worth saying, put it in `parked` using the finding schema below. A finding can be correctly fixed AND its fix can introduce a new problem; report both, and do not let `fixed: true` suppress the second. The text a fix added is the newest and least reviewed part of this artifact, so look there hardest. `parked` is reported to the human and is deliberately NOT acted on by this loop, so put things there freely rather than inflating a `fixed: false`. Return ONLY a single JSON object, no prose, no preamble: {"checks":[{"index":int,"fixed":true|false,"why":"string"}],"parked":[{"severity":"critical"|"high"|"medium"|"low","title":"string","body":"string","file":"string","line_start":int,"line_end":int,"confidence":0.0-1.0,"materialization":0.0-1.0,"instance":"string","recommendation":"string"}]}. Include exactly one `checks` entry per finding index below. <findings>@@OPEN_FINDINGS@@</findings> <diff>@@FIX_DIFF@@</diff>'`
>
> Return ONLY the script's stdout, exactly as codex emitted it — do NOT
> paraphrase, summarize, wrap in extra fences, or add your own
> commentary. Preserve the JSON object byte-for-byte.
>
> If the script exits non-zero, times out, prints an error to stderr,
> or codex's output starts with `Error:` / `command not found`, return
> the literal string `CODEX_ERROR: <one-line cause from stderr or exit
> code>` and nothing else.
>
> Do NOT propose fixes. Do NOT modify any file. You are only a
> transport.

`@@OPEN_FINDINGS@@` renders one block per still-open finding, from the
original finding objects in `round-01/findings.txt`:

```
N. [severity] file:line_start-line_end — title
   what: <body>
   bites when: <instance>
   cause: <cause>                    # omitted when empty
   recommendation: <recommendation>
```

`@@FIX_DIFF@@` is `git show` of the previous round's commit, plan
pathspec only.

**Why the full block and not just the title.** The verifier is a fresh
process with no memory of the hunt, so everything it knows about a
finding is what this block says. Given only a title and a
recommendation it can answer one question — *does this edit resemble
what was recommended?* — and an edit can match the recommendation's
wording while leaving the failure intact. `instance` is what turns that
into a checkable question: the hunt already wrote down one concrete run
that ends badly, with real values, so the verifier can ask whether the
diff makes **that run** impossible.

This is deliberately the alternative to resuming codex's session across
rounds. A session would give the verifier the hunter's memory — along
with the hunter's stake in its own recommendation, which is exactly the
wrong property in a grader. Passing the finding's own text instead keeps
the verdict independent, keeps the input auditable (it is verbatim from
the state dir), keeps the prompt shrinking as findings close, and
survives a resume. **Do not "optimize" this into a long-lived codex
session** — see the same argument for the hunt round above.

**Reading the reply** — `read_verify_json(raw)`: strip a leading
```` ```json ```` fence, `json.loads`, and on a valid
`{"checks":[{index,fixed,why}],"parked":[…]}` object build
`{index: bool}` plus the parked list. **Any parse failure, wrong shape,
or a missing index means every open finding stays open** — the inverse
of the arbiter's fail-safe, and for the same reason: there, silence must
not drop a finding; here, silence must not declare one fixed. A
malformed verify reply that read as "all fixed" would end the loop on
defects nobody checked.

Two things deliberately absent from this prompt: any instruction to
assess plan quality, and any mention of what a good plan looks like.
Both invite the model back into hunting mode, which is the behaviour
this round exists to prevent.

## Subagent #2 — implementer

Spawn with `subagent_type: general-purpose`.

The orchestrator passes the **actionable** findings (filtered to
`confidence >= 0.3` and `materialization >= 0.3`) as a compact list —
one bullet per finding with its `recommendation` and
`file:line_start-line_end`. Codex's prose summary, below-floor noise,
and unlikely-to-materialize findings are NOT forwarded.

**Prompt contract (verbatim — substitute placeholders only):**

> Apply the following review findings to `<PLAN_PATH>`. Each finding
> cites a specific line range and identifies a defect. Your job:
> minimum-scope edits that resolve each finding.
>
> <findings>
> <one bullet per actionable finding, rendered as:
>   - [severity, m=materialization] file:line_start-line_end — recommendation
>   followed by the finding's `instance` on the next indented line — one
>   concrete run that ends badly, which tells you what the fix has to
>   prevent far better than the abstract condition does.
>  Pre-filtered to confidence ≥ 0.3 and materialization ≥ 0.3 by the
>  orchestrator.>
> </findings>
>
> Rules:
> 1. Address EVERY finding above. The list has already been filtered
>    to confidence ≥ 0.3 and materialization ≥ 0.3; do not skip items
>    because they look minor or unlikely. `m=` is how likely the issue
>    is to actually bite — use it to size the fix (a low-`m` finding
>    deserves the smallest possible edit, not a new safeguard section),
>    never as a licence to skip one.
> 2. Do NOT add features, expand scope, or rewrite sections that no
>    finding touches. Findings are the only license to edit.
> 3. Preserve every prior fix. If a resolution would regress a
>    load-bearing string (the orchestrator runs a `grep -F` guard
>    after you finish), choose a different fix that keeps both intact.
> 4. For each fix, edit the smallest contiguous block that resolves
>    the finding. Do not refactor surrounding prose for style.
> 5. Return a one-paragraph summary listing which finding titles you
>    addressed and the `file:line` of each edit. No code blocks, no
>    diffs — the orchestrator reads the file directly to verify.
> 6. After addressing each finding, list 2-3 places in the plan that
>    might need related updates because of your fix, and address
>    those too within scope.
> 7. These findings have already been triaged as guard-level edits. If
>    resolving one would require restructuring the plan's approach —
>    changing a decision the plan already made, rather than fixing what it
>    says — STOP on that finding, leave it unedited, and say so in your
>    summary with the section it would have changed. Do not restructure a
>    plan on your own authority. The orchestrator routes those to the user.
>
> Do NOT commit. The orchestrator handles commits between rounds.

## Subagent #3 — arbiter (prose-drift gate)

Spawn with `subagent_type: general-purpose`. Runs on the **hunt round
and only there** (`ARBITER_FROM_ROUND`, default 1) — verify rounds
produce no findings, so there is nothing to classify. Its job is to
independently judge whether each actionable finding is a **real
defect** (something that, if the plan is implemented as written,
produces wrong / incomplete / contradictory / ambiguous-enough-to-
misbuild behavior — it changes *what gets built*) or a **prose finding**
(a critique of the plan's wording, clarity, redundancy, or structure, or
a re-interpretation that does not change the build outcome). It also
re-scores each finding's **materialization** from scratch — codex's own
score is deliberately withheld from it, so the number that drives the
floor and the gate comes from a party with no incentive to inflate.

It answers the inflation half of the problem: codex inflates prose
nitpicks to `high` severity on large plans, so `severity`/`confidence`
cannot tell them apart — only a fresh, plan-grounded reading can. It
does **not** answer the termination half. Filtering a round's findings
cannot stop a process that redraws its finding set every round; that is
what hunt-once does, and the two are independent fixes to two different
failures.

The orchestrator passes the **actionable** findings (confidence ≥ 0.3)
as a numbered list. The arbiter must read the plan itself, not trust
codex's framing. It does NOT edit anything.

**Prompt contract (verbatim — substitute placeholders only):**

> You are a triage arbiter. Read the implementation plan at
> `<PLAN_PATH>`, then classify each review finding below as either a
> real defect or a prose finding. This plan has already been refined
> over several rounds; later-round findings tend to be editorial.
>
> - `real` — the finding identifies a defect that changes WHAT gets
>   built: a contradiction, a missing/incorrect case, a wrong contract
>   or value, or ambiguity severe enough that an implementer would build
>   the wrong thing. Verify it against the plan text before trusting it.
> - `prose` — the finding critiques the plan's wording, clarity,
>   redundancy, ordering, or completeness-of-explanation, or
>   re-interprets prose, WITHOUT identifying a concrete defect that would
>   change the implementation. Codex often raises these as `high`
>   severity on large plans; do not be swayed by the stated severity.
>
> When genuinely uncertain, classify as `real` — never downgrade a
> possible defect to `prose`.
>
> Then, for every finding, score `materialization` 0.0-1.0
> independently of codex's own score (which is NOT shown to you):
> if the plan is built exactly as written, how likely is it that this
> issue actually bites? Score the probability that the triggering
> conditions occur, not how bad it would be:
>
> - `>0.7` — bites on the normal path or the first realistic input.
> - `0.3-0.7` — needs a specific but plausible condition (an error
>   path, a concurrent write, a large input, an unusual but expected
>   caller).
> - `<0.3` — needs an unlikely conjunction of conditions, a scenario
>   the plan already rules out, or a scale this system will not reach.
>
> A finding can be both real and near-zero materialization; that is a
> normal, useful answer, not a contradiction. Score `prose` findings
> too (they are usually low). When you genuinely cannot tell — the plan
> does not state the constraint that would settle it — score `1.0` and
> name the missing information in `materialization_reason`. The
> orchestrator treats a high score as "keep working on it", so
> uncertainty must never look like "safe to stop"; guessing low and
> guessing high are the same error, and only guessing low is silent.
>
> <findings>
> <one block per actionable finding, numbered from 1, rendered as:
>   N. [severity] file:line_start-line_end — title
>      recommendation / body (one line)>
> </findings>
>
> Then, for every finding you called `real`, decide independently whether
> the fix belongs at the guard level or the design level. Ask what makes
> the condition possible, and keep asking until the answer is a decision
> the plan already made rather than a missing line of code.
>
> - `guard` — the fix adds a check, retry, lock, flag, or branch that holds
>   the symptom down. The cause stays in the plan.
> - `design` — the condition only exists because of a choice the plan
>   already made, and changing that choice removes the failure mode by
>   construction. Name the plan section that holds it.
>
> Codex is shown the same question but has an incentive to answer `guard`,
> because a guard is the smaller edit. Judge it yourself from the plan. When
> the honest answer is "this fork should not exist", say `design` — do not
> pick between two guards when neither is the real fix.
>
> Return ONLY a single JSON object, no prose, no preamble:
> `{"classifications":[{"index":int,"class":"real"|"prose","materialization":0.0-1.0,"fix_kind":"guard"|"design","reason":"<=1 sentence, cite the plan","materialization_reason":"<=1 sentence naming the condition that would have to hold","cause":"<=1 sentence naming the plan decision, or empty"}],"summary":"<=1 sentence"}`.
> Include exactly one entry per finding index above.

**Reading the arbiter's reply** is something you (the orchestrator) do
directly on its JSON — there is no `state.py` helper for it (unlike
codex's findings, which `state.py` re-parses for `summary`/`detect-stuck`,
the arbiter verdict has no other consumer). Strip a leading
```` ```json ```` fence, `json.loads`, and on a valid
`{"classifications":[{index,class,materialization,fix_kind,...}]}` object
build three maps: `{index: "real"|"prose"}`, `{index: float}` for
materialization, and `{index: "guard"|"design"}` for fix_kind. Drop any
`materialization` that is missing or not a number in `0.0-1.0` from the
second map — an index absent from it reads as `1.0` at both threshold
checks. Drop any `fix_kind` that is not exactly `guard` or `design`; an
index absent from that map keeps **codex's** `fix_kind` rather than
defaulting, because inventing `design` would stall the loop on a user
prompt and inventing `guard` would hide the finding the gap-7 gate exists
to surface. On **any** parse/shape failure — or a
missing `class` entry for some index — fail safe: treat every finding as
`real` and discard the whole materialization and fix_kind maps for that
round (never converge, never drop a finding on a broken arbiter response),
and print a one-line warning. The arbiter's raw JSON is persisted to
`round-NN/arbiter.txt` via `state.py record-arbiter-end` for the audit
trail and the summary table's `Xr Yp m<max>` digest.

**Re-running after a terminal exit.** Every completion status is
terminal, so a re-run starts a fresh hunt. Under hunt-once that is the
*only* way to get new findings, and it is a decision to make
deliberately rather than a default — a second hunt on a plan that just
passed its verify rounds is precisely the "review it again and see what
turns up" move that made the old loop endless. Re-hunt when something
real changed: the plan gained a section, an ADR under it was revised, or
a `parked[]` item turned out to matter. Do not re-hunt to see whether
codex has calmed down.

## Commit cadence

One commit per round, format:

```
docs(plans): refine <slug> against codex (round N)

<one-line summary of round's themes, derived from finding severities,
 e.g. "1 critical (wire-contract mode normalization) + 2 medium">

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

**Pathspec-scoped staging**: the commit step runs
`git add -- <plan-path>` followed by `git commit -m …`. **Never**
`git add -A` / `git add .`. State lives beside the plan and is
gitignored via the auto-written `.gitignore`, but pathspec staging is
the suspenders that prevents an unrelated working-tree change from
landing in a codex-refine commit.

**Slug derivation**: strip the leading `YYYYMMDD-` date prefix from
the filename if present, then drop the `.md` extension. So
`<plans-dir>/20260101-foo-bar.md` → `foo-bar`,
`<plans-dir>/auth-rewrite.md` → `auth-rewrite`. The date prefix is
operationally noisy in commit messages.

Per-round commits give a bisectable history of what each codex pass
found. A later codex round contradicting an earlier one becomes a
single revert, not a manual unweaving. If the user wants one squashed
commit before merging, that's a manual `git rebase -i HEAD~N` choice
— not the default.

## Context discipline

Each subagent inherits only what it needs:
- Subagent #1: the plan file path. Nothing else from the orchestrator's
  running discussion.
- Subagent #2: the plan file path + the actionable findings list
  (filtered JSON, not codex's prose reasoning). Not prior rounds'
  findings, not the orchestrator's history.
- Subagent #3 (hunt round only): the plan file path + the numbered actionable
  findings. Crucially NOT codex's verdict, codex's own materialization
  scores, prior arbiter rulings, or the orchestrator's history — its
  independence from codex's framing is the whole point; a
  context-contaminated arbiter just launders codex's drift, and an
  arbiter shown codex's score anchors to it instead of re-deriving one.

This is the load-bearing reason for the subagent split (sycophancy
avoidance is secondary). A single subagent with longer context drifts
into "while I'm here, let me also fix X" territory — fixes you didn't
ask for that may regress prior work. The strict context boundary
forces each iteration to scope to exactly the current findings.

## What this skill does NOT do

- Execute the plan (that's `/planning:exec`).
- Refine multiple plans concurrently (loop is per-file).
- Address findings the user wants to defer — codex doesn't know your
  scope; the implementer's "stay in scope" rule is the gate.
- Chase prose nitpicks indefinitely — the hunt round's arbiter gate
  (subagent #3) auto-stops the loop (`completed_converged`) when the hunt
  has no real `high`/`critical` defects, reporting which findings were
  editorial. Later rounds cannot raise a nitpick at all: they only verify.
- Chase true-but-never-bites findings — the materialization floor keeps
  them out of the implementer and the materialization gate stops them
  from buying another round. Both report what they filtered; neither
  deletes it from `findings.txt`.
- Replace `/planning:plan-review` — that's a single-pass internal
  review with project-specific guidance; this skill is iterative
  codex external review. Both have a place in the chain.
