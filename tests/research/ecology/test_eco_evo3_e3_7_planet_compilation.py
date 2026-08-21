from __future__ import annotations

import hashlib
import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
IMPL = ROOT / "scripts/research/ecology/planet_ecology_program_compiler_v1.py"


def load_impl():
    spec = importlib.util.spec_from_file_location("e37_impl_semantic", IMPL)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TestE37PlanetCompilation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_impl()
        cls.inputs = cls.mod.load_verified_inputs()
        cls.program = cls.mod.build_planet_ecology_program(cls.inputs)

    def test_01_exact_chain_loads(self):
        self.assertEqual(set(self.inputs.values), {"e3_1", "e3_2", "e3_3", "e3_4", "catalog", "e3_5", "e3_6"})

    def test_02_program_is_research_only(self):
        self.assertEqual(self.program["authority"], "RESEARCH_DERIVED_NON_AUTHORITATIVE")
        self.assertFalse(self.program["canonical_binding_resolved"])
        self.assertFalse(self.program["production_binding_authorized"])

    def test_03_stable_identity_preserved(self):
        self.assertEqual(self.program["stable_planet_identity"], "eco-evo3-fixture/planet-alpha-01")
        self.assertEqual(self.program["stable_time_key"], "tf-fixture/planet-alpha/t000180")

    def test_04_exact_stage_artifacts_embedded(self):
        self.assertEqual(self.program["opportunity_field"], self.inputs.values["e3_2"])
        self.assertEqual(self.program["ecology_decomposition"], self.inputs.values["e3_3"])
        self.assertEqual(self.program["colonization_program"], self.inputs.values["e3_4"])
        self.assertEqual(self.program["population_workset"], self.inputs.values["e3_5"])
        self.assertEqual(self.program["temporal_program"], self.inputs.values["e3_6"])

    def test_05_species_manifest_is_full_persisted_catalog(self):
        catalog_ids = sorted(e["research_species_id"] for e in self.inputs.values["catalog"]["entries"])
        manifest_ids = [e["research_species_id"] for e in self.program["species_manifest"]]
        self.assertEqual(manifest_ids, catalog_ids)
        self.assertEqual(len(manifest_ids), 2)
        self.assertTrue(all(e["canonical_species_declared"] is False for e in self.program["species_manifest"]))

    def test_06_region_manifest_comes_from_e35_region_work_units(self):
        source = [u for u in self.inputs.values["e3_5"]["population_work_units"] if u.get("scale") == "REGION"]
        self.assertEqual(len(self.program["regions"]), len(source))
        self.assertGreaterEqual(len(source), 1)
        self.assertTrue(all(r["authority"] == "RESEARCH_SCHEDULING_IDENTITY_NON_CANONICAL" for r in self.program["regions"]))

    def test_07_projection_counts_are_consistent(self):
        p = self.program["projection"]
        self.assertEqual(p["catalog_entry_count"], 2)
        self.assertEqual(p["opportunity_sample_count"], len(self.inputs.values["e3_2"]["samples"]))
        self.assertEqual(p["research_patch_count"], len(self.inputs.values["e3_3"]["patches"]))
        self.assertEqual(p["research_edge_count"], len(self.inputs.values["e3_3"]["edges"]))
        self.assertEqual(p["temporal_envelope_count"], len(self.inputs.values["e3_6"]["temporal_envelopes"]))
        self.assertEqual(p["individual_entity_count"], 0)

    def test_08_e32_e33_spatial_linkage_exact(self):
        e32 = {x["stable_spatial_key"]: x for x in self.inputs.values["e3_2"]["samples"]}
        e33 = {x["stable_spatial_key"]: x for x in self.inputs.values["e3_3"]["patches"]}
        self.assertEqual(set(e32), set(e33))
        for key in e32:
            self.assertEqual(e33[key]["source_opportunity_id"], e32[key]["opportunity_id"])
            self.assertEqual(e33[key]["source_opportunity_sample_hash"], e32[key]["opportunity_sample_hash"])

    def test_09_temporal_fail_closed_semantics_preserved(self):
        temporal = self.program["temporal_program"]
        self.assertEqual(temporal["refresh_contract"]["seasonality_evidence_state"], "UNRESOLVED_SINGLE_SNAPSHOT")
        self.assertEqual(temporal["summary"]["future_disturbance_event_count"], 0)
        self.assertEqual(temporal["summary"]["canonical_history_write_count"], 0)
        for envelope in temporal["temporal_envelopes"]:
            self.assertEqual(envelope["disturbance_schedule"]["scheduled_events"], [])
            for observed in envelope["observed_envelopes"].values():
                self.assertEqual(observed["min"], observed["anchor"])
                self.assertEqual(observed["anchor"], observed["max"])

    def test_10_repeated_build_is_byte_identical(self):
        a = self.mod.serialize_planet_ecology_program(self.mod.build_planet_ecology_program(self.inputs))
        b = self.mod.serialize_planet_ecology_program(self.mod.build_planet_ecology_program(self.inputs))
        self.assertEqual(a, b)

    def test_11_program_hash_recomputes(self):
        self.assertEqual(self.program["planet_ecology_program_hash"], self.mod.object_hash(dict(self.program), "planet_ecology_program_hash"))
        self.assertEqual(self.program["provenance_hash"], hashlib.sha256(self.mod.canonical_bytes(self.program["provenance"])).hexdigest())

    def test_12_input_manifest_order_is_fixed(self):
        self.assertEqual([x["input"] for x in self.program["accepted_chain_manifest"]], ["e3_1", "e3_2", "e3_3", "e3_4", "catalog", "e3_5", "e3_6"])

    def test_13_no_global_rng_clock_or_ambient_environment_surface(self):
        source = IMPL.read_text(encoding="utf-8")
        forbidden = ("import random", "from random", "time.time(", "datetime.now(", "os.environ", "os.getenv(", "uuid4(")
        for token in forbidden:
            self.assertNotIn(token, source)

    def test_14_evidence_package_is_snapshot_bound(self):
        evidence = self.program["evidence_package"]
        self.assertTrue(evidence["accepted_chain_exact"])
        self.assertTrue(evidence["persisted_evo2_catalog_exact"])
        self.assertTrue(evidence["external_nondeterminism_snapshot_bound"])
        self.assertFalse(evidence["global_rng_used"])
        self.assertFalse(evidence["local_clock_used"])
        self.assertFalse(evidence["ambient_environment_used"])


if __name__ == "__main__":
    unittest.main()
