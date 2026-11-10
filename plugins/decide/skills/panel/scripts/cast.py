#!/usr/bin/env python3
"""Find a persona panel's cast, copy it into a project, and make the folder a panel writes in.

Usage: cast.py [--repo DIR]
       cast.py init [--repo DIR]
       cast.py run-dir SLUG [--repo DIR]

With no command it prints the cast as JSON: the layer it came from, its directory, its index
(README.md, or null) and each persona's stem and path. The cast comes from the first of three
layers that holds any persona file, a `*.md` other than README.md:

  project   .personas/cast/ at the root of the checkout
  user      ~/.config/personas/cast/
  built-in  the cast shipped beside this script

The whole cast comes from one layer, never merged file by file: persona names differ between
projects, so a merge would set a generic "person who uses the product" beside a project's own
shopper and the panel would pick from both.

A checkout with no project cast whose default branch has one is refused, not given the next
layer: it is a worktree branched before the cast landed, and a generic cast answering that
project's question gives a wrong card that looks right. Rebasing onto the default branch fixes it.

`init` copies the cast that resolves into .personas/cast/ so the project has a local copy to edit.
It refuses a checkout that already has a project cast.

`run-dir` makes .personas/runs/<YYYY-MM-DD>-<SLUG>/ and prints its path. The runs folder holds a
.gitignore of `*`, which ignores the folder and itself, so a panel's files never show in
`git status` and a project needs no ignore rule of its own. An existing folder is refused, so
two panels never write into one.
"""

# The macOS system python3 (3.9) may run this; it needs this for `str | None`.
from __future__ import annotations

import datetime
import json
import shutil
import subprocess
import sys
from pathlib import Path

PROJECT_CAST = Path(".personas") / "cast"
RUNS = Path(".personas") / "runs"
BUILT_IN = Path(__file__).resolve().parent.parent / "cast"


def fail(message: str) -> None:
    print(f"cast: {message}", file=sys.stderr)
    sys.exit(1)


def git(cwd: Path, *args: str) -> str:
    done = subprocess.run(["git", "-C", str(cwd), *args], capture_output=True, text=True)
    return done.stdout.strip() if done.returncode == 0 else ""


def checkout_root(start: Path) -> Path:
    top = git(start, "rev-parse", "--show-toplevel")
    return Path(top) if top else start.resolve()


def default_ref(root: Path) -> str:
    ref = git(root, "symbolic-ref", "--quiet", "refs/remotes/origin/HEAD")
    if ref:
        return ref.removeprefix("refs/remotes/")
    for name in ("origin/master", "origin/main", "master", "main"):
        if git(root, "rev-parse", "--verify", "--quiet", name):
            return name
    return ""


def personas(directory: Path) -> list[Path]:
    if not directory.is_dir():
        return []
    return sorted(p for p in directory.glob("*.md") if p.name != "README.md")


def refuse_stale_checkout(root: Path) -> None:
    ref = default_ref(root)
    if not ref:
        return
    listed = git(root, "ls-tree", "-r", "--name-only", ref, "--", PROJECT_CAST.as_posix())
    if any(Path(name).suffix == ".md" and Path(name).name != "README.md" for name in listed.splitlines()):
        fail(
            f"{ref} has a project cast in {PROJECT_CAST}/ and this checkout ({root}) does not; "
            f"rebase or merge {ref} first, or the panel would answer with another layer's cast"
        )


def resolve(root: Path) -> dict[str, object]:
    project = root / PROJECT_CAST
    if not personas(project):
        refuse_stale_checkout(root)
    layers = (("project", project), ("user", Path.home() / ".config" / "personas" / "cast"), ("built-in", BUILT_IN))
    for layer, directory in layers:
        found = personas(directory)
        if found:
            index = directory / "README.md"
            return {
                "layer": layer,
                "dir": str(directory),
                "index": str(index) if index.is_file() else None,
                "personas": [{"stem": p.stem, "path": str(p)} for p in found],
            }
    fail(f"no persona files in any layer; the built-in cast at {BUILT_IN} is missing")
    raise AssertionError


def init(root: Path) -> None:
    target = root / PROJECT_CAST
    if personas(target):
        fail(f"{target} already holds a cast; edit it there")
    cast = resolve(root)
    source = Path(str(cast["dir"]))
    target.mkdir(parents=True, exist_ok=True)
    for path in sorted(source.glob("*.md")):
        shutil.copy2(path, target / path.name)
    print(f"copied the {cast['layer']} cast from {source} to {target}")


def run_dir(root: Path, slug: str) -> None:
    if not slug or "/" in slug or slug.startswith("."):
        fail(f"a slug is one plain path segment, not {slug!r}")
    runs = root / RUNS
    runs.mkdir(parents=True, exist_ok=True)
    ignore = runs / ".gitignore"
    if not ignore.is_file():
        ignore.write_text("*\n")
    target = runs / f"{datetime.date.today().isoformat()}-{slug}"
    if target.exists():
        fail(f"{target} already exists; pick another slug")
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
