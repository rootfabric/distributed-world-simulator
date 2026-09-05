"""WP-VIS1 GENERIC_LAB_SCAFFOLD tests.

Structural checks for the presentation-only Surface Material Lab scaffold:
- fixture registry declares the six required orientation fixtures;
- descriptors are structurally sound (ids, shapes, milestones, normals);
- the lab scene is wired to the lab script;
- no production terrain/Matter/collision/ECO paths are referenced.
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[3]
LAB_DIR = ROOT / "scripts/world_packs/labs"
FIXTURES_GD = LAB_DIR / "surface_material_lab_fixtures.gd"
LAB_GD = LAB_DIR / "surface_material_lab.gd"
SCENE_TSCN = ROOT / "scenes/labs/world_packs/surface_material_lab.tscn"

REQUIRED_FIXTURE_IDS = [
    "horizontal_plane",
    "slope_45",
    "vertical_wall",
    "overhang",
    "inverted_ceiling",
    "sphere_fixture",
]

FIXTURE_TO_MILESTONE = {
    "horizontal_plane": "HORIZONTAL_VERTICAL_AND_SLOPED_SURFACES",
    "slope_45": "HORIZONTAL_VERTICAL_AND_SLOPED_SURFACES",
    "vertical_wall": "HORIZONTAL_VERTICAL_AND_SLOPED_SURFACES",
    "overhang": "OVERHANG_AND_INVERTED_SURFACES",
    "inverted_ceiling": "OVERHANG_AND_INVERTED_SURFACES",
    "sphere_fixture": "SPHERE_OR_IRREGULAR_FIXTURE",
}

# Registry blocks appear as `{` ... `},` dictionaries inside FIXTURES.
_BLOCK_RE = re.compile(r"\{\n(?:[^\n]|\n(?!\t\},?\n))+?\n\t\},?", re.S)


def _fixture_blocks(source: str) -> dict[str, str]:
    blocks: dict[str, str] = {}
    start = source.index("const FIXTURES")
    body = source[start:]
    for match in _BLOCK_RE.finditer(body):
        block = match.group(0)
        id_match = re.search(r'"id":\s*"([^"]+)"', block)
        if id_match:
            blocks[id_match.group(1)] = block
    return blocks


@pytest.fixture(scope="module")
def fixtures_source() -> str:
    return FIXTURES_GD.read_text(encoding="utf-8")


@pytest.fixture(scope="module")
def fixture_blocks(fixtures_source: str) -> dict[str, str]:
    blocks = _fixture_blocks(fixtures_source)
    assert blocks, "no fixture descriptor blocks found in registry"
    return blocks


def test_required_fixture_ids_declared(fixture_blocks: dict[str, str]) -> None:
    for fixture_id in REQUIRED_FIXTURE_IDS:
        assert fixture_id in fixture_blocks, f"missing fixture: {fixture_id}"


@pytest.mark.parametrize("fixture_id", REQUIRED_FIXTURE_IDS)
def test_fixture_descriptor_structure(fixture_blocks: dict[str, str], fixture_id: str) -> None:
    block = fixture_blocks[fixture_id]
    for key in (
        "id",
        "label",
        "shape",
        "size",
        "position",
        "rotation_degrees",
        "surface_normal_local",
        "diagnostic_color",
        "built_in_milestone",
    ):
        assert f'"{key}"' in block, f"{fixture_id} lacks key {key}"
    assert '"box"' in block or '"sphere"' in block, f"{fixture_id} shape unsupported"


@pytest.mark.parametrize("fixture_id", list(FIXTURE_TO_MILESTONE))
def test_fixture_milestone_assignment(
    fixture_blocks: dict[str, str], fixture_id: str
) -> None:
    block = fixture_blocks[fixture_id]
    milestone = FIXTURE_TO_MILESTONE[fixture_id]
    assert f'"built_in_milestone": "{milestone}"' in block


def test_registry_declares_scaffold_builds_no_surface_yet(fixtures_source: str) -> None:
    # The scaffold milestone must not claim any real oriented surface yet:
    # every fixture is assigned to a later milestone.
    assert f'"{list(FIXTURE_TO_MILESTONE)[0]}"' in fixtures_source
    for block in _fixture_blocks(fixtures_source).values():
        assert '"built_in_milestone": "GENERIC_LAB_SCAFFOLD"' not in block


def test_lab_scene_wired_to_lab_script() -> None:
    scene = SCENE_TSCN.read_text(encoding="utf-8")
    assert 'path="res://scripts/world_packs/labs/surface_material_lab.gd"' in scene
    assert 'name="SurfaceMaterialLab"' in scene


def test_lab_script_uses_fixture_registry_not_global_up_truth() -> None:
    lab = LAB_GD.read_text(encoding="utf-8")
    assert 'preload("res://scripts/world_packs/labs/surface_material_lab_fixtures.gd")' in lab
    assert "surface_normal_local" in lab
    # Mapping/build code must derive orientation from descriptors, not from
    # Vector3.UP as physical truth. The only permitted Vector3.UP use is the
    # rendering fallback inside the marker-arrow helper, which is display
    # geometry, not orientation semantics.
    arrow_helper_index = lab.index("func _make_normal_arrow")
    before_helper = lab[:arrow_helper_index]
    after_helper = lab[arrow_helper_index:]
    assert "Vector3.UP" not in before_helper
    assert before_helper.count("Vector3.UP") == 0
    assert after_helper.count("Vector3.UP") <= 2


def test_scaffold_files_stay_out_of_production_ownership(tmp_path: Path) -> None:
    for relative in (
        "scripts/world_packs/labs/surface_material_lab.gd",
        "scripts/world_packs/labs/surface_material_lab_fixtures.gd",
        "scripts/world_packs/labs/surface_material_lab_self_check.gd",
        "scenes/labs/world_packs/surface_material_lab.tscn",
    ):
        text = (ROOT / relative).read_text(encoding="utf-8")
        for forbidden in (
            "matter/mutations",
            "scripts/simulation",
            "scripts/network",
            "scenes/main",
            "project.godot",
        ):
            assert forbidden not in text, f"{relative} references {forbidden}"
