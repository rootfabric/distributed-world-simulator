"""VALIDATE_AND_RESOLVE tests: the resolve command reuses the WP1.0 resolver.

Locks produced by the CLI must be byte-identical to locks produced by calling
``library_contract.resolve`` directly — that is the proof there is no second,
incompatible resolver.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
CLI = ROOT / "tools" / "world_packs" / "wp_cli" / "__main__.py"
RECIPE = "recipe/lunar-swatch@1.0.0"

_spec = importlib.util.spec_from_file_location(
    "wp_library", ROOT / "tools" / "world_packs" / "library_contract.py")
wp = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(wp)


def run_cli(*argv, check=None):
    result = subprocess.run([sys.executable, str(CLI), *argv],
                            capture_output=True, text=True, check=False)
    if check is not None:
        assert result.returncode == check, (result.returncode, result.stdout, result.stderr)
    return result


def direct_lock(recipe=RECIPE):
    catalog = wp.read_json(wp.CATALOG_PATH)
    locations = wp.read_json(wp.LOCATIONS_PATH)
    schema = wp.read_json(wp.SCHEMA_PATH)
    return wp.resolve(wp.validate(catalog, locations, schema), recipe)


def test_resolve_matches_contract_module_output():
    result = run_cli("resolve", check=0)
    assert json.loads(result.stdout) == direct_lock()
    assert "wp resolve: PASS" in result.stderr
    assert json.loads(result.stdout)["schema"] == "dws.world_presentation_lock.v1"
    assert json.loads(result.stdout)["resolver"] == "wp-set-json-v1"


def test_resolve_explicit_recipe_and_known_hash():
    result = run_cli("resolve", "--recipe", RECIPE, check=0)
    lock = json.loads(result.stdout)
    assert lock["presentation_lock_hash"] == \
        "bfd0fbb15d8ef5292dd79aa002cb50f11fec9f916531234ee4842a02f52140a4"
    result = run_cli("resolve", "--recipe", "recipe/rocky-base@1.0.0", check=0)
    assert json.loads(result.stdout)["recipe"] == "recipe/rocky-base@1.0.0"


def test_resolve_unknown_recipe_fails_cleanly():
    result = run_cli("resolve", "--recipe", "recipe/does-not-exist@1.0.0", check=1)
    assert "unknown recipe" in result.stderr and "Traceback" not in result.stderr


def test_resolve_reports_binding_conflict(tmp_path):
    catalog = wp.read_json(wp.CATALOG_PATH)
    surface = json.loads(json.dumps(catalog["surfaces"][0]))
    surface["id"] = "surface/alternate-basalt"
    catalog["surfaces"].append(surface)
    catalog["recipes"][0]["bindings"].append(
        {"material_id": "matter/basalt", "surface": "surface/alternate-basalt@1.0.0"})
    catalog["recipes"][1]["bindings"].append(
        {"material_id": "matter/basalt", "surface": "surface/alternate-basalt@1.0.0"})
    bad = tmp_path / "catalog.conflict.json"
    bad.write_text(json.dumps(catalog), encoding="utf-8")
    result = run_cli("resolve", "--catalog", str(bad), check=1)
    assert "conflicting material binding" in result.stderr


def test_resolve_deterministic_across_runs():
    first = run_cli("resolve", check=0).stdout
    second = run_cli("resolve", check=0).stdout
    assert first == second
