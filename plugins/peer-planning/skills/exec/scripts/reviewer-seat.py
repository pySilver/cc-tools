#!/usr/bin/env python3
"""Pick the model for the reviewer seat of a peer-planning run, and say whether the pane must switch.

Usage: reviewer-seat.py make|exec [--codex-down REASON] [--keep "MODEL EFFORT"]

The seat is a second model family, with the models and efforts from the plugin's models.toml:

1. "codex", the skill's own Codex seat: [seat.make] while a plan is argued, [seat.exec] while
   tasks are reviewed.
2. "opus", an Opus subagent at high, when Codex is unavailable: no answer, a stale mailbox thread,
   or CLI errors. The caller decides that and passes --codex-down with its evidence; this script
   cannot see a hung Codex.

--keep "MODEL EFFORT" is the owner's answer at setup to keep the pane's own model for the run
instead of the seat: the seat is then "kept", with that model and effort, at every pick of the run
until Codex is down.

The pane's current model is read from Codex's status line in the right pane when agterm is there;
without it, "switch" is true whenever the seat is a Codex model.

A /clear does not keep a /model switch: the new conversation starts on the model and effort in
Codex's config.toml. So "clear_flags" carries the seat's --model and --reasoning for codex-clear.sh
whenever the seat is a Codex model other than that configured default, or the pane shows another
model, and is empty otherwise; the caller passes it to every clear. "switch" says only that the
pane shows a model other than the seat, which, once every clear carries clear_flags, happens when
the seat changes hands. When config.toml names no model, the default is unknown and clear_flags is
never empty for a Codex seat.

Prints one JSON object: skill, seat, model, effort, reason, pane_model, pane_default, switch,
clear_flags. Exit 1 when models.toml or config.toml is not valid TOML, or on bad arguments.
"""

import json
import os
import re
import subprocess
import sys
import tomllib
from pathlib import Path
from typing import NoReturn

CODEX_HOME = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
HERE = Path(__file__).resolve().parent
MODELS = HERE.parents[2] / "models.toml"
USAGE = 'usage: reviewer-seat.py make|exec [--codex-down REASON] [--keep "MODEL EFFORT"]'


def fail(message: str) -> NoReturn:
    print(f"reviewer-seat: {message}", file=sys.stderr)
    sys.exit(1)


def seats() -> dict[str, tuple[str, str]]:
    """The seats from models.toml, as {"make": ("gpt-6.1-sol", "xhigh"), ...}."""
    try:
        table = tomllib.loads(MODELS.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError) as error:
        fail(f"cannot read {MODELS}: {error}")
    found = {name: (row.get("model"), row.get("effort")) for name, row in table.get("seat", {}).items()}
    for name in ("make", "exec", "opus"):
        model, effort = found.get(name, (None, None))
        if not isinstance(model, str) or not isinstance(effort, str):
            fail(f"{MODELS} has no [seat.{name}] with a model and an effort")
    return found


def pane_model() -> str:
    """The model and effort Codex's status line shows, as "gpt-6.1-sol high", or ""."""
    target = os.environ.get("AGTERM_SESSION_ID", "")
    if not target:
        return ""
    socket = ["--socket", os.environ["AGTERM_SOCKET"]] if os.environ.get("AGTERM_SOCKET") else []
    done = subprocess.run(
        ["agtermctl", "session", "text", "--target", target, "--pane", "right", "--lines", "15", *socket],
        capture_output=True, text=True,
    )
    # The status line reads "GPT-6.1-Sol high · ~/path · Context 2% used · weekly 48% left".
    for line in reversed(done.stdout.splitlines()):
        match = re.match(r"\s*(GPT-[\w.\-]+)\s+(\w+)\s+·", line)
        if match:
            return f"{match.group(1).lower()} {match.group(2)}"
    return ""


def configured_default() -> str:
    """The model and effort a cleared Codex starts on, from config.toml, as "gpt-6-astra high", or ""."""
    path = CODEX_HOME / "config.toml"
    try:
        config = tomllib.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return ""
    except tomllib.TOMLDecodeError as error:
        fail(f"{path} is not valid TOML: {error}")
    model, effort = config.get("model"), config.get("model_reasoning_effort")
    if not isinstance(model, str) or not isinstance(effort, str):
        return ""
    return f"{model} {effort}"


def option(argv: list[str], name: str) -> str | None:
    if name in argv:
        i = argv.index(name)
        if i + 1 >= len(argv):
            fail(f"{name} needs a value")
        return argv[i + 1]
    return None


def main(argv: list[str]) -> None:
    if not argv or argv[0] not in ("make", "exec"):
        fail(USAGE)
    skill, rest = argv[0], argv[1:]
    known = {"--codex-down", "--keep"}
    flags = [a for a in rest if a.startswith("--")]
    if set(flags) - known or len(rest) != 2 * len(flags):
        fail(USAGE)
    down = option(rest, "--codex-down")
    keep = option(rest, "--keep")
    if keep is not None and (len(keep.split()) != 2 or "unknown" in keep.split()):
        fail(f'--keep takes "MODEL EFFORT", as the pane shows it: got {keep!r}')
    table = seats()

    if down:
        seat, reason = "opus", f"Codex is unavailable: {down}"
        model, effort = table["opus"]
    elif keep is not None:
        seat, reason = "kept", "the owner kept the pane model for this run"
        model, effort = keep.split()
    else:
        seat, reason = "codex", f"the {skill} seat in models.toml"
        model, effort = table[skill]

    codex = seat != "opus"
    current = pane_model() if codex else ""
    default = configured_default() if codex else ""
    switch = codex and current != f"{model} {effort}"
    reapply = codex and (switch or default != f"{model} {effort}")
    print(json.dumps({
        "skill": skill, "seat": seat, "model": model, "effort": effort, "reason": reason,
        "pane_model": current, "pane_default": default, "switch": switch,
        "clear_flags": f"--model {model} --reasoning {effort}" if reapply else "",
    }))


if __name__ == "__main__":
    main(sys.argv[1:])
