#!/usr/bin/env bash
# Print the planning rules the way /planning:make resolves them: the project's
# .claude/planning-rules.md first, else the planning plugin's user-level file.
# First found wins and an empty file counts as absent, so the two layers never
# merge. The first line names the source; nothing is printed when neither exists.
set -u

project_rules=".claude/planning-rules.md"
user_rules="${HOME}/.claude/plugins/data/planning-umputun-cc-thingz/planning-rules.md"

if [ -s "$project_rules" ]; then
  printf 'SOURCE: %s\n' "$project_rules"
  cat "$project_rules"
elif [ -s "$user_rules" ]; then
  printf 'SOURCE: %s\n' "$user_rules"
  cat "$user_rules"
fi
exit 0
