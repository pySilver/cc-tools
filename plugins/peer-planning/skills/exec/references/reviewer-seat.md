# The reviewer seat

The second voice in `make` and `exec` is a second model family, never the planner's own. Which
model holds the seat follows the owner's order:

| Seat | Model | When |
|---|---|---|
| `astra` | `gpt-6-astra`, reasoning `high` | the default |
| `sol` | `gpt-6.1-sol`, reasoning `xhigh` | the OpenAI week is at least 80% used and at most one usage reset is left |
| `opus` | an Opus subagent at high effort | Codex is unavailable |

`scripts/reviewer-seat.py` picks the seat and prints one JSON object: `seat`, `model`, `effort`,
`reason`, `used_percent`, `resets_left`, `pane_model` (what Codex's status line shows) and
`switch` (whether the pane must change). Weekly use comes from Codex's own rollouts. Resets left
are read only at 80% or more, through `codex-clear.sh --resets`, which opens Codex's `/usage`
screen, reads the count and leaves with Esc; it never sends Enter there. Redeeming a reset still
takes the owner's instruction.

## When to pick

Run the picker at the two points where the pane may change hands, and nowhere else:

- **At setup**, just before the first clear (`exec` setup step 10), or before the first message
  in `make`.
- **At each close**, just before `codex-clear.sh` (`exec` "E. Close" step 2).

Never in the middle of a discussion or a review: the argument needs the thread and the model it
stands on.

## Switching between Codex models

When `switch` is true and the seat is `astra` or `sol`, pass the seat to the clear:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/codex-clear.sh --model <model> --reasoning <effort>
```

It types `/model <model> --reasoning=<effort>` right after the `/clear`, waits for Codex to
confirm, then sends the READY prompt as usual. A switch survives later clears, so a plain clear is
enough while the seat stays. Log `reviewer.switch` with `from` (the old `pane_model`, or `opus`),
`to` (the new seat), `reason` (the picker's) and `used_percent`. In `make`, where nothing is
cleared before the first message, run the clear with the seat once before the first message only
when the picker says `switch`.

## Codex unavailable

Codex is unavailable when one of these holds, and only then:

- `codex-clear.sh --check` fails because no Codex runs in the right pane, or it never registers for
  mail;
- `mailbox-chat.py say` reports a stale thread ("no rollout found") that a clear does not fix;
- a message gets no answer at all and the pane shows a Codex error (a usage-limit banner, a
  crashed CLI, a network error) rather than a turn in progress.

A slow answer is not one of them: Codex at `xhigh` can think for many minutes. Run the picker
with `--codex-down "<the evidence, in a few words>"`, log `reviewer.switch` with `to=opus`, and
tell the user in one line.

The Opus seat is a fresh read-only subagent at high effort for each exchange that would have gone
to Codex. Give it the exact message `references/codex-messages.md` would have sent, with the same
`WORK_PATH`, report path and file offer, and tell it it is read-only and that its reply goes to
`RUN_DIR/msgs/NNN-opus-<kind>.md`. Read that reply exactly as a Codex reply: the same `LGTM`,
`MUST-FIX: N`, `AGREED` and `Changed:` conventions apply. A re-review in the same task resumes the
same subagent; the next task starts a new one, which is the Opus seat's version of a clear.

Return to Codex at the next close where `codex-clear.sh --check` passes again: run the picker
without `--codex-down`, clear with the seat it names, and log `reviewer.switch` with `from=opus`.
