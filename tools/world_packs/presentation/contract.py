"""WorldSurfacePresentationInput / SurfacePresentationSelection DTOs.

Read-only guarantee: the input is an immutable snapshot of canonical world
state plus a client capability. The adapter may never write it back; the
output selection carries presentation fields only (no mass, density,
strength, collision, authoritative geometry or network ownership).

Frame guarantee: ``surface_normal`` and ``gravity_direction`` are separate
optional vectors in body-fixed coordinates. No component of this contract may
assume global +Y up, ``normal == radial_up``, ``normal.dot(radial_up) > 0``, a
planet-only spherical exterior, or even the presence of gravity.
"""
from __future__ import annotations

from dataclasses import dataclass, field
import hashlib
import json
from types import MappingProxyType
from typing import Mapping, Optional, Sequence, Tuple

Vec3 = Tuple[float, float, float]

CLIENT_FIDELITIES = ("preview", "standard", "high")

# Fields a presentation selection must never carry. Presence is a contract
# violation regardless of value: WORLD PACKS does not own physical truth.
FORBIDDEN_OUTPUT_FIELDS = frozenset({
    "mass", "density", "strength", "yield", "collision", "collision_shape",
    "authoritative_geometry", "network_ownership", "mutation", "matter_write",
    "layer_depths", "physical_state",
})

# Physical keys a presentation recipe must never define (recipes cannot alter
# physical layer depths or any simulation truth).
FORBIDDEN_RECIPE_FIELDS = frozenset(FORBIDDEN_OUTPUT_FIELDS | {
    "composition", "material_id", "revision", "generator", "seed",
})


class UnknownMaterialError(ValueError):
    """Raised when the canonical Matter snapshot does not contain the material id."""


class MissingBindingError(LookupError):
    """Raised when no surface binding exists for a material family and the
    configured fallback policy is ``strict``."""


class PhysicalFieldError(ValueError):
    """Raised when a recipe or selection attempts to carry physical truth."""


@dataclass(frozen=True)
class ClientFidelity:
    """Client-local presentation capability. Never part of canonical world state."""
    level: str = "standard"

    def __post_init__(self) -> None:
        if self.level not in CLIENT_FIDELITIES:
            raise ValueError(
                f"unknown fidelity level {self.level!r}; expected one of {CLIENT_FIDELITIES}")


@dataclass(frozen=True)
class WorldSurfacePresentationInput:
    """Immutable read-only sample of one canonical surface point.

    Producers: canonical world / Matter / derived representation boundary.
    Consumers: the WP2 presentation resolver. There is intentionally no
    write-back path from this module to any producer.
    """
    body_id: str
    surface_id: str
    position_body_fixed: Vec3
    material_id: str
    composition: Mapping[str, float] = field(default_factory=dict)
    surface_state: str = ""
    matter_revision: int = 0
    surface_normal: Vec3 = (0.0, 0.0, 0.0)
    gravity_direction: Optional[Vec3] = None
    representation_revision: int = 0
    exposure_state: Optional[str] = None
    recipe_ref: str = ""

    def __post_init__(self) -> None:
        # Freeze mappings so no consumer can mutate the snapshot in place.
        object.__setattr__(self, "composition",
                           MappingProxyType(dict(self.composition)))
        for name in ("position_body_fixed", "surface_normal"):
            value = getattr(self, name)
            if len(value) != 3:
                raise ValueError(f"{name} must be a 3-vector, got {value!r}")
            object.__setattr__(self, name, tuple(float(x) for x in value))
        gravity = self.gravity_direction
        if gravity is not None:
            if len(gravity) != 3:
                raise ValueError(f"gravity_direction must be a 3-vector or None, got {gravity!r}")
            object.__setattr__(self, "gravity_direction",
                               tuple(float(x) for x in gravity))

    def canonical_state(self) -> dict:
        """Canonical-world part only: everything except the client-local recipe ref.

        The same ``canonical_state`` under different recipes or fidelities proves
        the world identity did not change.
        """
        return {
            "body_id": self.body_id,
            "surface_id": self.surface_id,
            "position_body_fixed": list(self.position_body_fixed),
            "material_id": self.material_id,
            "composition": dict(self.composition),
            "surface_state": self.surface_state,
            "matter_revision": self.matter_revision,
            "surface_normal": list(self.surface_normal),
            "gravity_direction": (None if self.gravity_direction is None
                                  else list(self.gravity_direction)),
            "representation_revision": self.representation_revision,
            "exposure_state": self.exposure_state,
        }


def canonical_input_hash(sample: WorldSurfacePresentationInput) -> str:
    """Stable SHA-256 over the canonical-world part of the input.

    Deliberately excludes ``recipe_ref`` and any client fidelity: changing the
    presentation recipe must never change this hash.
    """
    blob = json.dumps(sample.canonical_state(), sort_keys=True,
                      separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


@dataclass(frozen=True)
class SurfacePresentationSelection:
    """Presentation-only output. No world state, no physics, no authority."""
    surface_family: str
    variant: str
    variant_version: str
    fidelity: str
    mapping_mode: str
    scale_parameters: Mapping[str, float] = field(default_factory=dict)
    presentation_state: str = "ready"
    resolved_asset_refs: Tuple[str, ...] = ()
    presentation_lock: str = ""
    variation_seed: str = ""
    fallback_used: bool = False

    def __post_init__(self) -> None:
        object.__setattr__(self, "scale_parameters",
                           MappingProxyType(dict(self.scale_parameters)))
        object.__setattr__(self, "resolved_asset_refs",
                           tuple(self.resolved_asset_refs))
        _assert_no_physical_fields(self.__dict__)

    def to_json(self) -> dict:
        return {
            "surface_family": self.surface_family,
            "variant": self.variant,
            "variant_version": self.variant_version,
            "fidelity": self.fidelity,
            "mapping_mode": self.mapping_mode,
            "scale_parameters": dict(self.scale_parameters),
            "presentation_state": self.presentation_state,
            "resolved_asset_refs": list(self.resolved_asset_refs),
            "presentation_lock": self.presentation_lock,
            "variation_seed": self.variation_seed,
            "fallback_used": self.fallback_used,
        }


def _assert_no_physical_fields(namespace: Mapping[str, object]) -> None:
    bad = FORBIDDEN_OUTPUT_FIELDS.intersection(namespace)
    if bad:
        raise PhysicalFieldError(
            f"presentation selection carries physical fields {sorted(bad)}; "
            "WORLD PACKS owns presentation only")


def validate_recipe_document(doc: Mapping[str, object]) -> None:
    """Reject any recipe that tries to define physical truth."""
    def walk(node, path):
        if isinstance(node, Mapping):
            for key, value in node.items():
                if isinstance(key, str) and key.lower() in FORBIDDEN_RECIPE_FIELDS:
                    raise PhysicalFieldError(
                        f"recipe defines physical field {key!r} at {path}; "
                        "recipes cannot alter physical layer depths or simulation truth")
                walk(value, f"{path}.{key}")
    walk(doc, "$")
