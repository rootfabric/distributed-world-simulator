from __future__ import annotations

import json
import unittest
from pathlib import Path

from scripts.harness.evidence_sink_guard import (
    FAILURE_CODE,
    find_optional_evidence_sink_violations,
    guarded_test_path,
)

ROOT = Path(__file__).resolve().parents[2]


class OptionalEvidenceSinkContractTests(unittest.TestCase):
    def test_gdscript_antipattern_is_rejected(self) -> None:
        source = """extends SceneTree
func _init() -> void:
    var output := OS.get_environment("MVP_TEST_RESULT")
    var saved := false
    if not output.is_empty():
        saved = bool(write_result(output).get("success", false))
    var passed := true
    quit(0 if passed and saved else 1)
"""
        violations = find_optional_evidence_sink_violations("tests/runtime/test_bad.gd", source)
        self.assertEqual(1, len(violations))
        self.assertEqual(FAILURE_CODE, violations[0].code)
        self.assertEqual("MVP_TEST_RESULT", violations[0].env)
        self.assertEqual("saved", violations[0].flag)

    def test_optional_sink_absence_does_not_control_verdict(self) -> None:
        source = """extends SceneTree
func _init() -> void:
    var output := OS.get_environment("MVP_TEST_RESULT")
    var saved := true
    if not output.is_empty():
        saved = bool(write_result(output).get("success", false))
    var passed := true
    quit(0 if passed and saved else 1)
"""
        self.assertEqual(
            [],
            find_optional_evidence_sink_violations("tests/runtime/test_good.gd", source),
        )

    def test_requested_sink_write_can_remain_fail_closed(self) -> None:
        source = """extends SceneTree
func _init() -> void:
    var output := OS.get_environment("MVP_TEST_RESULT")
    var saved := output.is_empty()
    if not output.is_empty():
        saved = bool(write_result(output).get("success", false))
    var passed := true
    quit(0 if passed and saved else 1)
"""
        self.assertEqual(
            [],
            find_optional_evidence_sink_violations("tests/runtime/test_good.gd", source),
        )

    def test_python_antipattern_is_rejected(self) -> None:
        source = """import os, sys
output = os.environ.get("MVP_TEST_RESULT", "")
saved = False
if output:
    saved = write_result(output)
passed = True
sys.exit(0 if passed and saved else 1)
"""
        violations = find_optional_evidence_sink_violations("tests/integration/test_bad.py", source)
        self.assertEqual(1, len(violations))
        self.assertEqual("MVP_TEST_RESULT", violations[0].env)

    def test_guard_scope_excludes_harness_fixtures_but_covers_product_tests(self) -> None:
        self.assertTrue(guarded_test_path("tests/runtime/test_a.gd"))
        self.assertTrue(guarded_test_path("tests/integration/test_a.py"))
        self.assertFalse(guarded_test_path("tests/harness/test_optional_evidence_sink_contract.py"))
        self.assertFalse(guarded_test_path("scripts/validator.py"))

    def test_machine_policy_declares_the_same_fail_closed_contract(self) -> None:
        policy = json.loads(
            (ROOT / "config/control/harness/harness-policy.v1.json").read_text(encoding="utf-8")
        )
        contract = policy["test_evidence_sink_contract"]
        self.assertEqual("H0-EVIDENCE-SINK-2026-09-18-R1", contract["revision"])
        self.assertTrue(contract["optional_sink_absence_must_not_change_verdict"])
        self.assertTrue(contract["requested_sink_write_failure_must_fail"])
        self.assertTrue(contract["implicit_requiredness_via_false_saved_flag_forbidden"])
        self.assertEqual(FAILURE_CODE, contract["failure_code"])


if __name__ == "__main__":
    unittest.main()
