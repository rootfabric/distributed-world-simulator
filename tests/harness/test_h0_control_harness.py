from __future__ import annotations

import copy
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.checkpoint_planner import build_plan
from harness.contracts import ContractBundle, ContractValidationError, read_json
from harness.epoch_validator import validate_epoch
from harness.event_reducer import load_guard_context, reduce_events
from harness.state_builder import _validate_semantics, build_state

ACTIVE_EXECUTION = ROOT / "config/control/harness/executions/E2026-08-11-H0-1-R1"
ACTIVE_WORK_ORDER_ID = "H0-1-R1-DISPATCH-WO-001"
EPOCH_BASE_SHA = "be6ea2a8636a9242fc808aea377d9144ef9bc9eb"
R3_EXECUTION = ROOT / "config/control/harness/executions/E2026-08-11-H0-0-R3"


class CanonicalHandoffTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bundle = ContractBundle.load(ROOT)
        self.epoch = read_json(ACTIVE_EXECUTION / "project-epoch.v1.json")
        self.work_order = read_json(ACTIVE_EXECUTION / f"work-orders/{ACTIVE_WORK_ORDER_ID}.v1.json")
        self.transition = read_json(ACTIVE_EXECUTION / "transition-table.v1.json")
        self.events = [read_json(path) for path in sorted((ACTIVE_EXECUTION / f"events/{ACTIVE_WORK_ORDER_ID}").glob("*.json"))]
        self.guard = load_guard_context(ROOT, ACTIVE_EXECUTION)

    def test_canonical_contracts_and_h0_1_instances_validate(self):
        self.bundle.validate("project_epoch_schema", self.epoch, "h0_1_epoch")
        self.bundle.validate("work_order_schema", self.work_order, "h0_1_work_order")
        for event in self.events:
            self.bundle.validate("event_schema", event, "h0_1_event")
        _validate_semantics(self.bundle, self.epoch, self.work_order)
        self.assertEqual(69, self.epoch["registry_generation"])
        self.assertEqual(EPOCH_BASE_SHA, self.epoch["base_sha"])
        self.assertEqual("H0_1_CLOSED_LOOP_C22_PILOT", self.work_order["goal_checkpoint"])

    def test_planning_ledger_is_rebuildable_and_runtime_closed(self):
        reduced = reduce_events(self.bundle, self.work_order, self.events, self.transition, self.guard)
        self.assertEqual("PLANNED", reduced["state"])
        self.assertTrue(reduced["snapshot_matches_authoritative_state"])
        self.assertEqual(1, reduced["last_event_sequence"])

    def test_public_state_selects_fresh_h0_1_epoch(self):
        state = build_state(ROOT, ACTIVE_EXECUTION)
        self.assertEqual("E2026-08-11-H0-1-R1", state["epoch"]["epoch_id"])
        self.assertEqual(ACTIVE_WORK_ORDER_ID, state["active_work_order"]["work_order_id"])
        self.assertFalse(state["runtime_authorized"])
        self.assertEqual("EXACT_BASE", state["epoch"]["validation"]["status"])

    def test_plan_keeps_c22_branch_creation_closed_before_dispatch(self):
        state = build_state(ROOT, ACTIVE_EXECUTION)
        plan = build_plan(self.bundle.contracts, state["active_work_order"], state["reduced_work_order"])
        self.assertEqual("H0_1_CLOSED_LOOP_C22_PILOT", plan["selected_checkpoint"])
        self.assertEqual("PLANNING_ONLY", plan["mode"])
        self.assertEqual(0, plan["autonomous_runtime_workers"])
        self.assertEqual("WAITING_DIRECTOR_DISPATCH", plan["c22_dry_run"]["status"])
        self.assertEqual("FORBIDDEN_UNTIL_DISPATCH", plan["c22_dry_run"]["branch_creation"])

    def test_plan_allows_at_most_one_worker_only_after_dispatch(self):
        state = build_state(ROOT, ACTIVE_EXECUTION)
        dispatched = copy.deepcopy(state["reduced_work_order"])
        dispatched["state"] = "DISPATCHED"
        plan = build_plan(self.bundle.contracts, state["active_work_order"], dispatched)
        self.assertEqual("SINGLE_RUNTIME_PILOT", plan["mode"])
        self.assertEqual(1, plan["autonomous_runtime_workers"])
        self.assertEqual("AUTHORIZED_BY_DISPATCH", plan["c22_dry_run"]["branch_creation"])

    def test_launcher_points_only_to_fresh_h0_1_execution(self):
        launcher = (ROOT / "CONTROL_DEVELOPMENT.ps1").read_text(encoding="utf-8")
        self.assertIn("E2026-08-11-H0-1-R1", launcher)
        self.assertNotIn("$executionPath = 'config/control/harness/executions/E2026-08-11-H0-0-R3'", launcher)

    def test_r3_checkpoint_evidence_is_historical_and_terminal(self):
        self.assertTrue(R3_EXECUTION.exists())
        old_work_order = read_json(R3_EXECUTION / "work-orders/H0-0-R3-WO-001.v1.json")
        self.assertEqual("CHECKPOINT_PROPOSED", old_work_order["state"])
        terminal = read_json(R3_EXECUTION / "events/H0-0-R3-WO-001/0025-h0-0-scaffold-ready-checkpoint-proposed.v1.json")
        self.assertEqual("CHECKPOINT_PROPOSED", terminal["event_type"])
        self.assertEqual("H0_0_SCAFFOLD_READY", terminal["predicate"])

    def test_registry_generation_identity_remains_fail_closed(self):
        changed = copy.deepcopy(self.epoch)
        changed["registry_generation"] = 68
        with self.assertRaisesRegex(ContractValidationError, "EPOCH_REGISTRY_GENERATION_MISMATCH"):
            _validate_semantics(self.bundle, changed, self.work_order)

    def test_epoch_validator_detects_current_main_relationship(self):
        result = validate_epoch(ROOT, self.epoch, "main", None)
        self.assertIn(result["status"], {"EXACT_BASE", "MAIN_MOVED_REVIEW_REQUIRED"})
        if result["status"] == "MAIN_MOVED_REVIEW_REQUIRED":
            self.assertEqual("BLOCK_CONTINUATION", result["action"])

    def test_canonicalization_diff_has_no_runtime_domain_paths(self):
        base = subprocess.run(["git", "merge-base", "origin/main", "HEAD"], cwd=ROOT, text=True, capture_output=True, check=True).stdout.strip()
        changed = subprocess.run(["git", "diff", "--name-only", f"{base}..HEAD"], cwd=ROOT, text=True, capture_output=True, check=True).stdout.splitlines()
        forbidden = ("scenes/", "scripts/runtime/", "scripts/network/", "scripts/simulation/", "scripts/items/", "scripts/characters/", "scripts/construction/")
        self.assertFalse([path for path in changed if path.startswith(forbidden)])

    def test_h0_1_planning_work_order_forbids_runtime_paths(self):
        forbidden = tuple(self.work_order["forbidden_paths"])
        self.assertIn("scripts/construction/**", forbidden)
        self.assertIn("scripts/network/**", forbidden)
        self.assertIn("scripts/runtime/**", forbidden)
        self.assertIn("scripts/simulation/**", forbidden)


if __name__ == "__main__":
    unittest.main()
