#!/usr/bin/env python3
"""Append one event to a peer-planning run's event log.

Usage: log-event.py RUN_DIR EVENT [key=value ...] [key:=json ...]

Writes one JSON object per line to RUN_DIR/events.jsonl: "ts" (UTC, ISO 8601 to the
second), "event", then the given fields. "key=value" stores a string and "key:=value"
parses the value as JSON, so a count or a flag is typed by the caller instead of guessed
from its text: a commit SHA made only of digits must stay a string.

The same record goes to RUN_DIR/events.js as a "peerEvent({...});" line. The monitor page
is a file:// page, where fetch and XMLHttpRequest both fail, but a script tag with a
cache-busting query re-reads the file (measured in agterm 0.34.0). events.jsonl stays the
record; events.js exists only for the page.

The timestamp is taken here, at the moment of the call, because the log exists to show
where a run's time went.

A run.start missing one of the fields references/event-log.md lists for it is refused:
run-records.py tells whether a run has landed from the plan path it carries, and the monitor
shows the plan, branch and executor from it. Refusing the record here, while the orchestrator
can still fix its call, beats a traceback at housekeeping days later.
"""

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

USAGE = "usage: log-event.py RUN_DIR EVENT [key=value ...] [key:=json ...]"

# The fields a later reader cannot do without. The plan path is read against the remote's default
# branch, so it is relative to the repository root.
REQUIRED = {"run.start": ("plan", "tasks", "work_path", "branch", "executor", "session")}


def parse_field(pair: str) -> tuple[str, object]:
    key, sep, raw = pair.partition("=")
    if not sep or not key.rstrip(":"):
        sys.exit(f"log-event: not key=value or key:=json: {pair!r}")
    if key.endswith(":"):
        try:
            return key[:-1], json.loads(raw)
        except json.JSONDecodeError as error:
            sys.exit(f"log-event: {key[:-1]!r} is not JSON ({error}): {raw!r}")
    return key, raw


def main(argv: list[str]) -> None:
    if len(argv) < 3:
        sys.exit(USAGE)
    run_dir = Path(argv[1])
    if not run_dir.is_dir():
        sys.exit(f"log-event: the run directory does not exist: {run_dir}")
    record: dict[str, object] = {
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "event": argv[2],
    }
    for pair in argv[3:]:
        key, value = parse_field(pair)
        if key in record:
            sys.exit(f"log-event: field {key!r} is given twice or is reserved")
        record[key] = value
    missing = [field for field in REQUIRED.get(argv[2], ()) if field not in record]
    if missing:
        sys.exit(f"log-event: {argv[2]} needs {', '.join(missing)}; see references/event-log.md")
    if argv[2] == "run.start" and Path(str(record["plan"])).is_absolute():
        sys.exit(f"log-event: plan is the path from the repository root, not {record['plan']!r}")
    line = json.dumps(record, ensure_ascii=False)
    with (run_dir / "events.jsonl").open("a", encoding="utf-8") as log:
        log.write(line + "\n")
    with (run_dir / "events.js").open("a", encoding="utf-8") as page_feed:
        page_feed.write(f"peerEvent({line});\n")


if __name__ == "__main__":
    main(sys.argv)
