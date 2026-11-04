# Messages to Codex while planning

Send every message through `mailbox-chat.py say --stdin` with a quoted heredoc. The script adds
the `[peer chat]` label and a closing line telling Codex how to reply, so write neither, and leave
"reply by" instructions out of the message. Keep each message one paragraph. The user reads both panes, so a message has to make sense on its own.

**A file carries what a paragraph cannot.** When a message needs code, a list of more than a
handful of items, or a position that has outgrown a paragraph, write that part to
`RUN_DIR/msgs/NNN-claude-plan.md` and name the path in the message. The message still says the
gist. Number the files in order from `001`, mine and Codex's in one sequence.

**The work is where the plan is.** Codex's own directory is wherever the user started it. The
opening message names `REPO_PATH`, the absolute path of this checkout, and asks Codex to run its
commands there.

**No verdict tokens.** The Pair sessions rule this exchange follows produces a settled position, a
located disagreement or a checked fact, not a verdict, and nothing here logs a first word the way
exec does. Codex says plainly whether it agrees and why, or what it refutes and with which cite. A
question closes when you record its outcome; the whole exchange closes with "nothing further"
from you, and Codex adds no turn after that.

`FILE_OFFER` in the messages below reads: "If your answer needs more than a paragraph, write it to
RUN_DIR/msgs/NNN-codex-plan.md and name it; if you cannot write there without an approval prompt,
reply in chat instead." Once Codex has said it cannot write there, drop the offer.

## Opening the discussion

```
A planning discussion, before any plan is written. The work is in REPO_PATH, not necessarily in the directory you were started in: run every command there (cd REPO_PATH && ...) and open files by that path. You are read-only there: read and run non-mutating checks, and leave nothing behind. The problem: PROBLEM_OR_FILE. Success means SUCCESS. Binding constraints: CONSTRAINTS. Starting points: STARTING_POINTS. We take one question at a time. The first: QUESTION. My position: POSITION_OR_FILE, priced against MINIMAL_OPTION. Open what it cites and either agree, or refute it with a cite (path and symbol) or a concrete input that breaks it. If you see an approach I have not named, name it. Any addition you propose, such as a guard, a column, a lock or a retry, must name the failure it prevents, the input that produces it, whether that input is realistic here, and what breaks without it. FILE_OFFER
```

`PROBLEM_OR_FILE` is the problem as Step 1 settled it, or a backlog item's path. A user-set
constraint goes in `CONSTRAINTS` as binding, not as a position to argue.

## Continuing

Answer each of Codex's points in order: accepted, with how the position changes; or disputed, with
your own cite. Verify every claim Codex makes about the code with your own tool call first. Close
with the revised position in full, so the thread always holds the current version.

## The next question

```
Next planning question, same rules and same place, REPO_PATH: QUESTION. My position: POSITION_OR_FILE, priced against MINIMAL_OPTION. Say whether you agree, and refute anything you do not with a cite. FILE_OFFER
```

## Relaying a ruling

```
The user ruled on QUESTION: RULING. It goes into the plan's Decisions as an owner ruling; it is not reopened. No reply is needed.
```

## Relaying Fable's second opinion

```
We stalled on QUESTION and both of us put it down to the design, so I asked Fable once for a second opinion, with both our positions. Its answer is in FABLE_FILE; I checked its cites: CHECK_RESULT. Read it and argue the question once more: agree with a position (yours, mine or Fable's), or refute with a cite. Same rules as before. Say whether you agree, and refute anything you do not with a cite. FILE_OFFER
```

## Asking for the draft read

```
The plan is drafted at PLAN_PATH, in REPO_PATH. Its Decisions section records what we settled. Check that the plan says it, not the decisions over again: does every Decision reach the Constraints or Done when of each task it binds, do the tasks fit together, can each be reviewed on its own, and is each Done when evidence an executor can produce? A point that reopens a decision names that decision. Read-only, as before. Say whether you agree, and refute anything you do not with a cite. FILE_OFFER
```
