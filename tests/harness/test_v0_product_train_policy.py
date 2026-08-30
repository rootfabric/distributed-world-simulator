from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HARNESS = ROOT / "config" / "control" / "harness"
sys.path.insert(0, str(ROOT / "scripts"))

from harness.checkpoint_planner import build_plan

P7 = "V0_P7_BOUNDED_TERRAIN_MUTATION"
P7_BRANCH = "feature/v0-p7-bounded-terrain-mutation"
SM1_BASE = "acb9379cacc413fc25a65117fb1627f5a01b9736"


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


class V0ProductTrainPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.policy = _load(HARNESS / "v0-product-train-policy.v1.json")
        cls.scheduler = _load(HARNESS / "scheduler-policy.v1.json")
        cls.catalog = _load(HARNESS / "checkpoint-catalog.v1.json")
        cls.goals = _load(HARNESS / "project-goals.v1.json")
        cls.acceptance_sm1 = _load(HARNESS / "acceptance/V0-SM1-R1-CHECKPOINT-ACCEPTED-001.v1.json")
        cls.activation_p7 = _load(HARNESS / "activation/V0-P7-R1-ACTIVATION-001.v1.json")
        cls.epoch_p7 = _load(HARNESS / "executions/E2026-08-30-V0-P7-R1/project-epoch.v1.json")
        cls.work_order_p7 = _load(HARNESS / "executions/E2026-08-30-V0-P7-R1/work-orders/V0-P7-R1-WO-001.v1.json")
        cls.p7_plan = _load(HARNESS / "v0-p7-matter-production-convergence-plan.v1.json")

    def test_sm1_is_formally_accepted(self) -> None:
        self.assertEqual("ACCEPTED", self.acceptance_sm1["status"])
        self.assertEqual("b760a6cd8bf1f8b5c00d5f2430edd84853d1fa5f", self.acceptance_sm1["accepted_runtime_head"])
        self.assertEqual("7af1fe08e1f92e3b77a4b12dbccbb96c48e93a68", self.acceptance_sm1["accepted_runtime_tree"])
        self.assertEqual(SM1_BASE, self.acceptance_sm1["accepted_product_lineage_head"])
        sm1 = next(x for x in self.policy["checkpoint_sequence"] if x["id"] == "V0_SM1_SEAMLESS_PRODUCT_INTEGRATION")
        self.assertEqual("ACCEPTED", sm1["state"])

    def test_p7_is_current_but_runtime_is_fail_closed(self) -> None:
        self.assertEqual(P7, self.policy["current_checkpoint"])
        self.assertEqual("P7_OWNER_MAP_PRE_DISPATCH", self.policy["current_phase"])
        routing = self.scheduler["v0_product_train_routing"]
        self.assertEqual(P7, routing["current_checkpoint"])
        self.assertFalse(routing["runtime_mutation_allowed_now"])
        self.assertFalse(routing["next_runtime_checkpoint_eligible"])
        self.assertIn("P7_MATTER_OWNER_MAP_FRESH_REVIEW_PASS", routing["p7_remaining_activation_prerequisites"])

    def test_p7_activation_binds_exact_accepted_sm1_lineage(self) -> None:
        self.assertEqual(P7, self.activation_p7["checkpoint"])
        self.assertEqual(SM1_BASE, self.activation_p7["main_declared_exact_successor_base"])
        self.assertEqual(SM1_BASE, self.epoch_p7["base_sha"])
        self.assertEqual([P7], self.epoch_p7["eligible_checkpoints"])
        self.assertEqual(SM1_BASE, self.work_order_p7["base_sha"])
        self.assertEqual(P7_BRANCH, self.work_order_p7["branch"])
        self.assertEqual("PLANNED", self.work_order_p7["state"])
        self.assertEqual("CRITICAL", self.work_order_p7["risk_class"])
        self.assertFalse(self.activation_p7["mutation_lease"]["runtime_mutation_authorized"])
        self.assertEqual("PENDING", self.activation_p7["director_dispatch"]["status"])

    def test_p7_catalog_and_work_order_predicates_are_exact(self) -> None:
        checkpoint = self.catalog["checkpoints"][P7]
        self.assertEqual("CRITICAL", checkpoint["default_risk_floor"])
        self.assertEqual(checkpoint["required_predicates"], self.work_order_p7["required_predicates"])
        required = set(checkpoint["required_predicates"])
        for predicate in [
            "V0_P7_MATTER_OWNER_MAP_REVIEW_PASS",
            "V0_P7_NO_SECOND_MATTER_TRUTH_PASS",
            "V0_P7_TOOL_TO_MW4_ADAPTER_PASS",
            "V0_P7_MATERIAL_BATCH_ITEM_GRAPH_CONSERVATION_PASS",
            "V0_P7_MW10_MULTI_REGION_ATOMICITY_PASS",
            "V0_P7_GRAPHICAL_DIGGING_PASS",
        ]:
            self.assertIn(predicate, required)

    def test_p7_owner_map_reuses_existing_foundations(self) -> None:
        owner_map = self.p7_plan["owner_map"]
        self.assertEqual("MW4", owner_map["local_matter_mutation"])
        self.assertEqual("MW5", owner_map["matter_persistence"])
        self.assertEqual("MW10", owner_map["true_multi_region_mutation"])
        self.assertEqual("CANONICAL_ITEM_GRAPH", owner_map["inventory_truth"])
        self.assertIn("ACTOR_SEAM_CROSSING_DOES_NOT_IMPLY_MW10", self.p7_plan["multi_region_rule"])

    def test_mutation_lease_is_reserved_to_p7_and_still_serialized(self) -> None:
        lease = self.scheduler["pre_h0_3_runtime_mutation_lease"]
        self.assertEqual(1, lease["capacity"])
        self.assertEqual(P7, lease["holder_checkpoint"])
        self.assertEqual(P7_BRANCH, lease["holder_branch"])
        self.assertEqual("RESERVED_FOR_V0_P7_PRE_DISPATCH_NO_ACTIVE_RUNTIME_MUTATION", lease["state"])
        self.assertEqual(1, self.scheduler["concurrency"]["pre_h0_3_total_autonomous_runtime_mutation_workers"])

    def test_planner_exposes_p7_but_blocks_dispatch_until_control_gates_close(self) -> None:
        contracts = {"checkpoint_catalog": self.catalog, "scheduler_policy": self.scheduler}
        planned = {"completed_predicates": [], "work_order_id": "V0-P7-R1-WO-001", "state": "PLANNED"}
        plan = build_plan(contracts, self.work_order_p7, planned)
        self.assertEqual("PLANNING_ONLY", plan["mode"])
        self.assertIn("v0_p7_gate", plan)
        self.assertEqual("MW4_MW10_EXISTING_CANONICAL_FOUNDATION", plan["v0_p7_gate"]["matter_truth"])
        dispatched = dict(planned, state="DISPATCHED")
        with self.assertRaisesRegex(ValueError, "V0_P7_RUNTIME_DISPATCH_BLOCKED"):
            build_plan(contracts, self.work_order_p7, dispatched)


    def test_p7_0_exact_source_owner_map_is_bound_to_existing_owners(self) -> None:
        owner_map = _load(HARNESS / "v0-p7-matter-production-owner-map.v1.json")
        self.assertEqual("REVIEW_CANDIDATE", owner_map["status"])
        self.assertFalse(owner_map["runtime_mutation"])
        self.assertEqual("PASS", owner_map["no_second_owner_audit"]["result"])
        self.assertEqual(0, owner_map["no_second_owner_audit"]["duplicate_owner_count"])
        decisions = owner_map["core_decisions"]
        self.assertEqual("USE_EXISTING_MATTER_MUTATION_REQUEST_RESULT", decisions["mutation_contract"])
        self.assertEqual("USE_EXISTING_MW6_MATTER_MUTATION_HANDLER", decisions["gateway_ingress"])
        self.assertEqual("MW10_ONLY_WHEN_ONE_CANONICAL_MUTATION_SPANS_TWO_OR_MORE_MATTER_REGIONS", decisions["cross_region"])
        self.assertFalse(decisions["new_canonical_state_owner"])

        root = ROOT
        source_assertions = {
            "scripts/simulation/matter/mutation/matter_excavation_service.gd": [
                "func create_excavation_request(",
                "func execute(request: Dictionary)",
                "MATTER_MUTATION_TARGET_SET_MISMATCH",
                "BatchScript.create({",
            ],
            "scripts/simulation/matter/network/matter_authoritative_server.gd": [
                'const COMMAND_TYPE: String = "MATTER_MUTATION"',
                "func set_command_authority_gate(gate)",
                "func register_gateway(gateway)",
                "func handle_gateway_command(payload: Dictionary, envelope: Dictionary)",
                "MATTER_COMMAND_OPERATION_MISMATCH",
                "MATTER_COMMAND_ACTOR_NOT_OWNED",
            ],
            "scripts/runtime/networked_gameplay/sm1/sm1_authority_transfer_coordinator.gd": [
                "func authorize_write(authority_id: String, authority_epoch: int)",
                "SM1_AUTHORITY_TRANSFER_WRITE_FENCED",
            ],
            "scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service_p5.gd": [
                "func get_equipped_item(",
                'EQUIPMENT_SLOT_TOOL_MAIN := "tool/main"',
                'MINING_TOOL_DEFINITION_ID := "item/tool/mining"',
            ],
            "scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service_p3.gd": [
                "func preflight_server_output(",
                "func apply_server_output(",
            ],
            "scripts/runtime/networked_gameplay/networked_gameplay_service_p2.gd": [
                "func get_player(logical_player_id: String) -> Dictionary:",
            ],
            "scripts/simulation/matter/handoff/matter_regional_authority_gate.gd": [
                "func authorize_mutation(request: Dictionary)",
                "MATTER_CROSS_REGION_MUTATION_REQUIRES_COORDINATION",
            ],
            "scripts/simulation/matter/transactions/distributed/matter_cross_region_transaction_plan.gd": [
                "value[\"participants\"].size() < 2",
                "MATTER_CROSS_REGION_TRANSACTION_REQUIRES_MULTIPLE_REGIONS",
            ],
        }
        for relative, needles in source_assertions.items():
            content = (root / relative).read_text(encoding="utf-8")
            for needle in needles:
                self.assertIn(needle, content, f"{relative} lost P7.0 binding: {needle}")

    def test_p7_0_rejects_duplicate_terrain_and_resource_owners(self) -> None:
        owner_map = _load(HARNESS / "v0-p7-matter-production-owner-map.v1.json")
        forbidden = set(owner_map["no_second_owner_audit"]["forbidden_duplicates"])
        self.assertIn("TerrainMutationRequest", forbidden)
        self.assertIn("TerrainMutationResult", forbidden)
        self.assertIn("P7Persistence", forbidden)
        self.assertIn("P7AuthorityDirectory", forbidden)
        self.assertIn("P7ResourceInventory", forbidden)
        self.assertIn("P7InterestManager", forbidden)
        delivery = owner_map["p7_3_material_delivery_boundary"]
        self.assertFalse(delivery["new_delivery_receipt_store_allowed"])
        self.assertEqual("Canonical Item Graph replay ledger using deterministic derived operation_id", delivery["exactly_once_owner"])

    def test_product_sequence_remains_unique(self) -> None:
        ids = [item["id"] for item in self.policy["checkpoint_sequence"]]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(ids[-2:], [P7, "V0_P8_FIRST_MOBILE_CONSTRUCT"])
        train = next(item for item in self.goals["current_goal_graph"] if item["id"] == "V0_PRODUCT_TRAIN")
        self.assertIn(P7, train["sequence"])


if __name__ == "__main__":
    unittest.main()
