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

import hashlib
import json
from pathlib import Path
from typing import Mapping, Optional

from .contract import (
    ClientFidelity,
    MissingBindingError,
    SurfacePresentationSelection,
    UnknownMaterialError,
    WorldSurfacePresentationInput,
    validate_recipe_document,
)

REPO_ROOT = Path(__file__).resolve().parents[3]
CATALOG_SNAPSHOT_PATH = REPO_ROOT / "config" / "world_packs" / "presentation" / "matter_catalog_snapshot.v1.json"
RECIPES_PATH = REPO_ROOT / "config" / "world_packs" / "presentation" / "surface_recipes.v1.json"

# Alignment bands for mapping-mode selection. They use the ABSOLUTE dot of the
# surface normal with the gravity direction, so they are invariant to the sign
# of gravity (inward surfaces), to its absence (zero/weak gravity -> triplanar)
# and never reference a global axis. Overhangs and cave ceilings live in the
# low-alignment band together with walls: presentation, not physics.
ALIGNMENT_PLANAR_MIN = 0.85
ALIGNMENT_TRIPLE_MIN = 0.35


def _read_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _sha256_hex(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def select_mapping_mode(sample: WorldSurfacePresentationInput) -> str:
    """Frame-safe mapping mode: no global-Y, no radial-only, no gravity required."""
    gravity = sample.gravity_direction
    if gravity is None:
        return "triplanar"
    dot = sum(n * g for n, g in zip(sample.surface_normal, gravity))
    alignment = abs(dot)
    if alignment >= ALIGNMENT_PLANAR_MIN:
        return "planar_projection"
    if alignment >= ALIGNMENT_TRIPLE_MIN:
        return "triplanar_blend"
    return "triplanar"


class SurfacePresentationResolver:
    """Read-only resolver from Matter material families to presentation recipes.

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
        self._catalog = dict(catalog_snapshot) if catalog_snapshot is not None else _read_json(CATALOG_SNAPSHOT_PATH)
        self._recipes = dict(recipes) if recipes is not None else _read_json(RECIPES_PATH)
        validate_recipe_document(self._recipes)
        self._fallback_policy = fallback_policy

    @property
    def catalog_snapshot(self) -> Mapping[str, Mapping[str, str]]:
        return dict(self._catalog)

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

        variant = binding["variants"].get(fidelity.level) or binding["variants"]["standard"]
        mapping_mode = select_mapping_mode(sample)
        scale = dict(binding.get("scale_parameters", {}))
        # Variation token identifies the canonical surface under this recipe;
        # it is deliberately fidelity-independent (same surface, any client).
        variation_seed = _sha256_hex(f"{sample.surface_id}|{ref}")[:16]
        lock_blob = json.dumps({
            "recipe": ref, "recipe_version": recipe["version"],
            "variant": variant["name"], "variant_version": variant["variant_version"],
            "fidelity": fidelity.level, "mapping_mode": mapping_mode,
            "scale_parameters": scale,
        }, sort_keys=True, separators=(",", ":"))

        return SurfacePresentationSelection(
            surface_family=binding["surface_family"],
            variant=variant["name"],
            variant_version=variant["variant_version"],
            fidelity=fidelity.level,
            mapping_mode=mapping_mode,
            scale_parameters=scale,
            presentation_state="ready",
            resolved_asset_refs=tuple(variant.get("asset_refs", ())),
            presentation_lock=_sha256_hex(lock_blob),
            variation_seed=variation_seed,
            fallback_used=fallback_used,
        )
