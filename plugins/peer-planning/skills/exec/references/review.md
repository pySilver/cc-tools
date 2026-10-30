# Branch review: revmux rounds

The orchestrator follows this playbook itself after the last task. It is not a prompt for a
subagent. A project replaces it with its own `.claude/peer-planning/review.md`, which takes the
same placeholders: `WORK_PATH`, `DEFAULT_BRANCH`, `PLAN_FILE_PATH`, `PROGRESS_FILE_PATH` and
`REVIEW_PHASE`.

Each iteration runs one revmux round through the `revmux:revmux` skill. revmux runs its own panel,
then synthesizes and verifies before it returns findings, so this phase spawns no review subagents.
The one Agent call in a round belongs to the revmux skill, which writes the round's context files
through a subagent of its own. That agent reviews nothing.

If a round cannot run, stop the review phase and tell the user. Never fall back to reviewing with
subagents of your own: that review would look complete while running none of the project's review
setup. A review that is missing and says so can be recovered; a silent substitute cannot.

## Which profile an iteration runs

| `REVIEW_PHASE` | revmux profile | asks |
|---|---|---|
| `comprehensive` | `comprehensive` | what is wrong anywhere in this diff |
| `critical` | `final` | did the fixes close what was found, and did any fix the quoted site while leaving the same defect elsewhere |

revmux resolves a profile from the project's `.revmux/prompts/profiles/` before its shipped one, so
a project tunes these two by overriding them there. The `final` profile states its own severity
floor, so a minor finding cannot reach the critical pass.

## Step 1: preflight

The revmux skill checks `revmux` and every CLI the roster needs before it launches anything. Pass
it the profile this iteration runs. Without one it checks the default roster, and a missing CLI
surfaces mid-round. On a preflight failure, stop the phase and tell the user.

## Step 2: hand the round to the skill

Ask the skill for a round on that profile over `git diff DEFAULT_BRANCH...HEAD`, launched from the
main checkout with `--workdir WORK_PATH` so the round's archive stays with the main checkout. Give
it the task id: the branch name with every `/` replaced by `-`. The skill opens the round, numbers
it after the last one that ran, and writes `scope` and `goal`. Never open or launch a round by
hand.

Tell the skill three things it cannot infer:
- Write no `profile.md` into the round. `.revmux/profile.md` is the project's layer and reaches
  every round on its own; a round-local file would shadow it.
- Copy `PLAN_FILE_PATH` into the round's `context/`. From the second round on, copy
  `PROGRESS_FILE_PATH` too, and every earlier fixer report it names: `progress.md` carries what
  each iteration found, and the reports what each fixer changed or rejected as a false positive.
- In `critical` mode, say in `goal` that the round exists to answer whether the fixes held, and
  that finding nothing is a valid answer. Without that sentence the panel reads the round as owing
  findings and produces some.

Do not paste earlier findings into `scope`. revmux injects every earlier round of the task into
each prompt itself, and a pasted copy anchors the panel on conclusions it should re-derive.

## Step 3: run it

The skill runs the round and returns its JSON. A round takes 10 to 20 minutes. Findings are a
result, not a failure: never re-run a round because it found something, and never review again by
other means because it found nothing.

## Step 4: a degraded round

Read `sources`. If `degraded` is non-empty, the panel was short a source, so its silence is not
evidence. Ask the skill for one fresh round with the same context. If that round is degraded too:
1. Say `Review degraded: <n> of <m> sources reported. Missing: <names>.`
2. In `critical` mode, never report the iteration clean, even with zero findings.
3. Tell the user the phase finished without full coverage, and name the missing source.

## Step 5: the findings list for the fixer

`findings` is what survived synthesis and verification. It is already deduplicated and
adjudicated: do not re-verify, re-rank or drop anything here. Build `FINDINGS_LIST` from it:

- One heading per severity, in the order `### CRITICAL`, `### MAJOR`, `### MINOR`, skipping empty
  ones. In `critical` mode only CRITICAL and MAJOR appear.
- One bullet per finding: `- <sources>: <file:line> — <description>`, where `<sources>` joins the
  finding's `sources` array with `+` (`bugs+impl+codex`). Never substitute the `lenses` array:
  sources are the evidence of corroboration, lenses are not.
- A last line: `Total: <N> findings (<C> critical, <M> major, <m> minor)`.

The list ends at the `Total:` line, and the fixer treats everything in it as work.

In `critical` mode, an empty `findings` array in a round that was not degraded ends the phase:
say `Critical re-check: clean.` and log it to `progress.md`.

## Step 6: what the fixer never gets

`open_questions`, `pre_existing` and `immaterial` are real but are not work. A verifier judged
`immaterial` items accurate and not worth the change, `pre_existing` items are not this branch's,
and `open_questions` want the user's decision, not an edit. An unattended fixer handed them
overturns the verifier, edits code outside the branch, and answers questions for the user.

Report them to the user after the findings list, one line each (`Open questions: <n>`,
`Pre-existing: <n>`, `Immaterial: <n>`) with a bullet per item, and append the same to
`progress.md`. Never write a severity word in these bullets: the loop below reads severity words
as open findings.

## Step 7: what may drive another iteration

Before the fixer runs, write this round's gating count (CRITICAL plus MAJOR) and, for each gating
finding, its file, the function or symbol it sits in, and its mechanism into `progress.md`. The two
rules below compare against them.

**Only executable code drives another iteration.** A gating finding in a document an agent
executes as a contract (rule files, `AGENTS.md`, `CLAUDE.md`, skill and prompt files, `.revmux/*`,
the plan) is real and worth fixing, but fixing it writes new prose that the next round reviews, and
a rewritten rubric tends to produce a new finding of its own. List such findings for the user as
`Batched prose findings: <n>`, keep them out of `FINDINGS_LIST`, and leave them for one batch fix
after the loop. A script is code: fixing a `.sh` or `.py` replaces logic and counts normally. Only
the text a script prints batches with the prose.

**When the fixes are not landing, step back with Codex.** The rule fires when this round's gating
count in executable code is not strictly lower than the previous round's, and one of its gating
findings sits in the same function or symbol as a gating finding of the previous round. The place
decides, not the mechanism: a design gap patched one finding at a time shows up as a new mechanism
in the same function every round. Another fix would answer one more case, so when the rule fires:

1. Open a design discussion with Codex. It is the one exception to Codex taking no part in this
   phase. Send "Opening a design discussion in the branch review" from
   `references/codex-messages.md`, log `discuss.request` with `stage=review` and this iteration,
   and end your turn. The exchange follows the exec skill's task discussion, section B steps 3 to
   5: verify every claim Codex makes, answer each point, propose agreement once the thread
   converges, and take a stall to the user.
2. Once the design is agreed, write it into `progress.md` and run the fixer on this round's
   `FINDINGS_LIST`, with `DESIGN_BLOCK` carrying the agreed design. When Codex shows that the
   design holds and you accept its cite, run the fixer on the findings as they are. Either way the
   next iteration follows as usual.
3. A symbol gets one discussion. If the rule fires again on a symbol already discussed, name its
   finding to the user and end the phase without another iteration.
