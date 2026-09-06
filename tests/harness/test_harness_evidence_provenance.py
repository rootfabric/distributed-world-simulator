from __future__ import annotations

import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from harness.contracts import ContractBundle, ContractValidationError
from harness.evidence_provenance import (
    HARD_BLOCK_SCHEMA, MANIFEST_SCHEMA, REVIEW_SCHEMA, committed_bytes,
    validate_review_machine_evidence,
)
from harness.event_reducer import _enforce_guard, load_guard_context
from harness.state_builder import build_state


class EvidenceProvenanceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="dws-provenance-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-q", "-b", "verify/provenance-fixture")
        self.git("config", "user.name", "Provenance Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "core.autocrlf", "false")
        for path in (ROOT / "config/control/harness").glob("*.json"):
            dest = self.root / path.relative_to(ROOT)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, dest)
        dest = self.root / "config/control/project-program-registry.v1.json"
        shutil.copyfile(ROOT / dest.relative_to(self.root), dest)
        self.checkpoint = "H0_1_CLOSED_LOOP_C22_PILOT"
        # A genuine, isolated control fixture owns its own capacity-one lease.
        # No production ledger/config is edited and no state-builder mock is used.
        sched = self.read("config/control/harness/scheduler-policy.v1.json")
        sched["pre_h0_3_runtime_mutation_lease"].update(
            holder_checkpoint=self.checkpoint, holder_branch="verify/provenance-fixture",
        )
        self.write("config/control/harness/scheduler-policy.v1.json", sched)
        (self.root / "fixture_impl.txt").write_text("fixture implementation\n", encoding="utf-8")
        self.commit("fixture base")
        self.base = self.git("rev-parse", "HEAD")
        self.git("update-ref", "refs/remotes/origin/main", self.base)
        self.epoch_id = "E2026-09-06-PROVENANCE-TEST"
        self.execution = f"config/control/harness/executions/{self.epoch_id}"
        self.epoch = {
            "schema": "distributed_world_simulator.project_epoch.v1",
            "epoch_id": self.epoch_id, "base_sha": self.base,
            "registry_generation": 81, "architecture_revision": "TEST",
            "harness_revision": "H0-2026-08-11-R1", "created_at_utc": "2026-09-06T00:00:00Z",
            "eligible_checkpoints": [self.checkpoint], "status": "ACTIVE",
        }
        self.wo = {
            "schema": "distributed_world_simulator.work_order.v1",
            "work_order_id": "PROVENANCE-WO-001", "project_epoch": self.epoch_id,
            "program": "H0", "goal_checkpoint": self.checkpoint, "state": "BLOCKED",
            "work_order_type": "CONTROL", "base_sha": self.base,
            "branch": "verify/provenance-fixture", "scope": "Isolated provenance test",
            "allowed_paths": ["fixture_impl.txt"], "forbidden_paths": ["runtime/**"],
            "required_predicates": [], "required_outputs": [], "stop_conditions": [],
            "risk_class": "LOW", "review_required": False, "evidence_map_required": False,
            "required_review_roles": ["IMPLEMENTER", "VERIFIER"],
            "issued_at_utc": "2026-09-06T00:00:00Z",
        }
        self.proof_path = f"{self.execution}/evidence/hard-block.v1.json"
        self.event_path = f"{self.execution}/events/PROVENANCE-WO-001/003.v1.json"
        self.proof = {
            "schema": HARD_BLOCK_SCHEMA, "work_order_id": self.wo["work_order_id"],
            "project_epoch": self.epoch_id, "checkpoint": self.checkpoint,
            "blocked_event_id": "EVENT-003", "blocked_head_sha": self.base,
            "blocked_tree_sha": self.git("rev-parse", f"{self.base}^{{tree}}"),
            "blocker": "MANDATORY_TEST_CAPABILITY_UNAVAILABLE",
            "proven_non_automatable": True, "required_capability_mandatory": True,
            "automation_fallbacks_exhausted": True, "scope_preserving_recovery_exhausted": True,
            "proof_evidence_path": self.proof_path,
            "resume_condition": "MANDATORY_TEST_CAPABILITY_AVAILABLE",
        }
        self.write(f"{self.execution}/project-epoch.v1.json", self.epoch)
        self.write(f"{self.execution}/work-orders/PROVENANCE-WO-001.v1.json", self.wo)
        transition = json.loads((ROOT / "config/control/harness/executions/E2026-08-12-H0-1-R8/transition-table.v1.json").read_text())
        self.write(f"{self.execution}/transition-table.v1.json", transition)
        self.events = []
        for index, (kind, state) in enumerate([
            ("WORK_ORDER_CREATED", "PLANNED"), ("DISPATCHED", "DISPATCHED"), ("BLOCKED", "BLOCKED"),
        ], 1):
            event = {
                "schema": "distributed_world_simulator.harness_event.v1", "event_id": f"EVENT-{index:03}",
                "project_epoch": self.epoch_id, "work_order_id": self.wo["work_order_id"],
                "sequence": index, "event_type": kind, "work_state": state,
                "recorded_at_utc": f"2026-09-06T00:00:0{index}Z", "actor": "DIRECTOR",
                "branch": self.wo["branch"], "head_sha": self.base, "summary": kind,
            }
            if index == 3:
                event.update(blocker=self.proof["blocker"], evidence_paths=[self.proof_path])
            self.events.append(event)
            self.write(f"{self.execution}/events/PROVENANCE-WO-001/{index:03}.v1.json", event)
        self.commit("append immutable control ledger")
        self.subject = self.git("rev-parse", "HEAD")

    def git(self, *args: str) -> str:
        return subprocess.run(["git", *args], cwd=self.root, text=True, encoding="utf-8",
                              capture_output=True, check=True, timeout=30).stdout.strip()

    def read(self, path: str) -> dict:
        return json.loads((self.root / path).read_text(encoding="utf-8"))

    def write(self, path: str, value: dict) -> None:
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n", encoding="utf-8")

    def commit(self, message: str) -> None:
        self.git("add", ".")
        self.git("commit", "-qm", message)

    def cli(self, mode: str) -> tuple[int, dict]:
        env = {**os.environ, "PYTHONPATH": str(ROOT / "scripts"), "PYTHONUTF8": "1"}
        proc = subprocess.run(
            [sys.executable, "-m", "harness.cli", mode, "--root", str(self.root),
             "--execution", self.execution], cwd=self.root, env=env,
            text=True, encoding="utf-8", capture_output=True, timeout=45,
        )
        self.assertTrue(proc.stdout, proc.stderr)
        return proc.returncode, json.loads(proc.stdout)

    def state(self) -> dict:
        return build_state(self.root, self.root / self.execution)

    def publish_proof(self, **changes) -> None:
        self.write(self.proof_path, {**self.proof, **changes})
        self.commit("append blocker proof")

    def make_review(self) -> dict:
        return {
            "schema": REVIEW_SCHEMA, "review_id": "REVIEW-001",
            "review_type": "POST_BUILD_EXACT_HEAD_REVIEW", "work_order_id": self.wo["work_order_id"],
            "risk_class": "LOW", "reviewed_head_sha": self.subject, "reviewer": "INDEPENDENT_VERIFIER",
            "verdict": "PASS", "reviewed_at_utc": "2026-09-06T00:01:00Z",
            "required_fixes": [], "rank_up_moves": [], "evidence_gaps": [], "risk_assessment": "Fixture",
        }

    def publish_manifest(self, mutate=None) -> tuple[dict, dict]:
        log = f"{self.execution}/evidence/run.log"
        content = b"Ran 1 test\nOK\n"
        (self.root / log).parent.mkdir(parents=True, exist_ok=True)
        (self.root / log).write_bytes(content)
        manifest = {
            "schema": MANIFEST_SCHEMA, "work_order_id": self.wo["work_order_id"],
            "project_epoch": self.epoch_id, "subject_head_sha": self.subject,
            "subject_tree_sha": self.git("rev-parse", f"{self.subject}^{{tree}}"),
            "runner_id": "local-fixture", "run_id": "RUN-001",
            "tracked_checkout_clean_before": True, "tracked_checkout_clean_after": True,
            "artifacts": [{"path": log, "sha256": hashlib.sha256(content).hexdigest(),
                           "run_id": "RUN-001", "subject_head_sha": self.subject}],
            "commands": [{"command": "python -m unittest", "exit_code": 0,
                          "expected_exit_code": 0, "log_path": log}],
        }
        if mutate is not None:
            mutate(manifest)
        path = f"{self.execution}/evidence/manifest.v1.json"
        self.write(path, manifest)
        self.commit("append exact machine evidence")
        review = self.make_review()
        review["machine_evidence"] = {
            "mode": "REUSED", "manifest_path": path,
            "manifest_sha256": hashlib.sha256((self.root / path).read_bytes()).hexdigest(),
            "runner_id": "local-fixture", "run_id": "RUN-001", "artifact_paths": [log],
        }
        return review, manifest

    def check_review(self, review: dict) -> None:
        validate_review_machine_evidence(self.root, self.read("config/control/harness/review-policy.v1.json"), self.epoch, review)

    def test_real_drive_and_close_mission_accept_committed_proof(self):
        self.publish_proof()
        state = self.state()
        self.assertEqual(self.proof, state["hard_block_proof"])
        self.assertEqual("", self.git("status", "--porcelain"))
        for mode in ("drive", "close-mission"):
            with self.subTest(mode=mode):
                code, result = self.cli(mode)
                self.assertEqual(0, code, result)
                self.assertTrue(result["next"]["hard_blocked"])
                self.assertTrue(result["next"]["mission_exit_allowed"])
                self.assertFalse(result["next"]["mission_complete"])
                self.assertFalse(result["runtime_authorized"])

    def test_missing_and_untracked_proof_cannot_close_mission(self):
        for exists in (False, True):
            if exists:
                self.write(self.proof_path, self.proof)
            code, result = self.cli("close-mission")
            self.assertEqual(8, code, result)
            self.assertFalse(result["next"]["hard_blocked"])

    def test_modified_or_rewritten_proof_cannot_close_mission(self):
        self.publish_proof()
        self.write(self.proof_path, {**self.proof, "resume_condition": "ALTERED"})
        code, result = self.cli("close-mission")
        self.assertEqual(8, code, result)
        self.commit("rewrite proof is forbidden")
        code, result = self.cli("close-mission")
        self.assertEqual(8, code, result)

    def test_wrong_work_order_binding_fails_closed(self):
        self.publish_proof(work_order_id="UNRELATED")
        code, result = self.cli("drive")
        self.assertNotEqual(0, code)
        self.assertIn("HARD_BLOCK_PROOF_IDENTITY_MISMATCH", result["error"]["detail"])

    def test_wrong_head_tree_binding_fails_closed(self):
        self.publish_proof(blocked_tree_sha="0" * 40)
        code, result = self.cli("drive")
        self.assertNotEqual(0, code, result)
        self.assertIn("PROVENANCE_TREE_MISMATCH", result["error"]["detail"])

    def test_wrong_event_binding_fails_closed(self):
        self.publish_proof(blocked_event_id="OTHER")
        code, result = self.cli("drive")
        self.assertNotEqual(0, code, result)
        self.assertIn("HARD_BLOCK_PROOF_IDENTITY_MISMATCH", result["error"]["detail"])

    def test_path_traversal_and_symbolic_link_are_rejected(self):
        for path in ("../outside.json", "C:/outside.json", "/outside.json", "a/../b.json", ".git/config"):
            with self.subTest(path=path), self.assertRaises(ContractValidationError):
                committed_bytes(self.root, path)
        target = self.root / "linked.json"
        try:
            target.symlink_to(self.root / "fixture_impl.txt")
        except OSError as exc:
            self.skipTest(f"OS does not permit fixture symlinks: {exc}")
        self.commit("append link")
        with self.assertRaises(ContractValidationError):
            committed_bytes(self.root, "linked.json")

    def test_real_loader_downgrades_digest_free_pass_without_rewriting_it(self):
        review = self.make_review()
        path = f"{self.execution}/reviews/review.v1.json"
        self.write(path, review)
        self.commit("append review without machine evidence")
        state = self.state()
        self.assertEqual("INSUFFICIENT_EVIDENCE", state["review"]["post_build_state"])
        self.assertEqual("PASS", state["review"]["reviews"][0]["declared_verdict"])
        self.assertEqual("PASS", self.read(path)["verdict"])

    def test_valid_exact_manifest_satisfies_loader(self):
        review, _ = self.publish_manifest()
        self.check_review(review)
        self.write(f"{self.execution}/reviews/review.v1.json", review)
        self.commit("append bound independent review")
        self.assertEqual("PASS", self.state()["review"]["post_build_state"])

    def test_missing_binding_digest_or_artifact_cannot_reuse(self):
        review, _ = self.publish_manifest()
        for field in ("manifest_sha256", "manifest_path", "run_id", "runner_id", "artifact_paths", "mode"):
            changed = copy.deepcopy(review)
            del changed["machine_evidence"][field]
            with self.subTest(field=field), self.assertRaises(ContractValidationError):
                self.check_review(changed)
        for field, value in (("run_id", "OTHER-RUN"), ("manifest_sha256", "0" * 64), ("artifact_paths", [])):
            changed = copy.deepcopy(review)
            changed["machine_evidence"][field] = value
            with self.subTest(field=field), self.assertRaises(ContractValidationError):
                self.check_review(changed)

    def test_modified_artifact_is_not_trusted(self):
        review, _ = self.publish_manifest()
        (self.root / review["machine_evidence"]["artifact_paths"][0]).write_text("FAKE OK\n")
        with self.assertRaises(ContractValidationError):
            self.check_review(review)

    def test_fresh_execution_label_cannot_bypass_evidence(self):
        review = self.make_review()
        review["machine_evidence"] = {"mode": "FRESH_EXECUTION"}
        with self.assertRaises(ContractValidationError):
            self.check_review(review)

    def test_manifest_wrong_tree_is_rejected(self):
        review, _ = self.publish_manifest(lambda m: m.update(subject_tree_sha="0" * 40))
        with self.assertRaisesRegex(ContractValidationError, "PROVENANCE_TREE_MISMATCH"):
            self.check_review(review)

    def test_artifact_from_other_run_is_rejected(self):
        review, _ = self.publish_manifest(lambda m: m["artifacts"][0].update(run_id="OTHER-RUN"))
        with self.assertRaisesRegex(ContractValidationError, "REVIEW_ARTIFACT_RUN_BINDING_INVALID"):
            self.check_review(review)

    def test_artifact_wrong_digest_is_rejected(self):
        review, _ = self.publish_manifest(lambda m: m["artifacts"][0].update(sha256="0" * 64))
        with self.assertRaisesRegex(ContractValidationError, "REVIEW_ARTIFACT_DIGEST_MISMATCH"):
            self.check_review(review)

    def test_missing_artifact_digest_is_rejected(self):
        review, _ = self.publish_manifest(lambda m: m["artifacts"][0].pop("sha256"))
        with self.assertRaisesRegex(ContractValidationError, "REVIEW_ARTIFACT_DIGEST_REQUIRED"):
            self.check_review(review)

    def test_untracked_review_is_not_authoritative(self):
        review, _ = self.publish_manifest()
        self.write(f"{self.execution}/reviews/untracked.v1.json", review)
        self.assertEqual("INSUFFICIENT_EVIDENCE", self.state()["review"]["post_build_state"])

    def test_main_move_routes_epoch_recovery_instead_of_old_hard_block(self):
        self.publish_proof()
        self.git("update-ref", "refs/remotes/origin/main", self.git("rev-parse", "HEAD"))
        code, result = self.cli("close-mission")
        self.assertEqual(8, code, result)
        self.assertFalse(result["next"]["hard_blocked"])
        self.assertIn("EPOCH_AUDIT", result["next"]["next_action"])

    def test_prebuild_review_cannot_authorize_checkpoint_proposal(self):
        review = self.make_review()
        review["review_type"] = "PRE_BUILD_DESIGN_AUTHORIZATION"
        path = f"{self.execution}/reviews/prebuild.v1.json"
        self.write(path, review)
        self.commit("append design review")
        event = {**self.events[-1], "work_state": "CHECKPOINT_PROPOSED", "head_sha": self.subject,
                 "evidence_paths": [path]}
        bundle = ContractBundle.load(self.root)
        context = load_guard_context(self.root, self.root / self.execution)
        with self.assertRaisesRegex(ContractValidationError, "GUARDED_POST_BUILD_REVIEW_REQUIRED"):
            _enforce_guard(bundle, self.wo, "AUDITED", event, [event], 0, context)

    def test_historical_review_contract_is_preserved(self):
        # Legacy behavior requires an actual historical Git snapshot, not a flag.
        registry = self.read("config/control/project-program-registry.v1.json")
        registry["registry_generation"] = 80
        self.write("config/control/project-program-registry.v1.json", registry)
        epoch = {**self.epoch, "registry_generation": 80}
        self.write(f"{self.execution}/project-epoch.v1.json", epoch)
        self.commit("historical generation-80 fixture")
        validate_review_machine_evidence(self.root, {}, epoch, self.make_review())

    def test_dirty_epoch_registry_downgrade_cannot_enter_legacy_drive(self):
        self.publish_proof()
        registry = self.read("config/control/project-program-registry.v1.json")
        registry["registry_generation"] = 80
        self.write("config/control/project-program-registry.v1.json", registry)
        self.write(f"{self.execution}/project-epoch.v1.json", {**self.epoch, "registry_generation": 80})
        for mode in ("drive", "close-mission"):
            with self.subTest(mode=mode):
                code, result = self.cli(mode)
                self.assertEqual(3, code, result)
                self.assertIn("PROVENANCE_WORKTREE_MODIFIED", result["error"]["detail"])

    def test_forged_guard_context_cannot_downgrade_committed_generation(self):
        review = self.make_review()
        path = f"{self.execution}/reviews/review.v1.json"
        self.write(path, review)
        self.commit("append digest-free review for guard test")
        context = {"root": self.root, "execution_dir": self.root / self.execution,
                   "epoch": {**self.epoch, "registry_generation": 80}, "documents": {path: review}}
        event = {**self.events[-1], "work_state": "CHECKPOINT_PROPOSED", "head_sha": self.subject,
                 "evidence_paths": [path]}
        with self.assertRaisesRegex(ContractValidationError, "REVIEW_COMMITTED_EPOCH_MISMATCH"):
            _enforce_guard(ContractBundle.load(self.root), self.wo, "AUDITED", event, [event], 0, context)

    def test_dirty_current_policy_cannot_select_legacy_hard_block(self):
        self.publish_proof()
        path = "config/control/harness/continuation-policy.v1.json"
        policy = self.read(path)
        policy.pop("autonomous_execution")
        self.write(path, policy)
        code, result = self.cli("close-mission")
        self.assertEqual(3, code, result)
        self.assertIn("PROVENANCE_WORKTREE_MODIFIED", result["error"]["detail"])

    def test_checkpoint_event_guard_rejects_same_digest_free_pass(self):
        review = self.make_review()
        path = f"{self.execution}/reviews/review.v1.json"
        self.write(path, review)
        self.commit("append invalid review")
        event = {**self.events[-1], "work_state": "CHECKPOINT_PROPOSED", "head_sha": self.subject,
                 "evidence_paths": [path]}
        bundle = ContractBundle.load(self.root)
        context = load_guard_context(self.root, self.root / self.execution)
        with self.assertRaisesRegex(ContractValidationError, "REVIEW_MACHINE_EVIDENCE_REQUIRED"):
            _enforce_guard(bundle, self.wo, "AUDITED", event, [event], 0, context)


if __name__ == "__main__":
    unittest.main()
