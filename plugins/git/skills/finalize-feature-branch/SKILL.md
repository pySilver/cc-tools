---
name: finalize-feature-branch
description: After review approval, rebase onto the default branch, collapse the feature branch into a single commit, verify it, then merge it into the default branch and push that. Skips the full test suite when the rebase brought in nothing but documentation and a full run already passed on the branch's code, in this session or in a peer-planning run record. Holds a landing lock in the repository's git directory while it runs, so two worktrees on one machine never finalize at once.
disable-model-invocation: true
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion, Skill
---

# Finalize Feature Branch as One Commit

Policy: the finalized branch must end with exactly one commit ahead of origin/{DEFAULT_BRANCH}.

## Asking the user

Every question below is asked the way the user's own rules say. Inside agterm those
rules may send a choice to a huddle page: follow them. Where no rule says, use
AskUserQuestion. The options, their order and the default below hold in either form.

## 1. Determine Default Branch

If $ARGUMENTS is provided, use it as DEFAULT_BRANCH.

Otherwise:
- Detect the likely default branch with: `git remote show origin | grep "HEAD branch"`
- Ask the user which branch to use
- Offer the detected branch first
- Include common alternatives: main, master, develop

## 2. Determine Current Branch

Run:
- `git branch --show-current`

Store the result as CURRENT_BRANCH.

If CURRENT_BRANCH is empty or detached, stop and report the issue.

## 3. Preview and Confirm

Before making changes, gather and show:
- Current branch name
- DEFAULT_BRANCH target
- Number of commits ahead: `git rev-list --count origin/{DEFAULT_BRANCH}..HEAD`
- Commit list: `git log origin/{DEFAULT_BRANCH}..HEAD --oneline`
- Whether origin/{DEFAULT_BRANCH} appears up to date using: `git fetch origin --dry-run`

Record, before any fetch, the commit the branch is currently based on:
- `git merge-base HEAD origin/{DEFAULT_BRANCH}`

Store it as BASE_BEFORE. Step 9 needs it to tell what the rebase actually pulled in.
Take it now — after the fetch, the old value is unrecoverable.

Record the branch's head and whether the working tree is clean, before the rebase
and the collapse rewrite them:
- `git rev-parse HEAD`, stored as HEAD_BEFORE
- `git status --porcelain`, stored as CLEAN_BEFORE when it prints nothing

Step 9 compares a peer-planning run record against them.

Ask the user to confirm:
- "Proceed"
- "Abort"

If the user chooses "Abort", stop.

### Take the landing lock

After "Proceed", before the fetch in step 4, take the repository's landing lock.
It lives in the git common directory, which every worktree of the repository
shares, and `mkdir` either creates it or fails.

Read the three values first, each with its own command:
- `git rev-parse --path-format=absolute --git-common-dir`; LOCK is that path
  followed by `/finalize-feature-branch.lock`
- `git rev-parse --show-toplevel`, stored as TOPLEVEL
- `date -u +%Y-%m-%dT%H:%M:%SZ`, stored as STARTED

Then write every value into the commands as literal text, never as a shell
variable or a `$(...)`:
- `mkdir LOCK`
- On success, write the owner file with Bash, one line each:
  `printf 'branch=CURRENT_BRANCH\nworktree=TOPLEVEL\nstarted=STARTED\n' > LOCK/owner`

Use Bash for the owner file, not the Write tool. In a session Claude Code
isolated in a worktree, LOCK is inside the main checkout's `.git`, and Claude
Code refuses a Write or Edit there. Its guard also refuses a Bash command that
names git and holds a variable or a `$(...)`. In the worktree sessions up to
2026-11-13, it refused the Write tool on the owner file 30 times in 15 sessions
and every variable form it saw (4 of 4), and it ran every literal `mkdir`, owner
`printf` and release (58 calls).

If `mkdir` fails, another finalize holds the lock. Read LOCK/owner:
- When the owner's branch is already an ancestor of `origin/{DEFAULT_BRANCH}`, or
  its worktree path no longer exists, the lock is stale. Offer to
  break it: remove it, then take it as above. If the user
  declines, stop.
- Otherwise, or when `owner` is missing or unreadable, ask:
  - "Stop; rerun finalize after <branch> lands" (default)
  - "Break the lock"
- Never wait for the lock by sleeping or polling.

The lock keeps two worktrees on this machine from finalizing at once, so a lane
never rebases onto a default branch another lane is about to move and then fails
its push or reruns its suite. It does not cover pushes from other machines; the
plain non-force push still refuses those.

From here on, every stop releases the lock first: an aborted rebase, the
0-ahead stop, a wrong commit count, a failing suite, a diverged or moved default
branch, a rejected or failed push. Step 12 releases it after any landing, and
"Do nothing" in step 11 releases it too, with LOCK as literal text:
- `rm -f LOCK/owner && rmdir LOCK`

## 4. Fetch Latest Changes

Run:
- `git fetch origin`

## 5. Rebase onto DEFAULT_BRANCH

Run:
- `git rebase origin/{DEFAULT_BRANCH}`

If conflicts occur:
- Attempt to resolve them
- If resolution is clear, stage resolved files and run: `git rebase --continue`
- If resolution is unclear or the rebase fails, run: `git rebase --abort`
- Report the issue and stop

Remember whether any conflict had to be resolved. A resolved conflict means you
wrote code that nothing has ever run, so step 9 must not skip the test suite.

## 6. Inspect Ahead Commits

Run:
- `git rev-list --count origin/{DEFAULT_BRANCH}..HEAD`
- `git log origin/{DEFAULT_BRANCH}..HEAD --oneline`

Then:
- If there are 0 commits ahead, report that there is nothing to finalize and stop
- If there is 1 commit ahead, ask the user whether to keep or reword the commit message, then continue to step 8
- If there are 2 or more commits ahead, continue to step 7

## 7. Collapse to One Commit

If there are 2 or more commits ahead of `origin/{DEFAULT_BRANCH}`:

- Show the commits that will be combined
- Propose a final commit message derived from CURRENT_BRANCH
- Ask the user to confirm or edit the message
- Collapse all ahead commits into one commit

Generate the proposed message as follows:
- Start with CURRENT_BRANCH
- Remove common prefixes: `feature/`, `feat/`, `bugfix/`, `fix/`, `chore/`, `task/`
- Replace `-` and `_` with spaces
- Convert to a short imperative-style summary when possible

Examples:
- `feature/image-payload-support` -> `Add image payload support`
- `fix/login-redirect` -> `Fix login redirect`
- `feat/csv-export` -> `Add CSV export`

Run:
- `git reset --soft origin/{DEFAULT_BRANCH}`
- `git commit -m "<final feature commit message>"`

Do not use `git rebase -i`.

## 8. Verify Final State

Run:
- `git rev-list --count origin/{DEFAULT_BRANCH}..HEAD`
- `git log origin/{DEFAULT_BRANCH}..HEAD --oneline`

Require exactly 1 commit ahead of `origin/{DEFAULT_BRANCH}`.
If not, report the issue and stop.

## 9. Decide Whether the Full Test Suite Must Run

The finalize step usually changes nothing a test could see: `git reset --soft` +
commit rewrites history, not the tree. The one thing that can change the tree is
the rebase pulling in upstream work. So the question is narrow — what did the
rebase bring in, and can it break anything?

Compute the incoming upstream change:
- `git diff --name-only {BASE_BEFORE} origin/{DEFAULT_BRANCH}`

Call that set INCOMING. If BASE_BEFORE equals `origin/{DEFAULT_BRANCH}`, INCOMING
is empty and the branch was already up to date.

Run the full suite — do not skip — if any of these holds:
- The rebase in step 5 required conflict resolution
- No full-suite pass covers the feature branch's code: no full run passed earlier
  in this session against the current feature-branch code, and no run record
  holds a pass for HEAD_BEFORE (see below)
- INCOMING contains any file that is not documentation
- You cannot confidently classify a file in INCOMING

Skip the suite only when INCOMING is empty or documentation-only **and** a full
run already passed against the current feature-branch code, in this session or
in a run record for HEAD_BEFORE. A skip is a claim about test coverage — never
make it silently. Report the skip, the INCOMING file list, and which earlier run
it is relying on: the command this session ran, or the record's file and line.

### A pass from a peer-planning run record

A peer-planning `exec` run records a full-suite pass in its `progress.md`, as a
line of its own in a fixed form:

FULL-SUITE PASS sha=<40-character SHA> passed=<P> skipped=<S> collected=<C> command=<command>

The run directory sits at the root of the checkout its orchestrator ran in, which
is this worktree or the main checkout. Read both:
- `git rev-parse --show-toplevel`, and the main checkout, the parent of
  `git rev-parse --path-format=absolute --git-common-dir`
- `grep -h '^FULL-SUITE PASS sha=' <root>/.peer-planning/*/progress.md` in each

A record line counts only when every one of these holds:
- Its `sha` is exactly HEAD_BEFORE. The collapse does not change the tree, and a
  documentation-only INCOMING changes no code, so a pass on HEAD_BEFORE is a pass
  on the code this commit carries. exec writes the record after its last stage,
  so it names the branch's head unless code landed after the run; any later
  commit makes the record name an older commit, and then it does not count.
- CLEAN_BEFORE was recorded in step 3, and `git status --porcelain` prints
  nothing now.
- passed + skipped equals collected.

A line that does not parse in this form does not count. A record is a pass
another session saw, not one this session watched; say so in the report.

### What counts as documentation

Documentation:
- `*.md`, `*.mdx`, `*.rst`, `*.adoc`, `*.txt`, and files under `docs/`, `doc/`, `adrs/`
- `LICENSE`, `NOTICE`, `AUTHORS`, `CHANGELOG*`, `CONTRIBUTING*`, `CODE_OF_CONDUCT*`

Never documentation, whatever the extension — check each of these before deciding:
- Anything under `test/`, `tests/`, `spec/`, `testdata/`, `fixtures/`, `__snapshots__/`.
  Tests read these files, so editing prose in one can fail an assertion.
- Dependency and build manifests: `requirements*.txt`, `constraints*.txt`,
  `CMakeLists.txt`, `MANIFEST.in`, any lockfile.
- Markdown or text the project ships as **source** rather than prose. A repo whose
  product is prompts, skills, agents, templates, or content has `.md` files that are
  the code. Look at where the file lives, not at its extension.
- Markdown or rst executed as doctests. Grep the project config for
  `--doctest-glob`, `doctest_namespace`, or a Sphinx `doctest` builder first.

Anything that matches neither list is unclassified, and unclassified is not
documentation.

### When in doubt, ask

If any file in INCOMING is unclassified, or the earlier session run is only
probably still valid, do not guess in either direction. Show the INCOMING file
list, name the specific files or facts you are unsure about, and ask:
- "Run the full suite"
- "Skip the suite"

## 10. Run Verification

- Check CLAUDE.md or common project files for the test command
- Run the full test suite, unless step 9 decided to skip it
- Run the project's linter regardless — it is cheap and scoped to the final tree
- Report results, and state explicitly if the suite was skipped

If anything fails, stop before step 11. Do not merge or push a failing branch.

## 11. Land the Branch

Default flow: the feature branch is finished, so it goes into DEFAULT_BRANCH and
DEFAULT_BRANCH is published. Publishing the feature branch itself is the
exception, for when a pull request is wanted.

First find out whether the local merge is even available. Run:
- `git worktree list --porcelain`
- `git rev-parse --show-toplevel`

If a worktree other than this one holds `branch refs/heads/{DEFAULT_BRANCH}`, that
branch is locked to that checkout. Store that worktree's path as WORKTREE_PATH.
`git checkout {DEFAULT_BRANCH}` will fail with
`fatal: '{DEFAULT_BRANCH}' is already used by worktree at <path>`, and
`git fetch . HEAD:{DEFAULT_BRANCH}` refuses for the same reason. Do not attempt
either, and never move the ref behind that checkout's back with `git update-ref`
or `git branch -f` — the other worktree's index would still describe the old
commit, so it would come up looking like every file the branch added had been
deleted there. The commit goes straight to the remote instead, and the local
branch catches up afterwards.

Ask, in this order.

If DEFAULT_BRANCH is free:
- "Merge into {DEFAULT_BRANCH} and push" (default)
- "Push feature branch with force-with-lease"
- "Do nothing"

If DEFAULT_BRANCH is held by another worktree:
- "Push to origin/{DEFAULT_BRANCH} directly" (default)
- "Push feature branch with force-with-lease"
- "Do nothing"

In the second case, say in the question why the local merge is not on offer and
name WORKTREE_PATH.

### Merge into DEFAULT_BRANCH and push

Check the local DEFAULT_BRANCH first:
- `git rev-list --left-right --count {DEFAULT_BRANCH}...origin/{DEFAULT_BRANCH}`
- If it is behind, fast-forward it: `git checkout {DEFAULT_BRANCH}` then `git merge --ff-only origin/{DEFAULT_BRANCH}`
- If it has diverged (any commits on the left side), stop and report. Do not merge.

Then:
- `git checkout {DEFAULT_BRANCH}`
- `git merge --ff-only {CURRENT_BRANCH}`
- `git push origin {DEFAULT_BRANCH}`

`--ff-only` is required. HEAD was just rebased onto `origin/{DEFAULT_BRANCH}`, so a
fast-forward is the only correct outcome; if git refuses one, something moved
underneath and a merge commit would hide it. Stop and report instead.

Never force-push DEFAULT_BRANCH. If the push is rejected, someone else pushed
while you worked — report the rejection and stop, do not retry with force.

Leave the checkout on DEFAULT_BRANCH and say so in the report. The feature branch
is untouched; deleting it is the wrap-up's job (step 12).

### Push to origin/DEFAULT_BRANCH directly

Same landing, one hop fewer: the commit reaches the remote default branch without
a local checkout of it. It is still a fast-forward — step 5 rebased HEAD onto
`origin/{DEFAULT_BRANCH}` and nothing has moved since.

Confirm that before pushing:
- `git merge-base --is-ancestor origin/{DEFAULT_BRANCH} HEAD`
- If it fails, `origin/{DEFAULT_BRANCH}` moved after the rebase. Stop and report.

Then:
- `git push origin HEAD:{DEFAULT_BRANCH}`

Plain push — no `--force`, no `--force-with-lease`. The remote refuses a
non-fast-forward on its own, which is exactly the wanted behaviour: a rejection
means someone else pushed while you worked, so report it and stop.

The push updates the remote only. The local {DEFAULT_BRANCH} in WORKTREE_PATH is
now one commit behind `origin/{DEFAULT_BRANCH}`; report that either way. Whether
to fast-forward it depends on whether that checkout is dirty:
- `git -C {WORKTREE_PATH} status --porcelain`
- If it prints nothing, offer to run
  `git -C {WORKTREE_PATH} merge --ff-only origin/{DEFAULT_BRANCH}` — it is a
  fast-forward, but it does change files in a checkout the user may be sitting in
- If it prints anything, do not touch that worktree. Report the command so the
  user can run it once their work there is settled

In a session Claude Code isolated in a worktree, its guard refuses both
commands: `git -C` aimed at another checkout, usually the main one, is
refused whatever the form, and no setting turns it off. Never re-send a refused
command unchanged. Inside agterm (`AGTERM_SESSION_ID` is set), load the `agterm`
skill and run each command in a new agterm session rooted at WORKTREE_PATH,
which the guard does not reach: `agtermctl session new --cwd WORKTREE_PATH
--command … --wait`, as its "Launching a program in a session" says. Read the
output back with `agtermctl session text`, then close that session. Write the
path and the session id as literal text. The status check decides the rest
exactly as above. Outside agterm, the status is unknown: do not offer the
fast-forward, report both commands for the user to run in WORKTREE_PATH, and
say in the report that the check did not run.

This worktree's checkout does not move: it stays on CURRENT_BRANCH. Say so in the
report.

### Push feature branch with force-with-lease

- `git push --force-with-lease`

If push fails, report the error and stop.

## 12. Offer the Wrap-up

First release the landing lock (step 3), whatever step 11 did.

Only after a landing: the local merge or the direct push. A published feature
branch has not landed, and "Do nothing" landed nothing.

Ask whether to wrap up now. The wrap-up archives the plan under
docs/plans/completed/, drops the worktree's test database, removes the worktree
and the branch, and closes the peer-planning run record. If yes, invoke the
git:wrap-up skill with CURRENT_BRANCH as its argument. From inside a worktree it
removes that worktree too, last, and this session then goes on from another
directory; say so in the offer.

## 13. Report

Summarize:
- CURRENT_BRANCH
- DEFAULT_BRANCH
- Whether rebase was clean or had conflicts
- What the rebase pulled in, and whether the test suite ran or was skipped and why
- Whether commits were collapsed
- Final commit message
- Which landing path was taken — local merge, direct push to the remote default
  branch because another worktree holds it, or feature-branch publish
- What was pushed, if anything, and which branch the checkout is now on
- For the direct-push path: whether the local default branch in the other
  worktree was fast-forwarded or left behind, and its path
- Whether the wrap-up was offered, and what the user chose
- That the landing lock was taken and released, or that a stale or live lock was
  broken, and whose it was
- Test/lint results
- Any issues encountered

## Output Format

No markdown formatting. Plain text only.
- No headings
- No bold
- No backticks
