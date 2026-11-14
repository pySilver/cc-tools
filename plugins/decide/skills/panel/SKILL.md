---
name: panel
description: >
  Run a persona panel on a question before it reaches the user, and turn the
  answers into a question card: what each option looks like to the people it
  affects, a recommendation that says what it costs them and what backs it,
  the strongest dissent, what would flip it, whether it can be undone, and
  which of the facts it rests on a search confirmed. Each persona reads the project's profile
  and answers twice, once as an Opus subagent and once as a Sol subagent the
  paired Codex spawns, so a split between the two model families shows as
  uncertainty; when an option turns on a fact a source outside the project
  can settle (a tool's documented behavior, a published postmortem, a
  competitor's public page), a practice scout checks it on the web, for the
  moderator only. Use before any question
  whose options each cost something reaches the user, about users or
  technical (a design fork, a size, a default, a scope, a trade-off between
  consistency and cost), whenever a peer-planning run, a plan interview or a
  question gate is about to ask one, and when the user says "panel", "run the
  personas", "ask the personas", "what would users say" or "what do other
  teams do".
  It also reviews any artifact as those people (a backlog item, a plan
  section, a doc, a PR body, product copy) and synthesizes what each would
  notice, how much it matters to them and where they split: use it when the
  user says "personas review", "review this with the personas", "triage this
  with the personas" or "how would users take this". Not for intent or taste,
  which the user answers: the panel informs those, it never decides them.
---

# Persona panel

A hard question never reaches the user cold. Before it does, the people it affects answer it,
each from what they would actually see, and the user gets a card instead of a list of numbers.

## When it runs, and when it does not

- **It runs** on a question whose options each cost something, so that no option is plainly
  right: what shows first, how much a penalty weighs, which default a shopper gets, what a merchant
  sees after a change, and technical forks too, such as how much of a fix to build now, whether to
  measure at full scale first, or how fresh a copy of the data must be. A technical question brings
  the people who run and build the system, never a shopper.
- **It does not run** on a question the code, a test, a probe or an existing ruling can answer.
  Check the project's rulings first (in mybaze, `docs/rulings/`): a ruled question is quoted,
  never re-asked.
- **It does not decide intent or taste.** "Do we want this at all" and "which looks right" stay
  the user's. The panel can still tell the user what each choice looks like to the people it
  affects.

## The project profile

`.personas/profile.md` at the root of the checkout says what the project is: the product, who uses
it and where, its scale, the rules every answer works within, the tools and versions it runs,
what a newcomer gets wrong, and the teams to compare with. Every persona reads it before its own file, and so do the practice scout and
the moderator. Without it a persona judges a fifty-million-item catalog as if it held a thousand,
and a shopper persona in a fashion catalog took a drawing for a normal product photo, which the
owner answered with "There is no such thing in FASHION as ILLUSTRATION" (mybaze gate log,
2026-11).

Each project writes its own from `references/profile-template.md`; no user or built-in profile
stands in for it. `scripts/cast.py` prints its path as `profile`, from the checkout or, like the
cast, from the default branch when the checkout has none or holds only an unchanged older copy. When `profile` is null, the panel still
runs and every card and review says "no project profile"; offer once to draft one from the
project's own documents, for the user to finish and commit.

## The people

The cast is a folder of persona files, one person each, with a `README.md` index. It comes from
the first of three layers that has any persona file, the same order revmux reads its prompts in:

1. `.personas/cast/` at the root of the checkout, the project's own people (in mybaze a shopper, a
   merchant, an ops admin, the engineer on call and the CEO);
2. `~/.config/personas/cast/`, the user's;
3. the built-in cast in this skill's `cast/`: a person who uses the product, the engineer who runs
   it, the engineer who builds the next change on it and the owner who pays for it, generic enough
   for any repository.

The whole cast comes from one layer; files are never merged across layers, because a generic
person beside a project's own shopper would be picked as if they were one of its users. Resolve it
before every panel with `python3 ${CLAUDE_SKILL_DIR}/scripts/cast.py`, which prints the layer,
its source, the index and each persona's path as JSON. A worktree branched before the project's
cast landed has none of its own; the script then reads the default branch's cast, from whichever
of the local and remote branch is newer, so the panel keeps the project's people without a rebase,
and `source` names the branch and commit. The same holds for a worktree whose cast is an older copy
it never edited: a persona added on the default branch reaches it without a merge, while a branch
that edits its cast keeps its own. `cast.py init` copies the cast that resolves into
`.personas/cast/` when the user asks to set up personas for a project.

A panel brings only the people the question affects, never the whole cast by default. Pick them
before writing the brief: a persona is in when some option changes what that person sees, does or
answers for, and the brief says in one line why each one is there. A question about the storefront order brings the shopper and the merchant; one
about an alert brings the engineer on call; a technical fork brings the engineer who runs the
system and the one who builds the next change on it; the CEO comes in when the options differ in cost to
the company or in how they would be defended to shoppers and merchants. Two is the floor: with one
persona there is no second view to disagree. Add a question-specific persona in the brief when the
question turns on someone the files do not cover, such as a shopper in a market whose language or
currency matters to the answer. Write it as a short paragraph in the same shape as the files: who
they are, what they want, what they notice, what they never see.

## Steps

The panel's files live in one directory, `PANEL_DIR`: inside a peer-planning run,
`RUN_DIR/panels/<NNN>-<slug>/`, removed with the run's records; otherwise the folder
`python3 ${CLAUDE_SKILL_DIR}/scripts/cast.py run-dir <slug>` makes and prints,
`.personas/runs/<YYYY-MM-DD>-<slug>/` at the root of the checkout, which git ignores without any
rule in the project. Both are inside Codex's workspace, so Codex can write the Sol answers there.

### 1. Evidence first

Write `PANEL_DIR/brief.md` before anyone answers. It holds:

- **The question in user terms.** Not "how many ticks", but "how much broader must a demoted
  shop's page be before it still shows above an approved one".
- **For each option, what a person would actually see.** Real output wherever it can be had: the
  listing a query returns on the test stack under each option, the page a merchant would see, the
  alert the engineer would get. Where no stack can show it, a worked example written as the page:
  shops, products, prices and positions, never scores. In mybaze, a shared test stack is used by
  one session at a time; ask the session holding it over SendMessage before you use it.
- **The personas taking part**, as file paths, each with one line on why the question affects
  them, plus any question-specific persona in full.

Then write `PANEL_DIR/facts.md`, which no persona reads: each fact an option turns on that a source
outside the project can confirm or refute, with where it would be published. Such a fact is a
tool's documented behavior or limit at the version the profile names (a replication slot's
retention, a stream's delivery guarantee, a search engine's partial-update rule), a published
postmortem of the same design, a change after the model's training, or, for a question about what
outside people see, a competitor's or a standard's public page. Write "none" when the question
turns on taste, size, scope, approval or a product fact only the project holds: no search settles
those, and most held questions are of that kind.

The brief is neutral: no recommendation, no option marked as the expected one, no internal names
a persona would not know. Both model families read the same brief, so any lean in it reaches both
and the panel stops measuring anything.

Writing for a persona turns a qualified fact into a plain one, so two kinds of sentence are
checked as they are written. A sentence with "never", "nothing", "always", "the same" or "cannot"
gets its counterexample looked for first. An example table comes from the project's own functions
or its data model: a formula copied into a one-off script once gave a page more distinct sizes
than offers, which one size per offer row rules out.

**The brief is checked before any persona reads it.** Send the paired Codex the "Brief check"
message from `references/messages.md` and wait for its reply: which sentences of `brief.md` are
false against the code, the project's rulings and the corrections already accepted in this run.
Fix the brief for every point that holds. The challenge in step 4 reads the card, not the brief,
so it comes after the answers. In a read of 29 mybaze panels (2026-11-12 and 13), 20 briefs held a
false sentence that the personas read, none of those briefs was checked before they answered, and
11 of the errors reached the owner's page. Without Codex, a fresh Opus subagent checks the brief
with the same message, and the card says so.

A brief fixed after the personas answered means they answer again. When the fix touches a sentence
an answer gives as its reason, run step 2 again on the fixed brief, or the card names the answers
that rest on the false sentence.

### 2. Each persona answers twice, independently, and the scout searches

After the brief check, start both families and the scout at once, then end the turn; the answers
wake you.

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

- **The practice scout**, only when `facts.md` names at least one fact. One more Opus subagent
  in the same message, `subagent_type: "general-purpose"`, `model: "opus"`,
  `run_in_background: true`, with the "Practice scout" prompt. It checks each named fact on the
  web and writes `PANEL_DIR/practice.md`: each fact confirmed, contradicted or not found, with the
  quoted sentence, its link, date and the version it applies to. It never reports what a team
  "probably" does and never states a belief of its own as a finding: the personas who run and build
  the system already bring what a capable model knows, in two model families. Without a working web
  search, it writes "not searched" and why. It runs on question panels only, not on story reads or
  reviews.

  A competitor rarely publishes how it builds things, so a search for "what teams like ours do"
  returns little, and what it does return comes from much larger companies whose answer fits their
  size. On a mybaze outbox question (2026-11-13) a review found one competitor engineering blog, its
  newest post from 2021. So the scout checks named facts, not practice in general.

The personas never read `facts.md` or `practice.md`, and the brief never quotes them: a persona
that has read another team's choice can only repeat it, and its vote stops being a second view.
Only the moderator and the challenger read them.

If the paired Codex is unavailable, the panel runs on Opus alone and the card says so on its
persona line: "one model family only; agreement between families unmeasured". It never runs Sol
one-shot instead.

### 3. The moderator writes the card

A fresh Opus subagent, with the "Moderator" prompt from `references/messages.md`, reads the
profile, the brief, every answer, `facts.md` and the scout's `practice.md`, and writes `PANEL_DIR/card.md` in
the format below. It did not take part, so it
has no answer of its own to defend. A recommendation is never "the smaller change" on size alone;
it says what the option costs a user.

### 4. The challenger

Send the card to the paired Codex with the "Challenge" message: Codex, the other model family from
the Opus moderator, argues why the recommendation is wrong. Where it can open web pages, it also
checks that each link in `practice.md` says what the card claims; where it cannot (Codex's sandbox
may have no network), it says so, and the card's "What was checked" line adds "links not checked
again". Hold the exchange under the "Pair
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
would see" text, the recommendation marked with the reason that names what backs it, and the
checked facts in the page's context with their links; elsewhere as plain text, which also reads on a
phone. A card with "No clear pick" marks no option recommended: the badge appears only when the
card says what backs it. No option is preselected.

The page opens with the panel's answers, above the case: a table with one row per persona (who
they are, why the question affects them, what each model family picked) and one line on where they
agree and where they split. The full card goes below. A card placed as the second block under a
five-step case was not seen: the owner typed "Consult this with personas first" on a page that
held it (mybaze, 2026-11-12).

Record the answer in `PANEL_DIR/answer.md`. Whether the answer is a durable ruling is the
question gate's call, not the panel's.

## Reading stories

The panel's second job is reading a plan's stories, where it writes no card. Each story is a short
run through a change as one person sees it, and the people it names judge whether it reads right
to them before the user approves it.

1. Write `PANEL_DIR/stories.md`: each story, numbered as in the plan, without its `Test:` block,
   and for each the personas it concerns: the actor it names, plus anyone else an option of it
   changes something for. Two personas per story is the floor, as for a question.
2. Run each persona once as Opus and once as Sol, as in step 2 above, with the "Story read"
   prompts from `references/messages.md`, saving the answers as
   `PANEL_DIR/answers/<persona>.stories.opus.md` and `.stories.sol.md`. Each one answers every story
   it concerns: is the outcome
   what they would expect, and is anything confusing, missing or wrong for them?
3. A story is **flagged** when any answer says it is unexpected, confusing or wrong. Write
   `PANEL_DIR/story-read.md`: the flagged stories first, each with the answers that flagged it,
   quoted, then one line naming the stories nobody flagged, then the layer and source the cast came
   from.

The caller puts the flagged stories in front of the user first, with those answers beside them.
The panel never rewrites a story; the user and the agent who drafted it do.

## Reviewing

The panel's third job is reading any artifact as the people it affects: a backlog item, a plan
section, a document, a PR body, the copy a page shows. It asks no question and writes no card; the
review informs whoever acts next, and a decision that follows from it still goes through a card.

1. Write `PANEL_DIR/brief.md`, the only thing a persona reads: the artifact restated in user terms,
   what it changes or leaves broken for a person, and the outcomes on the table, then the personas
   taking part, as paths, each with one line on why the artifact touches them; two is the floor,
   as for a question. The brief stays neutral: no expected verdict and no internal names a persona
   would not know. So an artifact that carries a recommendation, code paths or internal terms (a
   backlog item's `where:` and "Recommendation:", a plan task) is restated, never pasted or cited
   by path. Text a person would meet as written, such as page copy or a notice, is quoted whole.
   When the artifact is internal, the brief says what a person would meet because of it: what they
   would see, when, and how often.
2. Run each persona once as Opus and once as Sol, as in step 2 of a question, with the "Review"
   prompts from `references/messages.md`, saving `PANEL_DIR/answers/<persona>.opus.md` and
   `.sol.md`.
3. A fresh Opus subagent with the "Review moderator" prompt reads the brief and every answer and
   writes `PANEL_DIR/review.md`:
   - **What it is**, in user terms, one or two sentences.
   - **Each persona**: what they would notice, how much it matters to them (stops them, costs them
     something, annoys them, or goes unnoticed), and the outcome they would want.
   - **Where they agree**, and **where they split**, between personas or between the two answers
     of one persona, which means the panel is unsure there.
   - **What would change the read**: the fact that, if true, would move the verdict most.
   - **The cast**: the layer and source it came from, "one model family only" when Codex was
     unavailable, and "no project profile" when there is none.

The caller reports the review with the artifact it was about. Reviewing a backlog item, the
`tracking:backlog` skill may offer to fold what the review changed into the item; the panel never
edits the artifact itself.

## The card

A card carries, in this order:

1. **The question**, in user terms, one sentence.
2. **Each option as what the people it affects would see**, a short paragraph each, from the
   evidence.
3. **The recommendation**, what it costs a user, and what backs it: how many personas want it in
   each model family. A checked fact never earns the badge by itself: a contradicted fact can rule
   an option out, and a confirmed one only supports a persona's reason. When the personas split
   with no clear side, **No clear pick**, and what each side rests on.
4. **The strongest dissent**: the best case against the recommendation that survived the
   challenge.
5. **Wrong if**: the fact that, if true, would flip the recommendation.
6. **Undo**: whether the choice can be reversed later, and what reversing costs.
7. **What was checked**: each fact the recommendation rests on, marked confirmed or contradicted
   with its link, or not found; then, marked "known, not checked", what the recommendation rests on
   that only the answers assert. Or "no fact needed a search", or "practice not searched" and why.
8. **The personas**, one line: what they said, with any split between personas or between the two
   model families, the layer and source the cast came from, and "no project profile" when there is
   none.

No internal units on the card: no scores, ticks, priors, levels or flags. When a number matters,
say it as a person would meet it ("about one more size on the page").

The user is not in the cast, and still pays for every page. An option that asks for another round
(test again, measure once more) names the miss it aims at and why a change can reach that miss,
and its cost says that the user reads one more page; "it varies from run to run" is not a cause.
When every option ends with nobody worse off than today, there is no question: the card
recommends the option that ships and lists the misses for a later fix. One mybaze question went to
the owner four times in about two hours (2026-11-11); the fourth card recommended a fifth test for
a miss the session itself had called ordinary variation.
