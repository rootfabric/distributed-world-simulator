"""WP-SURFACE1 sharded surface descriptor proofs.

Descriptors live in config/world_packs/library/surfaces/<name>.v1.json and must
stay consistent with taxonomy.v1.json and matter_binding_rules.v1.json.
"""
from copy import deepcopy
import json
from pathlib import Path

import pytest

from test_surface_families import (BindingError, ROOT, SURFACES_DIR, load_documents,
                                   load_matter_catalog, validate_bindings)

DESCRIPTOR_IDS = {"surface/regolith", "surface/basalt", "surface/sand", "surface/ice"}
DESCRIPTOR_FIELDS = {
    "schema", "id", "version", "family", "presentation_only", "binding_source",
    "binding_status", "canonical_material_ids", "physical_anchor_summary",
    "variants", "tags",
}


def load_descriptors():
    descriptors = {}
    for path in sorted(SURFACES_DIR.glob("*.v1.json")):
        if path.name in ("taxonomy.v1.json", "matter_binding_rules.v1.json"):
            continue
        with path.open("r", encoding="utf-8") as handle:
            value = json.load(handle)
        assert value["schema"] == "dws.world_packs.surface_descriptor.v1", path
        descriptors[value["id"]] = value
    return descriptors


def check_descriptors(taxonomy=None, rules=None, descriptors=None):
    if taxonomy is None or rules is None:
        taxonomy, rules = load_documents()
    if descriptors is None:
        descriptors = load_descriptors()
    validate_bindings(taxonomy, rules)
    families = {family["id"]: family for family in taxonomy["families"]}
    seen_ids = set()

    for surface_id, descriptor in descriptors.items():
        allowed = set(DESCRIPTOR_FIELDS)
        if descriptor["binding_status"] == "PENDING_CANONICAL_MATTER":
            allowed.add("pending_reason")
        assert set(descriptor) == allowed, f"{surface_id} field set drift"
        if descriptor["binding_status"] == "PENDING_CANONICAL_MATTER":
            assert str(descriptor.get("pending_reason", "")).strip(), f"{surface_id} pending_reason required"
        assert surface_id not in seen_ids, f"duplicate descriptor id {surface_id}"
        seen_ids.add(surface_id)
        family = families[descriptor["family"]]
        assert surface_id in family["surfaces"], f"{surface_id} not declared by {descriptor['family']}"
        assert descriptor["binding_status"] == family["binding_status"]
        assert descriptor["presentation_only"] is True
        rule_ids = {b["matter_id"] for b in rules["bindings"] if b["surface"] == surface_id}
        assert set(descriptor["canonical_material_ids"]) == rule_ids, (
            f"{surface_id} canonical_material_ids != binding rules")
        variant_ids = [variant["id"] for variant in descriptor["variants"]]
        assert len(variant_ids) == len(set(variant_ids)), f"{surface_id} duplicate variant id"

    for family in families.values():
        for surface_id in family["surfaces"]:
            assert surface_id in descriptors, f"taxonomy surface {surface_id} has no descriptor shard"


# ---------------------------------------------------------------- live proofs

def test_expected_descriptor_shards_exist():
    descriptors = load_descriptors()
    assert set(descriptors) == DESCRIPTOR_IDS


def test_descriptors_consistent_with_taxonomy_and_rules():
    check_descriptors()


def test_sand_descriptor_is_pending_and_unbound():
    descriptors = load_descriptors()
    _, rules = load_documents()
    sand = descriptors["surface/sand"]
    assert sand["binding_status"] == "PENDING_CANONICAL_MATTER"
    assert sand["canonical_material_ids"] == []
    assert not any(b["surface"] == "surface/sand" for b in rules["bindings"])


def test_descriptor_matter_ids_exist_in_canonical_catalog():
    matter = load_matter_catalog()
    for descriptor in load_descriptors().values():
        for matter_id in descriptor["canonical_material_ids"]:
            assert matter_id in matter


# ------------------------------------------------------------ negative proofs

def test_unknown_extra_matter_id_in_descriptor_fails():
    descriptors = load_descriptors()
    descriptors["surface/sand"] = deepcopy(descriptors["surface/sand"])
    descriptors["surface/sand"]["canonical_material_ids"] = ["matter/silicate-waste"]
    with pytest.raises(AssertionError, match="canonical_material_ids != binding rules"):
        check_descriptors(descriptors=descriptors)


def test_descriptor_with_wrong_family_fails():
    descriptors = load_descriptors()
    descriptors["surface/ice"] = deepcopy(descriptors["surface/ice"])
    descriptors["surface/ice"]["family"] = "surface-family/basalt"
    with pytest.raises(AssertionError):
        check_descriptors(descriptors=descriptors)


def test_missing_descriptor_shard_fails():
    descriptors = load_descriptors()
    dropped = {k: v for k, v in descriptors.items() if k != "surface/basalt"}
    with pytest.raises(AssertionError, match="has no descriptor shard"):
        check_descriptors(descriptors=dropped)


def test_binding_status_drift_fails():
    descriptors = load_descriptors()
    descriptors["surface/sand"] = deepcopy(descriptors["surface/sand"])
    descriptors["surface/sand"]["binding_status"] = "BOUND"
    with pytest.raises(AssertionError):
        check_descriptors(descriptors=descriptors)
