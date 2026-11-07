---
name: panel
description: >
  Run a persona panel on a question before it reaches the user, and turn the
  answers into a question card: what each option looks like to the people it
  affects, a recommendation that says what it costs them, the strongest
  dissent, what would flip it, and whether it can be undone. Each persona
  answers twice, once as an Opus subagent and once as a Sol subagent the
  paired Codex spawns, so a split between the two model families shows as
  uncertainty. Use before any question that needs judgment about users reaches
  the user (a design fork, a size, a default, a trade-off between options a
  shopper or merchant would notice), whenever a peer-planning run, a plan
  interview or a question gate is about to ask one, and when the user says
  "panel", "run the personas", "ask the personas" or "what would users say".
  Not for intent or taste, which the user answers: the panel informs those,
  it never decides them.
---

# Persona panel

A hard question never reaches the user cold. Before it does, the people it affects answer it,
each from what they would actually see, and the user gets a card instead of a list of numbers.

## When it runs, and when it does not

- **It runs** on a question a user would notice the answer to: what shows first, how much a
  penalty weighs, which default a shopper gets, what a merchant sees after a change.
- **It does not run** on a question the code, a test, a probe or an existing ruling can answer.
  Check the project's rulings first (in mybaze, `docs/rulings/`): a ruled question is quoted,
  never re-asked.
- **It does not decide intent or taste.** "Do we want this at all" and "which looks right" stay
  the user's. The panel can still tell the user what each choice looks like to the people it
  affects.

## The people

The project's persona files (in mybaze, `docs/personas/`) define them: a shopper, a merchant, an
ops admin, the engineer on call and the CEO. Use every one that has a stake; a persona with none
says so in a line, which is an answer too. Add a question-specific persona in the brief when the
question turns on someone the files do not cover, such as a shopper in a market whose language or
currency matters to the answer. Write it as a short paragraph in the same shape as the files: who
they are, what they want, what they notice, what they never see.

## Steps

The panel's files live in one directory, `PANEL_DIR`: inside a peer-planning run,
`RUN_DIR/panels/<NNN>-<slug>/`; otherwise `.peer-planning/panels/<YYYY-MM-DD>-<slug>/` at the
root of the checkout. Both are inside Codex's workspace, so Codex can write the Sol answers there.

### 1. Evidence first

Write `PANEL_DIR/brief.md` before anyone answers. It holds:

- **The question in user terms.** Not "how many ticks", but "how much broader must a demoted
  shop's page be before it still shows above an approved one".
- **For each option, what a person would actually see.** Real output wherever it can be had: the
  listing a query returns on the test stack under each option, the page a merchant would see, the
  alert the engineer would get. Where no stack can show it, a worked example written as the page:
  shops, products, prices and positions, never scores. In mybaze, a shared test stack is used by
  one session at a time; ask the session holding it over SendMessage before you use it.
- **The personas taking part**, as file paths, plus any question-specific persona in full.

The brief is neutral: no recommendation, no option marked as the expected one, no internal names
a persona would not know. Both model families read the same brief, so any lean in it reaches both
and the panel stops measuring anything.

### 2. Each persona answers twice, independently

Start both families at once, then end the turn; the answers wake you.

- **Opus.** One subagent per persona, all in one message so they run in parallel:
  `subagent_type: "general-purpose"`, `model: "opus"`, `run_in_background: true`, with the
  "Opus persona" prompt from `references/messages.md`. Save each reply verbatim to
  `PANEL_DIR/answers/<persona>.opus.md`.
- **Sol.** One mailbox message to the paired Codex (the `mailbox-chat` skill), the "Sol panel"
  message from `references/messages.md`. Codex spawns one `persona` subagent per persona (the
  agent defined in `~/.codex/agents/persona.toml`: `gpt-6.1-sol` at high, read-only), saves each
  reply verbatim to `PANEL_DIR/answers/<persona>.sol.md`, and replies with the paths. Codex caps
  the agents open at once (four including itself on Codex 0.167, so three persona slots), so the
  message asks for batches no larger than its free slots. The
  subagents' replies pass through Codex's own context; in a peer-planning run that is the
  reviewer's, so a panel waits for the next clear boundary when it can, and otherwise the review
  that follows is read knowing Codex saw the answers.

If the paired Codex is unavailable, the panel runs on Opus alone and the card says so on its
persona line: "one model family only; agreement between families unmeasured". It never runs Sol
one-shot instead.

### 3. The moderator writes the card

A fresh Opus subagent, with the "Moderator" prompt from `references/messages.md`, reads the brief
and every answer and writes `PANEL_DIR/card.md` in the format below. It did not take part, so it
has no answer of its own to defend. A recommendation is never "the smaller change" on size alone;
it says what the option costs a user.

### 4. The challenger

Send the card to the paired Codex with the "Challenge" message: Codex, the other model family from
the Opus moderator, argues why the recommendation is wrong. Hold the exchange under the "Pair
sessions" rules of `~/.agents/AGENTS.md`: each turn brings a refutation, a cite or a changed
position, and a turn that only repeats the one before it ends the exchange. Update the card for
every point you accept; the strongest point that survives is the card's "strongest dissent".
Without Codex, a fresh Opus subagent challenges instead, and the card says so.

### 5. The framing check

Ask Jev whether the card is framed for the user, with the "Framing check" spec from
`references/messages.md` through the `jev` command (the `jev` plugin). On "not framed", send the
moderator Jev's verdict and the criteria it failed, once, and check again. A card that still fails
goes to the user with the check's result on it, never silently.

### 6. Ask the user

Put the card to the user: in agterm with the `huddle` skill, the options carrying their "what you
would see" text and the recommendation marked; elsewhere as plain text, which also reads on a
phone. Record the answer in `PANEL_DIR/answer.md`. Whether the answer is a durable ruling is the
question gate's call, not the panel's.

## The card

A card carries, in this order:

1. **The question**, in user terms, one sentence.
2. **Each option as what a shopper or merchant would see**, a short paragraph each, from the
   evidence.
3. **The recommendation**, and what it costs a user.
4. **The strongest dissent**: the best case against the recommendation that survived the
   challenge.
5. **Wrong if**: the fact that, if true, would flip the recommendation.
6. **Undo**: whether the choice can be reversed later, and what reversing costs.
7. **The personas**, one line: what they said, with any split between personas or between the two
   model families.

No internal units on the card: no scores, ticks, priors, levels or flags. When a number matters,
say it as a person would meet it ("about one more size on the page").
