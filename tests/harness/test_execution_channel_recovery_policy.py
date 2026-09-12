from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.contracts import ContractBundle, ContractValidationError


class ExecutionChannelRecoveryPolicyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.policy = json.loads(
            (ROOT / "config/control/harness/continuation-policy.v1.json").read_text(
                encoding="utf-8"
            )
        )
        self.recovery = self.policy["execution_channel_recovery"]

    def test_channel_failure_is_never_a_mission_terminal_by_itself(self) -> None:
        self.assertEqual(
            "H0-CHANNEL-RECOVERY-2026-09-12-R1",
            self.policy["execution_channel_recovery_revision"],
        )
        self.assertEqual("FAIL_FORWARD_FROM_DURABLE_GIT", self.recovery["mode"])
        self.assertFalse(self.recovery["tool_failure_is_terminal"])
        self.assertFalse(self.recovery["resource_handle_loss_is_terminal"])
        self.assertFalse(self.recovery["executor_network_failure_is_terminal"])
        self.assertFalse(self.recovery["reasoning_or_session_channel_failure_is_terminal"])
        self.assertTrue(
            self.recovery["hard_block_escalation_requires_autonomous_execution_proof"]
        )

    def test_stale_resources_and_network_failures_have_fail_forward_routes(self) -> None:
        self.assertEqual(
            [
                "DISCARD_STALE_RESOURCE_HANDLE",
                "REFETCH_BY_DURABLE_LOCATOR",
                "VERIFY_EXACT_SUBJECT_IDENTITY",
                "RESUME_FROM_LAST_DURABLE_PREDICATE",
            ],
            self.recovery["ephemeral_resource_failure_route"],
        )
        network = self.recovery["executor_network_failure_route"]
        self.assertIn("DO_NOT_INFER_REMOTE_SERVICE_OUTAGE", network)
        self.assertIn("DO_NOT_REPEAT_IDENTICAL_FAILED_ROUTE", network)
        self.assertIn("TRY_GITHUB_CONNECTOR_OR_EXISTING_EXACT_CHECKOUT", network)
        self.assertIn("TRY_REPOSITORY_OWNED_CI_IF_EXECUTION_IS_REQUIRED", network)
        routing = self.recovery["github_source_routing"]
        self.assertTrue(routing["container_dns_failure_does_not_prove_github_unavailable"])
        self.assertTrue(routing["container_download_is_not_git_transport"])
        self.assertTrue(
            routing[
                "do_not_bootstrap_clone_from_network_restricted_container_when_connector_available"
            ]
        )

    def test_known_session_break_signatures_are_forbidden_stop_reasons(self) -> None:
        forbidden = set(self.recovery["forbidden_stop_reasons"])
        self.assertTrue(
            {
                "CONNECTOR_RESOURCE_NOT_READABLE",
                "CONNECTOR_RESOURCE_NOT_FOUND",
                "TOOL_RESULT_HANDLE_EXPIRED",
                "CURRENT_EXECUTOR_DNS_FAILURE",
                "CURRENT_EXECUTOR_GITHUB_CLONE_FAILURE",
                "DOWNLOAD_ROUTE_SECURITY_REJECTION",
                "LONG_REASONING_OR_TOOL_CHAIN_FAILURE",
                "PREFERRED_EXECUTOR_UNAVAILABLE",
                "CURRENT_EXECUTOR_WORKSPACE_LOSS",
            }.issubset(forbidden)
        )
        chain = self.recovery["long_tool_chain_guard"]
        self.assertTrue(chain["require_recovery_anchor_before_high_fanout_tool_phase"])
        self.assertTrue(chain["reanchor_exact_subject_after_transient_channel_failure"])
        self.assertTrue(chain["stale_resource_ids_must_not_cross_recovery_boundary"])
        self.assertTrue(chain["nonterminal_mission_must_fail_forward"])

    def test_contract_integrity_rejects_weakening_channel_recovery(self) -> None:
        bundle = ContractBundle.load(ROOT)
        weakened = copy.deepcopy(bundle.contracts)
        weakened["continuation_policy"]["execution_channel_recovery"][
            "tool_failure_is_terminal"
        ] = True
        with self.assertRaisesRegex(
            ContractValidationError,
            "CHANNEL_RECOVERY_POLICY_INVALID:tool_failure_is_terminal",
        ):
            ContractBundle(root=ROOT, contracts=weakened).validate_integrity()

        weakened = copy.deepcopy(bundle.contracts)
        weakened["continuation_policy"]["principles"][
            "unreadable_ephemeral_resource_must_be_refetched_from_durable_locator"
        ] = False
        with self.assertRaisesRegex(
            ContractValidationError,
            "CHANNEL_RECOVERY_PRINCIPLES_INVALID",
        ):
            ContractBundle(root=ROOT, contracts=weakened).validate_integrity()

    def test_agent_router_and_doctrine_expose_the_recovery_contract(self) -> None:
        agents = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
        doctrine = (ROOT / "docs/control/HARNESS_CHANNEL_RECOVERY_RU.md").read_text(
            encoding="utf-8"
        )
        self.assertIn("TOOL / TRANSPORT / SESSION FAILURE IS NOT A MISSION TERMINAL", agents)
        self.assertIn("RECOVER FROM EXACT SHA / DURABLE LOCATOR", agents)
        self.assertIn("ResourceNotReadable", doctrine)
        self.assertIn("EXECUTOR_LOCAL_ROUTE_FAILURE", doctrine)
        self.assertIn("NON-TERMINAL MISSION MUST FAIL FORWARD", doctrine)


if __name__ == "__main__":
    unittest.main()
