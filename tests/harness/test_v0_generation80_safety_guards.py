from __future__ import annotations

import copy
import json
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.checkpoint_planner import build_plan
from harness.contracts import ContractBundle, ContractValidationError, read_json
from harness.event_reducer import load_guard_context, reduce_events

P4 = "V0_P4_REAL_RESOURCE_CONSTRUCTION"
P4_BRANCH = "feature/v0-p4-construction-real-resources"
P4_RUNNER = "RUN_V0_P4_POST_ACTIVATION_EPOCH_AUDIT.ps1"
H0_2 = "H0_2_NX_C1_HIGH_RISK_PILOT"
HISTORICAL_EXECUTION = ROOT / "config/control/harness/executions/E2026-08-12-H0-1-R8"
HISTORICAL_WORK_ORDER = HISTORICAL_EXECUTION / "work-orders/H0-1-R8-C22-WO-001.v1.json"
HISTORICAL_EVENTS = HISTORICAL_EXECUTION / "events/H0-1-R8-C22-WO-001"
HISTORICAL_TRANSITION = HISTORICAL_EXECUTION / "transition-table.v1.json"


def load_json(path: str) -> dict:
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


class Generation80SafetyGuardTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bundle = ContractBundle.load(ROOT)
        self.scheduler = load_json("config/control/harness/scheduler-policy.v1.json")
        self.catalog = load_json("config/control/harness/checkpoint-catalog.v1.json")
        self.registry = load_json("config/control/project-program-registry.v1.json")
        self.contracts = {
            "checkpoint_catalog": self.catalog,
            "scheduler_policy": self.scheduler,
        }

    def test_generation80_reserves_one_global_mutation_lease_for_p4(self):
        self.assertEqual(80, self.registry["registry_generation"])
        lease = self.scheduler["pre_h0_3_runtime_mutation_lease"]
        self.assertEqual(80, lease["effective_registry_generation"])
        self.assertEqual(1, lease["capacity"])
        self.assertEqual("V0", lease["holder_program"])
        self.assertEqual(P4, lease["holder_checkpoint"])
        self.assertEqual(P4_BRANCH, lease["holder_branch"])
        self.assertEqual(["DISPATCHED", "IN_PROGRESS"], lease["mutating_states"])
        self.assertTrue(lease["implementation_complete_releases_worker"])
        self.assertTrue(lease["initial_dispatch_requires_director"])
        self.assertTrue(lease["holder_initial_dispatch_requires_authoritative_epoch_audit"])
        self.assertTrue(lease["non_holder_dispatch_forbidden"])
        self.assertTrue(lease["release_requires_main_owned_control_update"])

    def test_p4_dispatch_gets_the_single_worker_and_implemented_releases_it(self):
        work_order = {"goal_checkpoint": P4, "branch": P4_BRANCH}
        dispatched = {
            "completed_predicates": ["PROJECT_EPOCH_CREATED"],
            "work_order_id": "V0-P4-WO-TEST",
            "state": "DISPATCHED",
        }
        plan = build_plan(self.contracts, work_order, dispatched)
        self.assertEqual("SINGLE_HIGH_RISK_PRODUCT_SLICE", plan["mode"])
        self.assertEqual(1, plan["autonomous_runtime_workers"])
        self.assertEqual("AUTHORIZED_BY_DISPATCH", plan["v0_p4_gate"]["runtime_mutation"])
        self.assertEqual(P4, plan["v0_p4_gate"]["global_mutation_lease_holder_checkpoint"])

        implemented = copy.deepcopy(dispatched)
        implemented["state"] = "IMPLEMENTED"
        plan = build_plan(self.contracts, work_order, implemented)
        self.assertEqual("PRODUCT_RUNTIME_VERIFICATION", plan["mode"])
        self.assertEqual(0, plan["autonomous_runtime_workers"])
        self.assertEqual("NO_ACTIVE_MUTATION_SLOT", plan["v0_p4_gate"]["runtime_mutation"])
        self.assertEqual("VERIFY_V0_P4_EXACT_HEAD", plan["next_action"])

    def test_generation80_blocks_new_nx_and_unknown_mutation_dispatches(self):
        dispatched = {
            "completed_predicates": [],
            "work_order_id": "OTHER-WO",
            "state": "DISPATCHED",
        }
        with self.assertRaisesRegex(ValueError, f"GLOBAL_MUTATION_SLOT_RESERVED_FOR:{P4}"):
            build_plan(self.contracts, {"goal_checkpoint": H0_2}, dispatched)
        with self.assertRaisesRegex(ValueError, f"GLOBAL_MUTATION_SLOT_RESERVED_FOR:{P4}"):
            build_plan(self.contracts, {"goal_checkpoint": "SM0_NONTRIVIAL_FIX", "branch": "feature/sm0-fix"}, dispatched)

    def test_initial_dispatch_requires_director_without_rewriting_historical_evidence(self):
        work_order = read_json(HISTORICAL_WORK_ORDER)
        transition = read_json(HISTORICAL_TRANSITION)
        event_paths = sorted(HISTORICAL_EVENTS.glob("*.json"))[:2]
        events = [read_json(path) for path in event_paths]
        guard = load_guard_context(ROOT, HISTORICAL_EXECUTION)

        reduced = reduce_events(self.bundle, work_order, events, transition, guard)
        self.assertEqual("DISPATCHED", reduced["state"])
        self.assertEqual("DIRECTOR", events[1]["actor"])

        invalid = copy.deepcopy(events)
        invalid[1]["actor"] = "IMPLEMENTER"
        with self.assertRaisesRegex(ContractValidationError, "GUARDED_INITIAL_DISPATCH_DIRECTOR_REQUIRED"):
            reduce_events(self.bundle, work_order, invalid, transition, guard)

    def test_p4_audit_skip_fetch_is_explicitly_non_authorizing(self):
        remote = f"origin/{P4_BRANCH}"
        runner = git("show", f"{remote}:{P4_RUNNER}")
        self.assertIn('"BASE_READY_REFS_NOT_REFRESHED"', runner)
        self.assertIn("refs_fetch_performed = $RefsFetchPerformed", runner)
        self.assertIn("authoritative_for_dispatch = $AuthoritativeForDispatch", runner)
        self.assertIn('$AuthoritativeForDispatch = $Decision -eq "CONTINUE"', runner)
        self.assertNotIn('decision = if ($SkipPostMainProjectControl) { "BASE_READY_PC0_NOT_RUN" } else { "CONTINUE" }', runner)

    def test_registry_pin_and_required_docs_track_current_p4_head(self):
        remote_head = git("rev-parse", "--verify", f"origin/{P4_BRANCH}")
        v0 = self.registry["programs"]["V0"]
        self.assertEqual(remote_head, v0["prebuild_state"]["head_at_refresh_input"])
        for relative in (
            "docs/control/CURRENT_PROJECT_FRONTIERS_RU.md",
            "docs/plans/V0_CRITICAL_PATH_ACCELERATION_PROPOSAL_RU.md",
        ):
            text = (ROOT / relative).read_text(encoding="utf-8")
            self.assertIn(remote_head, text, relative)
            self.assertNotIn("c20310cf804374ab515fd7a363b6471c2b933ac0", text, relative)


if __name__ == "__main__":
    unittest.main()
