#!/usr/bin/env python3
"""Before a task starts: bring this run's branch up to the default branch, and find the other open
plans that touch the same files.

Usage: branch-overlap.py WORK_PATH [--rebase] [--paths PATH ...]

The other open plans are the branches checked out in the repository's other worktrees that have
not landed on the default branch. A file overlaps when this branch has changed it, or the task
names it in --paths, and another open branch has changed it too. For each overlap it says which
branch started later, by the first commit each has that the default branch lacks: the plan that
started later is the one that adapts or waits, without asking the user.

--rebase, when the default branch has moved on and the working tree is clean, rebases this branch
onto it. A conflict is never left half-done: the rebase is aborted and the conflicting files are
reported, so the run goes on from the old base and the user hears about it.

Prints one JSON object: base, behind, rebased (true, false, or "conflict"), conflicts, this_started,
overlaps [{branch, worktree, started, later, files}]. Exit 1 on a git failure.
"""

# The macOS system python3 (3.9) may run this; it needs this for `str | None`.
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"branch-overlap: {message}", file=sys.stderr)
    sys.exit(1)


def git(cwd: Path, *args: str, check: bool = True) -> str:
    done = subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True)
    if check and done.returncode:
        fail(f"git {' '.join(args)}: {done.stderr.strip()}")
    return done.stdout.strip()


def default_ref(cwd: Path) -> str:
    ref = git(cwd, "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD", check=False)
    if ref:
        return ref.removeprefix("refs/remotes/")
    for name in ("origin/master", "origin/main", "master", "main"):
        if git(cwd, "rev-parse", "--verify", "--quiet", name, check=False):
            return name
    fail("no default branch found")
    raise AssertionError


def changed(cwd: Path, base: str, ref: str) -> set[str]:
    return set(filter(None, git(cwd, "diff", "--name-only", f"{base}...{ref}").splitlines()))


def first_own_commit(cwd: Path, base: str, ref: str) -> str:
    """When the branch started: its oldest commit the default branch lacks, or "" when it has none."""
    stamps = git(cwd, "log", "--reverse", "--format=%cI", f"{base}..{ref}").splitlines()
    return stamps[0] if stamps else ""


def worktree_branches(cwd: Path) -> list[tuple[Path, str]]:
    found, path = [], None
    for line in git(cwd, "worktree", "list", "--porcelain").splitlines():
        if line.startswith("worktree "):
            path = Path(line[len("worktree "):])
        elif line.startswith("branch ") and path is not None:
            found.append((path, line[len("branch refs/heads/"):]))
    return found


def main(argv: list[str]) -> None:
    if not argv or argv[0].startswith("--"):
        fail("usage: branch-overlap.py WORK_PATH [--rebase] [--paths PATH ...]")
    work = Path(argv[0]).resolve()
    rebase = "--rebase" in argv
    paths = set(argv[argv.index("--paths") + 1:]) if "--paths" in argv else set()

    git(work, "fetch", "--quiet", "origin", check=False)
    base = default_ref(work)
    behind = int(git(work, "rev-list", "--count", f"HEAD..{base}") or 0)
    rebased: bool | str = False
    conflicts: list[str] = []
    if rebase and behind and not git(work, "status", "--porcelain"):
        done = subprocess.run(["git", "-C", str(work), "rebase", "--quiet", base], capture_output=True, text=True)
        if done.returncode:
            conflicts = git(work, "diff", "--name-only", "--diff-filter=U", check=False).splitlines()
            git(work, "rebase", "--abort", check=False)
            rebased = "conflict"
        else:
            rebased = True
            behind = 0

    mine = changed(work, base, "HEAD") | paths
    this_started = first_own_commit(work, base, "HEAD")
    current = git(work, "rev-parse", "--abbrev-ref", "HEAD")
    overlaps = []
    for path, branch in worktree_branches(work):
        if path.resolve() == work or branch == current or branch == base.split("/")[-1]:
            continue
        if subprocess.run(["git", "-C", str(work), "merge-base", "--is-ancestor", branch, base]).returncode == 0:
            continue  # landed: nothing left to collide with
        shared = sorted(mine & changed(work, base, branch))
        if shared:
            started = first_own_commit(work, base, branch)
            later = "this" if this_started and (not started or this_started > started) else branch
            overlaps.append({"branch": branch, "worktree": str(path), "started": started, "later": later, "files": shared})
    print(json.dumps({"base": base, "behind": behind, "rebased": rebased, "conflicts": conflicts,
                      "this_started": this_started, "overlaps": overlaps}))


if __name__ == "__main__":
    main(sys.argv[1:])
