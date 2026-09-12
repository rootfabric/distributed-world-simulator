from __future__ import annotations

import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from harness.contracts import ContractBundle, ContractValidationError

LEGACY_P7 = "3d7672cba293d8e7bd72427b803f73fc8fcee5da"
LEGACY_MAIN = "127c732a56cc5c25d5712f24a7627ed4bb877374"
CHANNEL_PRINCIPLES = (
    "tool_or_transport_failure_is_not_mission_terminal",
    "ephemeral_tool_handles_are_not_durable_state",
    "executor_local_network_failure_is_route_failure_not_project_block",
    "unreadable_ephemeral_resource_must_be_refetched_from_durable_locator",
    "reasoning_or_session_channel_failure_does_not_change_project_state",
)


def git(root: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", "--no-replace-objects", *args], cwd=root,
        text=True, encoding="utf-8", stderr=subprocess.PIPE, timeout=30,
    ).strip()


def historical_bundle(source: str) -> ContractBundle:
    return ContractBundle.load(
        ROOT, source_commit=source,
        reader=lambda path: json.loads(git(ROOT, "show", f"{source}:{path.relative_to(ROOT).as_posix()}")),
    )


def remove_channel_extension(contracts: dict) -> dict:
    value = copy.deepcopy(contracts)
    value["harness_policy"].pop("execution_channel_recovery_revision", None)
    continuation = value["continuation_policy"]
    continuation.pop("execution_channel_recovery_revision", None)
    continuation.pop("execution_channel_recovery", None)
    for name in CHANNEL_PRINCIPLES:
        continuation["principles"].pop(name, None)
    return value


class ExecutionChannelRecoveryPolicyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bundle = ContractBundle.load(ROOT)
        self.harness_policy = self.bundle.contracts["harness_policy"]
        self.policy = self.bundle.contracts["continuation_policy"]
        self.recovery = self.policy["execution_channel_recovery"]

    def test_channel_failure_is_never_a_mission_terminal_by_itself(self) -> None:
        expected_revision = "H0-CHANNEL-RECOVERY-2026-09-12-R1"
        self.assertEqual(expected_revision, self.harness_policy["execution_channel_recovery_revision"])
        self.assertEqual(expected_revision, self.policy["execution_channel_recovery_revision"])
        self.assertEqual("FAIL_FORWARD_FROM_DURABLE_GIT", self.recovery["mode"])
        self.assertFalse(self.recovery["tool_failure_is_terminal"])
        self.assertFalse(self.recovery["resource_handle_loss_is_terminal"])
        self.assertFalse(self.recovery["executor_network_failure_is_terminal"])
        self.assertFalse(self.recovery["reasoning_or_session_channel_failure_is_terminal"])
        self.assertTrue(self.recovery["hard_block_escalation_requires_autonomous_execution_proof"])

    def test_stale_resources_and_network_failures_have_fail_forward_routes(self) -> None:
        self.assertEqual(
            ["DISCARD_STALE_RESOURCE_HANDLE", "REFETCH_BY_DURABLE_LOCATOR",
             "VERIFY_EXACT_SUBJECT_IDENTITY", "RESUME_FROM_LAST_DURABLE_PREDICATE"],
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
        self.assertTrue(routing["do_not_bootstrap_clone_from_network_restricted_container_when_connector_available"])

    def test_known_session_break_signatures_are_forbidden_stop_reasons(self) -> None:
        self.assertTrue({
            "CONNECTOR_RESOURCE_NOT_READABLE", "CONNECTOR_RESOURCE_NOT_FOUND",
            "TOOL_RESULT_HANDLE_EXPIRED", "CURRENT_EXECUTOR_DNS_FAILURE",
            "CURRENT_EXECUTOR_GITHUB_CLONE_FAILURE", "DOWNLOAD_ROUTE_SECURITY_REJECTION",
            "TRANSIENT_CONNECTOR_FAILURE", "LONG_REASONING_OR_TOOL_CHAIN_FAILURE",
            "PREFERRED_EXECUTOR_UNAVAILABLE", "CURRENT_EXECUTOR_WORKSPACE_LOSS",
        }.issubset(set(self.recovery["forbidden_stop_reasons"])))
        chain = self.recovery["long_tool_chain_guard"]
        self.assertTrue(chain["require_recovery_anchor_before_high_fanout_tool_phase"])
        self.assertTrue(chain["reanchor_exact_subject_after_transient_channel_failure"])
        self.assertTrue(chain["stale_resource_ids_must_not_cross_recovery_boundary"])
        self.assertTrue(chain["nonterminal_mission_must_fail_forward"])

    def test_contract_integrity_rejects_weakening_channel_recovery(self) -> None:
        weakened = copy.deepcopy(self.bundle.contracts)
        weakened["continuation_policy"]["execution_channel_recovery"]["tool_failure_is_terminal"] = True
        with self.assertRaisesRegex(ContractValidationError, "CHANNEL_RECOVERY_POLICY_INVALID:tool_failure_is_terminal"):
            ContractBundle(root=ROOT, contracts=weakened).validate_integrity()
        weakened = copy.deepcopy(self.bundle.contracts)
        weakened["continuation_policy"]["principles"][CHANNEL_PRINCIPLES[3]] = False
        with self.assertRaisesRegex(ContractValidationError, "CHANNEL_RECOVERY_PRINCIPLES_INVALID"):
            ContractBundle(root=ROOT, contracts=weakened).validate_integrity()
        weakened = copy.deepcopy(self.bundle.contracts)
        weakened["continuation_policy"].pop("execution_channel_recovery_revision")
        with self.assertRaisesRegex(ContractValidationError, "CHANNEL_RECOVERY_REVISION_INVALID"):
            ContractBundle(root=ROOT, contracts=weakened).validate_integrity()

    def test_current_double_omission_is_not_historical_provenance(self) -> None:
        weakened = remove_channel_extension(self.bundle.contracts)
        with self.assertRaisesRegex(ContractValidationError, "CHANNEL_RECOVERY_LEGACY_PROVENANCE_REQUIRED"):
            ContractBundle(root=ROOT, contracts=weakened).validate_integrity()
        # Even a real current source SHA cannot masquerade as pre-feature history.
        with self.assertRaisesRegex(ContractValidationError, "CHANNEL_RECOVERY_LEGACY_PROVENANCE_INVALID"):
            ContractBundle(root=ROOT, contracts=weakened, source_commit=git(ROOT, "rev-parse", "HEAD")).validate_integrity()

    def test_real_historical_snapshots_remain_replayable(self) -> None:
        for source in (LEGACY_P7, LEGACY_MAIN):
            with self.subTest(source=source):
                bundle = historical_bundle(source)
                self.assertEqual(source, bundle.source_commit)
                self.assertNotIn("execution_channel_recovery_revision", bundle.contracts["harness_policy"])
                bundle.validate_schema_definitions()

    def test_historical_reader_without_declared_source_is_rejected(self) -> None:
        with self.assertRaisesRegex(ContractValidationError, "CHANNEL_RECOVERY_LEGACY_PROVENANCE_REQUIRED"):
            ContractBundle.load(ROOT, reader=lambda path: json.loads(
                git(ROOT, "show", f"{LEGACY_P7}:{path.relative_to(ROOT).as_posix()}")
            ))

    def test_historical_provenance_cannot_cover_mutated_or_mixed_contracts(self) -> None:
        original = historical_bundle(LEGACY_P7)
        for name in original.contracts:
            with self.subTest(contract=name):
                changed = copy.deepcopy(original.contracts)
                changed[name]["_forged_replay_marker"] = True
                with self.assertRaisesRegex(ContractValidationError, "CHANNEL_RECOVERY_LEGACY_SNAPSHOT_MISMATCH"):
                    ContractBundle(ROOT, changed, LEGACY_P7).validate_integrity()
        changed = copy.deepcopy(original.contracts)
        changed["harness_policy"]["principles"]["git_is_durable_memory"] = 1
        with self.assertRaisesRegex(ContractValidationError, "CHANNEL_RECOVERY_LEGACY_SNAPSHOT_MISMATCH:harness_policy"):
            ContractBundle(ROOT, changed, LEGACY_P7).validate_integrity()

    def test_branch_short_sha_and_missing_git_object_are_not_provenance(self) -> None:
        old = historical_bundle(LEGACY_P7).contracts
        for source in (None, "main", LEGACY_P7[:8], "f" * 40):
            with self.subTest(source=source):
                with self.assertRaisesRegex(ContractValidationError, "CHANNEL_RECOVERY_LEGACY_PROVENANCE_"):
                    ContractBundle(ROOT, old, source).validate_integrity()

    def test_anchor_requirements_are_complete_unique_and_typed(self) -> None:
        required = self.recovery["recovery_anchor_requires"]
        invalid = [None, [], "EXACT_SUBJECT", {}, [True], [[]],
                   required + [required[0]], required + ["UNKNOWN_REQUIREMENT"]]
        invalid.extend([item for item in required if item != missing] for missing in required)
        for value in invalid:
            with self.subTest(anchor=value):
                changed = copy.deepcopy(self.bundle.contracts)
                changed["continuation_policy"]["execution_channel_recovery"]["recovery_anchor_requires"] = value
                with self.assertRaisesRegex(ContractValidationError, "CHANNEL_RECOVERY_ANCHOR_REQUIREMENTS_INVALID"):
                    ContractBundle(ROOT, changed).validate_integrity()
        changed = copy.deepcopy(self.bundle.contracts)
        changed["continuation_policy"]["execution_channel_recovery"].pop("recovery_anchor_requires")
        with self.assertRaisesRegex(ContractValidationError, "CHANNEL_RECOVERY_ANCHOR_REQUIREMENTS_INVALID"):
            ContractBundle(ROOT, changed).validate_integrity()
        changed["continuation_policy"]["execution_channel_recovery"]["recovery_anchor_requires"] = list(reversed(required))
        ContractBundle(ROOT, changed).validate_integrity()

    def test_channel_booleans_do_not_accept_integer_aliases(self) -> None:
        for name, value in self.recovery.items():
            if type(value) is not bool:
                continue
            with self.subTest(field=name):
                changed = copy.deepcopy(self.bundle.contracts)
                changed["continuation_policy"]["execution_channel_recovery"][name] = int(value)
                with self.assertRaisesRegex(ContractValidationError, "CHANNEL_RECOVERY_POLICY_INVALID:"):
                    ContractBundle(ROOT, changed).validate_integrity()

    def test_real_drive_and_close_mission_reject_committed_current_omission(self) -> None:
        # Local clone of the CI checkout, never a network bootstrap. Keep the
        # tested Python code external to the fixture's deliberately damaged policy.
        subject = git(ROOT, "rev-parse", "HEAD")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "repo"
            git(ROOT, "clone", "--no-hardlinks", "--no-checkout", str(ROOT), str(root))
            git(root, "checkout", "-B", "main", subject)
            changed = remove_channel_extension(self.bundle.contracts)
            for name, relative in (
                ("harness_policy", "config/control/harness/harness-policy.v1.json"),
                ("continuation_policy", "config/control/harness/continuation-policy.v1.json"),
            ):
                (root / relative).write_text(json.dumps(changed[name]), encoding="utf-8")
                git(root, "add", relative)
            git(root, "-c", "user.name=Harness fixture", "-c", "user.email=harness@example.invalid",
                "commit", "-m", "negative control: omit channel recovery")
            git(root, "update-ref", "refs/remotes/origin/main", git(root, "rev-parse", "HEAD"))
            env = dict(os.environ, PYTHONPATH=str(ROOT / "scripts"))
            for mode in ("drive", "close-mission"):
                with self.subTest(mode=mode):
                    run = subprocess.run(
                        [sys.executable, "-m", "harness.cli", mode, "--root", str(root)],
                        cwd=root, env=env, capture_output=True, text=True,
                        encoding="utf-8", check=False, timeout=30,
                    )
                    self.assertEqual(3, run.returncode, run.stderr or run.stdout)
                    payload = json.loads(run.stdout.strip().splitlines()[-1])
                    self.assertFalse(payload["ok"])
                    self.assertIn("CHANNEL_RECOVERY_LEGACY_PROVENANCE_INVALID", payload["error"]["detail"])

    def test_agent_router_and_doctrine_expose_the_recovery_contract(self) -> None:
        agents = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
        doctrine = (ROOT / "docs/control/HARNESS_CHANNEL_RECOVERY_RU.md").read_text(encoding="utf-8")
        self.assertIn("TOOL / TRANSPORT / SESSION FAILURE IS NOT A MISSION TERMINAL", agents)
        self.assertIn("RECOVER FROM EXACT SHA / DURABLE LOCATOR", agents)
        self.assertIn("ResourceNotReadable", doctrine)
        self.assertIn("EXECUTOR_LOCAL_ROUTE_FAILURE", doctrine)
        self.assertIn("NON-TERMINAL MISSION MUST FAIL FORWARD", doctrine)
        self.assertIn("IMMUTABLE_LEGACY_SNAPSHOT_REQUIRED", doctrine)


if __name__ == "__main__":
    unittest.main()
