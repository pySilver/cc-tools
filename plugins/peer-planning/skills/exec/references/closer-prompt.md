# Closing-stage prompts

The branch review and the polish each run in a fresh closing-stage subagent, the closer, so their
rounds, fixers and tool calls never enter the orchestrator's context. Four prompts go to it: one
starts the branch review, one starts the polish, and two resume the same closer through
`SendMessage`, one after a design discussion and one with the user's answers. Substitute every
`UPPER_CASE` token before sending, because the closer runs in a fresh context and knows none of
these values.

- `PLAYBOOK_PATH` is the absolute path of the playbook the review step resolved: the project's
  `.claude/peer-planning/review.md`, else `${CLAUDE_SKILL_DIR}/references/review.md`.
- `POLISH_PATH` is the absolute path of the project's polish command file (in this user's main
  repository `WORK_PATH/.claude/commands/polish.md`).
- `EXECUTOR` is the resolved executor, the `subagent_type` of every fixer the closer starts.
- `FIXER_PROMPT_PATH` is `${CLAUDE_SKILL_DIR}/references/implementer-prompt.md`, whose "Fix review
  findings" section the closer sends to each fixer.
- `LOG_EVENT` is the absolute path of `${CLAUDE_SKILL_DIR}/scripts/log-event.py`.
- `REPORT_PATH` is the next numbered `RUN_DIR/msgs/NNN-review-report.md` or
  `NNN-polish-report.md`, and `QUESTIONS_PATH` the next numbered
  `RUN_DIR/msgs/NNN-closer-questions.md`. Every resume with answers names a new `QUESTIONS_PATH`,
  and `ANSWERED_PATH` is the file the answers are to.
- `QUESTION_FORM` is the block under "The questions file" below. `SYMBOL` and `FILE` come from
  the closer's `DISCUSS:` line.

The closer writes its report to `REPORT_PATH`, and the completion report reads it there. Its final
message carries only the lines the orchestrator acts on.

## Run the branch review

```
You run the branch review of a finished plan: revmux rounds over the whole branch, and a fresh
fixer for each round's findings, until the review ends. You own the stage from its first round to
its last fixer's commit.

Working directory: WORK_PATH. Run every git command with git -C WORK_PATH.
Default branch: DEFAULT_BRANCH
Plan: PLAN_FILE_PATH
Progress: PROGRESS_FILE_PATH. Append to it where the playbook says.
Playbook: PLAYBOOK_PATH. Read it whole and follow it as written. Where it speaks to "you", that is
you.
Run directory: RUN_DIR. Number every file you write in RUN_DIR/msgs after the highest number
already there.
Log an event: LOG_EVENT RUN_DIR <event> <fields>
Fixers: subagent_type EXECUTOR, with the "Fix review findings" prompt in FIXER_PROMPT_PATH.
Questions file: QUESTIONS_PATH
Report: REPORT_PATH

Project rules (apply them throughout, and pass them to every fixer as USER_RULES):
USER_RULES

The loop:
1. Iteration 1 runs REVIEW_PHASE=comprehensive, every later one critical, up to five iterations,
   until the playbook ends the phase. An iteration whose findings list is empty also ends it:
   nothing changed, so a re-check would review the same diff.
2. Log stage.start with stage=review and iteration:=N as the iteration starts, before its
   preflight. Log stage.done with the same fields as it ends: after its fixer's commit is
   confirmed, or when it ends the phase. Log when it happens, never afterwards.
3. Run every round through the revmux:revmux skill; load it with the Skill tool. Start each round
   with run_in_background and continue when its notification arrives. A round runs 10 to 20
   minutes, and a foreground call ends at 10. Never sleep-wait or poll.
4. When an iteration's findings list is not empty, start a fresh fixer in the background, with
   every token of its prompt substituted and the next numbered RUN_DIR/msgs/NNN-fixer-report.md
   as its REPORT_PATH. When it returns, read only its final message and confirm the commit with
   git -C WORK_PATH log -1 --oneline. Then append to the progress file:
   Review iteration N fixer: <report path>, commit <sha>, <n> fixed, <m> false positive

You cannot reach the user. Ask nothing by any tool. Where the revmux skill would ask the user, the
playbook decides: the profile is the one its table names, every finding in the list goes to the
fixer, and the task's archive stays as it is. A question nothing here decides goes into
QUESTIONS_PATH, one section per question, numbered from 1, in this form:
QUESTION_FORM
Carry on with every step whose result does not depend on its answer. Where the next step does,
end with REVIEW: waiting on answers.

The design discussion is not yours. When the playbook's stop rule fires (its Step 7), Codex
answers only in the orchestrator's pane. Write the round's gating findings in that symbol, each
with its round and file:line, into your report. Run no fixer for this round, and end with REVIEW:
waiting on a design discussion and DISCUSS: SYMBOL (FILE). The orchestrator resumes you with the
outcome. When the rule fires again on a symbol already discussed, end the phase with that reason.

A phase that cannot go on ends with REVIEW: ended: <reason>. That is a round that cannot run, a
failed preflight, a second degraded round, or a fixer whose COMMIT line names a failure. Never
review by other means, and never report a degraded or skipped round as clean.

Write your report to REPORT_PATH, and rewrite it whole each time you end:
REVIEW: as in the final message
ITERATIONS: one line per iteration, as in the final message
FINDINGS: for each iteration, the findings list the fixer got, or "none"
OPEN: one bullet per item under the headings Open questions, Pre-existing, Immaterial and Batched
  prose findings, never with a severity word
DISCUSSION: the gating findings in the symbol, with rounds and file:line, and the outcome once
  you are resumed; or "none"
DECISIONS: every fixer's DECISIONS lines, each with its report path, or "none"
NOT DONE: what you could not complete, or "none"

Your final message is these lines and nothing else:
REVIEW: clean after <N> iterations | ended: <reason> | waiting on a design discussion | waiting on answers
ITERATIONS:
- <N>: <profile>, <round directory>, <c> critical <M> major <m> minor[, degraded: <sources>], fixer <sha or none>, <f> fixed, <p> false positive
OPEN: <q> open questions, <p> pre-existing, <i> immaterial, <b> batched prose findings
DISCUSS: none, or SYMBOL (FILE)
QUESTIONS: none, or QUESTIONS_PATH
REPORT: REPORT_PATH
```

Five iterations that end with gating findings left are `REVIEW: ended: five iterations, <n>
gating findings left`, never clean.

## Run the polish

```
You run the project's polish step over a finished branch, as if the user had typed its command
with no argument inside WORK_PATH. You own the stage from its first step to its summary.

Working directory: WORK_PATH. Run every command there; git runs as git -C WORK_PATH.
Default branch: DEFAULT_BRANCH. It is the base the polish file diffs against.
Plan: PLAN_FILE_PATH
Progress: PROGRESS_FILE_PATH. Its "Batched prose findings" and the fixer reports it names are what
the branch review left for the polish.
Polish file: POLISH_PATH. Read it whole and follow it as written, in order, with its argument
empty. Where it speaks to "you", that is you.
Run directory: RUN_DIR. Number every file you write in RUN_DIR/msgs after the highest number
already there.
Fixers: when you hand a fix off, subagent_type EXECUTOR, with the "Fix review findings" prompt in
FIXER_PROMPT_PATH, and confirm its commit with git -C WORK_PATH log -1 --oneline.
Questions file: QUESTIONS_PATH
Report: REPORT_PATH

Project rules (apply them throughout):
USER_RULES

Run every revmux round the polish file asks for through the revmux:revmux skill; load it with the
Skill tool. Start each round with run_in_background and continue when its notification arrives.
A round runs 10 to 20 minutes, and a foreground call ends at 10. Never sleep-wait or poll.

You cannot reach the user. Ask nothing by any tool. Where the polish file tells the user
something (the scope it resolved, its read of its conditions, a summary, "Polish complete"),
write it into your report and carry its gist in the SUMMARY line. Where the file asks the user
something (a question about pre-existing items, an open question, a skip it cannot close), write
the question into QUESTIONS_PATH, with every item and every option the file names, one section
per question, numbered from 1, in this form:
QUESTION_FORM
Then carry on with every step whose result does not
depend on the answer. A step depends on an answer when the answer can change what that step reads
or writes: a later review round reads every earlier fix, so it waits on a question whose answer
may add one. Stop where the next step depends on an answer, and end with POLISH: waiting on
answers.

Where the revmux skill would ask the user, the polish file decides: the profile is the one the
file names, the file says which findings to act on, and the task's archive stays as it is. A
question neither decides goes into QUESTIONS_PATH like the others.

When the polish file says to stop and tell the user (a missing tool, the wrong branch), end with
POLISH: ended: <reason>. Never review by other means, and never report a degraded round as
clean.

Write your report to REPORT_PATH, and rewrite it whole each time you end: what the polish file
told the user, step by step; each round with its findings and what you fixed or left and why;
the open, pre-existing and immaterial items, never with a severity word; each question you asked
and the answer; each commit; and what you could not complete.

Your final message is these lines and nothing else:
POLISH: complete | waiting on answers | ended: <reason>
ROUNDS:
- <profile>, <round directory>, <counts by severity>[, degraded: <sources>], <what was fixed>
COMMITS: the SHAs in order, or "none"
SUMMARY: what the polish file tells the user, in at most five lines
QUESTIONS: none, or QUESTIONS_PATH
REPORT: REPORT_PATH
```

## Continue the branch review (sent to the same closer)

```
The design discussion on SYMBOL (FILE) is settled.

DESIGN_OUTCOME

Run this iteration's fixer now on the findings list you built, then go on with the loop as
before. Your report and final message keep the same form.
```

`DESIGN_OUTCOME` is one of two blocks. When the orchestrator and Codex agreed a change, or the user
ruled one:

```
The agreed design is below. Give it to the fixer as the prompt's DESIGN_BLOCK, with SYMBOL, FILE
and AGREED_DESIGN substituted:
AGREED_DESIGN
```

When Codex showed with a cite that the design holds and the orchestrator accepted it, or the user
ruled so:

```
The design holds: the findings are separate defects. Run the fixer on them as they are, with no
DESIGN_BLOCK.
```

## The user's answers (sent to the same closer)

```
The user answered the questions in ANSWERED_PATH:
ANSWERS

Do what each answer says, and go on from where each one was waited on. Write any new question
to QUESTIONS_PATH. Your report and final message keep the same form.
```

`ANSWERS` is one line per question, `Q<N>: <the option the user chose, or their own words>`. When
the gate answered a question from a recorded ruling, the line says so and quotes it.

## The questions file

`QUESTION_FORM` in both opening prompts is this block, sent as it is:

```
## Q<N>: <the question, as the playbook or polish file asks it>
Asked by: <the file and its step>
Items: one bullet per item it concerns, each with its fix where the file names one, or "none"
Options: one bullet per option the file names, the one it recommends first, marked
  "(Recommended)", with the file's reason
Waits: the steps that wait on the answer, or "nothing"
```

The orchestrator reads only this file and the closer's final message to put the question to the
user.
