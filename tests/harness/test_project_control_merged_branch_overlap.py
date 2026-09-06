from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "control"))

import project_control as pc


class MergedBranchOverlapTests(unittest.TestCase):
    def _program(self, name: str, head: str) -> dict:
        return {
            "program": name,
            "branch": f"feature/{name.lower()}",
            "head": head,
            "scope_changed_files": ["tests/harness/shared_contract.py"],
            "health": "GREEN",
            "findings": [],
        }

    @staticmethod
    def _policy() -> dict:
        return {"overlap_policy": {"ignored_patterns": [], "yellow_patterns": []}}

    def test_fully_merged_branch_does_not_create_concurrent_overlap(self) -> None:
        merged_head = "a" * 40
        active_head = "b" * 40
        programs = [self._program("V0", merged_head), self._program("NX", active_head)]

        def fake_git(*args: str, allow_fail: bool = False) -> str:
            self.assertEqual(("merge-base",), args[:1])
            head = args[1]
            return merged_head if head == merged_head else "c" * 40

        with patch.object(pc._core, "git", side_effect=fake_git):
            overlaps = pc.apply_cross_branch_overlap(programs, self._policy())

        self.assertEqual([], overlaps)
        self.assertEqual("GREEN", programs[0]["health"])
        self.assertEqual("GREEN", programs[1]["health"])
        self.assertEqual("FULLY_MERGED_INTO_MAIN", programs[0]["overlap_scope_state"])
        self.assertEqual(["tests/harness/shared_contract.py"], programs[0]["scope_changed_files"])

    def test_two_unmerged_branches_still_fail_red_on_contract_overlap(self) -> None:
        left_head = "d" * 40
        right_head = "e" * 40
        programs = [self._program("V0", left_head), self._program("NX", right_head)]

        with patch.object(pc._core, "git", return_value="f" * 40):
            overlaps = pc.apply_cross_branch_overlap(programs, self._policy())

        self.assertEqual(1, len(overlaps))
        self.assertEqual("RED", programs[0]["health"])
        self.assertEqual("RED", programs[1]["health"])
        self.assertEqual("CROSS_BRANCH_RUNTIME_OR_CONTRACT_OVERLAP", programs[0]["findings"][0]["code"])


if __name__ == "__main__":
    unittest.main()
