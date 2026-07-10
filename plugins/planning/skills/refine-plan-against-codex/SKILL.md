---
name: refine-plan-against-codex
description: >
  Iteratively refine an implementation-plan markdown file by asking Codex
  for findings, applying them, and looping until Codex returns an
  `approve` verdict with no actionable findings or the iteration cap is
  hit. Use AFTER `/planning:make` produces a draft and BEFORE
  `/planning:exec` begins execution. Activates on "refine against codex",
  "refine plan with codex", "loop codex review", "harden plan with codex",
  or when preparing a plan that defines a wire contract, multi-step state
  mutation, a new API endpoint, a cross-layer fixture, or anything the
  host repo's plan-review discipline doc (if any) flags as load-bearing.
---

# refine-plan-against-codex

Drives a review → fix → review loop on a single plan file until Codex
stops finding issues. Modeled on real runs that converged contract-heavy
plans over ~5 codex iterations (per codex's own count of distinct review
passes).

The loop's value front-loads: the first few rounds catch real design
defects, but as a plan grows codex starts inflating **prose nitpicks**
(re-interpretations of the plan's wording, not defects in what gets
built) to `high` severity — so severity alone can't tell a real defect
from editorial drift. From round 4 onward an independent **arbiter**
subagent classifies each finding real-vs-prose; when a round surfaces no
real `high`/`critical` defects — only prose nitpicks and/or minor
findings — the loop **auto-terminates as `completed_converged`** and
reports exactly which findings were editorial, so you can accept it or
force one more round. Real `high`/`critical` findings always keep the
loop alive.

> Output format, termination states, stuck-finding detail, prose-drift
> arbiter gate, and drift-guard mechanics: see
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
- Optional: `REFINE_PLAN_ARBITER_FROM_ROUND` (default `4`) — the round
  the prose-drift arbiter starts running and can terminate the loop. Set
  `1` to arbiter every round (or to force one more arbiter-gated round on
  an already-converged plan). Details under "Subagent #3".

## When to use

Run AFTER `/planning:make` produces a draft and BEFORE `/planning:exec`
begins execution. Skip for trivial plans (<3 tasks, no contract surface).

**Cost note**: Codex is slow (2-5 min per call); at the 20-round cap that
is ~100 minutes of subagent time worst case. Most plans terminate in 3-8
codex iterations. Budget accordingly and prefer running unattended.

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

MAX_ITER = 20
CONFIDENCE_FLOOR = 0.3                                  # matches state.py
ARBITER_FROM_ROUND = int($REFINE_PLAN_ARBITER_FROM_ROUND or 4)
#   The round at which the prose-drift arbiter (subagent #3) starts
#   running AND becomes able to terminate the loop. Default 4 → trust
#   codex fully for the high-value rounds 1-3. Set =1 to arbiter every
#   round (and to force "one more round" on an already-converged plan
#   without re-applying prose — see "Subagent #3").
while iter < MAX_ITER:
    iter += 1                                           # rounds are 1-indexed in state
    plan_sha_before = sha256(<plan-path>)               # gap-2 baseline
    print round-start line
    state.py record-codex-start  $state_dir $iter
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
    actionable = [f for f in parsed.findings if f.confidence >= CONFIDENCE_FLOOR]
    # Clean detection: verdict approve AND no actionable findings.
    if parsed.verdict == "approve" and len(actionable) == 0:
        state.py finalize $state_dir completed_clean
        break
    # gap-4: detect findings that recur across rounds at the same
    # file:line_start. Indicates the implementer's previous fix didn't
    # actually satisfy codex. Detail in references/orchestration.md.
    stuck = $(state.py detect-stuck $state_dir)
    if stuck non-empty AND iter >= 2:
        ask user: "<stuck details>; expand scope, terminate (completed_cap),
                   or continue the loop?"
        on "expand scope" → append a scope-expansion note to the implementer prompt
                            for this round (allowing edits beyond the strict
                            "findings are the only license" rule for the stuck items)
        on "terminate"   → state.py finalize $state_dir completed_cap; break
        on "continue"    → proceed normally (next stuck check is N rounds later;
                            skill won't re-ask on the same set until a new file:line
                            recurs)
    # gap-5: prose-drift arbiter gate. Codex inflates prose nitpicks to
    # `high`, so severity can't distinguish editorial drift from real
    # defects — an independent arbiter (subagent #3) judges each finding.
    # Runs only from ARBITER_FROM_ROUND (default 4); rounds 1-3 trust
    # codex. Detail in references/orchestration.md.
    if iter >= ARBITER_FROM_ROUND and len(actionable) > 0:
        state.py record-arbiter-start $state_dir $iter
        arbiter_return = arbiter_subagent(<plan-path>, actionable)   # subagent #3
        arbiter_raw, a_tokens, a_tool_uses = parse_subagent_return(arbiter_return)
        write arbiter_raw to /tmp/arbiter-current.txt
        state.py record-arbiter-end $state_dir $iter /tmp/arbiter-current.txt $a_tokens $a_tool_uses
        # Read the arbiter JSON yourself (see "Subagent #3" for the steps);
        # build classes = {index: "real"|"prose"}. On any parse/shape failure
        # OR a missing index, fail safe: treat all as real (never drop a real
        # finding or trigger a false convergence on a broken arbiter reply).
        classes = read_arbiter_json(arbiter_raw)   # {index: "real"|"prose"}, or {} if unparseable
        if not classes or any(i not in classes for i in range(1, len(actionable) + 1)):
            classes = {i: "real" for i in range(1, len(actionable) + 1)}
            warn("arbiter output unparseable/incomplete; treating all findings as real this round")
        real  = [f for i, f in enumerate(actionable, 1) if classes.get(i, "real") == "real"]
        prose = [f for i, f in enumerate(actionable, 1) if classes.get(i, "real") == "prose"]
        real_high_crit = [f for f in real if f.severity in ("critical", "high")]
        if len(real_high_crit) == 0:
            # Convergence: no real high/critical defects remain — only
            # prose nitpicks and/or real low/medium. Auto-terminate (the
            # report, not a prompt, is how the operator decides next).
            state.py finalize $state_dir completed_converged
            print convergence report (see references/orchestration.md
                "Convergence report"): the prose findings (file:line,
                severity, title, arbiter reason), any leftover real
                low/medium findings, and the one-more-round hint.
            break
        actionable = real   # implementer fixes real defects only; prose dropped this round
    print codex-done line (with severity counts + top finding)
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
noise-floor). Unlike the sibling, we retain a degraded prose fallback
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
"optimize" this to a long-lived codex session.

**Prompt contract (verbatim — substitute `<SKILL_DIR>` and `<PLAN_PATH>`
only; the orchestrator knows both):**

> Run this shell command and capture its full stdout:
>
> `bash <SKILL_DIR>/references/run-codex.sh 'Review the implementation plan at <PLAN_PATH> and return findings as a single JSON object — no prose, no preamble, no trailing commentary. Schema: {"verdict":"approve"|"needs-attention","summary":"string","findings":[{"severity":"critical"|"high"|"medium"|"low","title":"string","body":"string","file":"string","line_start":int,"line_end":int,"confidence":0.0-1.0,"recommendation":"string"}],"next_steps":["string", ...]}. Set verdict to "approve" with an empty findings array if you have no findings: {"verdict":"approve","summary":"…","findings":[],"next_steps":[]}. Cite file paths and line ranges from the plan you are reviewing. Use confidence < 0.3 to mark a finding as low-confidence noise — the orchestrator will record it but not act on it. Return ONLY the JSON object.'`
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

Rationale: structured JSON gives the implementer typed `severity`,
exact `line_start`/`line_end` ranges, an explicit `recommendation`
field, and a `confidence` signal to filter noise. The `CODEX_ERROR:`
sentinel is the transport-failure channel — distinct from JSON
parse failure, which the orchestrator catches downstream via
`parse_findings`.

## Subagent #2 — implementer

Spawn with `subagent_type: general-purpose`.

The orchestrator passes the **actionable** findings (filtered to
`confidence >= 0.3`) as a compact list — one bullet per finding with
its `recommendation` and `file:line_start-line_end`. Codex's prose
summary and below-floor noise are NOT forwarded.

**Prompt contract (verbatim — substitute placeholders only):**

> Apply the following review findings to `<PLAN_PATH>`. Each finding
> cites a specific line range and identifies a defect. Your job:
> minimum-scope edits that resolve each finding.
>
> <findings>
> <one bullet per actionable finding, rendered as:
>   - [severity] file:line_start-line_end — recommendation
>   followed by a short body line on the next indented line.
>  Pre-filtered to confidence ≥ 0.3 by the orchestrator.>
> </findings>
>
> Rules:
> 1. Address EVERY finding above. The list has already been filtered
>    to confidence ≥ 0.3; do not skip items because they look minor.
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
>
> Do NOT commit. The orchestrator handles commits between rounds.

## Subagent #3 — arbiter (prose-drift gate)

Spawn with `subagent_type: general-purpose`. Runs **only from
`ARBITER_FROM_ROUND` (default 4)**; rounds 1-3 skip it entirely. Its job
is to independently judge whether each actionable finding is a **real
defect** (something that, if the plan is implemented as written,
produces wrong / incomplete / contradictory / ambiguous-enough-to-
misbuild behavior — it changes *what gets built*) or a **prose finding**
(a critique of the plan's wording, clarity, redundancy, or structure, or
a re-interpretation that does not change the build outcome).

This is the load-bearing answer to the "loop keeps finding issues but
they're not real anymore" problem: codex inflates prose nitpicks to
`high` severity on large plans, so `severity`/`confidence` cannot tell
them apart — only a fresh, plan-grounded reading can.

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
> <findings>
> <one block per actionable finding, numbered from 1, rendered as:
>   N. [severity] file:line_start-line_end — title
>      recommendation / body (one line)>
> </findings>
>
> Return ONLY a single JSON object, no prose, no preamble:
> `{"classifications":[{"index":int,"class":"real"|"prose","reason":"<=1 sentence, cite the plan"}],"summary":"<=1 sentence"}`.
> Include exactly one entry per finding index above.

**Reading the arbiter's reply** is something you (the orchestrator) do
directly on its JSON — there is no `state.py` helper for it (unlike
codex's findings, which `state.py` re-parses for `summary`/`detect-stuck`,
the arbiter verdict has no other consumer). Strip a leading
```` ```json ```` fence, `json.loads`, and on a valid
`{"classifications":[{index,class,...}]}` object build a
`{index: "real"|"prose"}` map. On **any** parse/shape failure — or a
missing entry for some index — fail safe: treat every finding as `real`
for that round (never converge, never drop a finding on a broken arbiter
response), and print a one-line warning. The arbiter's raw JSON is
persisted to `round-NN/arbiter.txt` via `state.py record-arbiter-end`
for the audit trail and the summary table's `Xr Yp` digest.

**Forcing one more round after convergence.** `completed_converged` is
terminal, so a plain re-run starts fresh — and with the default
`ARBITER_FROM_ROUND=4` that fresh run would spend rounds 1-3 *applying*
the very prose nitpicks the arbiter exists to filter (the arbiter isn't
active yet). To get exactly one more arbiter-gated round on an
already-hardened plan, re-run with `REFINE_PLAN_ARBITER_FROM_ROUND=1` so
the arbiter engages from round 1 and re-converges immediately without
mutating the plan on prose.

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
- Subagent #3 (round 4+): the plan file path + the numbered actionable
  findings. Crucially NOT codex's verdict, prior arbiter rulings, or the
  orchestrator's history — its independence from codex's framing is the
  whole point; a context-contaminated arbiter just launders codex's
  drift.

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
- Chase prose nitpicks indefinitely — from round 4 the arbiter gate
  (subagent #3) auto-stops the loop (`completed_converged`) once a round
  has no real `high`/`critical` defects, reporting which findings were
  editorial so you decide whether to force one more round.
- Replace `/planning:plan-review` — that's a single-pass internal
  review with project-specific guidance; this skill is iterative
  codex external review. Both have a place in the chain.
