#!/usr/bin/env python3
"""List the peer-planning runs whose branch has landed, and remove one run's record.

Usage: run-records.py --landed
       run-records.py --remove RUN_DIR

A run has landed when its log holds run.end and its plan has been archived on the remote's
default branch: the plan file is gone from the path run.start logged and present under
completed/ beside it. Branch ancestry cannot tell, because finalize squashes the branch into
one new commit. A run without run.end is never offered, since it may be paused, not finished.

--landed prints one tab-separated line per landed run: the run directory, its size, the
commit that archived the plan, and the plan's file name. It fetches nothing; the orchestrator
reads origin as it stands. A finished run whose run.start carries no repository-relative plan
path cannot be told landed; it is named on stderr and left out, and the other runs are still
listed.

--remove deletes a run directory only when it is a landed run's, then closes the run's
"<plan-stem> monitor" agterm session if one is open. It refuses any other path.
"""

import json
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import NoReturn

from run_index import Run, RunIndexError, find_runs

START_DIR = os.environ.get("AGT_SESSION_PWD") or os.getcwd()
SOCKET = os.environ.get("AGT_SOCKET") or os.environ.get("AGTERM_SOCKET") or ""


def warn(message: str) -> None:
    print(f"run-records: {message}", file=sys.stderr)


def fail(message: str) -> NoReturn:
    warn(message)
    sys.exit(1)


@dataclass(frozen=True)
class LandedRun:
    run: Run
    archived_by: str
    plan_name: str


def git(checkout: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["git", "-C", str(checkout), *args], capture_output=True, text=True)


def default_ref(checkout: Path) -> str:
    head = git(checkout, "symbolic-ref", "--short", "refs/remotes/origin/HEAD")
    if head.returncode:
        fail(f"{checkout} has no origin/HEAD; run `git remote set-head origin --auto` there")
    return head.stdout.strip()


def events(run_dir: Path) -> list[dict]:
    lines = (run_dir / "events.jsonl").read_text(encoding="utf-8").splitlines()
    return [json.loads(line) for line in lines if line.strip()]


def exists_at(checkout: Path, ref: str, path: str) -> bool:
    return git(checkout, "cat-file", "-e", f"{ref}:{path}").returncode == 0


def landed(run: Run, ref: str) -> LandedRun | None:
    log = events(run.run_dir)
    start = next((event for event in log if event.get("event") == "run.start"), None)
    if start is None or not any(event.get("event") == "run.end" for event in log):
        return None
    plan_path = start.get("plan")
    if not isinstance(plan_path, str) or not plan_path or Path(plan_path).is_absolute():
        warn(f"{run.run_dir}: its run.start names no repository-relative plan, so whether it landed cannot be told; skipped")
        return None
    plan = Path(plan_path)
    archived = (plan.parent / "completed" / plan.name).as_posix()
    if exists_at(run.checkout, ref, plan.as_posix()) or not exists_at(run.checkout, ref, archived):
        return None
    commit = git(run.checkout, "log", "-1", "--format=%h", ref, "--", archived).stdout.strip()
    return LandedRun(run=run, archived_by=commit, plan_name=plan.name)


def landed_runs() -> list[LandedRun]:
    try:
        runs = find_runs(START_DIR)
    except RunIndexError as error:
        fail(str(error))
    if not runs:
        return []
    ref = default_ref(runs[0].checkout)
    return [found for run in runs if (found := landed(run, ref))]


def size(run_dir: Path) -> str:
    total = sum(path.stat().st_size for path in run_dir.rglob("*") if path.is_file())
    return f"{total / 1024:.0f} KiB"


def close_monitor(run_dir: Path) -> str:
    if not SOCKET:
        return "no agterm session to look in"
    tree = subprocess.run(["agtermctl", "tree", "--json", "--socket", SOCKET], capture_output=True, text=True)
    if tree.returncode:
        return f"monitor session not checked: {(tree.stderr or tree.stdout).strip()}"
    name = f"{run_dir.name} monitor"
    workspaces = json.loads(tree.stdout)["result"]["tree"].get("workspaces", [])
    targets = [s["id"] for ws in workspaces for s in ws.get("sessions", []) if s.get("name") == name]
    if not targets:
        return "no monitor session open"
    closed = subprocess.run(
        ["agtermctl", "session", "close", *[arg for t in targets for arg in ("--target", t)], "--socket", SOCKET],
        capture_output=True,
        text=True,
    )
    if closed.returncode:
        return f"monitor session not closed: {(closed.stderr or closed.stdout).strip()}"
    return f"closed the {name!r} session"


def remove(path: str) -> None:
    run_dir = Path(path).resolve()
    match = next((found for found in landed_runs() if found.run.run_dir.resolve() == run_dir), None)
    if match is None:
        fail(f"{run_dir} is not a landed peer-planning run; nothing removed")
    monitor = close_monitor(run_dir)
    shutil.rmtree(run_dir)
    print(f"removed {run_dir}; {monitor}")


def main(argv: list[str]) -> None:
    if argv == ["--landed"]:
        for found in landed_runs():
            print(f"{found.run.run_dir}\t{size(found.run.run_dir)}\t{found.archived_by}\t{found.plan_name}")
        return
    if len(argv) == 2 and argv[0] == "--remove":
        remove(argv[1])
        return
    fail("usage: run-records.py --landed | --remove RUN_DIR")


if __name__ == "__main__":
    main(sys.argv[1:])
