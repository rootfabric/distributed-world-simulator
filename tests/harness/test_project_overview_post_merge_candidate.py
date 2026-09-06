from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness import project_overview as overview


class PostMergeCandidateFreshnessTests(unittest.TestCase):
    def test_current_main_ancestor_makes_followup_candidate_fresh(self) -> None:
        canonical = "a" * 40
        candidate = "b" * 40

        def git(root: Path, *args: str):
            if args == ("rev-parse", "HEAD"):
                return 0, candidate
            if args == ("merge-base", canonical, candidate):
                return 0, canonical
            return 1, ""

        with patch.object(overview, "_git", side_effect=git):
            self.assertTrue(overview._candidate_contains_canonical_main(ROOT, canonical))

    def test_main_advanced_after_candidate_remains_stale(self) -> None:
        canonical = "c" * 40
        candidate = "d" * 40

        def git(root: Path, *args: str):
            if args == ("rev-parse", "HEAD"):
                return 0, candidate
            if args == ("merge-base", canonical, candidate):
                return 0, "e" * 40
            return 1, ""

        with patch.object(overview, "_git", side_effect=git):
            self.assertFalse(overview._candidate_contains_canonical_main(ROOT, canonical))

    def test_unresolvable_candidate_fails_closed(self) -> None:
        with patch.object(overview, "_git", return_value=(1, "")):
            self.assertFalse(overview._candidate_contains_canonical_main(ROOT, "f" * 40))


if __name__ == "__main__":
    unittest.main()
