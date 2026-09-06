"""Select declared execution resources for Harness role transitions."""
from __future__ import annotations

from pathlib import Path
from typing import Any

from .contracts import ContractValidationError, read_json

RESOURCE_PATH = "config/control/harness/execution-resources.v1.json"
RESOURCE_REVISION = "H0-EXECUTION-RESOURCES-2026-09-06-R1"


def validate_execution_resources(resources: dict[str, Any]) -> None:
    if resources.get("schema") != "distributed_world_simulator.execution_resources.v1":
        raise ContractValidationError("EXECUTION_RESOURCE_SCHEMA_INVALID")
    if resources.get("revision") != RESOURCE_REVISION:
        raise ContractValidationError("EXECUTION_RESOURCE_REVISION_INVALID")
    if resources.get("canonical_owner") != "main":
        raise ContractValidationError("EXECUTION_RESOURCE_OWNER_INVALID")

    principles = resources.get("principles")
    required_principles = (
        "execution_resource_is_not_role",
        "runner_identity_is_operational_not_canonical",
        "self_hosted_runner_is_validation_and_evidence_only",
        "github_actions_is_not_git_transport",
        "external_fork_execution_on_self_hosted_is_forbidden",
        "local_implementer_validation_remains_available",
        "exact_head_supersedes_queued_predecessor",
    )
    if not isinstance(principles, dict) or any(
        principles.get(name) is not True for name in required_principles
    ):
        raise ContractValidationError("EXECUTION_RESOURCE_PRINCIPLES_INVALID")

    routing = resources.get("routing")
    if not isinstance(routing, dict):
        raise ContractValidationError("EXECUTION_RESOURCE_ROUTING_INVALID")
    if routing.get("default_verifier_resource") != "DWS_LINUX_EXACT":
        raise ContractValidationError("EXECUTION_RESOURCE_DEFAULT_VERIFIER_INVALID")
    if routing.get("heavyweight_resource_capacity_is_authoritative") is not True:
        raise ContractValidationError("EXECUTION_RESOURCE_CAPACITY_POLICY_INVALID")

    resource_map = resources.get("resources")
    if not isinstance(resource_map, dict) or not {"LOCAL", "DWS_LINUX_EXACT"}.issubset(resource_map):
        raise ContractValidationError("EXECUTION_RESOURCE_MAP_INVALID")

    exact = resource_map["DWS_LINUX_EXACT"]
    if exact.get("provider") != "GITHUB_ACTIONS_SELF_HOSTED":
        raise ContractValidationError("EXECUTION_RESOURCE_PROVIDER_INVALID")
    if exact.get("repository") != "rootfabric/distributed-world-simulator":
        raise ContractValidationError("EXECUTION_RESOURCE_REPOSITORY_INVALID")
    if exact.get("capacity") != 1:
        raise ContractValidationError("EXECUTION_RESOURCE_CAPACITY_INVALID")

    labels = exact.get("runner_selector")
    required_labels = {"self-hosted", "Linux", "X64"}
    if not isinstance(labels, list) or not required_labels.issubset(set(labels)):
        raise ContractValidationError("EXECUTION_RESOURCE_LABELS_INVALID")
    preferred = exact.get("preferred_runner_selector_after_live_label_confirmation")
    preferred_labels = required_labels | {"dws-linux", "dws-godot-double"}
    if not isinstance(preferred, list) or not preferred_labels.issubset(set(preferred)):
        raise ContractValidationError("EXECUTION_RESOURCE_PREFERRED_LABELS_INVALID")
    if exact.get("selector_upgrade_condition") != "LIVE_RUNNER_CUSTOM_LABELS_CONFIRMED":
        raise ContractValidationError("EXECUTION_RESOURCE_SELECTOR_UPGRADE_INVALID")

    trust = exact.get("trust")
    if not isinstance(trust, dict):
        raise ContractValidationError("EXECUTION_RESOURCE_TRUST_INVALID")
    if trust.get("trusted_actors") != ["rootfabric"]:
        raise ContractValidationError("EXECUTION_RESOURCE_TRUSTED_ACTOR_INVALID")
    if trust.get("trusted_head_repositories") != ["rootfabric/distributed-world-simulator"]:
        raise ContractValidationError("EXECUTION_RESOURCE_TRUSTED_REPOSITORY_INVALID")
    if trust.get("allowed_events") != ["push", "workflow_dispatch"]:
        raise ContractValidationError("EXECUTION_RESOURCE_EVENT_POLICY_INVALID")
    if trust.get("pull_request_execution") is not False or trust.get("external_fork_execution") is not False:
        raise ContractValidationError("EXECUTION_RESOURCE_FORK_POLICY_INVALID")

    permissions = exact.get("github_permissions")
    if permissions != {"contents": "read"}:
        raise ContractValidationError("EXECUTION_RESOURCE_GITHUB_PERMISSIONS_INVALID")

    dispatch = exact.get("dispatch_policy")
    if not isinstance(dispatch, dict):
        raise ContractValidationError("EXECUTION_RESOURCE_DISPATCH_POLICY_INVALID")
    if dispatch.get("use_existing_approved_workflow_or_separate_validation_scope") is not True:
        raise ContractValidationError("EXECUTION_RESOURCE_APPROVED_WORKFLOW_POLICY_INVALID")
    for name in (
        "workflow_mutation_in_product_implementation_scope",
        "source_commit_or_ref_publication",
        "git_transport_fallback",
    ):
        if dispatch.get(name) is not False:
            raise ContractValidationError(f"EXECUTION_RESOURCE_DISPATCH_GUARD_INVALID:{name}")

    queue = resources.get("queue_policy")
    if not isinstance(queue, dict) or queue.get("max_dispatched_heavyweight_jobs_per_resource") != 1:
        raise ContractValidationError("EXECUTION_RESOURCE_QUEUE_CAPACITY_INVALID")
    if queue.get("on_subject_head_change") != "SUPERSEDE_AND_CANCEL_OLDER_QUEUED_EXACT_JOB":
        raise ContractValidationError("EXECUTION_RESOURCE_STALE_JOB_POLICY_INVALID")
    if queue.get("queued_job_is_not_pass") is not True or queue.get("in_progress_job_is_not_pass") is not True:
        raise ContractValidationError("EXECUTION_RESOURCE_PENDING_TRUTH_INVALID")


def load_execution_resources(root: Path) -> dict[str, Any]:
    resources = read_json(root / RESOURCE_PATH)
    validate_execution_resources(resources)
    return resources


def _resource(resources: dict[str, Any], name: str) -> dict[str, Any]:
    value = resources.get("resources", {}).get(name)
    if not isinstance(value, dict):
        raise ContractValidationError(f"EXECUTION_RESOURCE_UNKNOWN:{name}")
    return value


def build_execution_resource_plan(
    continuation: dict[str, Any],
    state: dict[str, Any],
    resources: dict[str, Any],
) -> dict[str, Any]:
    """Return deterministic routing for the next role, not a live availability probe."""
    validate_execution_resources(resources)
    actor = str(continuation.get("next_actor", ""))
    routing = resources.get("routing", {})
    preferences = routing.get("role_resource_preferences", {})
    names = preferences.get(actor, ["LOCAL"])
    if not isinstance(names, list) or not names:
        names = ["LOCAL"]

    selected = str(names[0])
    resource = _resource(resources, selected)
    required = actor == "VERIFIER" and selected != "LOCAL"
    plan: dict[str, Any] = {
        "required": required,
        "resource": selected,
        "provider": resource.get("provider"),
        "capacity": resource.get("capacity"),
        "capabilities": list(resource.get("capabilities", [])),
        "independent_verifier_environment": bool(
            resource.get("independent_verifier_environment", False)
        ),
        "live_availability": "NOT_PROBED_BY_HARNESS_GIT_STATE",
        "resource_is_not_role": True,
        "subject_head": state.get("repository", {}).get("implementation_head_sha"),
    }

    if resource.get("provider") == "GITHUB_ACTIONS_SELF_HOSTED":
        plan.update(
            {
                "repository": resource.get("repository"),
                "runner_selector": list(resource.get("runner_selector", [])),
                "preferred_runner_selector_after_live_label_confirmation": list(
                    resource.get("preferred_runner_selector_after_live_label_confirmation", [])
                ),
                "selector_upgrade_condition": resource.get("selector_upgrade_condition"),
                "trust": dict(resource.get("trust", {})),
                "github_permissions": dict(resource.get("github_permissions", {})),
                "dispatch_policy": dict(resource.get("dispatch_policy", {})),
                "queue_policy": dict(resources.get("queue_policy", {})),
                "fallback_policy": dict(resources.get("fallback_policy", {})),
            }
        )
    return plan
