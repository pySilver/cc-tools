#!/usr/bin/env bash
# Print the install path of the newest installed planning@umputun-cc-thingz plugin.
# peer-planning:exec's review phase reuses its exec scripts (resolve-file.sh, detect-branch.sh,
# append-progress.sh, stage-and-commit.sh) and the prompt files they resolve, so a
# review here behaves exactly as it does under /planning:exec.
set -euo pipefail
python3 - <<'PY'
import json
import os
import sys

path = os.path.expanduser("~/.claude/plugins/installed_plugins.json")
entries = json.load(open(path)).get("plugins", {}).get("planning@umputun-cc-thingz", [])
if not entries:
    sys.exit("planning@umputun-cc-thingz is not installed")


def version_key(entry):
    return tuple(int(part) if part.isdigit() else 0 for part in entry.get("version", "0").split("."))


print(max(entries, key=version_key)["installPath"])
PY
