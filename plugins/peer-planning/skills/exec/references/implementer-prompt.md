# Implementer prompts

Three prompts go to the implementation subagent: one to start a task, one to apply Codex's
review, and one to commit. Substitute every `UPPER_CASE` token before sending, because the
subagent runs in a fresh context and knows none of these values.

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
5. Leave nothing behind outside the diff: no stray files, processes or containers.

Nobody is available to answer questions during this task. Decide judgment calls from the plan's
intent, then the project's rules and agent docs, then the surrounding code. When a call is still
50/50, take the smaller, more reversible option, and record it.

Your final message is this report and nothing else:
STATUS: DONE | BLOCKED
APPROACH: the design you built, in two to five bullets
CHANGED: one line per file, saying what changed
VALIDATION: each command you ran and the summary line of its result
DECISIONS: judgment calls the plan did not settle, one per line, or "none"
DEVIATIONS: where the result differs from the agreed approach and why, one per line, or "none"
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

Apply each one, or report why one is wrong, with the evidence (path and symbol). Re-run the
validation from your last report, then report in the same format as before.
```

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
