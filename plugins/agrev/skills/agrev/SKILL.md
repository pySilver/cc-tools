---
name: agrev
description: Review a markdown document - usually a plan in docs/plans/ - with the user in plannotator, shown in an agterm session right after this one. The user annotates the rendered document (comments, deletions, labels, image attachments) and presses Send Feedback or Approve; you act on the feedback by editing the document, then reopen it for the next round with your replies pinned to the phrases they concern, and plannotator shows what changed since the last round. Use when the user says "agrev", "/agrev", "review this plan", "let's review the plan", "open the plan for review", "annotate the plan", "comment on the plan", or wants to read and mark up a markdown document rendered rather than as raw text or a diff.
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/review.py *)
---

# agrev

A review runs in rounds. Each round the user reads the document in plannotator, marks it up and
sends a decision; you change the document, answer each point, and open the next round. It ends when
the user approves. `scripts/review.py` (below: `review.py`) does everything that touches plannotator
and agterm.

plannotator must be installed (`~/.local/bin/plannotator`); when `open` says it is not, give the user
the install command it prints and stop.

## 1. Open a round

Take the file the user named, or the markdown document the conversation is about; when two or more
fit, ask as a plain numbered list, never the AskUserQuestion widget.

```bash
${CLAUDE_SKILL_DIR}/scripts/review.py open <file>
```

It starts plannotator, shows it in a session named "<file> review" right after this one, and switches
the user there; the chat is one click away and never covered. `--no-follow` opens it without
switching; `--here` lays it over the current session instead, when the user asks for that.

Then wait for the decision, with `run_in_background: true`:

```bash
${CLAUDE_SKILL_DIR}/scripts/review.py wait <file>
```

Tell the user in one line that the review is open, then end your turn. Do not poll: the background
`wait` exits when the user decides, and its completion wakes you. You cannot see comments while the
user writes them; they arrive together when the user presses Send Feedback.

## 2. When `wait` returns

plannotator's server ends with each decision, so `wait` replaces its page: after Send Feedback the
review session shows "Feedback sent" until the next round opens there, and after Approve it shows
that the review is done. A Close leaves the session as the user left it.

- **APPROVED**: the user is done. Carry any notes it prints into later work, say so in one line,
  and stop. Run `review.py close <file>` to remove the review session.
- **Closed without a decision**: the user closed the page (its Close button, or ⌘W). Say so; do not
  reopen unless asked.
- **CHANGES REQUESTED**: the feedback follows, one numbered item per annotation, each naming the
  quoted text and, for a comment, the source lines it sits on (`## 3. (lines 8–9) Feedback on: "…"`).
  "Remove this" items are deletions the user wants.

For CHANGES REQUESTED, handle every item:

1. **Change the document yourself.** You are the only writer during a review: edit the file with
   your normal tools. A question gets an answer, and the document changes too when the answer
   belongs in it. A point you disagree with gets your reason instead of an edit.
2. **Write your replies** as a JSON list, one entry per item:
   ```json
   [{"quote": "a phrase from the CURRENT file, next to what you changed or answered",
     "text": "Done: … / Kept, because … / Question: …"}]
   ```
   `quote` pins the reply to that phrase in the page. Copy it from the document as it now reads,
   as plain words without markdown markers (`Use one writer`, not `Use **one** writer`); a phrase
   that is not in the document cannot be pinned. Leave `quote` out for a reply about the whole
   document.
3. **Summarize in chat**: one line per item, what changed or why not.
4. **Open the next round** with the replies, and wait again in the background:
   ```bash
   ${CLAUDE_SKILL_DIR}/scripts/review.py open <file> --comments <replies.json>
   ${CLAUDE_SKILL_DIR}/scripts/review.py wait <file>
   ```
   plannotator shows "+N / −N since last review" on the document and a Versions tab, so the user
   sees exactly what you changed, with your replies beside the phrases.

To add a comment to a round that is already open, pipe the same JSON to
`review.py comment <file>`; it appears in the page at once.

## Notes

- plannotator exports your pinned comments back as if the user had written them. `wait` removes
  them from the feedback; when it cannot match one it prints a NOTE, and any item repeating your own
  words is yours, not the user's.
- With your comments on the page, plannotator's main button reads "Send Feedback"; Approve is in its
  dropdown. Mention it when the user may want to approve straight away.
- plannotator keeps its settings and first-run choices in cookies. A proxy in front of it saves them
  in `~/.cache/agrev/plannotator-cookies.json`, so the onboarding dialogs appear only once.
- A "Draft Recovered" dialog can appear when an earlier round's page left a draft. Restoring it can
  duplicate your pinned comments; Dismiss is the safe answer.
- Each round's files (plannotator's log, the result, your comments) are in
  `~/.cache/agrev/runs/<round>/`; `review.py status <file>` names the current one.
- Every plannotator page load checks GitHub for a newer release; no content is sent.
