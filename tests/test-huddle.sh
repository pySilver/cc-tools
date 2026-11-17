#!/usr/bin/env bash
# huddle: the spec checks, the guards, file-sourced blocks, and every shipped template and demo
# rendering without a runtime error. Opens no overlay and no browser window.
set -euo pipefail

cd "$(dirname "$0")/.."
B=plugins/huddle/bin/huddle
SKILL=plugins/huddle/skills/huddle
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
# The real interpreter, resolved before HOME moves: a version-manager shim reads its config from HOME.
# Every call below passes -B: importing bin/huddle must not leave a __pycache__ in the plugin (and -I
# ignores PYTHONDONTWRITEBYTECODE).
PY=$(python3 -I -c 'import sys; print(sys.executable)')
# A private HOME keeps the mermaid cache and any personal defaults out of the run; agterm is unset
# so nothing can reach a real session.
export HOME="$WORK/home" TMPDIR="$WORK/tmp"
unset AGTERM_ENABLED AGTERM_SESSION_ID AGTERM_SOCKET CLAUDE_CODE_SESSION_ATTENDED
mkdir -p "$HOME" "$TMPDIR"

fails=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; fails=$((fails + 1)); }

# expect NAME CODE STATUS -- CMD...: CMD exits CODE and prints JSON whose status is STATUS.
expect() {
  local name=$1 code=$2 status=$3 out got
  shift 4
  set +e
  out=$("$@" 2>/dev/null)
  got=$?
  set -e
  if [ "$got" != "$code" ]; then fail "$name: exit $got, want $code: $out"; return; fi
  if ! printf '%s' "$out" | "$PY" -I -B -c 'import json,sys; sys.exit(json.load(sys.stdin).get("status") != sys.argv[1])' "$status"; then
    fail "$name: status is not $status: $out"; return
  fi
  pass "$name"
}

if "$PY" -I -B -c 'import ast,sys; ast.parse(open(sys.argv[1]).read(), sys.argv[1])' "$B"; then pass "bin/huddle parses"; else fail "bin/huddle parses"; fi
if [ -x "$B" ]; then pass "bin/huddle is executable"; else fail "bin/huddle is executable"; fi

# Every template and demo renders.
for f in "$SKILL"/templates/*.json "$SKILL"/demos/*.json; do
  n=$(basename "$f" .json)
  if "$PY" -I -B "$B" render "$f" -o "$WORK/$n.html" >/dev/null 2>"$WORK/$n.err"; then pass "render $n"; else fail "render $n: $(cat "$WORK/$n.err")"; fi
done

# Malformed specs fail with the JSON error contract, never a traceback.
bad() { printf '%s' "$2" > "$WORK/bad.json"; expect "rejects $1" 1 error -- "$PY" -I -B "$B" render "$WORK/bad.json" -o "$WORK/bad.html"; }
bad "invalid JSON" 'nope'
bad "a non-object question" '{"questions": ["x"]}'
bad "a non-list options" '{"prompt": "p", "options": "x"}'
bad "a non-object option" '{"prompt": "p", "options": [1]}'
bad "duplicate option ids" '{"prompt": "p", "options": ["a", "a"]}'
bad "duplicate question ids" '{"questions": [{"id": "x", "prompt": "a"}, {"id": "x", "prompt": "b"}]}'
bad "ten options" '{"prompt": "p", "options": ["1","2","3","4","5","6","7","8","9","10"]}'
bad "a missing prompt" '{"options": ["a"]}'
bad "a missing code file" '{"prompt": "p", "context": {"code": {"file": "no/such/file.py"}}}'
bad "a misspelled question key" '{"questions": [{"prompt": "p", "subtitel": "x", "options": ["Yes", "No"]}]}'
bad "a misspelled option key" '{"prompt": "p", "options": [{"label": "Yes", "detial": "x"}]}'
bad "options that only count" '{"prompt": "Approve?", "mode": "multi", "options": ["Story 1", "Story 2"]}'
bad "a counting label with nothing else" '{"prompt": "p", "options": [{"id": "a", "label": "Option A"}, {"id": "b", "label": "Cache it"}]}'
bad "lines past the end" "{\"prompt\": \"p\", \"context\": {\"code\": {\"file\": \"$PWD/$B\", \"lines\": \"9000-9001\"}}}"

# A counting label is fine once the option carries its text, and a key starting with "_" is the author's own.
printf '{"prompt": "Approve?", "_data": 1, "options": [{"label": "Story 1", "detail": "The operator approves by hand."}, "Yes"]}' > "$WORK/carried.json"
if "$PY" -I -B "$B" render "$WORK/carried.json" -o "$WORK/carried.html" >/dev/null; then pass "a counting label carrying its text passes"; else fail "a counting label carrying its text passes"; fi
# A question's own context is shown on the page (checked in the browser below).
printf '{"questions": [{"id": "a", "prompt": "First?", "context": "QCTX-MARKER-ONE", "options": ["Yes", "No"]}, {"id": "b", "prompt": "Second?", "body": "QCTX-MARKER-TWO", "options": ["Yes", "No"]}]}' > "$WORK/qctx.json"
"$PY" -I -B "$B" render "$WORK/qctx.json" -o "$WORK/qctx.html" >/dev/null

# Markdown an agent writes by habit, each case a page of its own (checked in the browser below). md-owner
# is the table of a page on 2026-11-16 that showed as raw "| | |" and "|---|---|" lines.
MDCASES=$(cat <<'PY'
import json, os, sys
cases = {
    "md-owner": "| | |\n|---|---|\n| Outcome | Lem builds Lem: each change ... |\n| Careful paths | `land.py`, `stories.py`, ... |",
    "md-header": "| Name | Value |\n| :--- | ---: |\n| a | **b** |",
    "md-pipe-code": "| Op | Note |\n|---|---|\n| `a|b` | x \\| y |",
    "md-no-delim": "a | b | c\nd | e | f",
    "md-hr": "above\n\n---\n\nbelow",
    "md-h4": "#### Deep heading\n##### Deeper",
    "md-nested": "- top\n  - child\n    more of the child\n- next",
    "md-tilde": "~~~\ncode here\n~~~",
    "md-task": "- [ ] open\n- [x] done",
    "md-plus": "+ one\n+ two",
    "md-start": "3. three\n4. four",
}
for name, text in cases.items():
    with open(os.path.join(sys.argv[1], name + ".json"), "w") as f:
        json.dump({"prompt": "p", "context": text, "options": ["Yes", "No"]}, f)
print(" ".join(cases))
PY
)
MDNAMES=$("$PY" -I -B -c "$MDCASES" "$WORK")
for n in $MDNAMES; do
  "$PY" -I -B "$B" render "$WORK/$n.json" -o "$WORK/$n.html" >/dev/null
done

# A table wider than the window, in a table block, in a key-value block and in markdown, and a grid
# of options whose preview holds a long path with no space in it (checked in the browser below).
WIDE=$(cat <<'PY'
import json, sys
cell = "a cell with a long text that needs room"
md = "| " + " | ".join(f"Column {i}" for i in range(10)) + " |\n|" + "---|" * 10 + "\n| " + " | ".join([cell] * 10) + " |"
path = "plugins/huddle/skills/huddle/" + "a_very_long_module_name_with_no_space_in_it_" * 4 + ".py"
spec = {"questions": [
    {"id": "t", "prompt": "Wide tables?", "context": [{"table": {"columns": [f"Column {i}" for i in range(10)], "rows": [[cell] * 10]}},
     {"kv": [["key", "/" + "x" * 300]]}, {"md": md}], "options": ["Yes", "No"]},
    {"id": "g", "prompt": "Which file?", "layout": "grid", "columns": 3,
     "options": [{"id": f"o{i}", "label": f"File {i}", "preview": {"md": f"`{path}`"}} for i in range(3)]}]}
json.dump(spec, open(sys.argv[1], "w"))
PY
)
"$PY" -I -B -c "$WIDE" "$WORK/wide.json"
"$PY" -I -B "$B" render "$WORK/wide.json" -o "$WORK/wide.html" >/dev/null

# An unattended run never opens anything.
expect "refuses an unattended run" 3 unattended -- env CLAUDE_CODE_SESSION_ATTENDED=0 "$PY" -I -B "$B" q "Which?" A B
# Outside agterm it opens nothing unless the browser is asked for: the agent runs huddle without checking first.
expect "exit 3 outside agterm" 3 no-agterm -- "$PY" -I -B "$B" q "Which?" A B

# {"file": …} blocks carry the file's own lines, numbered, under the path.
printf 'a\nb\nc\nd\n' > "$WORK/src.py"
printf '{"prompt": "p", "context": {"code": {"file": "src.py", "lines": "2-3"}}, "options": ["a"]}' > "$WORK/file.json"
"$PY" -I -B "$B" render "$WORK/file.json" -o "$WORK/file.html" >/dev/null
if "$PY" -I -B - "$WORK/file.html" <<'PY'
import json, re, sys
html = open(sys.argv[1], encoding="utf-8").read()
spec = json.loads(re.search(r'id="hd-spec">(.*?)</script>', html, re.S).group(1).replace("<\\/", "</"))
c = spec["context"]
sys.exit(not (c["code"] == "b\nc" and c["start"] == 2 and c["title"] == "src.py:2-3" and c["lang"] == "py"))
PY
then pass "code from a file"; else fail "code from a file"; fi

# `q` reads "*Label|subtitle|why".
if "$PY" -I -B - "$B" <<'PY'
import argparse, importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("huddle", sys.argv[1])
mod = importlib.util.module_from_spec(importlib.util.spec_from_loader("huddle", loader))
loader.exec_module(mod)
a = argparse.Namespace(prompt="Which?", options=["*Redis|runs already|no new service", "PG|one table", "*JWT"],
                       multi=False, context=None, title=None)
o = mod.quick_spec(a)["options"]
sys.exit(not (o[0]["recommended"] == "no new service" and o[0]["subtitle"] == "runs already"
              and "recommended" not in o[1] and o[2]["recommended"] is True))
PY
then pass "q option syntax"; else fail "q option syntax"; fi

# The agterm paths, with agtermctl stubbed: an agterm error ends a wait at once instead of after
# the full timeout, and an occupied overlay slot is exit 5, naming the page when it is a huddle page.
stub() {
  local name=$1 code=$2 status=$3
  shift 3
  expect "$name" "$code" "$status" -- "$PY" -I -B -c "$STUB" "$B" "$@"
}
STUB=$(cat <<'PY'
import importlib.machinery, importlib.util, json, os, sys, types
loader = importlib.machinery.SourceFileLoader("huddle", sys.argv[1])
mod = importlib.util.module_from_spec(importlib.util.spec_from_loader("huddle", loader))
loader.exec_module(mod)
scenario = sys.argv[2]
os.environ.update(AGTERM_SESSION_ID="S1", AGTERM_ENABLED="1")
os.environ.pop("AGTERM_WINDOW_ID", None)
mod.time.sleep = lambda s: None
calls = []
def reply(stdout, code=0):
    return types.SimpleNamespace(stdout=stdout, stderr="", returncode=code)
def outcome(o):
    return reply(json.dumps({"ok": True, "result": {"pageOutcome": {"pageID": "P1", "outcome": o, "value": json.dumps({"status": "answered", "answers": {}})}}}))
def tree(file):
    return reply(json.dumps({"ok": True, "result": {"tree": {"workspaces": [{"sessions": [
        {"id": "S1", "htmlOverlays": [{"file": file, "id": "P0"}]}]}]}}}))
def ctl(*args, check=True):
    calls.append(args)
    if scenario == "invalid":
        return reply('{"ok":false,"error":"invalid page id"}', 1)
    if scenario == "silent":
        if len(calls) > 5:
            sys.exit(9)  # still polling: the wait never gave up
        return reply("")
    if scenario == "answered":
        return outcome("pending") if len(calls) < 3 else outcome("submitted")
    if scenario == "dismissed":
        return outcome("dismissed")
    if args[0] == "tree":
        return tree(os.path.join(mod.OUTDIR, "x.html") if scenario == "busy-own" else "/elsewhere/review.html")
    return reply('{"ok":false,"error":"overlay already open"}', 1)
mod.ctl = ctl
if scenario.startswith("busy"):
    a = types.SimpleNamespace(follow=False, size=None, full=False, chromeless=False)
    mod.open_overlay("/x.html", a, {"prompt": "p"})
    sys.exit(8)  # open_overlay returned instead of exiting
sys.exit(mod.wait_page("P1", 30, status=False))
PY
)
stub "wait stops on an agterm error" 1 error invalid
stub "wait stops when agterm goes silent" 1 error silent
stub "wait returns the answer" 0 answered answered
stub "wait reports a dismissal" 2 dismissed dismissed
stub "busy names a pending huddle page" 5 busy busy-own
stub "busy with another tool's overlay" 5 busy busy-other
own=$("$PY" -I -B -c "$STUB" "$B" busy-own 2>/dev/null || true)  # exit 5 is the point; read what it printed
other=$("$PY" -I -B -c "$STUB" "$B" busy-other 2>/dev/null || true)
if printf '%s' "$own" | "$PY" -I -B -c 'import json,sys; sys.exit(json.load(sys.stdin).get("pageID") != "P0")' \
  && printf '%s' "$other" | "$PY" -I -B -c 'import json,sys; sys.exit("pageID" in json.load(sys.stdin))'; then
  pass "busy carries the page id only for a huddle page"
else
  fail "busy carries the page id only for a huddle page"
fi

# The asking glyph against status hooks. The plugin's async Stop hook acts only when a huddle page is open,
# re-posts the asking status (with --auto-reset) whenever another hook posted over it, and stops once the
# page is gone. Its hooks.json guard keeps Python out of sessions outside agterm and machines without it.
# A timed-out wait leaves a glyph that a visit clears.
GLYPH=$(cat <<'PY'
import importlib.machinery, importlib.util, json, os, sys, types
loader = importlib.machinery.SourceFileLoader("huddle", sys.argv[1])
mod = importlib.util.module_from_spec(importlib.util.spec_from_loader("huddle", loader))
loader.exec_module(mod)
scenario = sys.argv[2]
os.environ.update(AGTERM_SESSION_ID="S1", AGTERM_ENABLED="1")
for k in ("AGTERM_WINDOW_ID", "AGTERM_PANE_ID", "CLAUDE_CODE_SESSION_ATTENDED"):
    os.environ.pop(k, None)
now = [1000.0]
mod.time.time = lambda: now[0]
mod.time.sleep = lambda s: now.__setitem__(0, now[0] + s)
glyph = {"status": "blocked" if scenario == "already" else "active", "changed": now[0]}
page = {"open": scenario != "nopage"}
posts, looks = [], []
def reply(stdout, code=0):
    return types.SimpleNamespace(stdout=stdout, stderr="", returncode=code)
def ctl(*args, check=True):
    if args[:2] == ("session", "status"):
        posts.append(list(args[2:]))
        glyph.update(status=args[2], changed=now[0])
        return reply("ok")
    if args[0] == "tree":
        looks.append(now[0])
        if scenario == "race" and now[0] >= 1001 and not glyph.get("raced"):  # a slower Stop hook posts at t=1001
            glyph.update(status="active", changed=1001.0, raced=True)
        if scenario == "answered" and now[0] >= 1000.4:
            page["open"] = False
        overlays = [{"file": os.path.join(mod.OUTDIR, "x.html"), "id": "P1"}] if page["open"] else []
        return reply(json.dumps({"ok": True, "result": {"tree": {"workspaces": [{"sessions": [
            {"id": "S1", "status": glyph["status"], "statusChangedAt": glyph["changed"], "htmlOverlays": overlays}]}]}}}))
    return reply(json.dumps({"ok": True, "result": {"pageOutcome": {"pageID": "P1", "outcome": "pending"}}}))
mod.ctl = ctl
mod.agtermctl = lambda: "/usr/bin/true"  # in_agterm() also wants the binary; CI runners have none
mod.defaults = lambda: {}
mod.sys.stdin = types.SimpleNamespace(isatty=lambda: False, read=lambda: "{}")
if scenario == "timeout":
    code = mod.wait_page("P1", 60, status=True)
else:
    code = mod.hook_stop()
print(json.dumps({"code": code, "posts": posts, "looks": len(looks)}))
PY
)
glyph() { "$PY" -I -B -c "$GLYPH" "$B" "$1" 2>/dev/null | tail -1 || true; }
check() {  # check NAME SCENARIO PYTHON-EXPR-ON-r
  local got
  got=$(glyph "$2")
  if printf '%s' "$got" | "$PY" -I -B -c "import json,sys; r=json.load(sys.stdin); sys.exit(not ($3))"; then pass "$1"; else fail "$1: $got"; fi
}
check "Stop hook re-posts the question after a slower hook paints over it" race \
  '[p[:2] for p in r["posts"]] == [["blocked", "--auto-reset"], ["blocked", "--auto-reset"]]'
check "Stop hook stops once the page is answered" answered 'r["posts"] == [] and r["looks"] == 2'
check "Stop hook leaves an asking glyph alone" already 'r["posts"] == [] and r["looks"] == 5'
check "Stop hook does nothing without a huddle page" nopage 'r["posts"] == [] and r["looks"] == 1'
check "a timed-out question leaves a glyph that a visit clears" timeout \
  'r["code"] == 4 and r["posts"][-1][:2] == ["blocked", "--auto-reset"]'
nohook=$(env -u AGTERM_ENABLED "$PY" -I -B "$B" hook-stop < /dev/null; echo "rc=$?")
if [ "$nohook" = "rc=0" ]; then pass "Stop hook is silent and exits 0 outside agterm"; else fail "Stop hook outside agterm: $nohook"; fi
# The hooks.json command itself, run the way Claude Code runs a command with no args: through a shell.
HOOKCMD=$("$PY" -I -B -c 'import json,sys; print(json.load(open(sys.argv[1]))["hooks"]["Stop"][0]["hooks"][0]["command"])' plugins/huddle/hooks/hooks.json)
guard1=$(env -u AGTERM_SESSION_ID CLAUDE_PLUGIN_ROOT="$PWD/plugins/huddle" sh -c "$HOOKCMD" < /dev/null 2>&1; echo "rc=$?")
guard2=$(env AGTERM_SESSION_ID=S1 PATH=/nonexistent CLAUDE_PLUGIN_ROOT="$PWD/plugins/huddle" /bin/sh -c "$HOOKCMD" < /dev/null 2>&1; echo "rc=$?")
if [ "$guard1" = "rc=0" ] && [ "$guard2" = "rc=0" ]; then
  pass "hooks.json guard: silent exit 0 with no agterm session, and with no python3"
else
  fail "hooks.json guard: no session [$guard1], no python3 [$guard2]"
fi

# A whole file in a code block is capped; past the cap the spec has to name its lines.
"$PY" -I -B -c 'print("\n".join(f"x = {i}" for i in range(400)))' > "$WORK/long.py"
bad "a whole long file as code" "{\"prompt\": \"p\", \"context\": {\"code\": {\"file\": \"$WORK/long.py\"}}}"

# The runtime parses, and every rendered page loads with no error node and every diagram drawn.
if command -v node >/dev/null; then
  if node --check "$SKILL/runtime/huddle.js"; then pass "huddle.js parses"; else fail "huddle.js parses"; fi
else
  printf 'SKIP huddle.js syntax: node is not installed\n'
fi
DOMCHECK=$(cat <<'PY'
import sys
from html.parser import HTMLParser
class P(HTMLParser):
    def __init__(self):
        super().__init__(); self.script = 0; self.app = False; self.errors = 0; self.mermaid = 0; self.failed = 0; self.drawn = 0
    def handle_starttag(self, tag, attrs):
        a = dict(attrs); cls = (a.get("class") or "").split()
        self.script += tag == "script"
        if self.script:
            return
        self.app |= "hd" in cls
        self.errors += "hd-err" in cls
        self.mermaid += "hd-mermaid" in cls
        self.failed += "hd-mermaid" in cls and "err" in cls
        self.drawn += tag == "svg" and (a.get("id") or "").startswith("hd-mm-")
    def handle_endtag(self, tag):
        self.script -= tag == "script"
p = P(); p.feed(open(sys.argv[1], encoding="utf-8").read())
problems = []
if not p.app: problems.append("no app root")
if p.errors: problems.append(f"{p.errors} .hd-err node(s)")
if sys.argv[2] == "required" and (p.failed or p.drawn != p.mermaid):
    problems.append(f"{p.drawn} of {p.mermaid} diagram(s) drawn")
print("; ".join(problems))
sys.exit(bool(problems))
PY
)
# PROBE PAGE COPY: COPY is PAGE with a script that measures, at each of its two questions, the
# page's width against its window and each preview of the current question against its card.
PROBE=$(cat <<'PY'
import sys
page = open(sys.argv[1], encoding="utf-8").read()
probe = """<script>setTimeout(() => {
  const d = document.documentElement, out = {};
  const look = () => ({page: [d.scrollWidth, d.clientWidth], prev: [...document.querySelectorAll(".hd-q.cur .hd-prev")].map(n => [n.scrollWidth, n.clientWidth])});
  out.tables = look();
  [...document.querySelectorAll(".hd-q")].forEach((q, i) => q.classList.toggle("cur", i === 1));
  setTimeout(() => { out.grid = look(); d.setAttribute("data-measure", JSON.stringify(out)); }, 300);
}, 1500);</script>"""
open(sys.argv[2], "w", encoding="utf-8").write(page.replace("</body>", probe + "</body>", 1))
PY
)
MEASURED=$(cat <<'PY'
import html, json, re, sys
found = re.search(r'data-measure="([^"]*)"', open(sys.argv[1], encoding="utf-8").read())
if not found:
    sys.exit("the probe wrote nothing")
m = json.loads(html.unescape(found.group(1)))
wrong = [f"the page of the {k} is {m[k]['page'][0]} px wide in a window of {m[k]['page'][1]}" for k in ("tables", "grid") if m[k]["page"][0] > m[k]["page"][1]]
wrong += [f"a preview of the grid is {w} px wide in a card of {c}" for w, c in m["grid"]["prev"] if w > c]
wrong += [] if len(m["grid"]["prev"]) == 3 else [f"the grid has {len(m['grid']['prev'])} previews, not 3"]
print("; ".join(wrong))
sys.exit(bool(wrong))
PY
)
MDCHECK=$(cat <<'PY'
import sys
from html.parser import HTMLParser
VOID = {"br", "hr", "img", "input", "meta", "link", "col", "area", "base", "embed", "source", "track", "wbr"}
class Node:
    def __init__(self, tag, attrs):
        self.tag, self.attrs, self.kids = tag, dict(attrs), []
    def text(self):
        return "".join(k if isinstance(k, str) else k.text() for k in self.kids)
    def find(self, tag):
        out = []
        for k in self.kids:
            if not isinstance(k, str):
                out += [k] if k.tag == tag else []
                out += k.find(tag)
        return out
    def els(self):
        return [k for k in self.kids if not isinstance(k, str)]
class P(HTMLParser):
    def __init__(self):
        super().__init__(); self.root = Node("root", []); self.stack = [self.root]
    def handle_starttag(self, tag, attrs):
        n = Node(tag, attrs); self.stack[-1].kids.append(n)
        if tag not in VOID:
            self.stack.append(n)
    def handle_endtag(self, tag):
        for i in range(len(self.stack) - 1, 0, -1):
            if self.stack[i].tag == tag:
                del self.stack[i:]; break
    def handle_data(self, data):
        if self.stack[-1].tag not in ("script", "style"):
            self.stack[-1].kids.append(data)
p = P(); p.feed(open(sys.argv[1], encoding="utf-8").read())
page, case = p.root, sys.argv[2]
texts = lambda nodes: [n.text().strip() for n in nodes]
tables = page.find("table")
bad = []
def want(cond, why):
    if not cond:
        bad.append(why)
if case == "md-owner":
    want(len(tables) == 1, f"{len(tables)} tables")
    if tables:
        t = tables[0]
        want(t.find("th") == [], "a header row of empty cells")
        rows = t.find("tr")
        want([texts(r.find("td"))[0] for r in rows] == ["Outcome", "Careful paths"], f"rows {[texts(r.find('td')) for r in rows]}")
        want(texts(t.find("code")) == ["land.py", "stories.py"], f"code {texts(t.find('code'))}")
    shown = page.text()
    want("|---" not in shown and "| |" not in shown and "| Outcome" not in shown, "raw table text on the page")
elif case == "md-header":
    want(len(tables) == 1, f"{len(tables)} tables")
    if tables:
        t = tables[0]
        want(texts(t.find("th")) == ["Name", "Value"], f"header {texts(t.find('th'))}")
        want(texts(t.find("td")) == ["a", "b"] and texts(t.find("b")) == ["b"], f"cells {texts(t.find('td'))}")
        want("right" in t.find("td")[1].attrs.get("style", "") if len(t.find("td")) > 1 else False, "the ---: column is not right-aligned")
elif case == "md-pipe-code":
    tds = tables[0].find("tr")[-1].find("td") if tables else []
    want(len(tds) == 2, f"{len(tds)} cells in the row")
    if len(tds) == 2:
        want(texts(tds[0].find("code")) == ["a|b"], f"code {texts(tds[0].find('code'))}")
        want(tds[1].text().strip() == "x | y", f"escaped pipe cell {tds[1].text()!r}")
elif case == "md-no-delim":
    want(tables == [], "a table with no delimiter line")
    want(any("a | b | c" in t for t in texts(page.find("p"))), "the lines are not a paragraph")
elif case == "md-hr":
    want(len(page.find("hr")) == 1, f"{len(page.find('hr'))} rules")
    want("---" not in page.text(), "raw --- on the page")
elif case == "md-h4":
    want(texts(page.find("h4")) == ["Deep heading"] and texts(page.find("h5")) == ["Deeper"], "no h4 and h5")
    want("####" not in page.text(), "raw #### on the page")
elif case == "md-nested":
    top = [u for u in page.find("ul") if any(li.text().startswith("top") for li in u.els())]
    want(len(top) == 1 and len(top[0].els()) == 2, "the outer list has not two items")
    if top:
        inner = top[0].els()[0].find("ul")
        want(len(inner) == 1 and "child" in inner[0].text() and "more of the child" in inner[0].text(), "the child is not a list in the first item")
elif case == "md-tilde":
    pres = [x for x in page.find("pre") if x.text() == "code here"]
    want(len(pres) == 1, "no code block")
    want("~~~" not in page.text(), "raw ~~~ on the page")
elif case == "md-task":
    shown = page.text()
    want("[ ]" not in shown and "[x]" not in shown, "raw task boxes on the page")
    want("☐" in shown and "☑" in shown, "no box glyphs")
elif case == "md-plus":
    want(any(texts(u.els()) == ["one", "two"] for u in page.find("ul")), "no list of two items")
elif case == "md-start":
    ols = page.find("ol")
    want(len(ols) == 1 and ols[0].attrs.get("start") == "3", "the list does not start at 3")
said = {
    "md-owner": "a table with an empty header row renders its rows and code, and no raw |---|",
    "md-header": "a table with a header row renders it, with the alignment marks",
    "md-pipe-code": "a pipe in a code span, or escaped, stays in its cell",
    "md-no-delim": "lines with pipes and no delimiter line stay a paragraph",
    "md-hr": "a --- line is a rule",
    "md-h4": "a heading of level 4 or 5 is a heading",
    "md-nested": "an indented item is a list in its parent item",
    "md-tilde": "a ~~~ fence is a code block",
    "md-task": "a task item shows a box",
    "md-plus": "a + item is a list item",
    "md-start": "an ordered list keeps its first number",
}[case]
print(f"markdown {case}: " + ("; ".join(bad) if bad else said))
sys.exit(bool(bad))
PY
)
chrome=""
for c in google-chrome chromium chromium-browser "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"; do
  if command -v "$c" >/dev/null 2>&1 || [ -x "$c" ]; then chrome=$c; break; fi
done
if [ -n "$chrome" ]; then
  for f in "$WORK"/*.html; do
    n=$(basename "$f" .html)
    case $n in bad) continue ;; esac
    # No network means no mermaid bundle, and diagrams show as source by design: say so, don't pass it.
    diagrams=required
    if grep -q 'mermaid unavailable' "$WORK/$n.err" 2>/dev/null; then
      diagrams=skip
      printf 'SKIP diagrams on %s: the mermaid bundle could not be downloaded\n' "$n"
    fi
    "$chrome" --headless=new --disable-gpu --no-sandbox --no-first-run --use-mock-keychain --user-data-dir="$WORK/chrome" \
      --virtual-time-budget=4000 --dump-dom "file://$f" > "$WORK/$n.dom" 2>/dev/null || true
    if why=$("$PY" -I -B -c "$DOMCHECK" "$WORK/$n.dom" "$diagrams"); then
      pass "page loads: $n"
    else
      fail "page loads: $n ($why)"
    fi
  done
  if "$PY" -I -B - "$WORK/qctx.dom" <<'PY'
import sys
from html.parser import HTMLParser
class P(HTMLParser):
    def __init__(self):
        super().__init__(); self.script = 0; self.text = []
    def handle_starttag(self, tag, attrs):
        self.script += tag == "script"
    def handle_endtag(self, tag):
        self.script -= tag == "script"
    def handle_data(self, data):
        if not self.script:
            self.text.append(data)
p = P(); p.feed(open(sys.argv[1], encoding="utf-8").read())
shown = " ".join(p.text)
sys.exit(not ("QCTX-MARKER-ONE" in shown and "QCTX-MARKER-TWO" in shown))
PY
  then pass "a question's own context and body are shown"; else fail "a question's own context and body are shown"; fi
  for n in $MDNAMES; do
    if why=$("$PY" -I -B -c "$MDCHECK" "$WORK/$n.dom" "$n"); then pass "$why"; else fail "$why"; fi
  done
  # At 900 px a wide table scrolls inside its own box and the page stays as wide as its window; the
  # grid's previews keep their path inside the card. A script added to a copy of the page measures
  # both questions of the spec and writes the numbers into the page Chrome prints.
  mkdir -p "$WORK/measure"
  "$PY" -I -B -c "$PROBE" "$WORK/wide.html" "$WORK/measure/wide.html"
  "$chrome" --headless=new --disable-gpu --no-sandbox --no-first-run --use-mock-keychain --user-data-dir="$WORK/chrome" \
    --window-size=900,900 --virtual-time-budget=4000 --dump-dom "file://$WORK/measure/wide.html" > "$WORK/measure/wide.dom" 2>/dev/null || true
  if why=$("$PY" -I -B -c "$MEASURED" "$WORK/measure/wide.dom"); then
    pass "at 900 px a wide table scrolls inside its own box and the page is no wider than its window; a long path in a grid's preview breaks inside the card"
  else
    fail "a wide table or a long path: $why"
  fi
else
  printf 'SKIP page loads: no Chrome or Chromium found\n'
fi

if [ "$fails" -gt 0 ]; then
  printf '%d huddle check(s) failed\n' "$fails"
  exit 1
fi
printf 'all huddle checks passed\n'
