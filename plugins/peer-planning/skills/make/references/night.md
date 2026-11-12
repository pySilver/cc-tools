# Night mode

`/peer-planning:make --night <backlog item>` drafts a plan with nobody at the keyboard. A
scheduled job starts it with `claude -p --permission-mode auto` in a worktree it prepared, on a
branch of its own, for a backlog item the triage marked "an agent can take it". The owner approves
the plan in the morning and starts exec themselves; night mode never executes anything.

Everything in `SKILL.md` holds, except what follows.

## Codex without a pane

There is no agterm split and no mailbox. Each exchange with Codex is one `codex exec` thread that
the planner resumes, so the argument keeps its context across turns:

- Pick the seat with `skills/exec/scripts/reviewer-seat.py make` as by day. Its `model` and `effort`
  go on the command line (`-m <model> -c model_reasoning_effort="<effort>"`); with the Opus seat,
  the reference's Opus subagent takes Codex's place.
- The model check runs without `--seat`, since each `codex exec` call names the seat's model
  itself, and asks nothing: each row that differs goes in the plan's header beside the planning
  line, with its current and recommended value, for the owner to read in the morning.
- The first message of an exchange:
  `codex exec -C "$WORK_PATH" -s read-only --json -m <model> -c model_reasoning_effort="<effort>" - < RUN_DIR/msgs/NNN-claude-plan.md`,
  run in the background. Its JSON events name the thread (`thread.started`, `thread_id`); note it
  in `RUN_DIR/night-threads.md`. The reply is the last agent message; save it verbatim as
  `RUN_DIR/msgs/NNN-codex-plan.md`.
- Every later turn of the same exchange, with the flags before `resume` (measured on Codex
  0.167; the resumed thread keeps the earlier turns):
  `codex exec -C "$WORK_PATH" -s read-only --json resume <thread_id> - < RUN_DIR/msgs/NNN-claude-plan.md`.
- The pair rules apply unchanged: one question at a time, a turn that only repeats the last ends
  the exchange, "nothing further" closes it. The saved files are the record the owner reads in the
  morning in place of watching the pane.

## No questions to the owner

Nothing waits for an answer at night: huddle refuses in an unattended run, and nobody would see a
question in the terminal.

- **Intent** comes from the backlog item: its concrete run, its options and its recommendation
  are the Overview. An item without a recommendation, or whose open unknown is a value judgment,
  should not have been picked; stop, and say so in the summary.
- **A question that would go to the owner** (a stalled point, a choice between surviving
  approaches, a story's wording) goes through `decide:gate`'s judge first. On *decided*, follow
  the ruling it quotes and cite it. On anything else, write the question into a section
  `## Questions for the owner` near the top of the plan, as the panel's card when it is about
  users (run `decide:panel`; at night its Sol personas run as separate
  `codex exec -m gpt-6.1-sol -c model_reasoning_effort="high" -s read-only` calls with the persona
  prompt from its `references/messages.md`, their replies saved under the panel directory), and go
  on with the recommended option marked **pending the owner's answer** wherever the plan relies
  on it. Tasks that depend on an open question say so in their first line.
- **The stories** are drafted from the item and read by the personas the same way. A flagged
  story stays in the plan with the flag and the answers that raised it.

## The gates, headless

Run the project's plan checkers and its plan review exactly as Step 3 says, with the revmux round
run headless. Fix what comes back. A finding that reopens a question you cannot settle from the
code or a ruling joins `## Questions for the owner`.

## The end of a night

- Commit the plan on the night branch with the project's commit rules, so the morning finds it in
  git rather than in a working tree. Never touch the default branch.
- Write `RUN_DIR/night-summary.md`: the plan's path and branch, the item it came from, how many
  questions wait for the owner (each in one line), the expert round's result, and anything that
  stopped the night early. The scheduled job copies its first lines into the morning digest.
- Stop there. Step 4's offer to execute is the owner's, in the morning.
