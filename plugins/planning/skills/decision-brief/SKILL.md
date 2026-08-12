---
name: decision-brief
description: >
  Rebuild the user's context before asking them to choose. Use when a turn
  ends in a judgement call only the user can make and the context needed to
  answer it lives in work they are not holding right now — a plan, an ADR, a
  session from another day. Produces a four-part brief: one concrete run that
  ends badly, two to four forks each replayed against that run with costs,
  a recommendation, and pointers last. Use before presenting a design fork,
  before reporting that an approach has to change, or when about to write a
  verdict out of section names and file paths. Activates on "give me the
  options", "what are my options here", "which way should we go", "write this
  up before I decide", "I don't have the context", "remind me what this was",
  or "decision brief".
---

# decision-brief

The user wrote the design while fully focused. They are not focused now. Section names, file paths, and internal terms are pointers to a model they no longer hold, so a verdict built out of them is unreadable — it asks them to reload a whole design from a pointer before they can even read the question.

## When this fires

Your response ends in a judgement call only the user can make, **and** the context needed to answer it lives in work they are not currently holding: a plan, a design record, an ADR, a session from another day.

It does not fire for:

- a failure you can diagnose and fix yourself — fix it and report cause, then fix;
- a yes/no on a step you just described;
- a question about work done in this session;
- a decision that is small or reversible, or one the user raised themselves this session so the context is already loaded.

When in doubt, one short question beats a four-part brief. A brief on a two-minute fork spends the attention the format exists to protect.

## First, settle the problem. Then write.

Name the guard you first reached for — the lock, the retry, the re-check, the flag — and say what it leaves in place.

If a root-cause or likelihood tool is available, use it and say which one. `/planning:check-likelihood` adjudicates a single raised risk and returns a materialization score with the `file:line` it relied on. If no tool is available, say plainly that the verdict is your judgement and not a checked result.

Bring back a verdict, not an impression. Do not paste that verdict at the user: it is evidence for you, and its condition becomes the story below.

If the cause is a decision made earlier — in the plan, in the ADR — say so and make revising that decision one of the options. Never present A against B when the honest answer is C: the split we made earlier was wrong.

## The four parts, in this order

### 1. The story

One concrete run through the system, in time order, that ends in the bad outcome. Name the actors. Use the values the system actually saw, not variable names. Keep the technical nouns — the user is a developer — but drop anything that only makes sense with the plan open. 5 to 10 lines; if the failure needs more events than that, keep the events and cut the words.

You will usually not have watched this happen. Construct the run: pick concrete stand-ins, name them, stay consistent. A constructed run with named actors beats an accurate abstraction. Say in one clause whether you **reproduced** it or **derived** it from the design — the two read identically and only one is evidence. If it has already caused damage, close the story with how much and whether it can be undone.

Bad, a restatement wearing the word "story":

```
The scenario is that a stale message can be applied after a newer one,
because the staleness comparison uses the wrong reference generation,
so ownership can regress silently.
```

Good:

```
Source A and source B both describe product P.
Run 10: A sees P, so P shows A's content.
Run 11: B sees P and takes ownership. P now shows B's content.
A message from run 10 was delayed and arrives now, after run 11 finished.
Our check asks "is this message older than what A last saw?" A last saw P
at run 10, so the answer is no, and we accept the message.
P flips back to A's old content. Nothing logs it. Derived from the plan,
not reproduced.
```

### 2. The forks

Two to four. For each one: what we do, in prose, 2 to 3 lines. What it costs, both now and if we add it later instead. Then how the same story ends under it — **replay** the story, do not summarize it. Say whether it removes the cause or only guards against it. Order them cheapest first; never order them to flatter the one you want.

```
Option 1: compare against the owner, not the sender. One extra lookup on
the write path, half a day. Removes the cause.
Story ends: the delayed run-10 message arrives, we compare against P's
owner (B, run 11), 10 is older than 11, we drop it. P keeps B's content.

Option 2: take a row lock around the write. An hour now, then contention
tuning under load. Guards only; the flaw stays.
Story ends: the delayed message still wins the comparison and still flips
P back to A's content. The lock stops two writers racing. This one is not
racing, it is late.
```

### 3. The recommendation

Which one you would take and why, in one or two lines. Then one question — not three. Make it answerable in one word or one number, and say so: *"reply 1, 2 or 3, or say `more` and I expand any of them."* Offering to re-explain costs the user nothing; a pointer asks them to go read.

If the choice turns on something only the user knows, say that instead of recommending. If every option is bad, say so before the forks and rank by which damage is most survivable; do not invent a third option to reach two.

Then say what you are doing meanwhile: stopped, or continuing on the parts this does not touch, named.

### 4. The pointers, last

Section names, `file:line`, ADR ids, any score or quote you got from a tool: one line at the end, for when the user wants to go deeper. Never at the top, never inside the story.

## In Claude Code

The story and the forks go in the message text, above the question. When you then call `AskUserQuestion`, each option label is the fork's name and its description carries the one-line *what we do + cost + removes or guards* — never the story, which has already been read. An option whose description is a pointer (`"as in ADR §4"`) defeats the whole format.

The story leads, even when your output style says to lead with the action: the user cannot judge an action they cannot place. The question in part 3 **is** the concrete next action, and the pointer line under it does not count as a trailing summary.

Keep the words short and the sentences short throughout. The user reads English well but does not think in it.

## Before you send

Could they follow the problem and pick an option **without opening the plan, the ADR, or the code**? If not, the story is missing or too thin. Rewrite it before sending.

If the response only reports a failure you already fixed, or can fix yourself, this skill does not apply. Report the fix and move on.
