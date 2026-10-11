#!/usr/bin/env python3
"""Open the live monitor of a peer-planning run in agterm.

Usage: open-monitor.py [--follow] [RUN_DIR]
       open-monitor.py --list

With RUN_DIR, opens that run. Without it, finds every run of the repository the caller
stands in, in the main checkout and in every worktree, since an orchestrator keeps its run
directory at the root of whichever checkout it runs in. One run opens directly; several are
offered in agterm's picker, most recent first. --list prints them instead.

The page opens in a session of its own named "<plan-stem> monitor", placed after the
caller's session, because an overlay over the agents' split would hide one of them. A session
already carrying that name is reused. --follow switches to it: a keyboard shortcut wants that,
the exec skill opening it in the background at setup does not.

It runs from a Claude session, which has the AGTERM_* variables, and from an agterm keymap
command, which has AGT_* instead.
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import NoReturn

from run_index import Run, RunIndexError, find_runs, local_time

ASSET = Path(__file__).resolve().parent.parent / "assets" / "monitor.html"


def env(*names: str) -> str:
    for name in names:
        if os.environ.get(name):
            return os.environ[name]
    return ""


SESSION = env("AGT_SESSION_ID", "AGTERM_SESSION_ID")
SOCKET = env("AGT_SOCKET", "AGTERM_SOCKET")
WINDOW = env("AGT_WINDOW_ID", "AGTERM_WINDOW_ID")
START_DIR = env("AGT_SESSION_PWD") or os.getcwd()


def fail(message: str) -> NoReturn:
    print(f"open-monitor: {message}", file=sys.stderr)
    sys.exit(1)


def ctl(*args: str, stdin: str = "", allowed: tuple[int, ...] = (0,)) -> subprocess.CompletedProcess:
    # agtermctl never reads the socket from the environment, and a bare call may reach
    # another agterm instance than the one hosting this session.
    command = ["agtermctl", *args, "--socket", SOCKET]
    done = subprocess.run(command, input=stdin, capture_output=True, text=True)
    if done.returncode not in allowed:
        fail(f"{' '.join(args[:3])} failed: {(done.stderr or done.stdout).strip()}")
    return done


def window_args() -> list[str]:
    return ["--window", WINDOW] if WINDOW else []


def choose(runs: list[Run]) -> Path:
    if len(runs) == 1:
        return runs[0].run_dir
    items = [
        {"id": str(run.run_dir), "label": run.run_dir.name, "subtitle": f"{run.checkout.name} · last event {local_time(run.last_ts)}"}
        for run in runs
    ]
    picked = ctl("pick", "--prompt", "Which plan run?", *window_args(), stdin=json.dumps(items), allowed=(0, 2))
    if picked.returncode == 2:
        sys.exit(0)
    return Path(json.loads(picked.stdout)["id"])


def open_page(run_dir: Path, target: str) -> None:
    ctl("session", "overlay", "open", "--html", str(run_dir / "monitor.html"), "--cwd", str(run_dir), "--js", "--target", target)


def open_monitor(run_dir: Path, follow: bool) -> None:
    if not (run_dir / "events.jsonl").is_file():
        fail(f"{run_dir} holds no events.jsonl; it is not a peer-planning run directory")
    # Refresh the page from the plugin, so an older run gets the current monitor.
    shutil.copyfile(ASSET, run_dir / "monitor.html")
    name = f"{run_dir.name} monitor"
    tree = json.loads(ctl("tree", "--json", *window_args()).stdout)["result"]["tree"]
    existing = [s for ws in tree.get("workspaces", []) for s in ws.get("sessions", []) if s.get("name") == name]
    if existing:
        target = existing[0]["id"]
        if any(page.get("file", "").endswith("/monitor.html") for page in existing[0].get("htmlOverlays", [])):
            ctl("session", "overlay", "reload", "--target", target)
        else:
            open_page(run_dir, target)
    else:
        target = ctl("session", "new", "--cwd", str(run_dir), "--name", name, "--after", SESSION, "--no-select").stdout.strip()
        open_page(run_dir, target)
    if follow:
        ctl("session", "select", "--target", target)
    print(f"{name}: session {target}, run {run_dir}")


def repository_runs() -> list[Run]:
    try:
        return find_runs(START_DIR)
    except RunIndexError as error:
        fail(str(error))


def main(argv: list[str]) -> None:
    flags = [a for a in argv if a.startswith("--")]
    paths = [a for a in argv if not a.startswith("--")]
    unknown = set(flags) - {"--follow", "--list"}
    if unknown or len(paths) > 1:
        fail("usage: open-monitor.py [--follow] [RUN_DIR] | --list")
    if "--list" in flags:
        for run in repository_runs():
            print(f"{local_time(run.last_ts):>14}  {run.run_dir.name:40}  {run.checkout}")
        return
    if not SESSION or not SOCKET:
        fail("not inside an agterm session")
    if not ASSET.is_file():
        fail(f"{ASSET} is missing")
    if paths:
        run_dir = Path(paths[0]).resolve()
    else:
        runs = repository_runs()
        if not runs:
            fail(f"no peer-planning runs in any checkout of the repository at {START_DIR}")
        run_dir = choose(runs)
    open_monitor(run_dir, follow="--follow" in flags)


if __name__ == "__main__":
    main(sys.argv[1:])
