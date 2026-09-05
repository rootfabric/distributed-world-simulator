# WP-CONTENT1 focused tests: SOURCE_POLICY milestone.
#
# Validates:
#   1. the candidate source schema file itself is well-formed;
#   2. policy invariants from docs/world_packs/sources/SOURCE_POLICY_RU.md
#      hold for every descriptor stored under config/world_packs/library/candidates;
#   3. valid/invalid fixtures behave as the policy requires;
#   4. no heavy/binary payloads live under the candidates tree.
#
# stdlib-first; jsonschema is used only when installed (extra assurance),
# policy invariants are enforced by explicit checks regardless.

from __future__ import annotations

import json
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
CANDIDATES_DIR = ROOT / "config/world_packs/library/candidates"
SCHEMA_PATH = CANDIDATES_DIR / "schema/candidate_source.v1.json"

try:  # optional extra assurance, not required
    import jsonschema  # type: ignore

    HAS_JSONSCHEMA = True
except Exception:
    jsonschema = None  # type: ignore
    HAS_JSONSCHEMA = False

FAMILIES = {"rock_cliff", "sand_gravel", "soil_ground", "ice", "snow"}
STATUSES = {"discovery", "license_verified", "bytes_verified", "rejected"}
URL_RE = re.compile(r"^https://\S+$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def load_descriptors() -> list[dict]:
    out = []
    for p in sorted(CANDIDATES_DIR.rglob("*.json")):
        if p == SCHEMA_PATH:
            continue
        out.append(json.loads(p.read_text(encoding="utf-8")))
    return out


def check_descriptor(d: dict) -> list[str]:
    errors: list[str] = []

    def err(msg: str) -> None:
        errors.append(msg)

    cid = d.get("candidate_id", "<missing>")
    if d.get("schema") != "dws.world_packs.candidate_source.v1":
        err(f"{cid}: wrong schema tag")
    if not re.fullmatch(r"candidate/[a-z0-9][a-z0-9-]*/[a-z0-9][a-z0-9-]*", cid or ""):
        err(f"{cid}: bad candidate_id")
    if d.get("family") not in FAMILIES:
        err(f"{cid}: family must be one of {sorted(FAMILIES)}")
    status = d.get("review_status")
    if status not in STATUSES:
        err(f"{cid}: bad review_status")

    # upstream
    up = d.get("upstream", {})
    if not URL_RE.match(up.get("page_url", "")):
        err(f"{cid}: upstream.page_url must be https URL")
    if not up.get("site") or not up.get("asset_identity"):
        err(f"{cid}: upstream site/asset_identity required")
    author = up.get("author")
    if author is not None and not up.get("author_observed_on"):
        err(f"{cid}: author set without author_observed_on")
    if author is None and up.get("author_observed_on"):
        err(f"{cid}: author_observed_on set without author")

    # license
    lic = d.get("license", {})
    if not URL_RE.match(lic.get("license_url", "")):
        err(f"{cid}: license_url must be https URL")
    v = lic.get("verified", {})
    if v.get("method") == "not_verified" and lic.get("expression") not in {"unknown", "rejected"}:
        err(f"{cid}: concrete license expression requires verification record")
    if v.get("method") != "not_verified" and not URL_RE.match(v.get("verified_url", "")):
        err(f"{cid}: verification requires verified_url")

    # observed: THE core anti-invention rule
    obs = d.get("observed", {})
    sha = obs.get("sha256")
    nbytes = obs.get("expected_bytes")
    if status != "bytes_verified":
        if sha is not None:
            err(f"{cid}: sha256 present but review_status={status} (bytes not verified)")
        if nbytes is not None:
            err(f"{cid}: expected_bytes present but review_status={status} (bytes not verified)")
    else:
        if sha is None or not SHA256_RE.fullmatch(sha or ""):
            err(f"{cid}: bytes_verified requires real sha256")
        if not isinstance(nbytes, int) or nbytes < 1:
            err(f"{cid}: bytes_verified requires expected_bytes")
    maps = obs.get("pbr_maps_observed", [])
    allowed_maps = {
        "diffuse_albedo", "normal_gl", "normal_dx", "roughness",
        "ao", "displacement", "arm", "metalness", "opacity",
    }
    if not isinstance(maps, list) or len(maps) != len(set(maps)) or set(maps) - allowed_maps:
        err(f"{cid}: pbr_maps_observed must be unique known map names or []")
    if not obs.get("observation"):
        err(f"{cid}: observation text required")

    # provenance
    prov = d.get("provenance", {})
    if prov.get("measured_reference") is True and not URL_RE.match(prov.get("measured_evidence_url") or ""):
        err(f"{cid}: measured_reference=true requires measured_evidence_url")
    if prov.get("class") == "measured_reference" and prov.get("measured_reference") is not True:
        err(f"{cid}: measured_reference class requires measured_reference=true")

    # intended use
    use = d.get("intended_use", {})
    if not use.get("surface_families"):
        err(f"{cid}: intended_use.surface_families required")

    if status == "rejected" and not d.get("rejection_reason"):
        err(f"{cid}: rejected requires rejection_reason")

    return errors


def test_schema_file_is_well_formed():
    data = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    assert data["$id"] == "urn:dws:world_packs:candidate_source:1"
    assert data["$schema"].startswith("https://json-schema.org/draft/2020-12")
    fam_enum = data["$defs"]["candidate"]["properties"]["family"]["enum"]
    assert set(fam_enum) == FAMILIES


def test_all_stored_descriptors_satisfy_policy():
    descriptors = load_descriptors()
    # The SOURCE_POLICY milestone itself may run before any candidate is
    # stored; once candidates land this loop is non-trivial.
    problems = [e for d in descriptors for e in check_descriptor(d)]
    assert problems == []


VALID_DISCOVERY = {
    "schema": "dws.world_packs.candidate_source.v1",
    "candidate_id": "candidate/example/test-good",
    "family": "rock_cliff",
    "review_status": "discovery",
    "upstream": {
        "site": "example",
        "page_url": "https://example.com/a/test-good",
        "asset_identity": "Test Good",
        "author": None,
        "author_observed_on": None,
    },
    "license": {
        "expression": "CC0-1.0",
        "license_url": "https://example.com/license",
        "applies_to": "downloadable_assets",
        "verified": {
            "method": "page_license_statement",
            "verified_url": "https://example.com/license",
            "verified_at_utc": "2026-09-05",
        },
    },
    "observed": {
        "sha256": None,
        "expected_bytes": None,
        "resolution_variant": None,
        "pbr_maps_observed": ["diffuse_albedo", "normal_gl"],
        "observation": "Page lists diffuse and GL normal maps.",
    },
    "provenance": {
        "class": "photogrammetry",
        "measured_reference": False,
        "claims": ["photogrammetry capture"],
    },
    "intended_use": {
        "surface_families": ["cliff"],
        "fidelity_tier": "standard",
        "notes": "Baseline candidate.",
    },
    "recorded_at_utc": "2026-09-05",
    "recorded_by": "WP-CONTENT1",
}


@pytest.mark.parametrize(
    "mutation,expected_fragment",
    [
        (lambda d: d["observed"].update(sha256="0" * 64), "sha256 present"),
        (lambda d: d["observed"].update(expected_bytes=12345), "expected_bytes present"),
        (lambda d: d["upstream"].update(author="Someone"), "author set without"),
        (
            lambda d: d["provenance"].update(measured_reference=True),
            "measured_reference=true requires",
        ),
        (
            lambda d: d["upstream"].update(page_url="http://example.com/a"),
            "page_url must be https",
        ),
        (
            lambda d: d["license"]["verified"].update(method="not_verified"),
            "requires verification record",
        ),
        (
            lambda d: d.update(review_status="rejected"),
            "rejected requires rejection_reason",
        ),
    ],
)
def test_policy_rejects_unproven_facts(mutation, expected_fragment):
    import copy

    d = copy.deepcopy(VALID_DISCOVERY)
    mutation(d)
    problems = check_descriptor(d)
    assert problems and expected_fragment in problems[0], problems


def test_valid_discovery_descriptor_passes():
    assert check_descriptor(VALID_DISCOVERY) == []


def test_bytes_verified_requires_real_hash():
    import copy

    d = copy.deepcopy(VALID_DISCOVERY)
    d["review_status"] = "bytes_verified"
    problems = check_descriptor(d)
    assert any("requires real sha256" in p for p in problems)


@pytest.mark.skipif(not HAS_JSONSCHEMA, reason="jsonschema not installed")
def test_schema_validates_good_fixture():
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    jsonschema.validate(VALID_DISCOVERY, schema)


def test_rock_cliff_candidates_present():
    descriptors = [d for d in load_descriptors() if d.get("family") == "rock_cliff"]
    assert len(descriptors) >= 2, "ROCK_AND_CLIFF_CANDIDATES milestone expects at least two stored descriptors"
    assert all(d["observed"]["sha256"] is None for d in descriptors), "discovery-stage rock candidates must not claim hashes"


def test_no_heavy_payloads_in_candidates_tree():
    allowed_suffixes = {".json", ".md"}
    for p in CANDIDATES_DIR.rglob("*"):
        if not p.is_file():
            continue
        assert p.suffix.lower() in allowed_suffixes, f"non-catalog file: {p.name}"
        assert p.stat().st_size <= 256 * 1024, f"file too large for Git: {p.name}"
