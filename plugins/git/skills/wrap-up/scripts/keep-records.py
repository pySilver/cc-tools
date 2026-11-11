#!/usr/bin/env python3
"""Keep a landed branch's run record and review results in the repository's workflow ledger.

Usage: keep-records.py inspect --main MAIN --branch BRANCH [--worktree WORKTREE] [--name NAME]
                               [--plan-stem STEM]
       keep-records.py copy    (the same arguments)

Wrap-up deletes a branch's peer-planning run record and its revmux tasks, and nothing else holds
what later analysis of the workflow reads. copy puts those small files first into
<git common dir>/workflow-ledger/, which is outside git and shared by every worktree, so it
outlives both:

  runs/<plan-stem>/events.jsonl, progress.md
  revmux/<task-id>/<round>/manifest.json, findings.json, stages/

The revmux half is laid out as a tasks root, so revmux's analyze-corpus.py reads it with
--tasks-dir <ledger>/revmux. A run's msgs/ and a round's agents/, input/ and prompts/ hold nearly
all the bytes and nothing that analysis reads, so they are not kept.

A run record is .peer-planning/<plan-stem>/ holding events.jsonl, in MAIN or in WORKTREE; a
directory with msgs/ alone is make's argument, not a run. A revmux task belongs to the branch when
its task.md front matter says branch: BRANCH, or its id is BRANCH with every / made -, the plan
stem, or plan-<NAME>. A round is finished when its manifest.json is not empty: revmux creates the
file empty when a review claims the round and fills it when the review ends, so a round without
it, or with it empty, was never reviewed and is skipped.

Each run record and round goes under its own name. When that name already holds other files (MAIN
and WORKTREE both hold the round, or an earlier branch of the same name kept one), it goes under
<name>~<the first 8 hex digits of the sha256 of its kept files> instead, and its entry carries
"renamed_from". MAIN is copied before WORKTREE, so MAIN's copy keeps the plain name. The same
files always land in the same place, so a second copy writes nothing. exec's run-records.py keeps
a run record by the same rule, so either may run first. Each one is written into a temporary
directory beside its place and renamed into it, so a failure leaves nothing half-kept.

Both commands print one JSON object. inspect has "status": "found" with "ledger", "runs" (where
each run record is and which of its files would be kept) and "tasks" (each matching task: its
tree, id, path, what matched it, its finished rounds, the unfinished ones by name, and its size).
copy has "status" one of:
  kept    every run record and finished round is in the ledger; each entry's "result" is
          "copied" or "already kept"
  failed  at least one could not be copied; its entry's "result" is "failed" with "error", and
          the command exits 1
Either command answers "status": "error" with "detail", and exits 1, when MAIN is not a git
checkout or a record cannot be read.
"""

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

LEDGER = "workflow-ledger"
RUN_FILES = ("events.jsonl", "progress.md")
ROUND_FILES = ("manifest.json", "findings.json")
ROUND_STAGES = "stages"


class RecordError(Exception):
    pass


@dataclass(frozen=True)
class Source:
    tree: str
    path: Path
    files: tuple[str, ...]


@dataclass(frozen=True)
class Task:
    tree: str
    path: Path
    matched_by: str
    finished: tuple[Source, ...]
    unfinished: tuple[str, ...]


def ledger_dir(main: Path) -> Path:
    found = subprocess.run(
        ["git", "-C", str(main), "rev-parse", "--path-format=absolute", "--git-common-dir"],
        capture_output=True,
        text=True,
    )
    if found.returncode:
        raise RecordError(f"{main} is not a git checkout: {found.stderr.strip()}")
    return Path(found.stdout.strip()) / LEDGER


def trees(main: Path, worktree: Path | None) -> list[tuple[str, Path]]:
    return [("main", main)] + ([("worktree", worktree)] if worktree else [])


def run_sources(main: Path, worktree: Path | None, stem: str | None) -> list[Source]:
    if not stem:
        return []
    found = []
    for tree, root in trees(main, worktree):
        run_dir = root / ".peer-planning" / stem
        if (run_dir / "events.jsonl").is_file():
            files = tuple(name for name in RUN_FILES if (run_dir / name).is_file())
            found.append(Source(tree, run_dir, files))
    return found


def front_matter_branch(task_md: Path) -> str | None:
    if not task_md.is_file():
        return None
    lines = task_md.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    for line in lines[1:]:
        if line.strip() == "---":
            break
        key, colon, value = line.partition(":")
        if colon and key == "branch":
            return value.split(" #", 1)[0].strip().strip("'\"") or None
    return None


def matched_by(task: Path, branch: str, name: str | None, stem: str | None) -> str | None:
    if front_matter_branch(task / "task.md") == branch:
        return "branch"
    if task.name == branch.replace("/", "-"):
        return "branch slug"
    if stem and task.name == stem:
        return "plan stem"
    if name and task.name == f"plan-{name}":
        return "plan-NAME"
    return None


def round_files(round_dir: Path) -> tuple[str, ...]:
    files = [name for name in ROUND_FILES if (round_dir / name).is_file()]
    stages = round_dir / ROUND_STAGES
    if stages.is_dir():
        files += sorted(path.relative_to(round_dir).as_posix() for path in stages.rglob("*") if path.is_file())
    return tuple(files)


def finished(round_dir: Path) -> bool:
    manifest = round_dir / "manifest.json"
    return manifest.is_file() and manifest.stat().st_size > 0


def tasks(main: Path, worktree: Path | None, branch: str, name: str | None, stem: str | None) -> list[Task]:
    found = []
    for tree, root in trees(main, worktree):
        tasks_root = root / ".revmux" / "tasks"
        if not tasks_root.is_dir():
            continue
        for task in sorted(path for path in tasks_root.iterdir() if path.is_dir()):
            how = matched_by(task, branch, name, stem)
            if how is None:
                continue
            rounds = sorted(path for path in task.iterdir() if path.is_dir())
            found.append(
                Task(
                    tree=tree,
                    path=task,
                    matched_by=how,
                    finished=tuple(Source(tree, r, round_files(r)) for r in rounds if finished(r)),
                    unfinished=tuple(r.name for r in rounds if not finished(r)),
                )
            )
    return found


def read(root: Path, names: tuple[str, ...]) -> dict[str, bytes]:
    return {name: (root / name).read_bytes() for name in names}


def digest(files: dict[str, bytes]) -> str:
    h = hashlib.sha256()
    for name in sorted(files):
        data = files[name]
        h.update(f"{name}\0{len(data)}\0".encode())
        h.update(data)
    return h.hexdigest()


def held(place: Path) -> dict[str, bytes] | None:
    if not place.exists():
        return None
    if not place.is_dir():
        return {}
    return {path.relative_to(place).as_posix(): path.read_bytes() for path in place.rglob("*") if path.is_file()}


def write(files: dict[str, bytes], place: Path) -> None:
    place.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix=f".{place.name}.", dir=place.parent))
    try:
        for name, data in files.items():
            target = staging / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        staging.rename(place)
    except BaseException:
        shutil.rmtree(staging)
        raise


def keep(source: Source, parent: Path, name: str) -> dict[str, object]:
    """Copy one run record or round into parent/name, or the name its digest gives."""
    entry: dict[str, object] = {"tree": source.tree, "source": str(source.path)}
    try:
        files = read(source.path, source.files)
        place = parent / name
        current = held(place)
        if current is not None and current != files:
            entry["renamed_from"] = str(place)
            place = parent / f"{name}~{digest(files)[:8]}"
            current = held(place)
            if current is not None and current != files:
                raise RecordError(f"{place} holds other files under this record's own digest; nothing overwritten")
        entry["ledger"] = str(place)
        if current == files:
            entry["result"] = "already kept"
        else:
            write(files, place)
            entry["result"] = "copied"
    except (OSError, RecordError) as error:
        entry.update(result="failed", error=str(error))
    return entry


def size_mb(path: Path) -> float:
    return round(sum(p.stat().st_size for p in path.rglob("*") if p.is_file()) / 1_000_000, 1)


def inspect(ledger: Path, runs: list[Source], found: list[Task]) -> int:
    print(
        json.dumps(
            {
                "status": "found",
                "ledger": str(ledger),
                "runs": [{"tree": r.tree, "source": str(r.path), "files": list(r.files)} for r in runs],
                "tasks": [
                    {
                        "tree": t.tree,
                        "id": t.path.name,
                        "path": str(t.path),
                        "matched_by": t.matched_by,
                        "rounds": len(t.finished),
                        "unfinished": list(t.unfinished),
                        "size_mb": size_mb(t.path),
                    }
                    for t in found
                ],
            }
        )
    )
    return 0


def copy(ledger: Path, runs: list[Source], found: list[Task]) -> int:
    kept_runs = [keep(run, ledger / "runs", run.path.name) for run in runs]
    kept_rounds = []
    for task in found:
        for rnd in task.finished:
            entry = keep(rnd, ledger / "revmux" / task.path.name, rnd.path.name)
            kept_rounds.append({"task": task.path.name, "round": rnd.path.name, **entry})
    skipped = [
        {"tree": t.tree, "task": t.path.name, "round": name, "reason": "unfinished: manifest.json missing or empty"}
        for t in found
        for name in t.unfinished
    ]
    failed = any(entry["result"] == "failed" for entry in kept_runs + kept_rounds)
    print(
        json.dumps(
            {
                "status": "failed" if failed else "kept",
                "ledger": str(ledger),
                "runs": kept_runs,
                "rounds": kept_rounds,
                "skipped": skipped,
            }
        )
    )
    return 1 if failed else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("command", choices=("inspect", "copy"))
    parser.add_argument("--main", required=True, type=Path)
    parser.add_argument("--worktree", type=Path)
    parser.add_argument("--branch", required=True)
    parser.add_argument("--name")
    parser.add_argument("--plan-stem")
    args = parser.parse_args()

    stem = args.plan_stem
    try:
        if stem is not None and (not stem or "/" in stem or stem in (".", "..")):
            raise RecordError(f"plan stem {stem!r} is not a file name")
        ledger = ledger_dir(args.main)
        runs = run_sources(args.main, args.worktree, stem)
        found = tasks(args.main, args.worktree, args.branch, args.name, stem)
    except (OSError, RecordError) as error:
        print(json.dumps({"status": "error", "detail": str(error)}))
        return 1
    if args.command == "inspect":
        return inspect(ledger, runs, found)
    return copy(ledger, runs, found)


if __name__ == "__main__":
    sys.exit(main())
