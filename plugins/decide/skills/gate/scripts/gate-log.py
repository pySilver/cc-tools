#!/usr/bin/env python3
"""The question gate's shadow log: the judge's verdict on each question beside the user's answer.

Usage: gate-log.py ask --id ID --question TEXT --verdict VERDICT --cite TEXT [--why TEXT] [--repo DIR]
       gate-log.py answer --id ID --answer TEXT [--ruling SLUG] [--repo DIR]
       gate-log.py report [--json] [--repo DIR]

`ask` records the judge's verdict when a question is about to reach the user; `answer` records what
the user said, and the ruling file it produced when the durable check said so. `report` lists every
question with the verdict and the answer side by side, then counts how often the judge would have
been right to act alone, which is what the user reads before deciding whether the judge may.

Verdicts: decided (a recorded ruling answers it; cite the file and heading), checkable (a probe, a
test or a rule answers it; cite which), cheap (reversible and cheap, so an agent may decide; cite
why), held (only the user can answer).

The log is the repository's git directory, decide-gate.jsonl: never committed, shared by every
worktree, and kept when a worktree and its run records are removed, so a week of comparisons
outlives the plans that produced them.
"""

# The macOS system python3 (3.9) may run this; it needs this for `str | None`.
from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

VERDICTS = ("decided", "checkable", "cheap", "held")


def fail(message: str) -> None:
    print(f"gate-log: {message}", file=sys.stderr)
    sys.exit(1)


def log_path(repo: Path) -> Path:
    done = subprocess.run(["git", "-C", str(repo), "rev-parse", "--git-common-dir"], capture_output=True, text=True)
    if done.returncode:
        fail(f"{repo} is not inside a git repository")
    common = Path(done.stdout.strip())
    return (common if common.is_absolute() else repo / common).resolve() / "decide-gate.jsonl"


def options(argv: list[str], allowed: set[str]) -> dict[str, str]:
    found: dict[str, str] = {}
    i = 0
    while i < len(argv):
        name = argv[i]
        if name == "--json":
            found["json"] = "1"
            i += 1
            continue
        if name not in allowed or i + 1 >= len(argv):
            fail(f"unexpected argument {name!r}")
        found[name[2:]] = argv[i + 1]
        i += 2
    return found


def read(path: Path) -> list[dict]:
    if not path.is_file():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def append(path: Path, record: dict) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False) + "\n")


def report(entries: list[dict], as_json: bool) -> None:
    asked: dict[str, dict] = {}
    for entry in entries:
        slot = asked.setdefault(entry["id"], {"id": entry["id"]})
        slot.update({k: v for k, v in entry.items() if k not in ("kind", "ts")})
        slot.setdefault("asked_at" if entry["kind"] == "ask" else "answered_at", entry["ts"])
    rows = list(asked.values())
    if as_json:
        print(json.dumps(rows, indent=1, ensure_ascii=False))
        return
    for row in rows:
        print(f"[{row.get('verdict', '?')}] {row.get('question', '')}")
        print(f"    judge: {row.get('cite', '')}")
        print(f"    owner: {row.get('answer', '(not answered yet)')}" + (f"  -> ruling {row['ruling']}" if row.get("ruling") else ""))
    answered = [r for r in rows if "answer" in r]
    acting = [r for r in answered if r.get("verdict") != "held"]
    print(f"\n{len(rows)} questions, {len(answered)} answered. The judge would have acted alone on {len(acting)} of the answered ones;")
    print("read each of those against the owner's answer to judge whether it should have.")


def main(argv: list[str]) -> None:
    if not argv or argv[0] not in {"ask", "answer", "report"}:
        fail("usage: gate-log.py ask|answer|report ...")
    command, rest = argv[0], argv[1:]
    repo = Path.cwd()
    if "--repo" in rest:
        i = rest.index("--repo")
        repo = Path(rest[i + 1])
        del rest[i : i + 2]
    path = log_path(repo)
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    if command == "ask":
        opts = options(rest, {"--id", "--question", "--verdict", "--cite", "--why"})
        if opts.get("verdict") not in VERDICTS or not opts.get("id") or not opts.get("question"):
            fail(f"ask needs --id, --question and --verdict one of {', '.join(VERDICTS)}")
        append(path, {"kind": "ask", "ts": now, **opts})
    elif command == "answer":
        opts = options(rest, {"--id", "--answer", "--ruling"})
        if not opts.get("id") or "answer" not in opts:
            fail("answer needs --id and --answer")
        if not any(e["id"] == opts["id"] and e["kind"] == "ask" for e in read(path)):
            fail(f"no question {opts['id']!r} was logged")
        append(path, {"kind": "answer", "ts": now, **opts})
    else:
        report(read(path), as_json="json" in options(rest, set()))


if __name__ == "__main__":
    main(sys.argv[1:])
