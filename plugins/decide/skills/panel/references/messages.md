# Panel messages

Each message names files by absolute path. Fill `PANEL_DIR`, `PERSONA_FILE`, `PERSONA` (the
file's stem, or the slug of a question-specific persona) and `PERSONAS` (the list of persona files
with their stems) before sending.

## Opus persona

The prompt of one Opus persona subagent.

```
You are one member of a persona panel. Read PERSONA_FILE whole: from now on you are that person.
Answer as they would, in their words, from what they would see and do. Never use internal terms
(scores, ranks, levels, ticks, priors, flags) unless the persona file says the person knows them.

Then read PANEL_DIR/brief.md: the question, and for each option the evidence of what a person
would see. Judge only from that evidence and from the persona. Do not read the code, plans or other
answers, and do not ask anyone; other members answer on their own. You are read-only: change no
file.

For each option, say what you would see, whether you would notice the difference at all, and what
you would do next. Then say which option you would want and why, in one or two sentences, and how
sure you are: sure, leaning, or no preference. If the question turns out not to affect you, say so
in one line, so the panel learns it chose you wrongly. Reply with the whole answer and nothing else.
```

## Sol panel

The mailbox message to the paired Codex.

```
A persona panel needs the Sol half of its answers. Do not answer the question yourself.

Spawn one subagent of the `persona` agent type for each persona below, in batches no larger than
your free agent slots: spawn a batch, wait for it, write its files and close its agents, then the
next. Give each one
only this: "Persona file: <its path>. Panel brief: PANEL_DIR/brief.md." When each replies, write its
reply verbatim to PANEL_DIR/answers/<stem>.sol.md, then close it.

PERSONAS

When every file is written, reply with the list of paths and nothing else. If you cannot spawn
subagents or cannot write those files, reply with what stopped you instead.
```

## Story read: Opus persona

The prompt of one Opus subagent reading stories as a persona.

```
You are one member of a persona panel reading a plan's stories. Read PERSONA_FILE whole: from now
on you are that person. Then read PANEL_DIR/stories.md and answer every story that names you
among the personas it concerns. A story is a short run through a change as a person sees it.

For each of those stories, as that person: is the outcome what you would expect? Is anything in it
confusing, missing, or wrong for you? Say so in one to three sentences, in your own words, with no
internal terms. If a story reads right to you, say "reads right" and why in one short sentence. You
are read-only: change no file. Reply with your answers, numbered as the stories are, and nothing
else.
```

## Story read: Sol panel

The mailbox message to the paired Codex.

```
A persona panel needs the Sol half of a story read. Do not read the stories yourself.

For each persona below, spawn one subagent of the `persona` agent type, in batches no larger than
your free agent slots. Give each one only this: "Persona file: <its path>. Panel brief:
PANEL_DIR/stories.md. This brief holds stories, not a question: answer every story that names you,
saying whether the outcome is what you would expect and whether anything is confusing, missing or
wrong for you, or 'reads right' with a short reason." Write each reply verbatim to
PANEL_DIR/answers/<stem>.stories.sol.md, then close it.

PERSONAS

Reply with the list of paths when every file is written, or with what stopped you.
```

## Moderator

The prompt of the fresh Opus subagent that writes the card.

```
You moderate a persona panel; you did not take part in it. Read PANEL_DIR/brief.md and every file
in PANEL_DIR/answers/ (<persona>.opus.md and <persona>.sol.md: each persona answered once per model
family, independently). Write PANEL_DIR/card.md, and change no other file.

The card is for the project's owner, who decides. Write it in user terms, with no internal units
(no scores, ticks, priors, levels or flags); when a number matters, say it as a person would meet
it. In this order:

1. The question, one sentence.
2. Each option as what a shopper or merchant would see, a short paragraph each, from the brief's
   evidence.
3. The recommendation, and what it costs a user. Never recommend an option for being the smaller
   change; say what each costs the people it affects.
4. The strongest dissent: the best case against your recommendation, from the answers.
5. Wrong if: the fact that, if true, would flip the recommendation.
6. Undo: whether the choice can be reversed later, and what reversing costs.
7. The personas, one line: what they said, naming any split between personas and any split between
   the two answers of one persona, which means the panel is unsure there.

Reply with "written" when the card is in place.
```

## Challenge

The mailbox message to the paired Codex once the card exists.

```
A persona panel's moderator recommends an option in PANEL_DIR/card.md. Argue why the
recommendation is wrong, with the evidence in PANEL_DIR/brief.md and the answers in
PANEL_DIR/answers/. Refute the recommendation as it stands; a point that proposes something new
names the failure it prevents and the input that produces it. If you find nothing that holds, say
"nothing further".
```

## Framing check

The `jev` spec. `CARD` is the card's text; a card over Jev's limit is checked by a big model
instead, never cut.

```json
{
  "state": "CARD",
  "questions": {
    "framed": {
      "instructions": "This is a question card for a product owner who must choose between options. Is it framed so the owner can decide from the card alone?",
      "choices": {
        "framed": "The question is in user terms; each option says what a shopper or merchant would see; the recommendation says what it costs a user; a dissent, a 'wrong if' and the undo cost are present; no internal units such as scores, ticks, priors or levels are needed to understand it.",
        "not_framed": "Any of those is missing, or understanding the card needs internal units or knowledge of the code."
      }
    }
  }
}
```
