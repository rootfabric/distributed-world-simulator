from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HARNESS = ROOT / "config" / "control" / "harness"
CONTROL = ROOT / "config" / "control"


EXPECTED_DOMAIN_IDS = frozenset(
    {
        "DEVELOPMENT_CONTROL",
        "ACCOUNT_AND_SESSION_IDENTITY",
        "AUTHORITY_OWNERSHIP_AND_FENCING",
        "NETWORK_TRANSPORT_REPLICATION_PREDICTION_RECONCILIATION",
        "CANONICAL_ITEM_GRAPH_INVENTORY_CONTAINERS",
        "EQUIPMENT_AND_TOOLS",
        "CONSTRUCTION",
        "PERSISTENCE_REPLAY_RECOVERY",
        "OPERATION_ID_DEDUP_IDEMPOTENCY",
        "RESOURCE_MINING_GAMEPLAY",
        "PERSISTENT_SHARED_OUTPOST_COMPOSITION",
        "EDGE_GATEWAY_COMMAND_SESSION_ROUTING",
        "WARM_SHADOW_COMPATIBILITY",
        "PRODUCTION_OWNERSHIP_DIRECTORY_AND_DOMAIN_TRANSFER",
        "SEAMLESS_RESEARCH_AND_MRPF",
    }
)

EXPECTED_REGISTRY_BINDINGS = {
    "DEVELOPMENT_CONTROL": "DEVELOPMENT_HARNESS",
    "ACCOUNT_AND_SESSION_IDENTITY": "IDENTITY_SESSION_FABRIC",
    "AUTHORITY_OWNERSHIP_AND_FENCING": "AUTHORITY_FOUNDATION",
    "NETWORK_TRANSPORT_REPLICATION_PREDICTION_RECONCILIATION": "NETWORK_REPLICATION_POLICY",
    "CANONICAL_ITEM_GRAPH_INVENTORY_CONTAINERS": "ITEM_IDENTITY_AND_GRAPH",
    "EQUIPMENT_AND_TOOLS": "ITEM_IDENTITY_AND_GRAPH",
    "CONSTRUCTION": "CONSTRUCTION_TRUTH",
    "PERSISTENCE_REPLAY_RECOVERY": "PERSISTENCE_DURABILITY",
    "OPERATION_ID_DEDUP_IDEMPOTENCY": "WORLD_TRANSACTION_MODEL",
    "WARM_SHADOW_COMPATIBILITY": "DERIVED_PRESENTATION",
}

EXPECTED_NON_REGISTRY_CONTRACTS = {
    "RESOURCE_MINING_GAMEPLAY": {
        "source_kind": "ACCEPTED_PRODUCT_COMPOSITION",
        "canonical_owner": "V0_P3_RESOURCE_MINING_RULE",
        "canonical_output_foundation_owner": "ITEM",
        "classification": "ADAPT",
    },
    "PERSISTENT_SHARED_OUTPOST_COMPOSITION": {
        "source_kind": "PRODUCT_COMPOSITION",
        "canonical_owner": "COMPOSITE_EXISTING_OWNERS",
        "classification": "ADAPT",
        "canonical_components": {
            "ITEM",
            "CONSTRUCTION",
            "V0_P3_RESOURCE_MINING_RULE",
            "V0_P5_EQUIPMENT_TOOLS",
            "R3_M0_MW",
        },
        "creates_canonical_store": False,
    },
    "EDGE_GATEWAY_COMMAND_SESSION_ROUTING": {
        "source_kind": "SEAM_READY_ADAPTER_BOUNDARY",
        "canonical_owner": "NX_AND_AUTHORITY_FOUNDATIONS",
        "classification": "ADAPT",
        "authoritative": False,
    },
    "PRODUCTION_OWNERSHIP_DIRECTORY_AND_DOMAIN_TRANSFER": {
        "source_kind": "POST_P6_SM1_SCOPE",
        "canonical_owner": "AUTHORITY",
        "classification": "READ_ONLY_DONOR",
        "production_active_in_p6": False,
    },
    "SEAMLESS_RESEARCH_AND_MRPF": {
        "source_kind": "RESEARCH_DONOR",
        "canonical_owner": "RESEARCH_ONLY",
        "classification": "READ_ONLY_DONOR",
        "becomes_product_base": False,
    },
}

EXPECTED_DOMAIN_EXTRA_CONTRACTS = {
    "EQUIPMENT_AND_TOOLS": {
        "accepted_gameplay_owner": "V0_P5_EQUIPMENT_TOOLS",
    },
    "OPERATION_ID_DEDUP_IDEMPOTENCY": {
        "implementation_authority": "EXISTING_M0_ATOMIC_COMMIT_AND_REPLAY_SEMANTICS",
    },
    "WARM_SHADOW_COMPATIBILITY": {
        "read_only": True,
    },
}

EXPECTED_GLOBAL_RULES = {
    "p6_is_product_composition_not_foundation_owner": True,
    "p6_runtime_mutation_authorized_by_this_map": False,
    "production_sm1_activated_by_this_map": False,
    "research_lineage_becomes_product_base": False,
    "gateway_can_authorize_mutation": False,
    "warm_shadow_can_authorize_mutation": False,
    "projection_can_authorize_mutation": False,
    "outpost_composition_creates_new_canonical_store": False,
    "actual_authority_transfer_is_post_p6_sm1_scope": True,
}

EXPECTED_FORBIDDEN_SECOND_TRUTHS = frozenset(
    {
        "P6_PRIVATE_ITEM_GRAPH",
        "P6_PRIVATE_INVENTORY_OR_CONTAINER_STORE",
        "P6_PRIVATE_EQUIPMENT_STORE",
        "P6_PRIVATE_CONSTRUCTION_STORE",
        "P6_PRIVATE_OUTPOST_CANONICAL_DATABASE",
        "P6_PRIVATE_PERSISTENCE_FORMAT_OR_OWNER",
        "P6_PRIVATE_OPERATION_DEDUP_LEDGER",
        "P6_PRIVATE_NETWORK_PROTOCOL_AUTHORITY_OR_RECONCILIATION_FOUNDATION",
        "GATEWAY_AS_OWNERSHIP_OR_MUTATION_ORACLE",
        "WARM_SHADOW_AS_MUTATION_AUTHORITY",
        "PROJECTION_AS_CANONICAL_GAMEPLAY_TRUTH",
        "RESEARCH_BRANCH_AS_PRODUCT_BASE",
    }
)


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _value_matches(actual: object, expected: object) -> bool:
    if isinstance(expected, set):
        return isinstance(actual, list) and set(actual) == expected and len(actual) == len(expected)
    return actual == expected


class V0P6CanonicalOwnershipMapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.ownership = _load(CONTROL / "architecture-ownership.v1.json")
        cls.map = _load(HARNESS / "v0-p6-canonical-ownership-map.v1.json")
        cls.roadmap = _load(HARNESS / "v0-p6-seamless-execution-roadmap.v1.json")
        cls.work_order = _load(
            HARNESS
            / "executions/E2026-08-21-V0-P6-R1/work-orders/V0-P6-R1-WO-001.v1.json"
        )
        cls.by_id = {entry["id"]: entry for entry in cls.map["domains"]}

    @classmethod
    def _derive_closed_model_violations(cls, model: dict) -> list[str]:
        violations: list[str] = []
        foundations = cls.ownership["foundations"]
        closed = model.get("closed_model", {})
        domains = model.get("domains", [])
        domain_ids = [entry.get("id") for entry in domains]
        actual_domain_ids = set(domain_ids)

        if closed.get("policy") != "EXACT_ALLOWLIST_REJECT_UNKNOWN_OR_UNMAPPED":
            violations.append("CLOSED_MODEL_POLICY_NOT_FAIL_CLOSED")
        if closed.get("unknown_domain_disposition") != "FAIL":
            violations.append("UNKNOWN_DOMAIN_NOT_FAIL_CLOSED")
        if closed.get("missing_domain_disposition") != "FAIL":
            violations.append("MISSING_DOMAIN_NOT_FAIL_CLOSED")
        if closed.get("duplicate_domain_id_disposition") != "FAIL":
            violations.append("DUPLICATE_DOMAIN_ID_NOT_FAIL_CLOSED")
        if closed.get("missing_registry_key_disposition") != "FAIL_UNLESS_EXPLICIT_NON_REGISTRY_CONTRACT":
            violations.append("MISSING_REGISTRY_KEY_NOT_FAIL_CLOSED")

        declared_allowed = set(closed.get("allowed_domain_ids", []))
        if declared_allowed != EXPECTED_DOMAIN_IDS:
            violations.append("CLOSED_ALLOWLIST_MISMATCH")

        declared_registry_backed = set(closed.get("registry_backed_domain_ids", []))
        if declared_registry_backed != set(EXPECTED_REGISTRY_BINDINGS):
            violations.append("REGISTRY_BACKED_ALLOWLIST_MISMATCH")

        declared_non_registry = closed.get("non_registry_domain_contracts", {})
        if set(declared_non_registry) != set(EXPECTED_NON_REGISTRY_CONTRACTS):
            violations.append("NON_REGISTRY_EXCEPTION_SET_MISMATCH")
        else:
            for domain_id, contract in EXPECTED_NON_REGISTRY_CONTRACTS.items():
                declared_contract = declared_non_registry[domain_id]
                for key, expected in contract.items():
                    if not _value_matches(declared_contract.get(key), expected):
                        violations.append(f"NON_REGISTRY_DECLARED_CONTRACT_MISMATCH:{domain_id}:{key}")

        if len(domain_ids) != len(set(domain_ids)):
            violations.append("DUPLICATE_DOMAIN_ID")

        for domain_id in sorted(EXPECTED_DOMAIN_IDS - actual_domain_ids):
            violations.append(f"MISSING_DOMAIN:{domain_id}")
        for domain_id in sorted(actual_domain_ids - EXPECTED_DOMAIN_IDS):
            violations.append(f"UNKNOWN_DOMAIN:{domain_id}")

        for entry in domains:
            domain_id = entry.get("id")
            if domain_id not in EXPECTED_DOMAIN_IDS:
                continue
            if entry.get("status") != "RESOLVED":
                violations.append(f"UNRESOLVED_DOMAIN:{domain_id}")

            if domain_id in EXPECTED_REGISTRY_BINDINGS:
                expected_key = EXPECTED_REGISTRY_BINDINGS[domain_id]
                actual_key = entry.get("ownership_registry_key")
                if actual_key != expected_key:
                    violations.append(f"REGISTRY_BINDING_MISMATCH:{domain_id}")
                    continue
                if expected_key not in foundations:
                    violations.append(f"UNKNOWN_REGISTRY_KEY:{domain_id}:{expected_key}")
                    continue
                expected_owner = foundations[expected_key]["owner"]
                if entry.get("canonical_owner") != expected_owner:
                    violations.append(f"REGISTRY_OWNER_MISMATCH:{domain_id}")
            else:
                if "ownership_registry_key" in entry:
                    violations.append(f"UNEXPECTED_REGISTRY_KEY_ON_EXCEPTION:{domain_id}")
                contract = EXPECTED_NON_REGISTRY_CONTRACTS.get(domain_id)
                if contract is None:
                    violations.append(f"UNMAPPED_DOMAIN:{domain_id}")
                else:
                    for key, expected in contract.items():
                        if not _value_matches(entry.get(key), expected):
                            violations.append(f"NON_REGISTRY_CONTRACT_MISMATCH:{domain_id}:{key}")

            for key, expected in EXPECTED_DOMAIN_EXTRA_CONTRACTS.get(domain_id, {}).items():
                if not _value_matches(entry.get(key), expected):
                    violations.append(f"DOMAIN_EXTRA_CONTRACT_MISMATCH:{domain_id}:{key}")

            owner = str(entry.get("canonical_owner", "")).upper()
            if owner == "P6" or owner.startswith("P6_") or owner.startswith("OUTPOST_"):
                violations.append(f"FORBIDDEN_P6_PRIVATE_CANONICAL_OWNER:{domain_id}:{owner}")

        global_rules = model.get("global_rules", {})
        for key, expected in EXPECTED_GLOBAL_RULES.items():
            if global_rules.get(key) != expected:
                violations.append(f"GLOBAL_RULE_MISMATCH:{key}")

        if set(model.get("forbidden_second_truths", [])) != EXPECTED_FORBIDDEN_SECOND_TRUTHS:
            violations.append("FORBIDDEN_SECOND_TRUTH_SET_MISMATCH")

        return sorted(set(violations))

    def test_exact_lineage_and_control_subject_are_bound(self) -> None:
        self.assertEqual(self.map["stage"], "P6.1_CANONICAL_OWNERSHIP_MAP")
        self.assertEqual(self.map["revision"], "V0-P6.1-OWNERSHIP-2026-08-21-R2")
        self.assertEqual(self.map["repair_of"]["finding_id"], "P6.1-R-001")
        self.assertEqual(
            self.map["repair_of"]["failed_review_head"],
            "9e4a0cebfe4801e075b7f91774e55173b5143619",
        )
        self.assertEqual(
            self.map["stacked_control_base"],
            "715370c2d81e5129095412fdf68e34eee1f71bdf",
        )
        self.assertEqual(
            self.map["canonical_main_anchor"],
            "1d9de3c479c60045d613660b2a5c5db0374963f8",
        )
        self.assertEqual(
            self.map["accepted_p5_product_lineage"],
            "491ca7d058690d3de5fcea5e41aaee230a31b3ab",
        )
        self.assertEqual(self.map["project_epoch"], "E2026-08-21-V0-P6-R1")
        self.assertEqual(self.map["work_order_id"], "V0-P6-R1-WO-001")
        self.assertEqual(self.work_order["base_sha"], self.map["accepted_p5_product_lineage"])
        self.assertEqual(self.work_order["state"], "PLANNED")

    def test_source_registry_is_exact_and_not_replaced_by_p6(self) -> None:
        source = self.map["source_ownership_registry"]
        self.assertEqual(source["path"], "config/control/architecture-ownership.v1.json")
        self.assertEqual(source["blob_sha"], "3319422747bd19bdef14abe5035fdd3c4af21d20")
        self.assertEqual(source["architecture_revision"], self.ownership["architecture_revision"])
        self.assertEqual(
            self.ownership["explicit_consumer_boundaries"]["V0"],
            "COMPOSITION_PRESENTATION_READBACK_CONSUMER_NOT_TRUTH_OWNER",
        )

    def test_domain_model_is_exact_closed_set_not_subset(self) -> None:
        domain_ids = [entry["id"] for entry in self.map["domains"]]
        self.assertEqual(len(domain_ids), len(set(domain_ids)))
        self.assertEqual(set(domain_ids), EXPECTED_DOMAIN_IDS)
        self.assertEqual(set(self.map["closed_model"]["allowed_domain_ids"]), EXPECTED_DOMAIN_IDS)
        self.assertEqual(
            set(self.map["closed_model"]["registry_backed_domain_ids"]),
            set(EXPECTED_REGISTRY_BINDINGS),
        )
        self.assertEqual(
            set(self.map["closed_model"]["non_registry_domain_contracts"]),
            set(EXPECTED_NON_REGISTRY_CONTRACTS),
        )

    def test_every_domain_has_exact_registry_binding_or_explicit_exception_contract(self) -> None:
        foundations = self.ownership["foundations"]
        for entry in self.map["domains"]:
            domain_id = entry["id"]
            if domain_id in EXPECTED_REGISTRY_BINDINGS:
                expected_key = EXPECTED_REGISTRY_BINDINGS[domain_id]
                self.assertEqual(entry.get("ownership_registry_key"), expected_key, domain_id)
                self.assertIn(expected_key, foundations, domain_id)
                self.assertEqual(entry["canonical_owner"], foundations[expected_key]["owner"], domain_id)
            else:
                self.assertNotIn("ownership_registry_key", entry, domain_id)
                contract = EXPECTED_NON_REGISTRY_CONTRACTS[domain_id]
                for key, expected in contract.items():
                    self.assertTrue(_value_matches(entry.get(key), expected), f"{domain_id}:{key}")

    def test_required_p6_domains_are_all_resolved(self) -> None:
        self.assertEqual(set(self.by_id), EXPECTED_DOMAIN_IDS)
        for domain_id in EXPECTED_DOMAIN_IDS:
            self.assertEqual(self.by_id[domain_id]["status"], "RESOLVED", domain_id)

    def test_item_equipment_construction_and_persistence_have_no_p6_private_owner(self) -> None:
        self.assertEqual(self.by_id["CANONICAL_ITEM_GRAPH_INVENTORY_CONTAINERS"]["canonical_owner"], "ITEM")
        self.assertEqual(self.by_id["EQUIPMENT_AND_TOOLS"]["canonical_owner"], "ITEM")
        self.assertEqual(self.by_id["EQUIPMENT_AND_TOOLS"]["accepted_gameplay_owner"], "V0_P5_EQUIPMENT_TOOLS")
        self.assertEqual(self.by_id["CONSTRUCTION"]["canonical_owner"], "CONSTRUCTION")
        self.assertEqual(self.by_id["PERSISTENCE_REPLAY_RECOVERY"]["canonical_owner"], "R3_M0_MW")

    def test_outpost_is_bounded_composition_not_new_canonical_database(self) -> None:
        outpost = self.by_id["PERSISTENT_SHARED_OUTPOST_COMPOSITION"]
        expected = EXPECTED_NON_REGISTRY_CONTRACTS["PERSISTENT_SHARED_OUTPOST_COMPOSITION"]
        self.assertEqual(outpost["canonical_owner"], expected["canonical_owner"])
        self.assertFalse(outpost["creates_canonical_store"])
        self.assertEqual(set(outpost["canonical_components"]), expected["canonical_components"])

    def test_operation_continuity_reuses_world_transaction_and_m0_semantics(self) -> None:
        operation = self.by_id["OPERATION_ID_DEDUP_IDEMPOTENCY"]
        self.assertEqual(operation["canonical_owner"], "WT")
        self.assertEqual(operation["ownership_registry_key"], "WORLD_TRANSACTION_MODEL")
        self.assertEqual(
            operation["implementation_authority"],
            "EXISTING_M0_ATOMIC_COMMIT_AND_REPLAY_SEMANTICS",
        )

    def test_network_gateway_warm_and_projection_boundaries_fail_closed(self) -> None:
        network = self.by_id["NETWORK_TRANSPORT_REPLICATION_PREDICTION_RECONCILIATION"]
        gateway = self.by_id["EDGE_GATEWAY_COMMAND_SESSION_ROUTING"]
        warm = self.by_id["WARM_SHADOW_COMPATIBILITY"]
        self.assertEqual(network["canonical_owner"], "NX")
        self.assertFalse(gateway["authoritative"])
        self.assertTrue(warm["read_only"])
        self.assertFalse(self.map["global_rules"]["gateway_can_authorize_mutation"])
        self.assertFalse(self.map["global_rules"]["warm_shadow_can_authorize_mutation"])
        self.assertFalse(self.map["global_rules"]["projection_can_authorize_mutation"])

    def test_sm1_and_research_remain_donor_only_not_product_authority(self) -> None:
        directory = self.by_id["PRODUCTION_OWNERSHIP_DIRECTORY_AND_DOMAIN_TRANSFER"]
        research = self.by_id["SEAMLESS_RESEARCH_AND_MRPF"]
        self.assertEqual(directory["classification"], "READ_ONLY_DONOR")
        self.assertFalse(directory["production_active_in_p6"])
        self.assertEqual(research["classification"], "READ_ONLY_DONOR")
        self.assertFalse(research["becomes_product_base"])
        self.assertFalse(self.map["global_rules"]["production_sm1_activated_by_this_map"])
        self.assertFalse(self.map["global_rules"]["research_lineage_becomes_product_base"])
        self.assertTrue(self.map["global_rules"]["actual_authority_transfer_is_post_p6_sm1_scope"])

    def test_forbidden_second_truth_set_is_exact_not_presence_only(self) -> None:
        self.assertEqual(set(self.map["forbidden_second_truths"]), EXPECTED_FORBIDDEN_SECOND_TRUTHS)

    def test_p6_1_exit_is_machine_derived_from_closed_model(self) -> None:
        stage = next(item for item in self.roadmap["p6_stages"] if item["id"] == "P6.1")
        exit_gate = self.map["p6_1_exit_gate"]
        derived_violations = self._derive_closed_model_violations(self.map)

        self.assertEqual(stage["exit"], "ZERO_UNRESOLVED_DUPLICATE_TRUTH")
        self.assertEqual(exit_gate["required_result"], stage["exit"])
        self.assertEqual(exit_gate["derivation_mode"], "MACHINE_DERIVED_FROM_CLOSED_MODEL")
        self.assertFalse(exit_gate["declared_arrays_are_authority"])
        self.assertEqual(derived_violations, [])
        self.assertEqual(exit_gate["unresolved_domains"], [])
        self.assertEqual(exit_gate["unresolved_duplicate_truth"], derived_violations)
        self.assertEqual(exit_gate["control_audit_result"], "PASS_CANDIDATE")
        self.assertFalse(exit_gate["completion_bearing_harness_event_emitted"])
        self.assertFalse(exit_gate["runtime_authority_granted"])
        self.assertFalse(self.map["global_rules"]["p6_runtime_mutation_authorized_by_this_map"])

    def test_adversarial_unknown_outpost_operation_ledger_is_rejected_even_if_author_declares_it_allowed(self) -> None:
        candidate = copy.deepcopy(self.map)
        candidate["domains"].append(
            {
                "id": "OUTPOST_OPERATION_LEDGER",
                "source_kind": "PRODUCT_COMPOSITION",
                "canonical_owner": "P6",
                "classification": "ADAPT",
                "status": "RESOLVED",
            }
        )
        candidate["closed_model"]["allowed_domain_ids"].append("OUTPOST_OPERATION_LEDGER")
        candidate["closed_model"]["non_registry_domain_contracts"]["OUTPOST_OPERATION_LEDGER"] = {
            "source_kind": "PRODUCT_COMPOSITION",
            "canonical_owner": "P6",
            "classification": "ADAPT",
        }
        candidate["p6_1_exit_gate"]["unresolved_duplicate_truth"] = []

        violations = self._derive_closed_model_violations(candidate)
        self.assertIn("CLOSED_ALLOWLIST_MISMATCH", violations)
        self.assertIn("NON_REGISTRY_EXCEPTION_SET_MISMATCH", violations)
        self.assertIn("UNKNOWN_DOMAIN:OUTPOST_OPERATION_LEDGER", violations)

    def test_adversarial_unmapped_foundation_domain_is_rejected(self) -> None:
        candidate = copy.deepcopy(self.map)
        item = next(
            entry
            for entry in candidate["domains"]
            if entry["id"] == "CANONICAL_ITEM_GRAPH_INVENTORY_CONTAINERS"
        )
        del item["ownership_registry_key"]
        candidate["p6_1_exit_gate"]["unresolved_duplicate_truth"] = []

        violations = self._derive_closed_model_violations(candidate)
        self.assertIn("REGISTRY_BINDING_MISMATCH:CANONICAL_ITEM_GRAPH_INVENTORY_CONTAINERS", violations)

    def test_adversarial_outpost_owner_takeover_is_rejected(self) -> None:
        candidate = copy.deepcopy(self.map)
        outpost = next(
            entry
            for entry in candidate["domains"]
            if entry["id"] == "PERSISTENT_SHARED_OUTPOST_COMPOSITION"
        )
        outpost["canonical_owner"] = "P6_OUTPOST"
        outpost["creates_canonical_store"] = True
        candidate["p6_1_exit_gate"]["unresolved_duplicate_truth"] = []

        violations = self._derive_closed_model_violations(candidate)
        self.assertIn(
            "NON_REGISTRY_CONTRACT_MISMATCH:PERSISTENT_SHARED_OUTPOST_COMPOSITION:canonical_owner",
            violations,
        )
        self.assertIn(
            "NON_REGISTRY_CONTRACT_MISMATCH:PERSISTENT_SHARED_OUTPOST_COMPOSITION:creates_canonical_store",
            violations,
        )
        self.assertIn(
            "FORBIDDEN_P6_PRIVATE_CANONICAL_OWNER:PERSISTENT_SHARED_OUTPOST_COMPOSITION:P6_OUTPOST",
            violations,
        )

    def test_adversarial_registry_rebinding_to_other_valid_foundation_is_rejected(self) -> None:
        candidate = copy.deepcopy(self.map)
        item = next(
            entry
            for entry in candidate["domains"]
            if entry["id"] == "CANONICAL_ITEM_GRAPH_INVENTORY_CONTAINERS"
        )
        item["ownership_registry_key"] = "CONSTRUCTION_TRUTH"
        item["canonical_owner"] = "CONSTRUCTION"

        violations = self._derive_closed_model_violations(candidate)
        self.assertIn("REGISTRY_BINDING_MISMATCH:CANONICAL_ITEM_GRAPH_INVENTORY_CONTAINERS", violations)

    def test_frozen_work_order_predicates_cover_ownership_and_duplicate_truth(self) -> None:
        predicates = set(self.work_order["required_predicates"])
        self.assertIn("V0_P6_CANONICAL_OWNERSHIP_MAP_PASS", predicates)
        self.assertIn("V0_P6_ZERO_DUPLICATE_CANONICAL_TRUTH_PASS", predicates)
        self.assertEqual(self.map["p6_1_exit_gate"]["required_result"], "ZERO_UNRESOLVED_DUPLICATE_TRUTH")


if __name__ == "__main__":
    unittest.main()
