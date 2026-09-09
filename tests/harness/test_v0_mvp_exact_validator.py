from __future__ import annotations

import fnmatch
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "docs/control/mvp-act0-r1/validate.py"
R6 = ROOT / "docs/control/mvp-act0-r1/work-order-exact-validator-r6.v1.json"
R6_SUBJECT = "32eabd082c372f532a9f87bc382f0fcce4d6e4db"
R6_TREE = "87874271a1897689aef27fb4ee142b23ee5cd31a"

spec = importlib.util.spec_from_file_location("act0_validate", VALIDATOR)
assert spec and spec.loader
act0_validate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(act0_validate)


class MVPExactValidatorTests(unittest.TestCase):
    def test_r6_repair_diff_touches_only_declared_paths(self) -> None:
        work_order = json.loads(R6.read_text(encoding="utf-8"))
        base = work_order["repair_diff_base"]
        observed_tree = subprocess.check_output(
            ["git", "show", "-s", "--format=%T", R6_SUBJECT], cwd=ROOT, text=True
        ).strip()
        self.assertEqual(observed_tree, R6_TREE)
        self.assertEqual(
            subprocess.run(
                ["git", "merge-base", "--is-ancestor", R6_SUBJECT, "HEAD"],
                cwd=ROOT,
                check=False,
            ).returncode,
            0,
            "current ACT0 descendant no longer contains the frozen R6 subject",
        )
        changed = subprocess.check_output(
            ["git", "diff", "--name-only", base, R6_SUBJECT], cwd=ROOT, text=True
        ).splitlines()
        self.assertTrue(changed)
        for path in changed:
            self.assertTrue(
                any(fnmatch.fnmatchcase(path, pattern) for pattern in work_order["allowed_paths"]),
                f"R6 out-of-scope path: {path}",
            )
            self.assertFalse(
                any(fnmatch.fnmatchcase(path, pattern) for pattern in work_order["forbidden_paths"]),
                f"R6 forbidden path: {path}",
            )

    def test_nonsemantic_formatting_outside_selector_is_ignored(self) -> None:
        left = '''import json\n\nVALUE = 1\n\ndef _select_epoch_audit(context, events):\n    return None\n\ndef stable():\n    return VALUE + 1\n'''
        right = '''import json\n\n\nVALUE=1\n\ndef _select_epoch_audit(context, events):\n    # selector is intentionally allowed to differ\n    return {"changed": True}\n\n\ndef stable( ) :\n    return VALUE+1\n'''
        self.assertEqual(
            act0_validate.without_selector_semantics(left),
            act0_validate.without_selector_semantics(right),
        )

    def test_selector_semantic_change_is_ignored_by_bounded_guard(self) -> None:
        left = '''X = 1\ndef _select_epoch_audit(context, events):\n    return None\ndef stable():\n    return X\n'''
        right = '''X = 1\ndef _select_epoch_audit(context, events):\n    return events[-1]\ndef stable():\n    return X\n'''
        self.assertEqual(
            act0_validate.without_selector_semantics(left),
            act0_validate.without_selector_semantics(right),
        )

    def test_semantic_change_outside_selector_is_rejected(self) -> None:
        left = '''X = 1\ndef _select_epoch_audit(context, events):\n    return None\ndef stable():\n    return X\n'''
        right = '''X = 2\ndef _select_epoch_audit(context, events):\n    return None\ndef stable():\n    return X\n'''
        self.assertNotEqual(
            act0_validate.without_selector_semantics(left),
            act0_validate.without_selector_semantics(right),
        )

    def test_exactly_one_top_level_selector_is_required(self) -> None:
        missing = 'X = 1\n'
        duplicate = '''def _select_epoch_audit(a, b):\n    return None\ndef _select_epoch_audit(a, b):\n    return None\n'''
        with self.assertRaisesRegex(RuntimeError, "R6_SELECTOR_IDENTITY_INVALID"):
            act0_validate.without_selector_semantics(missing)
        with self.assertRaisesRegex(RuntimeError, "R6_SELECTOR_IDENTITY_INVALID"):
            act0_validate.without_selector_semantics(duplicate)


if __name__ == "__main__":
    unittest.main()
