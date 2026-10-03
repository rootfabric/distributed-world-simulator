import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location(
    "collector", ROOT / "scripts/research/fabric_bake0/collect_r5_2_t14_evidence.py"
)
c = importlib.util.module_from_spec(spec)
spec.loader.exec_module(c)

class EvidenceTests(unittest.TestCase):
    def payload(self):
        return {
            "schema":"fabric.t14.result.v1", "failures":[], "checks":800,
            "instances":100,
            "family_counts":{"family-a":40,"family-b":30,"family-c":20,"family-d":10},
            "compile_events":42, "unique_family_models":4,
            "observed_instance":"t14-instance-058", "observed_family":"family-b",
            "refined_path":"root/bank/unit03/cannon",
            "detail_node_count":4, "detail_leaf_count":3,
            "selected_subtree_hash":"a"*64, "detail_manifest_hash":"b"*64,
            "refined_instances_during_observation":1,
            "compact_instances_during_observation":99,
            "same_instance_compact_siblings":5,
            "other_compact_instances":99,
            "physics_equivalent_after_refinement":100,
            "snapshot_roundtrip":True,
            "successful_requests":1, "restore_count":1, "release_count":2,
            "materialization_count":2, "detail_nodes_materialized":8,
            "source_leaf_traversals":0, "recompile_events":0,
            "active_refinements_final":0,
            "runtime_steps":200, "evaluations":1000,
            "boundary_calls":19000, "compiled_group_visits":12000,
            "physics_leaf_traversals":0,
            "caller_instances_unchanged":True,
            "model_identities_unchanged":True,
            "all_models_intact":True,
        }

    def test_valid(self):
        c.validate_result(self.payload())

    def test_adversarial_claims(self):
        cases = (
            ("instances", 99),
            ("detail_node_count", 30),
            ("compact_instances_during_observation", 98),
            ("same_instance_compact_siblings", 4),
            ("physics_equivalent_after_refinement", 99),
            ("detail_nodes_materialized", 30),
            ("source_leaf_traversals", 1),
            ("recompile_events", 1),
            ("active_refinements_final", 1),
            ("caller_instances_unchanged", False),
            ("model_identities_unchanged", False),
            ("all_models_intact", False),
        )
        for key, value in cases:
            with self.subTest(key=key):
                d = self.payload()
                d[key] = value
                with self.assertRaises(ValueError):
                    c.validate_result(d)

    def test_log_markers(self):
        raw = json.dumps(self.payload(), sort_keys=True, separators=(",", ":"))
        valid = c.PASS + " (800 assertions)\n" + c.PREFIX + raw
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "sample.log"
            p.write_text(valid, encoding="utf-8")
            row, value = c.read_sample(p)
            self.assertEqual(row, raw)
            self.assertEqual(value["detail_node_count"], 4)
            p.write_text(valid + "\nERROR: broken\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                c.read_sample(p)

    def test_source_contract(self):
        runtime = (ROOT / "scripts/research/fabric_bake0/r5_t14_observation_refinement_runtime_v1.gd").read_text()
        acceptance = (ROOT / "tests/research/fabric_bake0/fabric_r5_2_t14_observation_refinement_acceptance.gd").read_text()
        self.assertNotIn("res://tests/", runtime)
        self.assertNotIn("_compiler_v1.gd", runtime)
        self.assertIn("r5_t13_5_shared_families_runtime_v1.gd", runtime)
        self.assertIn("T14_ROOT_REFINEMENT_FORBIDDEN", runtime)
        self.assertIn("T14_INSTANCE_ALREADY_REFINED", runtime)
        self.assertIn("T14_SNAPSHOT_INSTANCE_MISMATCH", runtime)
        self.assertIn("T14_SNAPSHOT_MODEL_MISMATCH", runtime)
        self.assertIn("source_leaf_traversals", runtime)
        self.assertIn("recompile_events", runtime)
        self.assertIn('for field in ["state_revision", "damage_revision", "detail_node_count", "detail_leaf_count"]:', runtime)
        self.assertIn("U.is_json_integer(metadata.get(field))", runtime)
        self.assertEqual(acceptance.count("FF.build_families()"), 1)
        self.assertIn('REFINED_PATH := "root/bank/unit03/cannon"', acceptance)
        self.assertIn("physics_equivalent == 100", acceptance)
        self.assertIn("compact_siblings == 5", acceptance)
        self.assertIn("other_compact == 99", acceptance)
        self.assertIn('REFINED_PATH + "/not-real"', acceptance)
        self.assertIn("T14_SNAPSHOT_MODEL_MISMATCH", acceptance)
        self.assertIn("detail_nodes_materialized) == 8", acceptance)
        self.assertIn("FF.compile_events == 42", acceptance)

if __name__ == "__main__":
    unittest.main()
