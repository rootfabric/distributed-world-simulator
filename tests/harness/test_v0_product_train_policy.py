from __future__ import annotations

import json
import os
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HARNESS = ROOT / "config" / "control" / "harness"
sys.path.insert(0, str(ROOT / "scripts"))

from harness.checkpoint_planner import build_plan

P7 = "V0_P7_BOUNDED_TERRAIN_MUTATION"
P7_BRANCH = "feature/v0-p7-bounded-terrain-mutation"
P7_EXECUTION = HARNESS / "executions/E2026-08-30-V0-P7-R1"
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
        self.assertEqual("P7_5_COMPLETE_MERGED_P7_6_NEXT", self.policy["current_phase"])
        routing = self.scheduler["v0_product_train_routing"]
        self.assertEqual(P7, routing["current_checkpoint"])
        self.assertTrue(routing["runtime_mutation_allowed_now"])
        self.assertTrue(routing["next_runtime_checkpoint_eligible"])
        self.assertNotIn("P7_MATTER_OWNER_MAP_FRESH_REVIEW_PASS", routing["p7_remaining_activation_prerequisites"])
        self.assertNotIn("POST_MERGE_STANDARD_AND_DIRECTIONAL_PC0_NON_RED", routing["p7_remaining_activation_prerequisites"])
        self.assertEqual([], routing["p7_remaining_activation_prerequisites"])
        self.assertEqual("ACCEPTED", routing["p7_0"]["status"])
        self.assertEqual("PASS_NON_RED", routing["p7_post_merge_pc0"]["status"])
        self.assertEqual("COMPLETE_MERGED", routing["p7_5"]["state"])
        self.assertEqual("RESOLVED_BY_PR_432", routing["p7_5"]["control_precondition"])

    def test_p7_activation_binds_exact_accepted_sm1_lineage(self) -> None:
        self.assertEqual(P7, self.activation_p7["checkpoint"])
        self.assertEqual(SM1_BASE, self.activation_p7["main_declared_exact_successor_base"])
        self.assertEqual(SM1_BASE, self.epoch_p7["base_sha"])
        self.assertEqual([P7], self.epoch_p7["eligible_checkpoints"])
        self.assertEqual(SM1_BASE, self.work_order_p7["base_sha"])
        self.assertEqual(P7_BRANCH, self.work_order_p7["branch"])
        self.assertEqual("IN_PROGRESS", self.work_order_p7["state"])
        self.assertEqual("CRITICAL", self.work_order_p7["risk_class"])
        self.assertTrue(self.activation_p7["mutation_lease"]["runtime_mutation_authorized"])
        self.assertEqual("DISPATCHED", self.activation_p7["director_dispatch"]["status"])

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
        self.assertEqual("ACTIVE_V0_P7_IN_PROGRESS_RUNTIME_MUTATION", lease["state"])
        self.assertEqual(1, self.scheduler["concurrency"]["pre_h0_3_total_autonomous_runtime_mutation_workers"])

    def test_planner_exposes_p7_but_blocks_dispatch_until_control_gates_close(self) -> None:
        contracts = {"checkpoint_catalog": self.catalog, "scheduler_policy": self.scheduler}
        planned = {"completed_predicates": [], "work_order_id": "V0-P7-R1-WO-001", "state": "PLANNED"}
        plan = build_plan(contracts, self.work_order_p7, planned)
        self.assertEqual("PLANNING_ONLY", plan["mode"])
        self.assertIn("v0_p7_gate", plan)
        self.assertEqual("MW4_MW10_EXISTING_CANONICAL_FOUNDATION", plan["v0_p7_gate"]["matter_truth"])
        dispatched = dict(planned, state="DISPATCHED")
        dispatched_plan = build_plan(contracts, self.work_order_p7, dispatched)
        self.assertEqual("SINGLE_HIGH_RISK_PRODUCT_SLICE", dispatched_plan["mode"])
        self.assertEqual("AUTHORIZED_BY_DISPATCH", dispatched_plan["v0_p7_gate"]["runtime_mutation"])
        self.assertEqual("BEGIN_V0_P7_MATTER_PRODUCTION_CONVERGENCE", dispatched_plan["next_action"])


    def test_p7_0_exact_source_owner_map_is_bound_to_existing_owners(self) -> None:
        owner_map = _load(HARNESS / "v0-p7-matter-production-owner-map.v1.json")
        self.assertEqual("REVIEW_READY", owner_map["status"])
        self.assertEqual("V0-P7-0-OWNER-MAP-2026-08-30-R2", owner_map["revision"])
        self.assertFalse(owner_map["runtime_mutation"])
        self.assertEqual("PASS", owner_map["no_second_owner_audit"]["result"])
        self.assertEqual(0, owner_map["no_second_owner_audit"]["duplicate_owner_count"])
        decisions = owner_map["core_decisions"]
        self.assertEqual("USE_EXISTING_MATTER_MUTATION_REQUEST_RESULT", decisions["mutation_contract"])
        self.assertEqual("USE_EXISTING_MW6_MATTER_MUTATION_HANDLER", decisions["gateway_ingress"])
        self.assertEqual("MW10_ONLY_WHEN_ONE_CANONICAL_MUTATION_SPANS_TWO_OR_MORE_MATTER_REGIONS", decisions["cross_region"])
        self.assertFalse(decisions["new_canonical_state_owner"])
        self.assertEqual("MatterMutationRequest.actor_id = canonical V0 player_entity_id; logical_player_id remains gameplay lookup identity", decisions["actor_identity"])
        identity = owner_map["identity_projection"]
        self.assertEqual("player_entity_id", identity["matter_actor_id"])
        self.assertFalse(identity["new_identity_owner"])
        self.assertFalse(identity["new_identity_store"])
        player_registry = (ROOT / "scripts/runtime/networked_gameplay/services/player_registry.gd").read_text(encoding="utf-8")
        self.assertIn('String(record.get("player_entity_id", "")) != "player/%s" % logical_id', player_registry)
        matter_utils = (ROOT / "scripts/simulation/spatial/spatial_contract_utils.gd").read_text(encoding="utf-8")
        self.assertIn("parts.size() < minimum_parts", matter_utils)

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


    def _run_p7_control_cli(self, mode: str):
        env = dict(os.environ)
        scripts = str(ROOT / "scripts")
        env["PYTHONPATH"] = scripts + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")

        original_head = subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
        ).strip()
        original_branch = subprocess.check_output(
            ["git", "branch", "--show-current"], cwd=ROOT, text=True
        ).strip()
        rebound_detached_head = not original_branch
        if rebound_detached_head:
            # Project Control checks out the exact PR subject detached. The Harness
            # intentionally requires an active Work Order branch, so bind the same
            # exact commit to the P7 branch name for this CLI probe only.
            subprocess.check_call(
                ["git", "branch", "-f", P7_BRANCH, original_head],
                cwd=ROOT,
            )
            subprocess.check_call(
                ["git", "symbolic-ref", "HEAD", f"refs/heads/{P7_BRANCH}"],
                cwd=ROOT,
            )
        try:
            completed = subprocess.run(
                [
                    sys.executable,
                    "-m",
                    "harness.cli",
                    mode,
                    "--root",
                    str(ROOT),
                    "--execution",
                    str(P7_EXECUTION),
                ],
                cwd=ROOT,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
        finally:
            if rebound_detached_head:
                subprocess.check_call(
                    ["git", "checkout", "--detach", original_head],
                    cwd=ROOT,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
        payload = json.loads(completed.stdout.strip().splitlines()[-1])
        return completed, payload

    def test_p7_transition_ledger_repair_restores_drive_without_contract_exit_3(self) -> None:
        completed, payload = self._run_p7_control_cli("drive")
        self.assertEqual(0, completed.returncode, completed.stderr or completed.stdout)
        self.assertTrue(payload["ok"])
        self.assertEqual("DRIVE", payload["command"])
        self.assertEqual("IN_PROGRESS", payload["reduced_work_order"]["state"])
        reconciliation = payload["event_ledger_reconciliation"]
        self.assertTrue(reconciliation["active"])
        self.assertEqual(14, reconciliation["quarantined_event_count"])
        self.assertEqual(6, reconciliation["authoritative_event_count"])
        self.assertEqual(6, reconciliation["canonical_next_sequence"])
        self.assertEqual("CONTINUE_REQUIRED", payload["drive"]["status"])
        self.assertTrue(payload["drive"]["auto_continue_required"])
        self.assertFalse(payload["next"]["mission_exit_allowed"])

    def test_p7_transition_ledger_repair_keeps_close_mission_fail_closed_until_p7_acceptance(self) -> None:
        completed, payload = self._run_p7_control_cli("close-mission")
        self.assertEqual(8, completed.returncode, completed.stderr or completed.stdout)
        self.assertFalse(payload["ok"])
        self.assertEqual("MISSION_EXIT_FORBIDDEN", payload["error"]["code"])
        self.assertIn("CHECKPOINT_MISSION_STILL_OPEN", payload["error"]["detail"])

    def test_p7_reconciliation_blob_pins_match_current_immutable_event_files(self) -> None:
        manifest = _load(P7_EXECUTION / "event-ledger-reconciliation.v1.json")
        self.assertEqual(
            "QUARANTINE_EXACT_IMMUTABLE_NONCANONICAL_EVENTS",
            manifest["mode"],
        )
        self.assertEqual(14, len(manifest["quarantined_events"]))
        for record in manifest["quarantined_events"]:
            relative = record["path"]
            self.assertFalse(any(marker in relative for marker in ("*", "?", "[")), relative)
            observed = subprocess.check_output(
                ["git", "rev-parse", f"HEAD:{relative}"],
                cwd=ROOT,
                text=True,
            ).strip()
            self.assertEqual(record["git_blob_sha"], observed, relative)
            history = subprocess.check_output(
                ["git", "log", "--format=%H", "--", relative],
                cwd=ROOT,
                text=True,
            ).splitlines()
            self.assertEqual(1, len(history), relative)


if __name__ == "__main__":
    unittest.main()
