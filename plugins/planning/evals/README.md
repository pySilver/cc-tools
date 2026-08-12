# planning evals

Eval cases for the `planning` plugin, in the native `claude plugin eval` format (`evals/<case>/case.yaml`, schema 1.1).

```bash
# all cases, with the no-plugin baseline arm
claude plugin eval planning@silver-cc-tools

# from a checkout, without installing
claude plugin eval ./plugins/planning

# one case
claude plugin eval ./plugins/planning --case 'decision-brief-*'
```

Targeting the plugin **by name** adds a no-plugin baseline arm automatically (`--ablation with-without`); targeting a **path** defaults to no ablation, so pass `--ablation with-without` explicitly if you want the comparison. The comparison is the point — a score with no baseline says nothing about whether the skill changed anything.

`runs: 3` per case. Graders are LLM-judged (default judge: haiku, override with `--judge-model`) plus a few free regex graders. None of this runs in CI: it costs money and needs a live agent.

## Cases

| Case | Asserts |
|------|---------|
| `decision-brief-fires` | The brief fires and has the right shape — concrete walkthrough first, reproduced-or-derived stated, cause separated from the offered guard, 2–4 costed forks each replaying the scenario, one recommendation, one question, pointers last |
| `decision-brief-silent-bounded-fix` | It stays **silent** on a known cause with a bounded fix |
| `decision-brief-silent-known-cause` | It stays **silent** on a plain error report |

Two of the three cases are negative on purpose. The failure mode of a decision-brief format is **over-firing** — a four-part brief on a two-minute fork spends exactly the attention the format exists to protect — so a suite that only measures whether the shape appears would score an over-firing skill as perfect.

## Writing more

Each case is one directory with `case.yaml`. Required: `schema_version`, `name`, at least one grader. Grader types: `llm` (criteria prose), `regex` (`pattern` + `match: contains | not_contains | count:N`), `tool_used`, `tool_order`, `file_exists`, `baseline`. `plugins: [planning]` only resolves plugins under the path the run targets. Set `arm: with-only` on a grader that is meaningless without the plugin loaded, so it doesn't drag the baseline arm down.

`execution.allowed_tools` is empty here on purpose: these cases grade the shape of a written answer, and every prompt is self-contained, so the agent needs no tools.
