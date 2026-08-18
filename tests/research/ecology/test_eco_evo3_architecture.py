from __future__ import annotations
import copy
import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
MOD_PATH = ROOT / "scripts/research/ecology/validate_evo3_architecture.py"
spec = importlib.util.spec_from_file_location("evo3_validator", MOD_PATH)
v = importlib.util.module_from_spec(spec); assert spec.loader; spec.loader.exec_module(v)

class Evo3ArchitectureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.a = v.load(v.ARCH_PATH); cls.r = v.load(v.ROADMAP_PATH)

    def good(self, a=None, r=None):
        v.validate_pair(copy.deepcopy(a or self.a), copy.deepcopy(r or self.r))

    def rehash_a(self,a): a["architecture_hash"]=v.canonical_hash(a,"architecture_hash")
    def rehash_r(self,r): r["roadmap_hash"]=v.canonical_hash(r,"roadmap_hash")
    def rejects(self, fn):
        a=copy.deepcopy(self.a); r=copy.deepcopy(self.r); fn(a,r); self.rehash_a(a); self.rehash_r(r)
        with self.assertRaises(v.ContractError): v.validate_pair(a,r)

    def test_01_canonical_pair_passes(self): self.good()
    def test_02_wrong_xfer0_head_rejected(self): self.rejects(lambda a,r:a["parent"].__setitem__("xfer0_code_under_test_head","0"*40))
    def test_03_wrong_xfer0_hash_rejected(self): self.rejects(lambda a,r:a["parent"].__setitem__("xfer0_contract_hash","0"*64))
    def test_04_production_binding_rejected(self): self.rejects(lambda a,r:a["scope"].__setitem__("production_binding",True))
    def test_05_runtime_implementation_rejected(self): self.rejects(lambda a,r:a["scope"].__setitem__("runtime_implementation",True))
    def test_06_missing_tf_rejected(self): self.rejects(lambda a,r:a["canonical_inputs"].__setitem__("required_foundations",["G","ENV","MAT","WQ","SD"]))
    def test_07_concrete_api_binding_rejected(self): self.rejects(lambda a,r:a["canonical_inputs"].__setitem__("binding_mode","PRODUCTION_API"))
    def test_08_catalog_source_bypass_rejected(self): self.rejects(lambda a,r:a["catalog_input"].__setitem__("source","DIRECT_BUILD"))
    def test_09_ir_authority_escalation_rejected(self): self.rejects(lambda a,r:a["compiler_ir"].__setitem__("authority","CANONICAL"))
    def test_10_stage_reorder_rejected(self): self.rejects(lambda a,r:a["stages"].reverse())
    def test_11_global_rng_rejected(self): self.rejects(lambda a,r:a["determinism"].__setitem__("global_rng_consumption_forbidden",False))
    def test_12_sd_region_promotion_rejected(self): self.rejects(lambda a,r:a["authority_barriers"].remove("NO_RESEARCH_REGION_AS_CANONICAL_SD_DOMAIN"))
    def test_13_suitability_truth_promotion_rejected(self): self.rejects(lambda a,r:a["authority_barriers"].remove("NO_COMPILED_SUITABILITY_AS_POPULATION_TRUTH"))
    def test_14_network_authority_rejected(self): self.rejects(lambda a,r:a["scope"].__setitem__("network_authority",True))
    def test_15_taxonomy_promotion_rejected(self): self.rejects(lambda a,r:a["scope"].__setitem__("canonical_species_taxonomy",True))
    def test_16_biome_species_table_rejected(self): self.rejects(lambda a,r:a["scope"].__setitem__("biome_species_table_allowed",True))
    def test_17_e31_skip_rejected(self): self.rejects(lambda a,r:r["steps"][1].__setitem__("status","SKIPPED"))
    def test_18_e32_premature_activation_rejected(self): self.rejects(lambda a,r:r["steps"][2].__setitem__("status","AUTHORIZED_NOT_STARTED"))
    def test_19_dependency_cycle_rejected(self): self.rejects(lambda a,r:r["steps"][0].__setitem__("depends_on",["E3.FINAL"]))
    def test_20_xfer1_unblock_rejected(self): self.rejects(lambda a,r:r["xfer1_relation"].__setitem__("status","READY"))
    def test_21_production_without_xfer1_rejected(self): self.rejects(lambda a,r:r["xfer1_relation"].__setitem__("production_binding_may_not_continue_without_xfer1",False))
    def test_22_species_assignment_rule_rejected(self): self.rejects(lambda a,r:r["checkpoint_rules"].__setitem__("e3_2_may_not_emit_species_assignment",False))
    def test_23_individual_truth_rule_rejected(self): self.rejects(lambda a,r:r["checkpoint_rules"].__setitem__("e3_5_planet_wide_individual_truth_forbidden",False))
    def test_24_final_shortcut_rule_rejected(self): self.rejects(lambda a,r:r["checkpoint_rules"].__setitem__("final_no_rebake_target_tuning_biome_table_or_asset_scatter",False))
    def test_25_hash_tamper_rejected(self):
        a=copy.deepcopy(self.a); a["architecture_hash"]="0"*64
        with self.assertRaises(v.ContractError): v.validate_pair(a, copy.deepcopy(self.r))

if __name__=="__main__":
    unittest.main(verbosity=0)
