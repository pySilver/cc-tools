---
name: huddle
description: Ask the user a question as a page in an agterm HTML overlay and read the answer back as JSON. Use for every question that asks the user to choose or approve — a design fork, a sequencing call, a plan or its parts, a choice between two options — because each option then carries what it changes and what it costs; for options that are pictures (diagrams, wireframes, design samples, charts); for code or a diff the user has to read; for a value tuned by eye (sliders with a live preview); and for several related decisions at once. Also whenever the user says huddle, "ask me visually" or "show me the options". Only an answer the user types (a name, a path, a number) or a bare "go ahead?" on a step just described stays in the terminal. Needs agterm and checks for it itself, so run it without checking first. Up to 9 options with subtitles, a reasoned recommendation and pros/cons; a free-text box on every question; keyboard throughout. The agent writes a JSON spec or one `huddle q` line.
allowed-tools: Bash(huddle *)
---

# huddle — ask the user with a page, not a prompt

One command opens the question over **your own** agterm session, waits for the answer, and prints it as
JSON. The runtime (layout, styles, charts, diagrams, sliders, keyboard) is prebuilt; you describe the
question. `huddle` is on the Bash tool's `PATH` while this plugin is enabled.

Run it with the Bash tool's `timeout: 600000`. It waits up to 570 s, then exits 4 with the page still open
(see [Waiting](#waiting)).

## When to ask with a page

- **Ask with a page** whenever the user has to choose or approve: a design fork, a sequencing call, a plan
  or its parts, and a choice between just two options too. A short list of labels is where the user stops
  understanding the difference; on a page each option carries what it changes and what it costs. Pictures,
  code, tuned values and related decisions on one page come on top of that.
- **Ask in the terminal** only when the user answers by typing (a name, a path, a number), or for a bare
  "go ahead?" on a step you just described.
- **The user's own instructions win.** When their `CLAUDE.md` or `AGENTS.md` says how to ask questions,
  follow it; this section is the default, not an override.
- **Don't check for agterm first.** Run `huddle`: outside agterm it opens nothing and exits 3 with
  `status: "no-agterm"`, and you ask in the terminal instead.
- **Only the agent talking with the user asks.** A subagent, a plan executor or a background worker returns
  its question to whoever started it. In an unattended run (`claude -p`, where Claude Code sets
  `CLAUDE_CODE_SESSION_ATTENDED=0`) `huddle` refuses with exit 3 and opens nothing.

## Fastest: one line

```bash
huddle q "Which store for sessions?" "*Redis|already runs the job queue|no new service" "Postgres table|one table, expiry index" "Stateless JWT|cannot revoke"
```

Each option is `Label|subtitle`; a leading `*` marks it recommended, and a third field says why
(`*Label|subtitle|why`). `--multi` for multi-select, `--context "markdown"` for a paragraph under the
question, `--title` for the topic line above it.

## Normal: a JSON spec on stdin

```bash
huddle - <<'JSON'
{
  "title": "Session storage",
  "prompt": "Where should sessions live?",
  "context": "Sessions live in process memory, so every deploy logs everyone out.",
  "options": [
    {"id": "redis", "label": "Redis", "subtitle": "Managed, TTL per key",
     "recommended": "Already running for the job queue",
     "pros": ["Sub-ms reads"], "cons": ["Another moving part"]},
    {"id": "pg", "label": "Postgres table", "subtitle": "One table, expiry index"}
  ]
}
JSON
```

A spec in a file works the same way (`huddle spec.json`); relative paths inside it (images, `file` blocks)
then resolve beside the file instead of the working directory.

## Write the question first

The prompt is the biggest thing on the page; everything else supports it.

- `prompt`: **one short, direct question**, ideally under 12 words, ending in `?` or an imperative
  ("Tune the card style until it looks right"). The user should know what to do from it alone.
- `title`: the topic in two to five words ("Session storage"). Shown small above the prompt.
- `hint`: one line under the prompt saying what matters or how to answer. Not a second question.
- `context` (top level, shared by every question) or `body` (one question's own; `context` on a question
  means the same): the evidence — numbers, a diagram, a diff. Shown under the prompt.
- `header`: one or two words per question, for the tabs and the review list.

## Carry the context

A page is worth opening only when it shows more than a numbered list would. The user answers from the page
alone: the plan, the code and your last terminal message are not in front of them.

- **What is being decided lives on the option.** Approving stories, tasks, findings or plan sections: one
  option each, labeled by what it says rather than by its number ("4 · an unplaceable brand stays pending",
  never "Story 4"), the gist in `subtitle`, the full text in `detail` (or
  `{"md": {"file": "docs/plans/x.md", "lines": "40-52"}}`), and `expanded: true` so the text is open without
  a click. huddle refuses an option whose label only counts and that carries nothing else.
- **What several options share goes above them**: the example from the eval, the numbers, today's flow as a
  diagram, in `context` or the question's `body`.
- **Before you send**, read the page as the user will: could they answer without opening anything else? If
  not, it is missing the thing they need to judge.

## Pick the component for the question

| The answer is… | Use | Template |
| --- | --- | --- |
| one of a few alternatives | options, `layout: "list"` | `pick` |
| alternatives whose trade-offs matter | `layout: "compare"` (side by side, pros/cons visible) | `tradeoffs` |
| a visual (a diagram, a layout, a sample) | options with `preview` → `grid` | `architecture`, `layouts`, `design-tokens` |
| a judgement on code the user must read | `code` / `diff` blocks from `{"file": …}` in `context` | — |
| yes / no / later | `layout: "inline"` | `confirm` |
| several items from a list | `mode: "multi"`, `min`/`max` | `checklist` |
| a number or color that is a matter of taste, with no standard step to choose from (radius, gap, hue, speed, size, weight, delay) | **`controls`** — sliders with a live preview | `tune` |
| words | `mode: "text"` | `text` |
| several related decisions | `questions: [...]` — tabs, then a review of every answer | `design-tokens` |

When there *are* standard values (4/8/16 px, a design-system scale), offer them as options with previews.
When the value is continuous or purely taste, give sliders: the user sees the result while dragging.
Combine them: options to pick a direction, then a `controls` question to fine-tune it (see `demos/ui-kit`).

`huddle templates` lists the templates and prints their directory; read one and fill it. `huddle demo NAME`
opens one, as do the larger showcases in `demos/` (`motion`, `ui-kit`, `auth-flow`, `rollout`, `pricing`) —
read those for combinations.

## Show the real code

Never paste source into a spec by hand: escaping it into JSON is where a spec breaks or a snippet drifts
from the file. Point at the file instead and `huddle` reads it when it builds the page:

```json
{"code": {"file": "src/session/store.py", "lines": "40-62"}}
{"diff": {"file": "/tmp/change.patch"}}
{"md": {"file": "docs/plans/sessions.md"}}
{"mermaid": {"file": "docs/flow.mmd"}}
```

- `lines` is `"40-62"`, `"40"` or `[40, 62]`; omit it for the whole file. A `code` block from a file gets its
  path and range as its title, numbered lines (so a note can say "line 47"), and its extension as `lang`;
  a `title`, `start` or `lang` you set yourself wins.
- For a diff, write it to a file in the same Bash call:
  `git diff main -- src/session > "$TMPDIR/s.patch" && huddle - <<'JSON' …`.
- A missing file or a range past its end is an error (exit 1): the user is deciding on that code, so a page
  without it would mislead. So is a whole file of more than 300 lines as `code` — name the lines the question
  is about.

## The answer

```json
{"status": "answered", "pageID": "…",
 "answers": {"answer": {"selected": ["redis"], "labels": ["Redis"], "text": "but only for prod"}}}
```

- `answers` is keyed by question id (`answer` for a single-question spec, `q1`, `q2`… when unnamed).
- `selected` lists option ids in display order; `text` is present only when the user typed something —
  it may come **alone** (their own answer) or **with** a selection (a note on it). Read both.
- A `controls` question adds `values` (`{"radius": 12, "hue": 174, "shadow": true}`). `selected` holds a
  preset only if the user kept it untouched; `from` names the preset they started from and then changed.
- `extra` appears when page JavaScript called `api.setExtra(...)`.
- Exit 0 `status: "chat"` (with `text`): the user pressed **Discuss in chat** — they want to talk it
  through in the terminal. Stop and ask there; do not pick for them.
- Exit 2 `status: "dismissed"`: closed unanswered (⌘W). Treat as "not now": don't re-open the same
  question in a loop; say what you need in the terminal.
- Exit 3: no way to show it — `status: "no-agterm"` (this session is not in agterm) or `"unattended"` (see
  [When to ask](#when-to-ask-with-a-page)). Ask in the terminal; in an unattended run don't ask at all.
- Exit 4 `status: "pending"`: still open after `--timeout` (see [Waiting](#waiting)).
- Exit 5 `status: "busy"`: the session already shows an overlay. With a `pageID`, it is a huddle page still
  open on this session — almost always your own earlier question, left pending by a timeout or a call that
  was cut off: `huddle wait <pageID>` for its answer before asking anything new. Without one, it belongs to
  another tool (a diff review, a plan annotation): ask in the terminal, and never close an overlay you did
  not open.
- Exit 1 `status: "error"`: the spec or agterm failed; the `error` says which, including a key the page would
  drop (with the one it probably meant) and an option that only counts. Fix the spec and ask again.

## Spec reference

Top level: `title`, `subtitle`, `source` (replaces "Claude is asking"), `context` (blocks),
`width: "narrow"` (for short questions), `submitLabel`, `chat: false` (hide Discuss in chat), `script`
(JS, see [Extending](#extending)), `style`, `review`, `size` (see [Look, size and review](#look-size-and-review)),
and **either** the fields of one question **or** `questions: [...]` (tabs, answered in order).

Question: `id`, `header`, `prompt`, `hint`, `body` (blocks; `context` works too), `recommendation` (markdown banner naming the
overall pick), `mode` (`single` default · `multi` · `text`; `tune` is implied by `controls`), `min`/`max`
(multi), `layout` (`list` · `grid` · `compare` · `inline`; default `grid` when any option has a
`preview`, `inline` for presets, else `list`), `columns`, `expanded: true` (open every option's details),
`optional: true` (may submit empty), `text` (`false` to drop the free-text box, or
`{label, placeholder, required, multiline, value}`).

Any other key, at any of these levels, is an error that names the nearest valid one, since the page would
drop it without a word. A key starting with `_` is yours (data for a `script`) and passes.

Option: `id`, `label`, `subtitle` (gray line), `recommended` (`true`, or a string = the reason, shown
under it), `badge` (replaces the "Recommended" word), `tags` (small chips: effort, risk), `pros`, `cons`,
`detail` (blocks, behind "details"), `preview` (a block shown as the card's visual), `default: true`
(preselected), `values` (on a `controls` question: a preset). Strings may stand in for options:
`"options": ["Yes", "No"]`.

### Controls (sliders with a live preview)

```json
{
  "title": "Dashboard cards",
  "prompt": "Tune the card style until it looks right",
  "controls": [
    {"id": "radius", "label": "Corner radius", "min": 0, "max": 28, "value": 8, "unit": "px"},
    {"id": "hue", "label": "Accent", "type": "hue", "value": 220},
    {"id": "speed", "label": "Duration", "min": 100, "max": 1200, "step": 20, "value": 300, "unit": "ms"},
    {"id": "weight", "label": "Title weight", "type": "select", "options": ["500", "600", "700"], "value": "600"},
    {"id": "shadow", "label": "Shadow", "type": "toggle", "value": false, "on": "0 6px 18px rgba(0,0,0,.3)", "off": "none"},
    {"id": "brand", "label": "Brand color", "type": "color", "value": "#0d9488"}
  ],
  "preview": {"html": "<div style='border-radius:var(--radius);background:hsl({hue} 65% 45%);box-shadow:{shadow};font-weight:{weight};transition:all var(--speed)'>Sample</div>"},
  "baseline": true,
  "options": [{"id": "soft", "label": "Soft", "values": {"radius": 14, "shadow": true}}]
}
```

- Control `type`: `range` (default; `min`, `max`, `step`, `unit`) · `hue` (0–360, rainbow track) ·
  `color` (picker, `#rrggbb`) · `select` (segmented, `options`) · `toggle` (`on`/`off` are the strings it
  substitutes; default `"1"`/`"0"`).
- In `preview` (any block), `{id}` is replaced by the raw value (`12`, `#0d9488`, `600`) and `var(--id)`
  carries the unit (`12px`, `300ms`). The preview re-renders on every change, which also replays CSS
  animations; `r` or the ⟳ button replays without a change.
- `baseline: true` (or a label string) shows the starting values beside the live one ("Now" | "Yours").
- `options` with `values` are presets: picking one moves the sliders.
- Each slider has ↺ to return to its starting value.
- Optional linking: a `preview` may read earlier answers on the same page — `{@qid}` is the option id
  chosen on question `qid` (comma-joined for multi), `{@qid.label}` its label, `{@qid.ctl}` a slider value
  from another controls question. Use it when the fine-tuning should apply to what was just picked
  (`demos/motion`); skip it when the questions are independent.

### Blocks

Used in `context`, `body`, `detail`, `preview`. A plain string is markdown (`**bold**`, `*em*`,
`` `code` ``, lists, `> quote`, `[link](https://…)`, fenced code). Any block takes `title`, `caption` and
`card: true`.

| Block | Shape |
| --- | --- |
| markdown | `"text"` or `{"md": "text"}` |
| diagram | `{"mermaid": "flowchart LR\n A --> B"}` — any mermaid type (flowchart, sequence, class, state, ER, gantt, gitGraph). In labels avoid `#` (starts an entity: `#1` truncates the line) and `%` (comment marker in gantt); add `todayMarker off` to a gantt |
| chart | `{"chart": {"type": "bar"\|"line"\|"area"\|"hbar"\|"donut"\|"pie", "labels": [...], "series": [{"name", "values", "color"}], "unit": " ms"}}` — `values` alone for one series. Optional: `title`, `highlight` (index or label; not donut/pie), `marks: [{"value", "label"}]` (threshold lines), `min`, `max`, `height`; donut/pie `colors`, `center`, `size`; hbar `labelWidth` |
| stat tiles | `{"stats": [{"label", "value", "delta", "good": true\|false\|null, "sub"}]}` |
| image | `{"image": "/abs/or/relative.png", "height": 160, "fit": "cover", "alt": "…"}` — local files are embedded (up to 8 MB); a missing one shows its alt text |
| code / diff | `{"code": "…", "lang": "ts", "start": 40}` (`start` numbers the lines), `{"diff": "@@ …\n+added\n-removed"}` |
| from a file | `{"file": "path", "lines": "40-62"}` in place of the text of `code`, `diff`, `md` or `mermaid` — see [Show the real code](#show-the-real-code) |
| table | `{"table": {"columns": [...], "rows": [[...]]}}`, `{"kv": {"key": "value"}}` |
| callout | `{"callout": "markdown", "tone": "ok"\|"warn"\|"bad"}` |
| design samples | `{"radius": 12}`, `{"gap": 16, "items": 4, "direction": "column"}`, `{"colors": ["#hex", {"name", "value"}]}`, `{"type": {"family", "size", "weight", "tracking", "text"}}`, `{"style": {css}, "text": "…"}` |
| layout | `{"row": [block, block]}` side by side; a list of blocks stacks |
| svg / html / js | see [Extending](#extending) |

## Extending

The standard components cover most questions. When a question needs something they don't — a real
component rendered in the user's product style, an animation, typography in a particular script, a
filterable list — build it into that question, not into the skill:

- `{"html": "…"}` / `{"svg": "…"}` — raw markup as a block or an option's `preview`. `<style>` and CSS
  animations work. Use the theme variables inside `style=`: `--fg`, `--bg`, `--accent`, `--ok`,
  `--warn`, `--bad`, `--magenta`, `--cyan`, `--muted`, `--line`, `--line-strong`, `--panel`, `--panel-2`.
  They follow the user's terminal theme; hardcode colors only when the color *is* the question.
- `{"js": "code"}` — runs as `function(el, api)`; draw into `el`. The top-level `script` runs once with
  `api`. `api.setExtra(questionId, value)` (returned as `extra`), `api.setText(questionId, text)`,
  `api.select(questionId, optionId)`, `api.submit()`, `api.block(spec)` / `api.chart(spec)` (render a
  standard block), `api.md(text)`, `api.css("--accent")` (resolved color).
- Prefer `controls` over hand-written sliders: they come with keyboard, reset, presets, baseline and the
  review screen for free.
- Escape nothing in normal fields — the runtime escapes text. `html`, `svg` and `js` are raw, and the page
  runs with agterm's bridge, which can type into terminals: never paste outside text (an issue body, a log
  line, a file you did not write) into them; put it in markdown or `code`. Source code goes in through
  `{"file": …}`, never pasted into `html`.

## How the user answers

Keys `1`–`9`, arrows, `Space`, `Enter`, `Tab` into the note; the page lists them in its footer and `?`
shows the rest. ⌘W dismisses. Nothing here needs explaining to the user.

## Look, size and review

Defaults come from `defaults.json` beside this file, overlaid by the user's own
`~/.config/huddle/defaults.json` (or `$HUDDLE_CONFIG`) — the user's file is where their preferences live,
so don't override them unless a question needs it. Per call, a flag or the same key in the spec wins:

- `style`: `refined` (soft cards) · `minimal` (hairline rows) · `bold` (big type, filled choice) ·
  `terminal` (monospace). `--style NAME`.
- `size`: percent of the session pane as a floating panel, `"auto"` (66–90% by content) or `"full"`.
  `--size N`, `--full`.
- `status`: `{"asking": [...], "answered": [...]}` — the `agtermctl session status` arguments set while
  the question is open and after it is answered (default `blocked` / `active`; add `--color`, `--shape`,
  or `--sound default` to hear a question arrive while you are in another session).
- `review`: the answer list shown before sending — each choice, a thumbnail of a visual one, slider
  values with the live preview, and the user's note. `auto` = when the page has several questions, or a
  note was typed on a choice question · `always` · `never`. `--review MODE`. Question tabs also show the
  answer so far ("Radius · 14 px + note").

## Behavior you can rely on

- Opens over **your** session (`$AGTERM_SESSION_ID`), never the one the user is looking at, and does not
  switch them to it unless you pass `--follow`. While it waits, the sidebar shows the amber blinking
  "asking" triangle (the same glyph a built-in question gets); it goes back to "working" when answered.
  Status hooks that post a "working" or "done" glyph at the end of a turn would cover a question still
  waiting in the background; the plugin's own Stop hook re-posts the asking glyph when a turn ends with a
  huddle page still open, set to clear when the user visits. `--no-status` leaves the glyph alone.
- `--chromeless` hides the overlay's title strip.
- Outside agterm it opens nothing (exit 3, `no-agterm`). With `--browser`, or `"browser": true` in the
  user's defaults, it serves the page on `127.0.0.1` and opens the default browser instead, inside agterm
  too; the answer comes back the same way, and closing the tab counts as dismissed. That path lives only as
  long as the command: no `--no-wait`, and a timed-out browser question cannot be resumed.
- `AGTERMCTL` points at `agtermctl` when it is not on `PATH`.
- Mermaid is downloaded once to `~/.cache/huddle/` on first use and checked against a pinned sha256 on
  every use; offline, or on a mismatch, diagrams show as source and stderr says why.
- Generated pages land in `$TMPDIR/huddle/` and are pruned after a day. `huddle render spec.json -o out.html`
  builds one without opening it (for checking a spec).

## Waiting

Default wait is 570 s so it fits one Bash call. When it exits 4 with `"status": "pending"`, the page is
still up: run `huddle wait <pageID>` to keep waiting. `huddle wait` is for that case (and a `busy` reply
naming your page); an answered question needs nothing more. If the Bash call runs past its own `timeout`
anyway, the question is not lost: in Claude Code 2.1.296 (measured in auto mode) the harness moves the
call to the background instead of killing it, and the answer arrives as its completion notice. For a question the user may take long over, run
`huddle … --no-wait` (prints the `pageID` at once) and later `huddle wait <pageID>`, or run the whole command
with the Bash tool's `run_in_background: true` — you are notified when the user answers. In the background,
add `--timeout 86400`: the 570 s default exists only for foreground calls. A question whose answer the next
step does not depend on can wait in the background while you do that step; one that decides what you do
next is asked in the foreground. A timed-out wait leaves the "asking" glyph up, since the question is still
open, set to clear when the user visits the session to answer or close it.

## Recommending

- Recommend when you have a view, and say **why** in the `recommended` string; mark more than one when
  more than one is genuinely good. Use `recommendation` for a one-line verdict above the options.
- Up to 6 options reads well; 7–9 only for lists of peers (versions, files).
- Subtitles carry the one fact that distinguishes an option; pros/cons carry the rest.
- Batch related questions into one page (`questions`) rather than opening several in a row.
