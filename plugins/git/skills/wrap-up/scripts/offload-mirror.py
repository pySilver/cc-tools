#!/usr/bin/env python3
"""Find and remove a worktree's mirror on mybaze's second test machine.

Usage: offload-mirror.py inspect DB_NAME [--timeout SECONDS]
       offload-mirror.py remove DB_NAME [--timeout SECONDS]

DB_NAME is DATABASES.default.NAME from the worktree's .envs/.override.yaml, without the test_
prefix pytest adds. A pytest the suite lock holds back can run on the machine MYBAZE_SUITE_REMOTE
names: it rsyncs the checkout to ~/mybaze-offload/<remote name>/ there and creates
test_<remote name> and test_<remote name>_gw<N> in that machine's mybaze.postgres-test
container. Nothing else removes them. The remote name mirrors remote_name() in mybaze's
mybaze/core/testing/offload.py; the layout is docs/runbooks/dev-environment.md, "A second
machine for queued runs".

Both commands print one JSON object. "status" is one of:
  skipped      MYBAZE_SUITE_REMOTE is unset or empty; nothing was contacted
  unreachable  ssh failed, timed out, or asked for a browser login check, which is never opened
  busy         a pytest or remote_launcher has its working directory in the mirror; nothing touched
  absent       no mirror directory and no databases (inspect only)
  present      the mirror directory or databases exist (inspect only)
  removed      remove ran; "dropped" lists the databases dropped, "failed" any that were not
  error        the database list could not be read; "detail" says why

Every ssh call runs with BatchMode=yes and ConnectTimeout=5 under a hard subprocess timeout,
so a login that waits on a prompt cannot hang the caller. The mirror path is derived and
checked against its exact form before any command uses it, and databases are dropped only by
exact name. docker compose is never run on the second machine: postgres-test is a standing
service there.
"""

import argparse
import hashlib
import json
import os
import re
import shlex
import subprocess
import sys

REMOTE_ENV = "MYBAZE_SUITE_REMOTE"
REMOTE_ROOT = "mybaze-offload"
CONTAINER = "mybaze.postgres-test"
SSH_OPTIONS = ("-o", "BatchMode=yes", "-o", "ConnectTimeout=5")
REMOTE_NAME = re.compile(r"^mybaze_offload_[0-9a-f]{12}$")
BROWSER_CHECK = "login.tailscale.com"


def remote_name(db_name: str) -> str:
    """The checkout's name on the second machine, as mybaze's offload.remote_name has it."""
    return f"mybaze_offload_{hashlib.sha256(db_name.encode()).hexdigest()[:12]}"


def _busy_check(name: str) -> str:
    # A process counts when its working directory is the mirror or below it. /proc serves a
    # Linux host; lsof serves one without /proc.
    return f"""
mirror="$HOME/{REMOTE_ROOT}/{name}"
busy=0
for p in $(pgrep -f 'pytest|mybaze[.]core[.]testing[.]remote_launcher' 2>/dev/null); do
  c=$(readlink "/proc/$p/cwd" 2>/dev/null || lsof -a -d cwd -p "$p" -Fn 2>/dev/null | sed -n 's/^n//p')
  case "$c" in
    "$mirror"|"$mirror"/*) echo "BUSY $p $c"; busy=1;;
  esac
done
"""


def _db_list(name: str) -> str:
    return f"""
dbs=$(docker exec {CONTAINER} psql -U postgres -Atc 'select datname from pg_database' 2>&1) \\
  || {{ echo "DBERR $(printf '%s' "$dbs" | head -n 1)"; echo DONE; exit 0; }}
dbs=$(printf '%s\\n' "$dbs" | grep -E '^test_{name}(_gw[0-9]+)?$')
"""


def inspect_script(name: str) -> str:
    return (
        _busy_check(name)
        + '[ -d "$mirror" ] && echo "DIR yes" || echo "DIR no"\n'
        + _db_list(name)
        + 'for db in $dbs; do echo "DB $db"; done\necho DONE\n'
    )


def remove_script(name: str) -> str:
    return (
        _busy_check(name)
        + 'if [ "$busy" = 1 ]; then echo DONE; exit 0; fi\n'
        + 'if [ -d "$mirror" ]; then rm -rf -- "$mirror" && echo "DIR removed" '
        + '|| echo "DIR failed"; else echo "DIR absent"; fi\n'
        + _db_list(name)
        + "for db in $dbs; do\n"
        + f'  if docker exec {CONTAINER} dropdb -U postgres --if-exists --force "$db"; '
        + 'then echo "DROPPED $db"; else echo "DROPFAIL $db"; fi\n'
        + "done\necho DONE\n"
    )


def run_remote(target: str, script: str, timeout: float) -> tuple[str | None, list[str]]:
    """Run the script under bash -lc; return (problem, output lines)."""
    command = ["ssh", *SSH_OPTIONS, target, "bash -lc " + shlex.quote(script)]
    try:
        done = subprocess.run(
            command, capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL
        )
    except subprocess.TimeoutExpired as exc:
        seen = _text(exc.stdout) + _text(exc.stderr)
        if BROWSER_CHECK in seen:
            return "ssh asked for a browser login check, which was not opened", []
        return f"ssh did not finish within {timeout:g}s", []
    output = done.stdout + done.stderr
    if BROWSER_CHECK in output:
        return "ssh asked for a browser login check, which was not opened", []
    lines = done.stdout.splitlines()
    if done.returncode != 0 or "DONE" not in lines:
        last = (done.stderr.strip().splitlines() or ["no output"])[-1]
        return f"ssh exited {done.returncode}: {last}", []
    return None, lines


def _text(value: bytes | str | None) -> str:
    if value is None:
        return ""
    return value.decode(errors="replace") if isinstance(value, bytes) else value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("command", choices=("inspect", "remove"))
    parser.add_argument("db_name")
    parser.add_argument("--timeout", type=float)
    args = parser.parse_args()

    db_name = args.db_name.removeprefix("test_")
    name = remote_name(db_name)
    if not REMOTE_NAME.fullmatch(name):
        print(json.dumps({"status": "error", "detail": f"unexpected remote name {name!r}"}))
        return 1
    target = os.environ.get(REMOTE_ENV, "").strip()
    result: dict[str, object] = {"remote_name": name, "directory": f"~/{REMOTE_ROOT}/{name}"}
    if not target:
        print(json.dumps({"status": "skipped", **result}))
        return 0
    result["host"] = target

    if args.command == "inspect":
        problem, lines = run_remote(target, inspect_script(name), args.timeout or 20)
    else:
        problem, lines = run_remote(target, remove_script(name), args.timeout or 120)
    if problem:
        print(json.dumps({"status": "unreachable", "detail": problem, **result}))
        return 0

    busy = [line.removeprefix("BUSY ") for line in lines if line.startswith("BUSY ")]
    if busy:
        print(json.dumps({"status": "busy", "processes": busy, **result}))
        return 0
    dberr = next((line.removeprefix("DBERR ") for line in lines if line.startswith("DBERR")), None)

    if args.command == "inspect":
        databases = [line.removeprefix("DB ") for line in lines if line.startswith("DB ")]
        exists = "DIR yes" in lines
        result.update(directory_exists=exists, databases=databases)
        if dberr is not None:
            print(json.dumps({"status": "error", "detail": f"database list: {dberr}", **result}))
        else:
            print(json.dumps({"status": "present" if exists or databases else "absent", **result}))
        return 0

    directory = next((line.removeprefix("DIR ") for line in lines if line.startswith("DIR ")), "?")
    result.update(
        directory_result=directory,
        dropped=[line.removeprefix("DROPPED ") for line in lines if line.startswith("DROPPED ")],
        failed=[line.removeprefix("DROPFAIL ") for line in lines if line.startswith("DROPFAIL ")],
    )
    if dberr is not None:
        print(json.dumps({"status": "error", "detail": f"database list: {dberr}", **result}))
    else:
        print(json.dumps({"status": "removed", **result}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
