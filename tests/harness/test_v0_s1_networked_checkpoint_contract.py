from __future__ import annotations

import json
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.checkpoint_planner import build_plan

P4 = "V0_P4_REAL_RESOURCE_CONSTRUCTION"
P5 = "V0_P5_EQUIPMENT_TOOLS"
S1 = "V0_S1_NETWORKED_PLANETARY_OUTPOST"
H0_2 = "H0_2_NX_C1_HIGH_RISK_PILOT"
P4_BRANCH = "feature/v0-p4-construction-real-resources"
P5_BRANCH = "feature/v0-p5-equipment-tools"
P6 = "V0_P6_PERSISTENT_SHARED_OUTPOST"
P6_BRANCH = "feature/v0-p6-persistent-shared-outpost"
POST_P6_GATE = "V0_POST_P6_SEAMLESS_INSERTION_GATE"
SM1 = "V0_SM1_SEAMLESS_PRODUCT_INTEGRATION"
SM1_BRANCH = "feature/v0-sm1-seamless-product-integration"
P7 = "V0_P7_BOUNDED_TERRAIN_MUTATION"
P7_BRANCH = "feature/v0-p7-bounded-terrain-mutation"
CURRENT_V0_BRANCH = "control/v0-p7-activation-r1"
CURRENT_V0_PASSPORT = "config/control/branches/control__v0-p7-activation-r1.v1.json"
P4_PASSPORT = "config/control/branches/feature__v0-p4-construction-real-resources.v1.json"
SM1_ACCEPTED_BASE = "acb9379cacc413fc25a65117fb1627f5a01b9736"
P7_CONTROL_BASE = "f7d3deb80b67a41880d736f83b132a9a7a5a0964"


def load_json(path: str) -> dict:
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


class V0ProductCheckpointContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.catalog = load_json("config/control/harness/checkpoint-catalog.v1.json")
        self.scheduler = load_json("config/control/harness/scheduler-policy.v1.json")
        self.goals = load_json("config/control/harness/project-goals.v1.json")
        self.registry = load_json("config/control/project-program-registry.v1.json")
        self.contracts = {
            "checkpoint_catalog": self.catalog,
            "scheduler_policy": self.scheduler,
        }

    def test_p4_historical_high_risk_product_checkpoint_contract_is_preserved(self):
        checkpoint = self.catalog["checkpoints"][P4]
        self.assertEqual("PROJECT", checkpoint["kind"])
        self.assertEqual("V0", checkpoint["program"])
        self.assertEqual("HIGH", checkpoint["default_risk_floor"])
        self.assertEqual("V0_P4_PASS", checkpoint["success_state"])
        self.assertEqual("SERVER_PREDICTED", checkpoint["network_baseline"])
        self.assertEqual("V0_BLOCKED_REQUIRES_NX", checkpoint["blocked_state_if_network_foundation_change_required"])
        self.assertEqual("RUNTIME_FEATURE_MERGE", checkpoint["human_gate_after"])

    def test_p4_uses_main_declared_product_execution_base_not_bare_main(self):
        checkpoint = self.catalog["checkpoints"][P4]
        preconditions = set(checkpoint["preconditions"])
        self.assertIn("MAIN_DECLARED_V0_PRODUCT_EXECUTION_BASE_PRESENT", preconditions)
        self.assertIn("V0_P4_EXECUTION_BASE_DESCENDS_FROM_PLAYABLE_FRONTIER", preconditions)
        self.assertNotIn("V0_P4_EXACT_CURRENT_MAIN_BASE", checkpoint["required_predicates"])
        self.assertIn("V0_P4_MAIN_DECLARED_PRODUCT_EXECUTION_BASE", checkpoint["required_predicates"])

        rules = self.scheduler["parallel_product_checkpoints"]["rules"]
        self.assertTrue(rules["requires_main_declared_product_execution_base"])
        self.assertTrue(rules["control_epoch_remains_anchored_to_current_main"])
        self.assertTrue(rules["runtime_branch_may_continue_from_main_declared_stacked_product_lineage"])
        self.assertTrue(rules["product_execution_base_is_not_automatic_checkpoint_acceptance"])

    def test_prior_acceptance_debt_contract_is_preserved_for_historical_p4(self):
        checkpoint = self.catalog["checkpoints"][P4]
        non_preconditions = set(checkpoint["non_preconditions_for_bounded_implementation"])
        self.assertIn("P2_DIRECTOR_CHECKPOINT_VERDICT_COMPLETE", non_preconditions)
        self.assertIn("P3_AGGREGATE_ACCEPTANCE_COMPLETE", non_preconditions)
        self.assertIn("P3_REPLICA_REPAIR_ACCEPTED", non_preconditions)
        self.assertIn("V0_PRIOR_ACCEPTANCE_DEBT_RESOLVED", checkpoint["required_predicates"])

        rules = self.scheduler["parallel_product_checkpoints"]["rules"]
        self.assertTrue(rules["bounded_implementation_may_proceed_with_prior_acceptance_debt"])
        self.assertTrue(rules["checkpoint_acceptance_requires_prior_acceptance_debt_resolved"])

    def test_p4_required_predicates_cover_real_resource_atomicity_and_replication(self):
        required = set(self.catalog["checkpoints"][P4]["required_predicates"])
        expected = {
            "V0_P4_EXACT_CONSUME_RED_REPRODUCED",
            "V0_P4_EXACT_CONSUME_GREEN",
            "V0_P4_DETERMINISTIC_SERVER_ALLOCATOR_PASS",
            "V0_P4_LIVE_M4_SINGLE_OWNER_TRANSACTION_PORT_PASS",
            "V0_P4_ATOMIC_ITEM_GRAPH_AND_CONSTRUCTION_COMMIT_PASS",
            "V0_P4_INSUFFICIENT_RESOURCES_MUTATION_FREE_PASS",
            "V0_P4_DUPLICATE_EXACT_ONCE_PASS",
            "V0_P4_OPERATION_ID_CONFLICT_PASS",
            "V0_P4_FAULT_INJECTION_ROLLBACK_PASS",
            "V0_P4_FOREIGN_PLAYER_OWNERSHIP_ISOLATION_PASS",
            "V0_P4_ITEM_GRAPH_DELTA_AND_CONSTRUCTION_EVENT_PUBLICATION_PASS",
            "V0_P4_TWO_CLIENT_REPLICATION_PASS",
            "V0_P4_RECONNECT_CONVERGENCE_PASS",
            "V0_P4_NO_SECOND_ITEM_GRAPH_OR_PERSISTENCE_OWNER_PASS",
            "V0_P4_FAIL_CLOSED_TO_NX_IF_NETWORK_FOUNDATION_CHANGE_REQUIRED",
            "V0_PRIOR_ACCEPTANCE_DEBT_RESOLVED",
            "INDEPENDENT_REVIEWER_PASS",
            "INDEPENDENT_VERIFIER_PASS",
            "V0_P4_CHECKPOINT_PROPOSED",
        }
        self.assertTrue(expected.issubset(required), sorted(expected - required))

    def test_goal_graph_preserves_p0_p8_order_and_routes_current_product_lane_to_p7(self):
        goals = {entry["id"]: entry for entry in self.goals["current_goal_graph"]}
        self.assertEqual(P4, goals["V0_P4_PRODUCT"]["target_checkpoint"])
        sequence = goals["V0_PRODUCT_TRAIN"]["sequence"]
        self.assertEqual(
            [
                "V0_P0_PLAYABLE_FRONTIER",
                "V0_P1_WORLD_ITEMS_CONTAINERS",
                "V0_P2_RECONNECTABLE_SHARED_STATE",
                "V0_P3_RESOURCE_MINING",
                "V0_P4_REAL_RESOURCE_CONSTRUCTION",
                "V0_P5_EQUIPMENT_TOOLS",
                "V0_P6_PERSISTENT_SHARED_OUTPOST",
                "V0_POST_P6_SEAMLESS_INSERTION_GATE",
                "V0_SM1_SEAMLESS_PRODUCT_INTEGRATION_OR_EXPLICIT_DEFER",
                "V0_P7_BOUNDED_TERRAIN_MUTATION",
                "V0_P8_FIRST_MOBILE_CONSTRUCT",
            ],
            sequence,
        )
        core_p_sequence = [item for item in sequence if item.startswith("V0_P") and "POST_P6" not in item]
        self.assertEqual(
            [
                "V0_P0_PLAYABLE_FRONTIER",
                "V0_P1_WORLD_ITEMS_CONTAINERS",
                "V0_P2_RECONNECTABLE_SHARED_STATE",
                "V0_P3_RESOURCE_MINING",
                "V0_P4_REAL_RESOURCE_CONSTRUCTION",
                "V0_P5_EQUIPMENT_TOOLS",
                "V0_P6_PERSISTENT_SHARED_OUTPOST",
                "V0_P7_BOUNDED_TERRAIN_MUTATION",
                "V0_P8_FIRST_MOBILE_CONSTRUCT",
            ],
            core_p_sequence,
        )
        self.assertNotIn("V0_S2_NETWORKED_LANDED_SHIP_0", sequence)
        self.assertEqual([P7], self.scheduler["parallel_product_checkpoints"]["checkpoints"])
        self.assertEqual(H0_2, self.scheduler["current_pilot_override"]["current_checkpoint"])
        self.assertEqual(P7, self.scheduler["v0_product_train_routing"]["next_runtime_checkpoint"])
        self.assertFalse(self.scheduler["v0_product_train_routing"]["next_runtime_checkpoint_eligible"])
        self.assertFalse(self.scheduler["v0_product_train_routing"]["runtime_mutation_allowed_now"])

    def test_registry_generation_80_points_to_current_p7_control_frontier(self):
        self.assertEqual(80, self.registry["registry_generation"])
        v0 = self.registry["programs"]["V0"]
        self.assertEqual("COMPOSITION_FRONTIER", v0["role"])
        self.assertEqual(CURRENT_V0_BRANCH, v0["branch"])
        self.assertTrue(v0["requires_passport"])
        self.assertEqual(CURRENT_V0_PASSPORT, v0["passport_path"])
        execution = v0["product_execution_base"]
        self.assertEqual("accepted SM1 product lineage", execution["branch"])
        self.assertEqual(SM1_ACCEPTED_BASE, execution["sha"])
        self.assertTrue(execution["declares_checkpoint_acceptance"])
        self.assertEqual(
            "config/control/harness/acceptance/V0-SM1-R1-CHECKPOINT-ACCEPTED-001.v1.json",
            execution["acceptance_record"],
        )
        prebuild = v0["prebuild_state"]
        self.assertEqual(P7_BRANCH, prebuild["branch"])
        self.assertEqual("NOT_CREATED", prebuild["head_at_refresh_input"])
        self.assertFalse(prebuild["runtime_mutation_present"])

    def test_current_registry_and_current_passport_are_consistent(self):
        v0 = self.registry["programs"]["V0"]
        passport = load_json(CURRENT_V0_PASSPORT)
        self.assertEqual(CURRENT_V0_BRANCH, passport["branch"])
        self.assertEqual("V0", passport["program"])
        self.assertEqual(v0["role"], passport["role"])
        self.assertEqual(v0["current_stage"], passport["current_stage"])
        self.assertEqual(v0["stage_status"], passport["stage_status"])
        self.assertEqual(v0["blockers"], passport["blockers"])
        self.assertEqual(v0["health_declared"], passport["health_declared"])
        self.assertEqual(P7_CONTROL_BASE, passport["base_commit"])
        self.assertEqual([], passport["ownership_claims"])
        self.assertEqual([], passport["runtime_paths"])

    def test_historical_p4_passport_remains_auditable_without_being_current_registry_truth(self):
        remote_ref = f"origin/{P4_BRANCH}"
        git("rev-parse", "--verify", remote_ref)
        passport = json.loads(git("show", f"{remote_ref}:{P4_PASSPORT}"))
        self.assertEqual("distributed_world_simulator.branch_passport.v1", passport["schema"])
        self.assertEqual(P4_BRANCH, passport["branch"])
        self.assertEqual("V0", passport["program"])
        self.assertEqual("COMPOSITION_FRONTIER", passport["role"])
        self.assertEqual("ef3ad5f0afc433802d639171d938e4720b3a46ec", passport["base_commit"])
        self.assertEqual([], passport["ownership_claims"])
        self.assertEqual([], passport["runtime_paths"])
        self.assertTrue(passport["pre_dispatch_audit_gate"]["requires_refs_fetch_performed"])
        self.assertTrue(passport["pre_dispatch_audit_gate"]["requires_authoritative_for_dispatch"])
        self.assertTrue(passport["pre_dispatch_audit_gate"]["requires_committed_audit_evidence"])
        self.assertNotEqual(P4_BRANCH, self.registry["programs"]["V0"]["branch"])

    def test_pre_h0_3_concurrency_is_one_main_owned_p7_reserved_lease(self):
        concurrency = self.scheduler["concurrency"]
        rules = self.scheduler["parallel_product_checkpoints"]["rules"]
        lease = self.scheduler["pre_h0_3_runtime_mutation_lease"]
        self.assertEqual(1, concurrency["pre_h0_3_total_autonomous_runtime_mutation_workers"])
        self.assertEqual(1, concurrency["v0_product_max_autonomous_runtime_mutation_workers"])
        self.assertTrue(concurrency["verification_review_only_may_wait_in_parallel_with_one_runtime_mutation_worker"])
        self.assertEqual(1, rules["pre_h0_3_total_runtime_mutation_workers_max"])
        self.assertTrue(rules["v0_mutation_plus_nx_or_sm0_nontrivial_fix_mutation_forbidden"])
        self.assertEqual(1, lease["capacity"])
        self.assertEqual(P7, lease["holder_checkpoint"])
        self.assertEqual(P7_BRANCH, lease["holder_branch"])
        self.assertEqual("RESERVED_FOR_V0_P7_PRE_DISPATCH_NO_ACTIVE_RUNTIME_MUTATION", lease["state"])
        self.assertTrue(lease["non_holder_dispatch_forbidden"])

    def test_p4_planner_is_historical_and_cannot_reacquire_live_mutation_slot(self):
        work_order = {"goal_checkpoint": P4, "branch": P4_BRANCH}
        planned = {
            "completed_predicates": [],
            "work_order_id": "V0-P4-WO-TEST",
            "state": "PLANNED",
        }
        plan = build_plan(self.contracts, work_order, planned)
        self.assertEqual("PLANNING_ONLY", plan["mode"])
        self.assertEqual(0, plan["autonomous_runtime_workers"])
        self.assertEqual("MAIN_DECLARED_V0_PRODUCT_LINEAGE", plan["v0_p4_gate"]["runtime_execution_base"])
        self.assertEqual("FORBIDDEN_UNTIL_DISPATCH", plan["v0_p4_gate"]["runtime_mutation"])

        dispatched = {
            "completed_predicates": ["PROJECT_EPOCH_CREATED"],
            "work_order_id": "V0-P4-WO-TEST",
            "state": "DISPATCHED",
        }
        with self.assertRaisesRegex(ValueError, f"GLOBAL_MUTATION_SLOT_RESERVED_FOR:{P7}"):
            build_plan(self.contracts, work_order, dispatched)

        implemented = dict(dispatched, state="IMPLEMENTED")
        plan = build_plan(self.contracts, work_order, implemented)
        self.assertEqual("PRODUCT_RUNTIME_VERIFICATION", plan["mode"])
        self.assertEqual(0, plan["autonomous_runtime_workers"])
        self.assertEqual("NO_ACTIVE_MUTATION_SLOT", plan["v0_p4_gate"]["runtime_mutation"])

    def test_nx_c1_acceptance_contract_remains_strict(self):
        required = set(self.catalog["checkpoints"][H0_2]["required_predicates"])
        expected = {
            "OWNER_AUTHORITY_FOCUSED_PASS",
            "PHYSICS_PRESENTATION_SINGLE_WRITER_PASS",
            "ITEM_ROLLBACK_PICKUP_DROP_PASS",
            "TWO_CLIENT_PASS",
            "IMPAIRED_NETWORK_PASS",
            "RECONNECT_OWNERSHIP_EPOCH_PASS",
            "CH_TO_NX_DIRECTIONAL_REVALIDATION_PASS",
            "INDEPENDENT_REVIEWER_PASS",
            "TESTED_HEADS_EXACT_AND_FRESH",
            "NX_CHECKPOINT_PROPOSED",
        }
        self.assertTrue(expected.issubset(required), sorted(expected - required))
        self.assertIn(S1, self.catalog["checkpoints"])


if __name__ == "__main__":
    unittest.main()
