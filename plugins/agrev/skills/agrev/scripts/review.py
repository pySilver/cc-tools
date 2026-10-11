#!/usr/bin/env python3
"""Review a markdown document in plannotator, shown in an agterm session beside the agent's.

    review.py open FILE [--comments JSON] [--here] [--no-follow]
    review.py wait FILE
    review.py comment FILE                  JSON {"quote", "text"} or a list of them on stdin
    review.py status FILE
    review.py close FILE

plannotator (https://github.com/backnotprop/plannotator) owns the review page: annotation, version
history and "Show changes", Approve / Send / Close. This wrapper adds three things it lacks here.

- Placement. plannotator opens a browser; agterm shows a page as an overlay. PLANNOTATOR_BROWSER
  names scripts/record-url.sh, which only records the URL, and the page opens in a session of its
  own right after the caller's, so the chat is never covered.
- Cookies. plannotator keeps its settings and first-run flags in cookies, and an agterm overlay
  starts with empty storage every time, so each review would open on the onboarding dialogs. A
  small proxy in front of plannotator hands the page the cookies saved from earlier reviews and
  saves whatever the page sets. Everything else passes through untouched; plannotator checks no
  Host or Origin, so nothing is rewritten.
- The agent's voice. Comments the agent posts through plannotator's external-annotations API
  appear live in the page, pinned to a phrase, tagged with their source.

A review is one round: plannotator returns the reviewer's decision once, when they press Approve,
Send Annotations or Close. Each round gets its own run directory under ~/.cache/agrev/runs/.
"""

import argparse
import datetime as dt
import hashlib
import http.client
import json
import os
import random
import re
import shutil
import signal
import string
import subprocess
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SKILL = Path(__file__).resolve().parent.parent
ROOT = Path.home() / ".cache" / "agrev"
RUNS = ROOT / "runs"
DOCS = ROOT / "docs"
COOKIES = ROOT / "plannotator-cookies.json"
SOURCE = "Claude"                      # the badge plannotator shows on the agent's comments
READY_WAIT = dt.timedelta(seconds=20)
KEEP_RUNS = dt.timedelta(days=14)
COOKIE_PATH = "/___agrev/cookies"   # the proxy's own endpoint; plannotator has nothing there


class Fail(Exception):
    pass


def now() -> float:
    return time.time()


def write_atomic(path: Path, data: bytes) -> None:
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_bytes(data)
    tmp.replace(path)


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def doc_dir(path: Path) -> Path:
    d = DOCS / hashlib.sha256(str(path).encode()).hexdigest()[:16]
    d.mkdir(parents=True, exist_ok=True)
    return d


def alive(pid: "int | None") -> bool:
    if not pid:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def display_path(path: Path) -> str:
    proc = subprocess.run(["git", "-C", str(path.parent), "rev-parse", "--show-toplevel"],
                          capture_output=True, text=True, check=False)
    if proc.returncode == 0:
        try:
            return str(path.relative_to(Path(proc.stdout.strip()).resolve()))
        except ValueError:
            pass
    return str(path)


# ---- agterm -------------------------------------------------------------------------------------


def agtermctl(*args: str) -> dict:
    exe = os.environ.get("AGTERMCTL")
    if not exe:
        bundle = os.environ.get("GHOSTTY_BIN_DIR")
        exe = os.path.join(bundle, "agtermctl") if bundle and os.access(os.path.join(bundle, "agtermctl"), os.X_OK) \
            else shutil.which("agtermctl")
    if not exe:
        raise Fail("agtermctl not found")
    cmd = [exe, *args, "--json"] + (["--socket", os.environ["AGTERM_SOCKET"]] if os.environ.get("AGTERM_SOCKET") else [])
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    try:
        reply = json.loads(proc.stdout or proc.stderr or "{}")
    except ValueError:
        reply = {"error": (proc.stdout + proc.stderr).strip()}
    if proc.returncode:
        err = reply.get("error")
        raise Fail(f"agtermctl {' '.join(args[:3])}: {err.get('message') if isinstance(err, dict) else err}")
    return reply.get("result") or {}


def sessions(wid: "str | None") -> "list[dict]":
    tree = agtermctl("tree", *(["--window", wid] if wid else [])).get("tree", {})
    return [s for ws in tree.get("workspaces", []) for s in ws.get("sessions", [])]


def review_session(path: Path, wid: "str | None", caller: str) -> str:
    """The document's own session, right after the caller's; reused by the id recorded last time."""
    place = doc_dir(path) / "placement.json"
    live = sessions(wid)
    if place.exists():
        sid = read_json(place).get("session", "")
        if any(s["id"].lower() == sid.lower() for s in live):
            return sid
    name = f"{path.name} review"
    named = [s for s in live if s.get("name") == name]
    sid = named[0]["id"] if named else agtermctl(
        "session", "new", "--cwd", str(path.parent), "--name", name, "--after", caller, "--no-select",
        *(["--window", wid] if wid else [])).get("id")
    if not sid:
        raise Fail("agterm created no review session")
    write_atomic(place, json.dumps({"window": wid, "session": sid}).encode())
    return sid


def shown_url(sid: str, wid: "str | None") -> "str | None":
    for s in sessions(wid):
        if s["id"].lower() == sid.lower():
            for o in s.get("htmlOverlays") or []:
                if not o.get("pane"):
                    return o.get("url") or o.get("page") or ""
    return None


# ---- the cookie proxy ---------------------------------------------------------------------------

_HOP = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization", "te", "trailers",
        "transfer-encoding", "upgrade", "content-length", "accept-encoding", "host"}


def load_cookies() -> "dict[str, str]":
    try:
        return read_json(COOKIES)
    except (FileNotFoundError, ValueError):
        return {}


def cookie_script(saved: "dict[str, str]") -> bytes:
    """Runs first in the page: restore the saved cookies, then report every change back.

    Set-Cookie on the response carries the same values; the script repeats them because a web view
    may not expose response cookies to document.cookie before the page's own scripts read it.
    """
    payload = json.dumps(saved).replace("<", "\\u003c")
    return (
        "<script>(function(){var s=" + payload + ";"
        "for(var k in s){document.cookie=k+'='+s[k]+'; path=/; max-age=31536000; samesite=lax';}"
        "var last=document.cookie;"
        "function push(){var c=document.cookie;if(c===last)return;last=c;"
        "try{fetch('" + COOKIE_PATH + "',{method:'POST',body:c,keepalive:true});}catch(e){}}"
        "setInterval(push,1000);addEventListener('pagehide',push);addEventListener('visibilitychange',push);"
        "})();</script>"
    ).encode()


def make_proxy(upstream: str):
    up = urllib.parse.urlparse(upstream)

    class Proxy(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.0"  # one response per connection; streams end when upstream does

        def log_message(self, fmt, *args):
            pass

        def _cookies_post(self) -> None:
            n = int(self.headers.get("Content-Length") or 0)
            jar = load_cookies()
            for part in self.rfile.read(n).decode("utf-8", "replace").split(";"):
                if "=" in part:
                    k, v = part.strip().split("=", 1)
                    if k.startswith("plannotator-"):
                        jar[k] = v
            ROOT.mkdir(parents=True, exist_ok=True)
            write_atomic(COOKIES, json.dumps(jar, indent=1, sort_keys=True).encode())
            self.send_response(204)
            self.end_headers()

        def _forward(self) -> None:
            if self.command == "POST" and self.path == COOKIE_PATH:
                return self._cookies_post()
            body = None
            if self.headers.get("Content-Length"):
                body = self.rfile.read(int(self.headers["Content-Length"]))
            headers = {k: v for k, v in self.headers.items() if k.lower() not in _HOP}
            headers["Host"] = up.netloc
            headers["Accept-Encoding"] = "identity"
            conn = http.client.HTTPConnection(up.hostname, up.port, timeout=3600)
            try:
                conn.request(self.command, self.path, body=body, headers=headers)
                resp = conn.getresponse()
            except OSError as exc:
                self.send_error(502, f"plannotator unreachable: {exc}")
                return
            ctype = resp.getheader("Content-Type") or ""
            page = self.command == "GET" and ctype.startswith("text/html")
            self.send_response(resp.status, resp.reason)
            for k, v in resp.getheaders():
                if k.lower() not in _HOP and not (page and k.lower() == "content-length"):
                    self.send_header(k, v)
            if page:
                saved = load_cookies()
                for k, v in saved.items():
                    self.send_header("Set-Cookie", f"{k}={v}; Path=/; Max-Age=31536000; SameSite=Lax")
                html = resp.read()
                at = html.find(b"<head>")
                at = at + len(b"<head>") if at >= 0 else 0
                out = html[:at] + cookie_script(saved) + html[at:]
                self.send_header("Content-Length", str(len(out)))
                self.end_headers()
                self.wfile.write(out)
                return
            if resp.getheader("Content-Length"):
                self.send_header("Content-Length", resp.getheader("Content-Length"))
            self.end_headers()
            try:
                while True:  # stream: server-sent events must not wait for the end of the response
                    chunk = resp.read1(65536)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
            finally:
                conn.close()

        do_GET = do_POST = do_PATCH = do_DELETE = do_PUT = do_HEAD = _forward

    return Proxy


def serve_proxy(run: Path) -> None:
    """Runs detached for one review; exits when plannotator does."""
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    meta = read_json(run / "meta.json")
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), make_proxy(meta["upstream"]))
    httpd.daemon_threads = True
    write_atomic(run / "proxy.json", json.dumps({"pid": os.getpid(), "port": httpd.server_address[1]}).encode())

    def watch() -> None:
        while alive(meta["plannotator_pid"]):
            time.sleep(1)
        time.sleep(3)  # let the page fetch its closing screen
        httpd.shutdown()

    threading.Thread(target=watch, daemon=True).start()
    httpd.serve_forever(poll_interval=0.5)


# ---- runs ---------------------------------------------------------------------------------------


def current_run(path: Path) -> Path:
    """The document's latest round. Only the round's name is recorded, so the cache can move; a round
    pruned away, or never opened, reads as no review at all."""
    f = doc_dir(path) / "current.json"
    run = RUNS / Path(read_json(f)["run"]).name if f.exists() else None
    if run is None or not (run / "meta.json").exists():
        raise Fail(f"no review of {path} is on record")
    return run


def prune_runs() -> None:
    if RUNS.is_dir():
        cutoff = now() - KEEP_RUNS.total_seconds()
        for r in RUNS.iterdir():
            if r.is_dir() and r.stat().st_mtime < cutoff:
                shutil.rmtree(r, ignore_errors=True)


def remember_comments(run: Path, items: "list[dict]") -> None:
    """plannotator exports the agent's comments as if the reviewer wrote them; keep the agent's own list."""
    f = run / "agent-comments.json"
    mine = read_json(f) if f.exists() else []
    mine += [(it.get("text") or "").strip() for it in items]
    write_atomic(f, json.dumps(mine, indent=1, ensure_ascii=False).encode())


_FLAT = re.compile(r"\s+")


def strip_agent_items(feedback: str, mine: "list[str]") -> "tuple[str, int]":
    """Drop the feedback items whose text is one of the agent's own comments, and renumber the rest.

    plannotator writes each item as "## N. <where>" followed by "> " quoted lines.
    """
    if not mine or "\n## " not in feedback:
        return feedback, 0
    own = {_FLAT.sub(" ", m).strip() for m in mine}
    head, *items = re.split(r"\n(?=## \d+\. )", feedback)
    kept, dropped = [], 0
    for item in items:
        body = " ".join(line[1:].strip() for line in item.splitlines() if line.startswith(">"))
        if _FLAT.sub(" ", body).strip() in own:
            dropped += 1
        else:
            kept.append(item)
    tail = ""
    if kept and "\n---" in kept[-1]:
        kept[-1], tail = kept[-1].split("\n---", 1)
        tail = "\n---" + tail
    renumbered = [re.sub(r"^## \d+\. ", f"## {i}. ", it) for i, it in enumerate(kept, 1)]
    head = re.sub(r"have \d+ pieces? of feedback", f"have {len(kept)} piece{'' if len(kept) == 1 else 's'} of feedback", head)
    return "\n".join([head, *renumbered]) + tail, dropped


def post_comments(upstream: str, items: "list[dict]") -> "list[str]":
    """Pin the agent's comments to phrases of the document, live in the open page."""
    anns = []
    for it in items:
        text = (it.get("text") or "").strip()
        if not text:
            raise Fail("a comment needs text")
        quote = (it.get("quote") or "").strip()
        anns.append({"source": SOURCE, "type": "COMMENT", "originalText": quote, "text": text} if quote
                    else {"source": SOURCE, "type": "GLOBAL_COMMENT", "text": text})
    up = urllib.parse.urlparse(upstream)
    conn = http.client.HTTPConnection(up.hostname, up.port, timeout=10)
    conn.request("POST", "/api/external-annotations", body=json.dumps({"annotations": anns}),
                 headers={"Content-Type": "application/json"})
    resp = conn.getresponse()
    reply = json.loads(resp.read() or b"{}")
    if resp.status >= 300:
        raise Fail(f"plannotator refused the comments: {reply.get('error') or resp.status}")
    return reply.get("ids", [])


def cmd_open(ns) -> int:
    path = Path(ns.file).expanduser().resolve()
    if not path.is_file():
        raise Fail(f"no such file: {ns.file}")
    caller = os.environ.get("AGTERM_SESSION_ID")
    if os.environ.get("AGTERM_ENABLED") != "1" or not caller:
        raise Fail("needs an agterm session: run it from a shell inside agterm")
    exe = shutil.which("plannotator") or str(Path.home() / ".local/bin/plannotator")
    if not os.access(exe, os.X_OK):
        raise Fail("plannotator is not installed: curl -fsSL https://plannotator.ai/install.sh | bash -s -- --minimal")
    comments = json.loads(Path(ns.comments).read_text()) if ns.comments else []
    if isinstance(comments, dict):
        comments = [comments]
    try:
        old = current_run(path)
    except Fail:
        old = None
    if old and alive(read_json(old / "meta.json").get("plannotator_pid")) and not (old / "result.json").exists():
        raise Fail(f"a review of {path.name} is already open (run {old}); wait for it or close it")

    prune_runs()
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    run = RUNS / f"{stamp}-{''.join(random.choices(string.ascii_lowercase + string.digits, k=4))}"
    run.mkdir(parents=True)
    env = dict(os.environ, PLANNOTATOR_BROWSER=str(SKILL / "scripts" / "record-url.sh"), AGREV_READY=str(run / "ready"))
    log = open(run / "plannotator.log", "ab")
    proc = subprocess.Popen(
        [exe, "annotate", str(path), "--gate", "--json", "--result-file", str(run / "result.json")],
        cwd=str(path.parent), env=env, stdin=subprocess.DEVNULL, stdout=open(run / "stdout.json", "ab"),
        stderr=log, start_new_session=True)
    deadline = now() + READY_WAIT.total_seconds()
    while not (run / "ready").exists() or not (run / "ready").read_text().strip():
        if proc.poll() is not None or now() > deadline:
            raise Fail(f"plannotator did not start; see {run / 'plannotator.log'}")
        time.sleep(0.1)
    upstream = (run / "ready").read_text().strip()
    meta = {"file": str(path), "display": display_path(path), "upstream": upstream,
            "plannotator_pid": proc.pid, "run": str(run), "opened": now()}
    write_atomic(run / "meta.json", json.dumps(meta, indent=1).encode())
    write_atomic(doc_dir(path) / "current.json", json.dumps({"run": run.name}).encode())

    subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "proxy", str(run)],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=open(run / "proxy.log", "ab"),
                     start_new_session=True)
    while not (run / "proxy.json").exists():
        if now() > deadline:
            raise Fail(f"the cookie proxy did not start; see {run / 'proxy.log'}")
        time.sleep(0.05)
    port = read_json(run / "proxy.json")["port"]

    if comments:
        post_comments(upstream, comments)
        remember_comments(run, comments)

    wid = os.environ.get("AGTERM_WINDOW_ID")
    target = caller if ns.here else review_session(path, wid, caller)
    if shown_url(target, wid) is not None:
        agtermctl("session", "overlay", "close", "--target", target, *(["--window", wid] if wid else []))
    agtermctl("session", "overlay", "open", "--url", f"http://127.0.0.1:{port}/", "--js", "--target", target,
              *(["--window", wid] if wid else []))
    meta["session"] = target
    write_atomic(run / "meta.json", json.dumps(meta, indent=1).encode())
    if not ns.no_follow:
        agtermctl("session", "select", "--target", target, *(["--window", wid] if wid else []))
    where = "over this session" if ns.here else f'in the session "{path.name} review", right after this one'
    print(f"agrev: {meta['display']} is open in plannotator {where}"
          + (f", with {len(comments)} comment(s) from you pinned in it." if comments else "."))
    print(f"Now run in the background: {Path(__file__).resolve()} wait {path}")
    return 0


def cmd_wait(ns) -> int:
    path = Path(ns.file).expanduser().resolve()
    run = current_run(path)
    meta = read_json(run / "meta.json")
    result = run / "result.json"
    while not result.exists():
        if not alive(meta["plannotator_pid"]):
            time.sleep(0.5)  # the result file is published just before plannotator exits
            if not result.exists():
                print(f"agrev: plannotator ended without a decision for {meta['display']} (see {run / 'plannotator.log'}).")
                return 2
            break
        time.sleep(0.5)
    decision = json.loads(result.read_text() or "{}")
    kind = decision.get("decision")
    mine = read_json(run / "agent-comments.json") if (run / "agent-comments.json").exists() else []
    feedback, dropped = strip_agent_items((decision.get("feedback") or "").strip(), mine)
    if mine and dropped < len(mine):
        print(f"agrev: NOTE {len(mine) - dropped} of your own {len(mine)} comment(s) were not found in the "
              "feedback; the reviewer may have deleted them, or plannotator changed its export format, so any "
              "item below that repeats your words is yours, not the reviewer's.")
    if meta.get("session"):
        try:
            show_outcome(run, meta, kind, count=len(re.findall(r"^## \d+\. ", feedback, re.M)))
        except Fail:
            pass
    if kind == "approved":
        print(f"agrev: APPROVED {meta['display']}" + (" with notes:" if feedback else "."))
    elif kind == "annotated":
        print(f"agrev: CHANGES REQUESTED on {meta['display']}:")
    else:
        print(f"agrev: the review of {meta['display']} was closed without a decision.")
        return 2
    if feedback:
        print()
        print(feedback)
    return 0


OUTCOME_PAGE = """<!doctype html><html><head><meta charset="utf-8"><title>{title}</title><style>
body {{ margin: 0; height: 100vh; display: grid; place-items: center; font: 15px/1.6 -apple-system, sans-serif;
  background: var(--agterm-background, Canvas); color: var(--agterm-foreground, CanvasText); }}
.card {{ max-width: 520px; padding: 28px 32px; border-radius: 14px; text-align: center;
  border: 1px solid color-mix(in srgb, var(--agterm-foreground, CanvasText) 15%, transparent);
  background: color-mix(in srgb, var(--agterm-foreground, CanvasText) 5%, transparent); }}
h1 {{ font-size: 19px; margin: 0 0 8px; }} p {{ margin: 0; opacity: .75; }}
.dot {{ display: inline-block; width: 9px; height: 9px; border-radius: 50%; margin-right: 8px;
  background: var(--agterm-color-{color}, gray); }}
</style></head><body><div class="card"><h1><span class="dot"></span>{title}</h1><p>{body}</p></div></body></html>"""


def show_outcome(run: Path, meta: dict, kind: "str | None", count: int) -> None:
    """Replace the finished plannotator page, whose server is gone, with what happens next.

    Feedback leaves a page saying the next round opens here, so the session never goes blank
    between rounds; an approval says the review is done; a Close leaves the session as the user
    left it.
    """
    sid, wid = meta["session"], os.environ.get("AGTERM_WINDOW_ID")
    if shown_url(sid, wid) is not None:
        agtermctl("session", "overlay", "close", "--target", sid)
    if kind == "annotated":
        noun = "item" if count == 1 else "items"
        title, color = "Feedback sent", "5"
        body = (f"{count} {noun} went to Claude, who is revising {Path(meta['file']).name}. "
                "The next round opens here, showing what changed.")
    elif kind == "approved":
        title, color = "Approved", "2"
        body = f"The review of {Path(meta['file']).name} is done."
    else:
        return
    page = run / "outcome.html"
    page.write_text(OUTCOME_PAGE.format(title=title, body=body, color=color), encoding="utf-8")
    agtermctl("session", "overlay", "open", "--html", str(page), "--target", sid)


def cmd_comment(ns) -> int:
    path = Path(ns.file).expanduser().resolve()
    run = current_run(path)
    meta = read_json(run / "meta.json")
    if not alive(meta["plannotator_pid"]):
        raise Fail("the review page is closed; pass the comments to the next `open --comments` instead")
    items = json.loads(sys.stdin.read())
    items = items if isinstance(items, list) else [items]
    ids = post_comments(meta["upstream"], items)
    remember_comments(run, items)
    print(f"agrev: {len(ids)} comment(s) pinned in the open review")
    return 0


def cmd_status(ns) -> int:
    path = Path(ns.file).expanduser().resolve()
    try:
        run = current_run(path)
    except Fail as exc:
        print(f"agrev: {exc}")
        return 0
    meta = read_json(run / "meta.json")
    state = "decided" if (run / "result.json").exists() else "open" if alive(meta["plannotator_pid"]) else "ended"
    print(f"agrev: {meta['display']}: {state} (run {run})")
    return 0


def cmd_close(ns) -> int:
    path = Path(ns.file).expanduser().resolve()
    run = current_run(path)
    meta = read_json(run / "meta.json")
    for pid in (meta.get("plannotator_pid"), (read_json(run / "proxy.json") if (run / "proxy.json").exists() else {}).get("pid")):
        if alive(pid):
            os.kill(pid, signal.SIGTERM)
    place = doc_dir(path) / "placement.json"
    if place.exists():
        sid = read_json(place).get("session", "")
        try:
            if any(s["id"].lower() == sid.lower() for s in sessions(os.environ.get("AGTERM_WINDOW_ID"))):
                agtermctl("session", "close", "--target", sid)
        except Fail:
            pass
        place.unlink()
    print(f"agrev: review of {meta['display']} closed")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("open"); p.add_argument("file"); p.add_argument("--comments", metavar="JSON")
    p.add_argument("--here", action="store_true"); p.add_argument("--no-follow", action="store_true")
    for name in ("wait", "comment", "status", "close"):
        sub.add_parser(name).add_argument("file")
    p = sub.add_parser("proxy"); p.add_argument("run")
    ns = ap.parse_args()
    try:
        if ns.cmd == "proxy":
            serve_proxy(Path(ns.run))
            return 0
        return {"open": cmd_open, "wait": cmd_wait, "comment": cmd_comment, "status": cmd_status,
                "close": cmd_close}[ns.cmd](ns)
    except Fail as exc:
        print(f"agrev: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
