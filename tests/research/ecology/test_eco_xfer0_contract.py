from __future__ import annotations

import copy
import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
VALIDATOR_PATH = ROOT / "scripts" / "research" / "ecology" / "validate_xfer0_contract.py"
CONTRACT_PATH = ROOT / "config" / "ecology" / "eco-xfer0-contract.v1.json"

spec = importlib.util.spec_from_file_location("xfer0_validator", VALIDATOR_PATH)
validator = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(validator)


def load():
    return validator.load_contract(CONTRACT_PATH)


def rehash(value):
    value["contract_hash"] = validator._canonical_hash(value)
    return value


class Xfer0ContractTests(unittest.TestCase):
    def assert_invalid_after_rehash(self, mutated, expected_code_prefix):
        ok, errors = validator.validate_contract(rehash(mutated))
        self.assertFalse(ok, errors)
        self.assertTrue(any(e.startswith(expected_code_prefix) for e in errors), errors)

    def test_01_published_contract_is_valid(self):
        ok, errors = validator.validate_contract(load())
        self.assertTrue(ok, errors)

    def test_02_parent_evo2_final_pin_is_fail_closed(self):
        value = copy.deepcopy(load())
        value["parent_evo2"]["final_code_under_test"] = "0" * 40
        self.assert_invalid_after_rehash(value, "PARENT_PIN_MISMATCH:final_code_under_test")

    def test_03_production_activation_cannot_be_enabled(self):
        value = copy.deepcopy(load())
        value["scope"]["production_activation"] = True
        self.assert_invalid_after_rehash(value, "SCOPE_MUST_BE_FALSE:production_activation")

    def test_04_canonical_owner_mutation_cannot_be_enabled(self):
        value = copy.deepcopy(load())
        value["scope"]["canonical_owner_mutation"] = True
        self.assert_invalid_after_rehash(value, "SCOPE_MUST_BE_FALSE:canonical_owner_mutation")

    def test_05_canonical_foundation_set_cannot_be_reduced(self):
        value = copy.deepcopy(load())
        value["canonical_foundation_dependencies"]["required_before_xfer1"].remove("TF")
        self.assert_invalid_after_rehash(value, "FOUNDATION_ORDER_OR_SET_MISMATCH")

    def test_06_xfer0_cannot_bind_concrete_production_api(self):
        value = copy.deepcopy(load())
        value["interfaces"][0]["binding_mode"] = "CONCRETE_PRODUCTION_API"
        self.assert_invalid_after_rehash(value, "INTERFACE_BINDING_MODE:ENVIRONMENT_INPUT")

    def test_07_environment_input_cannot_gain_write_operation(self):
        value = copy.deepcopy(load())
        value["interfaces"][0]["allowed_operations"].append("WRITE_ENVIRONMENT")
        self.assert_invalid_after_rehash(value, "ENV_WRITE_SURFACE_DETECTED")

    def test_08_query_projection_cannot_mutate_world(self):
        value = copy.deepcopy(load())
        query = next(x for x in value["interfaces"] if x["id"] == "QUERY_PROJECTION")
        query["allowed_operations"].append("MUTATE_WORLD")
        self.assert_invalid_after_rehash(value, "QUERY_WRITE_SURFACE_DETECTED")

    def test_09_persistence_cannot_claim_durability(self):
        value = copy.deepcopy(load())
        persistence = next(x for x in value["interfaces"] if x["id"] == "PERSISTENCE_PAYLOAD")
        persistence["forbidden_operations"].remove("OWN_DURABILITY")
        self.assert_invalid_after_rehash(value, "PERSISTENCE_BARRIER_MISSING:OWN_DURABILITY")

    def test_10_research_identity_cannot_become_canonical_taxonomy(self):
        value = copy.deepcopy(load())
        identity = next(x for x in value["interfaces"] if x["id"] == "IDENTITY_PROVENANCE")
        identity["forbidden_operations"].remove("PROMOTE_TO_CANONICAL_TAXONOMY")
        self.assert_invalid_after_rehash(value, "TAXONOMY_BARRIER_MISSING")

    def test_11_promotion_surface_is_request_only(self):
        value = copy.deepcopy(load())
        promotion = next(x for x in value["interfaces"] if x["id"] == "REPRESENTATION_PROMOTION_REQUEST")
        promotion["allowed_operations"].append("CREATE_DURABLE_ENTITY")
        self.assert_invalid_after_rehash(value, "PROMOTION_MUST_BE_REQUEST_ONLY")

    def test_12_population_output_cannot_create_entity_truth(self):
        value = copy.deepcopy(load())
        state = next(x for x in value["interfaces"] if x["id"] == "ECOLOGY_STATE_OUTPUT")
        state["forbidden_operations"].remove("CREATE_PLANET_WIDE_ENTITY_TRUTH")
        self.assert_invalid_after_rehash(value, "STATE_ENTITY_TRUTH_BARRIER_MISSING")

    def test_13_xfer1_cannot_be_marked_ready(self):
        value = copy.deepcopy(load())
        value["xfer1_gate"]["status"] = "READY"
        self.assert_invalid_after_rehash(value, "XFER1_MUST_REMAIN_BLOCKED")

    def test_14_xfer0_cannot_be_treated_as_production_authorization(self):
        value = copy.deepcopy(load())
        value["xfer1_gate"]["may_treat_xfer0_as_production_authorization"] = True
        self.assert_invalid_after_rehash(value, "XFER0_PRODUCTION_AUTHORIZATION_FORBIDDEN")

    def test_15_evo3_cannot_gain_runtime_authority(self):
        value = copy.deepcopy(load())
        value["evo3_gate"]["production_runtime_authorized"] = True
        self.assert_invalid_after_rehash(value, "EVO3_RUNTIME_MUST_REMAIN_UNAUTHORIZED")

    def test_16_biome_species_table_shortcut_remains_forbidden(self):
        value = copy.deepcopy(load())
        value["scope"]["biome_species_table_allowed"] = True
        self.assert_invalid_after_rehash(value, "SCOPE_MUST_BE_FALSE:biome_species_table_allowed")

    def test_17_asset_scatter_cannot_become_ecology_truth(self):
        value = copy.deepcopy(load())
        value["scope"]["asset_scatter_as_ecology_truth_allowed"] = True
        self.assert_invalid_after_rehash(value, "SCOPE_MUST_BE_FALSE:asset_scatter_as_ecology_truth_allowed")


if __name__ == "__main__":
    unittest.main(verbosity=2)
