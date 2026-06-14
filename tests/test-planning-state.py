#!/usr/bin/env python3
"""Unit tests for the parse internals of refine-plan-against-codex's state.py.

These cover the bits awkward to assert from bash: parse_findings's
multi-strategy parser (structured JSON, ```json fence, degraded prose
fallback, malformed), the confidence-floor filter (_actionable), and
derive_slug. The CLI lifecycle is covered black-box in
tests/test-planning-refine-state.sh.

state.py is loaded read-only by path via importlib — it is import-safe
(execution is guarded by `if __name__ == "__main__"`) and is never
modified by the tests.

Run: python3 tests/test-planning-state.py
"""

import importlib.util
import json
import os
import sys
import tempfile
import unittest

# state.py lives in the shipped plugin tree; importing it must not leave a
# __pycache__/*.pyc beside it. Disable bytecode writes before we load it.
sys.dont_write_bytecode = True

_HERE = os.path.dirname(os.path.abspath(__file__))
_REPO_ROOT = os.path.dirname(_HERE)
_STATE_PATH = os.path.join(
    _REPO_ROOT,
    "plugins",
    "planning",
    "skills",
    "refine-plan-against-codex",
    "references",
    "state.py",
)


def _load_state():
    spec = importlib.util.spec_from_file_location("state", _STATE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


state = _load_state()


class ParseFindingsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()

    def _write(self, content):
        path = os.path.join(self.tmp, "findings.txt")
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        return path

    def test_structured_approve_empty(self):
        path = self._write(json.dumps({"verdict": "approve", "findings": []}))
        r = state.parse_findings(path)
        self.assertFalse(r["empty"])
        self.assertEqual(r["verdict"], "approve")
        self.assertEqual(r["findings"], [])
        self.assertFalse(r["degraded"])
        self.assertFalse(r["malformed"])

    def test_structured_needs_attention(self):
        payload = {
            "verdict": "needs-attention",
            "summary": "stuff",
            "findings": [
                {"severity": "high", "file": "a.py", "line_start": 42, "confidence": 0.9}
            ],
            "next_steps": ["fix it"],
        }
        path = self._write(json.dumps(payload))
        r = state.parse_findings(path)
        self.assertEqual(r["verdict"], "needs-attention")
        self.assertFalse(r["degraded"])
        self.assertFalse(r["malformed"])
        # structured passthrough — findings object survives unmodified
        self.assertEqual(r["findings"], payload["findings"])

    def test_json_fence_is_stripped(self):
        fenced = "```json\n" + json.dumps({"verdict": "approve", "findings": []}) + "\n```\n"
        path = self._write(fenced)
        r = state.parse_findings(path)
        self.assertFalse(r["empty"])
        self.assertEqual(r["verdict"], "approve")
        self.assertFalse(r["malformed"])

    def test_degraded_prose_fallback(self):
        prose = "Not JSON, but a critical problem lurks at `foo.py:99` somewhere."
        path = self._write(prose)
        r = state.parse_findings(path)
        self.assertTrue(r["degraded"])
        self.assertFalse(r["malformed"])
        self.assertFalse(r["empty"])
        self.assertEqual(len(r["findings"]), 1)
        self.assertEqual(r["findings"][0]["confidence"], 0.5)
        self.assertEqual(r["findings"][0]["file"], "foo.py")
        self.assertEqual(r["findings"][0]["line_start"], 99)
        warning = os.path.join(os.path.dirname(path), "parse-warning.txt")
        self.assertTrue(os.path.isfile(warning))

    def test_total_garbage_is_malformed(self):
        path = self._write("just some random words, no severity and no file line span")
        r = state.parse_findings(path)
        self.assertTrue(r["malformed"])
        self.assertFalse(r["empty"])

    def test_empty_file_is_empty(self):
        path = self._write("")
        r = state.parse_findings(path)
        self.assertTrue(r["empty"])

    def test_missing_path_is_empty(self):
        r = state.parse_findings(os.path.join(self.tmp, "does-not-exist.txt"))
        self.assertTrue(r["empty"])


class ActionableTest(unittest.TestCase):
    def test_drops_below_floor_keeps_at_or_above(self):
        findings = [
            {"id": "below", "confidence": 0.2},
            {"id": "edge", "confidence": 0.3},
            {"id": "high", "confidence": 0.9},
        ]
        kept = {f["id"] for f in state._actionable(findings)}
        self.assertEqual(kept, {"edge", "high"})


class DeriveSlugTest(unittest.TestCase):
    def test_strips_date_prefix(self):
        self.assertEqual(state.derive_slug("20260101-foo-bar.md"), "foo-bar")

    def test_no_date_prefix(self):
        self.assertEqual(state.derive_slug("auth-rewrite.md"), "auth-rewrite")


class CountArbiterTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()

    def _write(self, content):
        path = os.path.join(self.tmp, "arbiter.txt")
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        return path

    def test_counts_real_and_prose(self):
        payload = {
            "classifications": [
                {"index": 1, "class": "real", "reason": "wrong contract"},
                {"index": 2, "class": "prose", "reason": "wording nitpick"},
                {"index": 3, "class": "prose", "reason": "redundant sentence"},
            ],
            "summary": "1 real, 2 prose",
        }
        self.assertEqual(state._count_arbiter(self._write(json.dumps(payload))), "1r 2p")

    def test_strips_json_fence(self):
        fenced = "```json\n" + json.dumps(
            {"classifications": [{"index": 1, "class": "real"}]}
        ) + "\n```\n"
        self.assertEqual(state._count_arbiter(self._write(fenced)), "1r 0p")

    def test_missing_file_is_dash(self):
        self.assertEqual(state._count_arbiter(os.path.join(self.tmp, "nope.txt")), "—")

    def test_malformed_is_dash(self):
        self.assertEqual(state._count_arbiter(self._write("not json at all")), "—")


class TerminalStatusesTest(unittest.TestCase):
    def test_converged_is_terminal(self):
        # the prose-drift gate finalizes with this status; finalize must accept it
        self.assertIn("completed_converged", state.TERMINAL_STATUSES)


if __name__ == "__main__":
    unittest.main()
