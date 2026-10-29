---
name: wrap-up
description: Clean up after a feature branch has landed. Archives its plan under docs/plans/completed/, drops the worktree's test database, removes the worktree and the branch, closes the peer-planning run record and its monitor, and reports containers the worktree stranded. finalize-feature-branch offers it once the branch is on the default branch; /git:wrap-up [branch] runs it alone, and from the main checkout with no argument it offers every worktree whose branch has landed. Use when the user says wrap up, clean up the worktree, remove the worktree, drop the test database, or archive the plan after a feature landed.
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
---

# Wrap up a landed feature branch

Finalize lands the branch and leaves everything else where it was: the worktree, its branch, the
test database the worktree setup created, the plan still under `docs/plans/`, and a peer-planning
run record with its monitor session. This skill removes them, after the user ticks what goes. It
refuses a branch that has not landed.

It works from the main checkout throughout: a worktree is removed from outside, the plan is
archived on the default branch, and the compose stack belongs to the main tree.

## 1. Find the branch and where it lives

- BRANCH is $ARGUMENTS when given. Otherwise, inside a worktree, it is the output of
  `git branch --show-current` there. In the main checkout with no argument, run the check in
  step 2 for every worktree and offer those whose branch has landed; the user picks one or
  several, and each goes through the steps below in turn.
- MAIN is the first entry of `git worktree list --porcelain`. DEFAULT_BRANCH is
  `git symbolic-ref --short refs/remotes/origin/HEAD` without its `origin/` prefix.
- WORKTREE is the entry of `git worktree list --porcelain` that holds `branch refs/heads/BRANCH`,
  if any, and NAME is its directory name (`.claude/worktrees/<name>` in this user's repositories).
- If `git rev-parse --show-toplevel` in this session is WORKTREE, the session sits inside the
  worktree. Say so at once: every step runs except the removal, which a session cannot do to the
  directory it stands in, and step 8 prints the commands for the main checkout instead.

## 2. Confirm it landed

- `git fetch origin`
- `git merge-base --is-ancestor BRANCH origin/DEFAULT_BRANCH`

Finalize puts the branch's own commit on the default branch, so after it this holds. If it fails,
show `git log origin/DEFAULT_BRANCH..BRANCH --oneline` and stop: nothing below runs over work
that is not on the default branch. The one exception is a branch merged another way, such as a
pull request squash-merged on the remote. The user says so in their own words, and the report
records that it was taken on their word. Never infer it.

## 3. Gather what there is to remove

Collect each item before asking, so the question shows what exists and not a generic list.

- **The plan.** A `docs/plans/*.md` outside `completed/` on `origin/DEFAULT_BRANCH` whose stem
  without its date is NAME or the branch's slug. A `.peer-planning/<plan-stem>/events.jsonl` in
  MAIN or WORKTREE names it as `plan` on its `run.start` line. When nothing matches, ask whether
  the branch has a plan; a branch without one skips step 5.
- **The run record.** `.peer-planning/<plan-stem>/` in MAIN or in WORKTREE, and an agterm session
  named `<plan-stem> monitor` (`agtermctl tree --json`, when `AGTERM_SESSION_ID` is set).
- **The test database.** In this user's main repository, `scripts/setup-worktree.py` writes
  `DATABASES.default.NAME` into `WORKTREE/.envs/.override.yaml`, and pytest's database is that
  name with `test_` in front, on the `postgres-test` compose service. Read the name from the
  file. If the worktree is already gone, list that service's databases whose name starts with
  `test_mybaze_<slug>` and offer them.
- **The worktree and the branch.** WORKTREE, whether it is clean (`git -C WORKTREE status
  --porcelain`), BRANCH, and `origin/BRANCH` if the remote has it.

## 4. Ask

Offer the items found as a multi-select choice with every one ticked, each saying what it is and
what removing it costs: the plan's path and the commit it gets; the run record's size, and that
the monitor and later tuning of the exec skill lose it; the database name; the worktree path and
whether it is clean; the branch, and its remote copy if there is one. Nothing is removed until the
user answers.

## 5. Archive the plan

On DEFAULT_BRANCH in MAIN, with nothing staged (`git -C MAIN status --porcelain` shows no staged
entry; otherwise stop and say what is staged):

- `git -C MAIN checkout DEFAULT_BRANCH` if it is not there, then `git -C MAIN pull --ff-only`
- `git -C MAIN mv docs/plans/PLAN.md docs/plans/completed/PLAN.md`
- commit it as `docs(plans): <title>, completed`, the title being the plan's H1 with its first
  letter lowercased; a rename and nothing else
- `git -C MAIN push origin DEFAULT_BRANCH`

The commit goes through the project's hooks like any other. A rejected push means someone else
pushed meanwhile: report it and stop.

## 6. Remove the run record

- Close the monitor: `agtermctl session close --target ID` for each session named
  `<plan-stem> monitor`.
- `rm -rf MAIN/.peer-planning/<plan-stem>`. A copy inside WORKTREE goes with the worktree.

## 7. Drop the test database

From MAIN, which owns the compose stack:

- `pgrep -f "pytest.*WORKTREE"`; a running pytest means the worktree is still in use, so stop.
- `docker compose exec -T postgres-test dropdb -U postgres --if-exists --force test_DBNAME`

`--force` ends a connection a finished pytest left open; the check above is what keeps it from
ending a live run.

## 8. Remove the worktree and the branch

- `git -C MAIN worktree remove WORKTREE`. It refuses an unclean worktree: show the status and
  stop. Never add `--force` unasked; an untracked file is someone's work until the user says
  otherwise.
- `git -C MAIN branch -d BRANCH`. `-d` refuses a branch not merged into its upstream, which step 2
  rules out, so a refusal is news: report it, never `-D`.
- `git push origin --delete BRANCH`, when `origin/BRANCH` exists and the user ticked it.

Inside the worktree, print these commands with their values filled in, for the user to run from
MAIN, and go on to step 9.

## 9. Check for stranded containers

A container created from inside the worktree is pinned to that path and cannot start again once
the directory is gone, and one without a bind mount keeps running under a compose project that
now points nowhere. After the removal, run the scan from the project's worktree runbook:

```bash
for c in $(docker ps -aq); do
  wd=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' "$c" 2>/dev/null)
  mn=$(docker inspect --format '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}} {{end}}{{end}}' "$c" 2>/dev/null)
  case "$wd$mn" in *".claude/worktrees"*) echo "STRANDED: $(docker inspect --format '{{.Name}}' "$c")";; esac
done
```

Report what it prints and name the runbook (`docs/runbooks/worktree-setup.md`, "Removing a
worktree"). Remove no container: the fix costs a volume, and that is the user's call.

## 10. Report

Plain text, no markdown. One line per item: archived, removed, dropped or deleted, or left and
why; the archive commit's SHA; the commands left for the user when the session sat inside the
worktree; whether the landing was confirmed by ancestry or taken on the user's word; and any
stranded container.
