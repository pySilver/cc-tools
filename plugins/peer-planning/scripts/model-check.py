#!/usr/bin/env python3
"""Compare a peer-planning run's models with the recommended ones in the plugin's models.toml.

Usage: model-check.py make|exec [--agent ROLE=DEFINITION ...] [--seat FILE] [--accepted FILE]
                      [--project DIR]

One row per model the run will use:

- the Claude session itself (the planner in make, the orchestrator in exec): the model and effort
  of the newest assistant message in this session's transcript,
  <config dir>/projects/*/<CLAUDE_CODE_SESSION_ID>.jsonl, so a /model or /effort change made
  since the session started counts;
- each agent definition the run will use, given as --agent ROLE=DEFINITION (executor=implementer,
  closer=closer, second-opinion=second-opinion): the `model:` and `effort:` lines of the
  definition whose frontmatter `name:` is DEFINITION (or, when none has it, the file
  <definition>.md) in DIR/.claude/agents/, or else in <config dir>/agents/, the order Claude Code
  loads them in. A definition with no `model:` line inherits the session's model, and
  one with no `effort:` line the session's effort; neither is a recommendation, so the row
  differs;
- Codex's pane, from the file holding the JSON reviewer-seat.py printed, given as --seat: the
  model its status line shows against the seat the picker chose ([seat.make] or [seat.exec], or
  the model the owner kept). An Opus seat has no pane row. A
  pane whose status line could not be read is "unknown unknown", which differs and which the
  picker refuses as a model to keep.

--accepted names a file (exec's progress.md) whose lines `MODEL ACCEPTED <row> <model> <effort>`,
bare or as a list item, with or without backticks, record what the owner already said to keep for this run; a row on an accepted value matches, so a
resumed run asks only about what changed since. The config dir is CLAUDE_CONFIG_DIR, or else
~/.claude.

Prints one JSON object: skill, differs (true when any row differs), rows (row, current,
recommended, source, matches, note). Exit 1 when models.toml is unreadable or an argument is
wrong; a value it cannot read is a row with current "unknown", never an exit.
"""

import json
import os
import re
import subprocess
import sys
import tomllib
from pathlib import Path
from typing import NoReturn

MODELS = Path(__file__).resolve().parents[1] / "models.toml"
CONFIG_DIR = Path(os.environ.get("CLAUDE_CONFIG_DIR") or Path.home() / ".claude")
ACCEPTED = re.compile(r"^\s*(?:[-*]\s+)?`?MODEL ACCEPTED (\S+) (\S+) ([^\s`]+)`?\s*$")


def fail(message: str) -> NoReturn:
    print(f"model-check: {message}", file=sys.stderr)
    sys.exit(1)


def load_table() -> dict:
    try:
        return tomllib.loads(MODELS.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError) as error:
        fail(f"cannot read {MODELS}: {error}")


def recommendation(table: dict, section: str, name: str) -> tuple[list[str], str, str]:
    row = table.get(section, {}).get(name)
    if not isinstance(row, dict):
        fail(f"{MODELS} has no [{section}.{name}]")
    models, effort = row.get("models"), row.get("effort")
    if not isinstance(models, list) or not models or not isinstance(effort, str):
        fail(f"[{section}.{name}] in {MODELS} needs a models list and an effort")
    return models, effort, str(row.get("source", ""))


def session_now() -> tuple[str, str, str]:
    """The session's model and effort from its transcript, and a note when either is unreadable."""
    session = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    if not session:
        return "unknown", "unknown", "CLAUDE_CODE_SESSION_ID is not set"
    transcripts = sorted(CONFIG_DIR.glob(f"projects/*/{session}.jsonl"))
    if not transcripts:
        return "unknown", "unknown", f"no transcript for session {session} under {CONFIG_DIR}/projects"
    lines = transcripts[0].read_text(encoding="utf-8", errors="replace").splitlines()
    for line in reversed(lines):
        if '"assistant"' not in line:
            continue
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        message = entry.get("message") if isinstance(entry, dict) else None
        model = message.get("model") if isinstance(message, dict) else None
        # A synthetic message (an error the harness wrote) records "<synthetic>", not a model.
        if entry.get("type") != "assistant" or not isinstance(model, str) or model.startswith("<"):
            continue
        effort = entry.get("effort")
        if isinstance(effort, str) and effort:
            return model, effort, ""
        return model, "unknown", "the transcript records no effort for this session"
    return "unknown", "unknown", f"no assistant message with a model in {transcripts[0]}"


def frontmatter(path: Path) -> dict[str, str]:
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    fields = {}
    for line in lines[1:]:
        if line.strip() == "---":
            break
        match = re.match(r"^([A-Za-z_-]+):\s*(.*?)\s*$", line)
        if match:
            fields[match.group(1)] = match.group(2).strip("'\"")
    return fields


def project_root(directory: Path) -> Path:
    done = subprocess.run(["git", "-C", str(directory), "rev-parse", "--show-toplevel"],
                          capture_output=True, text=True)
    return Path(done.stdout.strip()) if done.returncode == 0 else directory


def find_definition(directory: Path, definition: str) -> Path | None:
    """The file in directory whose frontmatter name is definition, else <definition>.md."""
    if not directory.is_dir():
        return None
    for path in sorted(directory.glob("*.md")):
        if frontmatter(path).get("name") == definition:
            return path
    path = directory / f"{definition}.md"
    return path if path.is_file() else None


def agent_now(definition: str, project: Path) -> tuple[str, str, str]:
    for directory in (project / ".claude" / "agents", CONFIG_DIR / "agents"):
        path = find_definition(directory, definition)
        if path is not None:
            fields = frontmatter(path)
            return (fields.get("model") or "inherit", fields.get("effort") or "unset", str(path))
    return "unknown", "unknown", f"no definition {definition} in {project}/.claude/agents or {CONFIG_DIR}/agents"


def accepted_values(path: str | None) -> set[tuple[str, str, str]]:
    if path is None:
        return set()
    try:
        text = Path(path).read_text(encoding="utf-8")
    except FileNotFoundError:
        return set()
    except OSError as error:
        fail(f"cannot read --accepted {path}: {error}")
    return {match.groups() for line in text.splitlines() if (match := ACCEPTED.match(line))}


def row(name: str, model: str, effort: str, models: list[str], want_effort: str, source: str,
        note: str, accepted: set[tuple[str, str, str]]) -> dict:
    matches = model in models and effort == want_effort
    if not matches and (name, model, effort) in accepted:
        matches, note = True, "; ".join(filter(None, [note, "the owner kept it for this run"]))
    return {"row": name, "current": f"{model} {effort}", "recommended": f"{' or '.join(models)} {want_effort}",
            "source": source, "matches": matches, "note": note}


def option_values(argv: list[str], name: str) -> list[str]:
    values = []
    for i, arg in enumerate(argv):
        if arg == name:
            if i + 1 >= len(argv):
                fail(f"{name} needs a value")
            values.append(argv[i + 1])
    return values


def main(argv: list[str]) -> None:
    usage = "usage: model-check.py make|exec [--agent ROLE=DEFINITION ...] [--seat FILE] [--accepted FILE] [--project DIR]"
    if not argv or argv[0] not in ("make", "exec"):
        fail(usage)
    skill, rest = argv[0], argv[1:]
    known = {"--agent", "--seat", "--accepted", "--project"}
    flags = [a for i, a in enumerate(rest) if i % 2 == 0]
    if len(rest) % 2 or set(flags) - known:
        fail(usage)
    for name in ("--seat", "--accepted", "--project"):
        if len(option_values(rest, name)) > 1:
            fail(f"{name} is given once")
    table = load_table()
    accepted = accepted_values(next(iter(option_values(rest, "--accepted")), None))
    project = project_root(Path(next(iter(option_values(rest, "--project")), os.getcwd())))

    rows = []
    models, effort, source = recommendation(table, "session", skill)
    model, now_effort, note = session_now()
    rows.append(row("session", model, now_effort, models, effort, source, note, accepted))

    for spec in option_values(rest, "--agent"):
        role, _, definition = spec.partition("=")
        if not role or not definition:
            fail(f"--agent takes ROLE=DEFINITION: got {spec!r}")
        models, effort, source = recommendation(table, "agent", role)
        model, now_effort, where = agent_now(definition, project)
        rows.append(row(f"{role}/{definition}", model, now_effort, models, effort, source, where, accepted))

    for given in option_values(rest, "--seat"):
        try:
            seat = json.loads(Path(given).read_text(encoding="utf-8"))
        except (OSError, ValueError) as error:
            fail(f"--seat takes a file holding the JSON reviewer-seat.py printed: {error}")
        if not isinstance(seat, dict):
            fail(f"--seat {given} holds no JSON object")
        if seat.get("seat") == "opus":
            continue
        pane_model, pane_effort = ((seat.get("pane_model") or "").split() + ["unknown", "unknown"])[:2]
        if seat.get("seat") == "codex":
            source = str(table.get("seat", {}).get(skill, {}).get("source", ""))
        else:
            source = "the owner's keep at setup"
        rows.append(row("codex", pane_model, pane_effort, [str(seat.get("model"))], str(seat.get("effort")),
                        source, f"seat {seat.get('seat')}: {seat.get('reason')}", accepted))

    print(json.dumps({"skill": skill, "differs": not all(r["matches"] for r in rows), "rows": rows}, indent=1))


if __name__ == "__main__":
    main(sys.argv[1:])
