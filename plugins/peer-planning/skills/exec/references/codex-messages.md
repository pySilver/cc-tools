# Messages to Codex

The conversation happens in chat. Send every message through `peer-chat.py --to codex --stdin`
with a quoted heredoc. The script collapses whitespace to single spaces and adds the "Chat from
Claude:" label itself, so write each message as one paragraph. The user reads both panes, so a
message has to make sense on its own.

**A file carries what a paragraph cannot.** When a message needs code, a diff or more than a
handful of items, write that part to `RUN_DIR/msgs/NNN-claude-<kind>.md` and name the path in the
message. The message still says the gist, so the pane stays readable. Number the files in order
across the run; the kinds are `setup`, `discuss`, `review` and `ruling`. The implementer writes
its own reports, as `NNN-implementer-report.md` in the same numbering, and a message names that
file rather than copying it.

Codex may do the same, but only if the setup check showed it can write there. When it can, a
request that is likely to get a long answer names the file Codex may use, `NNN-codex-<kind>.md`
with the request's `NNN`.

Codex's context is cleared between tasks and keeps nothing, so every message states the task, the
working copy and the read-only rule. Use absolute paths, and let the message that opens an
exchange (the setup check, a discussion, a review) say that the work happens in `WORK_PATH` and
ask Codex to run its commands there. Codex's own directory is wherever the user started it,
usually the main checkout, and it cannot change it for the session: a bare `git diff` there
reviews the wrong tree. It can run any command in a directory it is given, by `cd WORK_PATH && …`
or the command's own working directory, and it can read anywhere, so naming the path is enough.

**The first word is the verdict.** A reply to a discussion opens with `AGREED` or `POINTS: N`, a
review reply with `LGTM` or `MUST-FIX: N`, and a reply to a ruling with `ACK`. The orchestrator
logs that word without reading further.

**The last line of a review is the tree.** A review reply, first round or re-review, ends with
`Changed:` and the paths `git -C WORK_PATH status --short` lists. The orchestrator runs that
command itself and compares the two before it logs the verdict: an LGTM given from Codex's own
directory, over an empty diff, reads like any other, and this line is what tells them apart.

## Setup check

```
A peer-planning run over PLAN_FILE_PATH is starting in WORK_PATH. The work happens there, not necessarily in the directory you were started in: run every command there (cd WORK_PATH && ...) and open files by that path. You are read-only there. The only place you may write is RUN_DIR/msgs/, for a long reply. Check that now: write the single word ready to RUN_DIR/msgs/000-codex-setup.md. If you cannot write it without an approval prompt, do not try; reply "no files" instead. Reply by peer-chat to Claude.
```

## Opening a task discussion

```
Task TASK_NUMBER of PLAN_FILE_PATH ("TASK_TITLE"), before any code is written. The work happens in WORK_PATH, not necessarily in the directory you were started in: run every command there (cd WORK_PATH && ...) and open files by that path. You are read-only there: read and run non-mutating checks, and leave nothing behind. The task text is the "### Task TASK_NUMBER:" section of the plan; its Decisions section is settled. My proposed approach: SKETCH_OR_FILE. Open what it cites and either agree, or refute it with a cite (path and symbol) or a concrete input that breaks it. Any addition you propose, such as a guard, a column, a lock or a retry, must name the failure it prevents, the input that produces it, whether that input is realistic here, and what breaks without it. Open your reply with AGREED or POINTS: N. FILE_OFFER Reply by peer-chat to Claude.
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

`REPORT_PATH` is the implementer's own report file. Send:

```
Task TASK_NUMBER of PLAN_FILE_PATH ("TASK_TITLE") is implemented in WORK_PATH and not yet committed. The work happens there, not necessarily in the directory you were started in: run every command there, git -C WORK_PATH status and git -C WORK_PATH diff show the change, and open files by that path. APPROACH_NOTE The implementer's report is in REPORT_PATH. Check the task's outcome. Does the change deliver the approach, every "Done when" item and the plan's Decisions? For a task whose approach was not discussed, judge the APPROACH the report states; it is not settled. Does the evidence exercise what it claims? Read the tests, fixtures and producers it relies on. Raise any correctness defect you see on the way. An existing caller or inverse operation that this change leaves inconsistent with the new behavior is a MUST-FIX. Do not sweep the diff for general rule, architecture or style issues: the branch review covers those. Open your reply with LGTM, or with MUST-FIX: N followed by N numbered items, each with file, symbol and why. End with Changed: and every path that git -C WORK_PATH status --short lists, so I can check we read the same tree. FILE_OFFER Read-only, as before. Reply by peer-chat to Claude.
```

`APPROACH_NOTE` only says where the approach is; the request itself says how to judge it. For a
discussed task it reads: "The approach was agreed beforehand and is written under the task's
heading in the plan." For any other task it reads: "The approach was not discussed beforehand; the
implementer states it in the APPROACH section of the report."

The request asks for an outcome check, not a sweep of the diff, and leaves rule, architecture and
style issues to the branch review. Claude and Codex settled that scope between them on
2026-10-30. It is a pair-settled position, not a measurement: nothing yet shows that the
narrower check and the branch review together catch what the full per-task review did.

`FILE_OFFER`, when Codex can write files, reads: "If the items need quoted code, put them in
RUN_DIR/msgs/NNN-codex-review.md and name it."

## Re-review after fixes

```
The must-fix items for Task TASK_NUMBER are addressed in WORK_PATH, still uncommitted; the implementer's report, with what it did on each item, is in REPORT_PATH. DISPUTES Please re-check only those items and open your reply with LGTM or MUST-FIX: N for what is still open, and end with Changed: as before.
```

`DISPUTES` names each item the implementer refuted, with the implementer's cite from its
`REFUTED` line ("The implementer disputes item N: …"), or is left out.

## Opening a design discussion in the branch review

Sent when the branch review's stop rule fires (`references/review.md`, Step 7). Codex has been
cleared since its last task and knows nothing of the branch review, so the message carries it all.
`FINDINGS_OR_FILE` is each round's gating finding in that symbol, with its round and `file:line`,
taken from `progress.md`, or the path of a file holding them. `FILE_OFFER` is the one a task
discussion uses.

```
The branch review of PLAN_FILE_PATH keeps finding defects in SYMBOL (FILE): FINDINGS_OR_FILE. Each fix answered one case and exposed the next. The work happens in WORK_PATH, not necessarily in the directory you were started in: run every command there (cd WORK_PATH && ...) and open files by that path; git -C WORK_PATH diff DEFAULT_BRANCH...HEAD shows the branch. You are read-only there. Step back from the single findings: is the design of SYMBOL right for what the plan asks of it? Either propose the change that answers the whole class of these findings, or show with a cite that the design holds and the findings are separate defects. Any addition you propose, such as a guard, a column, a lock or a retry, must name the failure it prevents, the input that produces it, whether that input is realistic here, and what breaks without it. Open your reply with POINTS: N, one point per change, or POINTS: 0 when the design holds. FILE_OFFER Reply by peer-chat to Claude.
```

From there the exchange runs as a task discussion does, through "Continuing the discussion" and
"Proposing agreement", with the design in place of the approach.

## Asking again after a mismatch

When the `Changed:` line differs from `git -C WORK_PATH status --short`, Codex has most likely run
git in its own directory. Log `review.mismatch` instead of a verdict and send:

```
Your Changed line for Task TASK_NUMBER does not match WORK_PATH: git -C WORK_PATH status --short lists TREE_PATHS, and you named CODEX_PATHS. You may have run git in your own directory. Review again in WORK_PATH, the same request as before, and end with Changed: as before.
```

A second mismatch on the same round goes to the user. A verdict is never logged over a tree Codex
did not read.

## Relaying the user's ruling

```
The user ruled on our disagreement over Task TASK_NUMBER: RULING. That settles it; FINAL_APPROACH_IF_DISCUSSION. Reply ACK.
```
