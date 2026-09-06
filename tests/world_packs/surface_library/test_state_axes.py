"""WP-SURFACE1 fidelity/exposure state axis proofs."""
from copy import deepcopy
import json

import pytest

from test_surface_families import load_documents, SURFACES_DIR
from test_surface_descriptors import load_descriptors

AXES_PATH = SURFACES_DIR / "state_axes.v1.json"
AXIS_FIELDS = {"exposure", "fidelity"}


def load_axes():
    with AXES_PATH.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    assert value["schema"] == "dws.world_packs.surface_state_axes.v1"
    return value


def check_state_axes(axes=None, descriptors=None):
    if axes is None:
        axes = load_axes()
    if descriptors is None:
        descriptors = load_descriptors()
    taxonomy, _ = load_documents()
    families = {family["id"] for family in taxonomy["families"]}

    assert set(axes["axes"]) == AXIS_FIELDS
    for axis in axes["axes"].values():
        values = axis["values"]
        assert len(values) == len(set(values)), "duplicate axis value"
        assert axis["default"] in values, "axis default not in values"
    assert set(axes["family_conditions"]) == families, "family_conditions must cover taxonomy"

    for surface_id, descriptor in descriptors.items():
        conditions = axes["family_conditions"][descriptor["family"]]
        assert len(conditions) == len(set(conditions)), f"{surface_id} duplicate condition"
        for variant in descriptor["variants"]:
            assert set(variant["states"]) <= set(conditions), (
                f"{surface_id}/{variant['id']} states outside family vocabulary")
            assert variant["exposure"] in axes["axes"]["exposure"]["values"], (
                f"{surface_id}/{variant['id']} bad exposure")
            assert variant["fidelity"] in axes["axes"]["fidelity"]["values"], (
                f"{surface_id}/{variant['id']} bad fidelity")
    return axes


# ---------------------------------------------------------------- live proofs

def test_state_axes_consistent_with_descriptors():
    check_state_axes()


def test_every_family_has_condition_vocabulary():
    axes = check_state_axes()
    taxonomy, _ = load_documents()
    for family in taxonomy["families"]:
        assert axes["family_conditions"][family["id"]]


# ------------------------------------------------------------ negative proofs

def _tamper_axes(mutation):
    axes = deepcopy(load_axes())
    mutation(axes)
    return axes


def test_state_outside_vocabulary_fails():
    axes = _tamper_axes(lambda a: a["family_conditions"]["surface-family/regolith"].remove("weathered"))
    with pytest.raises(AssertionError, match="states outside family vocabulary"):
        check_state_axes(axes=axes)


def test_unknown_exposure_fails():
    def drop_exposed(axes):
        axes["axes"]["exposure"]["values"].remove("exposed")
        axes["axes"]["exposure"]["default"] = "buried"
    axes = _tamper_axes(drop_exposed)
    with pytest.raises(AssertionError, match="bad exposure"):
        check_state_axes(axes=axes)


def test_unknown_fidelity_tier_fails():
    descriptors = load_descriptors()
    descriptors["surface/ice"] = deepcopy(descriptors["surface/ice"])
    descriptors["surface/ice"]["variants"][0]["fidelity"] = "ultra"
    with pytest.raises(AssertionError, match="bad fidelity"):
        check_state_axes(descriptors=descriptors)


def test_missing_family_vocabulary_fails():
    axes = _tamper_axes(lambda a: a["family_conditions"].pop("surface-family/ice"))
    with pytest.raises(AssertionError, match="family_conditions must cover taxonomy"):
        check_state_axes(axes=axes)
