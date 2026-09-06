"""WP-SURFACE1 surface family taxonomy and Matter binding rule proofs.

Validation reads the real canonical Matter catalog source (read-only) and fails
on unknown or ambiguous physical bindings, per matter_binding_rules.v1.json.
"""
from copy import deepcopy
import json
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
SURFACES_DIR = ROOT / "config/world_packs/library/surfaces"
MATTER_CATALOG_GD = ROOT / "scripts/simulation/matter/catalog/matter_material_catalog.gd"

RULE_IDS = {
    "BIND_EXISTING_MATTER_ONLY",
    "FAIL_ON_UNKNOWN_MATTER_ID",
    "FAIL_ON_AMBIGUOUS_BINDING",
    "FAIL_ON_FAMILY_MISMATCH",
    "PENDING_FAMILY_MUST_NOT_BIND",
    "NO_MATTER_MUTATION",
}


class BindingError(Exception):
    """Raised when surface/Matter bindings violate the declared rules."""


def read_json(path):
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def load_matter_catalog():
    """Extract real matter ids/families from the canonical GDScript catalog."""
    text = MATTER_CATALOG_GD.read_text(encoding="utf-8")
    pattern = re.compile(
        r'_spec\(\s*"(matter/[a-z0-9-]+)",\s*"[^"]*",\s*"(matter-family/[a-z0-9-]+)"'
    )
    materials = {}
    for match in pattern.finditer(text):
        materials[match.group(1)] = {"family": match.group(2)}
    assert materials, "canonical matter catalog source changed; update extraction"
    return materials


def load_documents():
    taxonomy = read_json(SURFACES_DIR / "taxonomy.v1.json")
    rules = read_json(SURFACES_DIR / "matter_binding_rules.v1.json")
    return taxonomy, rules


def validate_bindings(taxonomy=None, rules=None, matter=None):
    """Full rule-machine validation; raises BindingError on any violation."""
    if taxonomy is None or rules is None:
        taxonomy, rules = load_documents()
    if matter is None:
        matter = load_matter_catalog()
    families = {family["id"]: family for family in taxonomy["families"]}

    def fail(rule_id, detail):
        raise BindingError(f"{rule_id}: {detail}")

    # Structural taxonomy invariants.
    assert taxonomy["schema"] == "dws.world_packs.surface_taxonomy.v1"
    assert rules["schema"] == "dws.world_packs.surface_matter_binding_rules.v1"
    assert taxonomy["presentation_only"] is True and rules["presentation_only"] is True
    assert len(families) == len(taxonomy["families"]), "duplicate family id"
    declared_rule_ids = {rule["id"] for rule in rules["rules"]}
    assert RULE_IDS <= declared_rule_ids, "missing declared rule"

    seen_matter_to_family = {}
    seen_matter_to_surface = {}
    for binding in rules["bindings"]:
        matter_id = binding["matter_id"]
        family_id = binding["surface_family"]
        surface_id = binding["surface"]
        if matter_id not in matter:
            fail("FAIL_ON_UNKNOWN_MATTER_ID", f"{matter_id} not in canonical matter catalog")
        if family_id not in families:
            fail("BIND_EXISTING_MATTER_ONLY", f"{family_id} not in taxonomy")
        family = families[family_id]
        if surface_id not in family["surfaces"]:
            fail("BIND_EXISTING_MATTER_ONLY", f"{surface_id} not declared by {family_id}")
        if matter_id in seen_matter_to_family and seen_matter_to_family[matter_id] != family_id:
            fail("FAIL_ON_AMBIGUOUS_BINDING", f"{matter_id} bound to {seen_matter_to_family[matter_id]} and {family_id}")
        if matter_id in seen_matter_to_surface and seen_matter_to_surface[matter_id] != surface_id:
            fail("FAIL_ON_AMBIGUOUS_BINDING", f"{matter_id} bound to two surfaces inside {family_id}")
        seen_matter_to_family[matter_id] = family_id
        seen_matter_to_surface[matter_id] = surface_id
        if family["binding_status"] == "BOUND":
            if matter[matter_id]["family"] not in family["expected_matter_families"]:
                fail("FAIL_ON_FAMILY_MISMATCH",
                     f"{matter_id} family {matter[matter_id]['family']} not in {family_id} expected_matter_families")

    pending = {entry["surface_family"] for entry in rules.get("pending_families", [])}
    for family in families.values():
        bound_ids = [b["matter_id"] for b in rules["bindings"] if b["surface_family"] == family["id"]]
        if family["binding_status"] == "PENDING_CANONICAL_MATTER":
            if bound_ids:
                fail("PENDING_FAMILY_MUST_NOT_BIND", f"{family['id']} binds {bound_ids}")
            if family["id"] not in pending:
                fail("PENDING_FAMILY_MUST_NOT_BIND", f"{family['id']} missing from pending_families")
            if not family.get("expected_matter_families"):
                # Pending families declare no expected matter family until bound.
                pass
        elif family["binding_status"] == "BOUND":
            if not bound_ids:
                fail("BIND_EXISTING_MATTER_ONLY", f"{family['id']} BOUND but has no bindings")
            if family["id"] in pending:
                fail("PENDING_FAMILY_MUST_NOT_BIND", f"{family['id']} both BOUND and pending")

    for entry in rules.get("explicitly_unbound_matter", []):
        if entry["matter_id"] in seen_matter_to_family:
            fail("FAIL_ON_AMBIGUOUS_BINDING",
                 f"{entry['matter_id']} both explicitly unbound and bound to {seen_matter_to_family[entry['matter_id']]}")

    return {"families": sorted(families), "bindings": sorted(seen_matter_to_family)}


# ---------------------------------------------------------------- live proofs

def test_canonical_matter_catalog_contents():
    matter = load_matter_catalog()
    # Snapshot of the real catalog at WP-SURFACE1 base; guards silent drift.
    assert set(matter) == {
        "matter/regolith-loose", "matter/regolith-compacted", "matter/basalt",
        "matter/fractured-basalt", "matter/water-ice", "matter/iron-nickel-ore",
        "matter/silicate-waste",
    }


def test_live_taxonomy_and_bindings_valid():
    result = validate_bindings()
    assert result["bindings"] == [
        "matter/basalt", "matter/fractured-basalt", "matter/regolith-compacted",
        "matter/regolith-loose", "matter/water-ice",
    ]
    assert "surface-family/sand" in result["families"]


def test_pending_sand_family_has_no_binding():
    _, rules = load_documents()
    sand_bindings = [b for b in rules["bindings"] if b["surface_family"] == "surface-family/sand"]
    assert sand_bindings == []


# ------------------------------------------------------- negative mutation proofs

def _tamper(mutation):
    taxonomy, rules = load_documents()
    taxonomy = deepcopy(taxonomy)
    rules = deepcopy(rules)
    mutation(taxonomy, rules)
    return taxonomy, rules


def test_unknown_matter_id_fails():
    taxonomy, rules = _tamper(lambda t, r: r["bindings"].append(
        {"matter_id": "matter/martian-sand", "surface_family": "surface-family/sand",
         "surface": "surface/sand", "rationale": "invented"}))
    with pytest.raises(BindingError, match="FAIL_ON_UNKNOWN_MATTER_ID"):
        validate_bindings(taxonomy, rules)


def test_ambiguous_binding_fails():
    def bind_silicate_waste_as_regolith(t, r):
        r["bindings"].append({"matter_id": "matter/silicate-waste",
                              "surface_family": "surface-family/regolith",
                              "surface": "surface/regolith", "rationale": "ambiguous"})
    taxonomy, rules = _tamper(bind_silicate_waste_as_regolith)
    with pytest.raises(BindingError, match="FAIL_ON_FAMILY_MISMATCH"):
        validate_bindings(taxonomy, rules)


def test_family_mismatch_fails():
    def rebind_ice_to_basalt(t, r):
        for binding in r["bindings"]:
            if binding["matter_id"] == "matter/water-ice":
                binding["surface_family"] = "surface-family/basalt"
                binding["surface"] = "surface/basalt"
    taxonomy, rules = _tamper(rebind_ice_to_basalt)
    with pytest.raises(BindingError, match="FAIL_ON_FAMILY_MISMATCH"):
        validate_bindings(taxonomy, rules)


def test_pending_family_binding_fails():
    def bind_unbound_matter_as_sand(t, r):
        r["bindings"].append({"matter_id": "matter/silicate-waste",
                              "surface_family": "surface-family/sand",
                              "surface": "surface/sand", "rationale": "pending"})
    taxonomy, rules = _tamper(bind_unbound_matter_as_sand)
    with pytest.raises(BindingError, match="PENDING_FAMILY_MUST_NOT_BIND"):
        validate_bindings(taxonomy, rules)


def test_duplicate_family_id_fails():
    taxonomy, rules = _tamper(lambda t, r: t["families"].append(deepcopy(t["families"][0])))
    with pytest.raises(AssertionError, match="duplicate family id"):
        validate_bindings(taxonomy, rules)


def test_binding_to_undeclared_surface_fails():
    def bind_to_secret_surface(t, r):
        r["bindings"].append({"matter_id": "matter/water-ice",
                              "surface_family": "surface-family/ice",
                              "surface": "surface/secret-ice", "rationale": "undeclared"})
    taxonomy, rules = _tamper(bind_to_secret_surface)
    with pytest.raises(BindingError, match="BIND_EXISTING_MATTER_ONLY"):
        validate_bindings(taxonomy, rules)


def test_explicitly_unbound_matter_cannot_be_bound():
    def bind_ore(t, r):
        r["bindings"].append({"matter_id": "matter/iron-nickel-ore",
                              "surface_family": "surface-family/basalt",
                              "surface": "surface/basalt", "rationale": "ore is rock"})
    taxonomy, rules = _tamper(bind_ore)
    with pytest.raises(BindingError, match="FAIL_ON_AMBIGUOUS_BINDING|FAIL_ON_FAMILY_MISMATCH"):
        validate_bindings(taxonomy, rules)
