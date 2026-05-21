#!/usr/bin/env bash
#
# extract-sentinels.sh — drift-guard sentinel extraction for a plan file.
#
# Scans for lines containing "**load-bearing" (case-insensitive). For each
# match, collects every backtick-fenced span in a 3-line window (the match
# line ± 1). This fixes the single-line miss when the marker sits on the
# wrap line of a multi-line checkbox while the load-bearing identifier
# lives on the adjacent line.
#
# Output: one unique sentinel per line; empty output if none found.
# Empty output is informational, not an error — the orchestrator should
# warn the user that no drift guard will run for this plan.
#
# Usage: extract-sentinels.sh <plan-path>
set -euo pipefail
plan="${1:?Usage: $0 <plan-path>}"
[[ -f "$plan" ]] || { echo "$0: $plan: not a file" >&2; exit 1; }

python3 - "$plan" <<'PY'
import re, sys
with open(sys.argv[1]) as f:
    lines = f.readlines()
marker = re.compile(r"\*\*load-bearing", re.IGNORECASE)
backtick = re.compile(r"`([^`]+)`")
seen, ordered = set(), []
n = len(lines)
for i, line in enumerate(lines):
    if not marker.search(line):
        continue
    for j in (i - 1, i, i + 1):
        if 0 <= j < n:
            for m in backtick.finditer(lines[j]):
                s = m.group(1)
                if s not in seen:
                    seen.add(s)
                    ordered.append(s)
for s in ordered:
    print(s)
PY
