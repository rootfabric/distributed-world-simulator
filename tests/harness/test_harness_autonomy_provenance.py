from __future__ import annotations

import atexit
import contextlib
import io
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.cli import main as cli_main
from harness.contracts import ContractBundle
from harness.event_reducer import _authoritative_review_pass_present
from harness.state_builder import _load_reviews, build_state

P7 = "V0_P7_BOUNDED_TERRAIN_MUTATION"
P7_BRANCH = "feature/v0-p7-bounded-terrain-mutation"
SYNC_PATHS = [
    "scripts/harness/contracts.py",
    "scripts/harness/continuation.py",
    "scripts/harness/event_reducer.py",
    "scripts/harness/review_evidence.py",
    "scripts/harness/state_builder.py",
    "config/control/harness/harness-policy.v1.json",
    "config/control/harness/continuation-policy.v1.json",
    "config/control/harness/review-policy.v1.json",
    "config/control/harness/hard-block-proof.schema.v1.json",
]


def run(root: Path, *args: str) -> str:
    completed = subprocess.run(args, cwd=root, text=True, capture_output=True, check=True)
    return completed.stdout.strip()


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


_BUNDLE_PATH: Path | None = None


def exact_history_bundle() -> Path:
    global _BUNDLE_PATH
    if _BUNDLE_PATH is not None and _BUNDLE_PATH.is_file():
        return _BUNDLE_PATH
    fd, raw = tempfile.mkstemp(prefix="dws-autonomy-base-", suffix=".bundle")
    import os
    os.close(fd)
    bundle = Path(raw)
    bundle.unlink()
    subprocess.run([
        "git",
        "-c", f"safe.directory={ROOT}",
        "-c", f"safe.directory={ROOT / '.git'}",
        "-C", str(ROOT), "bundle", "create", str(bundle), "--all",
    ], check=True)
    _BUNDLE_PATH = bundle
    atexit.register(lambda: bundle.unlink(missing_ok=True))
    return bundle


class TempHarnessRepo:
    def __init__(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "repo"
        subprocess.run([
            "git", "clone", "--quiet", str(exact_history_bundle()), str(self.root),
        ], check=True)
        run(self.root, "git", "config", "user.email", "harness-test@example.invalid")
        run(self.root, "git", "config", "user.name", "Harness Test")
        run(self.root, "git", "checkout", "-B", P7_BRANCH)
        for relative in SYNC_PATHS:
            source = ROOT / relative
            target = self.root / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        run(self.root, "git", "add", *SYNC_PATHS)
        if run(self.root, "git", "status", "--porcelain"):
            run(self.root, "git", "commit", "-m", "test fixture: sync autonomy repair under test")
        self.subject_head = run(self.root, "git", "rev-parse", "HEAD")
        self.subject_tree = run(self.root, "git", "rev-parse", "HEAD^{tree}")
        self.main_head = run(ROOT, "git", "rev-parse", "origin/main")
        run(self.root, "git", "update-ref", "refs/remotes/origin/main", self.main_head)

    def close(self) -> None:
        self.temp.cleanup()

    def commit_all(self, message: str) -> str:
        run(self.root, "git", "add", "-A")
        run(self.root, "git", "commit", "-m", message)
        return run(self.root, "git", "rev-parse", "HEAD")

    def make_blocked_execution(self, *, include_proof: bool = True) -> Path:
        execution = self.root / "config/control/harness/executions/E-AUTONOMY-PROOF-R1"
        registry = json.loads((self.root / "config/control/project-program-registry.v1.json").read_text(encoding="utf-8"))
        harness = json.loads((self.root / "config/control/harness/harness-policy.v1.json").read_text(encoding="utf-8"))
        risk = json.loads((self.root / "config/control/harness/risk-policy.v1.json").read_text(encoding="utf-8"))
        epoch_id = "E-AUTONOMY-PROOF-R1"
        work_order_id = "AUTONOMY-PROOF-WO-001"
        proof_rel = f"config/control/harness/executions/{epoch_id}/evidence/AUTONOMY-HARD-BLOCK-001.v1.json"
        write_json(execution / "project-epoch.v1.json", {
            "schema": "distributed_world_simulator.project_epoch.v1",
            "epoch_id": epoch_id,
            "base_sha": self.main_head,
            "registry_generation": registry["registry_generation"],
            "architecture_revision": registry["architecture_revision"],
            "harness_revision": harness["harness_revision"],
            "created_at_utc": "2026-09-05T12:00:00Z",
            "eligible_checkpoints": [P7],
            "status": "ACTIVE",
        })
        write_json(execution / f"work-orders/{work_order_id}.v1.json", {
            "schema": "distributed_world_simulator.work_order.v1",
            "work_order_id": work_order_id,
            "project_epoch": epoch_id,
            "program": "V0",
            "goal_checkpoint": P7,
            "state": "BLOCKED",
            "work_order_type": "CONTROL",
            "base_sha": self.main_head,
            "branch": P7_BRANCH,
            "scope": "Synthetic production-route hard-block provenance regression",
            "allowed_paths": ["scripts/harness/**", "tests/harness/**"],
            "forbidden_paths": ["scripts/runtime/**", "scenes/**"],
            "required_predicates": [],
            "required_outputs": [],
            "stop_conditions": [],
            "risk_class": "LOW",
            "review_required": False,
            "required_review_roles": risk["classes"]["LOW"]["required_roles"],
            "evidence_map_required": False,
            "issued_at_utc": "2026-09-05T12:00:00Z",
        })
        source_transition = self.root / "config/control/harness/executions/E2026-08-30-V0-P7-R1/transition-table.v1.json"
        (execution / "transition-table.v1.json").parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_transition, execution / "transition-table.v1.json")
        event_dir = execution / f"events/{work_order_id}"
        common = {
            "schema": "distributed_world_simulator.harness_event.v1",
            "project_epoch": epoch_id,
            "work_order_id": work_order_id,
            "branch": P7_BRANCH,
            "head_sha": self.subject_head,
        }
        write_json(event_dir / "0001-created.v1.json", {
            **common,
            "event_id": "AUTONOMY-EVENT-001",
            "sequence": 1,
            "event_type": "WORK_ORDER_CREATED",
            "work_state": "PLANNED",
            "recorded_at_utc": "2026-09-05T12:00:01Z",
            "actor": "DIRECTOR",
            "summary": "Synthetic Work Order created.",
        })
        write_json(event_dir / "0002-dispatched.v1.json", {
            **common,
            "event_id": "AUTONOMY-EVENT-002",
            "sequence": 2,
            "event_type": "DISPATCHED",
            "work_state": "DISPATCHED",
            "recorded_at_utc": "2026-09-05T12:00:02Z",
            "actor": "DIRECTOR",
            "summary": "Synthetic control Work Order dispatched under the P7 closure lease.",
        })
        write_json(event_dir / "0003-blocked.v1.json", {
            **common,
            "event_id": "AUTONOMY-EVENT-003",
            "sequence": 3,
            "event_type": "BLOCKED",
            "work_state": "BLOCKED",
            "recorded_at_utc": "2026-09-05T12:00:03Z",
            "actor": "DIRECTOR",
            "evidence_paths": [proof_rel],
            "summary": "Synthetic hard block recorded.",
            "blocker": "MANDATORY_EXTERNAL_CAPABILITY_UNAVAILABLE",
        })
        if include_proof:
            write_json(self.root / proof_rel, {
                "schema": "distributed_world_simulator.harness_hard_block_proof.v1",
                "proof_id": "AUTONOMY-HARD-BLOCK-001",
                "project_epoch": epoch_id,
                "work_order_id": work_order_id,
                "checkpoint": P7,
                "blocked_event_id": "AUTONOMY-EVENT-003",
                "blocked_head_sha": self.subject_head,
                "recorded_at_utc": "2026-09-05T12:00:03Z",
                "proven_non_automatable": True,
                "required_capability_mandatory": True,
                "automation_fallbacks_exhausted": True,
                "scope_preserving_recovery_exhausted": True,
                "proof_evidence_path": proof_rel,
                "resume_condition": "MANDATORY_EXTERNAL_CAPABILITY_AVAILABLE",
            })
        self.commit_all("test fixture: durable blocked execution")
        return execution

    def make_review(self, *, machine_evidence: dict | None) -> tuple[Path, dict]:
        execution = self.root / "config/control/harness/executions/E-AUTONOMY-REVIEW-R1"
        path = execution / "reviews/AUTONOMY-REVIEW-001.v1.json"
        review = {
            "schema": "distributed_world_simulator.harness_review_result.v1",
            "review_id": "AUTONOMY-REVIEW-001",
            "review_type": "POST_BUILD_EXACT_HEAD_REVIEW",
            "work_order_id": "AUTONOMY-REVIEW-WO-001",
            "risk_class": "LOW",
            "reviewed_head_sha": self.subject_head,
            "reviewer": "FRESH_INDEPENDENT_VERIFIER_TEST",
            "verdict": "PASS",
            "reviewed_at_utc": "2026-09-05T12:05:00Z",
            "required_fixes": [],
            "rank_up_moves": [],
            "evidence_gaps": [],
            "risk_assessment": "Synthetic exact-head provenance regression.",
        }
        if machine_evidence is not None:
            review["machine_evidence"] = machine_evidence
        write_json(path, review)
        self.commit_all("test fixture: fresh post-build review")
        return execution, review


class HardBlockProductionRouteTests(unittest.TestCase):
    def test_committed_event_bound_proof_reaches_real_drive_hard_blocked(self) -> None:
        repo = TempHarnessRepo()
        try:
            execution = repo.make_blocked_execution(include_proof=True)
            state = build_state(repo.root, execution)
            self.assertTrue(state["hard_block_proof"]["_durable_provenance_validated"])
            output = io.StringIO()
            with patch("harness.cli.canonical_reconciliation_route", return_value=None), contextlib.redirect_stdout(output):
                exit_code = cli_main(["drive", "--root", str(repo.root), "--execution", str(execution)])
            payload = json.loads(output.getvalue().strip().splitlines()[-1])
            self.assertEqual(0, exit_code)
            self.assertEqual("HARD_BLOCKED", payload["drive"]["status"])
            self.assertTrue(payload["next"]["hard_blocked"])
            self.assertTrue(payload["next"]["mission_exit_allowed"])
        finally:
            repo.close()

    def test_missing_referenced_proof_never_authorizes_drive_terminal(self) -> None:
        repo = TempHarnessRepo()
        try:
            execution = repo.make_blocked_execution(include_proof=False)
            state = build_state(repo.root, execution)
            self.assertIsNone(state["hard_block_proof"])
            output = io.StringIO()
            with patch("harness.cli.canonical_reconciliation_route", return_value=None), contextlib.redirect_stdout(output):
                exit_code = cli_main(["drive", "--root", str(repo.root), "--execution", str(execution)])
            payload = json.loads(output.getvalue().strip().splitlines()[-1])
            self.assertEqual(0, exit_code)
            self.assertEqual("CONTINUE_REQUIRED", payload["drive"]["status"])
            self.assertFalse(payload["next"]["hard_blocked"])
            self.assertFalse(payload["next"]["mission_exit_allowed"])
        finally:
            repo.close()

    def test_proof_rewritten_after_block_event_is_rejected(self) -> None:
        repo = TempHarnessRepo()
        try:
            execution = repo.make_blocked_execution(include_proof=True)
            proof = execution / "evidence/AUTONOMY-HARD-BLOCK-001.v1.json"
            value = json.loads(proof.read_text(encoding="utf-8"))
            value["resume_condition"] = "DIFFERENT_LATER_CONDITION"
            write_json(proof, value)
            repo.commit_all("test fixture: forbidden later proof rewrite")
            with self.assertRaisesRegex(ValueError, "HARD_BLOCK_PROOF_NOT_DURABLE_AT_EVENT"):
                build_state(repo.root, execution)
        finally:
            repo.close()


    def test_proof_added_only_after_block_event_is_rejected(self) -> None:
        repo = TempHarnessRepo()
        try:
            execution = repo.make_blocked_execution(include_proof=False)
            proof_rel = "config/control/harness/executions/E-AUTONOMY-PROOF-R1/evidence/AUTONOMY-HARD-BLOCK-001.v1.json"
            write_json(repo.root / proof_rel, {
                "schema": "distributed_world_simulator.harness_hard_block_proof.v1",
                "proof_id": "AUTONOMY-HARD-BLOCK-001",
                "project_epoch": "E-AUTONOMY-PROOF-R1",
                "work_order_id": "AUTONOMY-PROOF-WO-001",
                "checkpoint": P7,
                "blocked_event_id": "AUTONOMY-EVENT-003",
                "blocked_head_sha": repo.subject_head,
                "recorded_at_utc": "2026-09-05T12:00:03Z",
                "proven_non_automatable": True,
                "required_capability_mandatory": True,
                "automation_fallbacks_exhausted": True,
                "scope_preserving_recovery_exhausted": True,
                "proof_evidence_path": proof_rel,
                "resume_condition": "MANDATORY_EXTERNAL_CAPABILITY_AVAILABLE",
            })
            repo.commit_all("test fixture: forbidden retroactive proof addition")
            with self.assertRaisesRegex(ValueError, "HARD_BLOCK_PROOF_NOT_DURABLE_AT_EVENT"):
                build_state(repo.root, execution)
        finally:
            repo.close()


class ReviewMachineEvidenceEnforcementTests(unittest.TestCase):
    def _work_order(self) -> dict:
        return {"work_order_id": "AUTONOMY-REVIEW-WO-001", "risk_class": "LOW"}

    def test_fresh_pass_without_machine_evidence_degrades_to_insufficient(self) -> None:
        repo = TempHarnessRepo()
        try:
            execution, _ = repo.make_review(machine_evidence=None)
            reviews = _load_reviews(ContractBundle.load(repo.root), execution, self._work_order())
            self.assertEqual("INSUFFICIENT_EVIDENCE", reviews[-1]["verdict"])
            self.assertEqual("PASS", reviews[-1]["declared_verdict"])
            self.assertIn("MACHINE_EVIDENCE_MODE_UNDECLARED", reviews[-1]["evidence_gaps"])
        finally:
            repo.close()

    def test_valid_fresh_reexecution_binding_remains_pass(self) -> None:
        repo = TempHarnessRepo()
        try:
            evidence = {
                "mode": "FRESH_REEXECUTION",
                "exact_head_sha": repo.subject_head,
                "exact_tree_sha": repo.subject_tree,
                "runner_or_workflow_run_id": "windows-local-verifier-r2",
            }
            execution, _ = repo.make_review(machine_evidence=evidence)
            reviews = _load_reviews(ContractBundle.load(repo.root), execution, self._work_order())
            self.assertEqual("PASS", reviews[-1]["verdict"])
        finally:
            repo.close()

    def test_valid_reused_sha256_manifest_remains_pass_and_guard_accepts_it(self) -> None:
        repo = TempHarnessRepo()
        try:
            evidence = {
                "mode": "REUSED_TRUSTED",
                "exact_head_sha": repo.subject_head,
                "exact_tree_sha": repo.subject_tree,
                "runner_or_workflow_run_id": "33963661379",
                "digest_manifest": [{
                    "artifact_id_or_path": "9968736274/project-control-report.zip",
                    "digest_algorithm": "SHA256",
                    "digest": "a" * 64,
                }],
            }
            execution, raw = repo.make_review(machine_evidence=evidence)
            bundle = ContractBundle.load(repo.root)
            reviews = _load_reviews(bundle, execution, self._work_order())
            self.assertEqual("PASS", reviews[-1]["verdict"])
            relative = (execution / "reviews/AUTONOMY-REVIEW-001.v1.json").relative_to(repo.root).as_posix()
            event = {"evidence_paths": [relative], "head_sha": repo.subject_head}
            context = {"root": repo.root, "documents": {relative: raw}}
            self.assertTrue(_authoritative_review_pass_present(bundle, event, context))
        finally:
            repo.close()

    def test_reused_manifest_with_unbound_digest_degrades_and_guard_rejects(self) -> None:
        repo = TempHarnessRepo()
        try:
            evidence = {
                "mode": "REUSED_TRUSTED",
                "exact_head_sha": repo.subject_head,
                "exact_tree_sha": repo.subject_tree,
                "runner_or_workflow_run_id": "33963661379",
                "digest_manifest": [{
                    "artifact_id_or_path": "9968736274/project-control-report.zip",
                    "digest_algorithm": "SHA256",
                    "digest": "not-a-sha256",
                }],
            }
            execution, raw = repo.make_review(machine_evidence=evidence)
            bundle = ContractBundle.load(repo.root)
            reviews = _load_reviews(bundle, execution, self._work_order())
            self.assertEqual("INSUFFICIENT_EVIDENCE", reviews[-1]["verdict"])
            self.assertIn("MACHINE_EVIDENCE_DIGEST_INVALID", reviews[-1]["evidence_gaps"])
            relative = (execution / "reviews/AUTONOMY-REVIEW-001.v1.json").relative_to(repo.root).as_posix()
            event = {"evidence_paths": [relative], "head_sha": repo.subject_head}
            context = {"root": repo.root, "documents": {relative: raw}}
            self.assertFalse(_authoritative_review_pass_present(bundle, event, context))
        finally:
            repo.close()


if __name__ == "__main__":
    unittest.main()
