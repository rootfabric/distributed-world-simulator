import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("collector", ROOT / "scripts/research/fabric_bake0/collect_r5_2_t13_evidence.py")
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)

class EvidenceTests(unittest.TestCase):
    def payload(self):
        return {
            "schema":"fabric.t13.result.v1", "failures":[], "checks":1400,
            "instance_gates":[1,10,100], "gate_counts":{"1":1,"10":10,"100":100},
            "bindings":100, "unique_binding_checksums":100,
            "shared_compiled_model_checksum":"a"*64, "shared_compiled_model_hash":"b"*64,
            "source_components_per_model":4275, "state_scalars_per_instance":31,
            "prepare_count":1, "recompile_events":0, "runtime_steps":311,
            "leaf_traversals":0, "evaluations":1000, "boundary_calls":19000,
            "compiled_group_visits":12000, "damaged_instance":"instance-042",
            "damage_revision":1, "healthy_equivalent_after_damage":99,
            "damaged_diverged":True, "model_hash_unchanged":True,
            "caller_states_unchanged":True, "isolation_hash":"c"*64,
        }

    def test_valid(self):
        c.validate_result(self.payload())

    def test_adversarial_claims(self):
        cases = (
            ("prepare_count", 2), ("recompile_events", 1), ("bindings", 99),
            ("healthy_equivalent_after_damage", 98), ("model_hash_unchanged", False),
            ("caller_states_unchanged", False), ("leaf_traversals", 1),
            ("runtime_steps", 310),
        )
        for key, value in cases:
            with self.subTest(key=key):
                d = self.payload(); d[key] = value
                with self.assertRaises(ValueError):
                    c.validate_result(d)

    def test_log_markers_and_fatal_errors(self):
        line = c.PREFIX + json.dumps(self.payload())
        for text in (line, c.PASS + "\n" + line + "\n" + line,
                     c.PASS + "\nSCRIPT ERROR: broken\n" + line):
            with tempfile.TemporaryDirectory() as tmp:
                p = Path(tmp) / "sample.log"
                p.write_text(text)
                with self.assertRaises(ValueError):
                    c.read_sample(p)

    def test_runtime_is_fixture_free_and_acceptance_compiles_once(self):
        runtime = (ROOT / "scripts/research/fabric_bake0/r5_t13_shared_instances_runtime_v1.gd").read_text()
        acceptance = (ROOT / "tests/research/fabric_bake0/fabric_r5_2_t13_shared_instances_acceptance.gd").read_text()
        self.assertNotIn("res://tests/", runtime)
        self.assertNotIn("_compiler_v1.gd", runtime)
        self.assertEqual(acceptance.count("F.make_ship()"), 1)
        self.assertNotIn("replace_third_emitter", acceptance)
        self.assertNotIn("U.canonical_hash(bundle)", acceptance)
        self.assertIn("exact_binary_hash(bundle)", acceptance)

if __name__ == "__main__":
    unittest.main()
