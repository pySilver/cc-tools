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
"""

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

USAGE = "usage: log-event.py RUN_DIR EVENT [key=value ...] [key:=json ...]"


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
    line = json.dumps(record, ensure_ascii=False)
    with (run_dir / "events.jsonl").open("a", encoding="utf-8") as log:
        log.write(line + "\n")
    with (run_dir / "events.js").open("a", encoding="utf-8") as page_feed:
        page_feed.write(f"peerEvent({line});\n")


if __name__ == "__main__":
    main(sys.argv)
