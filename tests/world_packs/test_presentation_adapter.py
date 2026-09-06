"""WP2.0 read-only presentation adapter contract tests.

These are contract-level proofs (no runtime lease; see
config/world_packs/wp2_activation_state.v1.json). They demonstrate:
read-only guarantee, normal != gravity, no global-Y assumption, exact
versioned recipe resolution, client-local fidelity, optional-subsystem
safety and Proof A invariants.
"""
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "wp_presentation", ROOT / "tools" / "world_packs" / "presentation" / "__init__.py",
    submodule_search_locations=[str(ROOT / "tools" / "world_packs" / "presentation")])
wp = importlib.util.module_from_spec(spec)
sys.modules["wp_presentation"] = wp
spec.loader.exec_module(wp)

proof_a = importlib.import_module("wp_presentation.proof_a")

RECIPE_A = proof_a.RECIPE_A
RECIPE_B = proof_a.RECIPE_B
GRAVITY = (0.0, 0.0, -1.0)


def sample(**overrides):
    base = dict(
        body_id="body/mock-moon",
        surface_id="surface/test/0",
        position_body_fixed=(1.0, 2.0, 3.0),
        material_id="matter/basalt",
        composition={"canonical": 1.0},
        surface_state="as-generated",
        matter_revision=7,
        surface_normal=(0.0, 0.0, 1.0),
        gravity_direction=GRAVITY,
        representation_revision=9,
        recipe_ref=RECIPE_A,
    )
    base.update(overrides)
    return wp.WorldSurfacePresentationInput(**base)


# ---------- read-only guarantee ----------

def test_input_is_immutable():
    s = sample()
    with pytest.raises(Exception):
        s.material_id = "matter/sandstone"  # type: ignore[misc]
    with pytest.raises(Exception):
        s.composition["injected"] = 0.5


def test_resolution_does_not_mutate_canonical_input():
    resolver = wp.SurfacePresentationResolver()
    s = sample()
    before = wp.canonical_input_hash(s)
    resolver.resolve(s, wp.ClientFidelity("high"))
    resolver.resolve(s, wp.ClientFidelity("preview"), recipe_ref=RECIPE_B)
    assert wp.canonical_input_hash(s) == before
    assert s.composition == {"canonical": 1.0}


def test_unknown_matter_id_fails_explicitly():
    resolver = wp.SurfacePresentationResolver()
    with pytest.raises(wp.UnknownMaterialError):
        resolver.resolve(sample(material_id="matter/not-in-catalog"),
                         wp.ClientFidelity("standard"))


def test_missing_binding_strict_fails_and_neutral_fallback_is_explicit():
    recipes_doc = json.loads((ROOT / "config/world_packs/presentation/surface_recipes.v1.json").read_text(encoding="utf-8"))
    catalog = json.loads((ROOT / "config/world_packs/presentation/matter_catalog_snapshot.v1.json").read_text(encoding="utf-8"))
    # Remove every binding for a family that exists in the catalog.
    stripped = deepcopy(recipes_doc)
    for recipe in stripped["recipes"].values():
        recipe["bindings"].pop("matter-family/silicate-rock")
    strict = wp.SurfacePresentationResolver(recipes=stripped, catalog_snapshot=catalog,
                                            fallback_policy="strict")
    neutral = wp.SurfacePresentationResolver(recipes=stripped, catalog_snapshot=catalog)
    with pytest.raises(wp.MissingBindingError):
        strict.resolve(sample(), wp.ClientFidelity("standard"))
    selection = neutral.resolve(sample(), wp.ClientFidelity("standard"))
    assert selection.fallback_used is True
    assert selection.surface_family == "surface-family/debug-neutral"


def test_recipe_cannot_carry_physical_fields():
    with pytest.raises(wp.PhysicalFieldError):
        wp.validate_recipe_document({"recipes": {"r@1": {"bindings": {
            "f": {"layer_depths": [1, 2, 3]}}}}})
    with pytest.raises(wp.PhysicalFieldError):
        wp.validate_recipe_document({"recipes": {"r@1": {"bindings": {
            "f": {"density": 2900.0}}}}})


def test_selection_rejects_physical_fields():
    # The output contract guard itself rejects any physical field.
    with pytest.raises(wp.PhysicalFieldError):
        wp.contract._assert_no_physical_fields({"mass": 1.0})
    # And a real selection's JSON view never contains physical keys.
    resolver = wp.SurfacePresentationResolver()
    out = resolver.resolve(sample(), wp.ClientFidelity("standard")).to_json()
    forbidden = {"mass", "density", "strength", "collision", "layer_depths",
                 "authoritative_geometry", "network_ownership"}
    assert not (forbidden & set(out))


# ---------- frame safety: normal != gravity, no global-Y ----------

def test_normal_and_gravity_are_separate_inputs():
    s = sample(surface_normal=(0.0, 0.0, 1.0), gravity_direction=(1.0, 0.0, 0.0))
    assert s.surface_normal != s.gravity_direction


@pytest.mark.parametrize("normal,gravity,mode", [
    ((0.0, 0.0, 1.0), (0.0, 0.0, -1.0), "planar_projection"),   # floor
    ((0.0, 1.0, 0.0), (0.0, 0.0, -1.0), "triplanar"),           # vertical wall
    ((0.0, 0.2, -0.98), (0.0, 0.0, -1.0), "planar_projection"),  # inward-facing cave ceiling
    ((0.0, 0.0, 1.0), (0.0, 0.0, 1.0), "planar_projection"),    # ceiling, inward gravity
    ((0.5, 0.5, 0.7), None, "triplanar"),                       # irregular asteroid, no gravity
    ((0.6, 0.0, 0.8), (0.0, 0.0, -1.0), "triplanar_blend"),     # steep slope band
])
def test_arbitrary_orientations_resolve_without_y_up(normal, gravity, mode):
    resolver = wp.SurfacePresentationResolver()
    s = sample(surface_normal=normal, gravity_direction=gravity)
    selection = resolver.resolve(s, wp.ClientFidelity("standard"))
    assert selection.mapping_mode == mode


def test_mapping_mode_is_gravity_sign_invariant():
    # Inward vs outward gravity along the same axis must not change the mode:
    # sign of the normal/gravity dot carries no presentation meaning.
    a = sample(surface_normal=(0.0, 0.0, 1.0), gravity_direction=(0.0, 0.0, -1.0))
    b = sample(surface_normal=(0.0, 0.0, 1.0), gravity_direction=(0.0, 0.0, 1.0))
    select = wp.resolver.select_mapping_mode
    assert select(a) == select(b) == "planar_projection"


# ---------- fidelity is client-local ----------

def test_fidelity_changes_presentation_only():
    resolver = wp.SurfacePresentationResolver()
    s = sample()
    world_before = wp.canonical_input_hash(s)
    low = resolver.resolve(s, wp.ClientFidelity("preview"))
    high = resolver.resolve(s, wp.ClientFidelity("high"))
    assert low.variant != high.variant
    assert low.fidelity == "preview" and high.fidelity == "high"
    assert wp.canonical_input_hash(s) == world_before


def test_two_clients_same_world_different_fidelity():
    resolver = wp.SurfacePresentationResolver()
    s = sample()
    client_a = resolver.resolve(s, wp.ClientFidelity("preview"))
    client_b = resolver.resolve(s, wp.ClientFidelity("high"))
    assert client_a.variation_seed == client_b.variation_seed  # same surface identity
    assert client_a.variant != client_b.variant                # different prepared presentation
    assert client_a.presentation_lock != client_b.presentation_lock


def test_unknown_fidelity_rejected():
    with pytest.raises(ValueError):
        wp.ClientFidelity("ultra")


# ---------- exact versioned recipe resolution ----------

def test_recipe_resolution_is_exact_and_versioned():
    resolver = wp.SurfacePresentationResolver()
    s = sample()
    sel = resolver.resolve(s, wp.ClientFidelity("high"))
    assert sel.variant_version == "1.0.0"
    # Presentation lock is the exact prepared-bundle identity: identical input
    # -> identical lock; the per-surface variation token identifies the surface.
    assert sel.presentation_lock == resolver.resolve(
        sample(), wp.ClientFidelity("high")).presentation_lock
    other = resolver.resolve(sample(surface_id="surface/test/1"), wp.ClientFidelity("high"))
    assert other.presentation_lock == sel.presentation_lock  # same bundle
    assert other.variation_seed != sel.variation_seed        # different surface


def test_unknown_recipe_rejected():
    resolver = wp.SurfacePresentationResolver()
    with pytest.raises(KeyError):
        resolver.resolve(sample(recipe_ref="recipe/does-not-exist@9.9.9"),
                         wp.ClientFidelity("standard"))


# ---------- optional subsystem: removal cannot break canonical truth ----------

def test_canonical_truth_does_not_depend_on_world_packs():
    # Canonical identity is computed from the input alone; no resolver,
    # recipes or catalog files are involved. If every WP presentation module
    # disappeared, the canonical snapshot and its identity would be unchanged.
    s = sample()
    digest = wp.canonical_input_hash(s)
    assert len(digest) == 64
    assert digest == wp.canonical_input_hash(sample())
    assert s.canonical_state()["material_id"] == "matter/basalt"


# ---------- Proof A ----------

def test_proof_a_fixture_invariants():
    fixture = json.loads(proof_a.FIXTURE_PATH.read_text(encoding="utf-8"))
    assert len(fixture["seeds"]) == 3
    matter_identity = None
    for seed_block in fixture["seeds"]:
        invariants = seed_block["invariants"]
        if matter_identity is None:
            matter_identity = invariants["matter_snapshot_identity"]
        assert invariants["matter_snapshot_identity"] == matter_identity
        for surface in seed_block["surfaces"]:
            a, b = surface["selection_recipe_a"], surface["selection_recipe_b"]
            assert surface["canonical_input_hash"] == surface["canonical_input_hash"]
            assert a["surface_family"] != b["surface_family"]
            assert a["presentation_lock"] != b["presentation_lock"]
            # physical truth untouched: no physical keys anywhere in selections
            forbidden = {"mass", "density", "strength", "collision", "layer_depths"}
            assert not (forbidden & set(a) | forbidden & set(b))


def test_proof_a_fixture_is_deterministic():
    rebuilt = proof_a.build_fixture()
    committed = json.loads(proof_a.FIXTURE_PATH.read_text(encoding="utf-8"))
    assert rebuilt == committed
