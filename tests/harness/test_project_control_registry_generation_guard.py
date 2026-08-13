from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "control"))

import project_control_core as standard
import project_control_directional_watch as directional
from project_control_registry_generation import (
    CANONICAL_R3_ARCHITECTURE_REVISION,
    evaluate_canonical_r3_registry_generation,
)


class ProjectControlRegistryGenerationGuardTests(unittest.TestCase):
    def _registry(self, generation: object) -> dict:
        return {
            "architecture_revision": CANONICAL_R3_ARCHITECTURE_REVISION,
            "registry_generation": generation,
        }

    def test_exact_allowlist_accepts_only_79_and_80(self):
        for generation in (79, 80):
            with self.subTest(generation=generation):
                decision = evaluate_canonical_r3_registry_generation(self._registry(generation))
                self.assertTrue(decision["allowed"], decision)
                self.assertEqual("EXACT_R3_REGISTRY_GENERATION_ALLOWED", decision["code"])

        for generation in (78, 81, 90, 999, "80", True, None):
            with self.subTest(generation=generation):
                decision = evaluate_canonical_r3_registry_generation(self._registry(generation))
                self.assertFalse(decision["allowed"], decision)
                self.assertEqual("UNSUPPORTED_R3_REGISTRY_GENERATION", decision["code"])

    def test_standard_pc0_returns_red_before_branch_audit_for_generation_81(self):
        invalid_registry = self._registry(81)
        with (
            patch.object(standard, "load_main_owned", return_value=copy.deepcopy(invalid_registry)),
            patch.object(standard, "audit_program") as audit_program,
            patch.object(sys, "argv", ["project_control_core.py", "--no-fetch"]),
        ):
            self.assertEqual(2, standard.main())
        audit_program.assert_not_called()

    def test_directional_pc0_returns_red_before_scope_collection_for_generation_81(self):
        invalid_registry = self._registry(81)
        with (
            patch.object(directional, "load_main_owned", return_value=copy.deepcopy(invalid_registry)),
            patch.object(directional, "program_scope") as program_scope,
            patch.object(sys, "argv", ["project_control_directional_watch.py"]),
        ):
            self.assertEqual(2, directional.main())
        program_scope.assert_not_called()


if __name__ == "__main__":
    unittest.main()
