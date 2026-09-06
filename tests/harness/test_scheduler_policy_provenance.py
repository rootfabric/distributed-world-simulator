from __future__ import annotations

import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.contracts import ContractValidationError
from harness.evidence_provenance import committed_enforcement_generation
from harness.event_reducer import load_guard_context


class CurrentBundlePolicyProvenanceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="dws-bundle-provenance-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self._git("init", "-q", "-b", "verify/bundle-provenance")
        self._git("config", "user.name", "Bundle Provenance Fixture")
        self._git("config", "user.email", "fixture@example.invalid")
        self._git("config", "core.autocrlf", "false")

        source_harness = ROOT / "config/control/harness"
        harness_dir = self.root / "config/control/harness"
        harness_dir.mkdir(parents=True, exist_ok=True)
        for source in source_harness.glob("*.json"):
            shutil.copyfile(source, harness_dir / source.name)

        registry = self.root / "config/control/project-program-registry.v1.json"
        registry.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / "config/control/project-program-registry.v1.json", registry)

        self.epoch_id = "E2026-09-06-BUNDLE-PROVENANCE"
        self.execution = harness_dir / "executions" / self.epoch_id
        self.execution.mkdir(parents=True, exist_ok=True)
        self.epoch = {
            "schema": "distributed_world_simulator.project_epoch.v1",
            "epoch_id": self.epoch_id,
            "base_sha": "0" * 40,
            "registry_generation": 81,
            "architecture_revision": "TEST",
            "harness_revision": "H0-2026-08-11-R1",
            "created_at_utc": "2026-09-06T00:00:00Z",
            "eligible_checkpoints": ["H0_1_CLOSED_LOOP_C22_PILOT"],
            "status": "ACTIVE",
        }
        (self.execution / "project-epoch.v1.json").write_text(
            json.dumps(self.epoch, sort_keys=True, indent=2) + "\n", encoding="utf-8"
        )
        self._git("add", ".")
        self._git("commit", "-qm", "fixture committed authority state")

    def _git(self, *args: str) -> str:
        return subprocess.run(
            ["git", *args], cwd=self.root, text=True, encoding="utf-8",
            capture_output=True, check=True, timeout=30,
        ).stdout.strip()

    def _bundle_paths(self) -> list[str]:
        policy = json.loads(
            (self.root / "config/control/harness/harness-policy.v1.json").read_text(encoding="utf-8")
        )
        keys = (
            "project_goals",
            "checkpoint_catalog",
            "scheduler_policy",
            "work_order_schema",
            "event_schema",
            "project_epoch_schema",
            "risk_policy",
            "review_policy",
            "repair_doctrine",
            "evidence_map_schema",
            "human_attention_schema",
            "continuation_policy",
        )
        return [
            "config/control/project-program-registry.v1.json",
            "config/control/harness/harness-policy.v1.json",
            *(policy[key] for key in keys),
        ]

    def _dirty_scheduler(self) -> None:
        path = self.root / "config/control/harness/scheduler-policy.v1.json"
        scheduler = json.loads(path.read_text(encoding="utf-8"))
        scheduler.pop("pre_h0_3_runtime_mutation_lease", None)
        path.write_text(json.dumps(scheduler, sort_keys=True, indent=2) + "\n", encoding="utf-8")

    def _dirty_repair_doctrine(self) -> None:
        path = self.root / "config/control/harness/repair-doctrine.v1.json"
        doctrine = json.loads(path.read_text(encoding="utf-8"))
        doctrine["repair_map_fields"] = []
        path.write_text(json.dumps(doctrine, sort_keys=True, indent=2) + "\n", encoding="utf-8")

    def test_dirty_scheduler_policy_is_rejected_by_generation_fence(self) -> None:
        self.assertEqual(81, committed_enforcement_generation(self.root, self.epoch))
        self._dirty_scheduler()
        with self.assertRaisesRegex(ContractValidationError, "PROVENANCE_WORKTREE_MODIFIED"):
            committed_enforcement_generation(self.root, self.epoch)

    def test_guard_context_rejects_dirty_scheduler_before_event_reduction(self) -> None:
        self._dirty_scheduler()
        with self.assertRaisesRegex(ContractValidationError, "PROVENANCE_WORKTREE_MODIFIED"):
            load_guard_context(self.root, self.execution)

    def test_assume_unchanged_cannot_hide_dirty_scheduler(self) -> None:
        path = "config/control/harness/scheduler-policy.v1.json"
        self._git("update-index", "--assume-unchanged", path)
        self._dirty_scheduler()
        with self.assertRaisesRegex(ContractValidationError, "PROVENANCE_WORKTREE_MODIFIED"):
            committed_enforcement_generation(self.root, self.epoch)

    def test_dirty_repair_doctrine_is_rejected_before_reducer_can_weaken_repair_map(self) -> None:
        self.assertEqual(81, committed_enforcement_generation(self.root, self.epoch))
        self._dirty_repair_doctrine()
        with self.assertRaisesRegex(ContractValidationError, "PROVENANCE_WORKTREE_MODIFIED"):
            committed_enforcement_generation(self.root, self.epoch)
        with self.assertRaisesRegex(ContractValidationError, "PROVENANCE_WORKTREE_MODIFIED"):
            load_guard_context(self.root, self.execution)

    def test_assume_unchanged_cannot_hide_dirty_repair_doctrine(self) -> None:
        path = "config/control/harness/repair-doctrine.v1.json"
        self._git("update-index", "--assume-unchanged", path)
        self._dirty_repair_doctrine()
        with self.assertRaisesRegex(ContractValidationError, "PROVENANCE_WORKTREE_MODIFIED"):
            committed_enforcement_generation(self.root, self.epoch)

    def test_every_current_contract_bundle_dependency_is_worktree_fenced(self) -> None:
        paths = self._bundle_paths()
        self.assertEqual(14, len(paths))
        self.assertEqual(len(paths), len(set(paths)))
        self.assertEqual(81, committed_enforcement_generation(self.root, self.epoch))
        for relative in paths:
            with self.subTest(path=relative):
                target = self.root / relative
                target.write_bytes(target.read_bytes() + b"\n")
                with self.assertRaisesRegex(ContractValidationError, "PROVENANCE_WORKTREE_MODIFIED"):
                    committed_enforcement_generation(self.root, self.epoch)
                self._git("checkout", "--", relative)
                self.assertEqual(81, committed_enforcement_generation(self.root, self.epoch))


if __name__ == "__main__":
    unittest.main()
