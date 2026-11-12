#!/usr/bin/env python3
"""Pick the model for the reviewer seat of a peer-planning run, and say whether the pane must switch.

Usage: reviewer-seat.py [--used-percent N] [--resets N] [--codex-down REASON] [--keep "MODEL EFFORT"]

The seat is a second model family, in the owner's order, with the models and efforts from the
plugin's models.toml:

1. gpt-6-astra at high, the default.
2. gpt-6.1-sol at xhigh, once the OpenAI week is at least 80% used and at most one usage reset
   is left, so the remaining week goes further on the model whose accuracy rises with effort.
3. An Opus subagent at high, when Codex is unavailable: no answer, a stale mailbox thread, or
   CLI errors. The caller decides that and passes --codex-down with its evidence; this script
   cannot see a hung Codex.

Weekly use comes from the newest Codex rollout under ~/.codex/sessions that records
rate_limits for the 10080-minute window. A record whose window has already reset counts as 0.
Resets left are read only when use is at 80 or more, through codex-clear.sh --resets, which opens
Codex's /usage screen, reads the count and leaves with Esc; below 80 the count changes nothing.
When either cannot be read (Codex behind a proxy records no rate_limits, and its /usage then asks
for a ChatGPT sign-in), the seat is astra and "unmeasured" says why, for the caller to tell the
owner: the owner's ruling of 2026-11-12, "try to read the usage and fallback to" astra.

--keep "MODEL EFFORT" is the owner's answer at setup to keep the pane's own model for the run
instead of the seat: the seat is then "kept", with that model and effort, at every pick of the run
until Codex is down.

--used-percent and --resets replace the measurement, for a dry run. The pane's current model is
read from Codex's status line in the right pane when agterm is there; without it, "switch" is
true whenever the seat is a Codex model.

A /clear does not keep a /model switch: the new conversation starts on the model and effort in
Codex's config.toml. So "clear_flags" carries the seat's --model and --reasoning for codex-clear.sh
whenever the seat is a Codex model other than that configured default, or the pane shows another
model, and is empty otherwise; the caller passes it to every clear. "switch" says only that the
pane shows a model other than the seat, which, once every clear carries clear_flags, happens when
the seat changes hands. When config.toml names no model, the default is unknown and clear_flags is
never empty for a Codex seat.

Prints one JSON object: seat, model, effort, reason, used_percent, resets_left, unmeasured,
pane_model, pane_default, switch, clear_flags. Exit 1 when models.toml or config.toml is not valid
TOML, or on bad arguments.
"""

import json
import os
import re
import subprocess
import sys
import time
import tomllib
from pathlib import Path
from typing import NoReturn

CODEX_HOME = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
SESSIONS = CODEX_HOME / "sessions"
WEEK_MINUTES = 10080
SOL_AT_PERCENT = 80
SOL_AT_RESETS = 1
HERE = Path(__file__).resolve().parent
MODELS = HERE.parents[2] / "models.toml"


def fail(message: str) -> NoReturn:
    print(f"reviewer-seat: {message}", file=sys.stderr)
    sys.exit(1)


def seats() -> dict[str, tuple[str, str]]:
    """The Codex seats from models.toml, as {"astra": ("gpt-6-astra", "high"), ...}."""
    try:
        table = tomllib.loads(MODELS.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError) as error:
        fail(f"cannot read {MODELS}: {error}")
    found = {name: (row.get("model"), row.get("effort")) for name, row in table.get("seat", {}).items()}
    for name in ("astra", "sol", "opus"):
        model, effort = found.get(name, (None, None))
        if not isinstance(model, str) or not isinstance(effort, str):
            fail(f"{MODELS} has no [seat.{name}] with a model and an effort")
    return found


def weekly_used_percent() -> tuple[float | None, str]:
    """The newest weekly used_percent any rollout recorded, 0 when that window has reset.

    None, with the reason, when none of the newest rollouts records it."""
    rollouts = sorted(SESSIONS.rglob("rollout-*.jsonl"), key=lambda p: p.stat().st_mtime, reverse=True)
    for rollout in rollouts[:20]:
        for line in reversed(rollout.read_text(encoding="utf-8", errors="replace").splitlines()):
            if '"rate_limits"' not in line:
                continue
            try:
                limits = json.loads(line)
            except ValueError:
                continue
            found = find_limits(limits)
            if found is None:
                continue
            primary = found.get("primary") or {}
            if primary.get("window_minutes") != WEEK_MINUTES or "used_percent" not in primary:
                continue
            resets_at = primary.get("resets_at")
            if isinstance(resets_at, (int, float)) and resets_at < time.time():
                return 0.0, ""
            return float(primary["used_percent"]), ""
    return None, f"none of the newest {min(len(rollouts), 20)} rollouts under {SESSIONS} records weekly rate_limits"


def find_limits(node: object) -> dict | None:
    if isinstance(node, dict):
        if isinstance(node.get("rate_limits"), dict):
            return node["rate_limits"]
        for value in node.values():
            hit = find_limits(value)
            if hit is not None:
                return hit
    if isinstance(node, list):
        for value in node:
            hit = find_limits(value)
            if hit is not None:
                return hit
    return None


def resets_left() -> tuple[int | None, str]:
    """The usage resets left, from Codex's /usage screen; None, with the reason, when unreadable."""
    done = subprocess.run(["bash", str(HERE / "codex-clear.sh"), "--resets"], capture_output=True, text=True)
    if done.returncode != 0 or not done.stdout.strip().isdigit():
        return None, f"resets left unreadable: {(done.stderr or done.stdout).strip()}"
    return int(done.stdout.strip()), ""


def pane_model() -> str:
    """The model and effort Codex's status line shows, as "gpt-6-astra high", or ""."""
    target = os.environ.get("AGTERM_SESSION_ID", "")
    if not target:
        return ""
    socket = ["--socket", os.environ["AGTERM_SOCKET"]] if os.environ.get("AGTERM_SOCKET") else []
    done = subprocess.run(
        ["agtermctl", "session", "text", "--target", target, "--pane", "right", "--lines", "15", *socket],
        capture_output=True, text=True,
    )
    # The status line reads "GPT-6-Astra high · ~/path · Context 2% used · weekly 48% left".
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
    known = {"--used-percent", "--resets", "--codex-down", "--keep"}
    flags = [a for a in argv if a.startswith("--")]
    if set(flags) - known or len(argv) != 2 * len(flags):
        fail('usage: reviewer-seat.py [--used-percent N] [--resets N] [--codex-down REASON] [--keep "MODEL EFFORT"]')
    down = option(argv, "--codex-down")
    keep = option(argv, "--keep")
    if keep is not None and (len(keep.split()) != 2 or "unknown" in keep.split()):
        fail(f'--keep takes "MODEL EFFORT", as the pane shows it: got {keep!r}')
    given_used = option(argv, "--used-percent")
    given_resets = option(argv, "--resets")
    table = seats()
    used = float(given_used) if given_used is not None else None
    resets = int(given_resets) if given_resets is not None else None
    unmeasured = None

    if down:
        seat, reason = "opus", f"Codex is unavailable: {down}"
    elif keep is not None:
        seat, reason = "kept", "the owner kept the pane model for this run"
    else:
        if used is None:
            used, why = weekly_used_percent()
            unmeasured = why or None
        if used is None:
            seat, reason = "astra", f"weekly use unknown: {unmeasured}"
        elif used >= SOL_AT_PERCENT:
            if resets is None:
                resets, why = resets_left()
                unmeasured = why or None
            if resets is None:
                seat, reason = "astra", f"weekly use {used:g}%, {unmeasured}"
            elif resets <= SOL_AT_RESETS:
                seat, reason = "sol", f"weekly use {used:g}% with {resets} reset(s) left"
            else:
                seat, reason = "astra", f"weekly use {used:g}%, but {resets} resets left"
        else:
            seat, reason = "astra", f"weekly use {used:g}%"

    model, effort = keep.split() if seat == "kept" else table[seat]
    codex = seat != "opus"
    current = pane_model() if codex else ""
    default = configured_default() if codex else ""
    switch = codex and current != f"{model} {effort}"
    reapply = codex and (switch or default != f"{model} {effort}")
    print(json.dumps({
        "seat": seat, "model": model, "effort": effort, "reason": reason,
        "used_percent": used, "resets_left": resets, "unmeasured": unmeasured, "pane_model": current,
        "pane_default": default, "switch": switch,
        "clear_flags": f"--model {model} --reasoning {effort}" if reapply else "",
    }))


if __name__ == "__main__":
    main(sys.argv[1:])
