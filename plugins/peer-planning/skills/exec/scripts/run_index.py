"""Find the peer-planning runs of a repository, shared by the scripts that list and act on them.

An orchestrator keeps its run directory at the root of whichever checkout it runs in, so a
repository's runs sit in its main checkout and in every worktree.
"""

import json
import subprocess
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


class RunIndexError(Exception):
    pass


@dataclass(frozen=True)
class Run:
    last_ts: str
    run_dir: Path
    checkout: Path


def last_event_ts(log: Path) -> str:
    for line in reversed(log.read_text(encoding="utf-8").splitlines()):
        if line.strip():
            try:
                return json.loads(line)["ts"]
            except (json.JSONDecodeError, KeyError) as error:
                raise RunIndexError(f"the last line of {log} is not an event") from error
    return ""


def find_runs(start_dir: str) -> list[Run]:
    """Every run of the repository holding start_dir, most recent last event first."""
    listing = subprocess.run(
        ["git", "-C", start_dir, "worktree", "list", "--porcelain"],
        capture_output=True,
        text=True,
    )
    if listing.returncode:
        raise RunIndexError(f"{start_dir} is not inside a git repository")
    runs = []
    for line in listing.stdout.splitlines():
        if line.startswith("worktree "):
            checkout = Path(line[len("worktree ") :])
            for log in checkout.glob(".peer-planning/*/events.jsonl"):
                runs.append(Run(last_event_ts(log), log.parent, checkout))
    return sorted(runs, key=lambda run: run.last_ts, reverse=True)


def local_time(ts: str) -> str:
    if not ts:
        return "no events"
    moment = datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    return moment.astimezone().strftime("%d %b %H:%M")
