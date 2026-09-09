from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
VALIDATOR = ROOT / "docs/control/mvp-act0-r1/validate.py"

spec = importlib.util.spec_from_file_location("act0_validate", VALIDATOR)
assert spec and spec.loader
act0_validate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(act0_validate)


class MVPExactValidatorTests(unittest.TestCase):
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
