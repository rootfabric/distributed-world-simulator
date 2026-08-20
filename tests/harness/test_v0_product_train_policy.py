from __future__ import annotations

import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HARNESS = ROOT / "config" / "control" / "harness"
sys.path.insert(0, str(ROOT / "scripts"))

from harness.checkpoint_planner import build_plan


def _load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _latest_work_state(event_dir: Path) -> str:
    event_paths = sorted(event_dir.glob("*.json"))
    if not event_paths:
        return "PLANNED"
    latest = _load(event_paths[-1])
    state = str(latest.get("work_state", ""))
    if not state:
        raise AssertionError(f"latest event has no work_state: {event_paths[-1]}")
    return state


class V0ProductTrainPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.policy = _load(HARNESS / "v0-product-train-policy.v1.json")
        cls.seamless = _load(HARNESS / "v0-post-p6-seamless-convergence.v1.json")
        cls.harness = _load(HARNESS / "harness-policy.v1.json")
        cls.scheduler = _load(HARNESS / "scheduler-policy.v1.json")
        cls.goals = _load(HARNESS / "project-goals.v1.json")
        cls.catalog = _load(HARNESS / "checkpoint-catalog.v1.json")
        cls.acceptance = _load(HARNESS / "acceptance/V0-P4-R1-CHECKPOINT-ACCEPTED-001.v1.json")
        cls.activation = _load(HARNESS / "activation/V0-P5-R1-ACTIVATION-001.v1.json")
        cls.epoch = _load(HARNESS / "executions/E2026-08-18-V0-P5-R1/project-epoch.v1.json")
        cls.work_order = _load(HARNESS / "executions/E2026-08-18-V0-P5-R1/work-orders/V0-P5-R1-WO-001.v1.json")
        cls.contracts = {
            "checkpoint_catalog": cls.catalog,
            "scheduler_policy": cls.scheduler,
        }

    def test_harness_binds_product_train_policy(self) -> None:
        self.assertEqual(self.harness["v0_product_train_policy"], "config/control/harness/v0-product-train-policy.v1.json")
        principles = self.harness["principles"]
        self.assertTrue(principles["product_train_advances_one_accepted_checkpoint_at_a_time"])
        self.assertTrue(principles["successor_product_base_is_exact_accepted_predecessor_lineage"])
        self.assertTrue(principles["runtime_implementation_and_closure_control_are_separate"])
        self.assertTrue(principles["research_frontiers_are_non_blocking_by_default"])

    def test_p4_is_formally_accepted_and_exact(self) -> None:
        expected = "2a6721cdf02fa1134c59d1ab98bb7b597c66821d"
        self.assertEqual(self.acceptance["decision"], "V0_P4_CHECKPOINT_ACCEPTED")
        self.assertEqual(self.acceptance["status"], "ACCEPTED")
        self.assertEqual(self.acceptance["accepted_product_lineage_head"], expected)
        p4 = self.policy["checkpoint_sequence"][0]
        self.assertEqual(p4["state"], "ACCEPTED")
        self.assertEqual(p4["accepted_runtime_head"], expected)

    def test_p5_is_current_pre_dispatch_checkpoint(self) -> None:
        self.assertEqual(self.policy["current_checkpoint"], "V0_P5_EQUIPMENT_TOOLS")
        self.assertEqual(self.policy["current_phase"], "P5_PRE_DISPATCH_CONTROL_READY")
        p5 = self.policy["checkpoint_sequence"][1]
        self.assertEqual(p5["state"], "CURRENT_PRE_DISPATCH")
        self.assertEqual(p5["activation_complete_except"], ["DIRECTOR_DISPATCH"])
        routing = self.scheduler["v0_product_train_routing"]
        self.assertEqual(routing["current_checkpoint"], "V0_P5_EQUIPMENT_TOOLS")
        self.assertEqual(routing["current_phase"], "PRE_DISPATCH_CONTROL_READY")
        self.assertFalse(routing["runtime_mutation_allowed_now"])
        self.assertEqual(routing["p5_remaining_activation_prerequisites"], ["DIRECTOR_DISPATCH"])

    def test_p5_base_epoch_and_work_order_are_exact(self) -> None:
        expected = "2a6721cdf02fa1134c59d1ab98bb7b597c66821d"
        self.assertEqual(self.activation["main_declared_exact_successor_base"], expected)
        self.assertEqual(self.epoch["base_sha"], expected)
        self.assertEqual(self.epoch["eligible_checkpoints"], ["V0_P5_EQUIPMENT_TOOLS"])
        self.assertEqual(self.epoch["status"], "ACTIVE")
        self.assertEqual(self.work_order["goal_checkpoint"], "V0_P5_EQUIPMENT_TOOLS")
        self.assertEqual(self.work_order["base_sha"], expected)
        self.assertEqual(self.work_order["branch"], "feature/v0-p5-equipment-tools")
        event_dir = HARNESS / "executions/E2026-08-18-V0-P5-R1/events/V0-P5-R1-WO-001"
        self.assertEqual(self.work_order["state"], _latest_work_state(event_dir))
        self.assertEqual(self.work_order["risk_class"], "HIGH")
        self.assertEqual(
            self.catalog["checkpoints"]["V0_P5_EQUIPMENT_TOOLS"]["required_predicates"],
            self.work_order["required_predicates"],
        )

    def test_single_mutation_lease_is_rotated_but_inactive_before_dispatch(self) -> None:
        lease = self.scheduler["pre_h0_3_runtime_mutation_lease"]
        self.assertEqual(lease["capacity"], 1)
        self.assertEqual(lease["holder_program"], "V0")
        self.assertEqual(lease["holder_checkpoint"], "V0_P5_EQUIPMENT_TOOLS")
        self.assertEqual(lease["holder_branch"], "feature/v0-p5-equipment-tools")
        self.assertEqual(lease["state"], "RESERVED_FOR_V0_P5_PRE_DISPATCH_NO_ACTIVE_RUNTIME_MUTATION")
        self.assertTrue(lease["successor_rotation_requires_predecessor_checkpoint_acceptance"])
        self.assertEqual(self.activation["mutation_lease"]["rotation_status"], "ROTATED_RESERVED_PRE_DISPATCH")
        self.assertEqual(self.policy["current_p5_activation_route"]["mutation_lease"], "ROTATED_RESERVED_PRE_DISPATCH")
        self.assertEqual(self.policy["current_p5_activation_route"]["runtime_mutation"], "FORBIDDEN_UNTIL_DIRECTOR_DISPATCH")

    def test_p5_planner_waits_for_director_then_grants_exactly_one_worker(self) -> None:
        work_order = {
            "goal_checkpoint": "V0_P5_EQUIPMENT_TOOLS",
            "branch": "feature/v0-p5-equipment-tools",
        }
        planned = {
            "completed_predicates": ["PROJECT_EPOCH_CREATED"],
            "work_order_id": "V0-P5-R1-WO-001",
            "state": "PLANNED",
        }
        plan = build_plan(self.contracts, work_order, planned)
        self.assertEqual(plan["mode"], "PLANNING_ONLY")
        self.assertEqual(plan["autonomous_runtime_workers"], 0)
        self.assertEqual(plan["next_action"], "DIRECTOR_DISPATCH_ACCEPTED_P4_BASE_V0_P5_WORK_ORDER")
        self.assertEqual(plan["v0_p5_gate"]["runtime_mutation"], "FORBIDDEN_UNTIL_DISPATCH")
        self.assertEqual(
            plan["v0_p5_gate"]["accepted_predecessor_base"],
            "2a6721cdf02fa1134c59d1ab98bb7b597c66821d",
        )

        dispatched = dict(planned)
        dispatched["state"] = "DISPATCHED"
        plan = build_plan(self.contracts, work_order, dispatched)
        self.assertEqual(plan["mode"], "SINGLE_HIGH_RISK_PRODUCT_SLICE")
        self.assertEqual(plan["autonomous_runtime_workers"], 1)
        self.assertEqual(plan["next_action"], "BEGIN_V0_P5_EQUIPMENT_TOOLS")
        self.assertEqual(plan["v0_p5_gate"]["runtime_mutation"], "AUTHORIZED_BY_DISPATCH")
        self.assertEqual(plan["v0_p5_gate"]["global_mutation_lease_holder_checkpoint"], "V0_P5_EQUIPMENT_TOOLS")

    def test_future_product_checkpoints_remain_ineligible(self) -> None:
        self.assertEqual(self.scheduler["parallel_product_checkpoints"]["checkpoints"], ["V0_P5_EQUIPMENT_TOOLS"])
        self.assertEqual(
            set(self.scheduler["parallel_product_checkpoints"]["future_checkpoints_not_yet_eligible"]),
            {
                "V0_P6_PERSISTENT_SHARED_OUTPOST",
                "V0_SM1_SEAMLESS_PRODUCT_INTEGRATION",
                "V0_P7_BOUNDED_TERRAIN_MUTATION",
                "V0_P8_FIRST_MOBILE_CONSTRUCT",
            },
        )
        p6 = self.policy["checkpoint_sequence"][2]
        self.assertEqual(p6["state"], "PLANNED_NOT_ELIGIBLE")
        self.assertIn("V0_P5_CHECKPOINT_ACCEPTED", p6["activation_requires"])
        self.assertEqual(self.seamless["status"], "FUTURE_ACTIVATION_PLAN_NOT_ELIGIBLE")
        self.assertFalse(self.seamless["control_effect"]["production_sm1_activated"])
        self.assertFalse(self.seamless["control_effect"]["p6_state_changed"])
        self.assertFalse(self.seamless["control_effect"]["runtime_mutation_authorized"])

    def test_product_sequence_and_research_isolation_remain_unchanged(self) -> None:
        ids = [item["id"] for item in self.policy["checkpoint_sequence"]]
        self.assertEqual(
            ids,
            [
                "V0_P4_REAL_RESOURCE_CONSTRUCTION",
                "V0_P5_EQUIPMENT_TOOLS",
                "V0_P6_PERSISTENT_SHARED_OUTPOST",
                "V0_POST_P6_SEAMLESS_INSERTION_GATE",
                "V0_SM1_SEAMLESS_PRODUCT_INTEGRATION",
                "V0_P7_BOUNDED_TERRAIN_MUTATION",
                "V0_P8_FIRST_MOBILE_CONSTRUCT",
            ],
        )
        self.assertEqual(len(ids), len(set(ids)))
        self.assertIn("ECO", self.policy["research_isolation"]["explicitly_non_blocking_programs_for_current_p_train"])
        self.assertTrue(self.scheduler["research_isolation"]["non_blocking_by_default"])

    def test_post_p6_gate_routes_to_r2_convergence_contract(self) -> None:
        gate = self.policy["checkpoint_sequence"][3]
        self.assertEqual(gate["id"], "V0_POST_P6_SEAMLESS_INSERTION_GATE")
        self.assertEqual(gate["mandatory_plan"], "docs/plans/V0_POST_P6_SEAMLESS_CONVERGENCE_R2_RU.md")
        self.assertEqual(gate["mandatory_legacy_context"], "docs/plans/V0_POST_P6_SEAMLESS_INTEGRATION_RU.md")
        self.assertEqual(gate["mandatory_companion"], "docs/plans/V0_MULTI_ROUTE_PROJECTION_FABRIC_RU.md")
        self.assertEqual(
            gate["machine_convergence_contract"],
            "config/control/harness/v0-post-p6-seamless-convergence.v1.json",
        )
        self.assertEqual(
            gate["allowed_decisions"],
            ["ACTIVATE_V0_SM1", "DEFER_V0_SM1_WITH_EXPLICIT_HUMAN_DECISION"],
        )

    def test_seamless_convergence_roles_and_topology_are_explicit(self) -> None:
        roles = self.seamless["convergence_roles"]
        self.assertEqual(roles["V0_P6"]["role"], "PRODUCTION_EXECUTION_BASE")
        self.assertEqual(roles["SEAMLESS_R2_INCUBATION"]["role"], "SEMANTIC_AUTHORITY_DONOR")
        self.assertEqual(roles["SM0"]["role"], "HISTORICAL_SCENARIO_EVIDENCE_DONOR")
        self.assertEqual(roles["NX"]["role"], "PRODUCTION_NETWORK_FOUNDATION_OWNER")
        self.assertEqual(roles["MRPF"]["role"], "PROJECTION_TOPOLOGY_DONOR")
        self.assertEqual(roles["EDGE_GATEWAY"]["role"], "NON_AUTHORITATIVE_COMMAND_SESSION_ROUTER")
        self.assertFalse(roles["EDGE_GATEWAY"]["ownership_authority"])
        topology = self.seamless["transport_topology_decision"]
        self.assertEqual(topology["model"], "HYBRID_GATEWAY_COMMAND_SESSION_PLUS_OPTIONAL_DIRECT_PROJECTION")
        self.assertEqual(topology["canonical_command_session_plane"], "CLIENT_TO_STABLE_EDGE_GATEWAY")
        self.assertEqual(topology["projection_data_plane"], "DIRECT_SOURCE_TO_CLIENT_ALLOWED_WHEN_AUTHORIZED")
        self.assertTrue(topology["projection_is_read_only"])
        self.assertFalse(topology["projection_route_grants_mutation_authority"])
        self.assertFalse(topology["active_authority_must_relay_all_view_traffic"])

    def test_pre_p6_priority_moves_from_i2_to_domain_and_player_closure(self) -> None:
        self.assertEqual(
            self.seamless["pre_p6_priority"][:4],
            [
                "CLOSE_I2_AT_REVIEWED_I2_6_BOUNDARY_UNLESS_FRESH_REVIEW_FINDS_A_CONCRETE_BLOCKER",
                "I3_GENERIC_AUTHORITY_DOMAIN_TRANSFER",
                "I4_PLAYER_CARRYING_DOMAIN",
                "START_AND_MAINTAIN_I8_PRODUCTION_PORT_MAP_EARLY",
            ],
        )
        self.assertIn("COMPLETE_NX_SM1_OWNERSHIP_AUDIT_BEFORE_POST_P6_ACTIVATION", self.seamless["pre_p6_priority"])
        self.assertFalse(self.seamless["mrpf_policy"]["full_mrpf_completion_is_blanket_prerequisite"])

    def test_sm1_production_base_and_exact_activation_inputs_are_fail_closed(self) -> None:
        sm1 = self.policy["checkpoint_sequence"][4]
        self.assertEqual(sm1["production_base"], "THEN_CURRENT_ACCEPTED_P6_MAIN_DECLARED_PRODUCT_BASELINE")
        self.assertEqual(sm1["production_network_foundation_owner"], "NX_OR_ACCEPTED_SUCCESSOR")
        self.assertEqual(
            set(sm1["donors_are_not_product_bases"]),
            {"SEAMLESS_R2_INCUBATION", "SM0", "MRPF"},
        )
        required = set(self.seamless["post_p6_required_exact_inputs"])
        self.assertIn("EXACT_ACCEPTED_P6_PRODUCT_HEAD_AND_MAIN_DECLARED_SUCCESSOR_BASE", required)
        self.assertIn("EXACT_ACCEPTED_SEAMLESS_R2_INCUBATION_DONOR_BOUNDARY", required)
        self.assertIn("EXACT_FROZEN_SM0_EVIDENCE_DONOR_BOUNDARY", required)
        self.assertIn("EXACT_CURRENT_NX_PRODUCTION_NETWORK_FOUNDATION_BOUNDARY", required)
        self.assertEqual(
            self.seamless["production_branch_rule"]["base"],
            "THEN_CURRENT_ACCEPTED_P6_MAIN_DECLARED_V0_PRODUCT_BASELINE",
        )
        self.assertFalse(self.seamless["production_branch_rule"]["research_lineage_is_production_base"])
        self.assertTrue(self.seamless["production_branch_rule"]["donor_sha_is_provenance_not_ancestry_requirement"])
        self.assertEqual(
            self.seamless["fail_closed_network_rule"]["if_sm1_requires_new_protocol_or_network_foundation_owner"],
            "V0_BLOCKED_REQUIRES_NX_OR_MAIN_ARCHITECTURE",
        )
        self.assertFalse(self.seamless["fail_closed_network_rule"]["private_v0_implementation"])

    def test_project_goal_graph_still_exposes_product_order(self) -> None:
        train = next(item for item in self.goals["current_goal_graph"] if item["id"] == "V0_PRODUCT_TRAIN")
        self.assertEqual(train["policy"], "config/control/harness/v0-product-train-policy.v1.json")
        self.assertEqual(
            train["sequence"][4:],
            [
                "V0_P4_REAL_RESOURCE_CONSTRUCTION",
                "V0_P5_EQUIPMENT_TOOLS",
                "V0_P6_PERSISTENT_SHARED_OUTPOST",
                "V0_POST_P6_SEAMLESS_INSERTION_GATE",
                "V0_SM1_SEAMLESS_PRODUCT_INTEGRATION_OR_EXPLICIT_DEFER",
                "V0_P7_BOUNDED_TERRAIN_MUTATION",
                "V0_P8_FIRST_MOBILE_CONSTRUCT",
            ],
        )


if __name__ == "__main__":
    unittest.main()
