"""WP-SURFACE1 recipe fragment composition proofs (basic semantics)."""
from copy import deepcopy
import json

import pytest

from test_surface_families import ROOT, SURFACES_DIR, load_documents, load_matter_catalog
from test_surface_descriptors import load_descriptors

RECIPES_PATH = ROOT / "config/world_packs/library/recipes/fragments.v1.json"
ENVIRONMENTS_DIR = ROOT / "config/world_packs/library/environments"


class CompositionError(Exception):
    """Raised when recipe fragment composition is invalid."""


def load_fragments():
    with RECIPES_PATH.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    assert value["schema"] == "dws.world_packs.recipe_fragments.v1"
    return value


def load_environments():
    environments = {}
    for path in sorted(ENVIRONMENTS_DIR.glob("*.v1.json")):
        with path.open("r", encoding="utf-8") as handle:
            value = json.load(handle)
        assert value["schema"] == "dws.world_packs.environment_descriptor.v1", path
        environments[f"{value['id']}@{value['version']}"] = value
    return environments


def resolve_surface_ref(ref, descriptors):
    surface_id = ref.split("@")[0]
    version = ref.split("@", 1)[1]
    descriptor = descriptors.get(surface_id)
    if descriptor is None:
        raise CompositionError(f"unknown surface {surface_id}")
    if descriptor["version"] != version:
        raise CompositionError(f"surface version mismatch for {ref}")
    if descriptor["binding_status"] == "PENDING_CANONICAL_MATTER":
        raise CompositionError(
            f"pending canonical matter: {surface_id} has no canonical Matter binding")
    return descriptor


def compose(recipe_id, fragments=None, descriptors=None, environments=None, _stack=None):
    """Compose a recipe: union of fragment bindings and environments.

    Conflicting bindings (same matter_id bound to two surfaces) and conflicting
    environments (two different environment ids) raise CompositionError.
    """
    if fragments is None:
        fragments = load_fragments()
    if descriptors is None:
        descriptors = load_descriptors()
    if environments is None:
        environments = load_environments()
    fragment_index = {f"{f['id']}@{f['version']}": f for f in fragments["fragments"]}
    recipe_index = {f"{r['id']}@{r['version']}": r for r in fragments["recipes"]}
    key = recipe_id if "@" in recipe_id else None
    if key is None:
        matches = [k for k in recipe_index if k.split("@")[0] == recipe_id]
        key = matches[0] if len(matches) == 1 else None
    if key not in recipe_index:
        raise CompositionError(f"unknown recipe {recipe_id}")
    _stack = _stack or []
    if key in _stack:
        raise CompositionError(f"fragment include cycle at {key}")

    bindings = {}
    envs = set()

    def add_binding(matter_id, ref):
        resolve_surface_ref(ref, descriptors)
        if matter_id in bindings and bindings[matter_id] != ref:
            raise CompositionError(
                f"conflicting material binding: {matter_id} -> {bindings[matter_id]} and {ref}")
        bindings[matter_id] = ref

    def add_env(env):
        if env not in environments:
            raise CompositionError(f"unknown environment {env}")
        envs.add(env)

    def collect(node_key, stack):
        if node_key in stack:
            raise CompositionError(f"include cycle at {node_key}")
        node = fragment_index.get(node_key) or recipe_index.get(node_key)
        if node is None:
            if any(node_key.split("@")[0] == f["id"] for f in fragments["fragments"]):
                raise CompositionError(f"unknown fragment include {node_key}")
            raise CompositionError(f"unknown recipe or fragment {node_key}")
        next_stack = stack + [node_key]
        for include in node.get("includes", []):
            collect(include, next_stack)
        for binding in node.get("bindings", []):
            add_binding(binding["matter_id"], binding["surface"])
        for env in node.get("environments", []):
            add_env(env)

    collect(key, [])
    return {
        "recipe": key,
        "bindings": {k: bindings[k] for k in sorted(bindings)},
        "environments": sorted(envs),
    }


# ---------------------------------------------------------------- live proofs

def test_recipe_fragment_files_exist():
    fragments = load_fragments()
    assert {f["id"] for f in fragments["fragments"]} == {
        "fragment/regolith-mantle", "fragment/basalt-bedrock", "fragment/ice-cement",
        "fragment/icy-mantle", "fragment/vacuum-exposure"}
    assert {r["id"] for r in fragments["recipes"]} == {
        "recipe/airless-rocky-body", "recipe/icy-regolith-body"}


def test_airless_rocky_composition():
    result = compose("recipe/airless-rocky-body")
    assert result["bindings"] == {
        "matter/basalt": "surface/basalt@1.0.0",
        "matter/fractured-basalt": "surface/basalt@1.0.0",
        "matter/regolith-compacted": "surface/regolith@1.0.0",
        "matter/regolith-loose": "surface/regolith@1.0.0",
    }
    assert result["environments"] == ["environment/airless-shard@1.0.0"]


def test_diamond_include_deduplicates():
    result = compose("recipe/icy-regolith-body")
    assert result["bindings"]["matter/regolith-loose"] == "surface/regolith@1.0.0"
    assert result["bindings"]["matter/water-ice"] == "surface/ice@1.0.0"
    assert result["environments"] == ["environment/airless-shard@1.0.0"]


def test_all_bound_matter_and_surfaces_are_real():
    matter = load_matter_catalog()
    descriptors = load_descriptors()
    for recipe in load_fragments()["recipes"]:
        result = compose(recipe["id"])
        for matter_id, ref in result["bindings"].items():
            assert matter_id in matter
            surface_id = ref.split("@")[0]
            assert matter_id in descriptors[surface_id]["canonical_material_ids"]


def test_pending_sand_never_bound_in_compositions():
    for recipe in load_fragments()["recipes"]:
        result = compose(recipe["id"])
        assert not any(v.startswith("surface/sand") for v in result["bindings"].values())


# ------------------------------------------------------------ negative proofs

def test_unknown_recipe_fails():
    with pytest.raises(CompositionError, match="unknown recipe"):
        compose("recipe/missing")


def test_unknown_fragment_include_fails():
    fragments = load_fragments()
    fragments["recipes"][0]["includes"].append("fragment/missing@1.0.0")
    with pytest.raises(CompositionError, match="unknown recipe or fragment fragment/missing"):
        compose("recipe/airless-rocky-body", fragments=fragments)


def test_unknown_environment_fails():
    fragments = load_fragments()
    fragments["fragments"][0]["environments"] = ["environment/missing@1.0.0"]
    with pytest.raises(CompositionError, match="unknown environment"):
        compose("recipe/airless-rocky-body", fragments=fragments)


def test_unknown_surface_version_fails():
    fragments = load_fragments()
    fragments["fragments"][1]["bindings"][0]["surface"] = "surface/basalt@9.9.9"
    with pytest.raises(CompositionError, match="surface version mismatch"):
        compose("recipe/airless-rocky-body", fragments=fragments)
