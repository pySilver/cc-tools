---
name: finalize-feature-branch
description: After review approval, rebase onto the default branch, collapse the feature branch into a single commit, verify it, and optionally force-push the rewritten branch.
disable-model-invocation: true
allowed-tools: Bash, Read, Glob, Grep
---

# Finalize Feature Branch as One Commit

Policy: the finalized branch must end with exactly one commit ahead of origin/{DEFAULT_BRANCH}.

## 1. Determine Default Branch

If $ARGUMENTS is provided, use it as DEFAULT_BRANCH.

Otherwise:
- Detect the likely default branch with: `git remote show origin | grep "HEAD branch"`
- Ask the user which branch to use via AskUserQuestion
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

Ask the user to confirm via AskUserQuestion:
- "Proceed"
- "Abort"

If the user chooses "Abort", stop.

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
- Ask the user to confirm or edit the message via AskUserQuestion
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

## 9. Run Verification

- Check CLAUDE.md or common project files for the test command
- Run the project's test suite
- Run the project's linter if applicable
- Report results

## 10. Offer Optional Push

Ask the user via AskUserQuestion:
- "Push with force-with-lease"
- "Skip push"

If the user chooses push, run:
- `git push --force-with-lease`

If push fails, report the error and stop.

## 11. Report

Summarize:
- CURRENT_BRANCH
- DEFAULT_BRANCH
- Whether rebase was clean or had conflicts
- Whether commits were collapsed
- Final commit message
- Whether the branch was pushed
- Test/lint results
- Any issues encountered

## Output Format

No markdown formatting. Plain text only.
- No headings
- No bold
- No backticks
