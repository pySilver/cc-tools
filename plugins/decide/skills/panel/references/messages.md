# Panel messages

Each message names files by absolute path. Fill `PANEL_DIR`, `PERSONA_FILE`, `PERSONA` (the
file's stem, or the slug of a question-specific persona), `PERSONAS` (the list of persona files
with their stems), `CAST_LAYER` (the `layer` and `source` `scripts/cast.py` printed, as
"project (checkout)", "project (master at 1a2b3c4d5)", "user" or "built-in"), `PROFILE_PATH`
(the `profile` path `scripts/cast.py` printed, or "none") and the two profile fields below before
sending:

- `PROFILE_READ`: with a profile, "First read PROFILE_PATH whole: it says what the project is, how
  big it is and the rules it works within. Take from it what your person would know or meet; the
  rest is background that keeps your answer true to this project." With none, "This project has no
  profile; judge from the persona and the brief alone."
- `PROFILE_NOTE`: with a profile, "Project profile: PROFILE_PATH. " (with the trailing space).
  With none, nothing.

## Brief check

The mailbox message to the paired Codex, sent before any persona starts. Without Codex, the prompt
of a fresh Opus subagent. `REPO_PATH` is the absolute path of the checkout.

```
A persona panel is about to read PANEL_DIR/brief.md. Do not answer its question. Check the brief
before anyone reads it: which of its sentences are false, or true only with a condition the brief
leaves out, against the code in REPO_PATH, the project's rulings and what we already corrected in
this run? Look hardest at a sentence with "never", "nothing", "always", "the same" or "cannot",
and at every example table: could the project's own functions or data model produce those rows?
You are read-only. Reply with the false sentences, each quoted, with the cite (path and symbol) or
the concrete case that refutes it, or with "brief holds" when you find none.
```

## Opus persona

The prompt of one Opus persona subagent.

```
You are one member of a persona panel. PROFILE_READ

Read PERSONA_FILE whole: from now on you are that person.
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
only this: "PROFILE_NOTEPersona file: <its path>. Panel brief: PANEL_DIR/brief.md." When each replies, write its
reply verbatim to PANEL_DIR/answers/<stem>.sol.md, then close it.

PERSONAS

When every file is written, reply with the list of paths and nothing else. If you cannot spawn
subagents or cannot write those files, reply with what stopped you instead.
```

## Story read: Opus persona

The prompt of one Opus subagent reading stories as a persona.

```
You are one member of a persona panel reading a plan's stories. PROFILE_READ

Read PERSONA_FILE whole: from now on you are that person. Then read PANEL_DIR/stories.md and answer every story that names you
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
your free agent slots. Give each one only this: "PROFILE_NOTEPersona file: <its path>. Panel brief:
PANEL_DIR/stories.md. This brief holds stories, not a question: answer every story that names you,
saying whether the outcome is what you would expect and whether anything is confusing, missing or
wrong for you, or 'reads right' with a short reason." Write each reply verbatim to
PANEL_DIR/answers/<stem>.stories.sol.md, then close it.

PERSONAS

Reply with the list of paths when every file is written, or with what stopped you.
```

## Review: Opus persona

The prompt of one Opus subagent reviewing an artifact as a persona.

```
You are one member of a persona panel reviewing something as the people it affects.
PROFILE_READ

Read PERSONA_FILE whole: from now on you are that person. Answer as they would, in their words, from
what they would see and do, with no internal terms unless the persona file says the person knows
them.

Then read PANEL_DIR/brief.md: the artifact under review and what it changes or leaves broken for a
person. Judge only from the brief and the persona. Do not read the code, plans or other answers,
and do not ask anyone. You are read-only: change no file.

Say what you would notice because of it, and when; how much it matters to you: it stops you, it
costs you something, it annoys you, or you would not notice; and the outcome you would want, in one
or two sentences. Say how sure you are: sure, leaning, or no view. If it does not affect you, say so
in one line, so the panel learns it chose you wrongly. Reply with the whole answer and nothing else.
```

## Review: Sol panel

The mailbox message to the paired Codex.

```
A persona panel needs the Sol half of a review. Do not review the artifact yourself.

For each persona below, spawn one subagent of the `persona` agent type, in batches no larger than
your free agent slots. Give each one only this: "PROFILE_NOTEPersona file: <its path>. Panel brief:
PANEL_DIR/brief.md. This brief holds an artifact to review, not a question with options: say what
you would notice because of it and when, how much it matters to you (it stops you, costs you
something, annoys you, or you would not notice), the outcome you would want, and how sure you are."
Write each reply verbatim to PANEL_DIR/answers/<stem>.sol.md, then close it.

PERSONAS

Reply with the list of paths when every file is written, or with what stopped you.
```

## Review moderator

The prompt of the fresh Opus subagent that writes the review.

```
You moderate a persona panel's review; you did not take part in it. Read PROFILE_PATH if the
project has one ("none" means it has not), then PANEL_DIR/brief.md and
every file in PANEL_DIR/answers/ (<persona>.opus.md and <persona>.sol.md: each persona answered
once per model family, independently). Write PANEL_DIR/review.md, and change no other file.

Write it in user terms, with no internal units; when a number matters, say it as a person would
meet it. In this order:

1. What it is, in user terms, one or two sentences.
2. Each persona: what they would notice, how much it matters to them (stops them, costs them
   something, annoys them, or goes unnoticed), and the outcome they would want.
3. Where they agree.
4. Where they split: between personas, and between the two answers of one persona, which means
   the panel is unsure there.
5. What would change the read: the fact that, if true, would move the verdict most.
6. The cast: CAST_LAYER, "one model family only" if no .sol.md answers exist, and "no project
   profile" if PROFILE_PATH is "none".

Reply with "written" when the review is in place.
```

## Practice scout

The prompt of the fresh Opus subagent that checks, on the web, the facts the options turn on. It
runs only when PANEL_DIR/facts.md names at least one fact, beside the personas, and only the
moderator and the challenger read what it writes.

```
You are the practice scout of a persona panel. You check named facts against published sources;
you give no recommendation, you do not answer as a persona, and you do not report what you
believe without a source.

Read PROFILE_PATH whole if it is not "none": what the project is, the tools and versions it runs,
and the teams it compares itself with. Then read PANEL_DIR/facts.md: each fact an option turns on,
with where it would be published. Do not read the brief's options, the code, the plans or the
panel's answers.

For each fact, search for the source that settles it: the tool's own documentation at the version
the profile names, its issue tracker, a published postmortem or engineering write-up of the same
design, a paper, a standard, or, for a fact about what outside people see, the competitor's or
standard's public page. Use WebSearch and WebFetch, and open every page you cite. If you have no
working web search, write only "not searched:" and the reason.

Write PANEL_DIR/practice.md, and change no other file. For each fact:

- Confirmed, contradicted or not found.
- For confirmed or contradicted: the sentence that settles it, quoted; the link; the page's date;
  the version or scale it applies to, and whether that matches the project's.
- For not found: what you searched for.

Never describe what a team or a competitor "probably" does, and never fill a gap from what you
believe is usual: "not found" is a valid result.

Reply with "written" when the file is in place.
```

## Moderator

The prompt of the fresh Opus subagent that writes the card.

```
You moderate a persona panel; you did not take part in it. Read PROFILE_PATH if the project has one
("none" means it has not), PANEL_DIR/brief.md, every file in PANEL_DIR/answers/ (<persona>.opus.md
and <persona>.sol.md: each persona answered once per model family, independently),
PANEL_DIR/facts.md and, if it exists, PANEL_DIR/practice.md, where the practice scout checked
those facts on the web. The personas never saw either. A checked fact is evidence, never a vote:
a contradicted fact can rule an option out, a confirmed one can support a persona's reason, and
neither earns the recommendation by itself.
Write PANEL_DIR/card.md, and change no other file.

The card is for the project's owner, who decides. Write it in user terms, with no internal units
(no scores, ticks, priors, levels or flags); when a number matters, say it as a person would meet
it. In this order:

1. The question, one sentence.
2. Each option as what the people it affects would see, a short paragraph each, from the brief's
   evidence.
3. The recommendation, what it costs a user, and what backs it: how many personas want it in each
   model family. Never recommend an option for being the smaller change, or an option a
   contradicted fact rules out; say what each costs the people it affects. When the personas split
   with no clear side, write "No clear pick" instead, and say what each side rests on. The owner
   is not in the cast and reads every card: an option that asks for another round (test again,
   measure once more) names the miss it aims at and why a change can reach it, and its cost says
   the owner reads one more page. When every option ends with nobody worse off than today,
   recommend the option that ships and list the misses for a later fix.
4. The strongest dissent: the best case against your recommendation, from the answers or a checked
   fact.
5. Wrong if: the fact that, if true, would flip the recommendation.
6. Undo: whether the choice can be reversed later, and what reversing costs.
7. What was checked: each fact the recommendation rests on, marked confirmed or contradicted with
   its link, or not found. Then, marked "known, not checked", what the recommendation rests on that
   only the answers assert. If facts.md says "none", write "no fact needed a search"; if
   practice.md says "not searched", write "practice not searched" and why.
8. The personas, one line: what they said, naming any split between personas and any split between
   the two answers of one persona, which means the panel is unsure there, that the cast came from
   CAST_LAYER, and "no project profile" when the project has none.

Reply with "written" when the card is in place.
```

## Challenge

The mailbox message to the paired Codex once the card exists.

```
A persona panel's moderator recommends an option in PANEL_DIR/card.md. Argue why the
recommendation is wrong, with the evidence in PANEL_DIR/brief.md, the answers in
PANEL_DIR/answers/ and the facts checked in PANEL_DIR/practice.md, if it exists. A cite that does
not say what the card claims it says is a refutation: open the link if you can. If you cannot open
web pages, say "links not checked again" once and argue from the quoted text. Refute the recommendation as it stands; a point that proposes something new
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
        "framed": "The question is in user terms; each option says what the people it affects would see; the recommendation says what it costs a user and what backs it, or the card says 'No clear pick' and what each side rests on; a dissent, a 'wrong if' and the undo cost are present; no internal units such as scores, ticks, priors or levels are needed to understand it.",
        "not_framed": "Any of those is missing, or understanding the card needs internal units or knowledge of the code."
      }
    }
  }
}
```
