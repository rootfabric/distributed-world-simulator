from __future__ import annotations

import fnmatch
import json
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.checkpoint_planner import build_plan
from harness.contracts import ContractBundle, read_json
from harness.event_reducer import load_guard_context, reduce_events
from harness.state_builder import _validate_semantics

CHECKPOINT = "H0_2_NX_C1_HIGH_RISK_PILOT"
R2_EXECUTION = ROOT / "config/control/harness/executions/E2026-08-13-H0-2-R2"
R2_WORK_ORDER_ID = "H0-2-R2-NX-C1-WO-001"
R2_BRANCH = "feature/h0-2-nx-c1-owner-authority-r2"
R2_BASE = "856d9ba8641942160283873c40494c12739acbcb"
R3 = "GLOBAL-P0-2026-08-12-R3-REFRESH-R1"


def load_json(path: str) -> dict:
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def git(*args: str) -> str:
    completed = subprocess.run(["git", *args], cwd=ROOT, text=True, capture_output=True, check=True)
    return completed.stdout.strip()


class H02MachineCheckpointContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.catalog = load_json("config/control/harness/checkpoint-catalog.v1.json")
        self.scheduler = load_json("config/control/harness/scheduler-policy.v1.json")
        self.goals = load_json("config/control/harness/project-goals.v1.json")
        self.contracts = {
            "checkpoint_catalog": self.catalog,
            "scheduler_policy": self.scheduler,
        }
        self.work_order = {
            "goal_checkpoint": CHECKPOINT,
        }

    def test_h0_2_checkpoint_exists_and_has_distinct_success_state(self):
        checkpoint = self.catalog["checkpoints"][CHECKPOINT]
        self.assertEqual("HARNESS", checkpoint["kind"])
        self.assertEqual("H0_2_PASS", checkpoint["success_state"])
        self.assertEqual("SOURCE_ACCEPTED", checkpoint["project_success_state"])
        self.assertEqual("H0_3_MULTI_WORKER_SCHEDULER", checkpoint["next_checkpoint"])

    def test_h0_2_is_bound_to_canonical_r3_and_post_r3_pc0(self):
        preconditions = set(self.catalog["checkpoints"][CHECKPOINT]["preconditions"])
        self.assertIn("GLOBAL_P0_R3_CANONICAL", preconditions)
        self.assertIn("REGISTRY_GENERATION_79", preconditions)
        self.assertIn("POST_R3_STANDARD_PC0_NON_RED", preconditions)
        self.assertIn("POST_R3_DIRECTIONAL_PC0_NON_RED", preconditions)
        self.assertIn("NO_GLOBAL_PROJECT_RED", preconditions)

    def test_h0_2_requires_high_risk_runtime_and_dependency_evidence(self):
        required = set(self.catalog["checkpoints"][CHECKPOINT]["required_predicates"])
        expected = {
            "PROJECT_EPOCH_R3_GENERATION_79_EXACT",
            "NX_C1_WORK_ORDER_ISSUED",
            "NX_C1_RISK_CLASSIFIED_HIGH_OR_CRITICAL",
            "FRESH_CURRENT_MAIN_NX_C1_BRANCH_CREATED",
            "OWNER_AUTHORITY_FOCUSED_PASS",
            "PHYSICS_PRESENTATION_SINGLE_WRITER_PASS",
            "ITEM_ROLLBACK_PICKUP_DROP_PASS",
            "TWO_CLIENT_PASS",
            "IMPAIRED_NETWORK_PASS",
            "RECONNECT_OWNERSHIP_EPOCH_PASS",
            "INDEPENDENT_REVIEWER_PASS",
            "STANDARD_PC0_NON_RED",
            "DIRECTIONAL_PC0_NON_RED_FOR_CRITICAL_HITS",
            "CH_TO_NX_DIRECTIONAL_REVALIDATION_PASS",
            "NX_CHECKPOINT_PROPOSED",
        }
        self.assertTrue(expected.issubset(required), sorted(expected - required))

    def test_scheduler_selects_h0_2_but_keeps_single_worker_ceiling(self):
        override = self.scheduler["current_pilot_override"]
        self.assertEqual(CHECKPOINT, override["current_checkpoint"])
        self.assertEqual(CHECKPOINT, override["checkpoint_sequence"][-1])
        self.assertEqual(1, self.scheduler["concurrency"]["h0_2_max_autonomous_runtime_workers"])
        self.assertTrue(self.scheduler["concurrency"]["h0_3_required_before_multi_runtime_worker_scheduler"])

    def test_goal_graph_routes_network_train_through_h0_2(self):
        goals = {entry["id"]: entry for entry in self.goals["current_goal_graph"]}
        self.assertEqual(CHECKPOINT, goals["HARNESS_H0_2"]["target_checkpoint"])
        self.assertEqual("NX_SOURCE_ACCEPTED", goals["HARNESS_H0_2"]["project_checkpoint"])
        self.assertEqual(["HARNESS_H0_2"], goals["NETWORK_TRAIN"]["depends_on"])

    def test_planner_allows_control_only_planning_branch_but_forbids_runtime_mutation_before_dispatch(self):
        reduced = {
            "completed_predicates": [],
            "work_order_id": "H0-2-NX-C1-WO-TEST",
            "state": "PLANNED",
        }
        plan = build_plan(self.contracts, self.work_order, reduced)
        self.assertEqual("PLANNING_ONLY", plan["mode"])
        self.assertEqual(0, plan["autonomous_runtime_workers"])
        self.assertEqual("PLANNING_BRANCH_ALLOWED_CONTROL_ONLY", plan["nx_c1_gate"]["branch_creation"])
        self.assertEqual("FORBIDDEN_UNTIL_DISPATCH", plan["nx_c1_gate"]["runtime_mutation"])
        self.assertEqual("HIGH", plan["nx_c1_gate"]["risk_floor"])
        self.assertIn("NX_C1_RUNTIME_MUTATION_BEFORE_DISPATCH", plan["stop_gates"])
        self.assertIn("H0_3_IMPLEMENTATION", plan["stop_gates"])

    def test_planner_dispatch_authorizes_exactly_one_high_risk_worker_on_current_work_order_branch(self):
        reduced = {
            "completed_predicates": ["PROJECT_EPOCH_CREATED"],
            "work_order_id": "H0-2-NX-C1-WO-TEST",
            "state": "DISPATCHED",
        }
        plan = build_plan(self.contracts, self.work_order, reduced)
        self.assertEqual("SINGLE_HIGH_RISK_RUNTIME_PILOT", plan["mode"])
        self.assertEqual(1, plan["autonomous_runtime_workers"])
        self.assertEqual("CURRENT_WORK_ORDER_BRANCH", plan["nx_c1_gate"]["branch_creation"])
        self.assertEqual("AUTHORIZED_BY_DISPATCH", plan["nx_c1_gate"]["runtime_mutation"])
        self.assertEqual("BEGIN_BOUNDED_NX_C1_IMPLEMENTATION_ON_DISPATCHED_BRANCH", plan["next_action"])
        self.assertEqual("CH_TO_NX_DIRECTIONAL_REVALIDATION_PASS", plan["nx_c1_gate"]["source_acceptance_requires"])

    def test_r2_execution_identity_schema_and_high_risk_design_are_exact(self):
        if not R2_EXECUTION.exists():
            self.skipTest("R2 execution package is branch-local")
        bundle = ContractBundle.load(ROOT)
        epoch = read_json(R2_EXECUTION / "project-epoch.v1.json")
        work_order = read_json(R2_EXECUTION / f"work-orders/{R2_WORK_ORDER_ID}.v1.json")
        bundle.validate("project_epoch_schema", epoch, "h0_2_r2_epoch")
        bundle.validate("work_order_schema", work_order, "h0_2_r2_work_order")
        _validate_semantics(bundle, epoch, work_order)
        self.assertEqual(R2_BASE, epoch["base_sha"])
        self.assertEqual(R2_BASE, work_order["base_sha"])
        self.assertEqual(79, epoch["registry_generation"])
        self.assertEqual(R3, epoch["architecture_revision"])
        self.assertEqual(R2_BRANCH, work_order["branch"])
        self.assertEqual("NX", work_order["program"])
        self.assertEqual(CHECKPOINT, work_order["goal_checkpoint"])
        self.assertEqual("HIGH", work_order["risk_class"])
        self.assertEqual(["IMPLEMENTER", "REVIEWER", "VERIFIER", "DIRECTOR"], work_order["required_review_roles"])
        self.assertTrue(work_order["review_required"])
        self.assertTrue(work_order["evidence_map_required"])
        self.assertIn("scripts/network/contracts/network_protocol_manifest.gd", work_order["forbidden_paths"])
        self.assertIn("scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd", work_order["forbidden_paths"])
        self.assertIn("scripts/items/**", work_order["forbidden_paths"])
        self.assertIn("scripts/characters/**", work_order["forbidden_paths"])
        self.assertIn("RUNTIME_FEATURE_MERGE", work_order["human_approval_required_for"])

    def test_r2_append_only_ledger_and_dispatch_authorization_are_fail_closed(self):
        if not R2_EXECUTION.exists():
            self.skipTest("R2 execution package is branch-local")
        bundle = ContractBundle.load(ROOT)
        work_order = read_json(R2_EXECUTION / f"work-orders/{R2_WORK_ORDER_ID}.v1.json")
        transition = read_json(R2_EXECUTION / "transition-table.v1.json")
        event_dir = R2_EXECUTION / "events" / R2_WORK_ORDER_ID
        events = [read_json(path) for path in sorted(event_dir.glob("*.json"))]
        for event in events:
            bundle.validate("event_schema", event, "h0_2_r2_event")
        reduced = reduce_events(bundle, work_order, events, transition, load_guard_context(ROOT, R2_EXECUTION))
        self.assertEqual(work_order["state"], reduced["state"])
        self.assertEqual(R2_BRANCH, work_order["branch"])
        self.assertEqual("WORK_ORDER_CREATED", events[0]["event_type"])
        self.assertEqual(R2_BASE, events[0]["head_sha"])

        changed = git("diff", "--name-only", "origin/main...HEAD").splitlines()
        if reduced["state"] == "PLANNED":
            control_only = (
                "config/control/harness/executions/E2026-08-13-H0-2-R2/**",
                "config/control/branches/feature__h0-2-nx-c1-owner-authority-r2.v1.json",
                "docs/plans/H0_2_NX_C1_OWNER_AUTHORITY_R2_RU.md",
                "tests/harness/test_h0_2_machine_checkpoint_contract.py",
            )
            violations = [path for path in changed if not any(fnmatch.fnmatch(path, pattern) for pattern in control_only)]
            self.assertFalse(violations, violations)
            plan = build_plan(self.contracts, work_order, reduced)
            self.assertEqual("FORBIDDEN_UNTIL_DISPATCH", plan["nx_c1_gate"]["runtime_mutation"])
            self.assertEqual(0, plan["autonomous_runtime_workers"])
            self.assertEqual(1, len(events))
        elif reduced["state"] == "DISPATCHED":
            self.assertEqual(2, len(events))
            self.assertEqual("DISPATCHED", events[1]["event_type"])
            reviews = [read_json(path) for path in sorted((R2_EXECUTION / "reviews").glob("*.json"))]
            prebuild = [item for item in reviews if item.get("review_type") == "PRE_BUILD_DESIGN_AUTHORIZATION"]
            self.assertEqual(1, len(prebuild))
            self.assertEqual("PASS", prebuild[0]["verdict"])
            self.assertEqual(prebuild[0]["reviewed_head_sha"], events[1]["head_sha"])
            self.assertNotIn("IMPLEMENTER", prebuild[0]["reviewer"].upper())
            plan = build_plan(self.contracts, work_order, reduced)
            self.assertEqual("AUTHORIZED_BY_DISPATCH", plan["nx_c1_gate"]["runtime_mutation"])
            self.assertEqual(1, plan["autonomous_runtime_workers"])
            scope_violations = [
                path for path in changed
                if not any(fnmatch.fnmatch(path, pattern) for pattern in work_order["allowed_paths"])
            ]
            self.assertFalse(scope_violations, scope_violations)
        else:
            self.assertIn(reduced["state"], {"IN_PROGRESS", "IMPLEMENTED", "VERIFYING", "VERIFIED", "AUDITED", "CHECKPOINT_PROPOSED", "FIX_REQUIRED", "BLOCKED", "WAITING_HUMAN", "EPOCH_INVALIDATED", "CANCELLED"})


if __name__ == "__main__":
    unittest.main()
