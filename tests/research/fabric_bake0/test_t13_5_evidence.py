import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location(
    "collector", ROOT / "scripts/research/fabric_bake0/collect_r5_2_t13_5_evidence.py"
)
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)

class EvidenceTests(unittest.TestCase):
    def payload(self):
        return {
            "schema":"fabric.t13_5.result.v1", "failures":[], "checks":700,
            "instances":100,
            "family_counts":{"family-a":40,"family-b":30,"family-c":20,"family-d":10},
            "family_registrations":5, "family_aliases":1, "unique_family_models":4,
            "compile_events":42, "naive_full_compile_events":3000, "compile_events_avoided":2958,
            "subtree_occurrences":120, "unique_subtree_hashes":42, "shared_subtree_hashes":29,
            "subtree_intern_events":42, "subtree_reuse_hits":78, "max_family_reuse":4,
            "runtime_steps":200, "evaluations":1000, "boundary_calls":19000,
            "compiled_group_visits":12000, "leaf_traversals":0,
            "damaged_instance":"family-instance-058", "damaged_family":"family-b",
            "damage_revision":1, "healthy_equivalent_after_damage":99,
            "damaged_diverged":True, "all_models_intact":True,
        }

    def test_valid(self):
        c.validate_result(self.payload())

    def test_adversarial_claims(self):
        cases = (
            ("instances", 99),
            ("unique_family_models", 5),
            ("compile_events", 3000),
            ("subtree_reuse_hits", 77),
            ("shared_subtree_hashes", 28),
            ("leaf_traversals", 1),
            ("healthy_equivalent_after_damage", 98),
            ("all_models_intact", False),
        )
        for key, value in cases:
            with self.subTest(key=key):
                d = self.payload()
                d[key] = value
                with self.assertRaises(ValueError):
                    c.validate_result(d)

    def test_log_markers(self):
        line = c.PREFIX + json.dumps(self.payload())
        valid = c.PASS + "\n" + line
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "sample.log"
            p.write_text(valid, encoding="utf-8")
            self.assertEqual(c.read_sample(p)["compile_events"], 42)
            p.write_text(valid + "\nERROR: broken\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                c.read_sample(p)

    def test_source_contract(self):
        runtime = (ROOT / "scripts/research/fabric_bake0/r5_t13_5_shared_families_runtime_v1.gd").read_text()
        fixture = (ROOT / "tests/research/fabric_bake0/fabric_r5_2_t13_5_family_fixture.gd").read_text()
        acceptance = (ROOT / "tests/research/fabric_bake0/fabric_r5_2_t13_5_shared_families_acceptance.gd").read_text()
        self.assertNotIn("res://tests/", runtime)
        self.assertNotIn("_compiler_v1.gd", runtime)
        self.assertIn("_subtree_pool", runtime)
        self.assertIn("_model_hash_to_owner", runtime)
        self.assertIn("unique_model_prepares", runtime)
        self.assertEqual(acceptance.count("FF.build_families()"), 1)
        self.assertIn("FF.compile_events == 42", acceptance)
        self.assertIn("INSTANCE_COUNT * 30", acceptance)
        self.assertNotIn(":= registry.family_subtree_hash", acceptance)
        self.assertIn('make_graph("NMC"', fixture)
        self.assertIn('make_graph("GLYCOL"', fixture)
        self.assertIn('make_graph("GAN"', fixture)

if __name__ == "__main__":
    unittest.main()
