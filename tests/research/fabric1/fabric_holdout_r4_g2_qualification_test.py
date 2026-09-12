"""Adversarial controls for the offline qualification reducer (no third-party modules)."""
from __future__ import annotations
import contextlib
import copy
import importlib.util
import io
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("r4_qualification", ROOT / "scripts/research/fabric_holdout_r4_g2/qualification.py")
assert SPEC and SPEC.loader
Q = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(Q)
HEAD, TREE, HASH, GODOT = "a" * 40, "b" * 40, "c" * 64, "d" * 64


class QualificationTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.log = self.root / "gate.log"
        self.log.write_text("stage one\nGATE: PASS\n", encoding="utf-8")
        self.policy = {"schema": Q.POLICY_SCHEMA, "gates": [{"id": "g", "required": True,
            "command_id": "gate-v1", "argv": ["bash", "gate.sh"], "environment_id": "exact-double",
            "godot_sha256": GODOT, "pass_markers": ["GATE: PASS"]}]}
        self.report = {"schema": Q.REPORT_SCHEMA, "subject_head": HEAD, "subject_tree": TREE,
            "policy_sha256": HASH, "gates": [{"id": "g", "subject_head": HEAD, "subject_tree": TREE,
            "policy_sha256": HASH, "command_id": "gate-v1", "argv": ["bash", "gate.sh"],
            "environment_id": "exact-double", "godot_sha256": GODOT, "classification": "NONE",
            "status": "COMPLETED", "conclusion": "PASS", "exit_code": 0, "source_clean": True,
            "evidence": [{"role": "combined_log", "path": "gate.log", "sha256": Q.digest(self.log.read_bytes())}]}]}

    def tearDown(self):
        self.temp.cleanup()

    def run_reduce(self, findings=None):
        return Q.reduce_evidence(self.policy, self.report, self.root, HEAD, TREE, HASH, findings or [])

    def blocked(self):
        result = self.run_reduce()
        self.assertEqual(result["qualification"], "BLOCKED")
        self.assertFalse(result["ready_for_independent_review"])
        self.assertFalse(result["production_freeze_allowed"])

    def replace_log(self, text):
        self.log.write_text(text)
        self.report["gates"][0]["evidence"][0]["sha256"] = Q.digest(self.log.read_bytes())

    def test_positive_never_grants_acceptance(self):
        result = self.run_reduce()
        self.assertEqual(result["qualification"], "PASS")
        self.assertEqual(result["blocking_total"], 0)
        self.assertTrue(result["ready_for_independent_review"])
        for key in ("production_freeze_allowed", "unseen_holdout_allowed", "checkpoint_accepted"):
            self.assertFalse(result[key])

    def test_missing(self):
        self.report["gates"] = []
        self.blocked()

    def test_stale_receipt_fields(self):
        original = copy.deepcopy(self.report)
        for field in ("subject_head", "subject_tree", "policy_sha256", "command_id", "environment_id", "godot_sha256"):
            with self.subTest(field=field):
                self.report = copy.deepcopy(original)
                self.report["gates"][0][field] = "wrong"
                self.blocked()

    def test_wrong_command(self):
        self.report["gates"][0]["argv"] = ["echo", "GATE: PASS"]
        self.blocked()

    def test_stale_report_fields(self):
        for field in ("subject_head", "subject_tree", "policy_sha256"):
            original = self.report[field]
            self.report[field] = "wrong"
            self.blocked()
            self.report[field] = original

    def test_non_pass_states(self):
        for state in ("CANCELLED", "SKIPPED", "RUNNING", "QUEUED", "MISSING", "INFRASTRUCTURE"):
            self.report["gates"][0]["status"] = state
            self.blocked()

    def test_baseline_never_waives_failure(self):
        for classification in sorted(Q.CLASSIFICATIONS):
            self.report["gates"][0].update(classification=classification, conclusion="FAIL", exit_code=1)
            self.blocked()

    def test_invalid_exit(self):
        for code in (None, False, True, "0", 1, 124, -15):
            self.report["gates"][0]["exit_code"] = code
            self.blocked()

    def test_dirty_source(self):
        self.report["gates"][0]["source_clean"] = False
        self.blocked()

    def test_missing_evidence(self):
        self.report["gates"][0]["evidence"] = []
        self.blocked()

    def test_combined_log_mandatory(self):
        self.report["gates"][0]["evidence"][0]["role"] = "summary_only"
        self.blocked()

    def test_corrupt_log(self):
        self.log.write_text("corrupted\nGATE: PASS\n")
        self.blocked()

    def test_missing_log(self):
        self.log.unlink()
        self.blocked()

    def test_pass_substring_not_sufficient(self):
        self.replace_log("NOT GATE: PASS\nGATE: PASS_BUT_UNVERIFIED\n")
        self.blocked()

    def test_all_pass_markers_required(self):
        self.policy["gates"][0]["pass_markers"].append("OTHER: PASS")
        self.blocked()

    def test_fatal_after_pass(self):
        for fatal in ("ERROR: broken", "SCRIPT ERROR: bad", "Parse Error:", "Assertion failed", "Segmentation fault", "Traceback (most recent call last):"):
            self.replace_log("GATE: PASS\n" + fatal)
            self.blocked()

    def test_traversal_paths(self):
        for path in ("../gate.log", "/tmp/gate.log", "a/../../gate.log", "C:\\gate.log"):
            self.report["gates"][0]["evidence"][0]["path"] = path
            self.blocked()

    def test_symlink_escape(self):
        with tempfile.TemporaryDirectory() as other:
            target = Path(other) / "log"
            target.write_bytes(self.log.read_bytes())
            self.log.unlink()
            self.log.symlink_to(target)
            self.blocked()

    def test_non_utf8(self):
        self.log.write_bytes(b"\xff")
        self.report["gates"][0]["evidence"][0]["sha256"] = Q.digest(self.log.read_bytes())
        self.blocked()

    def test_duplicate_receipt(self):
        self.report["gates"].append(copy.deepcopy(self.report["gates"][0]))
        with self.assertRaises(Q.EvidenceError): self.run_reduce()

    def test_unknown_receipt(self):
        self.report["gates"][0]["id"] = "unknown"
        with self.assertRaises(Q.EvidenceError): self.run_reduce()

    def test_bad_schema(self):
        self.policy["schema"] = "future"
        with self.assertRaises(Q.EvidenceError): self.run_reduce()

    def test_empty_policy(self):
        self.policy["gates"] = []
        with self.assertRaises(Q.EvidenceError): self.run_reduce()

    def test_duplicate_policy(self):
        self.policy["gates"].append(copy.deepcopy(self.policy["gates"][0]))
        with self.assertRaises(Q.EvidenceError): self.run_reduce()

    def test_policy_waiver_forbidden(self):
        self.policy["gates"][0]["required"] = False
        with self.assertRaises(Q.EvidenceError): self.run_reduce()

    def test_frozen_drift_blocks_even_when_all_gates_green(self):
        result = self.run_reduce(["HISTORICAL_BYTES_CHANGED:frozen.txt"])
        self.assertEqual(result["qualification"], "BLOCKED")
        self.assertGreater(result["blocking_total"], 0)
        self.assertFalse(result["ready_for_independent_review"])

    def test_deterministic(self):
        self.assertEqual(self.run_reduce(), self.run_reduce())

    def test_duplicate_json_keys(self):
        path = self.root / "input.json"
        path.write_text('{"gates":[],"gates":["fake"]}')
        with self.assertRaises(Q.EvidenceError): Q.load_json(path)

    def test_nonfinite_json(self):
        path = self.root / "input.json"
        for value in ("NaN", "Infinity", "-Infinity"):
            path.write_text('{"value":' + value + '}')
            with self.assertRaises(Q.EvidenceError): Q.load_json(path)

    def test_git_identity_and_frozen_bytes(self):
        repo = self.root / "repo"
        repo.mkdir()
        def git(*args):
            return subprocess.check_output(["git", "-C", str(repo), *args], text=True, stderr=subprocess.DEVNULL).strip()
        git("init")
        git("config", "user.name", "Qualification Test")
        git("config", "user.email", "qualification@example.invalid")
        frozen = repo / "frozen.txt"
        frozen.write_text("FALSIFIED\n")
        git("add", "frozen.txt")
        git("commit", "-m", "baseline")
        head, tree = git("rev-parse", "HEAD"), git("rev-parse", "HEAD^{tree}")
        policy = {"historical_control": {"head": head, "paths": ["frozen.txt"], "verdict": "FALSIFIED"}}
        self.assertEqual(Q.verify_subject(repo, head, tree, policy), [])
        with self.assertRaisesRegex(Q.EvidenceError, "SUBJECT_HEAD_TREE_MISMATCH"):
            Q.verify_subject(repo, head, "0" * 40, policy)
        frozen.write_text("PASS\n")
        git("add", "frozen.txt")
        git("commit", "-m", "wrong history")
        self.assertEqual(Q.verify_subject(repo, git("rev-parse", "HEAD"), git("rev-parse", "HEAD^{tree}"), policy), ["HISTORICAL_BYTES_CHANGED:frozen.txt"])

    def test_cli_rejects_wrong_policy_digest(self):
        path = self.root / "policy.json"
        path.write_text(json.dumps(self.policy))
        receipt = self.root / "report.json"
        receipt.write_text(json.dumps(self.report))
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = Q.main(["--repo", str(self.root), "--policy", str(path), "--policy-sha256", HASH,
                           "--receipts", str(receipt), "--evidence-root", str(self.root), "--head", HEAD, "--tree", TREE])
        self.assertEqual(code, 3)
        self.assertEqual(json.loads(out.getvalue())["qualification"], "INVALID_EVIDENCE")


class CIQualificationTest(unittest.TestCase):
    """Same fail-closed contract for the explicitly weaker, API-observed CI gate."""
    tearDown = QualificationTest.tearDown
    run_reduce = QualificationTest.run_reduce
    blocked = QualificationTest.blocked
    def setUp(self):
        QualificationTest.setUp(self)
        self.spec = self.policy["gates"][0]
        self.spec.pop("godot_sha256")
        self.spec.update(mode="ci_workflow", workflow_path=".github/workflows/gate.yml",
                         workflow_blob="e" * 40, job_name="smoke", steps=["Checkout", "Run"])
        self.receipt = self.report["gates"][0]
        self.receipt.update(mode="ci_workflow", workflow_path=self.spec["workflow_path"],
                            workflow_blob=self.spec["workflow_blob"])
        for field in ("godot_sha256", "exit_code", "source_clean"):
            self.receipt.pop(field, None)
        prefix = "https://api.github.com/repos/rootfabric/distributed-world-simulator/actions/"
        self.observation = {"schema": "fabric.r4.ci-observation.v1", "run_id": 42, "job_id": 43,
            "run_url": prefix + "runs/42", "job_url": prefix + "jobs/43", "tested_head": HEAD,
            "tested_tree": TREE, "run_head_sha": HEAD, "run_conclusion": "success",
            "job_conclusion": "success", "status": "completed", "job_name": "smoke",
            "steps": [{"name": name, "status": "completed", "conclusion": "success"} for name in self.spec["steps"]],
            "log_excerpt": ["GATE: PASS", "HEAD=" + HEAD, "TREE=" + TREE], "full_log_archived": False}
        self.write_observation()

    def write_observation(self):
        self.log.write_text(json.dumps(self.observation))
        self.receipt["evidence"] = [{"role": "ci_api_observation", "path": "gate.log", "sha256": Q.digest(self.log.read_bytes())}]

    def test_ci_positive_is_not_acceptance(self):
        result = self.run_reduce()
        self.assertEqual(result["qualification"], "PASS")
        self.assertFalse(result["checkpoint_accepted"])

    def test_ci_cancelled_or_other_subject(self):
        original = copy.deepcopy(self.observation)
        for field, value in [("run_head_sha", "f" * 40), ("tested_head", "f" * 40), ("tested_tree", "f" * 40),
                             ("status", "queued"), ("run_conclusion", "cancelled"), ("job_conclusion", "failure"),
                             ("run_id", True), ("job_id", 0), ("run_url", "https://example.invalid"),
                             ("job_name", "unrelated"), ("full_log_archived", True)]:
            with self.subTest(field=field):
                self.observation = copy.deepcopy(original)
                self.observation[field] = value
                self.write_observation()
                self.blocked()

    def test_ci_failed_or_missing_steps(self):
        for steps in ([], [{"name": "Checkout", "status": "completed", "conclusion": "success"}],
                      [{"name": name, "status": "completed", "conclusion": "failure"} for name in self.spec["steps"]]):
            self.observation["steps"] = steps
            self.write_observation()
            self.blocked()

    def test_ci_workflow_not_bound(self):
        self.receipt["workflow_blob"] = "f" * 40
        self.blocked()

    def test_ci_excerpt_is_not_a_full_log(self):
        self.receipt["evidence"][0]["role"] = "combined_log"
        self.blocked()

    def test_ci_missing_identity_lines(self):
        self.observation["log_excerpt"] = ["GATE: PASS"]
        self.write_observation()
        self.blocked()

    def test_ci_fatal_in_excerpt(self):
        self.observation["log_excerpt"].append("SCRIPT ERROR: broken")
        self.write_observation()
        self.blocked()

    def test_ci_duplicate_observation_json(self):
        self.log.write_text('{"schema":"fabric.r4.ci-observation.v1","schema":"fake"}')
        self.receipt["evidence"][0]["sha256"] = Q.digest(self.log.read_bytes())
        self.blocked()



class CollectorTest(unittest.TestCase):
    def test_real_process_collection_and_fail_closed_controls(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo = root / "repo"
            repo.mkdir()
            def git(*args):
                return subprocess.check_output(["git", "-C", str(repo), *args], text=True, stderr=subprocess.DEVNULL).strip()
            git("init")
            git("config", "user.name", "Qualification Test")
            git("config", "user.email", "qualification@example.invalid")
            (repo / "frozen.txt").write_text("FALSIFIED")
            (repo / "pass.sh").write_text("echo 'GATE: PASS'\n")
            (repo / "fail.sh").write_text("echo 'GATE: PASS'\nexit 1\n")
            (repo / "timeout.sh").write_text("sleep 5\n")
            git("add", ".")
            git("commit", "-m", "test fixture")
            head, tree = git("rev-parse", "HEAD"), git("rev-parse", "HEAD^{tree}")
            binary = root / "pinned-binary.fixture"
            binary.write_text("not used by the toy shell gate")
            policy = {"schema": Q.POLICY_SCHEMA, "historical_control": {"head": head, "verdict": "FALSIFIED", "paths": ["frozen.txt"]},
                "gates": [{"id": "g", "required": True, "command_id": "toy", "argv": ["bash", "pass.sh"],
                    "environment_id": "toy", "godot_sha256": Q.digest(binary.read_bytes()), "timeout_seconds": 1,
                    "pass_markers": ["GATE: PASS"]}]}
            path = root / "policy.json"
            for script, expected in [("pass.sh", 0), ("fail.sh", 2), ("timeout.sh", 2)]:
                with self.subTest(script=script):
                    policy["gates"][0]["argv"][1] = script
                    path.write_text(json.dumps(policy))
                    out = root / (script + "-result")
                    command = ["python3", str(ROOT / "scripts/research/fabric_holdout_r4_g2/qualify.py"),
                        "--repo", str(repo), "--policy", str(path), "--policy-sha256", Q.digest(path.read_bytes()),
                        "--head", head, "--tree", tree, "--godot", str(binary), "--out", str(out)]
                    result = subprocess.run(command, capture_output=True, text=True, timeout=15)
                    self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
                    document = json.loads((out / "qualification.json").read_text())
                    self.assertFalse(document["checkpoint_accepted"])
                    self.assertFalse(document["production_freeze_allowed"])
                    if script == "timeout.sh":
                        receipts = json.loads((out / "receipts.json").read_text())
                        self.assertEqual(receipts["gates"][0]["exit_code"], 124)
                    # Evidence is immutable: a second run cannot overwrite it.
                    repeat = subprocess.run(command, capture_output=True, text=True, timeout=15)
                    self.assertEqual(repeat.returncode, 3)
            (repo / "frozen.txt").write_text("DIRTY")
            command[-1] = str(root / "dirty-result")
            result = subprocess.run(command, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 3)
            self.assertFalse((root / "dirty-result").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
