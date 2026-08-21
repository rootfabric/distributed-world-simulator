from __future__ import annotations

import importlib.util
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
IMPL = ROOT / "scripts/research/ecology/cross_planet_generalization_matrix_v1.py"
CONTRACT = ROOT / "config/ecology/eco-evo3-e3-8-cross-planet-matrix-contract.v1.json"
SCHEMA = ROOT / "config/ecology/eco-evo3-e3-8-cross-planet-generalization-matrix.schema.v1.json"


def load_impl():
    spec = importlib.util.spec_from_file_location("e38_impl_semantic", IMPL)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TestE38GeneralizationMatrix(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_impl()
        cls.inputs = cls.mod.load_verified_inputs(CONTRACT)
        cls.matrix = cls.mod.build_planet_generalization_matrix(cls.inputs)

    def test_01_exact_accepted_inputs_load(self):
        self.assertEqual(type(self.inputs).__name__, "_VerifiedMatrixInputs")
        ai = self.inputs.contract["accepted_inputs"]
        self.assertEqual(self.inputs.snapshot["snapshot_hash"], ai["e3_1_snapshot_hash"])
        self.assertEqual(self.inputs.catalog["catalog_hash"], ai["catalog_hash"])
        self.assertEqual(len(self.inputs.catalog["entries"]), 2)

    def test_02_predeclared_six_families_in_order(self):
        families = [f["family"] for f in self.inputs.contract["predeclared_families"]]
        self.assertEqual(families, ["dry", "wet", "cold", "hot", "seasonal", "isolated"])

    def test_03_matrix_is_research_only(self):
        m = dict(self.matrix)
        self.assertEqual(m["authority"], "RESEARCH_DERIVED_NON_AUTHORITATIVE")
        self.assertFalse(m["canonical_binding_resolved"])
        self.assertFalse(m["production_binding_authorized"])

    def test_04_family_coverage_and_identity(self):
        self.assertEqual([f["family"] for f in self.matrix["families"]], ["dry", "wet", "cold", "hot", "seasonal", "isolated"])
        for f in self.matrix["families"]:
            self.assertTrue(f["stable_planet_identity"].startswith("eco-evo3-fixture/e3-8-family/" + f["family"] + "/"))

    def test_05_variant_snapshots_differ_from_accepted(self):
        accepted = self.inputs.snapshot["snapshot_hash"]
        for f in self.matrix["families"]:
            self.assertNotEqual(f["variant_snapshot_hash"], accepted)

    def test_06_outcome_classes_are_valid(self):
        valid = {"PRESERVED_COLONIZED", "PRESERVED_NO_COLONIZATION", "LOST_REVERSAL", "GAINED_ESTABLISHMENT"}
        for f in self.matrix["families"]:
            for sp in f["per_species"]:
                self.assertIn(sp["outcome_class"], valid)
                expected = {
                    ("COLONIZED", "COLONIZED"): "PRESERVED_COLONIZED",
                    ("NO_COLONIZATION", "NO_COLONIZATION"): "PRESERVED_NO_COLONIZATION",
                    ("COLONIZED", "NO_COLONIZATION"): "LOST_REVERSAL",
                    ("NO_COLONIZATION", "COLONIZED"): "GAINED_ESTABLISHMENT",
                }[(sp["baseline_status"], sp["family_status"])]
                self.assertEqual(sp["outcome_class"], expected)

    def test_07_null_no_colonization_outcome_preserved(self):
        statuses = [sp["family_status"] for f in self.matrix["families"] for sp in f["per_species"]]
        self.assertIn("NO_COLONIZATION", statuses)
        dry = [f for f in self.matrix["families"] if f["family"] == "dry"][0]
        self.assertTrue(all(sp["family_status"] == "NO_COLONIZATION" for sp in dry["per_species"]))

    def test_08_reversal_outcomes_present(self):
        reversals = [sp for f in self.matrix["families"] for sp in f["per_species"] if sp["outcome_class"] == "LOST_REVERSAL"]
        self.assertGreaterEqual(len(reversals), 2)

    def test_09_thermal_context_is_not_a_fitness_shortcut(self):
        baseline = self.matrix["accepted_inputs"]["baseline_species_statuses"]

        def statuses(family):
            f = [x for x in self.matrix["families"] if x["family"] == family][0]
            return {sp["research_species_id"]: sp["family_status"] for sp in f["per_species"]}

        self.assertEqual(statuses("cold"), baseline)
        self.assertEqual(statuses("hot"), baseline)

    def test_10_seasonality_pressure_changes_outcomes_without_time_ownership(self):
        seasonal = [f for f in self.matrix["families"] if f["family"] == "seasonal"][0]
        classes = {sp["outcome_class"] for sp in seasonal["per_species"]}
        self.assertIn("LOST_REVERSAL", classes)
        self.assertNotIn("history_write_allowed", seasonal)

    def test_11_isolated_topology_reduces_establishments(self):
        isolated = [f for f in self.matrix["families"] if f["family"] == "isolated"][0]
        wet = [f for f in self.matrix["families"] if f["family"] == "wet"][0]
        self.assertLess(isolated["summary"]["established_patch_total"], wet["summary"]["established_patch_total"])
        self.assertEqual(isolated["edge_continuity_scaling"], {"numerator": 100000, "denominator": 1000000})

    def test_12_catalog_untouched_and_modules_recorded(self):
        self.assertEqual(len(self.matrix["reused_modules"]), 3)
        for name, digest in self.matrix["reused_modules"].items():
            self.assertRegex(digest, r"^[0-9a-f]{64}$")

    def test_13_repeated_build_is_byte_identical(self):
        again = self.mod.build_planet_generalization_matrix(self.inputs)
        self.assertEqual(
            self.mod.serialize_planet_generalization_matrix(self.matrix),
            self.mod.serialize_planet_generalization_matrix(again),
        )

    def test_14_matrix_hash_recomputes(self):
        m = dict(self.matrix)
        self.assertEqual(m["cross_planet_generalization_matrix_hash"], self.mod.object_hash(m, "cross_planet_generalization_matrix_hash"))
        self.assertEqual(m["provenance_hash"], self.mod.sha256_hex(self.mod.canonical_bytes(m["provenance"])))

    def test_15_schema_validates(self):
        import jsonschema

        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        jsonschema.Draft202012Validator.check_schema(schema)
        jsonschema.Draft202012Validator(schema).validate(dict(self.matrix))

    def test_16_no_global_rng_clock_or_ambient_environment_surface(self):
        source = IMPL.read_text(encoding="utf-8")
        for token in ("import random", "from random", "time.time(", "datetime.now(", "os.environ", "os.getenv(", "uuid4("):
            self.assertNotIn(token, source)


if __name__ == "__main__":
    unittest.main()
