"""ACT0 tests. Installed as tests/harness/test_v0_mvp_act0.py by the assembler."""
from __future__ import annotations

from contextlib import contextmanager
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from harness.checkpoint_planner import build_plan
from harness.contracts import ContractBundle

BASE = "3d7672cba293d8e7bd72427b803f73fc8fcee5da"
P7 = "V0_P7_BOUNDED_TERRAIN_MUTATION"
MVP = "V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE"
BRANCH = "feature/v0-mvp-playable-seamless-planet-r1"
EPOCH = "E2026-09-09-V0-MVP-R1"
WO = "V0-MVP-R1-WO-001"
H = "config/control/harness/"
EX = H + "executions/" + EPOCH


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=root, encoding="utf-8", stderr=subprocess.PIPE).strip()


def read(path: str) -> dict:
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


class MVPAct0Tests(unittest.TestCase):
    def setUp(self):
        self.bundle = ContractBundle.load(ROOT)
        self.wo = read(EX + "/work-orders/" + WO + ".v1.json")
        self.reduced = {"work_order_id": WO, "state": "DISPATCHED", "completed_predicates": []}

    @contextmanager
    def fixture(self, adopted: bool):
        with tempfile.TemporaryDirectory(prefix="act0-authority-") as tmp:
            root = Path(tmp) / "repo"
            subprocess.run(["git", "clone", "--quiet", "--shared", str(ROOT), str(root)], check=True)
            head = git(ROOT, "rev-parse", "HEAD")
            git(root, "checkout", "--quiet", "-B", BRANCH, head)
            git(root, "update-ref", "refs/remotes/origin/main", head if adopted else BASE)
            yield root

    def cli(self, root: Path, *args: str):
        env = dict(os.environ, PYTHONPATH=str(root / "scripts"), PYTHONUTF8="1")
        result = subprocess.run([sys.executable, "-m", "harness.cli", *args, "--root", str(root)],
                                cwd=root, env=env, capture_output=True, text=True, encoding="utf-8", timeout=120)
        self.assertTrue(result.stdout.strip(), result.stderr)
        return result.returncode, json.loads(result.stdout.strip().splitlines()[-1])

    def test_exact_product_base_and_epoch_are_bound(self):
        act = read(H + "activation/V0-MVP-R1-ACTIVATION-001.v1.json")
        epoch = read(EX + "/project-epoch.v1.json")
        self.assertEqual(BASE, act["main_declared_exact_successor_base"])
        self.assertEqual(git(ROOT, "rev-parse", BASE + "^{tree}"), act["exact_successor_base_tree"])
        self.assertEqual(BASE, epoch["base_sha"])
        self.assertEqual(BASE, self.wo["base_sha"])
        self.assertEqual(EPOCH, self.wo["project_epoch"])
        self.assertEqual([MVP], epoch["eligible_checkpoints"])
        self.assertEqual(self.bundle.contracts["project_registry"]["registry_generation"], epoch["registry_generation"])
        self.assertEqual("CRITICAL", self.wo["risk_class"])
        self.assertFalse(act["mvp_accepted"])
        self.assertFalse(act["mutation_lease"]["actual_worker_started"])

    def test_operational_mirrors_are_consistent(self):
        registry = self.bundle.contracts["project_registry"]
        scheduler = self.bundle.contracts["scheduler_policy"]
        routing = scheduler["v0_product_train_routing"]
        train = read(H + "v0-product-train-policy.v1.json")
        work_map = read(H + "v0-current-work-map.v1.json")
        lane = registry["coordination"]["lanes"]["MVP"]
        for actual in (routing["current_checkpoint"], train["current_checkpoint"], work_map["current_campaign"], lane["current_checkpoint"]):
            self.assertEqual(MVP, actual)
        for phase in (routing["current_phase"], train["current_phase"], work_map["status"], registry["programs"]["V0"]["stage_status"]):
            self.assertEqual(lane["phase"], phase)
        self.assertEqual(MVP, scheduler["pre_h0_3_runtime_mutation_lease"]["holder_checkpoint"])
        self.assertEqual(BRANCH, scheduler["pre_h0_3_runtime_mutation_lease"]["holder_branch"])
        self.assertEqual(1, scheduler["pre_h0_3_runtime_mutation_lease"]["capacity"])
        self.assertEqual(1, scheduler["concurrency"]["pre_h0_3_total_autonomous_runtime_mutation_workers"])

    def test_work_order_does_not_weaken_catalog_or_risk_policy(self):
        required = self.bundle.contracts["checkpoint_catalog"]["checkpoints"][MVP]["required_predicates"]
        self.assertEqual(required, self.wo["required_predicates"])
        for predicate in ("FULL_WORLD_CORE_REGRESSION_PASS", "INDEPENDENT_REVIEWER_PASS", "INDEPENDENT_VERIFIER_PASS", "HUMAN_MVP_ACCEPTANCE"):
            self.assertIn(predicate, required)
        self.assertEqual(self.bundle.contracts["risk_policy"]["classes"]["CRITICAL"]["required_roles"], self.wo["required_review_roles"])
        self.assertIn("RUNTIME_FEATURE_MERGE", self.wo["human_approval_required_for"])

    def test_planner_selects_one_mvp_worker(self):
        plan = build_plan(self.bundle.contracts, self.wo, self.reduced)
        self.assertEqual(MVP, plan["selected_checkpoint"])
        self.assertEqual(1, plan["autonomous_runtime_workers"])
        self.assertEqual("BEGIN_V0_MVP_PLAYABLE_SEAMLESS_PLANET_COMPOSITION", plan["next_action"])
        self.assertEqual("CRITICAL", plan["v0_mvp_gate"]["risk_floor"])
        self.assertEqual("SERVER_PREDICTED", plan["v0_mvp_gate"]["network_baseline"])
        self.assertNotIn("SERVER_HANDOFF", plan["stop_gates"])

    def test_old_p7_and_other_runtime_workers_are_rejected(self):
        for checkpoint in (P7, "H0_2_NX_C1_HIGH_RISK_PILOT", "UNKNOWN_CHECKPOINT"):
            wo = dict(self.wo, goal_checkpoint=checkpoint)
            with self.subTest(checkpoint=checkpoint), self.assertRaisesRegex(ValueError, "GLOBAL_MUTATION_SLOT_RESERVED_FOR"):
                build_plan(self.bundle.contracts, wo, self.reduced)

    def test_wrong_base_epoch_and_branch_fail_closed(self):
        for field, value in (("base_sha", "f" * 40), ("project_epoch", "E-foreign"), ("work_order_id", "FOREIGN"), ("branch", "feature/foreign")):
            with self.subTest(field=field), self.assertRaises(ValueError):
                build_plan(self.bundle.contracts, dict(self.wo, **{field: value}), self.reduced)

    def test_runtime_hold_is_not_bypassed_by_planner(self):
        for value in (False, None, "true", 1):
            contracts = copy.deepcopy(self.bundle.contracts)
            contracts["scheduler_policy"]["v0_product_train_routing"]["runtime_mutation_allowed_now"] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                build_plan(contracts, self.wo, self.reduced)

    def test_all_p7_execution_and_acceptance_blobs_are_unchanged(self):
        for path in (H + "executions/E2026-08-30-V0-P7-R1", H + "acceptance"):
            self.assertEqual("", git(ROOT, "diff", "--name-only", BASE, "HEAD", "--", path))
        for path in ("scripts/runtime", "scripts/network", "scripts/simulation", "scenes", "project.godot"):
            self.assertEqual("", git(ROOT, "diff", "--name-only", BASE, "HEAD", "--", path))

    def test_candidate_default_and_explicit_execution_cannot_activate(self):
        with self.fixture(adopted=False) as root:
            for args in (("drive",), ("drive", "--execution", EX)):
                code, payload = self.cli(root, *args)
                self.assertEqual(0, code, payload)
                self.assertEqual("PROJECT_CONTROL_ROUTING", payload["output_kind"])
                self.assertFalse(payload["runtime_authorized"])
                self.assertEqual("ACTIVATE_MVP_FROM_ACCEPTED_P7", payload["control_route"]["next_action"])

    def test_adopted_control_routes_to_mvp_and_requires_epoch_audit(self):
        with self.fixture(adopted=True) as root:
            code, payload = self.cli(root, "drive")
            self.assertEqual(0, code, payload)
            self.assertEqual(MVP, payload["selected_checkpoint"])
            self.assertEqual("MAIN_MOVED_REVIEW_REQUIRED", payload["epoch"]["validation"]["status"])
            self.assertFalse(payload["next"]["mission_complete"])
            self.assertEqual("INTEGRATOR", payload["next"]["next_actor"])
            code, closed = self.cli(root, "close-mission")
            self.assertEqual(8, code, closed)

    def test_historical_p7_can_close_without_reopening_old_epoch(self):
        with self.fixture(adopted=True) as root:
            code, payload = self.cli(root, "close-mission", "--checkpoint", P7)
            self.assertEqual(0, code, payload)
            self.assertTrue(payload["control_route"]["mission_complete"])
            self.assertFalse(payload["runtime_authorized"])


    def commit_fixture(self, root, relative, value):
        path = root / relative
        path.write_text(json.dumps(value) + "\n", encoding="utf-8")
        git(root, "add", "--", relative)
        git(root, "-c", "user.name=ACT0 fixture", "-c", "user.email=fixture@example.invalid", "commit", "-qm", "test-only canonical fault")
        git(root, "update-ref", "refs/remotes/origin/main", git(root, "rev-parse", "HEAD"))

    def test_mvp_canonical_lease_and_mirror_faults_block_execution(self):
        faults = [
            (H + "scheduler-policy.v1.json", "LEASE_GENERATION_MISMATCH", "lease"),
            (H + "v0-product-train-policy.v1.json", "CURRENT_PHASE_MISMATCH", "phase"),
            (H + "activation/V0-MVP-R1-ACTIVATION-001.v1.json", "MVP_ACTIVATION_TREE_MISMATCH", "tree"),
            (H + "event.schema.v1.json", "JSON_SCHEMA_INVALID", "schema"),
        ]
        for relative, expected, kind in faults:
            with self.subTest(kind=kind), self.fixture(adopted=True) as root:
                value = json.loads((root / relative).read_text())
                if kind == "lease":
                    value["pre_h0_3_runtime_mutation_lease"]["effective_registry_generation"] -= 1
                elif kind == "phase":
                    value["current_phase"] = "INVALID_PHASE"
                elif kind == "tree":
                    value["exact_successor_base_tree"] = "f" * 40
                else:
                    value["type"] = "invalid-schema-type"
                self.commit_fixture(root, relative, value)
                code, result = self.cli(root, "drive")
                self.assertEqual(3, code, result)
                self.assertIn(expected, result["error"]["detail"])

    def test_current_product_sequence_is_unique(self):
        policy = read(H + "v0-product-train-policy.v1.json")
        ids = [item["id"] for item in policy["checkpoint_sequence"]]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual([P7, MVP, "V0_P8_FIRST_MOBILE_CONSTRUCT"], ids[-3:])


if __name__ == "__main__":
    unittest.main()
