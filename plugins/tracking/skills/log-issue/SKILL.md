---
name: log-issue
description: >
  Captures a finding just discussed in the conversation into the project's
  standing issue register at docs/issues/ — one file per entry, an index row,
  delete-on-decision. Initializes the register (directory + README contract)
  on first use. Use for a real defect, an open decision, or follow-up work
  that surfaced as a side effect of other work and is not yet a plan and not
  owned by a dated review. Activates on "log this issue", "log an issue",
  "park this as an issue", "register this issue", "register this decision",
  "add this to the issue register", "add it to docs/issues", "issue log
  this", or "log-issue".
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# log-issue

A finding surfaced mid-conversation — a defect, an open decision, follow-up
work. It is real, but it is not today's task. Without a home it either derails
the current work or evaporates. This skill writes it into the project's
standing issue register at `docs/issues/` so the current work continues and
the finding survives with enough context to act on later.

## Admission gate — check before writing

An entry belongs in the register only when **all three** hold:

1. The finding is real and **re-derivable from current code** — someone can
   confirm it exists without trusting this conversation.
2. Acting on it needs an **owner decision**, or it is **deferred on purpose**.
3. **No dated review owns it** — findings born in a review keep their own
   register under `docs/reviews/<date>/`.

When the gate fails, say where the finding belongs instead of logging it:

- Fixable in a few minutes with no decision needed → offer to fix it now.
- Already scheduled work → it belongs on the project's status board / queue
  (`docs/STATUS.md` if present), not here.
- Born in a dated review that has its own register → log it there, in that
  register's own format.

## Step 1 — locate the register; the project's README is the contract

Look for `docs/issues/README.md`.

- **It exists:** read it. Its file-shape section (frontmatter fields, ID
  scheme, body expectations) **overrides everything below** — projects evolve
  their register; the skill follows the project, never the other way around.
- **It does not exist:** initialize the register first — create `docs/issues/`
  and write the README from the template at the bottom of this skill, adapting
  the one project-specific bit (the frontmatter example's `area` value) to
  this repo. Then continue.

## Step 2 — write the entry

One file per entry: `<ID>-<short-slug>.md`.

**ID:** a short UPPERCASE prefix naming the subsystem or area the issue lives
in (derive from the code it touches — e.g. `FEEDNET`, `SEARCH`, `AUTH`), plus
a 3-digit sequence. Glob `docs/issues/<PREFIX>-*.md` for the next free number.
A subsystem prefix keeps entries standalone and avoids colliding with any
review register's numbering.

**Frontmatter** (unless the project README says otherwise):

```yaml
---
id: FEEDNET-001
type: open_decision   # or: issue | future_work
status: open — awaiting owner decision
area: products
affects: [products, ingestion]
date: 2026-08-09
---
```

Keep the taxonomy at these three `type` values. There is deliberately no
severity field and no richer status machine: **presence in the register means
open**, and the free-text `status` line carries any nuance. If a project
wants more, it edits its own README and the skill follows.

**Body** — enough context that the decision can be made without reading this
conversation or the branch it came from:

- **What** — the concrete failure run or gap, told with real values and named
  actors, not abstractions ("a failed publish for product 8814 cancels the
  other 499 publishes in the batch", not "errors may propagate").
- **What a reader would otherwise get wrong** — the misreading this entry
  exists to prevent.
- **Options with their costs** — 2–4, each a couple of lines.
- **Recommendation** — one, stated plainly.

Cite **files and symbols, never line numbers** — a line number rots on the
next edit. If the finding is a decision rather than a bug, open the body with
a one-line banner saying so ("This is a decision, not a bug report.").

## Step 3 — index and report

Add one row to the `## Entries` table in `docs/issues/README.md`:
`| [ID](file.md) | open | one-line summary |`. Then report the created file
path and the row to the user — and nothing else; logging an issue is a
side-quest, so return to the interrupted work without expanding scope.

## Leaving the register (tell the user when relevant)

Entries are **deleted on resolution**, never marked resolved in place — the
outcome lives in whatever records it (an ADR, a plan, the fixing commit). A
resolved entry left in the register reads as still-open. When a conversation
resolves a registered issue, offer to delete its file and index row as part
of that change.

## Init template

Write this as `docs/issues/README.md` when initializing (adapt the
frontmatter example's `area`/`affects` values to the repo):

````markdown
# Issues

Standing register for a known defect or an open decision that is **not**
attached to a dated review and **not** yet a plan.

An entry belongs here when all three hold:

1. The finding is real and re-derivable from current code.
2. Acting on it needs an owner decision, or it is deferred on purpose.
3. No dated review owns it — those keep their own registers under
   `docs/reviews/<date>/`.

## File shape

One file per entry, named `<ID>-<short-slug>.md`, with frontmatter:

```yaml
---
id: AREA-001
type: open_decision   # or: issue | future_work
status: open — awaiting owner decision
area: <subsystem>
affects: [<subsystem>, ...]
date: YYYY-MM-DD
---
```

The ID prefix names the subsystem, so an entry reads standalone and cannot
collide with a review register's numbering.

## What goes in the body

Enough context that the decision can be made without reading the branch it
came from: the concrete failure run, what a reader would otherwise get wrong
about it, the options with their costs, and a recommendation. Cite files and
symbols rather than line numbers — a line number rots on the next edit.

## Leaving the register

Delete the file when the decision is taken. The outcome lives in whatever
records it — an ADR, a plan, or the commit that fixed it. A resolved entry
left here reads as still-open.

## Entries

| ID | Status | Summary |
|---|---|---|
````
