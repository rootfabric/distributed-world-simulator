"""Canonical contract loading and JSON Schema validation."""
from __future__ import annotations

import importlib.metadata
import json
import re
import subprocess
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

# Last canonical main before channel recovery was introduced. Legacy replay must
# prove ancestry to this immutable commit AND match its actual source snapshot.
# Missing fields, a caller-supplied generation number, or a copied old policy are
# not provenance. This fence is not an authority/dispatch override.
_CHANNEL_RECOVERY_LEGACY_CUTOFF = "127c732a56cc5c25d5712f24a7627ed4bb877374"


class ContractValidationError(ValueError):
    """Raised when a canonical contract or execution instance is invalid."""


def _validator(schema: dict[str, Any]):
    try:
        version = importlib.metadata.version("jsonschema")
        if version != "4.22.0":
            raise ContractValidationError(
                f"PINNED_DEPENDENCY_VERSION_REQUIRED:jsonschema={version}"
            )
        from jsonschema import Draft202012Validator, FormatChecker
    except (ModuleNotFoundError, importlib.metadata.PackageNotFoundError) as exc:
        raise ContractValidationError("PINNED_DEPENDENCY_MISSING:jsonschema==4.22.0") from exc
    return Draft202012Validator(schema, format_checker=FormatChecker())


def read_json(path: Path) -> dict[str, Any]:
    def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        value: dict[str, Any] = {}
        for key, item in pairs:
            if key in value:
                raise ContractValidationError(f"JSON_DUPLICATE_KEY:{path}:{key}")
            value[key] = item
        return value

    try:
        value = json.loads(
            path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicate_keys
        )
    except ContractValidationError:
        raise
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ContractValidationError(f"JSON_LOAD_FAILED:{path}:{exc}") from exc
    if not isinstance(value, dict):
        raise ContractValidationError(f"JSON_OBJECT_REQUIRED:{path}")
    return value


def _contract_paths(policy: dict[str, Any]) -> dict[str, str]:
    paths = {
        "harness_policy": "config/control/harness/harness-policy.v1.json",
        "project_registry": "config/control/project-program-registry.v1.json",
    }
    for name in (
        "project_goals", "checkpoint_catalog", "scheduler_policy",
        "work_order_schema", "event_schema", "project_epoch_schema",
        "risk_policy", "review_policy", "repair_doctrine",
        "evidence_map_schema", "human_attention_schema", "continuation_policy",
    ):
        paths[name] = policy[name]
    return paths


def _legacy_git(root: Path, *args: str) -> str:
    """Read existing local Git objects only; never fetch or trust replace refs."""
    try:
        return subprocess.check_output(
            ["git", "--no-replace-objects", *args], cwd=root, text=True,
            encoding="utf-8", stderr=subprocess.PIPE, timeout=10,
        ).strip()
    except (OSError, UnicodeError, subprocess.SubprocessError) as exc:
        raise ContractValidationError("CHANNEL_RECOVERY_LEGACY_PROVENANCE_INVALID") from exc


@dataclass(frozen=True)
class ContractBundle:
    root: Path
    contracts: dict[str, dict[str, Any]]
    # An explicit historical source is a claim, not proof. The legacy path below
    # verifies its immutable ancestry and every contract against local Git.
    source_commit: str | None = None

    @classmethod
    def load(
        cls, root: Path, *, reader: Callable[[Path], dict[str, Any]] = read_json,
        source_commit: str | None = None,
    ) -> "ContractBundle":
        """Load one snapshot; a pinned Git reader must declare its source commit."""
        policy_path = root / "config/control/harness/harness-policy.v1.json"
        policy = reader(policy_path)
        contracts = {
            name: reader(root / relative)
            for name, relative in _contract_paths(policy).items()
        }
        if (
            policy.get("execution_channel_recovery_revision") is None
            and source_commit is None and reader is read_json
        ):
            # A real old checkout may replay, but stripped current worktree data
            # cannot claim an old HEAD. No inference is made for arbitrary readers.
            source_commit = _legacy_git(root, "rev-parse", "--verify", "HEAD^{commit}")
        bundle = cls(root=root, contracts=contracts, source_commit=source_commit)
        bundle.validate_integrity()
        return bundle

    def _validate_legacy_channel_snapshot(self) -> None:
        source = self.source_commit
        if not isinstance(source, str) or not re.fullmatch(r"[0-9a-f]{40}", source):
            raise ContractValidationError("CHANNEL_RECOVERY_LEGACY_PROVENANCE_REQUIRED")
        _legacy_git(
            self.root, "merge-base", "--is-ancestor", source,
            _CHANNEL_RECOVERY_LEGACY_CUTOFF,
        )

        def read_pinned(relative: str) -> dict[str, Any]:
            def unique(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
                result: dict[str, Any] = {}
                for key, value in pairs:
                    if key in result:
                        raise ContractValidationError("CHANNEL_RECOVERY_LEGACY_SNAPSHOT_INVALID")
                    result[key] = value
                return result

            try:
                value = json.loads(
                    _legacy_git(self.root, "show", f"{source}:{relative}"),
                    object_pairs_hook=unique,
                )
            except (ValueError, TypeError) as exc:
                raise ContractValidationError("CHANNEL_RECOVERY_LEGACY_SNAPSHOT_INVALID") from exc
            if not isinstance(value, dict):
                raise ContractValidationError("CHANNEL_RECOVERY_LEGACY_SNAPSHOT_INVALID")
            return value

        pinned_policy = read_pinned("config/control/harness/harness-policy.v1.json")
        paths = _contract_paths(pinned_policy)
        if set(self.contracts) != set(paths):
            raise ContractValidationError("CHANNEL_RECOVERY_LEGACY_SNAPSHOT_MISMATCH:members")
        for name, relative in paths.items():
            expected = pinned_policy if name == "harness_policy" else read_pinned(relative)
            # JSON serialization preserves bool/int distinctions that Python dict
            # equality would erase. Compare the complete parsed snapshot, not just
            # the two policy files or a mutable registry generation field.
            try:
                actual_json = json.dumps(self.contracts[name], sort_keys=True, allow_nan=False)
                expected_json = json.dumps(expected, sort_keys=True, allow_nan=False)
            except (ValueError, TypeError) as exc:
                raise ContractValidationError("CHANNEL_RECOVERY_LEGACY_SNAPSHOT_INVALID") from exc
            if actual_json != expected_json:
                raise ContractValidationError(f"CHANNEL_RECOVERY_LEGACY_SNAPSHOT_MISMATCH:{name}")

    def validate_integrity(self) -> None:
        policy = self.contracts["harness_policy"]
        if policy.get("canonical_branch") != self.contracts["project_registry"].get(
            "canonical_branch"
        ):
            raise ContractValidationError("CANONICAL_BRANCH_MISMATCH")
        if policy.get("harness_revision") != self.contracts["project_goals"].get(
            "harness_revision"
        ):
            raise ContractValidationError("HARNESS_REVISION_MISMATCH")
        for name in (
            "work_order_schema",
            "event_schema",
            "project_epoch_schema",
            "evidence_map_schema",
            "human_attention_schema",
        ):
            schema = self.contracts[name]
            if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
                raise ContractValidationError(f"JSON_SCHEMA_DRAFT_REQUIRED:{name}")
        review = self.contracts["review_policy"]
        if review.get("risk_policy") != "config/control/harness/risk-policy.v1.json":
            raise ContractValidationError("REVIEW_RISK_POLICY_LINK_INVALID")
        if policy.get("checkpoint_catalog") != "config/control/harness/checkpoint-catalog.v1.json":
            raise ContractValidationError("CHECKPOINT_CATALOG_LINK_INVALID")
        if self.contracts["scheduler_policy"].get("harness_revision") != policy.get(
            "harness_revision"
        ):
            raise ContractValidationError("SCHEDULER_HARNESS_REVISION_MISMATCH")
        if self.contracts["checkpoint_catalog"].get("harness_revision") != policy.get(
            "harness_revision"
        ):
            raise ContractValidationError("CHECKPOINT_HARNESS_REVISION_MISMATCH")
        continuation = self.contracts["continuation_policy"]
        if continuation.get("continuation_layer_revision") != policy.get(
            "continuation_layer_revision"
        ):
            raise ContractValidationError("CONTINUATION_LAYER_REVISION_MISMATCH")

        expected_channel_revision = policy.get("execution_channel_recovery_revision")
        observed_channel_revision = continuation.get("execution_channel_recovery_revision")
        if expected_channel_revision is not None:
            if expected_channel_revision != "H0-CHANNEL-RECOVERY-2026-09-12-R1":
                raise ContractValidationError("CHANNEL_RECOVERY_POLICY_GENERATION_INVALID")
            if observed_channel_revision != expected_channel_revision:
                raise ContractValidationError("CHANNEL_RECOVERY_REVISION_INVALID")

            continuation_principles = continuation.get("principles")
            required_channel_principles = (
                "tool_or_transport_failure_is_not_mission_terminal",
                "ephemeral_tool_handles_are_not_durable_state",
                "executor_local_network_failure_is_route_failure_not_project_block",
                "unreadable_ephemeral_resource_must_be_refetched_from_durable_locator",
                "reasoning_or_session_channel_failure_does_not_change_project_state",
            )
            if not isinstance(continuation_principles, dict) or any(
                continuation_principles.get(name) is not True
                for name in required_channel_principles
            ):
                raise ContractValidationError("CHANNEL_RECOVERY_PRINCIPLES_INVALID")

            channel_recovery = continuation.get("execution_channel_recovery")
            if not isinstance(channel_recovery, dict):
                raise ContractValidationError("CHANNEL_RECOVERY_POLICY_MISSING")
            expected_channel_values = {
                "contract": "docs/control/HARNESS_CHANNEL_RECOVERY_RU.md",
                "mode": "FAIL_FORWARD_FROM_DURABLE_GIT",
                "tool_failure_is_terminal": False,
                "resource_handle_loss_is_terminal": False,
                "executor_network_failure_is_terminal": False,
                "reasoning_or_session_channel_failure_is_terminal": False,
                "hard_block_escalation_requires_autonomous_execution_proof": True,
            }
            for name, expected in expected_channel_values.items():
                actual = channel_recovery.get(name)
                if type(actual) is not type(expected) or actual != expected:
                    raise ContractValidationError(
                        f"CHANNEL_RECOVERY_POLICY_INVALID:{name}"
                    )

            expected_ephemeral_route = [
                "DISCARD_STALE_RESOURCE_HANDLE",
                "REFETCH_BY_DURABLE_LOCATOR",
                "VERIFY_EXACT_SUBJECT_IDENTITY",
                "RESUME_FROM_LAST_DURABLE_PREDICATE",
            ]
            if channel_recovery.get("ephemeral_resource_failure_route") != expected_ephemeral_route:
                raise ContractValidationError("CHANNEL_RESOURCE_RECOVERY_ROUTE_INVALID")

            expected_network_route = [
                "CAPTURE_FAILURE_SIGNATURE",
                "CLASSIFY_AS_EXECUTOR_LOCAL_ROUTE_FAILURE",
                "DO_NOT_INFER_REMOTE_SERVICE_OUTAGE",
                "DO_NOT_REPEAT_IDENTICAL_FAILED_ROUTE",
                "TRY_GITHUB_CONNECTOR_OR_EXISTING_EXACT_CHECKOUT",
                "TRY_REPOSITORY_OWNED_CI_IF_EXECUTION_IS_REQUIRED",
                "REANCHOR_EXACT_SUBJECT",
                "RESUME_WORK",
            ]
            if channel_recovery.get("executor_network_failure_route") != expected_network_route:
                raise ContractValidationError("CHANNEL_NETWORK_RECOVERY_ROUTE_INVALID")

            github_source_routing = channel_recovery.get("github_source_routing")
            if not isinstance(github_source_routing, dict):
                raise ContractValidationError("CHANNEL_GITHUB_ROUTING_MISSING")
            required_routing_flags = (
                "do_not_bootstrap_clone_from_network_restricted_container_when_connector_available",
                "container_dns_failure_does_not_prove_github_unavailable",
                "container_download_is_not_git_transport",
                "one_broken_github_route_is_not_hard_block_while_an_allowed_route_exists",
            )
            if any(github_source_routing.get(name) is not True for name in required_routing_flags):
                raise ContractValidationError("CHANNEL_GITHUB_ROUTING_INVALID")

            forbidden_stop_reasons = channel_recovery.get("forbidden_stop_reasons")
            required_forbidden_stop_reasons = {
                "CONNECTOR_RESOURCE_NOT_READABLE",
                "CONNECTOR_RESOURCE_NOT_FOUND",
                "TOOL_RESULT_HANDLE_EXPIRED",
                "CURRENT_EXECUTOR_DNS_FAILURE",
                "CURRENT_EXECUTOR_GITHUB_CLONE_FAILURE",
                "DOWNLOAD_ROUTE_SECURITY_REJECTION",
                "TRANSIENT_CONNECTOR_FAILURE",
                "LONG_REASONING_OR_TOOL_CHAIN_FAILURE",
                "PREFERRED_EXECUTOR_UNAVAILABLE",
                "CURRENT_EXECUTOR_WORKSPACE_LOSS",
            }
            if (
                not isinstance(forbidden_stop_reasons, list)
                or any(not isinstance(item, str) for item in forbidden_stop_reasons)
                or not required_forbidden_stop_reasons.issubset(set(forbidden_stop_reasons))
            ):
                raise ContractValidationError("CHANNEL_FORBIDDEN_STOP_REASONS_INVALID")

            long_chain = channel_recovery.get("long_tool_chain_guard")
            required_long_chain_flags = (
                "persist_completed_predicate_before_next_long_slice",
                "require_recovery_anchor_before_high_fanout_tool_phase",
                "reanchor_exact_subject_after_transient_channel_failure",
                "stale_resource_ids_must_not_cross_recovery_boundary",
                "chat_only_summary_is_not_recovery_anchor",
                "nonterminal_mission_must_fail_forward",
            )
            if not isinstance(long_chain, dict) or any(
                long_chain.get(name) is not True for name in required_long_chain_flags
            ):
                raise ContractValidationError("CHANNEL_LONG_TOOL_CHAIN_GUARD_INVALID")

            required_anchor_fields = {
                "EXACT_SUBJECT",
                "LAST_COMPLETED_DURABLE_PREDICATE",
                "KNOWN_FAILED_ROUTE_OR_FAILURE_SIGNATURE",
                "NEXT_ACTION",
                "ALLOWED_RECOVERY_ROUTE",
            }
            anchor_fields = channel_recovery.get("recovery_anchor_requires")
            if (
                not isinstance(anchor_fields, list)
                or any(not isinstance(item, str) for item in anchor_fields)
                or len(anchor_fields) != len(required_anchor_fields)
                or set(anchor_fields) != required_anchor_fields
            ):
                raise ContractValidationError("CHANNEL_RECOVERY_ANCHOR_REQUIREMENTS_INVALID")
        elif observed_channel_revision is not None:
            raise ContractValidationError("CHANNEL_RECOVERY_UNDECLARED_BY_HARNESS_POLICY")
        else:
            self._validate_legacy_channel_snapshot()

        if policy.get("git_transport_policy_revision") != "H0-GIT-TRANSPORT-2026-09-05-R1":
            raise ContractValidationError("GIT_TRANSPORT_POLICY_REVISION_INVALID")

        principles = policy.get("principles")
        if not isinstance(principles, dict):
            raise ContractValidationError("GIT_TRANSPORT_PRINCIPLES_MISSING")
        required_principles = (
            "github_actions_is_validation_and_evidence_plane_not_git_transport",
            "github_actions_git_transport_workarounds_are_forbidden",
            "normal_git_push_failure_must_be_diagnosed_before_external_automation",
        )
        if any(principles.get(name) is not True for name in required_principles):
            raise ContractValidationError("GIT_TRANSPORT_PRINCIPLES_INVALID")

        git_authority = policy.get("git_execution_authority")
        if not isinstance(git_authority, dict):
            raise ContractValidationError("GIT_EXECUTION_AUTHORITY_INVALID")
        if git_authority.get("revision") != "H0-GIT-AUTHORITY-2026-09-05-R2":
            raise ContractValidationError("GIT_EXECUTION_AUTHORITY_REVISION_INVALID")
        transport = git_authority.get("github_actions_transport_policy")
        if not isinstance(transport, dict):
            raise ContractValidationError("GITHUB_ACTIONS_TRANSPORT_POLICY_MISSING")

        required_transport_values = {
            "mode": "VALIDATION_AND_EVIDENCE_ONLY",
            "normal_git_transport_required": True,
            "may_replace_normal_git_transport": False,
            "may_reconstruct_or_publish_source_commits": False,
            "may_push_source_refs_as_fallback": False,
            "may_mutate_workflows_to_gain_git_write_capability": False,
            "exception_policy": (
                "EXPLICIT_HUMAN_APPROVED_REPOSITORY_AUTOMATION_DESIGN_ONLY_"
                "AND_NEVER_AS_GIT_TRANSPORT_FALLBACK"
            ),
        }
        for name, expected in required_transport_values.items():
            if transport.get(name) != expected:
                raise ContractValidationError(
                    f"GITHUB_ACTIONS_TRANSPORT_POLICY_INVALID:{name}"
                )

        required_workarounds = {
            "CREATE_OR_MODIFY_WORKFLOW_TO_BYPASS_NORMAL_GIT_PUSH",
            "RECONSTRUCT_OR_REPLAY_COMMITS_IN_ACTIONS_FOR_SOURCE_PUBLICATION",
            "PUSH_SOURCE_OR_STAGING_REFS_FROM_ACTIONS_AS_GIT_TRANSPORT_FALLBACK",
            "USE_ACTIONS_ARTIFACTS_OR_BUNDLES_AS_SUBSTITUTE_FOR_NORMAL_GIT_TRANSPORT",
            "ESCALATE_TO_ACTIONS_BEFORE_DIAGNOSING_EXACT_GIT_OR_AUTH_FAILURE",
        }
        forbidden_workarounds = transport.get("forbidden_workarounds")
        if (
            not isinstance(forbidden_workarounds, list)
            or not required_workarounds.issubset(set(forbidden_workarounds))
        ):
            raise ContractValidationError(
                "GITHUB_ACTIONS_TRANSPORT_FORBIDDEN_WORKAROUNDS_INVALID"
            )

        expected_failure_protocol = [
            "CAPTURE_EXACT_GIT_PUSH_ERROR",
            "VERIFY_REMOTE_URL_AND_TARGET_REF",
            "VERIFY_ACTIVE_GIT_OR_CONNECTOR_WRITE_AUTHORITY",
            "RETRY_NORMAL_NON_FORCE_PUSH_ONLY_IF_FAILURE_IS_TRANSIENT",
            "REPORT_EXTERNAL_TOOL_AUTH_REQUIRED_IF_PLATFORM_BLOCKS_WRITE",
            "DO_NOT_CREATE_OR_MUTATE_GITHUB_ACTIONS_AS_TRANSPORT_WORKAROUND",
        ]
        if transport.get("push_failure_protocol") != expected_failure_protocol:
            raise ContractValidationError(
                "GITHUB_ACTIONS_TRANSPORT_FAILURE_PROTOCOL_INVALID"
            )

        required_guards = {
            "NO_GITHUB_ACTIONS_AS_GIT_TRANSPORT_WORKAROUND",
            "NORMAL_GIT_FAILURE_MUST_BE_DIAGNOSED_BEFORE_ESCALATION",
            "NO_WORKFLOW_CREATION_OR_MUTATION_TO_BYPASS_GIT_AUTH",
        }
        guards = git_authority.get("guards")
        if not isinstance(guards, list) or not required_guards.issubset(set(guards)):
            raise ContractValidationError("GIT_TRANSPORT_GUARDS_INVALID")

        boundary = git_authority.get("external_tool_boundary")
        if (
            not isinstance(boundary, str)
            or "GITHUB_ACTIONS_GIT_TRANSPORT_WORKAROUND_FORBIDDEN" not in boundary
        ):
            raise ContractValidationError("GIT_TRANSPORT_EXTERNAL_BOUNDARY_INVALID")

    def validate_schema_definitions(self) -> None:
        """Require the pinned validator and valid schemas without an execution."""
        for name, schema in self.contracts.items():
            if name.endswith("_schema"):
                validator = _validator(schema)
                from jsonschema.exceptions import SchemaError

                try:
                    validator.check_schema(schema)
                except SchemaError as exc:
                    raise ContractValidationError(f"JSON_SCHEMA_INVALID:{name}:{exc}") from exc

    def validate(self, schema_name: str, instance: dict[str, Any], label: str) -> None:
        schema = self.contracts[schema_name]
        errors = sorted(
            _validator(schema).iter_errors(instance), key=lambda error: list(error.path)
        )
        if errors:
            detail = "; ".join(
                f"{'.'.join(str(part) for part in error.absolute_path) or '$'}:{error.message}"
                for error in errors[:3]
            )
            raise ContractValidationError(f"SCHEMA_INVALID:{label}:{detail}")
