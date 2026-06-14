#!/usr/bin/env python3
"""state.py — state management for refine-plan-against-codex.

Execute-only: invoke as a subcommand surface; do NOT read this file
into context during a loop run. See ./README.md for the subcommand
reference and orchestration.md for the broader UX contract.

State lives beside the plan under `.refine-plan-against-codex/` so
its lifecycle follows the host repo. `$REFINE_PLAN_STATE_ROOT`
overrides; the prior XDG / `~/.local/state` resolution was removed.
A `.gitignore` containing `*` is written into the root on first init
so the artifacts never get committed by accident; the SKILL.md
commit step uses a `git add -- <plan-path>` pathspec as the
suspenders to that belt.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
from collections import defaultdict
from datetime import datetime, timezone

SCHEMA_VERSION = 1

# Confidence threshold matching the sibling thinking-tools:ask-codex
# noise floor — codex itself signals low confidence below this. Findings
# below 0.3 are recorded in findings.txt for the record, but excluded
# from the actionable set the implementer sees and from the
# clean/needs-attention decision.
CONFIDENCE_FLOOR = 0.3

SEVERITIES = ("critical", "high", "medium", "low")
_SEV_PROSE_PAT = re.compile(r"\b(critical|high|medium|low)\b", re.IGNORECASE)
_FILE_LINE_PAT = re.compile(r"`([^`]+?):(\d+)`")

TERMINAL_STATUSES = (
    "completed_clean",
    "completed_converged",
    "completed_cap",
    "aborted_codex_error",
    "aborted_malformed_output",
    "aborted_drift",
    "aborted_implementer_noop",
    "aborted_commit_failed",
)


# ── helpers ──────────────────────────────────────────────────────────


def iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def iso_now_compact() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def derive_slug(path: str) -> str:
    base = os.path.basename(path)
    if base.endswith(".md"):
        base = base[:-3]
    m = re.match(r"^\d{8}-(.+)$", base)
    return m.group(1) if m else base


def abs_path(path: str) -> str:
    return os.path.abspath(path)


def plan_sha(path: str) -> str:
    if not os.path.isfile(path):
        return ""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def state_root(plan_path: str) -> str:
    env = os.environ.get("REFINE_PLAN_STATE_ROOT")
    if env:
        return env
    return os.path.join(os.path.dirname(abs_path(plan_path)), ".refine-plan-against-codex")


def _round_dir(state_dir: str, n: int) -> str:
    return os.path.join(state_dir, f"round-{n:02d}")


# ── manifest read-modify-write ───────────────────────────────────────


class Manifest:
    """Centralizes manifest I/O with atomic save.

    Replaces the triplicated read-modify-write that the old state.sh
    inlined in three separate python heredocs. `save()` uses
    `os.replace()` on a sibling tempfile so a mid-write crash leaves
    the old manifest intact — the prior `aborted_state_corruption`
    punt is retired structurally.
    """

    @staticmethod
    def path(state_dir: str) -> str:
        return os.path.join(state_dir, "manifest.json")

    @staticmethod
    def load(state_dir: str) -> dict:
        with open(Manifest.path(state_dir), encoding="utf-8") as f:
            return json.load(f)

    @staticmethod
    def save(state_dir: str, m: dict) -> None:
        target = Manifest.path(state_dir)
        with tempfile.NamedTemporaryFile(
            mode="w",
            dir=state_dir,
            prefix=".manifest.",
            suffix=".tmp",
            delete=False,
            encoding="utf-8",
        ) as tmp:
            json.dump(m, tmp, indent=2)
            tmp_name = tmp.name
        os.replace(tmp_name, target)

    @staticmethod
    def upsert_round(m: dict, n: int) -> dict:
        rounds = m.setdefault("rounds", [])
        for r in rounds:
            if r.get("round") == n:
                return r
        entry = {"round": n}
        rounds.append(entry)
        return entry


def _stamp(state_dir: str, n: int, field: str, ts: str) -> None:
    m = Manifest.load(state_dir)
    entry = Manifest.upsert_round(m, n)
    entry[field] = ts
    if field.endswith("_ended_at"):
        started_field = field.replace("_ended_at", "_started_at")
        started = entry.get(started_field)
        if started:
            s = datetime.fromisoformat(started.rstrip("Z"))
            e = datetime.fromisoformat(ts.rstrip("Z"))
            entry[field.replace("_ended_at", "_elapsed_seconds")] = int(
                (e - s).total_seconds()
            )
    m["current_round"] = n
    Manifest.save(state_dir, m)


def _set_int(state_dir: str, n: int, field: str, val: int) -> None:
    m = Manifest.load(state_dir)
    entry = Manifest.upsert_round(m, n)
    entry[field] = int(val)
    Manifest.save(state_dir, m)


# ── shared findings parser ───────────────────────────────────────────


def _strip_json_fence(text: str) -> str:
    """Strip a single leading ```json / ``` fence if present."""
    stripped = text.strip()
    if not stripped.startswith("```"):
        return stripped
    m = re.match(r"^```(?:json)?\s*\n(.*?)\n```\s*$", stripped, re.DOTALL)
    if m:
        return m.group(1).strip()
    return stripped


def parse_findings(findings_path: str) -> dict:
    """Parse a round's findings.txt — single source of truth shared by
    `summary` and `detect-stuck` (the old state.sh maintained two
    divergent regexes).

    Strategy, in order:
      1. Strip ```json fences, attempt json.loads.
      2. JSON OK + has `verdict` + `findings` is list → structured.
      3. JSON OK but missing required keys → fall back to prose scan.
      4. JSON fail → degraded prose scan for `critical|high|medium|low`
         + `` `file:line` ``; on hit, write parse-warning.txt next to
         findings.txt.
      5. Prose scan empty too → mark malformed; caller signals
         aborted_malformed_output.

    Returns a dict with keys: verdict, summary, findings, next_steps,
    degraded, malformed, empty.
    """
    empty_result = {
        "verdict": "approve",
        "summary": "",
        "findings": [],
        "next_steps": [],
        "degraded": False,
        "malformed": False,
        "empty": True,
    }
    if not os.path.isfile(findings_path):
        return empty_result
    with open(findings_path, encoding="utf-8") as f:
        text = f.read()
    if not text.strip():
        return empty_result

    data = None
    try:
        data = json.loads(_strip_json_fence(text))
    except (json.JSONDecodeError, ValueError):
        data = None

    if isinstance(data, dict):
        verdict = data.get("verdict")
        findings = data.get("findings")
        if verdict in ("approve", "needs-attention") and isinstance(findings, list):
            return {
                "verdict": verdict,
                "summary": data.get("summary", "") or "",
                "findings": findings,
                "next_steps": data.get("next_steps", []) or [],
                "degraded": False,
                "malformed": False,
                "empty": False,
            }
        # JSON parsed but shape is wrong — fall through to prose so a
        # severity-flavored object still has a chance to surface.

    # Degraded prose scan.
    prose_findings = []
    for line in text.split("\n"):
        sev_m = _SEV_PROSE_PAT.search(line)
        if not sev_m:
            continue
        sev = sev_m.group(1).lower()
        for fl in _FILE_LINE_PAT.finditer(line):
            prose_findings.append(
                {
                    "severity": sev,
                    "title": line.strip()[:200],
                    "body": line.strip(),
                    "file": fl.group(1),
                    "line_start": int(fl.group(2)),
                    "line_end": int(fl.group(2)),
                    # 0.5 sits above the floor so the prose path still
                    # produces an actionable set; codex's own confidence
                    # is unrecoverable from a prose-only payload.
                    "confidence": 0.5,
                    "recommendation": line.strip(),
                }
            )

    if prose_findings:
        warning_path = os.path.join(os.path.dirname(findings_path), "parse-warning.txt")
        try:
            with open(warning_path, "w", encoding="utf-8") as wf:
                wf.write(
                    "Findings JSON parse failed; degraded prose-fallback scan in use.\n"
                    f"Recovered {len(prose_findings)} finding(s) by severity+file:line regex.\n"
                    "Inspect findings.txt to confirm the JSON shape codex actually emitted.\n"
                )
        except OSError:
            pass
        return {
            "verdict": "needs-attention",
            "summary": "",
            "findings": prose_findings,
            "next_steps": [],
            "degraded": True,
            "malformed": False,
            "empty": False,
        }

    return {
        "verdict": None,
        "summary": "",
        "findings": [],
        "next_steps": [],
        "degraded": True,
        "malformed": True,
        "empty": False,
    }


def _actionable(findings: list) -> list:
    return [
        f
        for f in findings
        if float(f.get("confidence", 1.0) or 0.0) >= CONFIDENCE_FLOOR
    ]


# ── subcommands ──────────────────────────────────────────────────────


def cmd_init(args: argparse.Namespace) -> None:
    plan_abs = abs_path(args.plan_path)
    slug = derive_slug(args.plan_path)
    ts = iso_now_compact()
    root = state_root(args.plan_path)
    os.makedirs(root, exist_ok=True)
    gi = os.path.join(root, ".gitignore")
    if not os.path.exists(gi):
        with open(gi, "w", encoding="utf-8") as f:
            f.write("*\n")
    state_dir = os.path.join(root, f"{slug}-{ts}")
    os.makedirs(state_dir, exist_ok=True)
    manifest = {
        "schema_version": SCHEMA_VERSION,
        "plan_path": plan_abs,
        "plan_slug": slug,
        "run_id": f"{slug}-{ts}",
        "started_at": iso_now(),
        "initial_plan_sha256": plan_sha(args.plan_path),
        "status": "in_progress",
        "current_round": 0,
        "rounds": [],
    }
    Manifest.save(state_dir, manifest)
    print(state_dir)


def cmd_resume(args: argparse.Namespace) -> None:
    plan_abs = abs_path(args.plan_path)
    root = state_root(args.plan_path)
    if not os.path.isdir(root):
        return
    best, best_ts = None, ""
    for entry in os.listdir(root):
        mp = os.path.join(root, entry, "manifest.json")
        if not os.path.isfile(mp):
            continue
        try:
            with open(mp, encoding="utf-8") as f:
                m = json.load(f)
        except (OSError, json.JSONDecodeError):
            continue
        if m.get("plan_path") != plan_abs:
            continue
        if m.get("status") != "in_progress":
            continue
        ts = m.get("started_at", "")
        if ts > best_ts:
            best_ts = ts
            best = os.path.join(root, entry)
    if best:
        print(best)


def cmd_record_codex_start(args: argparse.Namespace) -> None:
    os.makedirs(_round_dir(args.state_dir, args.round), exist_ok=True)
    _stamp(args.state_dir, args.round, "codex_started_at", iso_now())


def cmd_record_codex_end(args: argparse.Namespace) -> None:
    rdir = _round_dir(args.state_dir, args.round)
    os.makedirs(rdir, exist_ok=True)
    shutil.copyfile(args.findings_file, os.path.join(rdir, "findings.txt"))
    _stamp(args.state_dir, args.round, "codex_ended_at", iso_now())
    _set_int(args.state_dir, args.round, "codex_tokens", args.tokens)
    _set_int(args.state_dir, args.round, "codex_tool_uses", args.tool_uses)


def cmd_record_implementer_start(args: argparse.Namespace) -> None:
    _stamp(args.state_dir, args.round, "implementer_started_at", iso_now())


def cmd_record_implementer_end(args: argparse.Namespace) -> None:
    rdir = _round_dir(args.state_dir, args.round)
    os.makedirs(rdir, exist_ok=True)
    shutil.copyfile(args.summary_file, os.path.join(rdir, "implementer-summary.txt"))
    _stamp(args.state_dir, args.round, "implementer_ended_at", iso_now())
    _set_int(args.state_dir, args.round, "implementer_tokens", args.tokens)
    _set_int(args.state_dir, args.round, "implementer_tool_uses", args.tool_uses)


def cmd_record_arbiter_start(args: argparse.Namespace) -> None:
    os.makedirs(_round_dir(args.state_dir, args.round), exist_ok=True)
    _stamp(args.state_dir, args.round, "arbiter_started_at", iso_now())


def cmd_record_arbiter_end(args: argparse.Namespace) -> None:
    rdir = _round_dir(args.state_dir, args.round)
    os.makedirs(rdir, exist_ok=True)
    shutil.copyfile(args.arbiter_file, os.path.join(rdir, "arbiter.txt"))
    _stamp(args.state_dir, args.round, "arbiter_ended_at", iso_now())
    _set_int(args.state_dir, args.round, "arbiter_tokens", args.tokens)
    _set_int(args.state_dir, args.round, "arbiter_tool_uses", args.tool_uses)


def cmd_finalize(args: argparse.Namespace) -> None:
    if args.status not in TERMINAL_STATUSES:
        print(
            f"finalize: unknown status '{args.status}' "
            f"(allowed: {' | '.join(TERMINAL_STATUSES)})",
            file=sys.stderr,
        )
        sys.exit(2)
    m = Manifest.load(args.state_dir)
    m["status"] = args.status
    m["ended_at"] = iso_now()
    Manifest.save(args.state_dir, m)


def cmd_detect_stuck(args: argparse.Namespace) -> None:
    m = Manifest.load(args.state_dir)
    location_to_rounds: "defaultdict[tuple, list]" = defaultdict(list)
    for r in m.get("rounds", []):
        n = r["round"]
        fp = os.path.join(_round_dir(args.state_dir, n), "findings.txt")
        if not os.path.isfile(fp):
            continue
        parsed = parse_findings(fp)
        if parsed["malformed"] or parsed["empty"]:
            continue
        seen_this_round = set()
        for f in _actionable(parsed["findings"]):
            file = f.get("file")
            line = f.get("line_start")
            if not file or line is None:
                continue
            try:
                line_i = int(line)
            except (TypeError, ValueError):
                continue
            key = (file, line_i)
            if key in seen_this_round:
                continue
            seen_this_round.add(key)
            sev = (f.get("severity") or "").lower()
            location_to_rounds[key].append((n, sev))

    stuck = [(loc, occs) for loc, occs in location_to_rounds.items() if len(occs) >= 2]
    stuck.sort(key=lambda x: (-len(x[1]), x[0]))
    for (path, line), occs in stuck:
        rounds_str = ",".join(str(rd) for rd, _ in occs)
        sevs_str = ",".join(s for _, s in occs)
        print(f"STUCK {path}:{line} rounds: {rounds_str} severity: {sevs_str}")


# ── summary table (box-drawn) ────────────────────────────────────────


def _fmt_seconds(s) -> str:
    if not s:
        return "—"
    s = int(s)
    if s < 60:
        return f"{s}s"
    m_, ss = divmod(s, 60)
    return f"{m_}m {ss}s"


def _fmt_tokens(n) -> str:
    if not n:
        return "—"
    n = int(n)
    if n < 1000:
        return str(n)
    return f"{n // 1000}k"


def _count_findings(findings_path: str):
    parsed = parse_findings(findings_path)
    if parsed["empty"] or parsed["malformed"]:
        return ("—", 0)
    actionable = _actionable(parsed["findings"])
    if parsed["verdict"] == "approve" and not actionable:
        return ("No find.", 0)
    counts = {sev: 0 for sev in SEVERITIES}
    for f in actionable:
        sev = (f.get("severity") or "").lower()
        if sev in counts:
            counts[sev] += 1
    total = sum(counts.values())
    label = (
        f"{counts['critical']}C {counts['high']}H "
        f"{counts['medium']}M {counts['low']}L"
    )
    return (label, total)


def _count_arbiter(arbiter_path: str) -> str:
    """Digest a round's arbiter.txt for the summary table: `<R>r <P>p`
    (real vs prose classifications). Returns "—" when the file is absent
    or unparseable — the arbiter only runs from ARBITER_FROM_ROUND
    onward, so most early rounds have no arbiter.txt.
    """
    if not os.path.isfile(arbiter_path):
        return "—"
    try:
        with open(arbiter_path, encoding="utf-8") as f:
            data = json.loads(_strip_json_fence(f.read()))
    except (OSError, json.JSONDecodeError, ValueError):
        return "—"
    classes = data.get("classifications") if isinstance(data, dict) else None
    if not isinstance(classes, list) or not classes:
        return "—"
    real = sum(1 for c in classes if isinstance(c, dict) and c.get("class") == "real")
    prose = sum(1 for c in classes if isinstance(c, dict) and c.get("class") == "prose")
    return f"{real}r {prose}p"


def cmd_summary(args: argparse.Namespace) -> None:
    m = Manifest.load(args.state_dir)
    rounds = m.get("rounds", [])

    widths = (34, 13, 9, 10)
    headers = ("Phase", "Findings", "Tokens", "Elapsed")
    rows = []
    total_tokens = 0
    total_elapsed = 0
    sep_after = set()

    for r in rounds:
        n = r["round"]
        rdir = _round_dir(args.state_dir, n)
        findings_path = os.path.join(rdir, "findings.txt")
        findings_str, n_findings = _count_findings(findings_path)
        c_tokens = r.get("codex_tokens", 0) or 0
        c_elapsed = r.get("codex_elapsed_seconds", 0) or 0
        rows.append(
            (
                f"Round {n} codex",
                findings_str,
                _fmt_tokens(c_tokens),
                _fmt_seconds(c_elapsed),
            )
        )
        total_tokens += c_tokens
        total_elapsed += c_elapsed

        arbiter_path = os.path.join(rdir, "arbiter.txt")
        if os.path.isfile(arbiter_path):
            arb_str = _count_arbiter(arbiter_path)
            a_tokens = r.get("arbiter_tokens", 0) or 0
            a_elapsed = r.get("arbiter_elapsed_seconds", 0) or 0
            rows.append(
                (
                    f"Round {n} arbiter",
                    arb_str,
                    _fmt_tokens(a_tokens),
                    _fmt_seconds(a_elapsed),
                )
            )
            total_tokens += a_tokens
            total_elapsed += a_elapsed

        summary_path = os.path.join(rdir, "implementer-summary.txt")
        if os.path.isfile(summary_path):
            impl_str = f"{n_findings}/{n_findings} addr" if n_findings else "addressed"
            i_tokens = r.get("implementer_tokens", 0) or 0
            i_elapsed = r.get("implementer_elapsed_seconds", 0) or 0
            rows.append(
                (
                    f"Round {n} implementer",
                    impl_str,
                    _fmt_tokens(i_tokens),
                    _fmt_seconds(i_elapsed),
                )
            )
            total_tokens += i_tokens
            total_elapsed += i_elapsed

        sep_after.add(len(rows) - 1)

    rows.append(("Total", "", _fmt_tokens(total_tokens), _fmt_seconds(total_elapsed)))

    def hsep(start, mid, end):
        return start + mid.join("─" * w for w in widths) + end

    def row_line(values):
        cells = []
        for v, w in zip(values, widths):
            v_str = str(v)
            if len(v_str) > w - 2:
                v_str = v_str[: w - 3] + "…"
            cells.append(f" {v_str:<{w - 2}} ")
        return "│" + "│".join(cells) + "│"

    print(hsep("┌", "┬", "┐"))
    print(row_line(headers))
    print(hsep("├", "┼", "┤"))
    for i, r in enumerate(rows):
        print(row_line(r))
        is_total = i == len(rows) - 1
        if is_total:
            continue
        if i in sep_after or i == len(rows) - 2:
            print(hsep("├", "┼", "┤"))
    print(hsep("└", "┴", "┘"))


def cmd_status(args: argparse.Namespace) -> None:
    m = Manifest.load(args.state_dir)
    print(f"Plan:      {m['plan_path']}")
    print(f"Slug:      {m['plan_slug']}")
    print(f"Run:       {m['run_id']}")
    print(f"Status:    {m['status']}")
    print(f"Started:   {m['started_at']}")
    if m.get("ended_at"):
        print(f"Ended:     {m['ended_at']}")
    print(f"Round:     {m.get('current_round', 0)}")
    print(f"State-dir: {args.state_dir}")
    rs = m.get("rounds", [])
    total_c = sum(r.get("codex_elapsed_seconds", 0) or 0 for r in rs)
    total_i = sum(r.get("implementer_elapsed_seconds", 0) or 0 for r in rs)
    print(f"Codex:     {total_c}s total across {len(rs)} round(s)")
    print(f"Impl:      {total_i}s total")
    for r in rs:
        n = r["round"]
        c = r.get("codex_elapsed_seconds", "?")
        i = r.get("implementer_elapsed_seconds", "?")
        rdir = _round_dir(args.state_dir, n)
        findings_p = os.path.join(rdir, "findings.txt")
        summary_p = os.path.join(rdir, "implementer-summary.txt")
        print(f"  Round {n:2d}: codex={c}s implementer={i}s")
        if os.path.isfile(findings_p):
            print(f"           findings: {findings_p}")
        if os.path.isfile(summary_p):
            print(f"           summary:  {summary_p}")


# ── dispatch ─────────────────────────────────────────────────────────


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        prog="state.py",
        description="State management for refine-plan-against-codex.",
    )
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("init")
    p.add_argument("plan_path")
    p.set_defaults(func=cmd_init)

    p = sub.add_parser("resume")
    p.add_argument("plan_path")
    p.set_defaults(func=cmd_resume)

    p = sub.add_parser("record-codex-start")
    p.add_argument("state_dir")
    p.add_argument("round", type=int)
    p.set_defaults(func=cmd_record_codex_start)

    p = sub.add_parser("record-codex-end")
    p.add_argument("state_dir")
    p.add_argument("round", type=int)
    p.add_argument("findings_file")
    p.add_argument("tokens", nargs="?", type=int, default=0)
    p.add_argument("tool_uses", nargs="?", type=int, default=0)
    p.set_defaults(func=cmd_record_codex_end)

    p = sub.add_parser("record-implementer-start")
    p.add_argument("state_dir")
    p.add_argument("round", type=int)
    p.set_defaults(func=cmd_record_implementer_start)

    p = sub.add_parser("record-implementer-end")
    p.add_argument("state_dir")
    p.add_argument("round", type=int)
    p.add_argument("summary_file")
    p.add_argument("tokens", nargs="?", type=int, default=0)
    p.add_argument("tool_uses", nargs="?", type=int, default=0)
    p.set_defaults(func=cmd_record_implementer_end)

    p = sub.add_parser("record-arbiter-start")
    p.add_argument("state_dir")
    p.add_argument("round", type=int)
    p.set_defaults(func=cmd_record_arbiter_start)

    p = sub.add_parser("record-arbiter-end")
    p.add_argument("state_dir")
    p.add_argument("round", type=int)
    p.add_argument("arbiter_file")
    p.add_argument("tokens", nargs="?", type=int, default=0)
    p.add_argument("tool_uses", nargs="?", type=int, default=0)
    p.set_defaults(func=cmd_record_arbiter_end)

    p = sub.add_parser("finalize")
    p.add_argument("state_dir")
    p.add_argument("status")
    p.set_defaults(func=cmd_finalize)

    p = sub.add_parser("status")
    p.add_argument("state_dir")
    p.set_defaults(func=cmd_status)

    p = sub.add_parser("summary")
    p.add_argument("state_dir")
    p.set_defaults(func=cmd_summary)

    p = sub.add_parser("detect-stuck")
    p.add_argument("state_dir")
    p.set_defaults(func=cmd_detect_stuck)

    return ap


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    args.func(args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
