"""Unit tests for the evidence collector, not product/runtime acceptance."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("p7_validator", Path(__file__).with_name("validate_candidate.py"))
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


class EvidenceCollectorTests(unittest.TestCase):
    def test_p7_coverage_is_29_distinct_leaves_and_2032_assertions(self):
        self.assertEqual(sum(map(len, VALIDATOR.P7_LEAVES.values())), 29)
        self.assertEqual(sum(sum(v.values()) for v in VALIDATOR.P7_LEAVES.values()), 2032)

    def test_nested_manifests_are_not_excluded_as_self_hashes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            nested = root / "artifacts/test-results/recovery/manifest.json"
            VALIDATOR.write_json(nested, {"fixture": "unit-test-only"})
            out = root / "artifacts/evidence"
            out.mkdir()
            VALIDATOR.write_json(out / "manifest.json", {"stale": True})
            environment = {key: "unit-test-not-provider-evidence" for key in (
                "GITHUB_SHA", "GITHUB_RUN_ID", "GITHUB_RUN_ATTEMPT", "GITHUB_JOB", "RUNNER_NAME")}
            with patch.dict(os.environ, environment), patch.object(VALIDATOR, "identity", return_value={"unit_test": True}):
                VALIDATOR.preserve(root, out)
            manifest = json.loads((out / "manifest.json").read_text())
            paths = [entry["path"] for entry in manifest["files"]]
            self.assertIn("test-results/recovery/manifest.json", paths)
            self.assertNotIn("manifest.json", paths)
            self.assertEqual(manifest["files"][0]["sha256"], VALIDATOR.digest(nested))

    def test_zero_exit_is_not_enough_when_a_fatal_marker_is_present(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaisesRegex(RuntimeError, "FAILED_STEP:fatal"):
                VALIDATOR.run(root, root, "fatal", [sys.executable, "-c", "print('SCRIPT ERROR: unit-negative-control')"], 5)
            result = json.loads((root / "fatal.result.json").read_text())
            self.assertEqual(result["exit_code"], 0)
            self.assertTrue(result["fatal_matches"])

    def test_actual_nonzero_exit_is_preserved_and_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaisesRegex(RuntimeError, "FAILED_STEP:nonzero"):
                VALIDATOR.run(root, root, "nonzero", [sys.executable, "-c", "raise SystemExit(7)"], 5)
            self.assertEqual(json.loads((root / "nonzero.result.json").read_text())["exit_code"], 7)

    def test_only_explicit_expected_negative_exit_is_allowed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            VALIDATOR.run(root, root, "negative", [sys.executable, "-c", "raise SystemExit(1)"], 5, expected=1)
            result = json.loads((root / "negative.result.json").read_text())
            self.assertEqual(result["exit_code"], result["expected_exit"])

    def test_timeout_is_failure_and_is_recorded(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaisesRegex(RuntimeError, "FAILED_STEP:timeout"):
                VALIDATOR.run(root, root, "timeout", [sys.executable, "-c", "import time; time.sleep(10)"], 0.05)
            result = json.loads((root / "timeout.result.json").read_text())
            self.assertEqual(result["exit_code"], 124)
            self.assertIn("VALIDATOR_PROCESS_GROUP_TIMEOUT", (root / "timeout.log").read_text())

    def test_log_digest_is_computed_from_preserved_raw_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            VALIDATOR.run(root, root, "success", [sys.executable, "-c", "print('unit-output')"], 5)
            result = json.loads((root / "success.result.json").read_text())
            self.assertEqual(result["log_sha256"], VALIDATOR.digest(root / "success.log"))
            self.assertEqual(result["exit_code"], 0)


class P7SummaryTests(unittest.TestCase):
    def test_all_29_actual_canonical_summary_formats(self):
        path = Path(__file__).with_name("collector-evidence") / "p7-leaf-summaries.v1.json"
        stages = json.loads(path.read_text())["stages"]
        self.assertEqual(len(stages), 29)
        self.assertEqual(sum(row["assertions"] for row in stages), 2032)
        for row in stages:
            with self.subTest(name=row["name"]):
                VALIDATOR.check_p7_leaf(row["summary"], row["name"], row["assertions"])

    def test_wrong_subject_count_or_failures_are_rejected(self):
        for text in ("OTHER: PASS (130 assertions)",
                     "MW6 matter network authority: PASS (129 assertions)",
                     "MW6 matter network authority: PASS (130 assertions, 1 failures)",
                     "MW6 matter network authority: PASS (130 assertions",
                     "MW6 matter network authority: 130 assertions)"):
            with self.subTest(text=text), self.assertRaises(RuntimeError):
                VALIDATOR.check_p7_leaf(text, "mw6", 130)

    def test_missing_or_duplicate_terminal_summaries_are_rejected(self):
        summary = "MW6 matter network authority: PASS (130 assertions)"
        for text in ("", summary + "\n" + summary):
            with self.subTest(text=text), self.assertRaises(RuntimeError):
                VALIDATOR.check_p7_leaf(text, "mw6", 130)

    def test_pass_never_overrides_fatal_or_failure(self):
        summary = "MW6 matter network authority: PASS (130 assertions)"
        for failure in ("SCRIPT ERROR: failure", "[FAIL] assertion", "MW6: FAIL", "1 failures"):
            with self.subTest(failure=failure), self.assertRaises(RuntimeError):
                VALIDATOR.check_p7_leaf(failure + "\n" + summary, "mw6", 130)


if __name__ == "__main__":
    unittest.main()
