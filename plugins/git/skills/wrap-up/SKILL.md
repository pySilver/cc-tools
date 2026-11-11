---
name: wrap-up
description: Clean up after a feature branch has landed. Archives its plan under docs/plans/completed/, drops the worktree's test database, removes the worktree and the branch, closes the peer-planning run record and its monitor and removes the branch's revmux review task, after keeping the run's event log and the review rounds' results in a ledger outside git, and reports containers the worktree stranded. finalize-feature-branch offers it once the branch is on the default branch; /git:wrap-up [branch] runs it alone, and from the main checkout with no argument it offers every worktree whose branch has landed. Use when the user says wrap up, clean up the worktree, remove the worktree, drop the test database, or archive the plan after a feature landed.
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
---

# Wrap up a landed feature branch

Finalize lands the branch and leaves everything else where it was: the worktree, its branch, the
test database the worktree setup created, the plan still under `docs/plans/`, a peer-planning
run record with its monitor session, and the branch's revmux review rounds. This skill removes
them, after the user ticks what goes. Before it removes anything it copies the few files later
analysis reads, the run's event log and progress notes and each round's results, into a ledger
that outlives the worktree. It refuses a branch that has not landed.

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
  worktree. Say so at once, and say that every step still runs: step 9 removes the worktree from
  MAIN, after everything that reads it, and this session goes on from another directory.

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
  the branch has a plan; a branch without one skips step 6.
- **The run record.** `.peer-planning/<plan-stem>/` in MAIN or in WORKTREE, and an agterm session
  named `<plan-stem> monitor` (`agtermctl tree --json`, when `AGTERM_SESSION_ID` is set).
- **The review rounds.** Run `"${CLAUDE_SKILL_DIR}/scripts/keep-records.py" inspect --main MAIN
  --branch BRANCH`, adding `--worktree WORKTREE` while the worktree exists, `--name NAME` when
  NAME is known and `--plan-stem <plan-stem>` when the branch has a plan. Step 5 passes the same
  arguments to `copy`. Its JSON lists under `tasks` every revmux task of the branch in MAIN's and
  WORKTREE's `.revmux/tasks`: one whose `task.md` front matter says `branch: BRANCH`, or whose id
  is BRANCH with every `/` made `-`, the plan stem, or `plan-NAME`, as night plans name theirs.
  Each entry has its `tree`, `id`, `rounds` (the finished ones), `unfinished` and `size_mb`; `runs`
  says where the run record's event log is. Only MAIN's tasks are offered for removal. A task
  inside WORKTREE goes with the worktree.
- **The test database.** In this user's main repository, `scripts/setup-worktree.py` writes
  `DATABASES.default.NAME` into `WORKTREE/.envs/.override.yaml`, and pytest's database is that
  name with `test_` in front, on the `postgres-test` compose service. Read the name from the
  file. If the worktree is already gone, list that service's databases whose name starts with
  `test_mybaze_<slug>` and offer them.
- **The second machine's mirror.** Only when `MYBAZE_SUITE_REMOTE` is set and not empty; when it
  is unset, skip this item without a word. A pytest the suite lock held back may have run on the
  machine it names, which leaves a mirror of the worktree there and test databases in that
  machine's `postgres-test`. With the database name read above, and while the worktree still
  exists, run `"${CLAUDE_SKILL_DIR}/scripts/offload-mirror.py" inspect DBNAME`. It prints JSON:
  - `present`: offer it, naming `host`, `directory` and `databases`;
  - `absent` or `skipped`: nothing to offer;
  - `busy`: a run is alive in the mirror; leave it and say so in the report;
  - `unreachable`: report "second machine unreachable, mirror left";
  - `error`: report its `detail`, and leave the mirror.

  The script bounds every ssh call and never opens the browser login URL a Tailscale check
  prints; never open one yourself, and never edit `~/.ssh/config` to get past it.
- **The worktree and the branch.** WORKTREE, whether it is clean (`git -C WORKTREE status
  --porcelain`), BRANCH, and `origin/BRANCH` if the remote has it.

## 4. Ask

Offer the items found as a multi-select choice with every one ticked, each saying what it is and
what removing it costs: the plan's path and the commit it gets; the run record's size, and that
the monitor loses it while its event log and progress notes stay in the ledger; each of MAIN's
review tasks with its round count and size, and that the rounds' results stay in the ledger while
the agents' transcripts and inputs go; the database name; the second machine's host, mirror
directory and database names; the worktree path and whether it is clean, and that a run record or
review task inside it goes with it; the branch, and its remote copy if there is one. Nothing is
removed until the user answers.

## 5. Keep the records

Everything below deletes, so first copy what later analysis reads into the ledger,
`<git common dir>/workflow-ledger/`: outside git, shared by every worktree, and left alone by
everything this skill removes. Run it whatever the user ticked; it only writes to the ledger.

- `"${CLAUDE_SKILL_DIR}/scripts/keep-records.py" copy` with the arguments step 3 gave `inspect`.

It copies the run record's `events.jsonl` and `progress.md`, from whichever tree holds them, to
`runs/<plan-stem>/`, and every finished round of every task step 3 listed, from both trees, to
`revmux/<task-id>/<round>/` with its `manifest.json`, `findings.json` and `stages/`. That is the
part of a round revmux's `analyze-corpus.py` reads, and `--tasks-dir <ledger>/revmux` reads the
ledger as an archive. A round whose `manifest.json` is missing or empty never finished; it is
listed under `skipped`. When a name already holds different files, as when MAIN and WORKTREE both
hold `02-after-fix` of one task, the second copy goes under `<round>~<digest>` and its entry
carries `renamed_from`, so neither is lost. A second run copies nothing.

Its JSON says `kept`, with each entry `copied` or `already kept`. On `failed` (an entry's `error`
says why) or `error`, it exits 1: stop the whole wrap-up there and report what it printed.
Nothing below may delete what was not kept.

## 6. Archive the plan

On DEFAULT_BRANCH in MAIN, with nothing staged (`git -C MAIN status --porcelain` shows no staged
entry; otherwise stop and say what is staged):

- `git -C MAIN checkout DEFAULT_BRANCH` if it is not there, then `git -C MAIN pull --ff-only`
- `git -C MAIN mv docs/plans/PLAN.md docs/plans/completed/PLAN.md`
- commit it as `docs(plans): <title>, completed`, the title being the plan's H1 with its first
  letter lowercased; a rename and nothing else
- `git -C MAIN push origin DEFAULT_BRANCH`

The commit goes through the project's hooks like any other. A rejected push means someone else
pushed meanwhile: report it and stop.

## 7. Remove the run record and the review tasks

- Close the monitor: `agtermctl session close --target ID` for each session named
  `<plan-stem> monitor`.
- `rm -rf MAIN/.peer-planning/<plan-stem>`. A copy inside WORKTREE goes with the worktree.
- For each of MAIN's review tasks the user ticked, `cd MAIN && revmux cleanup --task ID`. revmux
  reads its tasks root from the working directory, and this is the only way it allows a task to
  be removed: never delete a task directory any other way. It refuses a task a running review
  holds; leave that task and report it.

## 8. Drop the test database

From MAIN, which owns the compose stack:

- `pgrep -f "pytest.*WORKTREE"`; a running pytest means the worktree is still in use, so stop.
- `docker compose exec -T postgres-test dropdb -U postgres --if-exists --force test_DBNAME`

`--force` ends a connection a finished pytest left open; the check above is what keeps it from
ending a live run.

When the user ticked the second machine's mirror, remove it with
`"${CLAUDE_SKILL_DIR}/scripts/offload-mirror.py" remove DBNAME`. It checks again for a live run
there and touches nothing if it finds one, removes the mirror directory by its derived path, and
drops the mirror's databases by exact name in the `mybaze.postgres-test` container. It never
runs `docker compose` on that machine, where `postgres-test` is a standing service. Its JSON
says `removed` with `dropped` and `failed`, or `busy`, `unreachable` or `error` as above.

## 9. Remove the worktree and the branch

- `git -C MAIN worktree remove WORKTREE`. It refuses an unclean worktree: show the status and
  stop. Never add `--force` unasked; an untracked file is someone's work until the user says
  otherwise.
- `git -C MAIN branch -d BRANCH`. `-d` refuses a branch not merged into its upstream, which step 2
  rules out, so a refusal is news: report it, never `-D`.
- `git push origin --delete BRANCH`, when `origin/BRANCH` exists and the user ticked it.

Inside the worktree, run them all the same, in one Bash call that starts with `cd MAIN`. git
removes a worktree a process stands in, and Claude Code recovers the shell: the next Bash call
fails once with `Working directory "…" was deleted; shell cwd recovered to …` and runs when
issued again (measured 2026-10-31 in a throwaway repository). Issue that call again, and from
here on use absolute paths. Everything that reads the worktree comes before this step, as steps
3 to 8 already do. Tell the user the session now stands outside any checkout; it can finish the
remaining steps, and they close it when they are done.

## 10. Check for stranded containers

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

## 11. Report

Plain text, no markdown. One line per item: archived, removed, dropped or deleted, or left and
why; the archive commit's SHA; the ledger: the `runs/<plan-stem>/` path and each
`revmux/<task-id>/` path with its round count, any round kept under a digest name and why, and
any skipped as unfinished; whether the session sat inside the worktree it
removed; whether the landing was confirmed by ancestry or taken on the user's word; the second
machine's mirror, when `MYBAZE_SUITE_REMOTE` is set: removed with the databases dropped, left
because a run was alive, or left because the machine was unreachable; and any stranded
container.
