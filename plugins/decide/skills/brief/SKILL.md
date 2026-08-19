---
name: brief
description: >
  Rebuild the user's context before asking them to choose. Use when a turn
  ends in a judgement call only the user can make and the context needed to
  answer it lives in work they are not holding right now — a plan, an ADR, a
  session from another day. Produces a five-part brief: one concrete run that
  ends badly, the step back that names why it became possible and how wide it
  reaches, two to four forks each replayed against that run with costs, a
  recommendation, and pointers last. Use before presenting a design fork,
  before reporting that an approach has to change, or when about to write a
  verdict out of section names and file paths. Activates on "give me the
  options", "what are my options here", "which way should we go", "write this
  up before I decide", "I don't have the context", "remind me what this was",
  "why did we end up here", "how did we get here", "is this a design flaw",
  "step back", or "decision brief".
---

# brief

The user wrote the design while fully focused. They are not focused now. Section names, file paths, and internal terms are pointers to a model they no longer hold, so a verdict built out of them is unreadable — it asks them to reload a whole design from a pointer before they can even read the question.

A readable fork is still the wrong question when the fork itself is the artifact of an earlier bad split. So the brief carries two things the user cannot reconstruct from the options alone: **why this became possible**, and **how far the same cause reaches**. Without them, picking is patching, and the user has no way to see that from inside the menu.

## When this fires

Your response ends in a judgement call only the user can make, **and** the context needed to answer it lives in work they are not currently holding: a plan, a design record, an ADR, a session from another day.

It does not fire for:

- a failure you can diagnose and fix yourself — fix it and report cause, then fix;
- a yes/no on a step you just described;
- a question about work done in this session;
- a decision that is small or reversible, or one the user raised themselves this session so the context is already loaded.

When in doubt, one short question beats a five-part brief. A brief on a two-minute fork spends the attention the format exists to protect.

## First, settle the problem. Then write.

Name the guard you first reached for — the lock, the retry, the re-check, the flag — and say what it leaves in place.

If a root-cause or likelihood tool is available, use it and say which one. `/decide:check-likelihood` adjudicates a single raised risk and returns a materialization score with the `file:line` it relied on. If no tool is available, say plainly that the verdict is your judgement and not a checked result.

Bring back a verdict, not an impression. Do not paste the tool's block at the user — its condition becomes the story in part 1, and its cause becomes part 2. Both reach the page; the raw output does not.

Settling the problem is not the same as reporting it settled. The finding that the fork exists because of an earlier decision is worth more to the user than any option you could write, and it is exactly the finding that dies if part 2 stays in your head.

## The five parts, in this order

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

### 2. The step back

Why this became possible, and how far it reaches. 2 to 5 lines, before any option.

Ask why until the answer is a decision someone made, not a line of code. Stop there. One rung short and you hand back the symptom wearing the word "cause" — *"the comparison uses the wrong side"* is where it shows, not why it can show. One rung long and you arrive at "we chose to have a database". Show where the ladder stopped, not the ladder.

Then the question the options cannot answer: **does the same cause produce failures we have not hit yet?** Name them, or say this is the only place it can surface. This is the part the user is picking blind without — two options that both look reasonable read very differently once you know the same choice has four other exits.

Land on one word, because it decides whether patching is honest:

- **Local** — the design was right and this build diverged from it. Say so in one line and go to the forks. Most defects are this, and the part stays short.
- **Design** — an earlier decision is what makes the condition possible. Then revising that decision **is** one of the forks in part 3, written and replayed like the others.
- **Unknown** — you could not trace it past the code. Say that, and name the one thing that would settle it. Do not promote a guess to a design flaw so this part has something to say.

Bad, the defect line relabelled:

```
Root cause: the stale-skip resolves the generation from the inbound message
instead of from the owning sighting. Fix the resolution and it goes away.
```

That names a line, so the ladder stopped one rung early — and it skips how wide it goes entirely. If the plan already specified resolving from the owner, the honest version is short and says so:

```
Local. The plan settled this in section 4.2 and the implementation reads the
wrong side of it. Nothing else resolves generations this way — I checked the
other two write paths.
```

Good, when it is not local:

```
Any sighting may write P's shared row, and ownership is settled at write
time by whichever write lands. That is a choice, not a bug — we chose shared
ownership with last-write-wins instead of one owner per row.
How wide: every field a second source can write has this shape. Ownership is
where we noticed it; content and price have the same exit.
Design. Fork 3 revises it.
```

Do not re-tell the story here, and do not price anything yet — costs live in part 3. If a root-cause tool produced this, that is where you say so in a clause, not by pasting its block.

### 3. The forks

Two to four. For each one: what we do, in prose, 2 to 3 lines. What it costs, both now and if we add it later instead. Then how the same story ends under it — **replay** the story, do not summarize it. Say whether it removes the cause or only guards against it. Order them cheapest first; never order them to flatter the one you want.

**If part 2 landed on Design, one fork revises that decision.** Not a mention in passing — the same treatment as the others: what we do, what it costs, the story replayed. Never present A against B when the honest answer is C, that the earlier split was wrong. Cheapest-first is a cost order, not a ranking; a fork that lands last on cost can still be the one you recommend. If revising it is genuinely off the table — already shipped, needs a migration, the release is Friday — say that in one line where the fork would have been, rather than leaving it out and letting the menu imply it was never available.

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

### 4. The recommendation

Which one you would take and why, in one or two lines. Then one question — not three. Make it answerable in one word or one number, and say so: *"reply 1, 2 or 3, or say `more` and I expand any of them."* Offering to re-explain costs the user nothing; a pointer asks them to go read.

If the choice turns on something only the user knows, say that instead of recommending. If every option is bad, say so before the forks and rank by which damage is most survivable; do not invent a third option to reach two.

If part 2 said **Design** and you are recommending a guard anyway, say why in the same breath — the release is Friday, the fix is a migration, the blast radius is one field. That is often the right call. A guard recommended with no such line reads as a claim the cause was local, which part 2 just said it was not.

Then say what you are doing meanwhile: stopped, or continuing on the parts this does not touch, named.

### 5. The pointers, last

Section names, `file:line`, ADR ids, any score or quote you got from a tool: one line at the end, for when the user wants to go deeper. Never at the top, never inside the story.

## In Claude Code

The story, the step back, and the forks go in the message text, above the question. When you then call `AskUserQuestion`, each option label is the fork's name and its description carries the one-line *what we do + cost + removes or guards* — never the story or the step back, which have already been read. An option whose description is a pointer (`"as in ADR §4"`) defeats the whole format.

The story leads, even when your output style says to lead with the action: the user cannot judge an action they cannot place. The question in part 4 **is** the concrete next action, and the pointer line under it does not count as a trailing summary.

Keep the words short and the sentences short throughout. The user reads English well but does not think in it.

## Before you send

Two questions.

1. Could they follow the problem and pick an option **without opening the plan, the ADR, or the code**? If not, the story is missing or too thin. Rewrite it before sending.
2. Can they tell **whether picking from this menu is patching over something**? If part 2 is missing, hedged into "there are a few contributing factors", or relabels the defect line as the cause, they cannot. And if it says **Design** while every fork is a guard, the brief is asking them to approve the patch without ever showing them the alternative.

If the response only reports a failure you already fixed, or can fix yourself, this skill does not apply. Report the fix and move on.
