"""ACT0 epoch resume through real Git/CLI; fixtures never mutate project authority."""
from __future__ import annotations

from datetime import datetime, timedelta
import json
from pathlib import Path
import unittest

from tests.harness import test_v0_mvp_act0 as fixtures

BASE, MVP, EPOCH, WO, EX = fixtures.BASE, fixtures.MVP, fixtures.EPOCH, fixtures.WO, fixtures.EX
git = fixtures.git


class MVPEpochResumeTests(unittest.TestCase):
    fixture = fixtures.MVPAct0Tests.fixture
    cli = fixtures.MVPAct0Tests.cli

    def setUp(self):
        fixtures.MVPAct0Tests.setUp(self)

    def append_audit(self, root: Path, *, actor="INTEGRATOR", command="MVP_ACT0_POST_MERGE_EPOCH_AUDIT",
                     wrong_main=False, wrong_identity=False, committed=True, pc0="NON_RED", dirty=False):
        main = git(root, "rev-parse", "origin/main")
        relative = EX + "/audits/ACT0-POST-MERGE-AUDIT-TEST.v1.json"
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        audit = {"schema":"distributed_world_simulator.harness_epoch_audit.v1",
                 "project_epoch":EPOCH, "work_order_id":"FOREIGN" if wrong_identity else WO,
                 "base_sha":BASE, "main_sha":BASE if wrong_main else main,
                 "decision":"CONTINUE", "pc0":pc0, "directional_pc0":"NON_RED",
                 "evidence_class":"ISOLATED_TEST_FIXTURE_NOT_REAL_PROJECT_ACCEPTANCE"}
        path.write_text(json.dumps(audit) + "\n", encoding="utf-8")
        previous = json.loads((root / EX / "events" / WO / "0002-director-dispatched.v1.json").read_text())
        recorded = datetime.fromisoformat(previous["recorded_at_utc"].replace("Z", "+00:00")) + timedelta(seconds=1)
        event = {**previous, "event_id":EPOCH + "-TEST-0003", "sequence":3,
                 "event_type":"RECOVERY_RESUMED", "work_state":"DISPATCHED", "actor":actor,
                 "command":command, "exit_code":0, "head_sha":main, "evidence_paths":[relative],
                 "recorded_at_utc":recorded.isoformat(), "predicate":"ACT0_TEST_ONLY_EPOCH_AUDIT",
                 "summary":"Isolated pre-implementation audit fixture; no product stage completes."}
        event_path = EX + "/events/" + WO + "/0003-test-epoch-resumed.v1.json"
        (root / event_path).write_text(json.dumps(event) + "\n", encoding="utf-8")
        git(root, "add", "--", event_path)
        if committed:
            git(root, "add", "--", relative)
        git(root, "-c", "user.name=ACT0 audit fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "test-only exact epoch evidence")
        if dirty:
            path.write_text(json.dumps(dict(audit, pc0="RED")) + "\n", encoding="utf-8")
        return relative

    def test_committed_exact_audit_resumes_without_product_completion(self):
        with self.fixture(adopted=True) as root:
            code, before = self.cli(root, "drive")
            self.assertEqual(0, code, before)
            self.assertEqual("INTEGRATOR", before["next"]["next_actor"])
            self.assertEqual("BLOCK_CONTINUATION", before["epoch"]["validation"]["action"])
            self.append_audit(root)
            code, after = self.cli(root, "drive")
            self.assertEqual(0, code, after)
            self.assertEqual("MAIN_MOVED_AUDIT_CONTINUE", after["epoch"]["validation"]["status"])
            self.assertEqual("CONTINUE", after["epoch"]["validation"]["action"])
            self.assertFalse(after["continuation_blocked"])
            # INTEGRATION orders keep INTEGRATOR; the action now executes the order.
            self.assertEqual("INTEGRATOR", after["next"]["next_actor"])
            self.assertEqual("CONTINUE_ACTIVE_WORK_ORDER_TO_IMPLEMENTED_AND_VALIDATED", after["next"]["next_action"])
            self.assertEqual("DISPATCHED", after["reduced_work_order"]["state"])
            self.assertEqual([], after["reduced_work_order"]["completed_predicates"])
            self.assertFalse(after["next"]["mission_complete"])
            close_code, closed = self.cli(root, "close-mission")
            self.assertEqual(8, close_code, closed)

    def test_wrong_actor_command_or_red_audit_cannot_resume(self):
        for changes in ({"actor":"IMPLEMENTER"}, {"command":"UNRELATED_AUDIT"}, {"pc0":"RED"}):
            with self.subTest(changes=changes), self.fixture(adopted=True) as root:
                self.append_audit(root, **changes)
                code, result = self.cli(root, "drive")
                self.assertEqual(0, code, result)
                self.assertEqual("INTEGRATOR", result["next"]["next_actor"])
                self.assertEqual("BLOCK_CONTINUATION", result["epoch"]["validation"]["action"])

    def test_wrong_main_or_identity_cannot_resume(self):
        for changes in ({"wrong_main":True}, {"wrong_identity":True}):
            with self.subTest(changes=changes), self.fixture(adopted=True) as root:
                self.append_audit(root, **changes)
                code, result = self.cli(root, "drive")
                self.assertEqual(3, code, result)
                self.assertIn("MVP_RESUME_AUDIT_IDENTITY_MISMATCH", result["error"]["detail"])

    def test_uncommitted_or_dirty_audit_cannot_resume(self):
        for changes in ({"committed":False}, {"dirty":True}):
            with self.subTest(changes=changes), self.fixture(adopted=True) as root:
                self.append_audit(root, **changes)
                code, result = self.cli(root, "drive")
                self.assertNotEqual(0, code, result)
                expected = "EXECUTION_AUTHORITY_JSON_SET_MISMATCH" if changes.get("committed") is False else "PROVENANCE_WORKTREE_MODIFIED"
                self.assertIn(expected, result["error"]["detail"])

    def test_unreferenced_audit_is_not_authority(self):
        with self.fixture(adopted=True) as root:
            self.append_audit(root, command="UNREFERENCED_AUDIT_IGNORED")
            code, result = self.cli(root, "drive")
            self.assertEqual(0, code, result)
            self.assertEqual("INTEGRATOR", result["next"]["next_actor"])

    def append_progress(self, root: Path, event_type: str, state: str, evidence=None):
        directory = root / EX / "events" / WO
        prior = max((json.loads(p.read_text()) for p in directory.glob("*.json")), key=lambda x: x["sequence"])
        sequence = prior["sequence"] + 1
        recorded = datetime.fromisoformat(prior["recorded_at_utc"].replace("Z", "+00:00")) + timedelta(seconds=1)
        event = {**prior, "event_id":f"{EPOCH}-TEST-{sequence:04d}", "sequence":sequence,
                 "event_type":event_type, "work_state":state, "actor":"INTEGRATOR",
                 "command":"ACT0_ISOLATED_LIFECYCLE_TEST", "head_sha":git(root,"rev-parse","HEAD"),
                 "recorded_at_utc":recorded.isoformat(), "evidence_paths":evidence or [],
                 "summary":"Isolated legitimate transition; no product predicate or acceptance is claimed."}
        event.pop("predicate", None)
        event_path = directory / f"{sequence:04d}-test-progress.v1.json"
        event_path.write_text(json.dumps(event) + "\n", encoding="utf-8")
        order_path = root / EX / "work-orders" / (WO + ".v1.json")
        order = json.loads(order_path.read_text())
        order["state"] = state
        order_path.write_text(json.dumps(order) + "\n", encoding="utf-8")
        git(root, "add", "--", str(event_path.relative_to(root)), str(order_path.relative_to(root)), *(evidence or []))
        git(root, "-c", "user.name=ACT0 lifecycle fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "test-only lifecycle progression")

    def test_audit_survives_implementation_and_verification_events(self):
        with self.fixture(adopted=True) as root:
            self.append_audit(root)
            for kind, state in (("IMPLEMENTATION_COMMITTED","IN_PROGRESS"),
                                ("IMPLEMENTATION_COMMITTED","IMPLEMENTED"),
                                ("VERIFICATION_STARTED","VERIFYING"),
                                ("PREDICATE_VERIFIED","VERIFIED")):
                self.append_progress(root, kind, state)
                code, result = self.cli(root, "drive")
                self.assertEqual(0, code, result)
                self.assertEqual("MAIN_MOVED_AUDIT_CONTINUE", result["epoch"]["validation"]["status"])
                self.assertEqual("CONTINUE", result["epoch"]["validation"]["action"])
                self.assertEqual(state, result["reduced_work_order"]["state"])
                self.assertEqual([], result["reduced_work_order"]["completed_predicates"])
                self.assertFalse(result["next"]["mission_complete"])

    def test_later_main_invalidates_retained_audit(self):
        with self.fixture(adopted=True) as root:
            self.append_audit(root)
            self.append_progress(root,"IMPLEMENTATION_COMMITTED","IN_PROGRESS")
            git(root,"update-ref","refs/remotes/origin/main",git(root,"rev-parse","HEAD"))
            code, result = self.cli(root,"drive")
            self.assertEqual(0, code, result)
            self.assertEqual("MAIN_MOVED_REVIEW_REQUIRED",result["epoch"]["validation"]["status"])
            self.assertTrue(result["continuation_blocked"])

    def test_later_completed_audit_overrides_old_recovery(self):
        with self.fixture(adopted=True) as root:
            original_path = self.append_audit(root)
            for kind, state in (("IMPLEMENTATION_COMMITTED","IMPLEMENTED"),
                                ("VERIFICATION_STARTED","VERIFYING"),
                                ("PREDICATE_VERIFIED","VERIFIED")):
                self.append_progress(root,kind,state)
            newer = EX + "/audits/000-later-red-audit.v1.json"
            audit = json.loads((root/original_path).read_text())
            audit["pc0"] = "RED"
            (root/newer).write_text(json.dumps(audit) + "\n",encoding="utf-8")
            self.append_progress(root,"AUDIT_COMPLETED","AUDITED",[newer])
            code, result = self.cli(root,"drive")
            self.assertEqual(0, code, result)
            self.assertEqual("MAIN_MOVED_REVIEW_REQUIRED",result["epoch"]["validation"]["status"])
            self.assertTrue(result["continuation_blocked"])

    def test_feature_workflow_requires_explicit_act0_request(self):
        workflow = (fixtures.ROOT / ".github/workflows/mvp-act0-validation.yml").read_text()
        condition = next(line.strip() for line in workflow.splitlines() if line.startswith("    if:"))
        expected = (
            "if: github.repository == 'rootfabric/distributed-world-simulator' && github.actor == 'rootfabric' && "
            "(github.ref == 'refs/heads/control/v0-mvp-act0-r1' || "
            "(github.ref == 'refs/heads/feature/v0-mvp-playable-seamless-planet-r1' && "
            "(github.event_name == 'workflow_dispatch' || contains(github.event.head_commit.message, '[act0-audit]'))))"
        )
        self.assertEqual(expected, condition)
        self.assertIn("  contents: read",workflow)
        self.assertNotIn("contents: write",workflow)


if __name__ == "__main__":
    unittest.main()
