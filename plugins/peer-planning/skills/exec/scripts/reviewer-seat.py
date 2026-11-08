#!/usr/bin/env python3
"""Pick the model for the reviewer seat of a peer-planning run, and say whether the pane must switch.

Usage: reviewer-seat.py [--used-percent N] [--resets N] [--codex-down REASON]

The seat is a second model family, in the owner's order:

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

Prints one JSON object: seat, model, effort, reason, used_percent, resets_left, pane_model,
pane_default, switch, clear_flags. Exit 1 when weekly use cannot be read and was not given, or when
config.toml is not valid TOML.
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
SEATS = {
    "astra": ("gpt-6-astra", "high"),
    "sol": ("gpt-6.1-sol", "xhigh"),
    "opus": ("opus", "high"),
}
HERE = Path(__file__).resolve().parent


def fail(message: str) -> NoReturn:
    print(f"reviewer-seat: {message}", file=sys.stderr)
    sys.exit(1)


def weekly_used_percent() -> float:
    """The newest weekly used_percent any rollout recorded, 0 when that window has reset."""
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
                return 0.0
            return float(primary["used_percent"])
    fail(f"no rollout under {SESSIONS} records weekly rate_limits; pass --used-percent")


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


def resets_left() -> int:
    done = subprocess.run(["bash", str(HERE / "codex-clear.sh"), "--resets"], capture_output=True, text=True)
    if done.returncode != 0:
        fail(f"could not read resets left: {(done.stderr or done.stdout).strip()}")
    return int(done.stdout.strip())


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
    known = {"--used-percent", "--resets", "--codex-down"}
    flags = [a for a in argv if a.startswith("--")]
    if set(flags) - known or len(argv) != 2 * len(flags):
        fail("usage: reviewer-seat.py [--used-percent N] [--resets N] [--codex-down REASON]")
    down = option(argv, "--codex-down")
    given_used = option(argv, "--used-percent")
    given_resets = option(argv, "--resets")
    used = float(given_used) if given_used is not None else (None if down else weekly_used_percent())
    resets = int(given_resets) if given_resets is not None else None

    if down:
        seat, reason = "opus", f"Codex is unavailable: {down}"
    elif used is not None and used >= SOL_AT_PERCENT:
        if resets is None:
            resets = resets_left()
        if resets <= SOL_AT_RESETS:
            seat, reason = "sol", f"weekly use {used:g}% with {resets} reset(s) left"
        else:
            seat, reason = "astra", f"weekly use {used:g}%, but {resets} resets left"
    else:
        seat, reason = "astra", f"weekly use {used:g}%"

    model, effort = SEATS[seat]
    codex = seat != "opus"
    current = pane_model() if codex else ""
    default = configured_default() if codex else ""
    switch = codex and current != f"{model} {effort}"
    reapply = codex and (switch or default != f"{model} {effort}")
    print(json.dumps({
        "seat": seat, "model": model, "effort": effort, "reason": reason,
        "used_percent": used, "resets_left": resets, "pane_model": current,
        "pane_default": default, "switch": switch,
        "clear_flags": f"--model {model} --reasoning {effort}" if reapply else "",
    }))


if __name__ == "__main__":
    main(sys.argv[1:])
