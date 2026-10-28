"""INSPECT_AND_INDEX tests: deterministic digests, full index, strict refs."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
CLI = ROOT / "tools" / "world_packs" / "wp_cli" / "__main__.py"

_spec = importlib.util.spec_from_file_location(
    "wp_library", ROOT / "tools" / "world_packs" / "library_contract.py")
wp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wp)

REFS = ["asset/dws/diagnostic-swatch@1.0.0", "surface/basalt@1.0.0",
        "recipe/lunar-swatch@1.0.0", "environment/airless@1.0.0"]


def run_cli(*argv, check=None):
    result = subprocess.run([sys.executable, str(CLI), *argv],
                            capture_output=True, text=True, check=False)
    if check is not None:
        assert result.returncode == check, (result.returncode, result.stdout, result.stderr)
    return result


def test_index_covers_every_descriptor_with_contract_digests():
    result = run_cli("index", check=0)
    document = json.loads(result.stdout)
    assert document["schema"] == "dws.world_packs.library_index.v1"
    catalog = wp.read_json(wp.CATALOG_PATH)
    total = 0
    for group in ("assets", "surfaces", "environments", "recipes"):
        expected = {wp.reference(e): wp.digest(e) for e in catalog[group]}
        assert document["descriptors"][group] == expected
        total += len(expected)
    assert sum(document["counts"].values()) == total


def test_index_is_deterministic_and_stable():
    first = run_cli("index", check=0).stdout
    second = run_cli("index", check=0).stdout
    assert first == second
    assert json.loads(first)["index_digest"] == json.loads(second)["index_digest"]


def test_index_writes_file(tmp_path):
    out = tmp_path / "index.json"
    run_cli("index", "--out", str(out), check=0)
    written = json.loads(out.read_text(encoding="utf-8"))
    stdout_version = json.loads(run_cli("index", check=0).stdout)
    assert written == stdout_version


def test_inspect_reports_group_digest_and_descriptor():
    result = run_cli("inspect", *REFS, check=0)
    report = json.loads(result.stdout)
    assert set(report["refs"]) == set(REFS) and report["missing"] == []
    entry = report["refs"]["surface/basalt@1.0.0"]
    assert entry["group"] == "surfaces"
    assert entry["digest"] == wp.digest(wp.read_json(wp.CATALOG_PATH)["surfaces"][0])
    assert entry["descriptor"]["canonical_material_ids"][0] == "matter/basalt"


def test_inspect_rejects_unknown_reference():
    result = run_cli("inspect", "surface/basalt@1.0.0", "asset/nope@1.0.0", check=1)
    assert "unknown reference" in result.stderr and "asset/nope@1.0.0" in result.stderr


def test_inspect_and_index_share_contract_digest_identity():
    inspect_doc = json.loads(run_cli("inspect", *REFS, check=0).stdout)
    index_doc = json.loads(run_cli("index", check=0).stdout)
    for ref, info in inspect_doc["refs"].items():
        group = info["group"]
        assert index_doc["descriptors"][group][ref] == info["digest"]
