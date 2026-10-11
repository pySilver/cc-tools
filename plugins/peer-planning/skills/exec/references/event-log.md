# The event log

`RUN_DIR/events.jsonl` holds one JSON object per line, appended by `scripts/log-event.py`. Every
line carries `ts` (UTC, ISO 8601 to the second) and `event`. The fields below follow.

The script writes each record a second time, to `RUN_DIR/events.js`, as a `peerEvent({...});`
line. The monitor page runs from a `file://` URL, where it cannot read a file with `fetch`, but it
can load a script. `events.jsonl` stays the record.

Two readers use it: a monitor that shows the run live, and whoever tunes this skill from past runs.
Both depend on the timestamps, so log a step when it happens, never afterwards from memory. The
monitor reads these names, so a change here is a change to the monitor as well.

`key=value` stores a string. `key:=value` stores JSON, for counts and flags: `task:=3`,
`must_fix:=2`, `discuss:=false`. A commit SHA is always `sha=…`, a string.

| Event | Logged when | Fields |
|---|---|---|
| `run.start` | setup is complete | `plan`, `tasks:=N` (the plan's task count), `work_path`, `branch`, `executor`, `session` (this session's agterm id) |
| `codex.ready` | Codex answered the setup check | `files:=true\|false` (whether it can write long replies) |
| `task.start` | a task begins | `task:=N`, `title`, `discuss:=true\|false` |
| `discuss.request` | a discussion message is sent | `task:=N` |
| `discuss.reply` | Codex's discussion reply is read | `task:=N`, `points:=N` (0 for `AGREED`) |
| `discuss.agreed` | Codex replied `AGREED` to the proposal | `task:=N` |
| `discuss.stalled` | the exchange ended without agreement and went to the user | `task:=N` |
| `ruling` | the user ruled on a disagreement | `task:=N`, `on=discussion\|review` |
| `implement.start` | the implementer is spawned | `task:=N`, `agent_id`, `agent_type` |
| `implement.done` | the implementer's report is read | `task:=N`, `status=done\|blocked` |
| `review.request` | a review or re-review message is sent | `task:=N`, `round:=N` |
| `review.reply` | Codex's review is read | `task:=N`, `round:=N`, `verdict=lgtm\|must_fix`, `must_fix:=N` |
| `fix.start` | the implementer is resumed with accepted items | `task:=N`, `round:=N`, `items:=N` |
| `fix.done` | the implementer's fix report is read | `task:=N`, `round:=N` |
| `commit` | the task's commit is confirmed | `task:=N`, `sha` |
| `codex.clear` | `codex-clear.sh` returned | `task:=N`, `exit:=N` |
| `task.done` | the task is closed | `task:=N`, `sha` |
| `stage.start` | the branch review loop or the polish step begins | `stage=review\|polish`, `iteration:=N` for review |
| `stage.done` | that stage ends | `stage=review\|polish`, `iteration:=N` for review |
| `run.end` | the completion report is given | |

What a run spends waiting follows from the last line: after `implement.start` or `fix.start` the
implementer is working, and after a `*.request` Codex is. Nothing needs logging to mark a wait.
