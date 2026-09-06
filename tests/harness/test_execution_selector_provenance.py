from __future__ import annotations

import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.contracts import ContractValidationError
from harness.execution_selector import resolve_execution


class ExplicitExecutionPathProvenanceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="dws-execution-selector-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.epoch_id = "E2026-09-06-SELECTOR-PROVENANCE"
        self.checkpoint = "H0_1_CLOSED_LOOP_C22_PILOT"
        self.canonical = self.root / "config/control/harness/executions" / self.epoch_id
        self._write_fixture(self.canonical)

    @staticmethod
    def _write_json(path: Path, value: dict) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n", encoding="utf-8")

    def _write_fixture(self, directory: Path) -> None:
        self._write_json(
            directory / "project-epoch.v1.json",
            {"schema": "fixture.epoch.v1", "epoch_id": self.epoch_id},
        )
        self._write_json(
            directory / "work-orders/WO-001.v1.json",
            {
                "schema": "fixture.work_order.v1",
                "work_order_id": "WO-001",
                "goal_checkpoint": self.checkpoint,
                "issued_at_utc": "2026-09-06T00:00:00Z",
            },
        )
        self._write_json(
            directory / "transition-table.v1.json",
            {"schema": "fixture.transition.v1"},
        )

    def test_explicit_canonical_execution_path_is_allowed(self) -> None:
        selected, checkpoint = resolve_execution(
            self.root, {}, execution=self.canonical,
        )
        self.assertEqual(self.canonical.resolve(), selected)
        self.assertEqual(self.checkpoint, checkpoint)

    def test_copied_epoch_under_arbitrary_directory_is_rejected(self) -> None:
        attacker = self.root / "scratch/forged-execution"
        shutil.copytree(self.canonical, attacker)
        value = json.loads((attacker / "transition-table.v1.json").read_text(encoding="utf-8"))
        value["allowed_state_transitions"] = {"VERIFIED": ["CHECKPOINT_PROPOSED"]}
        self._write_json(attacker / "transition-table.v1.json", value)
        with self.assertRaisesRegex(ContractValidationError, "EXECUTION_PATH_NOT_CANONICAL"):
            resolve_execution(self.root, {}, execution=attacker)

    def test_relative_arbitrary_execution_path_is_rejected(self) -> None:
        attacker = self.root / "tmp/copied-execution"
        shutil.copytree(self.canonical, attacker)
        relative = attacker.relative_to(self.root)
        with self.assertRaisesRegex(ContractValidationError, "EXECUTION_PATH_NOT_CANONICAL"):
            resolve_execution(self.root, {}, execution=relative)


if __name__ == "__main__":
    unittest.main()
