"""WP2 read-only surface presentation contract (contract-only, no runtime lease).

This package is the WP2.0 contract preparation allowed by
``config/world_packs/wp2_activation_state.v1.json`` while runtime activation is
BLOCKED. It contains no Godot runtime integration, no Matter writes, no
networking and no persistence: only DTOs, a pure resolver and fixtures.
"""
from .contract import (
    WorldSurfacePresentationInput,
    SurfacePresentationSelection,
    ClientFidelity,
    UnknownMaterialError,
    MissingBindingError,
    PhysicalFieldError,
    canonical_input_hash,
    validate_recipe_document,
)
from .resolver import SurfacePresentationResolver

__all__ = [
    "WorldSurfacePresentationInput",
    "SurfacePresentationSelection",
    "ClientFidelity",
    "UnknownMaterialError",
    "MissingBindingError",
    "PhysicalFieldError",
    "canonical_input_hash",
    "validate_recipe_document",
    "SurfacePresentationResolver",
]
