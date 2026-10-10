# decide evals

Eval cases for the `decide` plugin, in the native `claude plugin eval` format (`evals/<case>/case.yaml`, schema 1.1).

```bash
# all cases, with the no-plugin baseline arm
claude plugin eval decide@silver-cc-tools

# from a checkout, without installing
claude plugin eval ./plugins/decide

# one case
claude plugin eval ./plugins/decide --case 'brief-*'
```

Targeting the plugin **by name** adds a no-plugin baseline arm automatically (`--ablation with-without`); targeting a **path** defaults to no ablation, so pass `--ablation with-without` explicitly if you want the comparison. The comparison is the point — a score with no baseline says nothing about whether the skill changed anything.

`runs: 3` per case. Graders are LLM-judged (default judge: haiku, override with `--judge-model`) plus a few free regex graders. None of this runs in CI: it costs money and needs a live agent.

## Cases

| Case | Asserts |
|------|---------|
| `brief-fires` | The brief fires and has the right shape — concrete walkthrough first, reproduced-or-derived stated, a bounded step back that judges the *kind* of cause and its reach, cause separated from the offered guard, 2–4 costed forks each replaying the scenario, one recommendation, one question, pointers last |
| `brief-cause-is-a-decision` | The step back reaches a **decision**, not a missing guard — and the fork that revises it gets written, costed, and replayed alongside the two guards the prompt pre-offered |
| `brief-silent-bounded-fix` | It stays **silent** on a known cause with a bounded fix: no Skill call names `brief`, and the answer is not shaped like a decision menu |
| `brief-silent-known-cause` | It stays **silent** on a plain error report: no Skill call names `brief`, and the answer is not shaped like a decision menu |

Two of the four cases are negative on purpose. The failure mode of a brief format is **over-firing** — a five-part brief on a two-minute fork spends exactly the attention the format exists to protect — so a suite that only measures whether the shape appears would score an over-firing skill as perfect.

Firing and shape are graded separately, because a judge reading the reply cannot tell them apart. `brief-not-invoked` fails a negative case if any Skill call names `brief`; `brief-invoked` (with-only, so a plugin-fired indicator rather than part of the score) shows whether the positive cases loaded it. `no-decision-menu` judges the reply's shape whether or not anything loaded, so it also grades the base model: in 10 runs of the two negative cases on Claude Code 2.1.296, `brief` was never invoked, yet the menu shape still appeared in 5, and the no-plugin baseline failed it in 4 of 6 earlier runs. Read that grader through the with/without delta, not on its own.

The two positive cases are deliberately opposed on the step back. In `brief-fires` the plan was right and the build diverged from it, so the honest step back is short and says *local*; in `brief-cause-is-a-decision` an approved ADR is what makes the failure possible, so the honest step back names that decision and the forks have to include revising it. A skill that always reaches for "this is a design flaw" scores well on one and badly on the other, which is the point — manufacturing a root cause is as wrong as skipping it.

## Writing more

Each case is one directory with `case.yaml`. Required: `schema_version`, `name`, at least one grader. Grader types: `llm` (criteria prose), `regex` (`pattern` + `match: contains | not_contains | count:N`), `tool_used`, `tool_order`, `file_exists`, `baseline`. Leave `plugins:` out: it takes plugin directories relative to the case directory (`["../.."]`), defaults to the nearest enclosing plugin, and on Claude Code 2.1.296 a plugin *name* such as `[decide]` fails the case at load with `plugins entry "decide" does not exist`. Set `arm: with-only` on a grader that is meaningless without the plugin loaded, so it doesn't drag the baseline arm down; under `--ablation with-without` such a grader is reported as a plugin-fired indicator and left out of the score.

These cases grade the shape of a written answer, and every prompt is self-contained: it describes code and history the eval workspace does not contain. `execution.append_system_prompt` says so in each case. Without it the agent searches the empty workspace with the default read-only tools, finds nothing, and declines to write about code it cannot see (measured on 2.1.296: `brief-silent-known-cause` scored 0.17 that way).
