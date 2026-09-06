"""Validate control JSON and generation against the exact CI event baseline."""
from __future__ import annotations

import os
import re
import subprocess
from pathlib import Path
from typing import Any

from .contracts import ContractBundle, ContractValidationError, _validator, read_json
from .mission import _parse_json_object

REGISTRY = "config/control/project-program-registry.v1.json"
SCHEDULER = "config/control/harness/scheduler-policy.v1.json"
REQUIRED_JSON = (
    "config/control/project-control-policy.v1.json", REGISTRY,
    "config/control/architecture-ownership.v1.json",
    "config/control/directional-watch-clearances.v1.json",
    "config/architecture/global-program-roadmap.v1.json",
    "config/control/harness/v0-product-train-policy.v1.json",
    "config/control/harness/v0-current-work-map.v1.json",
    "config/control/harness/v0-p7-matter-production-convergence-plan.v1.json",
    "validation/harness/control-development-output.schema.v1.json",
)


def _git(root: Path, *args: str) -> str:
    result = subprocess.run(["git", *args], cwd=root, text=True, capture_output=True)
    if result.returncode:
        raise ContractValidationError(f"GIT_CONTROL_VALIDATION_FAILED:{args[0]}:{result.stderr.strip()}")
    return result.stdout.rstrip("\n")


def comparison_base(root: Path, event_name: str, event: dict[str, Any]) -> str | None:
    """A push compares its pre-push tree, never the already advanced origin/main."""
    if event_name == "push" and event.get("ref") == "refs/heads/main":
        before = event.get("before")
        if before and before != "0" * 40:
            if not isinstance(before, str) or not re.fullmatch(r"[0-9a-f]{40}", before):
                raise ContractValidationError("INVALID_PUSH_BEFORE_SHA")
            return _git(root, "rev-parse", "--verify", f"{before}^{{commit}}")
        if before == "0" * 40:
            return None  # Initial branch push: enumerate current tracked control JSON.
        parents = _git(root, "rev-list", "--parents", "-n", "1", "HEAD").split()
        return parents[1] if len(parents) > 1 else None
    return _git(root, "rev-parse", "--verify", "origin/main^{commit}")


def changed_paths(root: Path, base: str | None) -> list[str]:
    if base is None:
        raw = _git(root, "ls-files", "-z", "--", "config/control", "config/architecture", "validation/harness")
    else:
        raw = _git(root, "diff", "--name-only", "--diff-filter=ACMR", "-z", base, "HEAD", "--", "*.json")
    return [path for path in raw.split("\0") if path.endswith(".json")]


def validate_generation(root: Path, base: str | None, changed: list[str]) -> int:
    registry = read_json(root / REGISTRY)
    scheduler = read_json(root / SCHEDULER)
    generation = registry.get("registry_generation")
    lease_generation = scheduler.get("pre_h0_3_runtime_mutation_lease", {}).get("effective_registry_generation")
    if type(generation) is not int or generation < 1:
        raise ContractValidationError(f"REGISTRY_GENERATION_INVALID:{generation}")
    if type(lease_generation) is not int or lease_generation != generation:
        raise ContractValidationError("REGISTRY_LEASE_GENERATION_MISMATCH")
    if base is not None:
        prior = _parse_json_object(_git(root, "show", f"{base}:{REGISTRY}"), REGISTRY).get("registry_generation")
        if type(prior) is not int or prior < 1:
            raise ContractValidationError(f"BASE_REGISTRY_GENERATION_INVALID:{prior}")
        if generation < prior:
            raise ContractValidationError(f"REGISTRY_GENERATION_ROLLBACK:{generation}<{prior}")
        if {REGISTRY, SCHEDULER}.intersection(changed) and generation <= prior:
            raise ContractValidationError(f"REGISTRY_GENERATION_ADVANCE_REQUIRED:{generation}<={prior}")
    return generation


def validate_control(root: Path, *, event_name: str = "", event: dict[str, Any] | None = None) -> dict[str, Any]:
    root = root.resolve()
    base = comparison_base(root, event_name, event or {})
    changed = changed_paths(root, base)
    bundle = ContractBundle.load(root)
    bundle.validate_schema_definitions()
    paths = set(REQUIRED_JSON).union(changed)
    # The bundle's policy-owned contracts have already had strict duplicate-key
    # parsing and integrity checks. Include their schemas in the printed record.
    for path in sorted(paths):
        value = read_json(root / path)
        if "$schema" in value:
            _validator(value).check_schema(value)
        print(f"JSON DUPLICATE-KEY VALIDATION OK: {path}")
    generation = validate_generation(root, base, changed)
    print(f"CONTROL COMPARISON BASE: {base or 'INITIAL_PUSH_ALL_CONTROL_JSON'}")
    print(f"CANDIDATE REGISTRY GENERATION OK: {generation}")
    return {"comparison_base": base, "registry_generation": generation, "validated_json_paths": sorted(paths)}


def main() -> None:
    event_path = os.environ.get("GITHUB_EVENT_PATH")
    event = read_json(Path(event_path)) if event_path else {}
    validate_control(Path.cwd(), event_name=os.environ.get("GITHUB_EVENT_NAME", ""), event=event)


if __name__ == "__main__":
    main()
