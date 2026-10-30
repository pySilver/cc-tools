# Plan template for peer-planning:make

Fill every section. Where the project's planning rules add a section (for example
`## Stories`) or fix an order, the rules win over this template.

````markdown
# <Title: what exists when the plan is done>

**Executor:** `/peer-planning:exec`. A subagent implements each task and Codex reviews the diff
before the task closes; a task marked `**Discuss:** yes` has its approach agreed with Codex first.

## Stories
<As the project's rules require, or the single line "No actor observes a change".>

## Overview
- What changes and why, in a few bullets.
- The problem it solves and how it fits the existing system.

## Decisions
- Every decision an executor must not re-open, each with its reason and its
  evidence: a code cite by path and symbol, a measurement, or an owner ruling.
- Mark a position two agents settled as pair-settled, so a later review reads it
  as a claim rather than a fact.

## Context
- The files and components involved, the patterns to follow, the dependencies.
- Cite code by path and symbol, never by line number.

## Execution
- **Implementer:** the `implementer` agent definition (Opus at medium). A task may
  name another definition in its own **Executor:** line.
- **Validation:** <the project's commands, stated once here: format, lint, type
  check, framework checks, and pytest over only the test files a task writes or
  edits>.
- **Whole suite:** <the project's whole-suite command, stated once here. exec's closing
  suite stage runs it after the branch review and polish; no task runs it>.
- **Commits:** one per task, `type(scope): subject`, after Codex's review.

## Tasks

### Task 1: <the outcome, named as a result>
**Goal:** <one or two sentences: the behavior that exists when this task is done>
**Starting points:** `path/to/module.py` (`SymbolName`), `path/to/other.py` —
where to begin reading, not a complete list.
**Constraints:** <the decisions, invariants, rules and stories this task must
honor>
**Done when:**
- [ ] <an observable outcome>
- [ ] <an observable outcome>
- [ ] tests in `path/to/test_module.py` pin <the behavior> and pass

### Task 2: <outcome>
**Discuss:** yes  <!-- only for a migration, a lock order, a protocol or schema change, a visibility rule -->
**Executor:** worker  <!-- only when overriding the plan's implementer -->
...

### Task <n-1>: Verify acceptance criteria
- [ ] every story and every Done-when above holds

### Task <n>: Update documentation
- [ ] every guide, rule or doc the change made wrong describes the new state

## Post-Completion
<No checkboxes. Manual checks, owner-run steps, follow-ups outside this repo.>
````

Number the tasks with real integers; `<n-1>` and `<n>` above are placeholders.
