"""Baseline-only R3C3 source-grounded oracle, not a claim of performance PASS."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / "tools/net_smooth1/r3c3_earth_hotpath_audit.py"
spec = importlib.util.spec_from_file_location("r3c3_earth_hotpath_audit", MODULE)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class R3C3R0SourceAudit(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report = mod.audit(ROOT)

    def test_exact_baseline_geometry_samples(self):
        self.assertEqual(self.report["counts_from_config"]["global_mesh_sample_positions"], 8385)
        self.assertEqual(self.report["counts_from_config"]["local_mesh_sample_positions_per_build"], 13825)

    def test_all_vegetation_attempt_upper_bounds_are_config_derived(self):
        c = self.report["counts_from_config"]
        self.assertEqual(c["placement_tree_attempt_upper_bound"], 27200)
        self.assertEqual(c["placement_grass_attempt_upper_bound"], 42000)
        self.assertEqual(c["placement_rock_attempt_upper_bound"], 6900)
        self.assertEqual(c["placement_total_attempt_upper_bound"], 76100)

    def test_actual_call_graph_has_both_default_spawn_rebuilds(self):
        self.assertTrue(self.report["two_local_build_requests_during_initial_scene"])
        self.assertTrue(all(self.report["source_call_graph"].values()))

    def test_legacy_recenter_is_synchronous_and_clears_instances(self):
        c = self.report["source_call_graph"]
        self.assertTrue(c["recenter_requests_local_synchronously"])
        self.assertTrue(c["placement_clears_old_instances_first"])

    def test_diagnostics_never_fabricate_gui_acceptance(self):
        self.assertEqual(self.report["evidence_class"], "SOURCE_ONLY_BASELINE")
        self.assertTrue(self.report["not_runtime_acceptance"])
        self.assertFalse(self.report["runtime_or_gui_performance_verified"])
        self.assertFalse(self.report["actual_attempts_or_sample_duration_measured"])

    def test_audit_contains_no_mutations_of_game_code(self):
        s = MODULE.read_text(encoding="utf-8")
        self.assertNotIn("subprocess.run([\"godot\"", s)
        self.assertNotIn("write_text(", s[s.index("def source_is_blocking"):s.index("def audit")])
        self.assertIn("R3C3 RED oracle no longer reproduces exact source blocking chain", s)


if __name__ == "__main__":
    unittest.main()
