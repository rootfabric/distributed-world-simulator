from __future__ import annotations

import copy
import fnmatch
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

ACTIVE_EXECUTION = ROOT / "config/control/harness/executions/E2026-08-12-H0-1-R7"
ACTIVE_WORK_ORDER_ID = "H0-1-R7-C22-WO-001"
EPOCH_BASE_SHA = "4a42c2fb6befb386f5c3eb48d9ba070745e25bbb"
H0_0_R3_EXECUTION = ROOT / "config/control/harness/executions/E2026-08-11-H0-0-R3"


class H01R7ClosedLoopControlTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bundle = ContractBundle.load(ROOT)
        self.epoch = read_json(ACTIVE_EXECUTION / "project-epoch.v1.json")
        self.work_order = read_json(ACTIVE_EXECUTION / f"work-orders/{ACTIVE_WORK_ORDER_ID}.v1.json")
        self.transition = read_json(ACTIVE_EXECUTION / "transition-table.v1.json")
        self.events = [read_json(path) for path in sorted((ACTIVE_EXECUTION / f"events/{ACTIVE_WORK_ORDER_ID}").glob("*.json"))]
        self.guard = load_guard_context(ROOT, ACTIVE_EXECUTION)
        self.reduced = reduce_events(self.bundle, self.work_order, self.events, self.transition, self.guard)

    def test_canonical_contracts_and_r7_instances_validate(self):
        self.bundle.validate("project_epoch_schema", self.epoch, "h0_1_r7_epoch")
        self.bundle.validate("work_order_schema", self.work_order, "h0_1_r7_work_order")
        for event in self.events:
            self.bundle.validate("event_schema", event, "h0_1_r7_event")
        _validate_semantics(self.bundle, self.epoch, self.work_order)
        self.assertEqual(77, self.epoch["registry_generation"])
        self.assertEqual(77, self.bundle.contracts["project_registry"]["registry_generation"])
        self.assertEqual(EPOCH_BASE_SHA, self.epoch["base_sha"])
        self.assertEqual("IMPLEMENTATION", self.work_order["work_order_type"])
        self.assertEqual("HIGH", self.work_order["risk_class"])

    def test_ledger_rebuilds_and_snapshot_matches(self):
        self.assertTrue(self.reduced["snapshot_matches_authoritative_state"])
        self.assertEqual(self.work_order["state"], self.reduced["state"])
        self.assertGreaterEqual(self.reduced["last_event_sequence"], 1)

    def test_public_state_selects_r7(self):
        state = build_state(ROOT, ACTIVE_EXECUTION)
        self.assertEqual("E2026-08-12-H0-1-R7", state["epoch"]["epoch_id"])
        self.assertEqual(ACTIVE_WORK_ORDER_ID, state["active_work_order"]["work_order_id"])
        status = state["epoch"]["validation"]["status"]
        if state["epoch"]["validation"]["main_sha"] == EPOCH_BASE_SHA:
            self.assertEqual("EXACT_BASE", status)
        elif any(event.get("event_type") == "AUDIT_COMPLETED" for event in self.events):
            self.assertEqual("MAIN_MOVED_AUDIT_CONTINUE", status)
        else:
            self.assertEqual("MAIN_MOVED_REVIEW_REQUIRED", status)
            self.assertTrue(state["continuation_blocked"])

    def test_plan_never_exceeds_one_runtime_worker(self):
        state = build_state(ROOT, ACTIVE_EXECUTION)
        plan = build_plan(self.bundle.contracts, state["active_work_order"], state["reduced_work_order"])
        self.assertLessEqual(plan["autonomous_runtime_workers"], 1)
        if self.reduced["state"] == "PLANNED":
            self.assertEqual("PLANNING_ONLY", plan["mode"])
            self.assertEqual(0, plan["autonomous_runtime_workers"])
            self.assertEqual("FORBIDDEN_UNTIL_DISPATCH", plan["c22_dry_run"]["branch_creation"])
        elif self.reduced["state"] in {"DISPATCHED", "IN_PROGRESS", "IMPLEMENTED", "VERIFYING"}:
            self.assertEqual("SINGLE_RUNTIME_PILOT", plan["mode"])

    def test_dispatch_simulation_authorizes_exactly_one_worker(self):
        dispatched = copy.deepcopy(self.reduced)
        dispatched["state"] = "DISPATCHED"
        plan = build_plan(self.bundle.contracts, self.work_order, dispatched)
        self.assertEqual(1, plan["autonomous_runtime_workers"])
        self.assertEqual("AUTHORIZED_BY_DISPATCH", plan["c22_dry_run"]["branch_creation"])

    def test_launcher_points_only_to_r7(self):
        launcher = (ROOT / "CONTROL_DEVELOPMENT.ps1").read_text(encoding="utf-8")
        self.assertIn("E2026-08-12-H0-1-R7", launcher)
        self.assertNotIn("$executionPath = 'config/control/harness/executions/E2026-08-11-H0-1-R6'", launcher)
        self.assertNotIn("$executionPath = 'config/control/harness/executions/E2026-08-11-H0-1-R5'", launcher)

    def test_h0_0_checkpoint_remains_historical_terminal(self):
        old_work_order = read_json(H0_0_R3_EXECUTION / "work-orders/H0-0-R3-WO-001.v1.json")
        self.assertEqual("CHECKPOINT_PROPOSED", old_work_order["state"])

    def test_registry_generation_identity_fail_closed(self):
        changed = copy.deepcopy(self.epoch)
        changed["registry_generation"] = 76
        with self.assertRaisesRegex(ContractValidationError, "EPOCH_REGISTRY_GENERATION_MISMATCH"):
            _validate_semantics(self.bundle, changed, self.work_order)

    def test_epoch_validator_requires_audit_after_main_move(self):
        result = validate_epoch(ROOT, self.epoch, "main", None)
        if result["main_sha"] == EPOCH_BASE_SHA:
            self.assertEqual("EXACT_BASE", result["status"])
            self.assertEqual("CONTINUE", result["action"])
        else:
            self.assertEqual("MAIN_MOVED_REVIEW_REQUIRED", result["status"])
            self.assertEqual("BLOCK_CONTINUATION", result["action"])

    def test_work_order_scope_is_bounded_and_includes_harness(self):
        allowed = tuple(self.work_order["allowed_paths"])
        forbidden = tuple(self.work_order["forbidden_paths"])
        self.assertIn("tests/harness/**", allowed)
        self.assertIn("scripts/construction/proxies/construction_proxy_incremental_local_rebuilder.gd", allowed)
        self.assertIn("scripts/network/**", forbidden)
        self.assertIn("scripts/items/**", forbidden)
        self.assertIn("scripts/characters/**", forbidden)

    def test_current_diff_stays_inside_declared_scope(self):
        base = subprocess.run(["git", "merge-base", "origin/main", "HEAD"], cwd=ROOT, text=True, capture_output=True, check=True).stdout.strip()
        changed = subprocess.run(["git", "diff", "--name-only", f"{base}..HEAD"], cwd=ROOT, text=True, capture_output=True, check=True).stdout.splitlines()
        allowed = tuple(self.work_order["allowed_paths"])
        violations = [path for path in changed if not any(fnmatch.fnmatch(path, pattern) for pattern in allowed)]
        self.assertFalse(violations, violations)

    def test_r6_is_not_selected_authority(self):
        launcher = (ROOT / "CONTROL_DEVELOPMENT.ps1").read_text(encoding="utf-8")
        self.assertNotIn("E2026-08-11-H0-1-R6'", launcher)
        self.assertNotEqual("feature/h0-1-c22-current-main-r1", self.work_order["branch"])


if __name__ == "__main__":
    unittest.main()
