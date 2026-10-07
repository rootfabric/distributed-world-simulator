"""Collector falsifiers use synthetic temp campaigns, never runtime evidence."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

MODULE = Path(__file__).parents[3] / "scripts/research/fabric_bake0/collect_r5_4_evidence.py"
spec = importlib.util.spec_from_file_location("r54", MODULE)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for name in ("import", "parse"):
            (self.root / f"{name}.log").write_text("Godot test fixture\n")
        (self.root / "r53-regression.log").write_text("FABRIC R5.3 RECURSIVE HIERARCHICAL EXECUTION: PASS (1231 assertions)\n")
        (self.root / "r51-regression.log").write_text("FABRIC R5.1 QUANTITATIVE SCALE: PASS (93 assertions) count=100000\n")
        (self.root / "python-tests.log").write_text("Ran 1 test in 0.001s\n\nOK\n")
        self.set_identity(m.LINUX_GODOT_SHA256)
        for i in (1, 2, 3):
            self.write_sample(i, self.valid())

    def valid(self):
        # Deliberately independent of m.EXPECTED: changing a gate cannot silently
        # rewrite its positive fixture. These are the declared R3 predicates.
        return {
            "schema": "fabric.r5_4.mixed_complexity_100k.result.v2", "failures": [],
            "checks": 1048, "machine_parts": 100000, "recursive_levels": 4, "recursive_nodes": 15,
            "baseline_recursive_physical_components": 1812, "final_recursive_physical_components": 1852,
            "recursive_compiled_input_components": 24, "recursive_executable_equations": 4,
            "local_full_peak": 20, "local_reconstructed_parts": 20, "local_metadata_parts_scanned": 0,
            "local_range_query_count": 4, "local_range_query_prefix_reads": 80,
            "local_recursive_changed": 4, "local_recursive_reused": 11,
            "global_structural_parts_scanned": 0, "global_recursive_changed": 15, "global_recursive_reused": 0,
            "explicit_global_control_parts_scanned": 100000,
            "global_structural_state_unchanged": True, "explicit_global_control_state_unchanged": True,
            "rollback_rejected_events": 11, "rollback_state_unchanged_events": 11,
            "uninitialized_rejections": 3, "steady_calls": 320, "final_machine_hash": "a" * 64,
        }

    def set_identity(self, sha):
        rows = ["HEAD=" + "1" * 40, "TREE=" + "2" * 40,
                "GODOT_VERSION=4.7.1.stable.double.custom_build.a13da4feb", "GODOT_SHA256=" + sha]
        for name in ("before", "after"):
            (self.root / f"identity-{name}.txt").write_text("\n".join(rows) + "\n")
        return rows

    def write_sample(self, i, data):
        raw = json.dumps(data, sort_keys=True, separators=(",", ":"))
        hashed = hashlib.sha256(raw.encode()).hexdigest()
        (self.root / f"sample-{i}.log").write_text(
            m.PREFIX + raw + "\n" + m.HASH_PREFIX + hashed + "\n" +
            m.PASS + str(data["checks"]) + " assertions)\n")

    def bad_field(self, field, value):
        data = self.valid()
        data[field] = value
        self.write_sample(1, data)
        with self.assertRaisesRegex(ValueError, "mismatch " + field):
            m.collect(self.root)

    def test_valid_complete_campaign(self):
        result = m.collect(self.root, expected_head="1" * 40, expected_tree="2" * 40)
        self.assertEqual(result["status"], "IMPLEMENTER_EXACT_PASS")
        self.assertEqual(result["result"], self.valid())
        self.assertEqual(len(result["logs"]), 8)

    def test_canonical_linux_identity(self):
        rows = self.set_identity(m.LINUX_GODOT_SHA256)
        m.validate_identity(rows, rows)

    def test_canonical_windows_campaign(self):
        self.set_identity(m.WINDOWS_GODOT_SHA256)
        self.assertEqual(m.collect(self.root)["result"], self.valid())

    def test_unknown_engine_rejected(self):
        self.set_identity("0" * 64)
        with self.assertRaisesRegex(ValueError, "engine sha"):
            m.collect(self.root)

    def test_identity_movement_rejected(self):
        (self.root / "identity-after.txt").write_text("moved\n")
        with self.assertRaisesRegex(ValueError, "identity moved"):
            m.collect(self.root)

    def test_wrong_expected_head_tree_hash_rejected(self):
        for key in ("expected_head", "expected_tree", "expected_hash"):
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, "expected "):
                m.collect(self.root, **{key: "f" * (64 if key == "expected_hash" else 40)})

    def test_wrong_local_workset_rejected(self):
        self.bad_field("local_recursive_changed", 15)

    def test_false_global_structural_causality_rejected(self):
        self.bad_field("global_structural_parts_scanned", 100000)

    def test_missing_real_global_control_rejected(self):
        self.bad_field("explicit_global_control_parts_scanned", 0)

    def test_structural_change_under_global_event_rejected(self):
        self.bad_field("global_structural_state_unchanged", False)

    def test_physical_change_under_control_rejected(self):
        self.bad_field("explicit_global_control_state_unchanged", False)

    def test_incomplete_rollback_campaign_rejected(self):
        self.bad_field("rollback_rejected_events", 10)

    def test_partial_rollback_rejected(self):
        self.bad_field("rollback_state_unchanged_events", 10)

    def test_uninitialized_gap_rejected(self):
        self.bad_field("uninitialized_rejections", 0)

    def test_bool_and_float_are_not_integer_evidence(self):
        for value in (False, 0.0):
            with self.subTest(value=value):
                self.bad_field("global_structural_parts_scanned", value)

    def test_old_result_schema_rejected(self):
        data = self.valid(); data["schema"] = "fabric.r5_4.mixed_complexity_100k.result.v1"
        self.write_sample(1, data)
        with self.assertRaisesRegex(ValueError, "schema"):
            m.collect(self.root)

    def test_unknown_or_missing_fields_rejected(self):
        for remove in (True, False):
            data = self.valid()
            if remove:
                del data["rollback_state_unchanged_events"]
            else:
                data["invented"] = 1
            self.write_sample(1, data)
            with self.subTest(remove=remove), self.assertRaisesRegex(ValueError, "result fields"):
                m.collect(self.root)

    def test_forged_printed_hash_rejected(self):
        path = self.root / "sample-1.log"
        rows = path.read_text().splitlines(); rows[1] = m.HASH_PREFIX + "0" * 64
        path.write_text("\n".join(rows) + "\n")
        with self.assertRaisesRegex(ValueError, "declared deterministic hash"):
            m.collect(self.root)

    def test_sample_payload_drift_rejected(self):
        data = self.valid(); data["final_machine_hash"] = "b" * 64
        self.write_sample(3, data)
        with self.assertRaisesRegex(ValueError, "payload mismatch"):
            m.collect(self.root)

    def test_duplicate_result_marker_rejected(self):
        path = self.root / "sample-1.log"; text = path.read_text()
        path.write_text(text + text.splitlines()[0] + "\n")
        with self.assertRaisesRegex(ValueError, "result marker count"):
            m.collect(self.root)

    def test_duplicate_json_key_rejected(self):
        path = self.root / "sample-1.log"
        path.write_text(path.read_text().replace(m.PREFIX + "{", m.PREFIX + '{"machine_parts":100000,', 1))
        with self.assertRaisesRegex(ValueError, "duplicate JSON key"):
            m.collect(self.root)

    def test_nonfinite_json_rejected(self):
        for number in ("NaN", "Infinity", "-Infinity", "1e400"):
            self.write_sample(1, self.valid())
            path = self.root / "sample-1.log"
            path.write_text(path.read_text().replace('"machine_parts":100000', '"machine_parts":' + number))
            with self.subTest(number=number), self.assertRaisesRegex(ValueError, "nonfinite"):
                m.collect(self.root)

    def test_fatal_sample_rejected_despite_pass_marker(self):
        path = self.root / "sample-1.log"; path.write_text(path.read_text() + "SCRIPT ERROR: fixture\n")
        with self.assertRaisesRegex(ValueError, "sample fatal"):
            m.collect(self.root)

    def test_wrong_pass_assertion_count_rejected(self):
        path = self.root / "sample-1.log"; path.write_text(path.read_text().replace("1048 assertions", "1001 assertions"))
        with self.assertRaisesRegex(ValueError, "PASS assertion count"):
            m.collect(self.root)

    def test_failed_python_contract_rejected(self):
        (self.root / "python-tests.log").write_text("Ran 1 test in 0.001s\nFAILED (failures=1)\n")
        with self.assertRaisesRegex(ValueError, "python contract"):
            m.collect(self.root)

    def test_wrong_regression_scope_rejected(self):
        (self.root / "r51-regression.log").write_text("FABRIC R5.1 QUANTITATIVE SCALE: PASS (93 assertions) count=5000\n")
        with self.assertRaisesRegex(ValueError, "regression r51"):
            m.collect(self.root)

    def test_fatal_import_rejected(self):
        (self.root / "import.log").write_text("ERROR: fixture\n")
        with self.assertRaisesRegex(ValueError, "import fatal"):
            m.collect(self.root)

    def test_missing_log_rejected(self):
        (self.root / "sample-2.log").unlink()
        with self.assertRaises(FileNotFoundError):
            m.collect(self.root)


if __name__ == "__main__":
    unittest.main()
