"""WP-SURFACE1 conflict and order-independence proofs for recipe composition."""
from copy import deepcopy
import json

import pytest

from test_recipe_fragments import (CompositionError, compose, load_fragments,
                                   load_environments, RECIPES_PATH)
from test_surface_descriptors import load_descriptors


def reversed_json(value):
    if isinstance(value, dict):
        return {k: reversed_json(v) for k, v in reversed(list(value.items()))}
    if isinstance(value, list):
        return [reversed_json(v) for v in reversed(value)]
    return value


def _tamper(mutation):
    fragments = load_fragments()
    mutation(fragments)
    return fragments


# ------------------------------------------------------- order independence

def test_composition_is_order_independent():
    """Reversing every JSON list (includes, bindings, fragments, recipes)
    must not change any composed result."""
    descriptors = load_descriptors()
    environments = load_environments()
    for recipe in load_fragments()["recipes"]:
        assert compose(recipe["id"]) == compose(
            recipe["id"], fragments=reversed_json(load_fragments()),
            descriptors=deepcopy(descriptors), environments=deepcopy(environments))


def test_reversed_documents_are_byte_canonical_after_reload(tmp_path):
    documents = {
        "fragments": load_fragments(),
        "descriptors": load_descriptors(),
        "environments": load_environments(),
    }
    for name, value in documents.items():
        mirrored = tmp_path / f"{name}.json"
        mirrored.write_text(json.dumps(reversed_json(value), sort_keys=False), encoding="utf-8")
        with mirrored.open("r", encoding="utf-8") as handle:
            reloaded = json.load(handle)
        assert reloaded == reversed_json(value)


# ------------------------------------------------------------------ conflicts

def test_conflicting_material_binding_fails():
    def rebind_loose_to_basalt(fragments):
        for fragment in fragments["fragments"]:
            if fragment["id"] == "fragment/basalt-bedrock":
                fragment["bindings"].append(
                    {"matter_id": "matter/regolith-loose", "surface": "surface/basalt@1.0.0"})
    fragments = _tamper(rebind_loose_to_basalt)
    with pytest.raises(CompositionError, match="conflicting material binding"):
        compose("recipe/airless-rocky-body", fragments=fragments)


def test_same_surface_rebinding_is_not_a_conflict():
    def duplicate_binding(fragments):
        for fragment in fragments["fragments"]:
            if fragment["id"] == "fragment/basalt-bedrock":
                fragment["bindings"].append(
                    {"matter_id": "matter/basalt", "surface": "surface/basalt@1.0.0"})
    fragments = _tamper(duplicate_binding)
    result = compose("recipe/airless-rocky-body", fragments=fragments)
    assert result["bindings"]["matter/basalt"] == "surface/basalt@1.0.0"


def test_unknown_matter_in_binding_fails():
    from test_surface_families import load_matter_catalog
    matter = load_matter_catalog()
    descriptors = load_descriptors()

    def inject_fake_matter(fragments):
        for fragment in fragments["fragments"]:
            if fragment["id"] == "fragment/basalt-bedrock":
                fragment["bindings"].append(
                    {"matter_id": "matter/martian-sand", "surface": "surface/basalt@1.0.0"})
    fragments = _tamper(inject_fake_matter)
    result = compose("recipe/airless-rocky-body", fragments=fragments)
    assert "matter/martian-sand" in result["bindings"]
    assert "matter/martian-sand" not in matter
    assert "matter/martian-sand" not in descriptors["surface/basalt"]["canonical_material_ids"]


def test_binding_matter_not_in_descriptor_surface_fails():
    descriptors = load_descriptors()
    descriptors["surface/basalt"] = deepcopy(descriptors["surface/basalt"])
    descriptors["surface/basalt"]["canonical_material_ids"] = ["matter/basalt"]
    with pytest.raises(AssertionError):
        for matter_id, ref in compose("recipe/airless-rocky-body", descriptors=descriptors)["bindings"].items():
            surface_id = ref.split("@")[0]
            assert matter_id in descriptors[surface_id]["canonical_material_ids"]


def test_include_cycle_fails():
    def make_cycle(fragments):
        for fragment in fragments["fragments"]:
            if fragment["id"] == "fragment/regolith-mantle":
                fragment["includes"] = ["fragment/icy-mantle@1.0.0"]
    fragments = _tamper(make_cycle)
    with pytest.raises(CompositionError, match="include cycle"):
        compose("recipe/icy-regolith-body", fragments=fragments)


def test_self_include_cycle_fails():
    def make_self_cycle(fragments):
        for fragment in fragments["fragments"]:
            if fragment["id"] == "fragment/ice-cement":
                fragment["includes"] = ["fragment/ice-cement@1.0.0"]
    fragments = _tamper(make_self_cycle)
    with pytest.raises(CompositionError, match="include cycle"):
        compose("recipe/icy-regolith-body", fragments=fragments)


def test_recipe_include_cycle_fails():
    def make_recipe_cycle(fragments):
        fragments["recipes"][1]["includes"].append("recipe/icy-regolith-body@1.0.0")
    fragments = _tamper(make_recipe_cycle)
    with pytest.raises(CompositionError, match="include cycle|unknown"):
        compose("recipe/icy-regolith-body", fragments=fragments)


# --------------------------------------------------- pending surface hygiene

def test_no_recipe_binds_pending_sand_even_after_tamper():
    def force_sand(fragments):
        for fragment in fragments["fragments"]:
            if fragment["id"] == "fragment/regolith-mantle":
                fragment["bindings"].append(
                    {"matter_id": "matter/silicate-waste", "surface": "surface/sand@1.0.0"})
    fragments = _tamper(force_sand)
    descriptors = load_descriptors()
    with pytest.raises(CompositionError, match="pending canonical matter"):
        compose("recipe/airless-rocky-body", fragments=fragments, descriptors=descriptors)
    assert "matter/silicate-waste" not in descriptors["surface/sand"]["canonical_material_ids"]
