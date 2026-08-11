"""Canonical contract loading and JSON Schema validation.

The harness deliberately has no private copy of control policy.  Every path
below is named by ``harness-policy.v1.json`` or is the main-owned registry
needed to evaluate an execution instance.
"""
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
            raise ContractValidationError(f"PINNED_DEPENDENCY_VERSION_REQUIRED:jsonschema={version}")
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
        value = json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=reject_duplicate_keys)
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
        }
        contracts = {name: read_json(root / relative) for name, relative in required.items()}
        bundle = cls(root=root, contracts=contracts)
        bundle.validate_integrity()
        return bundle

    def validate_integrity(self) -> None:
        policy = self.contracts["harness_policy"]
        if policy.get("canonical_branch") != self.contracts["project_registry"].get("canonical_branch"):
            raise ContractValidationError("CANONICAL_BRANCH_MISMATCH")
        if policy.get("harness_revision") != self.contracts["project_goals"].get("harness_revision"):
            raise ContractValidationError("HARNESS_REVISION_MISMATCH")
        for name in ("work_order_schema", "event_schema", "project_epoch_schema", "evidence_map_schema", "human_attention_schema"):
            schema = self.contracts[name]
            if schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema":
                raise ContractValidationError(f"JSON_SCHEMA_DRAFT_REQUIRED:{name}")
        review = self.contracts["review_policy"]
        if review.get("risk_policy") != "config/control/harness/risk-policy.v1.json":
            raise ContractValidationError("REVIEW_RISK_POLICY_LINK_INVALID")
        if policy.get("checkpoint_catalog") != "config/control/harness/checkpoint-catalog.v1.json":
            raise ContractValidationError("CHECKPOINT_CATALOG_LINK_INVALID")
        if self.contracts["scheduler_policy"].get("harness_revision") != policy.get("harness_revision"):
            raise ContractValidationError("SCHEDULER_HARNESS_REVISION_MISMATCH")
        if self.contracts["checkpoint_catalog"].get("harness_revision") != policy.get("harness_revision"):
            raise ContractValidationError("CHECKPOINT_HARNESS_REVISION_MISMATCH")

    def validate(self, schema_name: str, instance: dict[str, Any], label: str) -> None:
        schema = self.contracts[schema_name]
        errors = sorted(_validator(schema).iter_errors(instance), key=lambda error: list(error.path))
        if errors:
            detail = "; ".join(
                f"{'.'.join(str(part) for part in error.absolute_path) or '$'}:{error.message}"
                for error in errors[:3]
            )
            raise ContractValidationError(f"SCHEMA_INVALID:{label}:{detail}")
