"""Regression controls for exit-zero Godot failures observed in run 35090924573."""
import os
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
os.environ.setdefault("MVP6_NX_PROBE_OUTPUT", str(HERE / "unused-output"))
os.environ.setdefault("MVP6_NX_PROBE_WORKTREE", str(HERE / "unused-worktree"))
os.environ.setdefault("GODOT_BIN", "unused-godot")
import mvp6_nx_dependency_probe as probe


class LogAdmission(unittest.TestCase):
    def test_real_false_green_logs_are_rejected_even_with_nonzero_assertions(self):
        for lane in ("baseline-current-main-plus-nx", "candidate-plus-mvp6-m4"):
            for name in ("test_nx_owner_movement_authority", "test_nx_owner_item_projection_rollback"):
                with self.subTest(lane=lane, name=name):
                    result = probe.inspect_log(HERE / "nx-false-green-r1" / lane / (name + ".log"), require_assertions=True)
                    self.assertFalse(result["log_valid"])
                    self.assertTrue(result["fatal_lines"])

    def test_clean_historical_controls_remain_valid(self):
        for name, count in (("test_nx_render_physics_separation", 31), ("test_nx_client_tick_robustness", 25), ("test_nx6_predicted_item_interactions", 940)):
            result = probe.inspect_log(HERE / "nx-false-green-r1/candidate-plus-mvp6-m4" / (name + ".log"), require_assertions=True)
            self.assertTrue(result["log_valid"])
            self.assertEqual(count, result["assertions"])

    def test_missing_zero_duplicate_or_fatal_pass_is_rejected(self):
        cases = ["", "NX: PASS (0 assertions)\n", "NX: PASS (44 assertions)\n" * 2,
                 "SCRIPT ERROR: invalid call\nNX: PASS (44 assertions)\n",
                 "ERROR: failed load\nNX: PASS (44 assertions)\n"]
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "test.log"
            for value in cases:
                with self.subTest(value=value):
                    path.write_text(value, encoding="utf-8")
                    self.assertFalse(probe.inspect_log(path, require_assertions=True)["log_valid"])

    def test_import_fatal_rejected_without_assertion_requirement(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "import.log"
            path.write_text("SCRIPT ERROR: parse failure\n", encoding="utf-8")
            self.assertFalse(probe.inspect_log(path, require_assertions=False)["log_valid"])

    def test_exit_zero_cannot_override_invalid_log_or_missing_test(self):
        rows = [{"exit_code": 0, "log_valid": True} for _ in range(6)]
        self.assertTrue(probe.passed(rows))
        self.assertFalse(probe.passed(rows[:-1]))
        rows[2]["log_valid"] = False
        self.assertFalse(probe.passed(rows))


if __name__ == "__main__":
    unittest.main()
