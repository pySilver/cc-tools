# The reviewer seat

The second voice in `make` and `exec` is a second model family, never the planner's own. The
models and efforts come from the plugin's `models.toml`, the table of recommended models both
skills read:

| Seat | Model | When |
|---|---|---|
| `codex` in `make` | `gpt-6.1-sol`, reasoning `xhigh` (`[seat.make]`) | the default while a plan is argued and checked |
| `codex` in `exec` | `gpt-6.1-sol`, reasoning `high` (`[seat.exec]`) | the default while tasks are reviewed |
| `opus` | an Opus subagent at high effort | Codex is unavailable |
| `kept` | the model Codex's pane ran at setup | the owner chose to keep it for the run, at the model check |

The owner ruled the two Codex seats on 2026-11-12, in place of `gpt-6-astra` at high for both:
Sol is faster and cheaper and still a strong model, and the branch review's revmux rounds catch
what a task review at `high` missed. The weekly-use rule that moved the seat from Astra to Sol at
80% went with it, since no cheaper Codex seat is left to move to.

`scripts/reviewer-seat.py make|exec` picks the seat and prints one JSON object: `skill`, `seat`,
`model`, `effort`, `reason`, `pane_model` (what Codex's status line shows), `pane_default` (the
model and effort in Codex's `config.toml`, which every cleared conversation starts on), `switch`
(whether the seat changes hands) and `clear_flags` (what every clear carries).

## When to pick

Run the picker at the two points where the pane may change hands, and nowhere else, with the
skill's name as its first argument (`reviewer-seat.py make` or `reviewer-seat.py exec`):

- **At setup**, at the model check, before the first clear (`exec` setup step 10), or before the
  first message in `make`. A plan argued on the `make` seat is followed by `exec`'s setup clear,
  which moves the same pane to the `exec` seat.
- **At each close**, just before `codex-clear.sh` (`exec` "E. Close" step 2).

Never in the middle of a discussion or a review: the argument needs the thread and the model it
stands on. Never right after a clear to check it either: a clear with `clear_flags` that exits 0
has already seen Codex confirm the model.

## Switching between Codex models

A `/clear` does not keep a `/model` switch: the new conversation starts on `pane_default`. Four
runs on 2026-11-07 logged a switch to Sol, and Codex's rollouts show the conversation after each
one's next plain clear running Astra. So the seat is applied on every clear, not once. Pass the
picker's `clear_flags` to every clear while the seat is `codex` or `kept`:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/codex-clear.sh <clear_flags>
```

`clear_flags` is `--model <model> --reasoning <effort>` whenever the seat differs from
`pane_default` or the pane shows another model, and empty when a plain clear already lands on the
seat. When `config.toml` names no model, the default is unknown and `clear_flags` is never empty.
With the flags, the script types `/model <model> --reasoning=<effort>` right after the `/clear`,
waits for Codex to confirm, then sends the READY prompt as usual.

Log `reviewer.switch` only when `switch` is true, with `from` (the old `pane_model`, or `opus`),
`to` (the new seat), and `reason` (the picker's). Re-applying the same seat at a
clear is not a switch and logs nothing beyond `codex.clear`. Because each clear re-applies the
seat, the pane shows the seat at the next close, and `switch` is true only when the seat changes.

In `make`, where nothing is cleared before the first message, run the clear with `clear_flags`
once before the first message only when the picker says `switch` and the owner chose the seat at
the model check; the planning conversation keeps its model for as long as it is not cleared.

## A kept model

At setup, the model check asks the owner when Codex's pane runs a model other than the seat. When
the owner keeps the pane's model, `exec` writes `MODEL ACCEPTED codex <model> <effort>` to
`progress.md`, picks again with `--keep "<model> <effort>"` before the setup clear, and passes
it to every later pick of the run. A pane whose model could not be read offers no keep, and the
picker refuses `--keep` with `unknown` in it. The seat is then
`kept`, and `clear_flags` puts the kept model back at each clear
just as it would a seat. `--codex-down` still wins: the Opus seat replaces a kept model as it
would any other, and the next pick with `--keep` returns to it.

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
without `--codex-down`, clear with its `clear_flags`, and log `reviewer.switch` with `from=opus`.
