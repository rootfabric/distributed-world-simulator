import copy
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("t16", ROOT / "scripts/research/fabric_bake0/collect_r5_2_t16_evidence.py")
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)

class EvidenceTests(unittest.TestCase):
    def payload(self):
        d = dict(c.COUNTS, schema="fabric.t16.result.v1", failures=[], cases={},
                 positive_trace_hash="a" * 64, max_energy_residual_j=1e-11, max_positive_boundary_error_k=1e-13)
        for name, (reason, execution) in c.CASES.items():
            row = dict(reason=reason, execution=execution)
            if name == "singular_elimination":
                row["artifact_empty"] = True
            else:
                row.update(source_preserved=True, state_preserved=True,
                           compact_calls=int(execution == "COMPACT_STEP_REFUSED"),
                           full_calls=int(execution in ("FULL", "FULL_STEP_REFUSED")),
                           candidate_calls=int(execution != "CANONICAL_HANDOFF_REQUIRED"),
                           compile_calls=0 if execution == "CANONICAL_HANDOFF_REQUIRED" or name in ("stale_frontier", "source_mutation_stale_capsule", "corrupt_capsule") else 1)
                if execution == "FULL":
                    n = 2 if name == "near_critical_step" else 1
                    row.update(full_substeps=n, source_cell_updates=128*n, physical_trace_hash="b"*64, events_hash="c"*64)
            d["cases"][name] = row
            if name != "singular_elimination":
                steps = (2 if name == "near_critical_step" else 1) if execution == "FULL" else 0
                row.update(full_solver_calls=steps, full_cell_updates=steps*128, execution_error="")
                if execution == "FULL_STEP_REFUSED":
                    row["execution_error"] = "T16_FULL_STATE_SCHEMA_INVALID" if name in ("extended_full_state", "missing_full_state") else "T16_FULL_STATE_DOMAIN_INVALID"
                elif execution == "COMPACT_STEP_REFUSED":
                    row["execution_error"] = "TEST_COMPACT_STEP_FAILURE"
        d["repair_r2"] = dict(temporal_pairs=22, temporal_compact_pairs=10, temporal_full_pairs=12,
                              max_temporal_output_error_k=1e-13, r1_f1_discrepancy_k=0.0, temporal_trace_hash="d"*64)
        return d

    def test_valid(self): c.validate_result(self.payload())
    def test_top_level_adversaries(self):
        for key, bad in (("checks", 1), ("checks", True), ("failures", ["broken"]), ("positive_trace_hash", ""), ("max_energy_residual_j", float("nan")), ("max_positive_boundary_error_k", 1.0)):
            with self.subTest(key=key, bad=bad):
                d = self.payload(); d[key] = bad
                with self.assertRaises(ValueError): c.validate_result(d)
    def test_each_case_required(self):
        for name in c.CASES:
            with self.subTest(name=name):
                d = self.payload(); del d["cases"][name]
                with self.assertRaises(ValueError): c.validate_result(d)
    def test_fake_fallback(self):
        for field, value in (("full_calls", 0), ("compact_calls", 1), ("state_preserved", False), ("physical_trace_hash", ""), ("source_cell_updates", 0), ("execution", "COMPACT")):
            d = self.payload(); d["cases"]["hidden_mode"][field] = value
            with self.subTest(field=field), self.assertRaises(ValueError): c.validate_result(d)
    def test_no_authority_bypass(self):
        d = self.payload(); d["cases"]["cross_authority"]["full_calls"] = 1
        with self.assertRaises(ValueError): c.validate_result(d)
    def test_no_double_executor(self):
        d = self.payload(); d["cases"]["compact_step_failure"]["full_calls"] = 1
        with self.assertRaises(ValueError): c.validate_result(d)
    def test_actual_temporal_policy(self):
        for key, bad in (("temporal_pairs", 0), ("temporal_compact_pairs", 0), ("temporal_full_pairs", 0), ("max_temporal_output_error_k", 0.83), ("r1_f1_discrepancy_k", 0.83), ("temporal_trace_hash", "")):
            d = self.payload(); d["repair_r2"][key] = bad
            with self.subTest(key=key), self.assertRaises(ValueError): c.validate_result(d)
    def test_live_handoff_does_not_execute(self):
        for name in ("live_cross_authority", "live_frontier_advanced", "live_missing"):
            for key in ("candidate_calls", "compile_calls", "full_calls", "compact_calls", "full_solver_calls", "full_cell_updates"):
                d = self.payload(); d["cases"][name][key] = 1
                with self.subTest(name=name, key=key), self.assertRaises(ValueError): c.validate_result(d)
    def test_unknown_state_does_not_advance(self):
        for key, bad in (("execution", "FULL"), ("execution_error", ""), ("full_solver_calls", 1), ("full_cell_updates", 128)):
            d = self.payload(); d["cases"]["extended_full_state"][key] = bad
            with self.subTest(key=key), self.assertRaises(ValueError): c.validate_result(d)
    def test_r1_evidence_is_not_r2(self):
        d = self.payload(); del d["repair_r2"]
        with self.assertRaises(ValueError): c.validate_result(d)
    def test_strict_json(self):
        for s in ('{"x": NaN}', '{"x": 1, "x": 2}', '[]'):
            with self.assertRaises(ValueError): c.strict_json(s)
    def test_logs(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "sample.log"
            valid = c.PREFIX + json.dumps(self.payload()) + "\n" + c.PASS + "\n"
            p.write_text(valid, encoding="utf-8"); c.read_sample(p)
            for bad in (valid + "ERROR: broken", valid + valid, valid.replace(c.PASS, "FAIL")):
                p.write_text(bad, encoding="utf-8")
                with self.assertRaises(ValueError): c.read_sample(p)
    def test_runtime_has_no_device_or_test_import(self):
        text = (ROOT / "scripts/research/fabric_bake0/r5_t16_no_safe_bake_runtime_v1.gd").read_text()
        self.assertNotIn("res://tests/", text)
        self.assertNotIn("thermal_", text)
        self.assertNotIn("register_family(", text)
        self.assertNotIn("assert(", text)
        self.assertIn("CANONICAL_HANDOFF_REQUIRED", text)
        self.assertIn("RECONSTRUCTION_NOT_EXACT", text)
        self.assertIn("T16_COMPACT_STEP_REFUSED", text)

if __name__ == "__main__": unittest.main()
