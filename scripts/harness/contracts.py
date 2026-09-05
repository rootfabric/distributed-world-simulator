"""Canonical contract loading and JSON Schema validation."""
from __future__ import annotations

import importlib.metadata
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any


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


@dataclass(frozen=True)
class ContractBundle:
    root: Path
    contracts: dict[str, dict[str, Any]]

    @classmethod
    def load(cls, root: Path) -> "ContractBundle":
        harness_root = root / "config" / "control" / "harness"
        policy_path = harness_root / "harness-policy.v1.json"
        policy = read_json(policy_path)
        required = {
            "harness_policy": "config/control/harness/harness-policy.v1.json",
            "project_registry": "config/control/project-program-registry.v1.json",
            "project_goals": policy["project_goals"],
            "checkpoint_catalog": policy["checkpoint_catalog"],
            "scheduler_policy": policy["scheduler_policy"],
            "work_order_schema": policy["work_order_schema"],
            "event_schema": policy["event_schema"],
            "project_epoch_schema": policy["project_epoch_schema"],
            "risk_policy": policy["risk_policy"],
            "review_policy": policy["review_policy"],
            "repair_doctrine": policy["repair_doctrine"],
            "evidence_map_schema": policy["evidence_map_schema"],
            "human_attention_schema": policy["human_attention_schema"],
            "continuation_policy": policy["continuation_policy"],
        }
        contracts = {
            name: read_json(root / relative) for name, relative in required.items()
        }
        bundle = cls(root=root, contracts=contracts)
        bundle.validate_integrity()
        return bundle

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
