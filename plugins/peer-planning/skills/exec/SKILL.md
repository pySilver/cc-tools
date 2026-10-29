---
name: exec
description: Execute a plan task by task as a two-agent run. An implementation subagent (Opus at medium by default) builds each task, Codex in the adjacent agterm pane reviews the diff before the commit, then Codex is cleared and the next task starts; a task the plan marks for discussion has its approach agreed with Codex first. The agents talk through peer-chat, with long content in files, and every step lands in a jsonl event log that a live agterm page shows. Finish with the project's revmux review rounds and its polish step. Use it whenever the user says peer-planning:exec, asks to execute a peer-planning:make plan, or wants plan execution reviewed by Codex task by task, even when they just say "run this plan with Codex".
---

# peer-planning:exec, two-agent plan execution

**Who does what:**
- **This session** is the orchestrator. It hands each task to an implementation subagent, carries
  the messages between Codex and the subagent, and keeps the run's record.
- **Codex**, in the right pane of the agterm split, is the reviewer. It reads each task's diff
  before the commit, and for a task marked for discussion it challenges the approach before any
  code exists. It is read-only in the repository; the only files it may write are long replies in
  the run directory. Its own directory is wherever the user started it, and this skill never
  changes it, so every message that opens an exchange names `WORK_PATH` and asks Codex to run its
  commands there.
- **The implementation subagent** does the code work, so the file reading and the diffs never enter
  this session's context.

A task closes only when Codex has found nothing left to fix and the commit has passed the project's
hooks. A task marked for discussion also needs both agents' agreement on its approach before any
code is written.

## The pair rules, and the one exception

The "Pair sessions" section of `~/.agents/AGENTS.md` governs every exchange with Codex here, in
discussion and in review. There is no turn limit. An exchange goes on while each turn brings
something new (a refutation, a cite, a checked fact or a changed position), and a turn that only
restates the one before it ends the exchange. An addition is priced on four questions: the failure
it prevents, the input, whether that input is realistic, and what breaks without it. A refutation
cites code.

The one exception, approved by the owner, is to the peer-chat skill's "only `peer-chat.py` touches
the pane". Every message still goes through `peer-chat.py`, but `scripts/codex-clear.sh` types
`/clear` between tasks. `peer-chat.py` prefixes every send with a label, so it cannot deliver a
slash command.

## The run directory

A run keeps its files in `RUN_DIR`, which is `.peer-planning/<plan-stem>/` at the root of the
checkout this session runs in:

- `msgs/` holds what a chat message cannot carry: code, diffs, an implementer's report, long item
  lists. `references/codex-messages.md` says when a message uses a file;
- `events.jsonl` is the event log, one JSON object per line, as `references/event-log.md`
  describes;
- `progress.md` is the run's memory in prose;
- `monitor.html` is the live page over the log;
- `tests.js` is the latest pytest invocation seen during the open task, rewritten while it runs
  by the `peer_planning_pytest` pytest plugin. That module is not part of this plugin: it lives
  in `~/.local/lib/agterm-pytest/` and is loaded into every pytest Claude starts through the env
  block of `~/.claude/settings.json`. It finds this run through the session and the checkout; its
  docstring has the rules. Without it `tests.js` is never written and the monitor shows no test
  progress. It is telemetry for the monitor only: the implementer's report stays the record of
  what passed.

The conversation itself stays in chat, where the user reads both agents. The directory stays out
of git and outlives the run: it is the record the monitor and later tuning read. Once the run's
branch has landed, "Run-record housekeeping" offers to remove it.

## Setup

1. **Load the peer-chat skill.** Its sending and manners rules apply to every message below.
2. **Confirm Codex is there.** Run `bash ${CLAUDE_SKILL_DIR}/scripts/codex-clear.sh --check`.
   It reads the right pane without typing and exits 0 only when Codex is idle with an empty
   composer. If Codex is not running in the right pane, stop and say so. This skill never starts an
   agent or opens a pane, and Codex runs with the model and effort the user started it with.
3. **Resolve the plan.** Use the argument, or list `docs/plans/*.md` outside `completed/` and ask
   the user to pick one.
4. **Load the rules.** Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/resolve-rules.sh`. Drop its
   `SOURCE:` line and keep the rest as `USER_RULES`, the project's `.claude/planning-rules.md`.
   It prints nothing when the project has none; `USER_RULES` is then "none".
5. **Resolve the executor.** The first source that names one wins: the user's invocation text, the
   task's own **Executor:** line, the plan's Execution section, then the default, the `implementer`
   agent definition (Opus at medium).
   - The Agent tool takes a model but no effort. Effort comes from an agent definition's
     frontmatter, so the executor is always a definition, passed as `subagent_type`.
   - A stated model and effort need a definition whose frontmatter carries both
     (`.claude/agents/` or `~/.claude/agents/`; `worker`, for example, is Opus at high).
   - If none matches, or the default definition is missing, say so and ask before task 1, offering
     to create one. Never approximate silently.
6. **Find the default branch.** Take `git symbolic-ref --short refs/remotes/origin/HEAD` without
   its `origin/` prefix; if that fails, the first of `main` and `master` that exists. Call it
   `DEFAULT_BRANCH`. A new worktree starts from it, and the branch review diffs against it.
7. **Choose where the work happens.** Offer a numbered choice: a new worktree (the default) or the
   current feature branch.
   - Never create or switch a branch in the main checkout: other sessions share it.
   - For a worktree:
     `git worktree add -b <name> .claude/worktrees/<name> DEFAULT_BRANCH`, where `<name>` is the
     plan's file stem without its date.
   - Then run the project's worktree setup if its agent docs name one; in this user's main
     repository that is `uv run scripts/setup-worktree.py`.
   - Call the absolute path `WORK_PATH`.
8. **Open the run directory.**
   - `RUN_DIR` is `$(git rev-parse --show-toplevel)/.peer-planning/<plan-stem>`, taken in this
     session's own directory rather than in `WORK_PATH`. Create `RUN_DIR/msgs`.
   - If `git check-ignore -q "$RUN_DIR"` fails, append `/.peer-planning/` to
     `$(git rev-parse --path-format=absolute --git-common-dir)/info/exclude`, the clone's local
     ignore file, and tell the user. Never edit the project's `.gitignore` for it unasked.
   - If `RUN_DIR/progress.md` exists, this is a resumed run: read it and `events.jsonl`, and
     continue from the last entry.
   - Run "Run-record housekeeping" once, before task 1, for the repository's other runs.
   - Otherwise start `progress.md` with the plan, `WORK_PATH`, the branch and the executor.
   - Re-read `progress.md` on every wake-up before acting. A Codex message arrives as a new turn,
     and the context may compact in the middle of a run.
   - Append to it after every step: the task, its phase, the implementer's agent id, the commit
     SHA, and every decision, deviation or user ruling.
9. **Check whether Codex can write long replies.** Send the setup check from
   `references/codex-messages.md` and end your turn.
   - If `RUN_DIR/msgs/000-codex-setup.md` then holds `ready`, log `codex.ready` with
     `files:=true`. If Codex replied "no files", log it with `files:=false` and never offer it a
     file; it answers in chat only. Record which in `progress.md`.
   - If Codex's pane shows an approval prompt instead, stop and tell the user. The prompt is theirs
     to answer.
10. **Open the monitor.** Log `run.start` with every field `references/event-log.md` gives it:

    ```bash
    "${CLAUDE_SKILL_DIR}/scripts/log-event.py" "$RUN_DIR" run.start plan=docs/plans/<plan>.md \
      tasks:=<N> work_path="$WORK_PATH" branch=<branch> executor=<executor> session="$AGTERM_SESSION_ID"
    ```

    `plan` is the plan's path from the repository root, as step 3 listed it, and `tasks` the
    plan's task count. Run-record housekeeping reads `plan` to tell whether the run has landed,
    and the monitor shows the plan, branch and executor from this record, so `log-event.py`
    refuses a `run.start` missing any of them. Then run
    `"${CLAUDE_SKILL_DIR}/scripts/open-monitor.py" "$RUN_DIR"`. It copies the page into
    `RUN_DIR` and shows it in a session of its own named `<plan-stem> monitor`, next to this one
    and without selecting it. A resumed run logs `run.start` again, so the monitor knows which
    session and checkout run it now, and makes the same call, which reuses that session if it is
    still open. The page reads the log through `events.js` and this session's agent status from
    `tree`; its one action on agterm, "Go to the agents", selects this session. Tell the user
    where it is, then go to task 1.

    The same script opens any run's monitor later, from any session inside the repository:
    without an argument it finds the runs in the main checkout and every worktree, and offers
    them in agterm's picker. `--list` prints them instead.

## Logging

Log each step as it happens:

```bash
"${CLAUDE_SKILL_DIR}/scripts/log-event.py" "$RUN_DIR" review.reply task:=3 round:=1 verdict=must_fix must_fix:=2
```

`references/event-log.md` lists every event and its fields. Log when the step happens, never
afterwards from memory: the timestamps are what the log is for. A failed log call is a failed
step; fix it before moving on.

## The task cycle

Tasks run strictly one at a time. Later tasks build on earlier commits, and all of them write to
the same plan file.

### A. Start

1. **Pick the task.** Re-read the plan and take the first `### Task N:` section with an unticked
   box. If none is left, go to "After the last task".
2. **Tell the user** which task is starting, in one line, followed by its "Done when" list.
3. **Decide on discussion.** Discuss the approach first only when the task carries
   `**Discuss:** yes`, or when the user's invocation asked for discussion on every task. Log
   `task.start` with `discuss:=true` or `discuss:=false`. Without discussion, go to C.

### B. Discuss (marked tasks only)

1. **Draft an approach sketch:** the approach in a few bullets, the files likely touched, the tests
   that will pin it, and the risks or open points.
   - Read what you need to form the sketch, but keep it bounded: the plan's cites and a few files,
     not the codebase.
   - The implementer discovers the details, and the sketch only has to be right at the level Codex
     can judge.
2. **Open the discussion.** Send the opening message, log `discuss.request`, and end your turn.
3. **On each reply:**
   - Log `discuss.reply`.
   - Verify every claim Codex makes about the code with your own tool call.
   - Answer each point: accept it and change the sketch, or dispute it with your own cite.
   - Two agents converging politely produce nothing, so disagree when you disagree.
   - End your turn after each message.
4. **Reach agreement.** When the thread converges, send the agreement proposal. The task is agreed
   when Codex's reply opens with `AGREED`; log `discuss.agreed`.
5. **When it stalls.** A reply that brings nothing new (it restates a point already answered,
   with no new refutation, cite or checked fact) ends the exchange without agreement. So does
   your own turn when you have nothing new to add.
   - Log `discuss.stalled` and put the disagreement to the user as a numbered choice, with each
     side's cite.
   - When the user rules, log `ruling`, relay it to Codex with the template, and do not debate it
     further.
6. **Record the result.** Write the agreed approach into the plan under the task heading, as
   `**Agreed approach (Claude and Codex, <date>):**` followed by bullets. The implementer, the
   reviewers and the final report all read it there.

### C. Implement

1. **Spawn the implementer:** a fresh subagent with the "Start a task" prompt from
   `references/implementer-prompt.md`, the resolved executor as `subagent_type`,
   `run_in_background: true`, and a description `Task N: <title>`. Log `implement.start` with its
   agent id, then end your turn.
2. **When it returns, read only its report,** and log `implement.done`.
   - **STATUS: BLOCKED** means a premise of the plan or of the agreed approach is false. For a
     discussed task, take the evidence back to Codex and re-agree. Otherwise, or when it changes a
     plan decision, take it to the user.
   - **Failed validation:** resume the same subagent with `SendMessage` and the failure, at most
     twice. After that, stop and report to the user.

### D. Review

1. **Ask for the review.** Put the implementer's report in a file, send the review request that
   names it, log `review.request`, and end your turn.
2. **Check the tree before the verdict.** Every review reply ends with `Changed:` and the paths
   Codex saw. Run `git -C WORK_PATH status --short` yourself and compare the two lists. When they
   differ, Codex has most likely run git in its own directory: log `review.mismatch`, send the
   "asking again" message from `references/codex-messages.md`, and end your turn. A second
   mismatch on the same round goes to the user. A verdict is logged only over a matching list.
3. **If the reply opens with `LGTM`,** log `review.reply` with `must_fix:=0` and go to E.
4. **If it opens with `MUST-FIX: N`,** log `review.reply` with that count, then check each item
   yourself by opening the cited code.
   - Resume the implementer with the accepted items, using the "Apply Codex's review" prompt, in
     the background. Log `fix.start`, and `fix.done` when it returns.
   - Put each item you dispute, with your own cite, in the re-review request.
   - Then send the re-review request with the next round number.
5. **When it stalls.** When Codex repeats an item you disputed with a cite and brings nothing
   new, take that item to the user as a numbered choice and log `ruling` once they decide. The
   other items go on.

### E. Close

1. **Commit.** Resume the implementer with the "Commit" prompt. When it returns, confirm
   `git -C WORK_PATH log -1 --oneline` and the task's ticked boxes in the plan, then log `commit`.
2. **Clear Codex.** Run `bash ${CLAUDE_SKILL_DIR}/scripts/codex-clear.sh` and log `codex.clear`
   with its exit code.
   - **Exit 0:** cleared.
   - **Exit 2:** it refused and typed nothing, usually because Codex is still finishing. Let
     Codex's next message arrive, then run the script again once. If it refuses again, ask the
     user.
   - **Exit 1:** it typed but could not confirm the reset. Read the pane and tell the user; never
     re-send blind.
   - Only clear after a commit, never while a discussion or review is open: the argument needs the
     thread it stands on.
3. **Report and move on.** Log `task.done` and tell the user `Task N done: <sha> <subject>`. The
   next task starts with a fresh implementer and Codex's fresh context.

## Waiting

After every message to Codex and every background launch, end your turn. Never poll Codex's pane
and never sleep-wait. While this session is busy, Codex's message cannot be typed into its
composer, so ending the turn is what lets the answer in.

If Codex's message says more is coming, answer it at once: acknowledge what arrived and ask for the
rest. Never end a turn waiting on a promised follow-up. Codex may already have ended its own turn,
and then both agents wait on each other with nothing to break the silence.

A reply is never owed. If the user asks why nothing arrived, read the pane without typing, then
report what it shows.

## Context hygiene

This session reads the plan, `progress.md`, the subagents' reports, Codex's messages and the files
they name, and the few lines a disputed claim cites. Code work, diffs and test output stay in the implementer. Keeping
them out is how this session remains coherent across a whole plan.

## After the last task: review, then polish

1. **Review the whole branch.** Follow the project's `.claude/peer-planning/review.md` if it has
   one, otherwise `references/review.md`, which runs revmux rounds. Substitute `WORK_PATH`,
   `DEFAULT_BRANCH`, `PLAN_FILE_PATH`, `PROGRESS_FILE_PATH` (as `RUN_DIR/progress.md`) and
   `REVIEW_PHASE`. Then run the loop:
   - The first iteration runs `REVIEW_PHASE=comprehensive`, and later ones run `critical`, up to
     five iterations, until the playbook ends the phase. An iteration whose findings list is
     empty also ends it: nothing changed, so a re-check would review the same diff. Log
     `stage.start` and `stage.done` for each, with `stage=review`.
   - When an iteration's findings list is not empty, spawn a fresh fixer subagent with the "Fix
     review findings" prompt from `references/implementer-prompt.md` and the resolved executor as
     its `subagent_type`. When it returns, append its FIXES and DECISIONS to `progress.md` and
     confirm the commit with `git -C WORK_PATH log -1 --oneline`.
   - Codex takes no part: it has already reviewed every task.
2. **Polish.** Run the project's polish step if it has one; here that is `/polish`
   (`.claude/commands/polish.md`), inside `WORK_PATH`. Log `stage.start` and `stage.done` with
   `stage=polish`. It is interactive, and it stops before finalize, which the user runs.

## Completion report

Tell the user:
- each task with its commit SHA and its must-fix count from the log;
- every decision and deviation the implementers logged;
- every disagreement with Codex and how it was settled, including the user's rulings;
- the review rounds' outcome;
- `WORK_PATH`, the branch and `RUN_DIR`, and what is left for the user: `/git:finalize-feature-branch`,
  then `/git:wrap-up`, which archives the plan and removes the worktree, its test database and this
  run's record.

Then log `run.end`. The plan is archived the way the project does it; here `/git:wrap-up` moves it
to `docs/plans/completed/` once the branch has landed. Never move it while reviews still read it.
`RUN_DIR` stays where it is until the branch lands. Then run "Run-record housekeeping" once more: it catches a run from an
earlier session that landed meanwhile. This run's own branch has not landed yet, so it is not
offered.

## Run-record housekeeping

Each run leaves a run directory, and nothing else removes one. So the skill offers it, once at
setup and once after the completion report, and deletes only what the user picks.

1. Run `"${CLAUDE_SKILL_DIR}/scripts/run-records.py" --landed` from this session's checkout. It
   prints one tab-separated line per landed run: the run directory, its size, the commit that
   archived the plan, and the plan's file name. A run has landed when its log holds `run.end`
   and its plan sits under `completed/` on the remote's default branch, not at the path
   `run.start` logged. Branch ancestry cannot tell, because finalize squashes the branch. The
   script reads origin as it stands and fetches nothing. A line on stderr names a finished run
   whose `run.start` carries no plan path, so the script cannot tell whether it landed; tell the
   user, who removes that directory by hand once its branch is in.
2. If it prints nothing, say nothing about it and move on.
3. Otherwise offer a numbered choice:
   - remove every run listed;
   - remove one of them, when more than one is listed;
   - keep everything, always as the last option.

   Every option names each run's plan, the commit that archived it and its size. Say in the
   question that a removed record is gone from the monitor and from later tuning of this skill.
4. Remove exactly what the user picked, one call per run:
   `"${CLAUDE_SKILL_DIR}/scripts/run-records.py" --remove RUN_DIR`. It refuses any path that is
   not a landed run's directory, and it closes the run's `<plan-stem> monitor` session if one is
   open. It removes nothing else: the worktree, the branch and any database belong to the
   project's own setup, and a revmux task to revmux's own cleanup.

## Never

- Answer a prompt, approval or chooser in Codex's pane. Those answers carry the user's authority.
- Type anything into Codex's pane other than a `peer-chat.py` message or `codex-clear.sh`.
- Treat "Codex agreed" as the user's approval of anything that needs it.
- Write or fix code in this session. Implementers and fixers do the code work.
- Run two tasks at once, or push.
