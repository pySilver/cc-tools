---
name: make
description: Create an implementation plan in docs/plans/ whose tasks are coarse, outcome-level slices meant for capable executors that find the details themselves, argued with Codex in the adjacent agterm pane before it is written and checked by Codex after, following the project's .claude/planning-rules.md. Use it whenever the user asks for a peer-planning:make plan, a plan for /peer-planning:exec, a peer-validated plan, a less granular plan, or a plan "for high-effort models", and whenever a plan will be executed with Codex paired in the adjacent pane, even if they only say "plan this".
---

# peer-planning:make, plans with coarse tasks

The plan this skill writes is executed by `/peer-planning:exec`. There, a subagent implements each
task (Opus at high by default) and Codex reviews the diff before the commit. A task the plan marks
for discussion has its approach agreed with Codex before any code. The executor is capable and finds
details itself, so each task states the outcome, the constraints and the proof that it is done, not
the steps. The planner's job moves up a level: settle the decisions an
executor must not re-open, and cut the work into slices that can each be reviewed on their own.

Codex takes part in planning too. Before anything is written, the planner and Codex argue the
problem and the approach, and the user picks from what survives. After the draft, Codex checks
that the plan says what was settled. A plan made without Codex says so in its header.

## Load the rules first

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-rules.sh
```

It prints the project's `.claude/planning-rules.md`, with a first line naming it, or nothing when
the project has none. Treat the content as binding project convention for the plan's structure,
naming, testing and documentation. It supplements this skill, and where it contradicts this
skill, the rules win: they are the project's own.

If the project has a workflow document (`docs/development-workflow.md` or one the root agent doc
names), read its planning stage before drafting. It says which gates and review rounds a plan
passes through here.

## Codex in planning

Codex runs in the right pane of this agterm split. This session is the planner and the only
writer; Codex is read-only in the repository.

- **The pair rules govern.** The "Pair sessions" section of `~/.agents/AGENTS.md` applies to every
  exchange. One question at a time. The planner states its position, the minimal option it was
  priced against and the code behind it; Codex agrees or refutes with a cite. There is no turn
  limit: an exchange goes on while each turn brings something new (a refutation, a cite, a checked
  fact or a changed position), and a turn that only restates the one before it ends it. An addition
  names the failure it prevents, the input that produces it, whether that input is realistic, and
  what breaks without it, or it is refused.
- **Messages.** Load the `mailbox-chat` skill; its sending, waiting and manners rules apply to every
  message. `references/codex-messages.md` has the messages. After each one, end the turn: Codex's
  reply wakes this session. Under `/goal`, whose Stop hook refuses an idle turn and answers each one
  with a nudge that costs a filler turn, first start a background wait on the file the reply lands
  in, with `run_in_background`: `until test -f RUN_DIR/msgs/NNN-codex-plan.md; do sleep 3; done`
  (for a panel's Sol half, every answer file it names). The hook stays quiet while the wait runs,
  and the chat reply or the wait's notification wakes the session, whichever comes first. It is the
  one exception to mailbox-chat's never-wait rule: it watches a file, not the pane, and sends
  nothing, so no second message reaches Codex mid-thought. Verify
  every claim Codex makes about the code with your own tool call before accepting or disputing it.
- **Long content goes in files.** Fix the plan's file name first (the naming rule in Step 2), so its
  stem is known. `RUN_DIR` is `.peer-planning/<plan-stem>/` at the root of this checkout, the same
  directory exec uses for the run. Create `RUN_DIR/msgs/`; if `git check-ignore -q "$RUN_DIR"`
  fails, append `/.peer-planning/` to
  `$(git rev-parse --path-format=absolute --git-common-dir)/info/exclude` and tell the user. Name
  files `NNN-claude-plan.md`, `NNN-codex-plan.md` and, for the one Fable call, `NNN-fable-plan.md`,
  numbered from `001`; `000` is exec's setup
  check. Never create `progress.md` there: exec reads it as a run to resume. The plan must read
  whole without these files.
- **Pick the reviewer seat** before the first message, with
  `${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/reviewer-seat.py`, as
  `${CLAUDE_PLUGIN_ROOT}/skills/exec/references/reviewer-seat.md` says, and write its JSON to
  `RUN_DIR/seat.json` for the model check. When it says `switch`, the
  model check below asks first, and only on "switch to the seat" run `codex-clear.sh` with its
  `clear_flags`, once, before the first message. When
  Codex is unavailable, the same reference makes the second voice an Opus subagent; that is a
  second model family, so it needs no waiver. The plan header names the model that held the seat.
- **Check that Codex is there** before the first message:
  `bash ${CLAUDE_PLUGIN_ROOT}/skills/exec/scripts/codex-clear.sh --check`. It reads the right pane
  without typing and exits 0 only when Codex is idle with an empty composer and registered for
  mail. If it fails, say what it reported and offer a numbered choice: start Codex in the right
  pane and say go, or plan without a peer. This skill never starts an agent or opens a pane.
- **Skipping Codex takes an explicit waiver** from the user: "skip Codex", "plan it alone", or "just
  plan it" given as the answer to that choice. "Plan this" or "just plan it" on its own names the
  work, not who does it. Ask for the waiver once and record it in the plan's header.
- **Check the models** once Codex's presence and any waiver are settled, before the first
  message. The owner asked to be asked before planning goes on with a model other than the
  recommended one, on the Claude side and on the Codex side. `${CLAUDE_PLUGIN_ROOT}/models.toml`
  holds the recommended model and effort of each role, and exec reads the same table. Run
  `python3 ${CLAUDE_PLUGIN_ROOT}/scripts/model-check.py make --agent second-opinion=second-opinion --seat "$RUN_DIR/seat.json"`,
  without `--seat` when Codex is unavailable or waived. It prints one row for this session, one
  for the Fable definition and one for Codex's pane.
  - When `differs` is false, say nothing about it and go on.
  - When a row differs, ask once, with every differing row in the one question: the role, its
    current value, the recommended one and where the recommendation comes from. It confirms this
    plan's setup against a table the owner already ruled, so it skips the gate; inside agterm it
    is a huddle page. For this session or the definition the answers are "go on as it is" or "I
    will switch"; for Codex, "switch to the seat" or "keep `<pane model>`", which leaves the pane
    as it is. Offer "keep" only when the pane's model was read, not for `unknown unknown`.
  - After "I will switch", wait until the user says it is done, then run the check again. This
    session switches with `/model` and `/effort`, which keep the conversation.
  - When the picker's `unmeasured` is set, tell the user in one line that the weekly use is
    unknown and why, and that the seat is astra.

## Night mode

With `--night` before the argument, this skill drafts a plan unattended for a scheduled job:
Codex is argued through a resumable `codex exec` thread instead of the pane, questions for the user
are written into the plan instead of asked, the review runs headless, and the plan is committed on
its night branch. `references/night.md` is the whole of it; read it first when `--night` is given.

## Questions to the user go through the gate

Before any question that asks the user to rule (an approach, a size, a disagreement with Codex
that stalled, a scope call), run the `decide:gate` skill on it. It checks whether a recorded
ruling, a probe or a rule already answers it, sends a question about users through the persona
panel, checks the card's framing, and records the user's answer as a ruling when it is one. While
the gate is in shadow mode the question still reaches the user; only the judge's verdict is
logged. Inside a run its files go in `RUN_DIR/gate/`. A typed value or a bare go-ahead on a step
just described is not a ruling and skips the gate.

## Step 0: a quick scan

Build enough context to ask good questions, and no more:
- `git status` and `git log --oneline -5`;
- a glob or grep over the area the request names;
- one to three of the most relevant files.

Stop at about five files. The executor does the deep reading later. Summarize what you found in
three to five bullets.

When the request names a `docs/backlog/` item, it is the problem statement. Its `where:` is a
starting point; check that its condition still holds. Its `worth:` and rationale keep the
provenance they have: a `later` brings its open question, and a `no` an earlier call against the
work, which takes new evidence or the user's word to reopen. A `worth:` field is a triage call, not
an owner ruling, unless the item says the user ruled.

## Step 1: settle the intent

When the ask is missing who it serves, why, what success looks like or the binding constraint,
run the `decide:interview-me` skill if it is available. Its confirmed restate is this plan's
Overview. Otherwise ask the few questions you need one at a time, each with your recommended answer
attached, in the form the user's own instructions give for questions.

## Step 1.5: argue the problem with Codex

Before any draft, and before the user picks an approach, argue the problem with Codex.

1. **Open.** Send the opening message: the problem as Step 1 settled it, what success looks like,
   the binding constraints, the starting points from Step 0, and the first question with your
   position on it. The first question is usually the approach: the one you recommend, the
   alternatives with their trade-offs, and the minimal option you priced it against. A backlog
   item goes by its path.
2. **One question at a time.** After the approach come the decisions an executor must not re-open:
   a contract, a schema, a lock order, a visibility rule, what is out of scope. Answer each of
   Codex's points: accept it and change your position, or dispute it with your own cite. Codex may
   name an approach you did not; it goes on the list. Two agents converging politely produce
   nothing, so disagree when you disagree.
3. **How a question ends.**
   - **Settled:** it goes to Decisions as pair-settled, with its cite.
   - **A checked fact:** it goes to Decisions with the cite.
   - **Stalled:** a turn that brings nothing new ends the exchange without agreement. Put the
     question to the user as a numbered choice with each side's cite; the ruling goes to Decisions
     as an owner ruling. Relay it to Codex and do not debate it further.
   - **Stalled on a design issue:** both of you found no good solution, and the cause is the
     design itself rather than a preference only the user can weigh. Before going to the user,
     you may call Fable once for a second opinion; see "One Fable call" below.
   A constraint the user set stays binding. Codex can show that it contradicts something; it
   cannot vote it away.
4. **The user picks.** When more than one approach survives, offer them with Codex's points in
   each option's trade-offs, your recommendation first. Skip the pick only when one approach is
   left or the user already chose.
5. **Nothing open goes into the draft.** A question of scope or of a contract that is still open
   blocks Step 2: no task is written until the user answers. exec takes any plan in `docs/plans/`
   and tells Codex its Decisions are settled, so a plan cannot carry an open one.

A path that looks single and clear still gets this step: that judgment is the planner's, and
testing it is what Codex is for. A small change gets a short exchange, not none.

### One Fable call

Fable is not a participant. It is one call per `make` run, for one question, when the pair is
stuck on a design issue: the stalled question in Step 1.5, or a point in Step 2.5 that reopens a
decision and stalls the same way. A stall over a value choice (scope, priority, what the user
wants) goes straight to the user, since Fable cannot answer it either.

1. **Find the agent.** Fable runs as the `second-opinion` agent definition, from `.claude/agents/`
   or `~/.claude/agents/`. This plugin does not ship it. If neither has it, tell the user and take
   the question to them as a plain stall.
2. **Brief it in a file**, `RUN_DIR/msgs/NNN-claude-plan.md`: the problem, the binding
   constraints, the stalled question, each side's position with its cites, why both of you think
   the design is at fault, and the files to read. Ask for its view of the design, any approach the
   pair did not name, and what it would refuse, priced on the same four questions as any addition.
3. **Spawn it once** with the Agent tool, `subagent_type: "second-opinion"`, telling it it is
   read-only and should leave nothing behind. Save its final message as
   `RUN_DIR/msgs/NNN-fable-plan.md`. Never continue it with SendMessage and never call it again in
   this run: a challenged Fable claim is a fact you check with your own tool call.
4. **Take it back to Codex.** Verify Fable's cites first, then send its answer with the relay
   message. Argue the question once more under the same rules.
5. **Record it.** A position this settles goes to Decisions as pair-settled after Fable's second
   opinion. If it still stalls, the user gets the numbered choice with all three positions and
   their cites.

## Step 2: write the plan

Name the file the way the rules say. When they are silent, use `docs/plans/yyyy-mm-dd-<task-name>.md`
with today's date. Build it from `references/plan-template.md`. Headings are
`### Task N:` with real integers, so other executors can run the same file.

### How big a task is

A task is one coherent, reviewable change: a behavior slice that a capable model can build
and verify in one session, which usually means one commit and a handful of files. Size it by
review, not by step count. Split a task when its two halves would each deserve their own review,
or when one half crosses a risky boundary alone: a migration, a lock order, a protocol or schema
change, a visibility rule. Merge two tasks when neither can be reviewed without the other. A
feature typically lands in three to eight implementation tasks, plus the closing tasks the rules
require.

### What a task carries

- **Goal:** one or two sentences naming the behavior that exists when the task is done.
- **Starting points:** the files and symbols to begin reading, as path and symbol, never a line
  number. This is not a complete list; the executor finds the rest.
- **Constraints:** the decisions, invariants, rules and stories the task must honor. Point at the
  plan's Decisions section rather than restating it.
- **Done when:** three to six checkboxes. Each is an observable outcome, including the tests that
  pin the behavior and the docs or guides the change makes wrong. When the plan resolves a backlog
  item, whatever its `worth:` was, the task whose commit lands the fix carries its `git rm`: the
  backlog deletes an item in the commit that lands the fix, not in a separate cleanup.
- **Executor:** only when a task needs a different implementer than the plan's default, named as
  an agent definition, for example `worker` (Opus at high).
- **Discuss:** `yes` only when the task crosses a risky boundary: a migration, a lock order, a
  protocol or schema change, a visibility rule. Codex and the orchestrator then agree the approach
  before any code. Leave the line out everywhere else; such a task goes straight to the
  implementer, and Codex reviews the approach together with the diff. Planning having argued the
  task does not remove the mark: exec's discussion checks a sketch against the checkout as it
  stands then, after the earlier tasks.

Never write exec's `**Agreed approach (Claude and Codex, <date>):**` block under a task. exec writes
it after its own discussion, the implementer is told to follow it, and Codex's review skips judging
an approach marked agreed. A planning sketch under that label would pass unchecked. What planning
settled goes in Decisions.

### What a task leaves out

Step-by-step instructions, code snippets, per-function test lists and exhaustive file inventories
all go. Each is a guess the executor would have to unlearn. The implementer designs the approach
against the real code, and Codex reviews it, or agrees it first on a task marked for discussion. What stays in the plan is what an executor
cannot discover: why this, which alternatives were refused, and what must not break.

### The plan as a whole

- **Planning:** the header line says who planned it: Claude and Codex, or Claude alone on the
  user's waiver, with the circumstance when there was one (no Codex in the pane).
- **Decisions:** carries everything settled, each with its evidence and where it actually came
  from: a checked fact (a code cite or a measurement), pair-settled (Claude and Codex), an owner
  ruling, or the planner's own call with its reason. Pair-settled is a claim, not a fact; the
  project's review reads it as one.
- **Execution:** names the implementer, the `implementer` agent definition (Opus at high) unless
  the plan names another definition, the validation commands and the whole-suite command, once.
  Tasks refer to them rather than repeating them.
- **The project's rules still apply in full:**
  - stories;
  - the final verification task, which no longer runs the whole suite;
  - the suite record, which exec's closing suite stage writes; the plan names the whole-suite
    command once in Execution;
  - OWNER-RUN titles for tasks that must not run unattended;
  - the SKIPPED convention;
  - one commit per task;
  - documentation that describes the current state only.

## Step 2.2: the personas read the stories

Before the user approves the stories, run the persona panel's story read (`decide:panel`,
"Reading stories") on the plan's `## Stories`, unless the plan says "No actor observes a change".
Its files go in `RUN_DIR/panels/<NNN>-stories/`, the next free number, as for any panel inside a
run, so a second read after the stories change never meets the first one's files. When the user
approves the stories, put the flagged ones first, each with the persona answers that flagged it
quoted beside it; the others follow as already read. A
flag is a reason to look, not a verdict: the user may keep a flagged story as written.

## Step 2.5: Codex reads the draft

Send the draft-read request. Codex checks that the plan says what was settled, not the decisions
over again: every Decision reaches the Constraints or Done when of each task it binds, the tasks
fit together and each can be reviewed alone, and each Done when is evidence an executor can
produce. A point that reopens a decision is argued as one question under the Step 1.5 rules,
including the one Fable call if it has not been used, not as a new round over the whole plan.
Fix the plan for every point you accept. The read ends when Codex has no point left, or when a
point stalls, which goes to the user as in Step 1.5; close it with "nothing further".

Codex helped settle the Decisions, so this read is not the independent one. That is the project's
review, next.

## Step 3: the project's gates

If the project ships plan checkers, run them now and fix the plan until each is clean. In this
user's main repository those are `python scripts/check_plan.py <plan>` and
`python scripts/check_stories.py --form <plan>`. A name the plan introduces comes back as
unresolved; confirm it is new rather than a typo.

Then run the review the project's workflow prescribes for a plan. Where the project reviews with
revmux (it has a `.revmux/` directory), that is one round on the profile its workflow names for
plans (`expert` here), through the `revmux:revmux` skill, with the plan file as the subject and no
round-local `profile.md`. Fix what comes back. A confirming round is only for fixes that changed a
contract, and it runs on the narrower profile the workflow names (`final` here). Never run a
second planning round on the same profile.

When a finding overturns a pair-settled decision, take that one question back to Codex, and record
the outcome with its new provenance. Do not rerun the whole discussion.

## Step 4: next step

Offer execution only when no question is open. Tell the user the plan's path, then offer, as a
numbered list:

1. Execute it from a fresh session: `/clear`, then `/peer-planning:exec <plan>`. Started here,
   the run would carry this planning context and pay for it on every call. `/clear` keeps this
   agterm session, so Codex stays in the pane next to it, and removes any `/goal`, which exec
   refuses to run under. Codex's pane needs no `/clear`: exec clears Codex itself before a new
   run's first task, so the planning argument does not reach the first review.
2. Execute it another way the project supports.
3. Stop here.

Commit the plan only when the user asks. Where it lands, on the feature branch or elsewhere, is
the project's convention; follow its rules.

## Rules management

- **Show the rules:** run the resolver and say which file they came from.
- **Change project rules:** edit `.claude/planning-rules.md`. Other planning tools may read it too
  (`/planning:make` does), so say that before editing it.

This skill never edits its own files. A change to how it plans is a request to the user, not
something to do mid-plan.
