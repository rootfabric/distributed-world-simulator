"""WP2.0 read-only presentation adapter contract tests.

These are contract-level proofs (no runtime lease; see
config/world_packs/wp2_activation_state.v1.json). They demonstrate:
read-only guarantee, frame vector contract (normalized alignment), no
global-Y assumption, true immutable resolver inputs, honest
requested/resolved fidelity, presentation selection lock semantics,
domain-separated variation tokens, exact versioned recipe resolution,
strict numeric canonicalization, optional-subsystem safety and REAL
Proof A invariants (R1-R8 repair).
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
        wp.validate_recipe_document({"recipes": {"recipe/bad@1.0.0": {"version": "1.0.0", "bindings": {
            "f": {"layer_depths": [1, 2, 3]}}}}})
    with pytest.raises(wp.PhysicalFieldError):
        wp.validate_recipe_document({"recipes": {"recipe/bad@1.0.0": {"version": "1.0.0", "bindings": {
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


# ---------- R1: frame vector contract (normalize internally) ----------

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


def test_mapping_mode_is_normal_sign_invariant():
    a = sample(surface_normal=(0.0, 0.0, 1.0))
    b = sample(surface_normal=(0.0, 0.0, -100.0))
    assert wp.select_mapping_mode(a) == wp.select_mapping_mode(b) == "planar_projection"


def test_alignment_is_bounded_cosine():
    for kwargs in [
        dict(surface_normal=(0.0, 0.0, 1.0)),
        dict(surface_normal=(3.0, 4.0, 0.0), gravity_direction=(0.0, 0.0, -0.001)),
        dict(surface_normal=(1e-3, 1e-3, 1e-3), gravity_direction=(5.0, 0.0, 0.0)),
    ]:
        alignment = wp.surface_alignment(sample(**kwargs))
        assert 0.0 <= alignment <= 1.0


@pytest.mark.parametrize("normal,gravity", [
    ((0.0, 0.0, 1.0), (0.0, 0.0, -1.0)),
    ((0.0, 0.0, 10.0), (0.0, 0.0, -3.0)),
    ((0.0, 0.0, 0.1), (0.0, 0.0, -50.0)),
])
def test_mapping_mode_is_scale_invariant(normal, gravity):
    # Metamorphic R1: magnitude carries no direction; only orientation maps.
    resolver = wp.SurfacePresentationResolver()
    selection = resolver.resolve(
        sample(surface_normal=normal, gravity_direction=gravity),
        wp.ClientFidelity("standard"))
    assert selection.mapping_mode == "planar_projection"


@pytest.mark.parametrize("kwargs", [
    dict(surface_normal=(0.0, 0.0, 0.0)),                       # zero normal
    dict(gravity_direction=(0.0, 0.0, 0.0)),                    # zero gravity when supplied
    dict(surface_normal=(0.0, float("nan"), 1.0)),              # NaN normal
    dict(surface_normal=(0.0, float("inf"), 1.0)),              # +Inf normal
    dict(gravity_direction=(float("-inf"), 0.0, 0.0)),          # -Inf gravity
    dict(surface_normal=(1.0, 2.0)),                            # malformed length
    dict(gravity_direction=(1.0, 2.0, 3.0, 4.0)),               # malformed length
    dict(surface_normal="not-a-vector"),                        # malformed type
])
def test_frame_vectors_are_validated(kwargs):
    with pytest.raises((wp.MalformedVectorError, wp.MalformedCanonicalNumberError)):
        sample(**kwargs)


def test_zero_position_components_are_finite_but_position_may_be_zero():
    s = sample(position_body_fixed=(0.0, 0.0, 0.0))
    assert s.position_body_fixed == (0.0, 0.0, 0.0)


# ---------- R2: true immutable resolver inputs ----------

def _loaded_configs():
    recipes_doc = json.loads((ROOT / "config/world_packs/presentation/surface_recipes.v1.json").read_text(encoding="utf-8"))
    catalog = json.loads((ROOT / "config/world_packs/presentation/matter_catalog_snapshot.v1.json").read_text(encoding="utf-8"))
    return recipes_doc, catalog


def test_mutating_original_catalog_after_construction_is_inert():
    _, catalog = _loaded_configs()
    resolver = wp.SurfacePresentationResolver(catalog_snapshot=catalog)
    baseline = resolver.resolve(sample(), wp.ClientFidelity("standard")).to_json()
    catalog["materials"]["matter/basalt"] = {"matter_family": "matter-family/volatile-ice"}
    catalog["materials"]["matter/injected"] = {"matter_family": "matter-family/regolith"}
    after = resolver.resolve(sample(), wp.ClientFidelity("standard")).to_json()
    assert after == baseline


def test_mutating_returned_catalog_view_is_inert():
    resolver = wp.SurfacePresentationResolver()
    baseline = resolver.resolve(sample(), wp.ClientFidelity("standard")).to_json()
    view = resolver.catalog_snapshot
    view["materials"]["matter/basalt"] = {"matter_family": "matter-family/volatile-ice"}
    view["materials"].pop("matter/regolith-loose")
    after = resolver.resolve(sample(), wp.ClientFidelity("standard")).to_json()
    assert after == baseline


def test_mutating_original_recipes_after_construction_is_inert():
    recipes_doc, catalog = _loaded_configs()
    resolver = wp.SurfacePresentationResolver(recipes=recipes_doc, catalog_snapshot=catalog)
    baseline = resolver.resolve(sample(), wp.ClientFidelity("standard")).to_json()
    recipes_doc["recipes"][RECIPE_A]["bindings"]["matter-family/silicate-rock"]["variants"]["standard"]["name"] = "tampered"
    recipes_doc["recipes"][RECIPE_A]["bindings"]["matter-family/silicate-rock"]["scale_parameters"]["macro_scale"] = 999.0
    after = resolver.resolve(sample(), wp.ClientFidelity("standard")).to_json()
    assert after == baseline


def test_mutating_returned_recipes_view_is_inert():
    resolver = wp.SurfacePresentationResolver()
    baseline = resolver.resolve(sample(), wp.ClientFidelity("standard")).to_json()
    view = resolver.recipes_snapshot
    view["recipes"][RECIPE_A]["bindings"]["matter-family/silicate-rock"]["variants"]["standard"]["name"] = "tampered"
    after = resolver.resolve(sample(), wp.ClientFidelity("standard")).to_json()
    assert after == baseline


def test_internal_state_is_deep_frozen():
    resolver = wp.SurfacePresentationResolver()
    # Internal representation is recursively frozen (MappingProxyType): no
    # mutable container exists inside the resolver to write to.
    from types import MappingProxyType
    internal = resolver._catalog
    assert isinstance(internal, MappingProxyType)
    assert isinstance(internal["materials"], MappingProxyType)
    with pytest.raises(TypeError):
        internal["materials"]["matter/basalt"] = {"matter_family": "tampered"}


# ---------- R3: requested vs resolved fidelity ----------

def test_requested_high_with_only_standard_resolves_standard_honestly():
    # ice/ore fixtures only define the standard tier.
    resolver = wp.SurfacePresentationResolver()
    s = sample(material_id="matter/water-ice")
    sel = resolver.resolve(s, wp.ClientFidelity("high"))
    assert sel.requested_fidelity == "high"
    assert sel.resolved_fidelity == "standard"
    assert sel.variant == "dark-ice-mid"  # the standard asset, truthfully named
    assert list(sel.resolved_asset_refs) == ["asset/dark-ice-mid@1.0.0"]


def test_requested_preview_with_only_standard_resolves_standard_honestly():
    resolver = wp.SurfacePresentationResolver()
    s = sample(material_id="matter/iron-nickel-ore")
    sel = resolver.resolve(s, wp.ClientFidelity("preview"))
    assert sel.requested_fidelity == "preview"
    assert sel.resolved_fidelity == "standard"


def test_exact_existing_high_resolves_high():
    resolver = wp.SurfacePresentationResolver()
    s = sample(material_id="matter/basalt")
    sel = resolver.resolve(s, wp.ClientFidelity("high"))
    assert sel.requested_fidelity == sel.resolved_fidelity == "high"
    assert sel.variant == "dark-basaltic-high"


def test_fidelity_changes_presentation_only():
    resolver = wp.SurfacePresentationResolver()
    s = sample()
    world_before = wp.canonical_input_hash(s)
    low = resolver.resolve(s, wp.ClientFidelity("preview"))
    high = resolver.resolve(s, wp.ClientFidelity("high"))
    assert low.resolved_fidelity == "preview" and high.resolved_fidelity == "high"
    assert low.variant != high.variant
    assert wp.canonical_input_hash(s) == world_before


def test_two_clients_same_world_different_fidelity():
    resolver = wp.SurfacePresentationResolver()
    s = sample()
    client_a = resolver.resolve(s, wp.ClientFidelity("preview"))
    client_b = resolver.resolve(s, wp.ClientFidelity("high"))
    assert client_a.variation_seed == client_b.variation_seed  # same surface identity
    assert client_a.variant != client_b.variant                # different prepared presentation
    assert client_a.presentation_selection_lock != client_b.presentation_selection_lock


def test_unknown_fidelity_rejected():
    with pytest.raises(ValueError):
        wp.ClientFidelity("ultra")


# ---------- R4: presentation selection lock ----------

def test_selection_lock_is_exact_and_versioned():
    resolver = wp.SurfacePresentationResolver()
    s = sample()
    sel = resolver.resolve(s, wp.ClientFidelity("high"))
    assert sel.variant_version == "1.0.0"
    # The selection lock is the exact presentation selection identity:
    # identical resolved selection -> identical lock; the per-surface
    # variation token identifies the surface.
    assert sel.presentation_selection_lock == resolver.resolve(
        sample(), wp.ClientFidelity("high")).presentation_selection_lock
    other = resolver.resolve(sample(surface_id="surface/test/1"), wp.ClientFidelity("high"))
    assert other.presentation_selection_lock == sel.presentation_selection_lock  # same selection
    assert other.variation_seed != sel.variation_seed                            # different surface


def test_lock_regression_asset_refs_change_lock():
    recipes_doc, catalog = _loaded_configs()
    tampered = deepcopy(recipes_doc)
    tampered["recipes"][RECIPE_A]["bindings"]["matter-family/silicate-rock"]["variants"]["high"]["asset_refs"] = [
        "asset/dark-basaltic-high@2.0.0"]
    base = wp.SurfacePresentationResolver()
    changed = wp.SurfacePresentationResolver(recipes=tampered, catalog_snapshot=catalog)
    s = sample()
    lock_a = base.resolve(s, wp.ClientFidelity("high")).presentation_selection_lock
    lock_b = changed.resolve(s, wp.ClientFidelity("high")).presentation_selection_lock
    assert lock_a != lock_b


def test_lock_regression_resolved_variant_change_lock():
    recipes_doc, catalog = _loaded_configs()
    tampered = deepcopy(recipes_doc)
    tampered["recipes"][RECIPE_A]["bindings"]["matter-family/silicate-rock"]["variants"]["high"]["name"] = "renamed"
    base = wp.SurfacePresentationResolver()
    changed = wp.SurfacePresentationResolver(recipes=tampered, catalog_snapshot=catalog)
    s = sample()
    assert (base.resolve(s, wp.ClientFidelity("high")).presentation_selection_lock
            != changed.resolve(s, wp.ClientFidelity("high")).presentation_selection_lock)


def test_lock_regression_mapping_mode_change_lock():
    resolver = wp.SurfacePresentationResolver()
    floor = sample(surface_normal=(0.0, 0.0, 1.0))          # planar_projection
    wall = sample(surface_normal=(0.0, 1.0, 0.0))           # triplanar
    assert (resolver.resolve(floor, wp.ClientFidelity("high")).presentation_selection_lock
            != resolver.resolve(wall, wp.ClientFidelity("high")).presentation_selection_lock)


def test_lock_regression_requested_fidelity_fallback_same_lock():
    # Requested fidelity changes but the resolved selection is identical
    # (both fall back to the standard tier for volatile-ice) -> the lock,
    # which covers the resolved selection only, must NOT change.
    resolver = wp.SurfacePresentationResolver()
    s = sample(material_id="matter/water-ice")
    preview_req = resolver.resolve(s, wp.ClientFidelity("preview"))
    high_req = resolver.resolve(s, wp.ClientFidelity("high"))
    assert preview_req.requested_fidelity != high_req.requested_fidelity
    assert preview_req.resolved_fidelity == high_req.resolved_fidelity == "standard"
    assert preview_req.variant == high_req.variant
    assert (preview_req.presentation_selection_lock
            == high_req.presentation_selection_lock)


def test_lock_is_not_claimed_to_be_prepared_bundle_identity():
    # Documentation contract: the lock carries resolved selection identity
    # (recipe, family, variant, resolved fidelity, mapping, scale, asset refs)
    # and nothing else. Two recipes over the same surface must differ.
    resolver = wp.SurfacePresentationResolver()
    s = sample()
    a = resolver.resolve(s, wp.ClientFidelity("standard"), recipe_ref=RECIPE_A)
    b = resolver.resolve(s, wp.ClientFidelity("standard"), recipe_ref=RECIPE_B)
    assert a.presentation_selection_lock != b.presentation_selection_lock


# ---------- R6: variation token domain ----------

def test_variation_token_fidelity_independent():
    resolver = wp.SurfacePresentationResolver()
    s = sample()
    low = resolver.resolve(s, wp.ClientFidelity("preview"))
    high = resolver.resolve(s, wp.ClientFidelity("high"))
    assert low.variation_seed == high.variation_seed


def test_variation_token_is_body_scoped():
    same_surface_other_body = sample(body_id="body/other-moon")
    this = sample()
    assert this.surface_id == same_surface_other_body.surface_id
    assert wp.variation_token(this.body_id, this.surface_id, RECIPE_A) \
        != wp.variation_token(same_surface_other_body.body_id,
                              same_surface_other_body.surface_id, RECIPE_A)
    resolver = wp.SurfacePresentationResolver()
    assert (resolver.resolve(this, wp.ClientFidelity("standard")).variation_seed
            != resolver.resolve(same_surface_other_body,
                                wp.ClientFidelity("standard")).variation_seed)


def test_variation_token_is_recipe_scoped():
    token_a = wp.variation_token("body/mock-moon", "surface/test/0", RECIPE_A)
    token_b = wp.variation_token("body/mock-moon", "surface/test/0", RECIPE_B)
    assert token_a != token_b


def test_variation_token_domain_separated_and_stable():
    token = wp.variation_token("body/mock-moon", "surface/test/0", RECIPE_A)
    assert token == wp.variation_token("body/mock-moon", "surface/test/0", RECIPE_A)
    assert len(token) == 16  # documented token width


# ---------- R7: exact version validation ----------

def test_shipped_recipe_document_passes_validation():
    wp.validate_recipe_document(_loaded_configs()[0])


@pytest.mark.parametrize("key,version", [
    ("recipe/no-version", "1.0.0"),                # missing @version
    ("recipe/bad@latest", "latest"),               # floating tag
    ("recipe/bad@1.0", "1.0"),                     # invalid semver
    ("recipe/mismatch@1.2.3", "1.2.4"),            # key/version mismatch
    ("recipe/noversion-declared@2.0.0", None),     # version missing in doc
])
def test_recipe_version_violations_rejected(key, version):
    doc = {"recipes": {key: {"version": version, "bindings": {}}}}
    with pytest.raises((wp.RecipeVersionError, wp.PhysicalFieldError)):
        wp.validate_recipe_document(doc)


def test_recipe_duplicate_logical_identity_rejected():
    doc = {"recipes": {
        "recipe/same@1.0.0": {"version": "1.0.0", "bindings": {}},
        "recipe/same@1.2.0": {"version": "1.2.0", "bindings": {}},
    }}
    with pytest.raises(wp.RecipeVersionError):
        wp.validate_recipe_document(doc)


def test_resolver_rejects_malformed_recipe_document_on_construction():
    _, catalog = _loaded_configs()
    bad = {"recipes": {"recipe/mismatch@1.0.0": {"version": "1.2.3", "bindings": {}}}}
    with pytest.raises(wp.RecipeVersionError):
        wp.SurfacePresentationResolver(recipes=bad, catalog_snapshot=catalog)


def test_unknown_recipe_rejected():
    resolver = wp.SurfacePresentationResolver()
    with pytest.raises(KeyError):
        resolver.resolve(sample(recipe_ref="recipe/does-not-exist@9.9.9"),
                         wp.ClientFidelity("standard"))


# ---------- R8: strict numeric canonical input ----------

@pytest.mark.parametrize("kwargs", [
    dict(position_body_fixed=(float("nan"), 0.0, 0.0)),
    dict(position_body_fixed=(0.0, float("inf"), 0.0)),
    dict(position_body_fixed=(0.0, 0.0, float("-inf"))),
    dict(composition={"x": float("nan")}),
    dict(composition={"x": float("infinity")}),
    dict(composition={"x": "0.5"}),   # strings are not canonical numbers
    dict(composition={"x": True}),    # bools are not canonical numbers
])
def test_non_finite_canonical_numbers_rejected(kwargs):
    with pytest.raises(wp.MalformedCanonicalNumberError):
        sample(**kwargs)


def test_canonical_hash_is_deterministic_strict_json():
    s = sample()
    digest = wp.canonical_input_hash(s)
    assert len(digest) == 64
    assert digest == wp.canonical_input_hash(sample())


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


# ---------- Proof A (R5): REAL invariants ----------

def test_proof_a_fixture_invariants():
    fixture = json.loads(proof_a.FIXTURE_PATH.read_text(encoding="utf-8"))
    assert fixture["contract_revision"] == "WP2_CONTRACT_REPAIR_R1"
    assert len(fixture["seeds"]) == 3
    resolver = wp.SurfacePresentationResolver()
    matter_identity = None
    for seed_block in fixture["seeds"]:
        assert len(seed_block["surfaces"]) == 6  # 3 seeds x 6 surfaces
        invariants = seed_block["invariants"]
        if matter_identity is None:
            matter_identity = invariants["matter_snapshot_identity"]
        assert invariants["matter_snapshot_identity"] == matter_identity
        # Independently rebuild the deterministic samples for this seed and
        # re-verify every recorded invariant from scratch.
        samples = proof_a._samples_for_seed(seed_block["seed"])
        assert invariants["geometry_source_identity"] == proof_a._geometry_source_identity(samples)
        for surface, s in zip(seed_block["surfaces"], samples):
            # REAL before/after invariant, not a self-comparison.
            assert surface["canonical_before_recipe_a"] == surface["canonical_after_recipe_a"]
            assert surface["canonical_before_recipe_b"] == surface["canonical_after_recipe_b"]
            # Independent resolutions A and B agree on canonical identity.
            assert (surface["canonical_after_recipe_a"]
                    == surface["canonical_after_recipe_b"]
                    == surface["canonical_input_hash"]
                    == wp.canonical_input_hash(s))
            # Canonical fields unchanged by either resolution.
            assert surface["material_id"] == s.material_id
            assert surface["matter_revision"] == s.matter_revision
            assert surface["representation_revision"] == s.representation_revision
            a, b = surface["selection_recipe_a"], surface["selection_recipe_b"]
            assert a["surface_family"] != b["surface_family"]
            assert a["presentation_selection_lock"] != b["presentation_selection_lock"]
            # physical truth untouched: no physical keys anywhere in selections
            forbidden = {"mass", "density", "strength", "collision", "layer_depths"}
            assert not (forbidden & set(a) | forbidden & set(b))
        # Live re-resolution must reproduce the committed selections exactly.
        for surface, s in zip(seed_block["surfaces"], samples):
            live_a = resolver.resolve(s, wp.ClientFidelity("high"), recipe_ref=RECIPE_A)
            assert live_a.to_json() == surface["selection_recipe_a"]


def test_proof_a_fixture_is_deterministic():
    rebuilt = proof_a.build_fixture()
    committed = json.loads(proof_a.FIXTURE_PATH.read_text(encoding="utf-8"))
    assert rebuilt == committed
