import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("collector", ROOT / "scripts/research/fabric_bake0/collect_r5_2_t12_evidence.py")
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)

class EvidenceTests(unittest.TestCase):
    def payload(self):
        return {"schema":"fabric.t12.result.v1", "failures":[], "instances":3, "leaf_components":4275,
                "state_scalars":31, "steps":2048, "leaf_traversals":0, "checks":8390,
                "max_energy_residual_j":1e-9, "max_bus_residual_j":1e-10, "max_reference_current_error_a":1e-8,
                "max_evaluations_per_step":9, "evaluations":4096, "compiled_group_visits":49152,
                "boundary_calls":77824, "total_optical_j":100, "total_pump_j":2, "regeneration_current_a":-1,
                "overload_error":"T12_SHARED_POWER_LIMIT", "refine_path":"root/bank/unit03/cannon/emitter",
                "capsule_checksum":"a"*64, "final_state_hash":"b"*64}

    def test_valid(self):
        c.validate_result(self.payload())

    def test_adversarial_claims(self):
        for key, val in (("failures", ["failed"]), ("leaf_traversals", 1), ("steps", 1),
                         ("max_energy_residual_j", float("nan")), ("regeneration_current_a", 0),
                         ("boundary_calls", 0), ("refine_path", "root"), ("checks", 10)):
            with self.subTest(key=key):
                d = self.payload(); d[key] = val
                with self.assertRaises(ValueError): c.validate_result(d)

    def test_log_markers_and_fatal_errors(self):
        line = c.PREFIX + json.dumps(self.payload())
        for text in (line, c.PASS + "\n" + line + "\n" + line,
                     c.PASS + "\nSCRIPT ERROR: broken\n" + line):
            with tempfile.TemporaryDirectory() as tmp:
                p = Path(tmp)/"sample.log"; p.write_text(text)
                with self.assertRaises(ValueError): c.read_sample(p)

    def test_runtime_does_not_import_source_fixtures(self):
        for p in (ROOT / "scripts/research/fabric_bake0").glob("r5_t12_*runtime_v1.gd"):
            text = p.read_text()
            self.assertNotIn("res://tests/", text)
            self.assertNotIn("_fixture.gd", text)
            self.assertNotIn("_compiler_v1.gd", text)

if __name__ == "__main__": unittest.main()
