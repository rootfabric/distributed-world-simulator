from __future__ import annotations

import copy
import fnmatch
import json
import subprocess
import sys
import unittest
from unittest.mock import patch
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.checkpoint_planner import build_plan
from harness.contracts import ContractBundle, ContractValidationError, read_json
from harness.epoch_validator import validate_epoch
from harness.execution_selector import default_checkpoint
from harness.event_reducer import load_guard_context, reduce_events
from harness.state_builder import _implementation_pathspecs, _validate_semantics, build_state

ACTIVE_EXECUTION = ROOT / "config/control/harness/executions/E2026-08-12-H0-1-R8"
ACTIVE_WORK_ORDER_ID = "H0-1-R8-C22-WO-001"
EPOCH_BASE_SHA = "4a42c2fb6befb386f5c3eb48d9ba070745e25bbb"
HISTORICAL_R8_HEAD = "ab674669b9a293d898e5ca5983b4918cc685d990"
H0_0_R3_EXECUTION = ROOT / "config/control/harness/executions/E2026-08-11-H0-0-R3"


class H01R8ClosedLoopControlTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bundle = ContractBundle.load(ROOT)
        self.epoch = read_json(ACTIVE_EXECUTION / "project-epoch.v1.json")
        self.work_order = read_json(ACTIVE_EXECUTION / f"work-orders/{ACTIVE_WORK_ORDER_ID}.v1.json")
        self.transition = read_json(ACTIVE_EXECUTION / "transition-table.v1.json")
        self.events = [read_json(path) for path in sorted((ACTIVE_EXECUTION / f"events/{ACTIVE_WORK_ORDER_ID}").glob("*.json"))]
        self.guard = load_guard_context(ROOT, ACTIVE_EXECUTION)
        self.reduced = reduce_events(self.bundle, self.work_order, self.events, self.transition, self.guard)

    def _historical_bundle(self) -> ContractBundle:
        # Replay immutable R8 input with its actual generation-77 control snapshot.
        # This fixture is never installed into current registry, scheduler or Git refs.
        contracts = copy.deepcopy(self.bundle.contracts)
        paths = {
            "project_registry": "config/control/project-program-registry.v1.json",
            "scheduler_policy": "config/control/harness/scheduler-policy.v1.json",
            "checkpoint_catalog": "config/control/harness/checkpoint-catalog.v1.json",
        }
        for name, path in paths.items():
            contracts[name] = json.loads(subprocess.check_output(
                ["git", "show", f"{EPOCH_BASE_SHA}:{path}"], cwd=ROOT, text=True,
            ))
        return ContractBundle(root=ROOT, contracts=contracts)

    def _historical_state(self):
        with (
            patch("harness.state_builder.ContractBundle.load", return_value=self._historical_bundle()),
            patch("harness.state_builder._git_branch", return_value=self.work_order["branch"]),
        ):
            return build_state(ROOT, ACTIVE_EXECUTION)

    def test_current_generation_rejects_historical_r8_as_live_authority(self):
        self.assertGreater(self.bundle.contracts["project_registry"]["registry_generation"], 77)
        with self.assertRaisesRegex(ContractValidationError, "EPOCH_REGISTRY_GENERATION_MISMATCH"):
            build_state(ROOT, ACTIVE_EXECUTION)
        dispatched = {**self.reduced, "state": "DISPATCHED"}
        with self.assertRaisesRegex(ValueError, "GLOBAL_MUTATION_SLOT_RESERVED_FOR:"):
            build_plan(self.bundle.contracts, self.work_order, dispatched)

    def test_canonical_contracts_and_r8_instances_validate(self):
        self.bundle.validate("project_epoch_schema", self.epoch, "h0_1_r8_epoch")
        self.bundle.validate("work_order_schema", self.work_order, "h0_1_r8_work_order")
        for event in self.events:
            self.bundle.validate("event_schema", event, "h0_1_r8_event")
        _validate_semantics(self._historical_bundle(), self.epoch, self.work_order)
        self.assertEqual(77, self.epoch["registry_generation"])
        self.assertEqual(77, self._historical_bundle().contracts["project_registry"]["registry_generation"])
        self.assertEqual(EPOCH_BASE_SHA, self.epoch["base_sha"])
        self.assertEqual("IMPLEMENTATION", self.work_order["work_order_type"])
        self.assertEqual("HIGH", self.work_order["risk_class"])

    def test_ledger_rebuilds_and_snapshot_matches(self):
        self.assertTrue(self.reduced["snapshot_matches_authoritative_state"])
        self.assertEqual(self.work_order["state"], self.reduced["state"])
        self.assertGreaterEqual(self.reduced["last_event_sequence"], 1)

    def test_historical_state_replays_r8_without_selecting_current_authority(self):
        state = self._historical_state()
        self.assertEqual("E2026-08-12-H0-1-R8", state["epoch"]["epoch_id"])
        self.assertEqual(ACTIVE_WORK_ORDER_ID, state["active_work_order"]["work_order_id"])
        status = state["epoch"]["validation"]["status"]
        if state["epoch"]["validation"]["main_sha"] == EPOCH_BASE_SHA:
            self.assertEqual("EXACT_BASE", status)
        else:
            # A historical AUDIT_COMPLETED event cannot authorize a different main HEAD.
            self.assertEqual("MAIN_MOVED_REVIEW_REQUIRED", status)
            self.assertTrue(state["continuation_blocked"])

    def test_plan_never_exceeds_one_runtime_worker(self):
        state = self._historical_state()
        plan = build_plan(self._historical_bundle().contracts, state["active_work_order"], state["reduced_work_order"])
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
        plan = build_plan(self._historical_bundle().contracts, self.work_order, dispatched)
        self.assertEqual(1, plan["autonomous_runtime_workers"])
        self.assertEqual("AUTHORIZED_BY_DISPATCH", plan["c22_dry_run"]["branch_creation"])

    def test_launcher_uses_current_machine_selector_not_historical_r8(self):
        launcher = (ROOT / "CONTROL_DEVELOPMENT.ps1").read_text(encoding="utf-8")
        self.assertNotIn("E2026-08-12-H0-1-R8", launcher)
        self.assertIn("harness.cli", launcher)
        self.assertIn("$Checkpoint", launcher)
        self.assertNotEqual(self.work_order["goal_checkpoint"], default_checkpoint(self.bundle.contracts))
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
        self.assertIn("scripts/harness/**", allowed)
        self.assertIn("scripts/construction/proxies/construction_proxy_incremental_local_rebuilder.gd", allowed)
        self.assertIn("scripts/network/**", forbidden)
        self.assertIn("scripts/items/**", forbidden)
        self.assertIn("scripts/characters/**", forbidden)

    def test_implementation_freshness_scope_covers_runtime_without_self_staling_evidence(self):
        pathspecs = _implementation_pathspecs(ROOT, ACTIVE_EXECUTION, self.work_order)
        self.assertIn("scripts/harness/**", pathspecs)
        self.assertIn("scripts/construction/proxies/construction_proxy_incremental_local_rebuilder.gd", pathspecs)
        self.assertIn("RUN_WORLD_REGRESSION_TESTS.ps1", pathspecs)
        execution_prefix = f"config/control/harness/executions/{self.epoch['epoch_id']}/"
        self.assertNotIn(f"{execution_prefix}**", pathspecs)
        self.assertIn(f"{execution_prefix}transition-table.v1.json", pathspecs)
        self.assertFalse(any(path.startswith("config/control/branches/") for path in pathspecs))
        self.assertFalse(any(path.startswith("docs/checkpoints/") for path in pathspecs))

        state = self._historical_state()
        expected = subprocess.run(
            ["git", "log", "-1", "--format=%H", "--", *pathspecs],
            cwd=ROOT, text=True, capture_output=True, check=True,
        ).stdout.strip()
        self.assertEqual(expected, state["repository"]["implementation_head_sha"])
        self.assertEqual(expected, state["review"]["review_target_head_sha"])

    def test_historical_r8_diff_stays_inside_its_declared_scope(self):
        changed = subprocess.run(
            ["git", "diff", "--name-only", EPOCH_BASE_SHA, HISTORICAL_R8_HEAD],
            cwd=ROOT, text=True, capture_output=True, check=True,
        ).stdout.splitlines()
        self.assertTrue(changed, "historical scope audit must not silently inspect an empty current diff")
        allowed = tuple(self.work_order["allowed_paths"])
        violations = [path for path in changed if not any(fnmatch.fnmatch(path, pattern) for pattern in allowed)]
        self.assertFalse(violations, violations)

    def test_previous_attempts_are_not_selected_authority(self):
        launcher = (ROOT / "CONTROL_DEVELOPMENT.ps1").read_text(encoding="utf-8")
        self.assertNotIn("E2026-08-11-H0-1-R6'", launcher)
        self.assertNotIn("E2026-08-12-H0-1-R7'", launcher)
        self.assertEqual("feature/h0-1-c22-current-main-r3", self.work_order["branch"])


if __name__ == "__main__":
    unittest.main()
