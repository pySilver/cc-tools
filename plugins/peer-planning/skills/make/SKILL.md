---
name: make
description: Create an implementation plan in docs/plans/ whose tasks are coarse, outcome-level slices meant for capable executors that find the details themselves, loading the project's .claude/planning-rules.md the same way /planning:make does. Use it whenever the user asks for a peer-planning:make plan, a plan for /peer-planning:exec, a less granular plan, or a plan "for high-effort models", and whenever a plan will be executed with Codex paired in the adjacent pane, even if they only say "plan this".
---

# peer-planning:make, plans with coarse tasks

The plan this skill writes is executed by `/peer-planning:exec`. There, a subagent implements each
task (Opus at medium by default) and Codex reviews the diff before the commit. A task the plan marks
for discussion has its approach agreed with Codex before any code. The executor is capable and finds
details itself, so each task states the outcome, the constraints and the proof that it is done, not
the steps. The planner's job moves up a level: settle the decisions an
executor must not re-open, and cut the work into slices that can each be reviewed on their own.

## Load the rules first

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-rules.sh
```

It resolves `planning-rules.md` exactly as `/planning:make` does: the project's
`.claude/planning-rules.md` first, else the planning plugin's user-level file. The first line
names the source. Treat the content as binding project convention for the plan's structure,
naming, testing and documentation. It supplements this skill, and where it contradicts this
skill, the rules win: they are the project's own.

If the project has a workflow document (`docs/development-workflow.md` or one the root agent doc
names), read its planning stage before drafting. It says which gates and review rounds a plan
passes through here.

## Step 0: a quick scan

Build enough context to ask good questions, and no more:
- `git status` and `git log --oneline -5`;
- a glob or grep over the area the request names;
- one to three of the most relevant files.

Stop at about five files. The executor does the deep reading later. Summarize what you found in
three to five bullets.

## Step 1: settle the intent

When the ask is missing who it serves, why, what success looks like or the binding constraint,
run the `decide:interview-me` skill if it is available. Its confirmed restate is this plan's
Overview. Otherwise ask the few questions you need one at a time, each as a plain numbered
markdown item with your recommended answer attached. Do not use a question widget: this user
answers in plain text.

## Step 1.5: approaches

When more than one reasonable approach exists, propose two or three in plain text, with the
trade-offs and your recommendation first, and let the user pick. Skip this when the path is
single and clear, or when the user already chose.

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
  pin the behavior and the docs or guides the change makes wrong.
- **Executor:** only when a task needs a different implementer than the plan's default, named as
  an agent definition, for example `worker` (Opus at high).
- **Discuss:** `yes` only when the task crosses a risky boundary: a migration, a lock order, a
  protocol or schema change, a visibility rule. Codex and the orchestrator then agree the approach
  before any code. Leave the line out everywhere else; such a task goes straight to the
  implementer, and Codex reviews the approach together with the diff.

### What a task leaves out

Step-by-step instructions, code snippets, per-function test lists and exhaustive file inventories
all go. Each is a guess the executor would have to unlearn. The implementer designs the approach
against the real code, and Codex reviews it, or agrees it first on a task marked for discussion. What stays in the plan is what an executor
cannot discover: why this, which alternatives were refused, and what must not break.

### The plan as a whole

- **Decisions:** carries everything settled, each with its evidence: a code cite, a measurement or
  an owner ruling.
- **Execution:** names the implementer, the `implementer` agent definition (Opus at medium) unless
  the plan names another definition, and the validation commands, once. Tasks refer to them rather
  than repeating them.
- **The project's rules still apply in full:**
  - stories;
  - the final verification task and its record;
  - OWNER-RUN titles for tasks that must not run unattended;
  - the SKIPPED convention;
  - one commit per task;
  - documentation that describes the current state only.

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

## Step 4: next step

Tell the user the plan's path, then offer, as a numbered list:

1. Execute it with `/peer-planning:exec <plan>`.
2. Execute it another way the project supports, such as ralphex or `/planning:exec`.
3. Stop here.

Commit the plan only when the user asks. Where it lands, on the feature branch or elsewhere, is
the project's convention; follow its rules.

## Rules management

- **Show the rules:** run the resolver and say which layer they came from.
- **Change project rules:** edit `.claude/planning-rules.md`, which `/planning:make` and
  `/planning:exec` read too, so say that before editing it.

This skill never edits its own files. A change to how it plans is a request to the user, not
something to do mid-plan.
