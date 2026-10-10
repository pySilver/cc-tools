# huddle evals

Eval cases for the `huddle` plugin, in the native `claude plugin eval` format (`evals/<case>/case.yaml`, schema 1.1).

```bash
# with the no-plugin baseline arm; --scaffold builds huddle-fires-code's retry.py
claude plugin eval ./plugins/huddle --ablation with-without --scaffold --allow-tools Bash
```

`--allow-tools Bash` is the operator grant the cases' `allowed_tools` need; the run is sandboxed. `runs: 3` per case. None of this runs in CI: it costs money and needs a live agent.

## What an eval run can and cannot see

Measured on Claude Code 2.1.296:

- **`huddle` never executes.** The plugin's `bin/` is not on the run's `PATH` (the Bash call ends `command not found: huddle`), and the run is never inside agterm: it inherits only an allowlist of the operator's environment plus `EVAL_*` variables, so no `AGTERM_*` value arrives, and a case's own `execution.env` accepts only `EVAL_*` keys. So nothing can open, anywhere.
- **What it measures** is the half that is the skill's job: whether the description and the prompt lead the agent to try `huddle`, and how good the spec it writes is. The graders read that spec from the session trace (`focus: trace`), not from the final reply, which is the agent's text fallback after the failed call.
- **Your own instructions are absent.** Each run gets a temporary home and Claude Code configuration with CLAUDE.md loading disabled, so `~/.claude/rules`, `~/.agents/AGENTS.md` and project `CLAUDE.md` files do not load. A pass says the skill fires on its own; it says nothing about whether a personal rule on how to ask lets it fire.

## Cases

| Case | Asserts |
|------|---------|
| `huddle-fires-visual` | An architecture choice between three shapes goes to `huddle` with a good spec: three options with what distinguishes each, a picture of each (mermaid previews, a diagram of today's flow, or a side-by-side layout), a reasoned recommendation; and the agent does not decide for the user |
| `huddle-fires-code` | A judgement on a stretch of code shows that code through `{"code": {"file": "retry.py", "lines": …}}`, not as source pasted into the spec |
| `huddle-silent-plain` | A question with one-line answers ("full suite or unit tests?") stays in the terminal |
| `huddle-silent-confirm` | A yes/no confirmation of a file rename stays in the terminal |

Two of the four are negative on purpose: the cost of this skill is a context switch, so its failure mode is a page for a question that a line of text would have answered.

## Reading a result

Read the per-run `error` field in the JSON before trusting a score: a run that errored before starting (a rejected `execution.env` key, a `plugins:` entry that does not resolve) still lets the suite report its cases as passed under `--threshold 0`. Under `--ablation with-without`, a grader marked `arm: with-only` is reported as a plugin-fired indicator and left out of the score, so these cases mark none: the baseline arm cannot call `huddle`, and that gap is the delta.
