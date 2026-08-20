from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
IMPL_PATH = ROOT / "scripts/research/ecology/causal_colonization_program_compiler_v1.py"
CONTRACT_PATH = ROOT / "config/ecology/eco-evo3-e3-4-causal-colonization-contract.v1.json"
BINDING_PATH = ROOT / "config/ecology/accepted_inputs/e3_3_accepted_research_ecology_decomposition.binding.v1.json"
DECOMPOSITION_PATH = ROOT / "config/ecology/accepted_inputs/e3_3_candidate_research_ecology_decomposition.v1.json"
CATALOG_PATH = ROOT / "config/ecology/accepted_inputs/evo2_full_persisted_species_catalog.e3_4.v1.json"

spec = importlib.util.spec_from_file_location("e34_impl", IMPL_PATH)
impl = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(impl)


def load(path: pathlib.Path):
    return json.loads(path.read_text(encoding="utf-8"))


def rehash_contract(contract):
    body = copy.deepcopy(contract)
    body.pop("contract_hash", None)
    contract["contract_hash"] = impl.sha256_canonical(body)
    return contract


def vector(base: int):
    return {
        "water_opportunity_ppm": base,
        "light_opportunity_ppm": min(1_000_000, base + 250_000),
        "nutrient_opportunity_ppm": min(1_000_000, base + 120_000),
        "persistence_opportunity_ppm": min(1_000_000, base + 500_000),
        "limiting_resource_opportunity_ppm": min(1_000_000, base + 20_000),
        "establishment_opportunity_ppm": min(1_000_000, base + 5_000),
    }


def patch(pid: str, key: str, base: int):
    return {"research_patch_id": pid, "stable_spatial_key": key, "opportunity_vector": vector(base)}


def edge(eid: str, a: str, b: str, continuity: int):
    return {"research_edge_id": eid, "patch_a_id": a, "patch_b_id": b, "continuity_ppm": continuity}


def decomposition(contract, source_base=110_400):
    return {
        "authority": impl.AUTHORITY,
        "canonical_binding_resolved": False,
        "decomposition_hash": contract["accepted_e3_3"]["decomposition_hash"],
        "decomposition_provenance_hash": contract["accepted_e3_3"]["decomposition_provenance_hash"],
        "stable_planet_identity": "planet/test",
        "stable_time_key": "tf/test/t1",
        "patches": [
            patch("patch/p2", "cell-02", 180_000),
            patch("patch/p1", "cell-01", source_base),
            patch("patch/p3", "cell-03", 260_000),
            patch("patch/p4", "cell-99", 400_000),
        ],
        "edges": [
            edge("edge/e2", "patch/p2", "patch/p3", 900_000),
            edge("edge/e1", "patch/p1", "patch/p2", 940_000),
        ],
        "regions": [{"research_region_id": "r1"}, {"research_region_id": "r2"}],
    }


def program_fixture(source_base=110_400):
    contract = load(CONTRACT_PATH)
    catalog = load(CATALOG_PATH)
    return contract, catalog, decomposition(contract, source_base)


def authoritative_program():
    contract = impl.load_contract(CONTRACT_PATH)
    decomposition_value = impl.load_accepted_decomposition(DECOMPOSITION_PATH, BINDING_PATH, contract)
    catalog = impl.load_full_persisted_catalog(CATALOG_PATH, contract)
    return impl.build_colonization_program(contract, decomposition_value, catalog)


class E34Tests(unittest.TestCase):
    def test_01_contract_valid(self):
        impl.validate_contract(load(CONTRACT_PATH))

    def test_02_contract_hash_exact(self):
        c = load(CONTRACT_PATH); body = copy.deepcopy(c); claimed = body.pop("contract_hash")
        self.assertEqual(claimed, impl.sha256_canonical(body))

    def test_03_catalog_hash_exact(self):
        self.assertEqual(load(CATALOG_PATH)["catalog_hash"], "5fcd8b90135cd8af69defc4f4a5ea26ede422ff82b25a0995bf5c6b10a53f219")

    def test_04_full_catalog_two_entries(self):
        self.assertEqual(len(load(CATALOG_PATH)["entries"]), 2)

    def test_05_catalog_order_preserved_in_manifest(self):
        c, cat, dec = program_fixture(); out = impl.build_colonization_program(c, dec, cat)
        self.assertEqual([e["research_species_id"] for e in cat["entries"]], [e["research_species_id"] for e in out["input_species_manifest"]])

    def test_06_all_catalog_entries_at_source_port(self):
        c, cat, dec = program_fixture(); out = impl.build_colonization_program(c, dec, cat)
        self.assertEqual(out["source_port"]["species_entry_count"], len(cat["entries"]))
        self.assertEqual(out["source_port"]["species_ids"], [e["research_species_id"] for e in cat["entries"]])

    def test_07_source_port_is_lexicographic_lowest_key(self):
        c, cat, dec = program_fixture(); out = impl.build_colonization_program(c, dec, cat)
        self.assertEqual(out["source_port"]["stable_spatial_key"], "cell-01")
        self.assertEqual(out["source_port"]["research_patch_id"], "patch/p1")

    def test_08_disconnected_patch_stays_unreachable(self):
        c, cat, dec = program_fixture(); out = impl.build_colonization_program(c, dec, cat)
        for sp in out["species_programs"]:
            ev = next(x for x in sp["patch_evaluations"] if x["research_patch_id"] == "patch/p4")
            self.assertEqual(ev["decision"], "UNREACHABLE")

    def test_09_propagates_over_established_chain(self):
        c, cat, dec = program_fixture(); out = impl.build_colonization_program(c, dec, cat)
        for sp in out["species_programs"]:
            self.assertIn("patch/p3", sp["established_patch_ids"])

    def test_10_current_catalog_colonizes(self):
        c, cat, dec = program_fixture(); out = impl.build_colonization_program(c, dec, cat)
        self.assertEqual(out["colonization_result"], "COLONIZATION_PRESENT")
        self.assertEqual(out["summary"]["colonized_species_count"], 2)

    def test_11_no_colonization_is_valid(self):
        c, cat, dec = program_fixture(20_000); out = impl.build_colonization_program(c, dec, cat)
        impl.validate_program_integrity(out)
        self.assertEqual(out["colonization_result"], "NO_COLONIZATION")
        self.assertTrue(out["summary"]["no_colonization"])

    def test_12_species_can_be_causally_filtered_without_input_prefilter(self):
        c, cat, dec = program_fixture(); cat = copy.deepcopy(cat)
        beta = cat["entries"][0]
        beta["genome"]["water_tolerance_width"] = 0.0
        beta["genome"]["shade_tolerance"] = 0.0
        beta["genome"]["root_depth_m"] = 0.0
        beta["recruitment_traits"]["dormancy_fraction"] = 0.0
        beta["recruitment_traits"]["seed_bank_half_life_years"] = 0.0
        out = impl.build_colonization_program(c, dec, cat)
        self.assertEqual(out["summary"]["input_species_count"], 2)
        self.assertGreaterEqual(out["summary"]["filtered_species_count"], 1)

    def test_13_output_is_research_only(self):
        c, cat, dec = program_fixture(); out = impl.build_colonization_program(c, dec, cat)
        self.assertEqual(out["authority"], impl.AUTHORITY)
        self.assertFalse(out["canonical_binding_resolved"])
        self.assertFalse(out["production_binding_authorized"])

    def test_14_authoritative_provenance_carries_e2_final(self):
        out = authoritative_program()
        self.assertEqual(out["provenance"]["e2_final_aggregate_hash"], "6daab256af3d1e7693c66a8afaad4d04fd1564c4376b9f3cd747a268a10c2250")

    def test_15_authoritative_provenance_carries_historical_anchor(self):
        out = authoritative_program()
        self.assertEqual(out["provenance"]["historical_eco_anchor"], "f0e16195f1331f238bbacab2768e5d72ec01d1a3")

    def test_16_authoritative_provenance_carries_transport_sha(self):
        out = authoritative_program()
        self.assertEqual(out["provenance"]["persisted_evo2_transport_sha256"], "b31c863f8e1943e5778d56631f8c8ad75b95f3b9d3930a699f80fd07595d45d1")

    def test_17_program_hash_valid(self):
        c, cat, dec = program_fixture(); out = impl.build_colonization_program(c, dec, cat)
        impl.validate_program_integrity(out)

    def test_18_program_serialization_deterministic(self):
        c, cat, dec = program_fixture(); a = impl.serialize_program(impl.build_colonization_program(c, dec, cat)); b = impl.serialize_program(impl.build_colonization_program(c, dec, cat))
        self.assertEqual(a, b)

    def test_19_input_order_of_patches_does_not_change_output(self):
        c, cat, dec = program_fixture(); a = impl.build_colonization_program(c, dec, cat); dec = copy.deepcopy(dec); dec["patches"].reverse(); b = impl.build_colonization_program(c, dec, cat)
        self.assertEqual(a, b)

    def test_20_input_order_of_edges_does_not_change_output(self):
        c, cat, dec = program_fixture(); a = impl.build_colonization_program(c, dec, cat); dec = copy.deepcopy(dec); dec["edges"].reverse(); b = impl.build_colonization_program(c, dec, cat)
        self.assertEqual(a, b)

    def test_21_contract_biome_table_promotion_rejected_after_rehash(self):
        c = load(CONTRACT_PATH); c["input_policy"]["biome_species_table_allowed"] = True; rehash_contract(c)
        with self.assertRaises(ValueError): impl.validate_contract(c)

    def test_22_contract_target_injection_rejected_after_rehash(self):
        c = load(CONTRACT_PATH); c["input_policy"]["target_aware_species_injection_allowed"] = True; rehash_contract(c)
        with self.assertRaises(ValueError): impl.validate_contract(c)

    def test_23_contract_prefilter_rejected_after_rehash(self):
        c = load(CONTRACT_PATH); c["input_policy"]["catalog_prefilter_allowed"] = True; rehash_contract(c)
        with self.assertRaises(ValueError): impl.validate_contract(c)

    def test_24_contract_rebake_rejected_after_rehash(self):
        c = load(CONTRACT_PATH); c["input_policy"]["catalog_rebake_allowed"] = True; rehash_contract(c)
        with self.assertRaises(ValueError): impl.validate_contract(c)

    def test_25_contract_target_tuning_rejected_after_rehash(self):
        c = load(CONTRACT_PATH); c["input_policy"]["catalog_target_tuning_allowed"] = True; rehash_contract(c)
        with self.assertRaises(ValueError): impl.validate_contract(c)

    def test_26_contract_production_promotion_rejected_after_rehash(self):
        c = load(CONTRACT_PATH); c["output_policy"]["production_binding_authorized"] = True; rehash_contract(c)
        with self.assertRaises(ValueError): impl.validate_contract(c)

    def test_27_contract_canonical_taxonomy_rejected_after_rehash(self):
        c = load(CONTRACT_PATH); c["output_policy"]["canonical_species_taxonomy"] = True; rehash_contract(c)
        with self.assertRaises(ValueError): impl.validate_contract(c)

    def test_28_contract_e3_5_promotion_rejected_after_rehash(self):
        c = load(CONTRACT_PATH); c["successor"]["e3_5_authorized"] = True; rehash_contract(c)
        with self.assertRaises(ValueError): impl.validate_contract(c)

    def test_29_catalog_missing_entry_rejected(self):
        c, cat, _ = program_fixture(); cat = copy.deepcopy(cat); cat["entries"].pop()
        with self.assertRaises(ValueError): impl.validate_catalog(cat, c)

    def test_30_catalog_extra_entry_rejected(self):
        c, cat, _ = program_fixture(); cat = copy.deepcopy(cat); cat["entries"].append(copy.deepcopy(cat["entries"][0])); cat["entries"][-1]["research_species_id"] += "x"
        with self.assertRaises(ValueError): impl.validate_catalog(cat, c)

    def test_31_catalog_canonical_promotion_rejected(self):
        c, cat, _ = program_fixture(); cat = copy.deepcopy(cat); cat["canonical_species_declared"] = True
        with self.assertRaises(ValueError): impl.validate_catalog(cat, c)

    def test_32_entry_canonical_promotion_rejected(self):
        c, cat, _ = program_fixture(); cat = copy.deepcopy(cat); cat["entries"][0]["canonical_species_declared"] = True
        with self.assertRaises(ValueError): impl.validate_catalog(cat, c)

    def test_33_duplicate_species_id_rejected(self):
        c, cat, _ = program_fixture(); cat = copy.deepcopy(cat); cat["entries"][1]["research_species_id"] = cat["entries"][0]["research_species_id"]
        with self.assertRaises(ValueError): impl.validate_catalog(cat, c)

    def test_34_decomposition_authority_promotion_rejected(self):
        c, cat, dec = program_fixture(); dec["authority"] = "CANONICAL"
        with self.assertRaises(ValueError): impl.build_colonization_program(c, dec, cat)

    def test_35_decomposition_canonical_binding_promotion_rejected(self):
        c, cat, dec = program_fixture(); dec["canonical_binding_resolved"] = True
        with self.assertRaises(ValueError): impl.build_colonization_program(c, dec, cat)

    def test_36_decomposition_hash_substitution_rejected(self):
        c, cat, dec = program_fixture(); dec["decomposition_hash"] = "0" * 64
        with self.assertRaises(ValueError): impl.build_colonization_program(c, dec, cat)

    def test_37_duplicate_patch_rejected(self):
        c, cat, dec = program_fixture(); dec["patches"].append(copy.deepcopy(dec["patches"][0]))
        with self.assertRaises(ValueError): impl.build_colonization_program(c, dec, cat)

    def test_38_edge_unknown_endpoint_rejected(self):
        c, cat, dec = program_fixture(); dec["edges"][0]["patch_b_id"] = "missing"
        with self.assertRaises(ValueError): impl.build_colonization_program(c, dec, cat)

    def test_39_edge_continuity_overflow_rejected(self):
        c, cat, dec = program_fixture(); dec["edges"][0]["continuity_ppm"] = 1_000_001
        with self.assertRaises(ValueError): impl.build_colonization_program(c, dec, cat)

    def test_40_program_hash_tamper_rejected(self):
        c, cat, dec = program_fixture(); out = impl.build_colonization_program(c, dec, cat); out["summary"]["colonized_patch_count"] += 1
        with self.assertRaises(ValueError): impl.validate_program_integrity(out)

    def test_41_authoritative_provenance_tamper_rejected(self):
        out = authoritative_program(); out["provenance"]["historical_eco_anchor"] = "0" * 40
        with self.assertRaises(ValueError): impl.validate_program_integrity(out)

    def test_42_manifest_species_drop_rejected_after_program_rehash(self):
        c, cat, dec = program_fixture(); out = impl.build_colonization_program(c, dec, cat); out["input_species_manifest"].pop(); body = copy.deepcopy(out); body.pop("colonization_program_hash"); out["colonization_program_hash"] = impl.sha256_canonical(body)
        with self.assertRaises(ValueError): impl.validate_program_integrity(out)

    def test_43_source_port_species_drop_rejected_after_program_rehash(self):
        c, cat, dec = program_fixture(); out = impl.build_colonization_program(c, dec, cat); out["source_port"]["species_ids"].pop(); body = copy.deepcopy(out); body.pop("colonization_program_hash"); out["colonization_program_hash"] = impl.sha256_canonical(body)
        with self.assertRaises(ValueError): impl.validate_program_integrity(out)

    def test_44_no_global_rng_import(self):
        text = IMPL_PATH.read_text(encoding="utf-8")
        self.assertNotIn("import random", text)
        self.assertNotIn("from random", text)
        self.assertNotIn("numpy.random", text)

    def test_45_no_snapshot_bypass_cli(self):
        text = IMPL_PATH.read_text(encoding="utf-8")
        self.assertNotIn('add_argument("--snapshot"', text)

    def test_46_no_fixture_bypass_cli(self):
        text = IMPL_PATH.read_text(encoding="utf-8")
        self.assertNotIn('add_argument("--fixture"', text)

    def test_47_no_biome_species_lookup_surface(self):
        text = IMPL_PATH.read_text(encoding="utf-8").lower()
        self.assertNotIn("biome_to_species", text)
        self.assertNotIn("species_by_biome", text)
        self.assertNotIn('add_argument("--biome"', text)

    def test_48_serialized_artifact_ends_with_single_newline(self):
        c, cat, dec = program_fixture(); data = impl.serialize_program(impl.build_colonization_program(c, dec, cat))
        self.assertTrue(data.endswith(b"\n")); self.assertFalse(data.endswith(b"\n\n"))


if __name__ == "__main__":
    unittest.main()
