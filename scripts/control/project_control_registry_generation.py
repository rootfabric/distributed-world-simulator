"""Exact canonical R3 registry-generation guard shared by PC0 entry points."""

from __future__ import annotations

from typing import Any


CANONICAL_R3_ARCHITECTURE_REVISION = "GLOBAL-P0-2026-08-12-R3-REFRESH-R1"
SUPPORTED_R3_REGISTRY_GENERATIONS = frozenset({79, 80})


def evaluate_canonical_r3_registry_generation(registry: dict[str, Any]) -> dict[str, Any]:
    """Return an explicit fail-closed decision for the canonical R3 registry.

    Registry generation is an authorization boundary, not a monotonic range.
    A future generation requires an explicit new control rule rather than being
    accepted implicitly by an ``>= 79`` comparison.
    """
    architecture_revision = registry.get("architecture_revision")
    generation = registry.get("registry_generation")
    if architecture_revision != CANONICAL_R3_ARCHITECTURE_REVISION:
        return {
            "allowed": False,
            "code": "UNSUPPORTED_CANONICAL_ARCHITECTURE_REVISION",
            "architecture_revision": architecture_revision,
            "registry_generation": generation,
            "supported_architecture_revision": CANONICAL_R3_ARCHITECTURE_REVISION,
            "supported_registry_generations": sorted(SUPPORTED_R3_REGISTRY_GENERATIONS),
        }
    if type(generation) is not int or generation not in SUPPORTED_R3_REGISTRY_GENERATIONS:
        return {
            "allowed": False,
            "code": "UNSUPPORTED_R3_REGISTRY_GENERATION",
            "architecture_revision": architecture_revision,
            "registry_generation": generation,
            "supported_architecture_revision": CANONICAL_R3_ARCHITECTURE_REVISION,
            "supported_registry_generations": sorted(SUPPORTED_R3_REGISTRY_GENERATIONS),
        }
    return {
        "allowed": True,
        "code": "EXACT_R3_REGISTRY_GENERATION_ALLOWED",
        "architecture_revision": architecture_revision,
        "registry_generation": generation,
        "supported_architecture_revision": CANONICAL_R3_ARCHITECTURE_REVISION,
        "supported_registry_generations": sorted(SUPPORTED_R3_REGISTRY_GENERATIONS),
    }


def require_canonical_r3_registry_generation(registry: dict[str, Any]) -> int:
    """Return the accepted generation or raise a deterministic guard error."""
    decision = evaluate_canonical_r3_registry_generation(registry)
    if not decision["allowed"]:
        raise AssertionError(f"{decision['code']}:{decision['registry_generation']}")
    return int(decision["registry_generation"])
