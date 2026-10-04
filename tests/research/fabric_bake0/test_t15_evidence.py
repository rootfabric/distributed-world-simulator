import importlib.util, json, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("collector", ROOT / "scripts/research/fabric_bake0/collect_r5_2_t15_evidence.py")
c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)

class EvidenceTests(unittest.TestCase):
    def payload(self):
        return {
            "schema":"fabric.t15.result.v1","failures":[],"checks":500,"instances":100,
            "family_counts":{"family-a":40,"family-b":30,"family-c":20,"family-d":10},
            "target_instance":"t15-instance-058","target_original_family":"family-b",
            "selected_path":"root/bank/unit03/cannon/emitter",
            "baseline_compile_events":42,"damage_compile_events":5,"repair_compile_events":5,
            "local_compile_events_total":10,"source_leaf_traversals_rebuild":256,
            "source_anchor_checks":2,"source_components_per_ship":4275,"changed_paths_per_mutation":5,"unchanged_subtrees_per_mutation":25,
            "original_family_models":4,"final_family_models":6,"final_unique_subtree_hashes":52,
            "final_subtree_occurrences":180,"final_subtree_reuse_hits":128,
            "healthy_equivalent_after_damage":99,"damaged_target_diverged":True,
            "repair_restored_healthy_behavior":True,"repair_differs_from_damaged_continuation":True,
            "physical_state_preserved_on_damage":True,"physical_state_preserved_on_repair":True,
            "final_damage_revision":2,"steady_leaf_traversals_after_damage":0,
            "fork_events":2,"state_projection_events":2,"superseded_rejections":2,
            "event_receipts":2,"current_instances":100,"original_models_intact":True,"all_models_intact":True,
            "atomicity_unsafe_reject_clean":True,"atomicity_retry_same_ids":True,
            "atomicity_alias_reject_clean":True,"atomicity_occupied_id_reject_clean":True,
        }
    def test_valid(self): c.validate_result(self.payload())
    def test_adversarial(self):
        for key, value in (
            ("damage_compile_events", 30),("source_leaf_traversals_rebuild", 4275),
            ("unchanged_subtrees_per_mutation", 24),("healthy_equivalent_after_damage", 98),
            ("repair_restored_healthy_behavior", False),("physical_state_preserved_on_damage", False),
            ("steady_leaf_traversals_after_damage", 1),("original_models_intact", False),("all_models_intact", False),
            ("atomicity_unsafe_reject_clean", False),("atomicity_retry_same_ids", False),
        ):
            with self.subTest(key=key):
                d=self.payload(); d[key]=value
                with self.assertRaises(ValueError): c.validate_result(d)
    def test_log_markers(self):
        raw=json.dumps(self.payload(), sort_keys=True, separators=(",", ":"))
        valid=c.PASS+" (500 assertions)\n"+c.PREFIX+raw
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/"sample.log"; p.write_text(valid, encoding="utf-8")
            row,value=c.read_sample(p); self.assertEqual(row,raw); self.assertEqual(value["local_compile_events_total"],10)
            p.write_text(valid+"\nERROR: broken\n", encoding="utf-8")
            with self.assertRaises(ValueError): c.read_sample(p)
    def test_source_contract(self):
        runtime=(ROOT/"scripts/research/fabric_bake0/r5_t15_local_damage_runtime_v1.gd").read_text()
        fixture=(ROOT/"tests/research/fabric_bake0/fabric_r5_2_t15_local_damage_fixture.gd").read_text()
        acceptance=(ROOT/"tests/research/fabric_bake0/fabric_r5_2_t15_local_damage_acceptance.gd").read_text()
        self.assertNotIn("res://tests/", runtime)
        self.assertNotIn("_compiler_v1.gd", runtime)
        self.assertIn("r5_t14_observation_refinement_runtime_v1.gd", runtime)
        self.assertIn("T15_INSTANCE_SUPERSEDED", runtime)
        self.assertIn("T15_ACTIVE_OBSERVATION_MUST_RELEASE", runtime)
        self.assertIn("T15_DIVERGENCE_NOT_LOCAL_TO_SELECTED_CHAIN", runtime)
        self.assertIn("_preflight_successor", runtime)
        self.assertIn("T15_FAMILY_ID_ALREADY_REGISTERED", runtime)
        self.assertIn("physical_state_hash_before", runtime)
        self.assertIn('EF.make_graph("GAAS", current_disabled)', fixture)
        self.assertIn("T15_SOURCE_UNBAKE_ANCHOR_MISMATCH", fixture)
        self.assertIn("source_leaf_traversals += int(emitter_graph.gain_cells.size())", fixture)
        self.assertIn("DF.compile_events == 5", acceptance)
        self.assertIn("healthy_equivalent == 99", acceptance)
        self.assertIn("repair_restored_behavior", acceptance)
        self.assertIn("T15_STATE_PROJECTION_UNSAFE", acceptance)
        self.assertIn("unsafe_reject_clean", acceptance)
        self.assertIn("retry_same_ids", acceptance)

if __name__ == "__main__": unittest.main()
