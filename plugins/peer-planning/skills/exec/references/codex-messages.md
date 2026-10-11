# Messages to Codex

The conversation happens in chat. Send every message through `peer-chat.py --to codex --stdin`
with a quoted heredoc. The script collapses whitespace to single spaces and adds the "Chat from
Claude:" label itself, so write each message as one paragraph. The user reads both panes, so a
message has to make sense on its own.

**A file carries what a paragraph cannot.** When a message needs code, a diff, the implementer's
report or more than a handful of items, write that part to `RUN_DIR/msgs/NNN-claude-<kind>.md` and
name the path in the message. The message still says the gist, so the pane stays readable. Number
the files in order across the run; the kinds are `setup`, `discuss`, `review` and `ruling`.

Codex may do the same, but only if the setup check showed it can write there. When it can, a
request that is likely to get a long answer names the file Codex may use, `NNN-codex-<kind>.md`
with the request's `NNN`.

Codex's context is cleared between tasks and keeps nothing, so every message states the task, the
working copy and the read-only rule. Use absolute paths: Codex's own directory may be the main
checkout while the work happens in a worktree.

**The first word is the verdict.** A reply to a discussion opens with `AGREED` or `POINTS: N`, a
review reply with `LGTM` or `MUST-FIX: N`, and a reply to a ruling with `ACK`. The orchestrator
logs that word without reading further.

## Setup check

```
A peer-planning run over PLAN_FILE_PATH is starting in WORK_PATH, where you are read-only. The only place you may write is RUN_DIR/msgs/, for a long reply. Check that now: write the single word ready to RUN_DIR/msgs/000-codex-setup.md. If you cannot write it without an approval prompt, do not try; reply "no files" instead. Reply by peer-chat to Claude.
```

## Opening a task discussion

```
Task TASK_NUMBER of PLAN_FILE_PATH ("TASK_TITLE"), before any code is written. Working copy: WORK_PATH. You are read-only there: read and run non-mutating checks, and leave nothing behind. The task text is the "### Task TASK_NUMBER:" section of the plan; its Decisions section is settled. My proposed approach: SKETCH_OR_FILE. Open what it cites and either agree, or refute it with a cite (path and symbol) or a concrete input that breaks it. Any addition you propose, such as a guard, a column, a lock or a retry, must name the failure it prevents, the input that produces it, whether that input is realistic here, and what breaks without it. Open your reply with AGREED or POINTS: N. FILE_OFFER Reply by peer-chat to Claude.
```

`SKETCH_OR_FILE` is the sketch itself when it fits a paragraph, or its gist and the path of the
file holding it. `FILE_OFFER`, when Codex can write files, reads: "If your points need code, put
them in RUN_DIR/msgs/NNN-codex-discuss.md and name it."

## Continuing the discussion

Answer each of Codex's points in order: accepted, with how the sketch changes; or disputed, with
your own cite. Verify every claim Codex makes about the code with your own tool call before
accepting or disputing it. Close with the revised approach in full, so the thread always holds the
current version; when it has outgrown a paragraph, it goes in a new file.

## Proposing agreement

```
Agreed approach for Task TASK_NUMBER: FINAL_APPROACH_OR_FILE. If this is what we agreed, reply AGREED; otherwise open with POINTS: N and name exactly what differs.
```

## Asking for the review

Put the implementer's report in `RUN_DIR/msgs/NNN-claude-review.md`, verbatim, and send:

```
Task TASK_NUMBER of PLAN_FILE_PATH ("TASK_TITLE") is implemented in WORK_PATH and not yet committed. See git diff and git status there. APPROACH_NOTE The implementer's report is in REPORT_PATH. Review against the approach, the task's "Done when" list and the plan's Decisions. Open your reply with LGTM, or with MUST-FIX: N followed by N numbered items, each with file, symbol and why. Leave out style preferences unless they break a project rule. FILE_OFFER Read-only, as before. Reply by peer-chat to Claude.
```

`APPROACH_NOTE` for a discussed task reads: "Review it against the agreed approach under the
task's heading in the plan." For any other task it reads: "The approach was not discussed
beforehand; the implementer states it in the APPROACH section of the report, so review it as well
as the code."

`FILE_OFFER`, when Codex can write files, reads: "If the items need quoted code, put them in
RUN_DIR/msgs/NNN-codex-review.md and name it."

## Re-review after fixes

```
The must-fix items for Task TASK_NUMBER are addressed in WORK_PATH, still uncommitted: FIX_SUMMARY. DISPUTES Please re-check only those items and open your reply with LGTM or MUST-FIX: N for what is still open.
```

`DISPUTES` names each item you dispute with your own cite, or is left out.

## Relaying the user's ruling

```
The user ruled on our disagreement over Task TASK_NUMBER: RULING. That settles it; FINAL_APPROACH_IF_DISCUSSION. Reply ACK.
```
