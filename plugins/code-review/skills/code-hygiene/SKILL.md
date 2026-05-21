---
name: code-hygiene
description: Analyze app code for agentic smells — overly complex code patterns and verbose/stale/AI-speak docstrings and comments typically introduced by AI review-fix loops. Pass app path as argument (e.g., /code-hygiene myproj/app).
allowed-tools: Agent, Glob, Read, Grep, Bash, AskUserQuestion
---

# Code Hygiene Review

Analyze code in a Python/Django app for patterns that are technically correct but unnecessarily
complex — the kind of code that AI-assisted review-fix cycles tend to produce. This is a
**read-only analysis** — do not fix anything, only report findings for human review.

## Step 0: Validate Input

If $ARGUMENTS is empty, ask the user for the app path using AskUserQuestion.
Store the validated path as APP_PATH.

## Step 1: Discover Files

Use Glob to find all `.py` files under APP_PATH, excluding:
- `tests/` and `test_*.py` files
- `migrations/` directories
- `__init__.py` files (unless >20 lines)
- `apps.py` (boilerplate)

Count and display the discovered files. If more than 40 files, inform the user and
proceed — the batching handles scale.

## Step 2: Create Review Batches

Group files into batches of 5-8 files each. Keep related files together when possible
(e.g., `services.py` + `selectors.py`, `models.py` + `schemas.py`).

## Step 3: Parallel Review

Spawn one Agent per batch, all in a single message (parallel execution). Use
`subagent_type: "general-purpose"` and `model: "opus"` for each agent.

Each agent receives its batch of file paths and the review instructions below.

### Review Agent Prompt Template

Use this prompt for each agent, replacing {FILE_LIST} with the batch's file paths:

---

You are reviewing Python code for "agentic code smells" — patterns that are technically
correct but unnecessarily complex, typically introduced when AI agents iteratively
review and fix code. These patterns make code harder to read and maintain without
adding value.

**Read each file listed below and look for these specific patterns:**

{FILE_LIST}

For each file, examine both code shape and prose (triple-quoted docstrings,
`#` comments, TODO/FIXME markers).

## What to Look For

### Code Smells

#### CAT-1: Tautological Expressions
- `True if condition else False` — just use `condition`
- `False if condition else True` — just use `not condition`
- `x == True`, `x is True` — just use `x`
- `if cond: return True` / `else: return False` — use `return cond`
- Redundant `bool()` casts on already-boolean values
- `len(x) > 0` instead of just `x` (for collections)
- `if x is not None: return x` / `else: return None` — just `return x`

#### CAT-2: Impossible-State Guards
- Checking function params for values the caller/signature cannot provide
- `if x is None` checks when `x` is typed as non-optional
- Guards inside methods for states the method's preconditions exclude
- Example: `if source == target: return` inside `migrate(source, target)` where
  the function's purpose IS to migrate between different things

#### CAT-3: Defensive Dead Code
- Try/except catching exceptions the enclosed code cannot raise
- If/elif branches whose conditions can never be true given surrounding logic
- Fallback values after operations guaranteed to succeed
- Catch-log-reraise (`except X: logger.error(...); raise`) — let it propagate,
  the caller's handler will log it

#### CAT-4: Convoluted Control Flow
- Nested if/else that could be flattened with early returns
- Flag variables tracking state that could be computed directly
  (`is_x = True; if a: is_x = False; if is_x: ...` — just use `if not a:`)
- Multiple conditional assignments that are really one expression
- Unnecessary temporary booleans: `is_x = True if a else False; if is_x:` — just `if a:`

#### CAT-5: Redundant Validation
- Re-checking what Pydantic schemas already validate
- Duplicate null/empty checks at multiple layers (schema + service + model)
- Type assertions on values whose type is guaranteed by annotations
- Re-validating enum values that are already constrained by the type

#### CAT-6: Over-Engineered Concurrency
- Locks or mutexes in code paths that run single-threaded
- Complex retry-with-backoff for deterministic failures
- `select_for_update` without actual concurrent writers
- Race condition guards for operations that are inherently sequential

#### CAT-7: Verbose No-Ops
- Setting a variable to its current value
- `if condition: pass` (empty branches)
- Assigning a value immediately overwritten
- Building data structures that are never consumed

#### CAT-8: Unnecessary Intermediates
- Variables aliasing a simple attribute access used once immediately
- `result = do_thing(); return result` — just `return do_thing()`
- Creating a collection just to immediately unpack
- Wrapper variables that add no clarity

### Docstring and Comment Smells

These apply to triple-quoted docstrings and `#` comments inside `.py` files.
They do NOT apply to `.md` files (CLAUDE.md, rules, README) — those are out of scope.

#### CAT-9: Comment Explains WHAT, Not WHY

Test: a reader who already knows Python and reads the next 5 lines of code gains
nothing from reading the comment first.

**Always HIGH** — these are the calibration anchors. Two reviewers must reach the
same verdict on each of these patterns:

1. **Paraphrase of adjacent structured prose.** A `#` comment or docstring restates
   information already present within 3 lines as `help_text=`, `verbose_name=`,
   another docstring, a `raise ApplicationError("…")` message, or a type
   annotation. The Django `help_text=` value IS structured prose — any
   `#` comment above the field that paraphrases or shortens it is HIGH.

2. **Inline restatement.** End-of-line comment that restates the line it sits on
   (`counter += 1  # increment counter`).

3. **Args/Returns/Raises boilerplate.** `Args:` / `Returns:` / `Raises:` entries
   that only paraphrase the type signature without adding constraints, units, or
   failure conditions. (Do not also report this pattern under CAT-11.)

4. **Class docstring that paraphrases the class name with no added clarifier.**
   `"""Service for managing X."""` on `XService`, `"""Selector for querying Xs."""`
   on `XSelector`, `"""Result of computing Y."""` on `YResult`. The class name
   alone already conveys this.

   **Exempt:** A short class docstring that adds a clarifying noun, scope, or
   failure mode beyond what the name conveys. Examples:
   - `"""Validate file extension against the actual content, not the filename."""`
     on `RealFileExtensionValidator` — the "against actual content" clarifier is
     the value-add.
   - `"""ASGI handler that serves static files and falls back to the wrapped app."""`
     on `StaticFilesHandler` — names the fallback semantics.

**HIGH but conditional** — these patterns require checking before flagging:

5. **Group / section label above declarations.** A single-line `#` comment whose
   only job is to announce the group below: ASCII separators
   (`# ===…===`, `# ---…---`), bare group labels (`# Image fields`,
   `# Retry tracking`, `# Internal`, `# Pickup`), `# Section: X` style.

   **HIGH when:**
   - The label sits above 1-2 declarations (no group to navigate).
   - The codebase mixes banner styles (`=`, `-`, plain prose) — the
     inconsistency is the smell. Pick the dominant style and flag the others.
   - The label paraphrases the immediate identifier name
     (`# Pickup` immediately above `pickup_method = ...` with no other Pickup-related
     declarations following).

   **Exempt when:**
   - The label sits above **3 or more related declarations** and aids navigation
     in a long file. Field-group labels in Django models, Pydantic schemas, and
     dataclasses with many fields belong here (`# Snapshot fields`,
     `# Retry tracking` above `retry_count` + `last_attempt_at` + `error`).
   - The label is a **step marker** inside a long function (>50 lines) where each
     step is a distinct logical chunk (e.g. `# Phash similarity`,
     `# Loyalty programs`, `# Pickup` inside `_schema_to_product_kwargs`).
   - The label is a **regex explainer** above a `re.compile(...)` pattern,
     even when the regex itself looks mechanical.
   - The label groups **FSM transition tuples** by intent
     (`# Initial application review`, `# Reconsideration paths` inside a
     `pgtrigger.FSM(transitions=[...])` list).
   - The label names a **non-obvious invariant** the identifier alone cannot
     convey: `# Denormalized from Brand — must be re-synced when Brand.name changes`,
     race-window descriptions, ordering constraints, performance trade-offs with
     measured numbers, external-library gotchas.

The exempt clause covers information the names cannot convey. It does not cover
any reasonable-sounding paragraph. If removing the comment loses only verbosity,
it is CAT-9.

#### CAT-10: Stale Historical Reference

**Always HIGH:**
- `# used to be X`, `# previously did Y`, `# removed in the Z refactor`
- `# added for the W flow`, `# for issue #123`, `# see ticket ABC-456`
- TODO referencing a refactor that already happened
- Comment naming a class, function, file, or module that no longer exists
- `# see also: <doc>` where the doc has been deleted or renamed
- **Comments that cite `.claude/rules/*.md` paths or restate rules from that
  tree.** Examples: `# Official Interface - modifications must go through service
  layer` (restates `.claude/rules/03-pgtrigger.md`), `# See .claude/rules/12-outbox.md`.
  The rule belongs in the project's CLAUDE.md tree, not the source file —
  in-code citations read as project-pollution and rot when rules move. The
  trigger / decorator / type annotation already enforces the rule; the comment
  adds nothing.

  **Exempt:** a one-line in-code pointer to a specific external document
  (a Vespa schema file, an external API doc URL, an RFC). The rule is the
  difference between in-tree project rules (paraphrase) and out-of-tree
  domain references (load-bearing).

#### CAT-11: Multi-Paragraph Docstring or Comment Block

Length itself is not the smell. Length plus paraphrase is the smell.

**HIGH:**
- Docstring of 4+ lines where at least half the lines paraphrase the function
  name, the type signature, or other already-structured prose.
- `#` comment block of 4+ consecutive lines that narrates a sequence the code
  makes obvious — for example, 4 lines describing each step of a 4-step
  function when each step is one self-explanatory call.
- Single sentence with 3+ chained clauses, embedded parentheticals, or no
  natural break.

**MEDIUM:**
- Long docstring that mixes WHY (load-bearing) with WHAT (paraphrase). The
  paraphrase chunks are removable but the surgery is manual.

**Exempt:**
- Long docstring or comment that documents a multi-step invariant, race
  window, ordering constraint, or external-library gotcha. Length is
  justified when the content cannot be split without losing the WHY.

Args/Returns/Raises boilerplate belongs under CAT-9 (subcase 4), not here.

#### CAT-12: AI-Speak in Docstring or Comment
- Filler phrases: "it's important to note that", "it's worth mentioning", "in order to"
- AI words: "comprehensive", "robust", "leverage", "utilize", "facilitate", "seamless", "streamline"
- Abstract noun forms: "the implementation of X", "performs validation of"
- Hedging: "perhaps", "it would seem that", "this approach may"
- Meta-commentary: "this function works by", "the benefit of this is", "what this means is"
- Excessive transitions: "Furthermore", "Additionally", "Moreover", "In conclusion"

#### CAT-13: Commented-Out Code
- Blocks of code commented out with `# ` prefixes (git has the history)
- `if False:` / `if 0:` guards around dead code
- Old implementation left next to the new one as "reference"

#### CAT-14: Bare TODO/FIXME/XXX
- TODO with no owner, no ticket, no condition for when it becomes actionable
- TODO for trivial work that should just be done now
- FIXME / XXX / HACK with no context — the reader cannot tell what to fix

**FLAG ONLY — never silently remove.** A TODO/FIXME/XXX is an actionable memo:
it records work the author deliberately deferred. Report it so a human can
decide (act on it, file a ticket, or sharpen the wording), but do NOT delete it
during a fix pass. Deleting a memo destroys intent that cannot be recovered from
the code or git history. This holds even for "bare" TODOs that match the
patterns above — bareness is a reason to flag for improvement, not to delete.

## Rules

- ONLY report patterns where simpler code is EQUALLY CORRECT, or where shorter
  prose is EQUALLY INFORMATIVE — not stylistic preferences
- DO NOT report: naming style, formatting, type hints (ruff/basedpyright handle those)
- DO NOT report MISSING docs — this skill targets bad docs, not absent ones
- DO NOT report code that is complex because the PROBLEM is complex
- DO NOT report a comment or docstring whose WHY-exempt clause applies. The
  clause covers content that names a multi-step invariant, race window,
  ordering constraint, performance trade-off with numbers, non-obvious side
  effect of an external library, or another decision the identifier names
  alone cannot convey. It does NOT cover paraphrase of `help_text`, function
  names, or type signatures — those remain CAT-9 regardless of how plausibly
  written
- A comment that adds non-obvious value MUST be kept. Non-obvious value is
  anything the identifiers and types cannot convey: an invariant, a race
  window, an ordering constraint, a performance trade-off with numbers, an
  external-library gotcha, a load-bearing magic constant, or a deliberate
  override of inherited behavior (e.g. "title and description inherit
  default=\"\" from parent"). When in doubt whether a comment carries such
  value, treat it as keep — downgrade to MEDIUM, never flag HIGH
- DO NOT report group / section labels above 3+ related declarations, step
  markers in functions >50 lines, regex explainers, FSM transition labels, or
  navigation aids in long files. These are covered by CAT-9 subcase 5's exempt
  list and are valuable
- DO check banner-style consistency. The canonical section-divider style is a
  plain `# Section name` block comment (Django / CPython style) — NO decorative
  rule lines (`# ====`, `# ----`), NO fences (`###`), NO inline wrappers
  (`# --- X ---`). When you find decorative banners, flag them as STYLE_DRIFT;
  the fix reduces them to a plain `# Section name` label, never a competing
  decorative style. A multi-line rule block collapses to the single label line
  it wraps. (The label itself stays only when it earns its place under CAT-9
  subcase 5 — above 3+ related declarations, as a step marker in a long
  function, etc. A decorative banner above 1-2 declarations is STILL CAT-9: drop
  the whole thing, not just the rule lines.)
- DO check section-divider spacing. A **module-level section name** — a topic
  label heading top-level definitions (`# Shoes`, `# Product handlers`,
  `# Enums - Product Attributes`, `# Departments (L0)`, `# Gender normalization`)
  — takes a **blank line after** the comment, separating it from the code below.
  A **group / explanatory label** that describes the contiguous block right under
  it stays **attached** (no blank line after): in-class field groups
  (`# Canonical consensus — array fields`), in-function step markers, and
  module-level comments explaining the single definition that follows
  (`# Hard TTL window …`, `# Alias lookup table …`, `# Per-doc-type batch sizes`).
  The dividing line is scope, not wording: module-level section name → blank;
  in-class / in-function / single-definition explainer → attached. Flag a section
  name glued to its code as STYLE_DRIFT (fix: insert one blank line). Never insert
  a blank after an attached label. Let the formatter settle the count — before a
  class/def it enforces 2 blank lines, before an assignment 1; you only ensure at
  least one blank exists after a section name.
- For each finding, explain WHY the simpler version is equivalent
- Skip files with no findings silently

## Confidence Calibration

Goal: two reviewers reading the same file reach the same HIGH/MEDIUM verdict in
roughly 95% of cases.

### Calibration history (2026-05-20 / 2026-05-21)

The earlier version of this skill listed *all* group/section labels above
declarations as Always-HIGH (CAT-9 subcase 2). Field reviews showed this was too
aggressive: bulk-applying the rule deleted navigation aids from long Django
models, Pydantic schemas, and large functions, and the user pushed back on
several of those reverts. The current rule promotes the navigation case to
exempt and keeps Always-HIGH only for the narrower cases (paraphrase of a
nearby identifier, banner above 1-2 declarations, mixed styles in the same
codebase). Class docstrings that add a clarifier beyond the class name were
also moved from Always-HIGH to exempt for the same reason.

### Calibration update (2026-05-21)

- **Section banners.** Project convention is plain `# Section name` block
  comments (Django / CPython style). All decorative dividers — full-width rule
  lines (`# ====`, `# ----`), `###` fences, and inline `# --- X ---` wrappers —
  are STYLE_DRIFT; the fix collapses them to the plain label (and the label
  itself survives only if it earns its place under CAT-9 subcase 5). See the
  DO-check banner rule.
- **TODO/FIXME/XXX are flag-only.** They are actionable memos and must never be
  silently removed during a fix pass (CAT-14).
- **Non-obvious value is decisive.** A comment that carries an invariant, race
  window, ordering constraint, measured trade-off, library gotcha, magic
  constant, or inherited-behavior override is kept regardless of length or
  phrasing.
- **Section-divider spacing (refinement).** When a label *survives* (it is a
  kept section name, not a CAT-9 drop), its spacing encodes its role: a
  module-level section name gets a blank line after it; an in-class /
  in-function / single-definition explanatory label stays attached to the code
  it describes. An earlier sweep collapsed the trailing blank on *all* labels
  (treating "attached" as the one true style); the user corrected this — gluing
  a section name to its first definition blurs section vs. group. The fix is
  whitespace only (insert one blank after section names; never after attached
  labels), and the formatter then sets the exact count (2 before a class/def, 1
  before an assignment). See the DO-check section-divider-spacing rule.

**HIGH** — use when one of these holds:
- The pattern matches an "Always HIGH" subcase named under CAT-9, CAT-10, CAT-11,
  CAT-13, or CAT-14.
- The simpler form has identical externally observable effects and you confirmed
  this by reading the function plus its immediate context (callers in the same
  file, tests in the matching test file). No cross-module reading needed.

**MEDIUM** — use when one of these holds:
- Confirming equivalence requires reading callers in other files or external
  state.
- The pattern matches a category description but the WHY-exempt clause is
  plausibly invoked and you cannot decide from the immediate context.

Do NOT use HIGH when you suspect the smell but have not read enough context to
rule out a non-obvious reason. Downgrade to MEDIUM.

If you hesitate between HIGH and MEDIUM more than a few times in a single batch,
you are not anchoring on the subcase definitions. Re-read CAT-9 subcases 1–4
and the WHY-exempt clause, then re-rate.

## Output Format

Return findings as a structured list. Use this exact format:

```
CAT: {category_number}
FILE: {file_path}:{line_number}
CODE: {the problematic code, 1-3 lines}
ISSUE: {what's wrong, one sentence}
FIX: {what simpler code looks like}
CONF: {high|medium}
---
```

High confidence = clearly an agentic smell, simpler code is provably equivalent.
Medium confidence = likely an issue but might have a non-obvious reason.
Do not report low-confidence findings.

---

## Step 4: Collect and Group

After all agents complete, collect all findings. Group them by category (CAT-1 through
CAT-8). Within each category, sort by confidence (high first), then by file path.

## Step 5: Present Report

Present the final report in this format:

```
Code Hygiene Report: {APP_PATH}
Files reviewed: N | Findings: N (N high, N medium)
```

Then for each category that has findings:

```
## {Category Name} ({N} findings)

1. `{file_path}:{line}` [{CONF}]

   {problematic code, indented}

   Issue: {description}
   Fix: {simpler code}

2. ...
```

Category names for reference:

Code Smells:
- CAT-1: Tautological Expressions
- CAT-2: Impossible-State Guards
- CAT-3: Defensive Dead Code
- CAT-4: Convoluted Control Flow
- CAT-5: Redundant Validation
- CAT-6: Over-Engineered Concurrency
- CAT-7: Verbose No-Ops
- CAT-8: Unnecessary Intermediates

Docstring and Comment Smells:
- CAT-9: Comment Explains WHAT, Not WHY
- CAT-10: Stale Historical Reference
- CAT-11: Multi-Paragraph Docstring or Comment Block
- CAT-12: AI-Speak in Docstring or Comment
- CAT-13: Commented-Out Code
- CAT-14: Bare TODO/FIXME/XXX

Omit categories with zero findings. End with:

```
Summary: N findings across N categories. N high-confidence items recommended for review.
```

## Important

- This is READ-ONLY analysis. Do not modify any files.
- Do not suggest refactoring unrelated to the 8 categories above.
- Do not report anything that ruff or basedpyright would catch.
- Focus on code that a human would find odd or unnecessarily complex.
