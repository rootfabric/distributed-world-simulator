"""Non-authorizing checks for restored verdicts and complete world coverage."""
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("p7_post_validation", ROOT / "docs/control/p7-post-acceptance-r1/validate.py")
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


class P7PostAcceptancePacketTests(unittest.TestCase):
    def test_historical_verdicts_are_exact_and_not_current_review(self):
        for path, expected in VALIDATOR.HISTORICAL.items():
            with self.subTest(path=path):
                data = (ROOT / path).read_bytes()
                self.assertEqual(expected, VALIDATOR.blob(data))
                record = json.loads(data)
                subject = record.get("reviewed_head", record.get("verified_head"))
                self.assertEqual("dca12cec28107042f07dcfe1b9d4d8ccd82fb8eb", subject)
                self.assertEqual("PASS", record["verdict"])

    def test_acceptance_verdict_paths_resolve(self):
        record = json.loads((ROOT / "config/control/harness/acceptance/V0-P7-R1-CHECKPOINT-ACCEPTED-001.v1.json").read_text())
        for relative in record["machine_evidence"]["verdict_documents"]:
            with self.subTest(path=relative):
                path = ROOT / relative
                self.assertTrue(path.is_file())
                self.assertIn(json.loads(path.read_text())["verdict"], ("PASS", "FAIL", "INSUFFICIENT_EVIDENCE"))

    def test_directional_advisory_is_explicit_and_preserved(self):
        advisory = {"level": "RED", "global_blocking": False, "target_program": "G"}
        report = {"findings": [advisory]}
        before = copy.deepcopy(report)
        self.assertEqual([], VALIDATOR.blocking_directional_findings(report))
        self.assertEqual(before, report)
        for value in (True, None, 0, "false", ""):
            with self.subTest(global_blocking=value):
                row = {"level": "RED", "global_blocking": value}
                self.assertEqual([row], VALIDATOR.blocking_directional_findings({"findings": [row]}))
        missing = {"level": "RED"}
        self.assertEqual([missing], VALIDATOR.blocking_directional_findings({"findings": [missing]}))
        with self.assertRaisesRegex(RuntimeError, "DIRECTIONAL_FINDINGS_INVALID"):
            VALIDATOR.blocking_directional_findings({"findings": [None]})

    def test_step_identity_uses_target_not_basename(self):
        first = {
            "name": "test_controller_profiles",
            "kind": "headless_script",
            "target": "res://tests/core/test_controller_profiles.gd",
            "passed": True,
            "exit_code": 0,
        }
        second = {
            "name": "test_controller_profiles",
            "kind": "headless_script",
            "target": "res://tests/integration/test_controller_profiles.gd",
            "passed": True,
            "exit_code": 0,
        }
        VALIDATOR.validate_world_step_identities([first, second])
        with self.assertRaisesRegex(RuntimeError, "WORLD_STEP_IDENTITY_COLLISION"):
            VALIDATOR.validate_world_step_identities([first, second, copy.deepcopy(first)])

    def fixture(self):
        temporary = tempfile.TemporaryDirectory(prefix="p7-coverage-")
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        scripts = [VALIDATOR.NATIVE, "tests/runtime/test_v0_p7_4_persistence_restart_composition.gd", "tests/core/test_example.gd"]
        for path in scripts + ["tests/core/fixtures/test_support.gd"]:
            target = root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("extends SceneTree\n")
        def step(name, kind="headless_script", target=""):
            return dict(name=name, kind=kind, target=target, passed=True, exit_code=0)
        steps = [step("test_manifest_coverage", "static"), step("editor_import_parse", "editor")]
        steps.append(step("test_matter_repository_lock_reclaim", target="res://" + scripts[0]))
        for phase in ("seed", "recover-deliver", "recover-replay"):
            steps.append(step("test_v0_p7_4_persistence_restart_composition[" + phase + "]", target="res://" + scripts[1]))
        steps += [step("test_example", target="res://" + scripts[2]), step("main_scene_cli_all", "main_scene_cli")]
        value = dict(passed=True, declared_test_count=3, discovered_test_count=3, steps=steps)
        self.save(root, value)
        return root, value

    def save(self, root, value):
        path = root / "artifacts/test-results/world-regression-summary.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value))

    def test_complete_dynamic_coverage(self):
        root, value = self.fixture()
        self.assertEqual(value, VALIDATOR.world_summary(root))

    def test_missing_duplicate_and_reordered_stages_fail_closed(self):
        root, value = self.fixture()
        cases = []
        missing = copy.deepcopy(value)
        missing["steps"].pop(2)
        cases.append(missing)
        duplicate = copy.deepcopy(value)
        duplicate["steps"][6] = copy.deepcopy(duplicate["steps"][2])
        cases.append(duplicate)
        reordered = copy.deepcopy(value)
        reordered["steps"][3], reordered["steps"][4] = reordered["steps"][4], reordered["steps"][3]
        cases.append(reordered)
        aggregate = copy.deepcopy(value)
        aggregate["steps"][-1]["name"] = "not_the_aggregate"
        cases.append(aggregate)
        failed = copy.deepcopy(value)
        failed["steps"][2]["exit_code"] = 1
        cases.append(failed)
        for index, case in enumerate(cases):
            with self.subTest(case=index):
                self.save(root, case)
                with self.assertRaises((RuntimeError, ValueError)):
                    VALIDATOR.world_summary(root)

    def test_new_discovered_script_cannot_be_silently_skipped(self):
        root, _ = self.fixture()
        (root / "tests/core/test_new.gd").write_text("extends SceneTree\n")
        with self.assertRaisesRegex(RuntimeError, "WORLD_DISCOVERY_NOT_COMPLETE"):
            VALIDATOR.world_summary(root)


if __name__ == "__main__":
    unittest.main()
