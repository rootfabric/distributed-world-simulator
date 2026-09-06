"""WorldSurfacePresentationInput / SurfacePresentationSelection DTOs.

Read-only guarantee: the input is an immutable snapshot of canonical world
state plus a client capability. The adapter may never write it back; the
output selection carries presentation fields only (no mass, density,
strength, collision, authoritative geometry or network ownership).

Frame guarantee: ``surface_normal`` and ``gravity_direction`` are separate
optional vectors in body-fixed coordinates. No component of this contract may
assume global +Y up, ``normal == radial_up``, ``normal.dot(radial_up) > 0``, a
planet-only spherical exterior, or even the presence of gravity.

Frame vector contract (R1, contract A — normalize internally):
    ``surface_normal`` is a REQUIRED non-zero finite 3-vector.
    ``gravity_direction`` may be ``None``; otherwise it is a non-zero finite
    3-vector. Consumers normalize internally before any angular comparison;
    producers must NOT be required to supply unit vectors. Zero vectors,
    NaN and ±Infinity are rejected at construction.

Strict numeric canonicalization (R8): every numeric field (position, normal,
gravity, composition values) must be a finite real number. The canonical hash
additionally serializes with ``allow_nan=False`` so non-finite state can never
hash silently.

R2.1 — ``surface_normal`` has NO default. A caller that forgets the normal
must fail loudly at DTO construction; it must never silently receive a global
axis (+Z, +Y or any other implicit up-vector).

R2.4 — composition keys are part of the canonical hash, so they must be
non-empty UTF-8 strings. Arbitrary JSON-serializable keys (ints, bools,
None, empty or mixed-type keys) are rejected at construction because JSON
serialization of mixed keys is ambiguous and would break hash determinism.
The upstream derived-surface DTO does not yet define composition key
semantics (e.g. ``matter/<canonical-id>``); until it does, the durable note
``RUNTIME_COMPOSITION_KEY_SEMANTICS_PENDING_UPSTREAM_CONTRACT`` applies and
only the syntactic non-empty-string contract is enforced.
"""
from __future__ import annotations

from dataclasses import dataclass, field
import hashlib
import json
import math
import re
from types import MappingProxyType
from typing import Mapping, Optional, Sequence, Tuple

Vec3 = Tuple[float, float, float]

CLIENT_FIDELITIES = ("preview", "standard", "high")

# Tier used when the requested fidelity tier is absent for a binding. The
# output records the truth: requested_fidelity != resolved_fidelity.
FALLBACK_FIDELITY_TIER = "standard"

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

# R7: exact versioned recipe identity. Keys must be `recipe/<name>@X.Y.Z`
# with strict numeric semver; no `latest`, no floating tags.
_RECIPE_KEY_RE = re.compile(r"^recipe/(?P<name>[^@]+)@(?P<version>\d+\.\d+\.\d+)$")
_SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+$")

# R2.4 durable note: the real upstream derived-surface DTO does not yet
# define composition key semantics. Only the syntactic contract (non-empty
# UTF-8 string) is enforced; richer semantics (matter/<canonical-id>) must
# come from the upstream contract, not be invented here.
RUNTIME_COMPOSITION_KEY_SEMANTICS_PENDING_UPSTREAM_CONTRACT = (
    "RUNTIME_COMPOSITION_KEY_SEMANTICS_PENDING_UPSTREAM_CONTRACT: "
    "composition keys are validated as non-empty UTF-8 strings only; "
    "semantic key identity (matter/<canonical-id>) awaits the upstream "
    "derived-surface DTO contract"
)


class UnknownMaterialError(ValueError):
    """Raised when the canonical Matter snapshot does not contain the material id."""


class MissingBindingError(LookupError):
    """Raised when no surface binding exists for a material family and the
    configured fallback policy is ``strict``."""


class PhysicalFieldError(ValueError):
    """Raised when a recipe or selection attempts to carry physical truth."""


class MalformedVectorError(ValueError):
    """Raised when a frame vector is zero, non-finite or malformed (R1)."""


class MalformedCanonicalNumberError(ValueError):
    """Raised when canonical numeric state is non-finite or non-numeric (R8)."""


class RecipeVersionError(ValueError):
    """Raised when a recipe document key/version pair is not exact (R7)."""


class CompositionKeyError(ValueError):
    """Raised when a canonical composition key is not a non-empty string (R2.4)."""


def _is_real_number(value: object) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _require_finite(name: str, value: object) -> float:
    if not _is_real_number(value):
        raise MalformedCanonicalNumberError(
            f"{name} must be a real number, got {value!r}")
    number = float(value)
    if not math.isfinite(number):
        raise MalformedCanonicalNumberError(
            f"{name} must be finite, got {number!r}")
    return number


def _validate_vec3(name: str, value: object, allow_none: bool = False,
                   allow_zero: bool = False) -> Optional[Vec3]:
    if value is None:
        if allow_none:
            return None
        raise MalformedVectorError(f"{name} is required, got None")
    try:
        components = tuple(value)
    except TypeError:
        raise MalformedVectorError(f"{name} must be a 3-vector, got {value!r}")
    if len(components) != 3:
        raise MalformedVectorError(f"{name} must be a 3-vector, got {value!r}")
    numbers = tuple(_require_finite(f"{name}[{i}]", c) for i, c in enumerate(components))
    if not allow_zero and all(c == 0.0 for c in numbers):
        raise MalformedVectorError(
            f"{name} must be a non-zero vector; the zero vector has no direction")
    return numbers


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
    # R2.1: REQUIRED, no default. Placed before all defaulted fields so the
    # dataclass enforces it positionally/keyword-ally with no implicit axis.
    surface_normal: Vec3
    composition: Mapping[str, float] = field(default_factory=dict)
    surface_state: str = ""
    matter_revision: int = 0
    gravity_direction: Optional[Vec3] = None
    representation_revision: int = 0
    exposure_state: Optional[str] = None
    recipe_ref: str = ""

    def __post_init__(self) -> None:
        # Freeze mappings so no consumer can mutate the snapshot in place.
        frozen_composition = {}
        for key, raw in dict(self.composition).items():
            # R2.4: composition keys are part of the canonical hash. Only
            # non-empty strings keep the canonical JSON form deterministic;
            # ints, bools, None and empty/mixed keys are rejected outright.
            if not isinstance(key, str) or not key:
                raise CompositionKeyError(
                    f"composition key {key!r} must be a non-empty UTF-8 string; "
                    "arbitrary JSON keys would make the canonical hash "
                    "ambiguous (RUNTIME_COMPOSITION_KEY_SEMANTICS_"
                    "PENDING_UPSTREAM_CONTRACT)")
            frozen_composition[key] = _require_finite(
                f"composition[{key!r}]", raw)
        object.__setattr__(self, "composition",
                           MappingProxyType(frozen_composition))
        position = _validate_vec3("position_body_fixed", self.position_body_fixed,
                                  allow_zero=True)
        object.__setattr__(self, "position_body_fixed", position)
        # R1: surface_normal is required, non-zero, finite. gravity_direction
        # may be None; otherwise non-zero and finite.
        object.__setattr__(self, "surface_normal",
                           _validate_vec3("surface_normal", self.surface_normal))
        object.__setattr__(self, "gravity_direction",
                           _validate_vec3("gravity_direction", self.gravity_direction,
                                          allow_none=True))

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

    Deterministic strict JSON contract (R8): sorted keys, `,`/`:` separators,
    ``ensure_ascii=False``, UTF-8, and ``allow_nan=False`` so non-finite state
    raises instead of hashing silently. This is a bounded documented
    deterministic form, not a new RFC canonicalizer.
    """
    blob = json.dumps(sample.canonical_state(), sort_keys=True,
                      separators=(",", ":"), ensure_ascii=False,
                      allow_nan=False)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


@dataclass(frozen=True)
class SurfacePresentationSelection:
    """Presentation-only output. No world state, no physics, no authority.

    Fidelity semantics (R3): ``requested_fidelity`` is what the client asked
    for; ``resolved_fidelity`` is the tier actually selected. They differ when
    the requested tier is absent and the fallback tier was served (e.g. ice/ore
    fixtures that only define ``standard``). The output never claims the
    selected asset is of a higher tier than it is.

    ``presentation_selection_lock`` (R4, Option A): a hash over the EXACT
    presentation selection — recipe id/version, surface family, resolved
    variant/version, resolved fidelity, mapping mode, scale parameters and the
    exact resolved asset refs. It is a selection-identity lock, NOT a
    prepared-cache content identity: it does not pin asset content hashes, and
    it deliberately does not include the merely-requested fidelity (a
    fallback request resolves to the same selection, hence the same lock).
    """
    surface_family: str
    variant: str
    variant_version: str
    requested_fidelity: str
    resolved_fidelity: str
    mapping_mode: str
    scale_parameters: Mapping[str, float] = field(default_factory=dict)
    presentation_state: str = "ready"
    resolved_asset_refs: Tuple[str, ...] = ()
    presentation_selection_lock: str = ""
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
            "requested_fidelity": self.requested_fidelity,
            "resolved_fidelity": self.resolved_fidelity,
            "mapping_mode": self.mapping_mode,
            "scale_parameters": dict(self.scale_parameters),
            "presentation_state": self.presentation_state,
            "resolved_asset_refs": list(self.resolved_asset_refs),
            "presentation_selection_lock": self.presentation_selection_lock,
            "variation_seed": self.variation_seed,
            "fallback_used": self.fallback_used,
        }


def _assert_no_physical_fields(namespace: Mapping[str, object]) -> None:
    bad = FORBIDDEN_OUTPUT_FIELDS.intersection(namespace)
    if bad:
        raise PhysicalFieldError(
            f"presentation selection carries physical fields {sorted(bad)}; "
            "WORLD PACKS owns presentation only")


def _validate_recipe_version_entry(key: str, doc: Mapping[str, object]) -> None:
    match = _RECIPE_KEY_RE.match(key)
    if match is None:
        raise RecipeVersionError(
            f"recipe key {key!r} must be of the exact form "
            "'recipe/<name>@X.Y.Z' with strict numeric semver; "
            "missing @version, floating tags and 'latest' are rejected")
    declared = doc.get("version")
    if not isinstance(declared, str) or not _SEMVER_RE.match(declared):
        raise RecipeVersionError(
            f"recipe {key!r} must declare version as a strict semver string, "
            f"got {declared!r}")
    if declared != match.group("version"):
        raise RecipeVersionError(
            f"recipe key {key!r} declares version {declared!r}; "
            "key version and document version must match exactly")


def validate_recipe_document(doc: Mapping[str, object]) -> None:
    """Validate a recipe document.

    Rejects (R7): keys not of the exact form ``recipe/<name>@X.Y.Z``,
    missing/malformed ``version``, key/version mismatch and duplicate logical
    identity (the same ``recipe/<name>`` appearing more than once). No
    ``latest`` alias exists.

    Rejects any recipe that tries to define physical truth at ANY depth of the
    JSON-like tree (R2.2): the forbidden-field walker recurses through
    mappings AND sequence containers (list/tuple), so a physical field hidden
    inside a nested list (or list-of-lists) is rejected exactly like a
    top-level one.
    """
    seen_logical_names = set()
    recipes = doc.get("recipes", {}) if isinstance(doc, Mapping) else {}
    if not isinstance(recipes, Mapping):
        raise RecipeVersionError("'recipes' must be a mapping of recipe documents")
    for key, value in recipes.items():
        _validate_recipe_version_entry(key, value if isinstance(value, Mapping) else {})
        logical = _RECIPE_KEY_RE.match(key).group("name")
        if logical in seen_logical_names:
            raise RecipeVersionError(
                f"duplicate logical recipe identity 'recipe/{logical}': "
                "each recipe name may appear exactly once per document")
        seen_logical_names.add(logical)

    def walk(node, path):
        if isinstance(node, Mapping):
            for key, value in node.items():
                if isinstance(key, str) and key.lower() in FORBIDDEN_RECIPE_FIELDS:
                    raise PhysicalFieldError(
                        f"recipe defines physical field {key!r} at {path}; "
                        "recipes cannot alter physical layer depths or simulation truth")
                walk(value, f"{path}.{key}")
        elif isinstance(node, (list, tuple)):
            # R2.2: recurse into sequence containers. A forbidden field
            # wrapped in a nested list must not escape the walker.
            for index, value in enumerate(node):
                walk(value, f"{path}[{index}]")
    walk(doc, "$")
