"""Generic surface presentation resolver bridge (non-runtime, pure function).

Pipeline direction is fixed:

    Canonical world / Matter
      -> derived representation surface sample (input DTO, produced upstream)
      -> WP2 read-only adapter (this module)
      -> surface family / variant selection
      -> renderer presentation

Never: WORLD PACKS deciding geology or creating Matter. The resolver only
reads the immutable input snapshot, the read-only Matter catalog snapshot and
a versioned recipe document, and emits a presentation-only selection.
"""
from __future__ import annotations

import copy
import hashlib
import json
import math
from pathlib import Path
from types import MappingProxyType
from typing import Mapping, Optional

from .contract import (
    ClientFidelity,
    FALLBACK_FIDELITY_TIER,
    MissingBindingError,
    SurfacePresentationSelection,
    UnknownMaterialError,
    WorldSurfacePresentationInput,
    validate_recipe_document,
)

REPO_ROOT = Path(__file__).resolve().parents[3]
CATALOG_SNAPSHOT_PATH = REPO_ROOT / "config" / "world_packs" / "presentation" / "matter_catalog_snapshot.v1.json"
RECIPES_PATH = REPO_ROOT / "config" / "world_packs" / "presentation" / "surface_recipes.v1.json"

# Alignment bands for mapping-mode selection. Contract A (R1): both vectors
# are normalized internally before the dot product, so alignment is the
# absolute cosine of the angle and is guaranteed to lie in [0, 1]. The bands
# use the ABSOLUTE cosine, so they are invariant to the sign of gravity
# (inward surfaces), to its absence (None -> triplanar) and never reference a
# global axis. Overhangs and cave ceilings live in the low-alignment band
# together with walls: presentation, not physics.
ALIGNMENT_PLANAR_MIN = 0.85
ALIGNMENT_TRIPLE_MIN = 0.35

# R6: domain separation prefix for variation tokens. The token is a pure
# function of the stable canonical spatial identity (body + surface + recipe
# + channel). It deliberately does NOT include world seed (the seed is
# already embedded in the stable surface_id spatial identity produced
# upstream), client fidelity, camera position, region owner or filesystem
# order. Two clients at different fidelities receive the SAME token for one
# surface/recipe/channel.
# R2.3: variation token width. The token is the FULL SHA-256 hexdigest
# (256-bit, 64 hex chars), comfortably above the 128-bit minimum required
# for a stable long-term surface variation identity. The previous 16-hex-char
# (64-bit) truncation is retired: collision risk over a huge world was not
# acceptable for a durable presentation identity.
#
# Semantics: the variation token is a DETERMINISTIC PRESENTATION VARIATION
# KEY. It is NOT canonical world identity (use canonical_input_hash) and NOT
# authority identity. Required properties:
#   same body/surface/recipe/channel -> same token
#   different body / surface / recipe / channel -> different token
#   different client fidelity         -> SAME token
# It never includes camera, filesystem state or region owner.
VARIATION_TOKEN_DOMAIN = "DWS-WP2-VARIATION-V1"
DEFAULT_VARIATION_CHANNEL = "surface-presentation"
VARIATION_TOKEN_HEX_WIDTH = 64  # full SHA-256; >= 128-bit identity requirement


def _read_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _sha256_hex(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _normalize(vec) -> tuple:
    length = math.sqrt(sum(c * c for c in vec))
    if not math.isfinite(length) or length == 0.0:
        # DTO construction already rejects this; guard the pure function too.
        raise ValueError(f"cannot normalize vector {vec!r}")
    return tuple(c / length for c in vec)


def surface_alignment(sample: WorldSurfacePresentationInput) -> float:
    """|cos(angle)| between surface normal and gravity, in [0, 1].

    Contract A: vectors are normalized internally; producers never have to
    supply unit vectors. Returns 0.0 when gravity is absent.
    """
    gravity = sample.gravity_direction
    if gravity is None:
        return 0.0
    n = _normalize(sample.surface_normal)
    g = _normalize(gravity)
    alignment = abs(sum(a * b for a, b in zip(n, g)))
    # Floating-point guard: cosine magnitude must stay within [0, 1].
    return min(1.0, max(0.0, alignment))


def select_mapping_mode(sample: WorldSurfacePresentationInput) -> str:
    """Frame-safe mapping mode: no global-Y, no radial-only, no gravity required."""
    if sample.gravity_direction is None:
        return "triplanar"
    alignment = surface_alignment(sample)
    if alignment >= ALIGNMENT_PLANAR_MIN:
        return "planar_projection"
    if alignment >= ALIGNMENT_TRIPLE_MIN:
        return "triplanar_blend"
    return "triplanar"


def _deep_freeze(node):
    """Recursively freeze a JSON-like structure: dict -> MappingProxyType,
    list -> tuple. The result shares no mutable container with the input."""
    if isinstance(node, dict):
        return MappingProxyType({key: _deep_freeze(value) for key, value in node.items()})
    if isinstance(node, list):
        return tuple(_deep_freeze(value) for value in node)
    return node


def _deep_thaw(node):
    """Recursively convert a frozen structure back into plain JSON-like
    dicts/lists. The result is a fresh copy: mutating it cannot reach the
    frozen internal state."""
    if isinstance(node, (MappingProxyType, dict)):
        return {key: _deep_thaw(value) for key, value in node.items()}
    if isinstance(node, (tuple, list)):
        return [_deep_thaw(value) for value in node]
    return node


def variation_token(body_id: str, surface_id: str, recipe_ref: str,
                    channel: str = DEFAULT_VARIATION_CHANNEL) -> str:
    """Domain-separated variation token (R6, R2.3).

    Identity semantics: this token is a deterministic PRESENTATION variation
    key — it is NOT canonical world identity and NOT authority identity.

    Key layout: ``DWS-WP2-VARIATION-V1|body_id|surface_id|recipe_ref|channel``.
    Same surface_id on different bodies yields different tokens; different
    client fidelities never change the token; different channels yield
    different tokens. The world seed is not part of the key because it is
    already embedded in the stable canonical spatial identity
    (body_id/surface_id) produced upstream.

    Width (R2.3): full SHA-256 hexdigest (64 hex chars, 256 bits) — at
    least the 128-bit minimum mandated for a durable stable variation
    identity over a huge world.
    """
    return _sha256_hex(
        f"{VARIATION_TOKEN_DOMAIN}|{body_id}|{surface_id}|{recipe_ref}|{channel}"
    )


class SurfacePresentationResolver:
    """Read-only resolver from Matter material families to presentation recipes.

    Immutable inputs (R2): the injected catalog snapshot and recipe document
    are deep-copied at construction into a recursively frozen internal
    representation. Mutating the injected originals afterwards, or the copies
    returned by ``catalog_snapshot`` / ``recipes_snapshot``, can never change
    resolver behavior.

    ``fallback_policy``:
      - ``neutral-fallback`` (default): an explicitly declared debug/neutral
        family is selected and the output records ``fallback_used=True``.
      - ``strict``: a missing binding raises :class:`MissingBindingError`.

    An unknown canonical Matter id NEVER falls back: it raises
    :class:`UnknownMaterialError`. Materials are canonical truth; presentation
    must not silently invent them.
    """

    def __init__(
        self,
        catalog_snapshot: Optional[Mapping[str, Mapping[str, str]]] = None,
        recipes: Optional[Mapping[str, object]] = None,
        fallback_policy: str = "neutral-fallback",
    ) -> None:
        if fallback_policy not in ("neutral-fallback", "strict"):
            raise ValueError(f"unknown fallback policy {fallback_policy!r}")
        catalog_data = copy.deepcopy(dict(catalog_snapshot)) if catalog_snapshot is not None \
            else _read_json(CATALOG_SNAPSHOT_PATH)
        recipes_data = copy.deepcopy(dict(recipes)) if recipes is not None \
            else _read_json(RECIPES_PATH)
        validate_recipe_document(recipes_data)
        self._catalog = _deep_freeze(catalog_data)
        self._recipes = _deep_freeze(recipes_data)
        self._fallback_policy = fallback_policy

    @property
    def catalog_snapshot(self) -> Mapping[str, Mapping[str, str]]:
        """Fresh deep copy: mutating the returned view cannot reach internal state."""
        return _deep_thaw(self._catalog)

    @property
    def recipes_snapshot(self) -> Mapping[str, object]:
        """Fresh deep copy of the validated recipe document (R2)."""
        return _deep_thaw(self._recipes)

    def resolve(
        self,
        sample: WorldSurfacePresentationInput,
        fidelity: ClientFidelity,
        recipe_ref: Optional[str] = None,
    ) -> SurfacePresentationSelection:
        ref = recipe_ref if recipe_ref is not None else sample.recipe_ref
        if not ref:
            raise ValueError("no presentation recipe reference: pass recipe_ref or set sample.recipe_ref")

        entry = self._catalog.get("materials", {}).get(sample.material_id)
        if entry is None:
            raise UnknownMaterialError(
                f"material id {sample.material_id!r} is not in the canonical Matter "
                "catalog snapshot; WORLD PACKS cannot invent canonical materials")

        recipe = self._recipes["recipes"].get(ref)
        if recipe is None:
            raise KeyError(f"unknown presentation recipe {ref!r}")

        family = entry["matter_family"]
        binding = recipe["bindings"].get(family)
        fallback_used = False
        if binding is None:
            if self._fallback_policy == "strict":
                raise MissingBindingError(
                    f"recipe {ref!r} has no binding for matter family {family!r}")
            binding = self._recipes["fallback_binding"]
            family = binding["surface_family"]
            fallback_used = True

        # R3: resolve the tier honestly. If the requested tier is absent, the
        # fallback tier is served and resolved_fidelity records the truth.
        variants = binding["variants"]
        requested_level = fidelity.level
        if requested_level in variants:
            resolved_level = requested_level
        else:
            resolved_level = FALLBACK_FIDELITY_TIER
            if resolved_level not in variants:
                raise KeyError(
                    f"recipe {ref!r} family {family!r} has neither the requested "
                    f"tier {requested_level!r} nor the fallback tier "
                    f"{FALLBACK_FIDELITY_TIER!r}")
        variant = variants[resolved_level]

        mapping_mode = select_mapping_mode(sample)
        scale = dict(binding.get("scale_parameters", {}))
        asset_refs = tuple(variant.get("asset_refs", ()))
        # Variation token identifies the canonical surface under this recipe
        # and channel; it is deliberately fidelity-independent (same surface,
        # any client) and body-scoped (no cross-body collisions).
        variation_seed = variation_token(sample.body_id, sample.surface_id, ref)
        # R4 Option A: lock over the EXACT presentation selection. Requested
        # fidelity is deliberately excluded — a fallback request resolves to
        # the same selection and must produce the same lock. This is a
        # selection identity, not a prepared-cache content identity.
        lock_blob = json.dumps({
            "recipe": ref, "recipe_version": recipe["version"],
            "surface_family": binding["surface_family"],
            "variant": variant["name"], "variant_version": variant["variant_version"],
            "resolved_fidelity": resolved_level,
            "mapping_mode": mapping_mode,
            "scale_parameters": scale,
            "resolved_asset_refs": list(asset_refs),
        }, sort_keys=True, separators=(",", ":"), allow_nan=False)

        return SurfacePresentationSelection(
            surface_family=binding["surface_family"],
            variant=variant["name"],
            variant_version=variant["variant_version"],
            requested_fidelity=requested_level,
            resolved_fidelity=resolved_level,
            mapping_mode=mapping_mode,
            scale_parameters=scale,
            presentation_state="ready",
            resolved_asset_refs=asset_refs,
            presentation_selection_lock=_sha256_hex(lock_blob),
            variation_seed=variation_seed,
            fallback_used=fallback_used,
        )
