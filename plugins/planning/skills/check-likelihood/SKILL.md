---
name: check-likelihood
description: >
  Adjudicates a single risk or issue an agent just raised: how likely is it
  actually to happen here, and is it worth the design fork it is being used
  to justify? Reads the artifact and the project's own invariants, then
  returns a materialization score, the condition that would have to hold,
  and a simple-path / take-the-fork / defer recommendation. Use when an ADR
  discussion, a
  plan review, or any agent turn surfaces a risk that smells rare or
  theoretical, or when a claimed problem is being used to justify extra
  complexity, an extra branch, a lock, a retry, or a "we should also handle
  X". Activates on "how likely is that", "is that likely", "does that
  actually happen", "when would that actually happen", "has that ever
  happened", "can that actually happen", "that sounds theoretical", "sounds
  rare", "isn't that an edge case", "that seems unlikely", "that's a
  stretch", or "check likelihood".
allowed-tools: Read, Glob, Grep, Bash, Agent, AskUserQuestion
---

# check-likelihood

An agent hands you a fork: *"you need to decide between A and B, because
X could happen."* Often X is true, and also will never happen in this
project. Accepting the fork buys permanent complexity to defend against
nothing.

This skill adjudicates one claim, fast. It is **read-only** — it never
edits the artifact and never takes the fork for you.

> Related but different: `adr-review` scores materialization inside a full
> ADR review, and `refine-plan-against-codex`'s arbiter scores inside the
> codex loop. Both are batch gates on a whole document. This is the ad-hoc
> one — point it at a single claim mid-conversation.

## What it answers, in order

1. **Is the claim even established?** — can the condition be stated at all?
2. **Can that condition occur here?** — checked against this project, not in
   the abstract.
3. **What makes the condition possible, and is the proposal worth it?** —
   the cause, then the fork question.

Stop at the first one that settles it. A claim that fails #1 never reaches
#2 — and skips Step 5 too, since there is nothing to price.

## Step 0: Get the claim

- `$ARGUMENTS` non-empty → that is the claim. A pasted sentence, a finding
  block, or a file path holding several.
- `$ARGUMENTS` empty → use the risk raised in the most recent agent turn of
  this conversation. Restate it in one line before proceeding, so a
  misidentified claim fails loudly instead of quietly.
- Several claims → adjudicate up to 3, sharing one 5-read budget across all
  of them; a file read for one claim is already read for the next. At 4 or
  more, do not start — offer the highest-severity three, or `adr-review` /
  the refine loop, which are built to batch.

## Step 1: Write the trigger sentence

One sentence, this shape:

> **This bites when** `<condition>`.

It has to be concrete enough that someone could go check it. "When two
workers claim the same row" is checkable. "When there's a race" is not.

**If you cannot write that sentence, the claim is NOT ESTABLISHED.** Report
that and stop. Do not invent a plausible condition on the claim's behalf —
supplying the missing specifics is exactly how a vague worry gets promoted
into a finding, and you would then be grading your own invention.

## Step 2: Predict the read before you spend it

Name the files that could settle the condition **without opening them** —
`Glob` for paths, `Grep` for matching lines. That costs almost nothing and
tells you which mode you are in.

**Budget: 5 full file reads.** Not "five minutes" — you cannot feel elapsed
time, so a clock is decoration. You can count files, so the budget is
files. A `Grep` hit you read as a single line is free; opening the file is
not.

The budget counts files, not tools. A `Read`, a `cat`, a `sed -n` range, or
a `grep` with more than ~5 lines of context each spend one. Grep for the
matching line, not for the block around it.

- **≤5 candidates** → read them, continue to Step 3. The normal case.
- **>5 candidates** → do **not** start reading. Go to "When the read is too
  big" below.
- **No candidate you can name** → go to "Nothing is written yet" below.

### Nothing is written yet

**This is the common case, not the edge case.** You fire during ADR and
planning work, where the code the claim is about does not exist. No file can
hold the guard, so there is nothing to read and no candidate to name. Do not
route this to "When the read is too big" — that path wants a file list you
do not have, and a subagent cannot read code nobody wrote.

Score against the artifact and the project's rules alone:

- **The artifact states the constraint** → `unreachable`. Quote the line.
- **The artifact is silent** → this is a finding about the artifact, not a
  dead end. The cheapest fix is almost never the guard: it is one sentence
  in the plan that makes the condition impossible. Say which sentence, in
  which section. Score `unverified` only if you cannot tell what that
  sentence would say.

**Do not let `unverified` become the default answer here.** A plan is silent
about most things — that is what a plan is. Returning "cannot say" on every
greenfield claim turns a triage tool into a source of paralysis, which costs
more than the rare risk you were protecting against. Silence in the plan is
information: it usually means the constraint has not been decided yet, and
deciding it is both the answer and the action.

### When the read is too big

The cost of a 14-file read is not the wait. It is 14 files landing in the
planning context you are in the middle of using — you invoked a triage
check, and it ate the session you were trying to protect.

So report the estimate first and let the user choose:

```
scope: ~14 files (app/services/*.py, 3 migrations, .claude/rules/12-outbox.md)
This is an audit, not a triage. Pick one:
  1. Delegate — a subagent reads it and returns only the verdict (~30-60s,
     keeps this context clean)
  2. Narrow — name the one file you think settles it, I read only that
  3. Skip — take it as `unverified` and move on
```

Never start an over-budget read inline, and never delegate silently — 1 and
3 are genuinely different answers and only the user knows which they want.

**If delegating:** `Agent`, `subagent_type: general-purpose`. Hand it the
claim, the trigger sentence from Step 1, and the candidate file list.
Require the Output block below verbatim, including the `file:line` quote.
Its context absorbs the 14 files and dies with it; yours stays clean. That
asymmetry is the whole reason to delegate rather than read.

## Step 3: Find the evidence

This is the whole job. Work down this list and stop at the first thing that
settles the condition:

1. **The artifact** (the ADR, the plan, the diff) — a stated constraint,
   cardinality, ordering guarantee, or explicit exclusion.
2. **The project's own rules** — `CLAUDE.md`, `.claude/rules/*.md`, config,
   migrations, schema.
3. **The code** — the guard, the unique index, the single-caller set, the
   `select_for_update`, the enum that makes the branch unreachable.
4. **Observable scale** — row counts, traffic, deployment topology, how many
   workers actually run.

**Quote the line you relied on, with `file:line`.** A score without a quote
is a guess wearing a number. This is the same bar the rest of the pack
uses: point at the invariant or you have not classified anything.

If the budget runs out before anything settles it, that *is* the answer:
`unverified`, with the files you did read and the one you would read next.
Do not quietly take a sixth.

## Step 4: Classify

Score `materialization` 0.00-1.00 — the probability the triggering
condition actually occurs, not how bad it would be. (The pack calls the
field `materialization` so a verdict here can be pasted straight into an
ADR review or a plan finding. "Likelihood" is the same thing in plain
English.)

| band | meaning |
| --- | --- |
| `>0.7` | occurs on the normal path or the first realistic input |
| `0.3-0.7` | needs a specific but real condition — an error path, a concurrent write, a large input |
| `<0.3` | needs an unlikely conjunction, a scenario this project already rules out, or a scale it will not reach |

Then land in exactly one case:

- **Reachable** — you read the file that would hold the guard and there is
  none, or you found something that enables the condition. Cite the file you
  checked, not the absence. Score from the bands: on the normal path is
  `>0.7`; needing a specific real trigger is `0.3-0.7`. If you never reached
  the file that would hold the guard, you are **Unverifiable**, not
  Reachable — a missing guard you did not look for is not evidence.
- **Unreachable** — you found the invariant that prevents it. Score `<0.3`,
  quote the invariant. The claim stays true; it just cannot fire here.
- **Unverifiable** — you can name the condition but the evidence is not
  available to you (it turns on a constraint nobody wrote down, or code you
  cannot see). Do **not** score it and do **not** downgrade it. Report
  `materialization: unverified` and name the one thing that would settle it.

**Guessing low and guessing high are the same error — but only guessing low
is silent.** A wrong high score costs one unnecessary fix, which someone
will notice. A wrong low score deletes a real problem, and nobody ever finds
out. When the evidence is missing, that asymmetry decides for you.

## Step 5: The fork question

Most claims arrive attached to a proposal — a branch, a retry, a lock, a
nullable column, an extra table, a "we should also handle".

**First ask why the condition exists at all.** Before pricing any guard, ask
what makes the condition possible. Keep asking until the answer is a
decision someone made, not a line of code. Often it is one: two writers
exist because the ADR chose two writers; the ordering can invert because the
plan put the reconciler and the trigger on separate paths. When the cause is
a decision, the cheapest fix is usually to revise it — the condition then
cannot occur by construction, and there is no guard to carry.

A guard holds the symptom down and leaves the cause in place. Reach for it
second, not first.

Then price the proposal:

- **Cost now** — the complexity the guard adds and you then carry forever:
  code paths, tests, a concept every future reader must hold.
- **Cost if it fires** — blast radius × the score from Step 4.
- **Cost of adding it later** — usually the number that decides. A guard
  that is cheap to add the day you first see the problem should not be
  bought today on a `<0.3` score. A guard that becomes a data migration
  later is worth buying early even at a low score.

Land on one of five:

- **Revisit the decision** — the condition only exists because of an earlier
  choice, and changing it removes the failure mode instead of guarding
  against it. Name the ADR or plan section that holds the choice and what it
  would become. Offer this whenever it is true, even when the guard is
  cheap: never present A against B when the honest answer is C, the earlier
  split was wrong.
- **Take the simple path** — skip the guard. Say what you would lose if the
  claim turns out reachable after all.
- **Take the fork** — the guard earns its cost.
- **Defer with a trigger** — the honest middle, and usually the right answer
  on a `0.3-0.7` score. Skip it now and **name the observable signal** that
  should make you revisit: a row count, a second consumer appearing, a
  latency number, a support ticket. A deferral with no named trigger is just
  forgetting with extra steps.
- **Cannot say yet** — the score came back `unverified`, or the claim is not
  established. Do not price a fork on a number you do not have. Name the one
  file or fact that settles it and hand the choice back unmade. `unverified`
  plus TAKE THE FORK is how an unread file becomes permanent complexity —
  the asymmetry in Step 4 tells you not to guess the *score* low, not to
  guess the *fork* expensive.

## Step 6: Escalate — but ask first

Different problem from Step 2's delegation, and worth keeping straight.
Step 2 delegates for **volume** — the evidence is reachable, there is just
too much of it to read here. This escalates for **independence** — you have
a verdict and it should not be the only one.

Get a second, independent opinion when any of these hold:

- The score lands within `0.05` of a band edge — `0.25-0.35` or `0.65-0.75`.
- The fork is expensive or hard to reverse: schema, wire contract,
  migration, anything with a deployed consumer.
- You could not find evidence **and** the area is load-bearing.
- Your Evidence line quotes only the artifact the claim came from. Nothing
  independent of the claim's author checked it, and self-grading with no
  external check is the failure mode this pack keeps designing around.

Two escalation paths, both **offered to the user, never run silently** —
they cost minutes:

- **Fresh subagent** (~30-60s) — spawn via `Agent`, `subagent_type:
  general-purpose`, prompted to *argue the condition IS reachable* and to
  cite lines. Adversarial framing is the point; a neutral second pass just
  agrees with the first.
- **Codex cross-model** (2-5 min) — reuse the sibling skill's wrapper, same
  plugin:
  `bash ${CLAUDE_PLUGIN_ROOT}/skills/refine-plan-against-codex/references/run-codex.sh '<prompt>'`.
  Worth it when the fork is expensive and a different architecture's blind
  spots are the value.

## Output

**Lead with the sentence, not the number.** The reader is mid-planning and
has the design paged out. A first line of `materialization: 0.4 · reachable`
asks them to reload the whole context from a score. One plain sentence first
lets them stop reading there if that is all they needed.

```
<One sentence: does it happen here, and what should we do. No jargon, no score.>

materialization: <0.00-1.00 | unverified> · <reachable | unreachable | unverifiable | not established>
Claim:      <one-line restatement>
Bites when: <a concrete instance, or "cannot be stated">
Evidence:   <file:line> — "<the quoted line that settles it>"

Cause:      <the decision that makes the condition possible, when there is one>
Fork:       <what the claim is being used to justify>
Cost now:   <what the guard costs, carried forever>
Cost later: <what it costs to add after the fact>
→ <REVISIT THE DECISION — <ADR/plan section> | SIMPLE PATH | TAKE THE FORK | DEFER — revisit when <signal> | CANNOT SAY — settles on <file or fact>>
```

**`Bites when:` takes an instance, not a rule.** A condition is checkable
but not imaginable; an instance is both, and the reader judges it without
reloading the design.

- Rule: "when two workers claim the same row" — correct, and still abstract.
- Instance: "worker 2 picks up order 8814 while worker 1 is still writing
  it" — same fact, and the reader can see it happen.

Use real values. `order 8814`, `run 11`, `a 40MB upload`. Invented specifics
are fine; the point is that the reader can picture one run through the
system, not that the number is real.

Omit `Cause:` when the condition is not traceable to a decision, and the
`Fork:` block when the claim is not attached to a proposal. Keep the whole
thing under ~15 lines per claim.

## Rules

1. **Read before scoring.** Every verdict cites a `file:line`, or says
   plainly that it could not find one.
2. **Never edit the artifact.** Read-only. The recommendation is a
   recommendation.
3. **Never take the fork on the user's behalf**, in either direction —
   including by quietly dropping the claim.
4. **Report `not established` proudly.** "This claim has no statable
   condition" is a complete, useful answer and takes ten seconds.
5. **Do not score what you did not check.** `unverified` exists so you never
   have to guess.
6. **Stay inside the budget.** Five file reads. If a check is turning into
   an investigation, hand it back: name the scope and offer the three
   options. A triage that quietly becomes an audit costs the user the
   context they were working in.
7. **Pushback is evidence or it is nothing.** When the user disagrees with a
   score, ask for the file, the incident, or the config that makes the
   condition reachable, and re-score on that — a staging incident is
   evidence and outranks any invariant you quoted. Absent new evidence,
   restate the same score once and let the user overrule it on the record.
   Do not re-score on assertion.

## Common rationalizations

| Rationalization | Reality |
|---|---|
| "It's technically possible, so it counts" | Possible is the entry fee, not the verdict. Find the invariant or admit you didn't look. |
| "Better safe than sorry — just add the guard" | The guard is not free and never gets removed. Price it against the score and against adding it later. |
| "I can't find the constraint, so it's probably fine" | That is the one guess you may not make. It's `unverified`, and unverified keeps the question open. |
| "The reviewer that raised it is usually right" | Track record is not evidence. This skill exists because that reviewer raises rare issues at full confidence. |
| "It's a one-line fix, cheaper to just do it" | Then it is also a one-line fix later, which is exactly the argument for deferring it with a trigger. |
| "Let me check every place this could matter" | That's an audit, not a triage. Report the scope and offer to delegate it. |
| "It's only a couple more files" | It is always only a couple more files. That is how a 5-file budget becomes a 20-file read of someone else's planning context. |
| "The guard is cheap, just add it and move on" | Cheap guards are how a design accumulates. If an earlier decision is what makes the condition possible, say so — REVISIT THE DECISION is on the menu even when the guard costs little. |
| "The plan doesn't say, so I can't answer" | On greenfield the plan is silent about most things. Silence usually means undecided, and naming the sentence that would decide it is the answer. |

## Red flags

- A score with no quoted evidence behind it
- Inventing the specifics of a condition the claim never stated
- `<0.3` used for "I couldn't check" instead of "I checked, it can't happen"
- A deferral with no named signal that would make you revisit
- Pricing a guard without asking what decision made the condition possible
- `unverified` returned on a greenfield claim because the plan was silent,
  when the answer was "the plan should say X"
- A `Bites when:` that restates the rule instead of showing one run of it
- Escalating to codex or a subagent without asking — it costs the user minutes
- Opening files past the 5-read budget instead of reporting the scope
- Starting a big read inline when delegating would have kept the context clean
- Predicting scope *after* opening the first few files, which is not predicting
- Adjudicating a whole review's worth of findings one at a time (use
  `adr-review` or the refine loop)
