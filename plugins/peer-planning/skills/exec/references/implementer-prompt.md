# Implementer prompts

Three prompts go to the implementation subagent: one to start a task, one to apply Codex's
review, and one to commit. A fourth goes to a fresh fixer subagent after each round of the branch
review. Substitute every `UPPER_CASE` token before sending, because the subagent runs in a fresh
context and knows none of these values.

The implementer writes each report to its own file, and that file is `REPORT_PATH` in the prompt
that asks for it: `RUN_DIR/msgs/NNN-implementer-report.md`, numbered with the run's other message
files, a new number for every report. Its final message only points at the file, so the report
reaches Codex without passing through the orchestrator.

## Start a task

```
You implement one task of a plan. Discover the details from the code yourself.

Working directory: WORK_PATH
Plan: PLAN_FILE_PATH. Read its Overview, Decisions, Context and Execution sections first.
Task: TASK_HEADING (the "### Task N:" section in the plan)

APPROACH_BLOCK

Project rules (apply them throughout):
USER_RULES

How to work:
1. Read the code the task and the approach name, and confirm their premises. If a premise is
   false, or the task cannot work the way the plan decides it, stop and report STATUS: BLOCKED
   with the evidence (path and symbol). Do not design around a settled decision.
2. Implement the task so that every "Done when" item holds, and write the tests that pin the
   behavior.
3. Validate with the commands in the plan's Execution section and the project rules: formatting,
   lint, type check, framework checks, and the tests. Run only the test files you wrote or edited,
   and report passed + skipped == collected.
4. Do not commit, and do not tick the plan's checkboxes. A reviewer reads the uncommitted diff
   first, and you will be told when to commit.
5. Leave nothing behind outside the diff: no stray files, processes or containers. The one file
   you write outside it is your report.

Nobody is available to answer questions during this task. Decide judgment calls from the plan's
intent, then the project's rules and agent docs, then the surrounding code. When a call is still
50/50, take the smaller, more reversible option, and record it.

Write your report to REPORT_PATH. The reviewer reads it as it is:
STATUS: DONE | BLOCKED
APPROACH: the design you built, in two to five bullets
CHANGED: one line per file, saying what changed
VALIDATION: each command you ran and the summary line of its result
DECISIONS: judgment calls the plan did not settle, one per line, or "none"
DEVIATIONS: where the result differs from the agreed approach and why, one per line, or "none"

Your final message is these five lines and nothing else:
STATUS: DONE | BLOCKED
REPORT: REPORT_PATH
VALIDATION: passed, or failed: the command that failed
DECISIONS: the judgment calls in one line, or "none"
DEVIATIONS: the deviations in one line, or "none"
```

`APPROACH_BLOCK` depends on whether the task was discussed.

For a task whose approach was agreed with Codex:

```
Agreed approach, settled between the orchestrator and the reviewer (Codex). Follow it:
AGREED_APPROACH
```

For any other task:

```
No approach was agreed beforehand. Design it from the task's Goal, Constraints and "Done when" and
from the plan's Decisions. The reviewer (Codex) reviews your approach together with the code, so
state it plainly in the APPROACH line of your report. DEVIATIONS is "none" for such a task.
```

## Apply Codex's review (sent to the same subagent)

```
The reviewer asks for these changes to your uncommitted work on TASK_HEADING:

REVIEW_ITEMS

Apply each one, or refute it with the evidence (path and symbol) when it is wrong. Re-run the
validation from your last report. Write a new report to REPORT_PATH in the same format as before,
with one more section:
REVIEW: one line per item, as "N applied: <what changed>" or "N refuted: <why, with path and symbol>"

Your final message is the same five lines as before, and one more:
REFUTED: one line per refuted item, as "N: <why, with path and symbol>", or "none"
```

`REVIEW_ITEMS` is Codex's numbered items exactly as it sent them, or the path of
`RUN_DIR/msgs/NNN-codex-review.md` when it put them there. Never paraphrase, merge or drop one: the
implementer has the code open and judges each item against it.

## Commit (sent to the same subagent)

```
The review passed. Commit TASK_HEADING now:
1. In PLAN_FILE_PATH, tick every "Done when" checkbox of this task that your work satisfies.
2. Stage the files you changed and the plan file by name (never `git add -A`), and commit once
   with a semantic message: type(scope): subject.
3. The commit hook runs the project's gates. If it fails, fix the cause, re-run the task's tests
   and commit again. Never pass --no-verify.
Reply with the commit SHA and the hook's result, or with the failure you could not fix.
```

## Fix review findings (sent to a fresh subagent)

```
A review of the whole branch found the issues below. Verify each one, fix the real ones, and
commit.

Working directory: WORK_PATH
Plan: PLAN_FILE_PATH. Its Execution section names the validation commands.
Progress: PROGRESS_FILE_PATH. Read it for what earlier tasks and review rounds found and fixed.

FINDINGS:
FINDINGS_LIST

DESIGN_BLOCK

Project rules (apply them throughout):
USER_RULES

How to work:
1. For each finding, read the code at its file:line with enough context to judge it. Classify it
   as confirmed, or as a false positive when the issue does not exist or is already handled.
2. Fix every confirmed finding, adding the tests a finding asks for.
3. You write last, after the review, so nothing checks your output. Re-read what you added and
   hold it to the project rules above.
4. Validate with the commands in the plan's Execution section and the project rules. Run only the
   test files you wrote or edited, and report passed + skipped == collected.
5. Stage the files you changed by name (never `git add -A`) and commit once with a semantic
   message: fix(scope): address review findings. The commit hook runs the project's gates. If it
   fails, fix the cause and commit again. Never pass --no-verify.
6. Leave nothing behind outside the diff: no stray files, processes or containers.

Nobody is available to answer questions. Decide judgment calls from the plan's intent, then the
project's rules and agent docs, then the surrounding code. When a call is still 50/50, take the
smaller, more reversible option, and record it.

Your final message is this report and nothing else:
FIXES: one line per finding, as "fixed: <file:line> — <what changed>" or
  "false positive: <finding> — <why>"
COMMIT: the SHA and the hook's result, or the failure you could not fix
VALIDATION: each command you ran and the summary line of its result
DECISIONS: judgment calls the findings did not settle, one per line, or "none"
```

`DESIGN_BLOCK` is left out unless the round went to a design discussion with Codex
(`references/review.md`, Step 7). Then it reads:

```
The findings in SYMBOL (FILE) kept coming back, one case per round, so the orchestrator and the
reviewer (Codex) agreed a change to its design. Build that design instead of patching the finding,
and treat the findings in SYMBOL above as cases it must answer:
AGREED_DESIGN
```
