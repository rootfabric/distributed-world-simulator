from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.contracts import ContractBundle, ContractValidationError
from harness.git_authority import build_git_authority


class GitTransportPolicyTests(unittest.TestCase):
    def test_github_actions_is_validation_evidence_only(self) -> None:
        harness = json.loads(
            (ROOT / "config/control/harness/harness-policy.v1.json").read_text(
                encoding="utf-8"
            )
        )
        principles = harness["principles"]
        self.assertTrue(
            principles[
                "github_actions_is_validation_and_evidence_plane_not_git_transport"
            ]
        )
        self.assertTrue(
            principles["github_actions_git_transport_workarounds_are_forbidden"]
        )
        self.assertTrue(
            principles[
                "normal_git_push_failure_must_be_diagnosed_before_external_automation"
            ]
        )

        authority = harness["git_execution_authority"]
        transport = authority["github_actions_transport_policy"]
        self.assertEqual("VALIDATION_AND_EVIDENCE_ONLY", transport["mode"])
        self.assertTrue(transport["normal_git_transport_required"])
        self.assertFalse(transport["may_replace_normal_git_transport"])
        self.assertFalse(transport["may_reconstruct_or_publish_source_commits"])
        self.assertFalse(transport["may_push_source_refs_as_fallback"])
        self.assertFalse(
            transport["may_mutate_workflows_to_gain_git_write_capability"]
        )
        self.assertIn(
            "DO_NOT_CREATE_OR_MUTATE_GITHUB_ACTIONS_AS_TRANSPORT_WORKAROUND",
            transport["push_failure_protocol"],
        )

        exposed = build_git_authority(harness)
        self.assertIn(
            "GITHUB_ACTIONS_GIT_TRANSPORT_WORKAROUND_FORBIDDEN",
            exposed["external_tool_boundary"],
        )

    def test_contract_integrity_rejects_transport_policy_weakening(self) -> None:
        bundle = ContractBundle.load(ROOT)
        weakened = copy.deepcopy(bundle.contracts)
        weakened["harness_policy"]["git_execution_authority"][
            "github_actions_transport_policy"
        ]["may_replace_normal_git_transport"] = True

        with self.assertRaisesRegex(
            ContractValidationError,
            "GITHUB_ACTIONS_TRANSPORT_POLICY_INVALID:may_replace_normal_git_transport",
        ):
            ContractBundle(root=ROOT, contracts=weakened).validate_integrity()

    def test_contract_integrity_rejects_missing_actions_transport_guard(self) -> None:
        bundle = ContractBundle.load(ROOT)
        weakened = copy.deepcopy(bundle.contracts)
        weakened["harness_policy"]["git_execution_authority"]["guards"].remove(
            "NO_GITHUB_ACTIONS_AS_GIT_TRANSPORT_WORKAROUND"
        )

        with self.assertRaisesRegex(
            ContractValidationError,
            "GIT_TRANSPORT_GUARDS_INVALID",
        ):
            ContractBundle(root=ROOT, contracts=weakened).validate_integrity()


if __name__ == "__main__":
    unittest.main()
