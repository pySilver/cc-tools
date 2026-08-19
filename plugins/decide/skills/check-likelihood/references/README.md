# check-likelihood — references

## `run-codex.sh`

Codex invocation wrapper, used only by Step 6's optional cross-model
escalation. **Execute-only**: invoke it via `bash`; do not read it into
context during a check. This contract is the loadable surface.

**Fork** of the planning plugin's
`~/.claude/plugins/cache/umputun-cc-thingz/planning/3.7.1/skills/exec/scripts/run-codex.sh`,
owned here so the wedge-fix patch we maintain doesn't get clobbered by
plugin updates. We deliberately DON'T route through
`thinking-tools:ask-codex` — one fewer plugin dependency, and the fix
stays durable.

Inherits the upstream's:

- `codex exec --sandbox read-only` invocation shape
- VCS detect (git vs hg) → adds `--skip-git-repo-check` for hg
- Default `-c` overrides (model, reasoning effort, project_doc context)
- `CODEX_NO_OVERRIDES=1` and `CODEX_MODEL=<name>` escape hatches (our
  default model is `gpt-5.6-sol`)

Adds:

- `set -euo pipefail` (upstream uses `set -e` only)
- Inlined VCS detect (upstream has a separate `detect-vcs.sh` helper;
  we keep the dependency surface at one file)
- The wedge fix (`exec codex ... </dev/null`) maintained at the source,
  with a comment explaining the failure mode it defends against.

Usage: `bash run-codex.sh '<prompt>'`. Output on stdout, exit code from
codex. Covered by `tests/test-decide-run-codex.sh`, which stubs
`codex` and `git` on `PATH`.
