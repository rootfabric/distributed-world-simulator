from __future__ import annotations

import copy
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.checkpoint_planner import build_plan
from harness.contracts import ContractBundle, ContractValidationError, read_json
from harness.epoch_validator import validate_epoch
from harness.event_reducer import reduce_events
from harness.state_builder import build_state


EXECUTION = ROOT / "config/control/harness/executions/E2026-08-11-H0-0-R1"


class H0ControlHarnessTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bundle = ContractBundle.load(ROOT)
        self.work_order = read_json(EXECUTION / "work-orders/H0-0-WO-001.v1.json")
        self.transition_table = read_json(EXECUTION / "transition-table.v1.json")
        self.events = [read_json(path) for path in sorted((EXECUTION / "events/H0-0-WO-001").glob("*.json"))]

    def test_positive_live_ledger_matches_declared_snapshot(self) -> None:
        reduced = reduce_events(self.bundle, self.work_order, self.events, self.transition_table)
        self.assertEqual(self.work_order["state"], reduced["state"])
        self.assertTrue(reduced["snapshot_matches_authoritative_state"])
        state = build_state(ROOT, EXECUTION)
        self.assertEqual("GIT_ONLY_WORKER_DATA", state["source"])
        self.assertEqual(self.work_order["state"], state["reduced_work_order"]["state"])
        heads = state["repository"]
        self.assertEqual(40, len(heads["event_subject_head_sha"]))
        self.assertEqual(40, len(heads["event_ledger_head_sha"]))
        self.assertEqual(40, len(heads["current_branch_head_sha"]))

    def test_plan_keeps_c22_dry_run_blocked(self) -> None:
        reduced = reduce_events(self.bundle, self.work_order, self.events, self.transition_table)
        plan = build_plan(self.bundle.contracts, reduced)
        self.assertEqual("H0_0_SCAFFOLD_READY", plan["selected_checkpoint"])
        self.assertEqual("BLOCKED", plan["c22_dry_run"]["status"])
        self.assertEqual("FORBIDDEN", plan["c22_dry_run"]["branch_creation"])

    def test_negative_snapshot_mismatch_is_hard_error(self) -> None:
        changed = copy.deepcopy(self.work_order)
        changed["state"] = "PLANNED"
        reduced = reduce_events(self.bundle, changed, self.events, self.transition_table)
        self.assertFalse(reduced["snapshot_matches_authoritative_state"])

    def test_negative_transition_pair_is_rejected(self) -> None:
        changed = copy.deepcopy(self.events)
        changed[0]["work_state"] = "DISPATCHED"
        with self.assertRaisesRegex(ContractValidationError, "EVENT_TYPE_STATE_PAIR_INVALID"):
            reduce_events(self.bundle, self.work_order, changed, self.transition_table)

    def test_replay_requires_contiguous_unique_ledger(self) -> None:
        changed = copy.deepcopy(self.events)
        changed[3]["sequence"] = 99
        with self.assertRaisesRegex(ContractValidationError, "EVENT_SEQUENCE_GAP"):
            reduce_events(self.bundle, self.work_order, changed, self.transition_table)

    def test_replay_is_ordered_by_numeric_sequence_not_filename_order(self) -> None:
        changed = list(reversed(copy.deepcopy(self.events)))
        reduced = reduce_events(self.bundle, self.work_order, changed, self.transition_table)
        self.assertEqual(self.work_order["state"], reduced["state"])
        self.assertEqual(len(self.events), reduced["last_event_sequence"])

    def test_duplicate_event_id_is_rejected(self) -> None:
        changed = copy.deepcopy(self.events)
        changed[1]["event_id"] = changed[0]["event_id"]
        with self.assertRaisesRegex(ContractValidationError, "EVENT_ID_NOT_UNIQUE"):
            reduce_events(self.bundle, self.work_order, changed, self.transition_table)

    def test_duplicate_sequence_is_rejected(self) -> None:
        changed = copy.deepcopy(self.events)
        changed[1]["sequence"] = changed[0]["sequence"]
        with self.assertRaisesRegex(ContractValidationError, "EVENT_SEQUENCE_NOT_UNIQUE"):
            reduce_events(self.bundle, self.work_order, changed, self.transition_table)

    def test_zero_sequence_is_rejected_by_schema(self) -> None:
        changed = copy.deepcopy(self.events)
        changed[0]["sequence"] = 0
        with self.assertRaisesRegex(ContractValidationError, "SCHEMA_INVALID"):
            reduce_events(self.bundle, self.work_order, changed, self.transition_table)

    def test_cross_work_order_and_branch_events_are_rejected(self) -> None:
        changed = copy.deepcopy(self.events)
        changed[0]["work_order_id"] = "OTHER"
        with self.assertRaisesRegex(ContractValidationError, "EVENT_WORK_ORDER_OR_EPOCH_MISMATCH"):
            reduce_events(self.bundle, self.work_order, changed, self.transition_table)
        changed = copy.deepcopy(self.events)
        changed[0]["branch"] = "other/branch"
        with self.assertRaisesRegex(ContractValidationError, "EVENT_BRANCH_MISMATCH"):
            reduce_events(self.bundle, self.work_order, changed, self.transition_table)

    def test_illegal_state_jump_and_terminal_continuation_are_rejected(self) -> None:
        changed = copy.deepcopy(self.events[:2])
        changed[1]["event_type"] = "PREDICATE_VERIFIED"
        changed[1]["work_state"] = "VERIFIED"
        with self.assertRaisesRegex(ContractValidationError, "STATE_TRANSITION_INVALID"):
            reduce_events(self.bundle, self.work_order, changed, self.transition_table)
        changed = copy.deepcopy(self.events[:2])
        changed[1]["event_type"] = "CANCELLED"
        changed[1]["work_state"] = "CANCELLED"
        continuation = copy.deepcopy(changed[1])
        continuation.update({"event_id": "continued", "sequence": 3, "event_type": "RECOVERY_RESUMED", "work_state": "DISPATCHED"})
        with self.assertRaisesRegex(ContractValidationError, "STATE_TRANSITION_INVALID"):
            reduce_events(self.bundle, self.work_order, [*changed, continuation], self.transition_table)

    def test_timestamp_regression_and_invalid_sha_are_rejected(self) -> None:
        changed = copy.deepcopy(self.events)
        changed[1]["recorded_at_utc"] = "2000-01-01T00:00:00Z"
        with self.assertRaisesRegex(ContractValidationError, "EVENT_TIMESTAMP_DECREASES"):
            reduce_events(self.bundle, self.work_order, changed, self.transition_table)
        changed = copy.deepcopy(self.events)
        changed[0]["head_sha"] = "bad"
        with self.assertRaisesRegex(ContractValidationError, "SCHEMA_INVALID"):
            reduce_events(self.bundle, self.work_order, changed, self.transition_table)

    def test_contract_schema_negatives_are_machine_identified(self) -> None:
        cases = [
            ("work_order_schema", self.work_order, "state", "UNKNOWN"),
            ("event_schema", self.events[0], "schema", "wrong"),
        ]
        for schema_name, original, field, value in cases:
            with self.subTest(schema=schema_name, field=field):
                changed = copy.deepcopy(original)
                changed[field] = value
                with self.assertRaisesRegex(ContractValidationError, f"SCHEMA_INVALID:negative-{field}"):
                    self.bundle.validate(schema_name, changed, f"negative-{field}")

    def test_review_evidence_and_human_attention_contracts_load(self) -> None:
        state = build_state(ROOT, EXECUTION)
        self.assertEqual("PASS", state["review"]["pre_build_state"])
        self.assertEqual("MISSING", state["review"]["post_build_state"])
        self.assertEqual("PENDING_POST_BUILD_REVIEW", state["review"]["state"])
        human_schema = self.bundle.contracts["human_attention_schema"]
        candidate = {
            "schema": "distributed_world_simulator.harness_human_attention.v1",
            "decision_id": "D1", "program": "HARNESS", "checkpoint": "H0_0_SCAFFOLD_READY",
            "risk_class": "HIGH", "reason": "test", "decision_required": "choose",
            "options": ["A", "B"], "blast_radius": [], "blocking": True, "status": "OPEN",
        }
        self.bundle.validate("human_attention_schema", candidate, "human")
        candidate["options"] = ["A"]
        with self.assertRaisesRegex(ContractValidationError, "SCHEMA_INVALID:human"):
            self.bundle.validate("human_attention_schema", candidate, "human")

    def test_status_plan_resume_and_invalid_invocation_contract(self) -> None:
        shell = shutil.which("powershell") or shutil.which("pwsh")
        self.assertIsNotNone(shell)
        for switch, command in (("-Status", "STATUS"), ("-Plan", "PLAN"), ("-Resume", "RESUME")):
            with self.subTest(command=command):
                completed = subprocess.run([shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(ROOT / "CONTROL_DEVELOPMENT.ps1"), switch], cwd=ROOT, text=True, encoding="utf-8", capture_output=True, check=False)
                self.assertEqual(0, completed.returncode, completed.stderr)
                envelope = json.loads(completed.stdout.splitlines()[-1])
                self.assertEqual(command, envelope["command"])
                self.assertFalse(envelope["runtime_authorized"])
                self.assertEqual("H0_0_SCAFFOLD_READY", envelope["next"]["checkpoint"])
        invalid = subprocess.run([shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(ROOT / "CONTROL_DEVELOPMENT.ps1"), "-Status", "-Plan"], cwd=ROOT, text=True, encoding="utf-8", capture_output=True, check=False)
        self.assertEqual(2, invalid.returncode)
        self.assertEqual("INVALID_INVOCATION", json.loads(invalid.stdout.splitlines()[-1])["error"]["code"])
        execute = subprocess.run([shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(ROOT / "CONTROL_DEVELOPMENT.ps1"), "-Execute"], cwd=ROOT, text=True, encoding="utf-8", capture_output=True, check=False)
        self.assertEqual(2, execute.returncode)

    def test_output_envelope_matches_published_schema(self) -> None:
        from jsonschema import Draft202012Validator
        schema = read_json(ROOT / "validation/harness/control-development-output.schema.v1.json")
        shell = shutil.which("powershell") or shutil.which("pwsh")
        completed = subprocess.run([shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(ROOT / "CONTROL_DEVELOPMENT.ps1"), "-Status"], cwd=ROOT, text=True, encoding="utf-8", capture_output=True, check=False)
        envelope = json.loads(completed.stdout.splitlines()[-1])
        self.assertEqual([], list(Draft202012Validator(schema).iter_errors(envelope)))

    def test_plan_lists_required_unsatisfied_predicates_and_c22_gate(self) -> None:
        state = build_state(ROOT, EXECUTION)
        plan = build_plan(self.bundle.contracts, state["reduced_work_order"])
        required = self.bundle.contracts["checkpoint_catalog"]["checkpoints"]["H0_0_SCAFFOLD_READY"]["required_predicates"]
        self.assertEqual(required, plan["unsatisfied_predicates"])
        self.assertEqual("H0_0_SCAFFOLD_READY_REQUIRED", plan["c22_dry_run"]["reason"])
        self.assertEqual(0, plan["autonomous_runtime_workers"])

    def test_epoch_exact_moved_and_invalidated(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            for args in (("init", "-b", "main"), ("config", "user.email", "h0@example.test"), ("config", "user.name", "H0"), ("commit", "--allow-empty", "-m", "base")):
                subprocess.run(["git", *args], cwd=repository, check=True, capture_output=True)
            base = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repository, check=True, text=True, capture_output=True).stdout.strip()
            epoch = {"base_sha": base, "status": "ACTIVE"}
            self.assertEqual("EXACT_BASE", validate_epoch(repository, epoch, "main", False)["status"])
            subprocess.run(["git", "commit", "--allow-empty", "-m", "advance"], cwd=repository, check=True, capture_output=True)
            self.assertEqual("MAIN_MOVED_REVIEW_REQUIRED", validate_epoch(repository, epoch, "main", False)["status"])
            self.assertEqual("MAIN_MOVED_AUDIT_CONTINUE", validate_epoch(repository, epoch, "main", True)["status"])
            epoch["status"] = "INVALIDATED"
            self.assertEqual("EPOCH_INVALIDATED", validate_epoch(repository, epoch, "main", True)["status"])

    def test_powershell_non_root_cwd_returns_single_json_envelope(self) -> None:
        shell = shutil.which("powershell") or shutil.which("pwsh")
        self.assertIsNotNone(shell)
        completed = subprocess.run([shell, "-NoProfile", "-File", str(ROOT / "CONTROL_DEVELOPMENT.ps1"), "-Resume"], cwd=ROOT.parent, text=True, capture_output=True, check=False)
        self.assertEqual(0, completed.returncode, completed.stderr)
        envelope = json.loads(completed.stdout.splitlines()[-1])
        self.assertEqual("RESUME", envelope["command"])
        self.assertTrue(envelope["ok"])
        self.assertIn("[CONTROL][RESUME]", completed.stdout)


if __name__ == "__main__":
    unittest.main()
