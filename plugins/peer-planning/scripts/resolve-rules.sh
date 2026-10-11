#!/usr/bin/env bash
# Print the project's planning rules, .claude/planning-rules.md in the current directory. The first
# line names the source; nothing is printed when the file is missing or empty.
set -u

project_rules=".claude/planning-rules.md"

if [ -s "$project_rules" ]; then
  printf 'SOURCE: %s\n' "$project_rules"
  cat "$project_rules"
fi
exit 0
