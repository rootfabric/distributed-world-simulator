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
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.checkpoint_planner import build_plan
from harness.contracts import ContractBundle, ContractValidationError, read_json
from harness.epoch_validator import validate_epoch
from harness.event_reducer import load_guard_context, reduce_events
from harness.state_builder import _load_reviews, _select_epoch_audit, _validate_event_git_provenance, _validate_semantics, build_state


EXECUTION = ROOT / "config/control/harness/executions/E2026-08-11-H0-0-R1"


class H0ControlHarnessTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bundle = ContractBundle.load(ROOT)
        self.work_order = read_json(EXECUTION / "work-orders/H0-0-WO-001.v1.json")
        self.transition_table = read_json(EXECUTION / "transition-table.v1.json")
        self.events = [read_json(path) for path in sorted((EXECUTION / "events/H0-0-WO-001").glob("*.json"))]
        self.guard_context = load_guard_context(ROOT, EXECUTION)

    def reduce(self, events: list[dict] | None = None, work_order: dict | None = None) -> dict:
        return reduce_events(
            self.bundle,
            work_order or self.work_order,
            events or self.events,
            self.transition_table,
            self.guard_context,
        )

    def test_positive_live_ledger_matches_declared_snapshot(self) -> None:
        reduced = self.reduce()
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
        reduced = self.reduce()
        plan = build_plan(self.bundle.contracts, reduced)
        self.assertEqual("H0_0_SCAFFOLD_READY", plan["selected_checkpoint"])
        self.assertEqual("BLOCKED", plan["c22_dry_run"]["status"])
        self.assertEqual("FORBIDDEN", plan["c22_dry_run"]["branch_creation"])

    def test_negative_snapshot_mismatch_is_hard_error(self) -> None:
        changed = copy.deepcopy(self.work_order)
        changed["state"] = "PLANNED"
        reduced = self.reduce(work_order=changed)
        self.assertFalse(reduced["snapshot_matches_authoritative_state"])

    def test_negative_transition_pair_is_rejected(self) -> None:
        changed = copy.deepcopy(self.events)
        changed[0]["work_state"] = "DISPATCHED"
        with self.assertRaisesRegex(ContractValidationError, "EVENT_TYPE_STATE_PAIR_INVALID"):
            self.reduce(changed)

    def test_replay_requires_contiguous_unique_ledger(self) -> None:
        changed = copy.deepcopy(self.events)
        changed[3]["sequence"] = 99
        with self.assertRaisesRegex(ContractValidationError, "EVENT_SEQUENCE_GAP"):
            self.reduce(changed)

    def test_replay_is_ordered_by_numeric_sequence_not_filename_order(self) -> None:
        changed = list(reversed(copy.deepcopy(self.events)))
        reduced = self.reduce(changed)
        self.assertEqual(self.work_order["state"], reduced["state"])
        self.assertEqual(len(self.events), reduced["last_event_sequence"])

    def test_duplicate_event_id_is_rejected(self) -> None:
        changed = copy.deepcopy(self.events)
        changed[1]["event_id"] = changed[0]["event_id"]
        with self.assertRaisesRegex(ContractValidationError, "EVENT_ID_NOT_UNIQUE"):
            self.reduce(changed)

    def test_duplicate_sequence_is_rejected(self) -> None:
        changed = copy.deepcopy(self.events)
        changed[1]["sequence"] = changed[0]["sequence"]
        with self.assertRaisesRegex(ContractValidationError, "EVENT_SEQUENCE_NOT_UNIQUE"):
            self.reduce(changed)

    def test_zero_sequence_is_rejected_by_schema(self) -> None:
        changed = copy.deepcopy(self.events)
        changed[0]["sequence"] = 0
        with self.assertRaisesRegex(ContractValidationError, "SCHEMA_INVALID"):
            self.reduce(changed)

    def test_cross_work_order_and_branch_events_are_rejected(self) -> None:
        changed = copy.deepcopy(self.events)
        changed[0]["work_order_id"] = "OTHER"
        with self.assertRaisesRegex(ContractValidationError, "EVENT_WORK_ORDER_OR_EPOCH_MISMATCH"):
            self.reduce(changed)
        changed = copy.deepcopy(self.events)
        changed[0]["branch"] = "other/branch"
        with self.assertRaisesRegex(ContractValidationError, "EVENT_BRANCH_MISMATCH"):
            self.reduce(changed)

    def test_illegal_state_jump_and_terminal_continuation_are_rejected(self) -> None:
        changed = copy.deepcopy(self.events[:2])
        changed[1]["event_type"] = "PREDICATE_VERIFIED"
        changed[1]["work_state"] = "VERIFIED"
        with self.assertRaisesRegex(ContractValidationError, "STATE_TRANSITION_INVALID"):
            self.reduce(changed)
        changed = copy.deepcopy(self.events[:2])
        changed[1]["event_type"] = "CANCELLED"
        changed[1]["work_state"] = "CANCELLED"
        continuation = copy.deepcopy(changed[1])
        continuation.update({"event_id": "continued", "sequence": 3, "event_type": "RECOVERY_RESUMED", "work_state": "DISPATCHED"})
        with self.assertRaisesRegex(ContractValidationError, "STATE_TRANSITION_INVALID"):
            self.reduce([*changed, continuation])

    def test_timestamp_regression_and_invalid_sha_are_rejected(self) -> None:
        changed = copy.deepcopy(self.events)
        changed[1]["recorded_at_utc"] = "2000-01-01T00:00:00Z"
        with self.assertRaisesRegex(ContractValidationError, "EVENT_TIMESTAMP_DECREASES"):
            self.reduce(changed)
        changed = copy.deepcopy(self.events)
        changed[0]["head_sha"] = "bad"
        with self.assertRaisesRegex(ContractValidationError, "SCHEMA_INVALID"):
            self.reduce(changed)

    def test_all_redispatch_guards_fail_closed(self) -> None:
        blocked = copy.deepcopy(self.events[:4])
        blocked[3]["evidence_paths"] = []
        with self.assertRaisesRegex(ContractValidationError, "GUARDED_BLOCKED_REDISPATCH_EVIDENCE_MISSING"):
            self.reduce(blocked)
        blocked[3]["evidence_paths"] = ["AGENTS.md"]
        with self.assertRaisesRegex(ContractValidationError, "GUARDED_BLOCKED_REDISPATCH_EVIDENCE_MISSING"):
            self.reduce(blocked)
        arbitrary_blocker = copy.deepcopy(self.events[:4])
        arbitrary_blocker[2]["blocker"] = "PC0_RED_UNRESOLVED"
        with self.assertRaisesRegex(ContractValidationError, "GUARDED_BLOCKED_REDISPATCH_EVIDENCE_MISSING"):
            self.reduce(arbitrary_blocker)
        future_block = copy.deepcopy(self.events[:4])
        blocker = copy.deepcopy(self.events[2])
        blocker.update({"event_id": "future-block", "sequence": 5, "blocker": "UNRELATED_SECURITY_STOP", "recorded_at_utc": "2026-08-11T06:00:00Z"})
        dispatch = copy.deepcopy(self.events[3])
        dispatch.update({"event_id": "future-dispatch", "sequence": 6, "recorded_at_utc": "2026-08-11T06:00:01Z"})
        with self.assertRaisesRegex(ContractValidationError, "GUARDED_BLOCKED_REDISPATCH_EVIDENCE_MISSING"):
            self.reduce([*future_block, blocker, dispatch])

        waiting = copy.deepcopy(self.events[:4])
        waiting[2].update({"event_type": "WAITING_HUMAN", "work_state": "WAITING_HUMAN", "blocker": "DECISION"})
        waiting[3]["evidence_paths"] = []
        with self.assertRaisesRegex(ContractValidationError, "GUARDED_HUMAN_REDISPATCH_RESOLUTION_MISSING"):
            self.reduce(waiting)

        fixing = copy.deepcopy(self.events[:4])
        fixing[2].update({"event_type": "FIX_REQUIRED", "work_state": "FIX_REQUIRED", "blocker": "DEFECT"})
        fixing[3]["evidence_paths"] = ["fake/final-resolution.v1.json"]
        with self.assertRaisesRegex(ContractValidationError, "GUARDED_FIX_REDISPATCH_EVIDENCE_MISSING"):
            self.reduce(fixing)

    def test_premature_recovery_requires_reviewer_or_director_and_blocker(self) -> None:
        changed = copy.deepcopy(self.events[:5])
        changed[2].update({"event_type": "FIX_REQUIRED", "work_state": "FIX_REQUIRED", "blocker": "DEFECT"})
        changed[3].update({"event_type": "DISPATCHED", "work_state": "DISPATCHED", "evidence_paths": []})
        changed[4].update({"event_type": "FIX_REQUIRED", "work_state": "FIX_REQUIRED", "actor": "IMPLEMENTER", "blocker": ""})
        with self.assertRaisesRegex(ContractValidationError, "GUARDED_FIX_REDISPATCH_EVIDENCE_MISSING"):
            self.reduce(changed)

    def test_failed_event_predicate_is_observed_but_not_completed(self) -> None:
        changed = copy.deepcopy(self.events[:3])
        changed[2].update({"event_type": "FIX_REQUIRED", "work_state": "FIX_REQUIRED", "predicate": "CONTROL_DEVELOPMENT_STATUS_WORKS", "blocker": "FAILED"})
        reduced = self.reduce(changed)
        self.assertIn("CONTROL_DEVELOPMENT_STATUS_WORKS", reduced["observed_predicates"])
        self.assertNotIn("CONTROL_DEVELOPMENT_STATUS_WORKS", reduced["completed_predicates"])
        implementation = copy.deepcopy(self.events[:3])
        implementation[2].update({"event_type": "IMPLEMENTATION_COMMITTED", "work_state": "IMPLEMENTED", "predicate": "PC0_NON_RED"})
        implementation[2].pop("command", None)
        implementation[2].pop("exit_code", None)
        reduced = self.reduce(implementation)
        self.assertIn("PC0_NON_RED", reduced["observed_predicates"])
        self.assertNotIn("PC0_NON_RED", reduced["completed_predicates"])

    def test_high_risk_requires_review_and_evidence_map(self) -> None:
        epoch = read_json(EXECUTION / "project-epoch.v1.json")
        for field in ("review_required", "evidence_map_required"):
            changed = copy.deepcopy(self.work_order)
            changed[field] = False
            with self.subTest(field=field), self.assertRaisesRegex(ContractValidationError, "RISK_"):
                _validate_semantics(self.bundle, epoch, changed)

    def test_scope_symlink_escape_is_rejected_when_supported(self) -> None:
        epoch = read_json(EXECUTION / "project-epoch.v1.json")
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as outside:
            root = Path(directory)
            link = root / "escape"
            try:
                os.symlink(outside, link, target_is_directory=True)
            except OSError:
                self.skipTest("Windows symlink creation is unavailable")
            bundle = ContractBundle(root=root, contracts=self.bundle.contracts)
            changed = copy.deepcopy(self.work_order)
            changed["allowed_paths"] = ["escape/**"]
            with self.assertRaisesRegex(ContractValidationError, "SCOPE_PATH_ESCAPES_REPOSITORY"):
                _validate_semantics(bundle, epoch, changed)

    def test_duplicate_json_keys_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "duplicate.json"
            path.write_text('{"state":"BLOCKED","state":"DISPATCHED"}', encoding="utf-8")
            with self.assertRaisesRegex(ContractValidationError, "JSON_DUPLICATE_KEY"):
                read_json(path)

    def test_review_results_fail_closed_on_shape_and_head(self) -> None:
        source = read_json(EXECUTION / "reviews/H0-0-WO-001-PREBUILD-REVIEW-001.v1.json")
        cases = (("reviewed_head_sha", "bad"), ("required_fixes", "not-an-array"), ("review_type", None))
        for field, value in cases:
            with self.subTest(field=field), tempfile.TemporaryDirectory() as directory:
                review_dir = Path(directory) / "reviews"
                review_dir.mkdir()
                changed = copy.deepcopy(source)
                if value is None:
                    changed.pop(field)
                else:
                    changed[field] = value
                (review_dir / "review.json").write_text(json.dumps(changed), encoding="utf-8")
                with self.assertRaises(ContractValidationError):
                    _load_reviews(ROOT, Path(directory), self.work_order)

    def test_event_git_provenance_rejects_worktree_mutation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            subprocess.run(["git", "init", "-b", "main"], cwd=repository, check=True, capture_output=True)
            subprocess.run(["git", "config", "user.email", "h0@example.test"], cwd=repository, check=True)
            subprocess.run(["git", "config", "user.name", "H0"], cwd=repository, check=True)
            subprocess.run(["git", "commit", "--allow-empty", "-m", "base"], cwd=repository, check=True, capture_output=True)
            subject = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repository, check=True, text=True, capture_output=True).stdout.strip()
            event_dir = repository / "events"
            event_dir.mkdir()
            event_path = event_dir / "0001.json"
            event = {"event_id": "E1", "head_sha": subject}
            event_path.write_text(json.dumps(event), encoding="utf-8")
            subprocess.run(["git", "add", "events/0001.json"], cwd=repository, check=True)
            subprocess.run(["git", "commit", "-m", "event"], cwd=repository, check=True, capture_output=True)
            current = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repository, check=True, text=True, capture_output=True).stdout.strip()
            self.assertEqual(40, len(_validate_event_git_provenance(repository, [event_path], [event], current)))
            event_path.write_text(json.dumps({**event, "changed": True}), encoding="utf-8")
            with self.assertRaisesRegex(ContractValidationError, "EVENT_WORKTREE_MUTATION_DETECTED"):
                _validate_event_git_provenance(repository, [event_path], [event], current)
            subprocess.run(["git", "add", "events/0001.json"], cwd=repository, check=True)
            subprocess.run(["git", "commit", "-m", "illegal mutation"], cwd=repository, check=True, capture_output=True)
            mutated_head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repository, check=True, text=True, capture_output=True).stdout.strip()
            with self.assertRaisesRegex(ContractValidationError, "EVENT_IMMUTABILITY_NOT_PROVEN"):
                _validate_event_git_provenance(repository, [event_path], [{**event, "changed": True}], mutated_head)
            with self.assertRaisesRegex(ContractValidationError, "EVENT_SUBJECT_HEAD_UNREACHABLE"):
                fresh_repository = Path(directory) / "fresh"
                fresh_repository.mkdir()
                subprocess.run(["git", "init", "-b", "main"], cwd=fresh_repository, check=True, capture_output=True)
                subprocess.run(["git", "config", "user.email", "h0@example.test"], cwd=fresh_repository, check=True)
                subprocess.run(["git", "config", "user.name", "H0"], cwd=fresh_repository, check=True)
                unreachable_path = fresh_repository / "0001.json"
                unreachable = {"event_id": "E2", "head_sha": "0" * 40}
                unreachable_path.write_text(json.dumps(unreachable), encoding="utf-8")
                subprocess.run(["git", "add", "0001.json"], cwd=fresh_repository, check=True)
                subprocess.run(["git", "commit", "-m", "event"], cwd=fresh_repository, check=True, capture_output=True)
                fresh_head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=fresh_repository, check=True, text=True, capture_output=True).stdout.strip()
                _validate_event_git_provenance(fresh_repository, [unreachable_path], [unreachable], fresh_head)

    def test_event_git_provenance_rejects_committed_deletion(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            subprocess.run(["git", "init", "-b", "main"], cwd=repository, check=True, capture_output=True)
            subprocess.run(["git", "config", "user.email", "h0@example.test"], cwd=repository, check=True)
            subprocess.run(["git", "config", "user.name", "H0"], cwd=repository, check=True)
            subprocess.run(["git", "commit", "--allow-empty", "-m", "base"], cwd=repository, check=True, capture_output=True)
            subject = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repository, check=True, text=True, capture_output=True).stdout.strip()
            event_dir = repository / "events"
            event_dir.mkdir()
            first = event_dir / "0001.json"
            second = event_dir / "0002.json"
            first_event = {"event_id": "E1", "head_sha": subject}
            first.write_text(json.dumps(first_event), encoding="utf-8")
            second.write_text(json.dumps({"event_id": "E2", "head_sha": subject}), encoding="utf-8")
            subprocess.run(["git", "add", "events"], cwd=repository, check=True)
            subprocess.run(["git", "commit", "-m", "events"], cwd=repository, check=True, capture_output=True)
            subprocess.run(["git", "rm", "events/0002.json"], cwd=repository, check=True, capture_output=True)
            subprocess.run(["git", "commit", "-m", "illegal deletion"], cwd=repository, check=True, capture_output=True)
            current = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repository, check=True, text=True, capture_output=True).stdout.strip()
            with self.assertRaisesRegex(ContractValidationError, "EVENT_LEDGER_DELETION_DETECTED"):
                _validate_event_git_provenance(repository, [first], [first_event], current)

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

    def test_wrong_pinned_dependency_version_fails_closed(self) -> None:
        with mock.patch("harness.contracts.importlib.metadata.version", return_value="4.21.0"):
            with self.assertRaisesRegex(ContractValidationError, "PINNED_DEPENDENCY_VERSION_REQUIRED"):
                self.bundle.validate("event_schema", self.events[0], "event")
        with mock.patch("harness.contracts.importlib.metadata.version", side_effect=__import__("importlib").metadata.PackageNotFoundError("jsonschema")):
            with self.assertRaisesRegex(ContractValidationError, "PINNED_DEPENDENCY_MISSING"):
                self.bundle.validate("event_schema", self.events[0], "event")

    def test_unreferenced_epoch_audit_never_authorizes_continuation(self) -> None:
        audit_path = "config/control/harness/executions/E/audits/audit.json"
        audit = {"schema": "distributed_world_simulator.harness_epoch_audit.v1", "base_sha": "1" * 40, "main_sha": "2" * 40, "decision": "CONTINUE", "pc0": "NON_RED", "directional_pc0": "NON_RED"}
        context = {"documents": {audit_path: audit}}
        self.assertIsNone(_select_epoch_audit(context, []))
        incomplete_event = {"event_type": "AUDIT_COMPLETED", "work_state": "AUDITED", "exit_code": 0, "evidence_paths": [audit_path]}
        self.assertIsNone(_select_epoch_audit(context, [incomplete_event]))
        complete_event = {**incomplete_event, "command": "CONTROL_PROJECT.ps1"}
        self.assertEqual(audit, _select_epoch_audit(context, [complete_event]))

    def test_review_evidence_and_human_attention_contracts_load(self) -> None:
        state = build_state(ROOT, EXECUTION)
        self.assertEqual("PASS", state["review"]["pre_build_state"])
        self.assertIn(state["review"]["post_build_state"], {"FAIL", "STALE"})
        self.assertEqual("PENDING_POST_BUILD_REVIEW", state["review"]["state"])
        self.assertTrue(state["checkpoint_proposal_blocked"])
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
        unknown = subprocess.run([shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(ROOT / "CONTROL_DEVELOPMENT.ps1"), "-Unknown"], cwd=ROOT, text=True, encoding="utf-8", capture_output=True, check=False)
        self.assertEqual(2, unknown.returncode)
        self.assertEqual("INVALID_INVOCATION", json.loads(unknown.stdout.splitlines()[-1])["error"]["code"])

    def test_output_envelope_matches_published_schema(self) -> None:
        from jsonschema import Draft202012Validator
        schema = read_json(ROOT / "validation/harness/control-development-output.schema.v1.json")
        shell = shutil.which("powershell") or shutil.which("pwsh")
        completed = subprocess.run([shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(ROOT / "CONTROL_DEVELOPMENT.ps1"), "-Status"], cwd=ROOT, text=True, encoding="utf-8", capture_output=True, check=False)
        envelope = json.loads(completed.stdout.splitlines()[-1])
        self.assertEqual([], list(Draft202012Validator(schema).iter_errors(envelope)))
        minimal = {"schema": "distributed_world_simulator.control_development_output.v1", "command": "STATUS", "ok": True}
        self.assertTrue(list(Draft202012Validator(schema).iter_errors(minimal)))
        with_error = copy.deepcopy(envelope)
        with_error["error"] = {"code": "INTERNAL_ERROR", "detail": "must not coexist with success"}
        self.assertTrue(list(Draft202012Validator(schema).iter_errors(with_error)))
        for switch, section in (("-Plan", "plan"), ("-Resume", "resume")):
            completed = subprocess.run([shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(ROOT / "CONTROL_DEVELOPMENT.ps1"), switch], cwd=ROOT, text=True, encoding="utf-8", capture_output=True, check=False)
            candidate = json.loads(completed.stdout.splitlines()[-1])
            candidate.pop(section)
            self.assertTrue(list(Draft202012Validator(schema).iter_errors(candidate)))
            empty_section = json.loads(completed.stdout.splitlines()[-1])
            empty_section[section] = {}
            self.assertTrue(list(Draft202012Validator(schema).iter_errors(empty_section)))
        status_with_sections = copy.deepcopy(envelope)
        status_with_sections.update({"plan": {}, "resume": {}})
        self.assertTrue(list(Draft202012Validator(schema).iter_errors(status_with_sections)))
        error_with_plan = {
            "schema": "distributed_world_simulator.control_development_output.v1",
            "command": "PLAN",
            "ok": False,
            "error": {"code": "INVALID_INVOCATION", "detail": "bad"},
            "exit_codes": envelope["exit_codes"],
            "plan": {},
        }
        self.assertTrue(list(Draft202012Validator(schema).iter_errors(error_with_plan)))

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
            self.assertEqual("EXACT_BASE", validate_epoch(repository, epoch, "main", None)["status"])
            subprocess.run(["git", "commit", "--allow-empty", "-m", "advance"], cwd=repository, check=True, capture_output=True)
            main = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repository, check=True, text=True, capture_output=True).stdout.strip()
            self.assertEqual("MAIN_MOVED_REVIEW_REQUIRED", validate_epoch(repository, epoch, "main", None)["status"])
            wrong_audit = {
                "schema": "distributed_world_simulator.harness_epoch_audit.v1",
                "base_sha": base,
                "main_sha": "0" * 40,
                "decision": "CONTINUE",
                "pc0": "NON_RED",
                "directional_pc0": "NON_RED",
            }
            self.assertEqual("MAIN_MOVED_REVIEW_REQUIRED", validate_epoch(repository, epoch, "main", wrong_audit)["status"])
            exact_audit = {**wrong_audit, "main_sha": main}
            self.assertEqual("MAIN_MOVED_AUDIT_CONTINUE", validate_epoch(repository, epoch, "main", exact_audit)["status"])
            epoch["status"] = "INVALIDATED"
            self.assertEqual("EPOCH_INVALIDATED", validate_epoch(repository, epoch, "main", exact_audit)["status"])

    def test_powershell_non_root_cwd_returns_single_json_envelope(self) -> None:
        shell = shutil.which("powershell") or shutil.which("pwsh")
        self.assertIsNotNone(shell)
        completed = subprocess.run([shell, "-NoProfile", "-File", str(ROOT / "CONTROL_DEVELOPMENT.ps1"), "-Resume"], cwd=ROOT.parent, text=True, capture_output=True, check=False)
        self.assertEqual(0, completed.returncode, completed.stderr)
        envelope = json.loads(completed.stdout.splitlines()[-1])
        self.assertEqual("RESUME", envelope["command"])
        self.assertTrue(envelope["ok"])
        self.assertIn("[CONTROL][RESUME]", completed.stdout)

    def test_clean_clone_public_snapshot_mismatch_exits_five(self) -> None:
        dirty = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, text=True, capture_output=True, check=True).stdout.strip()
        if dirty:
            self.skipTest("clean-HEAD recovery drill runs after the repair unit is committed")
        shell = shutil.which("powershell") or shutil.which("pwsh")
        with tempfile.TemporaryDirectory() as directory:
            clone = Path(directory) / "verification clone"
            completed = subprocess.run(["git", "clone", "--no-hardlinks", "--branch", "control/h0-closed-loop-development", str(ROOT), str(clone)], text=True, capture_output=True, check=False)
            self.assertEqual(0, completed.returncode, completed.stderr)
            canonical_main = subprocess.run(["git", "rev-parse", "origin/main"], cwd=ROOT, text=True, capture_output=True, check=True).stdout.strip()
            subprocess.run(["git", "update-ref", "refs/remotes/origin/main", canonical_main], cwd=clone, check=True)
            work_order_path = clone / "config/control/harness/executions/E2026-08-11-H0-0-R1/work-orders/H0-0-WO-001.v1.json"
            work_order = read_json(work_order_path)
            work_order["state"] = "PLANNED"
            work_order_path.write_text(json.dumps(work_order), encoding="utf-8")
            result = subprocess.run([shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(clone / "CONTROL_DEVELOPMENT.ps1"), "-Resume"], cwd=clone.parent, text=True, encoding="utf-8", capture_output=True, check=False)
            self.assertEqual(5, result.returncode, result.stderr)
            envelope = json.loads(result.stdout.splitlines()[-1])
            self.assertEqual("EXECUTION_STATE_INVALID", envelope["error"]["code"])
            self.assertIn("WORK_ORDER_SNAPSHOT_STATE_MISMATCH", envelope["error"]["detail"])


if __name__ == "__main__":
    unittest.main()
