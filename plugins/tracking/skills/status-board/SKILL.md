---
name: status-board
description: >
  Creates and maintains a single project status board at docs/STATUS.md — the
  one file that says what is executing now, what is next in the ordered
  queue, what is gated on the owner, and what is parked with a named
  re-entry trigger. On first use it initializes the board from the repo's
  actual state and wires a pointer plus two standing WIP rules into the
  project's CLAUDE.md. Use to create the board, to update it after work
  lands ("update the status board"), or when queue order changes. Activates
  on "status board", "create STATUS.md", "update STATUS.md", "update the
  status board", "add this to the queue", "park this work", or
  "status-board".
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# status-board

A project drifts when its truth is scattered — plans that rotted before
execution, ADRs awaiting plans nobody lists, branches nobody remembers. The
board is the single answer to "what is the state of this project": one
screen, four sections, pointers only. Everything else (plans, ADRs, issue
files) is detail behind a link.

## The contract the board enforces

Two standing rules ride with the board, and the board is where they are
visible:

1. **A plan is written and refined only when it reaches the front of the
   queue, and is executed immediately after refinement.** A refined-plan
   inventory is what rots — the codebase moves underneath it.
2. **The plans directory holds at most 2 plan files.** Anything else is
   completed, deleted, or a one-line queue entry on this board.

And one structural rule for the board itself: **pointers, never copies.** A
queue line links its ADR, plan, or issue file; it never restates their
content. An issue register (`docs/issues/`) gets a single pointer line, not
mirrored entries — two lists of the same thing always diverge.

## Step 1 — locate or initialize

Look for `docs/STATUS.md`. If it exists, skip to Step 3 (update).

**Initialize** otherwise — but never from imagination. Gather the real state
first:

- `ls docs/plans/` and `docs/plans/completed/` (what is mid-flight vs done)
- recent `git log --oneline -15` and `git branch -vv` (what is executing)
- accepted-but-unimplemented ADRs the conversation or the user names
- an existing tracker (a program README, a review S-table) — if one is
  authoritative today, mirror its live rows as queue entries and link back;
  do not fork its content

Draft the board, then **show the proposed queue order to the user before
writing** — the ordering is an owner decision, not an inference.

## Step 2 — the board shape

```markdown
# Status

> The single source of truth for what runs now and what is next.
> Rules: a plan is written/refined only at queue front and executed
> immediately after; docs/plans/ holds at most 2 plan files; this board
> carries pointers, never copies.

Last touched: YYYY-MM-DD

## Executing now (max 1)

- <work item> — <plan or branch link>

## Next (ordered)

1. <item> — <ADR / plan / issue link>, <one-line why-this-order note if any>
2. ...

## Gated on owner

- <gate> — <what unblocks it>

## Parked (each with a named re-entry trigger)

- <item> — trigger: <the observable event that reopens it>

## Issue register

Open defects and decisions live in [docs/issues/](issues/) — not mirrored
here.
```

Adapt section limits to the project only if the user says so; the defaults
are: one item executing, an ordered Next list, every Parked item carrying a
trigger (a parked item with no trigger is forgetting with extra steps —
either give it one or delete it).

## Step 2b — wire CLAUDE.md (init only)

Add a short block to the project's root `CLAUDE.md` so every session loads
the board. Propose this edit to the user before applying:

```markdown
## Project status

`docs/STATUS.md` is the single board: executing now, the ordered queue,
owner gates, parked work. Read it before starting work; update it when work
lands. Two standing rules: a plan is written and refined only at queue
front (and executed immediately after); `docs/plans/` holds at most 2 plan
files.
```

If the project distinguishes current-state docs from historical ones, offer
(as an option, not silently) a one-line precedence statement alongside it —
e.g. "code > verified architecture docs > app docs > rules; ADRs and
completed plans are history, never cited for current behavior" — with paths
adapted to the repo's actual layout.

## Step 3 — update mode

When invoked with the board already present:

1. Read the board and the repo signals (plans dir, recent commits) for what
   changed.
2. Apply the moves: finished work leaves *Executing now*; the queue head
   moves up; a newly surfaced gate lands under *Gated on owner*; deferred
   work lands under *Parked* **with a trigger**.
3. Keep every line a pointer. If an update would paste content in, link the
   file instead — and if the content has no file, that is a `log-issue` or a
   plan, not a board entry.
4. Update `Last touched`, show the diff of the board to the user, done. Do
   not expand into executing queue items — the board records, it does not
   drive.

## What this skill refuses to do

- Reorder the queue on its own judgment — proposed order changes are shown
  and confirmed; the queue is the owner's.
- Mirror another tracker's rows while that tracker is still live without a
  link back to it — one of the two must be declared authoritative.
- Add a Parked item without a trigger.
