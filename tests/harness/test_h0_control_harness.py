from __future__ import annotations

import copy
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from contextlib import contextmanager
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.checkpoint_planner import build_plan
from harness.contracts import ContractBundle, ContractValidationError, read_json
from harness.epoch_validator import validate_epoch
from harness.event_reducer import load_guard_context, reduce_events
from harness.state_builder import (
    _git_implementation_head,
    _load_evidence_maps,
    _load_reviews,
    _select_epoch_audit,
    _validate_event_git_provenance,
    _validate_semantics,
    build_state,
)


ACTIVE_EXECUTION = ROOT / "config/control/harness/executions/E2026-08-11-H0-0-R2"
ACTIVE_WORK_ORDER_ID = "H0-0-R2-WO-001"
ACTIVE_BRANCH = "control/h0-closed-loop-development-r2"
EPOCH_BASE_SHA = "40c117bb16a635b03acfbaa7d9fe18b74245c989"


class H0ControlHarnessTests(unittest.TestCase):
    """Phase-independent H0.0 R2 acceptance and authorization-isolation tests."""

    def setUp(self) -> None:
        self.bundle = ContractBundle.load(ROOT)
        self.work_order = read_json(
            ACTIVE_EXECUTION / f"work-orders/{ACTIVE_WORK_ORDER_ID}.v1.json"
        )
        self.transition_table = read_json(ACTIVE_EXECUTION / "transition-table.v1.json")
        self.events = [
            read_json(path)
            for path in sorted(
                (ACTIVE_EXECUTION / f"events/{ACTIVE_WORK_ORDER_ID}").glob("*.json")
            )
        ]
        self.guard_context = load_guard_context(ROOT, ACTIVE_EXECUTION)

    def reduce(self, events=None, work_order=None):
        return reduce_events(
            self.bundle,
            work_order or self.work_order,
            events or self.events,
            self.transition_table,
            self.guard_context,
        )

    @contextmanager
    def active_documents(self, documents):
        paths = []
        try:
            for relative, document in documents.items():
                path = ACTIVE_EXECUTION / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                self.assertFalse(path.exists(), relative)
                path.write_text(json.dumps(document), encoding="utf-8")
                paths.append(path)
            yield
        finally:
            for path in paths:
                path.unlink(missing_ok=True)

    def historical_evidence_map(self):
        return {
            "schema": "distributed_world_simulator.harness_evidence_map.v1",
            "work_order_id": "HISTORICAL-H0-WO",
            "program": "HARNESS",
            "checkpoint": "H0_0_SCAFFOLD_READY",
            "risk_class": "HIGH",
            "evidence_head_sha": EPOCH_BASE_SHA,
            "intent": "Synthetic historical PASS fixture used only to prove isolation.",
            "root_cause_or_reason": "Historical evidence cannot authorize active R2.",
            "changed_surfaces": [],
            "canonical_owner": "MAIN/HARNESS",
            "entry_points": [],
            "callers": [],
            "callees": [],
            "sibling_surfaces_checked": [],
            "canonical_truth_changed": False,
            "architecture_ownership_changed": False,
            "focused_validation": "PASS",
            "full_regression": "NOT_REQUIRED",
            "pc0": "NON_RED",
            "directional_pc0": "NON_RED",
            "remaining_risks": [],
            "required_fixes": [],
            "rank_up_moves": [],
            "evidence_gaps": [],
            "review_verdict": "PASS",
        }

    def historical_review(self):
        return {
            "schema": "distributed_world_simulator.harness_review_result.v1",
            "review_id": "HISTORICAL-H0-REVIEW",
            "review_type": "POST_BUILD_EXACT_HEAD_REVIEW",
            "work_order_id": "HISTORICAL-H0-WO",
            "risk_class": "HIGH",
            "reviewed_head_sha": EPOCH_BASE_SHA,
            "reviewer": "INDEPENDENT_HISTORICAL_FIXTURE",
            "verdict": "PASS",
            "reviewed_at_utc": "2026-08-11T00:00:00Z",
            "required_fixes": [],
            "rank_up_moves": [],
            "evidence_gaps": [],
            "risk_assessment": "Synthetic historical PASS fixture only.",
        }

    def active_evidence_map(self, head_sha, **updates):
        value = self.historical_evidence_map()
        value.update(
            {
                "work_order_id": ACTIVE_WORK_ORDER_ID,
                "program": "HARNESS",
                "checkpoint": "H0_0_SCAFFOLD_READY",
                "risk_class": "HIGH",
                "evidence_head_sha": head_sha,
                "intent": "Active R2 test Evidence Map",
                **updates,
            }
        )
        return value

    def active_review(self, head_sha, **updates):
        value = self.historical_review()
        value.update(
            {
                "review_id": "H0-0-R2-WO-001-TEST-POSTBUILD-REVIEW",
                "work_order_id": ACTIVE_WORK_ORDER_ID,
                "risk_class": "HIGH",
                "reviewed_head_sha": head_sha,
                "reviewer": "INDEPENDENT_R2_TEST_REVIEWER",
                **updates,
            }
        )
        return value

    def test_active_ledger_matches_whatever_phase_is_declared(self):
        reduced = self.reduce()
        self.assertEqual(self.work_order["state"], reduced["state"])
        self.assertEqual(len(self.events), reduced["last_event_sequence"])
        self.assertTrue(reduced["snapshot_matches_authoritative_state"])
        self.assertIn("PC0_NON_RED", reduced["completed_predicates"])
        state = build_state(ROOT, ACTIVE_EXECUTION)
        self.assertEqual(ACTIVE_WORK_ORDER_ID, state["active_work_order"]["work_order_id"])
        self.assertEqual(ACTIVE_BRANCH, state["active_work_order"]["branch"])
        self.assertFalse(state["runtime_authorized"])
        if reduced["state"] == "FIX_REQUIRED":
            self.assertIsNotNone(state["repair"]["map"])
            self.assertTrue(state["continuation_blocked"])

    def test_historical_pass_fixtures_validate_but_do_not_authorize_r2(self):
        with tempfile.TemporaryDirectory() as directory:
            execution = Path(directory)
            evidence_dir = execution / "evidence"
            review_dir = execution / "reviews"
            evidence_dir.mkdir()
            review_dir.mkdir()
            (evidence_dir / "historical.json").write_text(
                json.dumps(self.historical_evidence_map()), encoding="utf-8"
            )
            (review_dir / "historical.json").write_text(
                json.dumps(self.historical_review()), encoding="utf-8"
            )
            self.assertEqual(
                [],
                _load_evidence_maps(self.bundle, evidence_dir, ACTIVE_WORK_ORDER_ID),
            )
            self.assertEqual([], _load_reviews(ROOT, execution, self.work_order))
        live = build_state(ROOT, ACTIVE_EXECUTION)
        self.assertEqual([], live["review"]["evidence_maps"])
        self.assertEqual([], live["review"]["reviews"])

    def test_malformed_historical_claim_fails_before_partition(self):
        with tempfile.TemporaryDirectory() as directory:
            execution = Path(directory)
            evidence_dir = execution / "evidence"
            review_dir = execution / "reviews"
            evidence_dir.mkdir()
            review_dir.mkdir()
            bad_map = self.historical_evidence_map()
            bad_map.pop("intent")
            (evidence_dir / "bad.json").write_text(json.dumps(bad_map), encoding="utf-8")
            with self.assertRaisesRegex(ContractValidationError, "SCHEMA_INVALID:evidence"):
                _load_evidence_maps(self.bundle, evidence_dir, ACTIVE_WORK_ORDER_ID)
            bad_review = self.historical_review()
            bad_review.pop("risk_assessment")
            (review_dir / "bad.json").write_text(
                json.dumps(bad_review), encoding="utf-8"
            )
            with self.assertRaisesRegex(ContractValidationError, "REVIEW_RESULT_INVALID"):
                _load_reviews(ROOT, execution, self.work_order)

    def test_implementation_head_uses_selected_epoch_and_ignores_ledger(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            subprocess.run(["git", "init", "-b", "main"], cwd=repo, check=True, capture_output=True)
            subprocess.run(["git", "config", "user.email", "h0@example.test"], cwd=repo, check=True)
            subprocess.run(["git", "config", "user.name", "H0"], cwd=repo, check=True)
            execution = repo / "config/control/harness/executions/E-FRESH-R9"
            transition = execution / "transition-table.v1.json"
            transition.parent.mkdir(parents=True)
            transition.write_text('{"version":1}', encoding="utf-8")
            module = repo / "scripts/harness/module.py"
            module.parent.mkdir(parents=True)
            module.write_text("VALUE = 1\n", encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-m", "implementation"], cwd=repo, check=True, capture_output=True)
            implementation = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=repo, check=True, text=True, capture_output=True
            ).stdout.strip()
            self.assertEqual(implementation, _git_implementation_head(repo, execution))
            event = execution / "events/W/0001.json"
            event.parent.mkdir(parents=True)
            event.write_text("{}", encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-m", "ledger"], cwd=repo, check=True, capture_output=True)
            self.assertEqual(implementation, _git_implementation_head(repo, execution))
            transition.write_text('{"version":2}', encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-m", "transition"], cwd=repo, check=True, capture_output=True)
            latest = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=repo, check=True, text=True, capture_output=True
            ).stdout.strip()
            self.assertEqual(latest, _git_implementation_head(repo, execution))

    def test_implementation_head_rejects_execution_escape(self):
        with tempfile.TemporaryDirectory() as directory, tempfile.TemporaryDirectory() as outside:
            with self.assertRaisesRegex(
                ContractValidationError, "EXECUTION_PATH_ESCAPES_REPOSITORY"
            ):
                _git_implementation_head(Path(directory), Path(outside))

    def test_plan_keeps_c22_blocked(self):
        state = build_state(ROOT, ACTIVE_EXECUTION)
        plan = build_plan(self.bundle.contracts, state["reduced_work_order"])
        self.assertEqual("H0_0_SCAFFOLD_READY", plan["selected_checkpoint"])
        self.assertEqual("BLOCKED", plan["c22_dry_run"]["status"])
        self.assertEqual("FORBIDDEN", plan["c22_dry_run"]["branch_creation"])
        self.assertEqual(0, plan["autonomous_runtime_workers"])

    def test_reducer_rejects_sequence_identity_and_branch_corruption(self):
        changed = copy.deepcopy(self.events)
        changed[1]["sequence"] = 99
        with self.assertRaisesRegex(ContractValidationError, "EVENT_SEQUENCE"):
            self.reduce(changed)
        changed = copy.deepcopy(self.events)
        changed[0]["work_order_id"] = "OTHER"
        with self.assertRaisesRegex(
            ContractValidationError, "EVENT_WORK_ORDER_OR_EPOCH_MISMATCH"
        ):
            self.reduce(changed)
        changed = copy.deepcopy(self.events)
        changed[0]["branch"] = "other/branch"
        with self.assertRaisesRegex(ContractValidationError, "EVENT_BRANCH_MISMATCH"):
            self.reduce(changed)

    def test_guarded_blocked_redispatch_requires_resolution(self):
        base = copy.deepcopy(self.events[:2])
        blocked = copy.deepcopy(base[-1])
        blocked.update(
            {
                "event_id": "SYNTHETIC-BLOCKED",
                "sequence": 3,
                "event_type": "BLOCKED",
                "work_state": "BLOCKED",
                "recorded_at_utc": "2026-08-11T09:41:00Z",
                "actor": "VERIFIER",
                "blocker": "SYNTHETIC_BLOCKER",
                "predicate": "SYNTHETIC_BLOCK",
                "command": "synthetic blocker",
                "exit_code": 1,
                "evidence_paths": ["tests/harness/test_h0_control_harness.py"],
            }
        )
        redispatch = copy.deepcopy(blocked)
        redispatch.update(
            {
                "event_id": "SYNTHETIC-REDISPATCH",
                "sequence": 4,
                "event_type": "DISPATCHED",
                "work_state": "DISPATCHED",
                "recorded_at_utc": "2026-08-11T09:42:00Z",
                "actor": "DIRECTOR",
                "blocker": "",
                "predicate": "SYNTHETIC_REDISPATCH",
                "command": "redispatch without resolution",
                "exit_code": 0,
                "evidence_paths": [],
            }
        )
        with self.assertRaisesRegex(
            ContractValidationError, "GUARDED_BLOCKED_REDISPATCH_EVIDENCE_MISSING"
        ):
            self.reduce([*base, blocked, redispatch])

    def test_high_risk_requires_review_and_evidence(self):
        epoch = read_json(ACTIVE_EXECUTION / "project-epoch.v1.json")
        for field in ("review_required", "evidence_map_required"):
            changed = copy.deepcopy(self.work_order)
            changed[field] = False
            with self.subTest(field=field), self.assertRaisesRegex(
                ContractValidationError, "RISK_"
            ):
                _validate_semantics(self.bundle, epoch, changed)

    def test_scope_escape_is_rejected_when_supported(self):
        epoch = read_json(ACTIVE_EXECUTION / "project-epoch.v1.json")
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
            with self.assertRaisesRegex(
                ContractValidationError, "SCOPE_PATH_ESCAPES_REPOSITORY"
            ):
                _validate_semantics(bundle, epoch, changed)

    def test_duplicate_json_keys_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "duplicate.json"
            path.write_text(
                '{"state":"BLOCKED","state":"DISPATCHED"}', encoding="utf-8"
            )
            with self.assertRaisesRegex(ContractValidationError, "JSON_DUPLICATE_KEY"):
                read_json(path)

    def test_wrong_pinned_dependency_version_fails_closed(self):
        with mock.patch(
            "harness.contracts.importlib.metadata.version", return_value="4.21.0"
        ):
            with self.assertRaisesRegex(
                ContractValidationError, "PINNED_DEPENDENCY_VERSION_REQUIRED"
            ):
                self.bundle.validate("event_schema", self.events[0], "event")

    def test_active_review_and_evidence_freshness_matrix(self):
        implementation = _git_implementation_head(ROOT, ACTIVE_EXECUTION)
        for review_fresh, map_fresh in (
            (False, False),
            (False, True),
            (True, False),
            (True, True),
        ):
            documents = {
                "reviews/ZZ-ACTIVE-REVIEW.json": self.active_review(
                    implementation if review_fresh else EPOCH_BASE_SHA
                ),
                "evidence/ZZ-ACTIVE-MAP.json": self.active_evidence_map(
                    implementation if map_fresh else EPOCH_BASE_SHA
                ),
            }
            with self.subTest(
                review_fresh=review_fresh, map_fresh=map_fresh
            ), self.active_documents(documents):
                state = build_state(ROOT, ACTIVE_EXECUTION)
                self.assertEqual(
                    "PASS" if review_fresh else "STALE",
                    state["review"]["post_build_state"],
                )
                self.assertEqual(
                    not review_fresh,
                    "POST_BUILD_REVIEW_NOT_FRESH_PASS" in state["checkpoint_blockers"],
                )
                self.assertEqual(
                    not map_fresh,
                    "EVIDENCE_MAP_NOT_FRESH_PASS" in state["checkpoint_blockers"],
                )

    def test_unreferenced_epoch_audit_never_authorizes(self):
        audit_path = "config/control/harness/executions/E/audits/audit.json"
        audit = {
            "schema": "distributed_world_simulator.harness_epoch_audit.v1",
            "base_sha": "1" * 40,
            "main_sha": "2" * 40,
            "decision": "CONTINUE",
            "pc0": "NON_RED",
            "directional_pc0": "NON_RED",
        }
        context = {"documents": {audit_path: audit}}
        self.assertIsNone(_select_epoch_audit(context, []))
        incomplete = {
            "event_type": "AUDIT_COMPLETED",
            "work_state": "AUDITED",
            "exit_code": 0,
            "evidence_paths": [audit_path],
        }
        self.assertIsNone(_select_epoch_audit(context, [incomplete]))
        self.assertEqual(
            audit,
            _select_epoch_audit(
                context, [{**incomplete, "command": "CONTROL_PROJECT.ps1"}]
            ),
        )

    def test_epoch_exact_moved_audited_and_invalidated(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            for args in (
                ("init", "-b", "main"),
                ("config", "user.email", "h0@example.test"),
                ("config", "user.name", "H0"),
                ("commit", "--allow-empty", "-m", "base"),
            ):
                subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True)
            base = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=repo, check=True, text=True, capture_output=True
            ).stdout.strip()
            epoch = {"base_sha": base, "status": "ACTIVE"}
            self.assertEqual("EXACT_BASE", validate_epoch(repo, epoch, "main", None)["status"])
            subprocess.run(
                ["git", "commit", "--allow-empty", "-m", "advance"],
                cwd=repo,
                check=True,
                capture_output=True,
            )
            main = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=repo, check=True, text=True, capture_output=True
            ).stdout.strip()
            self.assertEqual(
                "MAIN_MOVED_REVIEW_REQUIRED",
                validate_epoch(repo, epoch, "main", None)["status"],
            )
            audit = {
                "schema": "distributed_world_simulator.harness_epoch_audit.v1",
                "base_sha": base,
                "main_sha": main,
                "decision": "CONTINUE",
                "pc0": "NON_RED",
                "directional_pc0": "NON_RED",
            }
            self.assertEqual(
                "MAIN_MOVED_AUDIT_CONTINUE",
                validate_epoch(repo, epoch, "main", audit)["status"],
            )
            epoch["status"] = "INVALIDATED"
            self.assertEqual(
                "EPOCH_INVALIDATED",
                validate_epoch(repo, epoch, "main", audit)["status"],
            )

    def test_event_provenance_rejects_worktree_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            subprocess.run(["git", "init", "-b", "main"], cwd=repo, check=True, capture_output=True)
            subprocess.run(["git", "config", "user.email", "h0@example.test"], cwd=repo, check=True)
            subprocess.run(["git", "config", "user.name", "H0"], cwd=repo, check=True)
            subprocess.run(["git", "commit", "--allow-empty", "-m", "base"], cwd=repo, check=True, capture_output=True)
            subject = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=repo, check=True, text=True, capture_output=True
            ).stdout.strip()
            event_dir = repo / "events"
            event_dir.mkdir()
            path = event_dir / "0001.json"
            event = {"event_id": "E1", "head_sha": subject}
            path.write_text(json.dumps(event), encoding="utf-8")
            subprocess.run(["git", "add", "."], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-m", "event"], cwd=repo, check=True, capture_output=True)
            current = subprocess.run(
                ["git", "rev-parse", "HEAD"], cwd=repo, check=True, text=True, capture_output=True
            ).stdout.strip()
            self.assertEqual(
                40,
                len(_validate_event_git_provenance(repo, [path], [event], current)),
            )
            path.write_text(json.dumps({**event, "changed": True}), encoding="utf-8")
            with self.assertRaisesRegex(
                ContractValidationError, "EVENT_WORKTREE_MUTATION_DETECTED"
            ):
                _validate_event_git_provenance(repo, [path], [event], current)

    def test_status_plan_resume_use_r2_epoch(self):
        shell = shutil.which("powershell") or shutil.which("pwsh")
        if shell is None:
            self.skipTest("PowerShell unavailable")
        for switch, command in (
            ("-Status", "STATUS"),
            ("-Plan", "PLAN"),
            ("-Resume", "RESUME"),
        ):
            completed = subprocess.run(
                [
                    shell,
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(ROOT / "CONTROL_DEVELOPMENT.ps1"),
                    switch,
                ],
                cwd=ROOT,
                text=True,
                encoding="utf-8",
                capture_output=True,
                check=False,
            )
            with self.subTest(command=command):
                self.assertEqual(0, completed.returncode, completed.stderr)
                envelope = json.loads(completed.stdout.splitlines()[-1])
                self.assertTrue(envelope["ok"])
                self.assertEqual(command, envelope["command"])
                self.assertEqual("E2026-08-11-H0-0-R2", envelope["epoch"]["epoch_id"])
                self.assertEqual(
                    ACTIVE_WORK_ORDER_ID,
                    envelope["active_work_order"]["work_order_id"],
                )
                self.assertFalse(envelope["runtime_authorized"])
                self.assertEqual(
                    "H0_0_SCAFFOLD_READY", envelope["next"]["checkpoint"]
                )

    def test_invalid_public_invocation_fails_closed(self):
        shell = shutil.which("powershell") or shutil.which("pwsh")
        if shell is None:
            self.skipTest("PowerShell unavailable")
        completed = subprocess.run(
            [
                shell,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(ROOT / "CONTROL_DEVELOPMENT.ps1"),
                "-Status",
                "-Plan",
            ],
            cwd=ROOT,
            text=True,
            encoding="utf-8",
            capture_output=True,
            check=False,
        )
        self.assertEqual(2, completed.returncode)
        self.assertEqual(
            "INVALID_INVOCATION",
            json.loads(completed.stdout.splitlines()[-1])["error"]["code"],
        )

    def test_clean_clone_snapshot_mismatch_exits_five(self):
        dirty = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=True,
        ).stdout.strip()
        if dirty:
            self.skipTest("clean-HEAD recovery drill requires a committed worktree")
        shell = shutil.which("powershell") or shutil.which("pwsh")
        if shell is None:
            self.skipTest("PowerShell unavailable")
        with tempfile.TemporaryDirectory() as directory:
            clone = Path(directory) / "verification clone"
            cloned = subprocess.run(
                [
                    "git",
                    "clone",
                    "--no-hardlinks",
                    "--branch",
                    ACTIVE_BRANCH,
                    str(ROOT),
                    str(clone),
                ],
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(0, cloned.returncode, cloned.stderr)
            canonical_main = subprocess.run(
                ["git", "rev-parse", "origin/main"],
                cwd=ROOT,
                text=True,
                capture_output=True,
                check=True,
            ).stdout.strip()
            subprocess.run(
                ["git", "update-ref", "refs/remotes/origin/main", canonical_main],
                cwd=clone,
                check=True,
            )
            path = (
                clone
                / "config/control/harness/executions/E2026-08-11-H0-0-R2"
                / f"work-orders/{ACTIVE_WORK_ORDER_ID}.v1.json"
            )
            work_order = read_json(path)
            work_order["state"] = "PLANNED"
            path.write_text(json.dumps(work_order), encoding="utf-8")
            result = subprocess.run(
                [
                    shell,
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(clone / "CONTROL_DEVELOPMENT.ps1"),
                    "-Resume",
                ],
                cwd=clone.parent,
                text=True,
                encoding="utf-8",
                capture_output=True,
                check=False,
            )
            self.assertEqual(5, result.returncode, result.stderr)
            envelope = json.loads(result.stdout.splitlines()[-1])
            self.assertEqual("EXECUTION_STATE_INVALID", envelope["error"]["code"])
            self.assertIn(
                "WORK_ORDER_SNAPSHOT_STATE_MISMATCH", envelope["error"]["detail"]
            )


if __name__ == "__main__":
    unittest.main()
