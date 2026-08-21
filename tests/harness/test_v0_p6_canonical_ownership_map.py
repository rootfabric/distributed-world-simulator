from __future__ import annotations

import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HARNESS = ROOT / "config" / "control" / "harness"
CONTROL = ROOT / "config" / "control"


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


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

    def test_exact_lineage_and_control_subject_are_bound(self) -> None:
        self.assertEqual(self.map["stage"], "P6.1_CANONICAL_OWNERSHIP_MAP")
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
        self.assertTrue(self.map["global_rules"]["p6_is_product_composition_not_foundation_owner"])
        self.assertEqual(
            self.ownership["explicit_consumer_boundaries"]["V0"],
            "COMPOSITION_PRESENTATION_READBACK_CONSUMER_NOT_TRUTH_OWNER",
        )

    def test_every_foundation_mapping_matches_canonical_registry_owner(self) -> None:
        foundations = self.ownership["foundations"]
        checked = 0
        for entry in self.map["domains"]:
            key = entry.get("ownership_registry_key")
            if not key:
                continue
            self.assertIn(key, foundations, entry["id"])
            self.assertEqual(entry["canonical_owner"], foundations[key]["owner"], entry["id"])
            checked += 1
        self.assertGreaterEqual(checked, 9)

    def test_required_p6_domains_are_explicitly_resolved(self) -> None:
        required = {
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
        self.assertTrue(required.issubset(self.by_id))
        for domain_id in required:
            self.assertEqual(self.by_id[domain_id]["status"], "RESOLVED", domain_id)

    def test_item_equipment_construction_and_persistence_have_no_p6_private_owner(self) -> None:
        self.assertEqual(self.by_id["CANONICAL_ITEM_GRAPH_INVENTORY_CONTAINERS"]["canonical_owner"], "ITEM")
        self.assertEqual(self.by_id["EQUIPMENT_AND_TOOLS"]["canonical_owner"], "ITEM")
        self.assertEqual(self.by_id["EQUIPMENT_AND_TOOLS"]["accepted_gameplay_owner"], "V0_P5_EQUIPMENT_TOOLS")
        self.assertEqual(self.by_id["CONSTRUCTION"]["canonical_owner"], "CONSTRUCTION")
        self.assertEqual(self.by_id["PERSISTENCE_REPLAY_RECOVERY"]["canonical_owner"], "R3_M0_MW")

        forbidden = set(self.map["forbidden_second_truths"])
        self.assertIn("P6_PRIVATE_ITEM_GRAPH", forbidden)
        self.assertIn("P6_PRIVATE_EQUIPMENT_STORE", forbidden)
        self.assertIn("P6_PRIVATE_CONSTRUCTION_STORE", forbidden)
        self.assertIn("P6_PRIVATE_PERSISTENCE_FORMAT_OR_OWNER", forbidden)

    def test_outpost_is_composition_not_a_new_canonical_database(self) -> None:
        outpost = self.by_id["PERSISTENT_SHARED_OUTPOST_COMPOSITION"]
        self.assertEqual(outpost["canonical_owner"], "COMPOSITE_EXISTING_OWNERS")
        self.assertFalse(outpost["creates_canonical_store"])
        self.assertEqual(
            set(outpost["canonical_components"]),
            {
                "ITEM",
                "CONSTRUCTION",
                "V0_P3_RESOURCE_MINING_RULE",
                "V0_P5_EQUIPMENT_TOOLS",
                "R3_M0_MW",
            },
        )
        self.assertIn("P6_PRIVATE_OUTPOST_CANONICAL_DATABASE", self.map["forbidden_second_truths"])

    def test_operation_continuity_reuses_world_transaction_and_m0_semantics(self) -> None:
        operation = self.by_id["OPERATION_ID_DEDUP_IDEMPOTENCY"]
        self.assertEqual(operation["canonical_owner"], "WT")
        self.assertEqual(operation["implementation_authority"], "EXISTING_M0_ATOMIC_COMMIT_AND_REPLAY_SEMANTICS")
        self.assertIn("P6_PRIVATE_OPERATION_DEDUP_LEDGER", self.map["forbidden_second_truths"])

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
        self.assertIn(
            "P6_PRIVATE_NETWORK_PROTOCOL_AUTHORITY_OR_RECONCILIATION_FOUNDATION",
            self.map["forbidden_second_truths"],
        )

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

    def test_p6_1_exit_is_zero_unresolved_truth_without_runtime_authorization(self) -> None:
        stage = next(item for item in self.roadmap["p6_stages"] if item["id"] == "P6.1")
        exit_gate = self.map["p6_1_exit_gate"]
        self.assertEqual(stage["exit"], "ZERO_UNRESOLVED_DUPLICATE_TRUTH")
        self.assertEqual(exit_gate["required_result"], stage["exit"])
        self.assertEqual(exit_gate["unresolved_domains"], [])
        self.assertEqual(exit_gate["unresolved_duplicate_truth"], [])
        self.assertEqual(exit_gate["control_audit_result"], "PASS_CANDIDATE")
        self.assertFalse(exit_gate["completion_bearing_harness_event_emitted"])
        self.assertFalse(exit_gate["runtime_authority_granted"])
        self.assertFalse(self.map["global_rules"]["p6_runtime_mutation_authorized_by_this_map"])

    def test_work_order_requires_both_ownership_predicates(self) -> None:
        predicates = set(self.work_order["required_predicates"])
        self.assertIn("V0_P6_CANONICAL_OWNERSHIP_MAP_COMPLETE", predicates)
        self.assertIn("V0_P6_ZERO_UNRESOLVED_DUPLICATE_TRUTH", predicates)


if __name__ == "__main__":
    unittest.main()
