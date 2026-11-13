#!/usr/bin/env python3
"""Find a persona panel's cast, copy it into a project, and make the folder a panel writes in.

Usage: cast.py [--repo DIR]
       cast.py init [--repo DIR]
       cast.py run-dir SLUG [--repo DIR]

With no command it prints the cast as JSON: the layer it came from, where in that layer (`source`),
its directory, its index (README.md, or null), each persona's stem and path, and the project's
profile (`profile`: its path and source, or null). The cast comes from
the first of three layers that holds any persona file, a `*.md` other than README.md:

  project   .personas/cast/ in the checkout, or else on the repository's default branch
  user      ~/.config/personas/cast/
  built-in  the cast shipped beside this script

The whole cast comes from one layer, never merged file by file: persona names differ between
projects, so a merge would set a generic "person who uses the product" beside a project's own
shopper and the panel would pick from both.

A checkout with no cast of its own may still belong to a project that has one: a worktree branched
before the cast landed, or moved. Its panel reads the default branch's cast, never a generic one, so
a session running in that worktree keeps the project's people without a rebase. Of the local and
remote default branch, the newer one is read: work can land on either side first. The files
are written once per commit under the repository's git directory (personas-cast/<sha>/), which is
never committed and is shared by every worktree; `source` names the branch and commit.

The profile, .personas/profile.md, says what the project is: the product, its scale, its rules and
the teams it compares itself with. Every persona, the practice scout and the moderator read it first.
It has one layer, the project's: a profile is about one project, so no user or built-in profile
stands in for it. A checkout without one reads the default branch's, as for the cast, written under
the git directory (personas-profile/<sha>.md); with neither, `profile` is null.

`init` copies the cast that resolves into .personas/cast/ so the project has a local copy to edit.
It refuses a checkout whose .personas/cast/ already holds any file, and one whose default branch
already has a cast, which a rebase brings in instead.

`run-dir` makes .personas/runs/<YYYY-MM-DD>-<SLUG>/ and prints its path. The runs folder holds a
.gitignore of `*`, which ignores the folder and itself, so a panel's files never show in
`git status` and a project needs no ignore rule of its own. An existing folder is refused, so
two panels never write into one.
"""

# The macOS system python3 (3.9) may run this; it needs this for `str | None`.
from __future__ import annotations

import datetime
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

PROJECT_CAST = Path(".personas") / "cast"
PROJECT_PROFILE = Path(".personas") / "profile.md"
RUNS = Path(".personas") / "runs"
BUILT_IN = Path(__file__).resolve().parent.parent / "cast"


def fail(message: str) -> None:
    print(f"cast: {message}", file=sys.stderr)
    sys.exit(1)


def git(cwd: Path, *args: str) -> str:
    done = subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True)
    return done.stdout.strip() if done.returncode == 0 else ""


def checkout_root(start: Path) -> Path:
    if not start.is_dir():
        fail(f"{start} is not a directory")
    top = git(start, "rev-parse", "--show-toplevel")
    return Path(top) if top else start.resolve()


def is_persona(name: str) -> bool:
    return name.endswith(".md") and Path(name).name != "README.md"


def personas(directory: Path) -> list[Path]:
    if not directory.is_dir():
        return []
    return sorted(p for p in directory.glob("*.md") if is_persona(p.name))


def commit_of(root: Path, ref: str) -> str:
    return git(root, "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}")


def default_refs(root: Path) -> list[str]:
    """The default branch's local and remote refs that exist, the newer first.

    Work can land on either side first: a commit on the local branch waits for its push, and a
    worktree that pushes straight to the remote leaves the local branch behind until someone
    fast-forwards it. When one contains the other, the containing one is read first; when they have
    diverged, the local one is.
    """
    remote_head = git(root, "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD")
    names = [remote_head.removeprefix("refs/remotes/origin/")] if remote_head else ["master", "main", "trunk"]
    refs: list[str] = []
    for name in names:
        local, upstream = f"refs/heads/{name}", f"refs/remotes/origin/{name}"
        pair = [ref for ref in (local, upstream) if commit_of(root, ref)]
        if len(pair) == 2 and commit_of(root, local) != commit_of(root, upstream):
            local_is_behind = subprocess.run(
                ["git", "-C", str(root), "merge-base", "--is-ancestor", local, upstream],
            ).returncode == 0
            if local_is_behind:
                pair.reverse()
        refs += pair
    return refs


def default_branch_cast(root: Path) -> tuple[str, Path] | None:
    """The default branch's cast, written out under the git directory, or None when it has none."""
    for ref in default_refs(root):
        sha = commit_of(root, ref)
        label = ref.removeprefix("refs/heads/").removeprefix("refs/remotes/")
        listed = git(root, "ls-tree", "--name-only", sha, "--", f"{PROJECT_CAST.as_posix()}/")
        names = [n for n in listed.splitlines() if n.endswith(".md")]
        if not any(is_persona(n) for n in names):
            continue
        common = Path(git(root, "rev-parse", "--git-common-dir"))
        target = (common if common.is_absolute() else root / common).resolve() / "personas-cast" / sha
        if not target.is_dir():
            # Two sessions may resolve the same commit at once: each stages under its own name and
            # the first rename wins; the loser's copy is identical, so it is dropped.
            staging = target.with_name(f"{sha}.{os.getpid()}.partial")
            staging.mkdir(parents=True)
            for name in names:
                body = subprocess.run(["git", "-C", str(root), "show", f"{sha}:{name}"], capture_output=True)
                if body.returncode:
                    fail(f"could not read {name} at {label} ({sha[:9]}): {body.stderr.decode().strip()}")
                (staging / Path(name).name).write_bytes(body.stdout)
            try:
                staging.rename(target)
            except OSError:
                if not target.is_dir():
                    raise
                shutil.rmtree(staging)
        return f"{label} at {sha[:9]}", target
    return None


def git_dir_file(root: Path, folder: str, name: str, body: bytes) -> Path:
    """Write body once to <git common dir>/<folder>/<name> and return the path.

    Two sessions may write the same commit's file at once: each stages under its own name and the
    first rename wins; the copies are identical, so the loser's is dropped.
    """
    common = Path(git(root, "rev-parse", "--git-common-dir"))
    target = (common if common.is_absolute() else root / common).resolve() / folder / name
    if not target.is_file():
        target.parent.mkdir(parents=True, exist_ok=True)
        staging = target.with_name(f"{name}.{os.getpid()}.partial")
        staging.write_bytes(body)
        try:
            staging.rename(target)
        except OSError:
            if not target.is_file():
                raise
            staging.unlink()
    return target


def profile(root: Path) -> dict[str, str] | None:
    """The project's profile: the checkout's, else the default branch's, else None."""
    local = root / PROJECT_PROFILE
    if local.is_file():
        return {"source": "checkout", "path": str(local)}
    for ref in default_refs(root):
        sha = commit_of(root, ref)
        label = ref.removeprefix("refs/heads/").removeprefix("refs/remotes/")
        if git(root, "cat-file", "-t", f"{sha}:{PROJECT_PROFILE.as_posix()}") != "blob":
            continue
        body = subprocess.run(
            ["git", "-C", str(root), "show", f"{sha}:{PROJECT_PROFILE.as_posix()}"], capture_output=True
        )
        if body.returncode:
            fail(f"could not read {PROJECT_PROFILE} at {label} ({sha[:9]}): {body.stderr.decode().strip()}")
        path = git_dir_file(root, "personas-profile", f"{sha}.md", body.stdout)
        return {"source": f"{label} at {sha[:9]}", "path": str(path)}
    return None


def resolve(root: Path) -> dict[str, object]:
    candidates: list[tuple[str, str, Path]] = [("project", "checkout", root / PROJECT_CAST)]
    if not personas(root / PROJECT_CAST):
        found = default_branch_cast(root)
        if found:
            candidates.append(("project", found[0], found[1]))
    candidates += [
        ("user", "~/.config/personas/cast", Path.home() / ".config" / "personas" / "cast"),
        ("built-in", "decide:panel", BUILT_IN),
    ]
    for layer, source, directory in candidates:
        found_personas = personas(directory)
        if found_personas:
            index = directory / "README.md"
            return {
                "layer": layer,
                "source": source,
                "dir": str(directory),
                "index": str(index) if index.is_file() else None,
                "personas": [{"stem": p.stem, "path": str(p)} for p in found_personas],
                "profile": profile(root),
            }
    fail(f"no persona files in any layer; the built-in cast at {BUILT_IN} is missing")
    raise AssertionError


def init(root: Path) -> None:
    target = root / PROJECT_CAST
    if target.is_dir() and any(target.iterdir()):
        fail(f"{target} already holds files; edit them there")
    cast = resolve(root)
    if cast["layer"] == "project":
        fail(f"the default branch already has a cast ({cast['source']}); rebase onto it instead")
    source = Path(str(cast["dir"]))
    target.mkdir(parents=True, exist_ok=True)
    for path in sorted(source.glob("*.md")):
        shutil.copy2(path, target / path.name)
    print(f"copied the {cast['layer']} cast from {source} to {target}")


def run_dir(root: Path, slug: str) -> None:
    if not slug or "/" in slug or slug.startswith(".") or slug.startswith("-"):
        fail(f"a slug is one plain path segment, not {slug!r}")
    runs = root / RUNS
    runs.mkdir(parents=True, exist_ok=True)
    ignore = runs / ".gitignore"
    if not ignore.is_file():
        ignore.write_text("*\n")
    target = runs / f"{datetime.date.today().isoformat()}-{slug}"
    if target.exists():
        fail(f"{target} already exists; add a suffix such as -2 to the slug")
    target.mkdir()
    print(target)


def main(argv: list[str]) -> None:
    repo = Path.cwd()
    if "--repo" in argv:
        at = argv.index("--repo")
        if at + 1 >= len(argv):
            fail("--repo needs a directory")
        repo = Path(argv[at + 1])
        argv = argv[:at] + argv[at + 2 :]
    root = checkout_root(repo)
    if not argv:
        print(json.dumps(resolve(root), indent=2))
    elif argv == ["init"]:
        init(root)
    elif len(argv) == 2 and argv[0] == "run-dir":
        run_dir(root, argv[1])
    else:
        fail(f"unexpected arguments {argv!r}; see the usage in this script's docstring")


if __name__ == "__main__":
    main(sys.argv[1:])
