"""Executable metadata proofs, deliberately not planetary renderer E2E proofs."""
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

import pytest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("wp_library", ROOT / "tools/world_packs/library_contract.py")
wp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wp)
RECIPE = "recipe/lunar-swatch@1.0.0"


@pytest.fixture
def documents():
    return (wp.read_json(wp.CATALOG_PATH), wp.read_json(wp.LOCATIONS_PATH), wp.read_json(wp.SCHEMA_PATH))


def lock(documents):
    return wp.resolve(wp.validate(*documents), RECIPE)


def test_exact_fixture_and_lock(documents):
    catalog, locations, _ = documents
    source = locations["entries"][0]["sources"][0]["locator"]
    wp.verify_bytes(wp.local_file(ROOT, source), catalog["assets"][0])
    result = lock(documents)
    assert len(result["bindings"]) == 4
    assert result["presentation_lock_hash"] == "bfd0fbb15d8ef5292dd79aa002cb50f11fec9f916531234ee4842a02f52140a4"


def test_order_independent_resolution(documents):
    def reverse(value):
        if isinstance(value, dict):
            return {k: reverse(v) for k, v in reversed(list(value.items()))}
        if isinstance(value, list):
            return [reverse(v) for v in reversed(value)]
        return value
    assert lock(documents) == lock(tuple(reverse(x) for x in documents))


def test_storage_move_does_not_rewrite_identity(documents):
    before = lock(documents)
    documents[1]["entries"][0]["sources"] = [
        {"type": "https", "locator": "https://assets.example.org/immutable/swatch.txt",
         "source_version": "mirror-2028", "role": "mirror"}]
    assert lock(documents) == before  # Syntax only: no request to this example host.


def test_asset_or_import_change_changes_lock(documents):
    before = lock(documents)
    documents[0]["assets"][0]["import_recipe"]["version"] = "1.0.1"
    assert lock(documents) != before
    documents[0]["assets"][0]["sha256"] = "1" * 64
    documents[1]["entries"][0]["sha256"] = "1" * 64
    assert lock(documents) != before


@pytest.mark.parametrize("change", [
    lambda c, l: c.update(schema="dws.world_library.v99"),
    lambda c, l: c["assets"][0].update(expected_bytes=True),
    lambda c, l: c["assets"][0].update(expected_bytes=1.5),
    lambda c, l: c["assets"][0].update(expected_bytes=2**53),
    lambda c, l: c["assets"][0].update(sha256="bad"),
    lambda c, l: c["assets"][0].update(density_kg_m3=2900),
    lambda c, l: c["assets"].append(deepcopy(c["assets"][0])),
    lambda c, l: c["assets"][0]["license"].update(redistribution="unknown"),
    lambda c, l: c["assets"][0]["license"].update(commercial_use="forbidden"),
    lambda c, l: c["assets"][0]["license"].update(attribution_required=True, attribution=" "),
    lambda c, l: c["assets"][0]["license"].update(expression="CC-BY-4.0"),
    lambda c, l: c["assets"][0]["license"].pop("provenance"),
    lambda c, l: c["assets"][0]["license"].update(provenance=" "),
    lambda c, l: c["assets"][0]["license"].update(author=" "),
    lambda c, l: l["entries"][0]["sources"][0].update(source_version=" "),
    lambda c, l: c["assets"][0].update(id="asset/dws//swatch"),
    lambda c, l: c["surfaces"][0]["variants"][0].update(assets=["asset/missing@1.0.0"]),
    lambda c, l: c["surfaces"][0]["variants"].append(deepcopy(c["surfaces"][0]["variants"][0])),
    lambda c, l: c["recipes"][0]["bindings"][0].update(material_id="matter/water-ice"),
    lambda c, l: c["recipes"][0].update(includes=[RECIPE]),
    lambda c, l: c["recipes"][0].update(includes=["recipe/missing@1.0.0"]),
    lambda c, l: c["recipes"][0].update(environments=["environment/missing@1.0.0"]),
    lambda c, l: l.update(entries=[]),
    lambda c, l: l["entries"][0].update(sha256="0" * 64),
    lambda c, l: l["entries"][0].update(sources=[]),
    lambda c, l: l["entries"].append(deepcopy(l["entries"][0])),
])
def test_invalid_contract_rejected(documents, change):
    change(*documents[:2])
    with pytest.raises(wp.ContractError):
        lock(documents)


def test_diamond_and_conflict(documents):
    catalog = documents[0]
    parent = deepcopy(catalog["recipes"][0])
    parent.update(id="recipe/second-path", includes=["recipe/rocky-base@1.0.0"], bindings=[])
    catalog["recipes"].append(parent)
    catalog["recipes"][1]["includes"].append("recipe/second-path@1.0.0")
    assert len(lock(documents)["bindings"]) == 4
    other = deepcopy(catalog["surfaces"][0])
    other["id"] = "surface/alternate-basalt"
    catalog["surfaces"].append(other)
    parent["bindings"] = [{"material_id": "matter/basalt", "surface": "surface/alternate-basalt@1.0.0"}]
    with pytest.raises(wp.ContractError, match="conflicting material binding"):
        lock(documents)


def test_environment_conflict(documents):
    catalog = documents[0]
    env = deepcopy(catalog["environments"][0])
    env["id"] = "environment/other"
    catalog["environments"].append(env)
    catalog["recipes"][0]["environments"] = ["environment/other@1.0.0"]
    with pytest.raises(wp.ContractError, match="conflicting environment"):
        lock(documents)


@pytest.mark.parametrize("path", ["../escape", "/absolute", "a/../b", "a//b", "a/./b", "a/",
                                      "C:/drive", "a\\b", "%2e%2e/a", "\\\\server\\share", "a\x00b"])
def test_unsafe_paths_rejected(path):
    with pytest.raises(wp.ContractError):
        wp.safe_relative_path(path)


@pytest.mark.parametrize("url", ["http://example.org/file", "https://u:p@example.org/file", "https://localhost/a",
    "https://127.0.0.1/a", "https://169.254.169.254/a", "https://[::1]/a", "https://example.org:bad/a",
    "https://example.org:444/a", "https://example.org/a#fragment", "https://foo..com/a", "https://127.1/a",
    "https://example.org/ bad", "https://example.org\\@localhost/a", "file:///tmp/a"])
def test_unsafe_urls_rejected(url):
    with pytest.raises(wp.ContractError):
        wp.public_https(url)


def test_local_missing_symlink_and_corruption(documents, tmp_path):
    asset = documents[0]["assets"][0]
    with pytest.raises(OSError):
        wp.local_file(tmp_path, "missing")
    target = tmp_path / "payload"
    target.write_bytes(b"x" * asset["expected_bytes"])
    with pytest.raises(wp.ContractError, match="checksum mismatch"):
        wp.verify_bytes(target, asset)
    target.write_bytes(b"x")
    with pytest.raises(wp.ContractError, match="size mismatch"):
        wp.verify_bytes(target, asset)
    (tmp_path / "link").symlink_to(target)
    with pytest.raises(wp.ContractError, match="symlinks"):
        wp.local_file(tmp_path, "link")


@pytest.mark.parametrize("text", ['{"x":1,"x":2}', '{"x":NaN}', '{"x":Infinity}'])
def test_noncanonical_json_rejected(text, tmp_path):
    path = tmp_path / "bad.json"
    path.write_text(text)
    with pytest.raises(wp.ContractError):
        wp.read_json(path)


def test_seed_domain_separation():
    args = (123, "body/moon", "cell/4/7", "surface/basalt@1.0.0", "micro")
    assert wp.variation_token(*args) == wp.variation_token(*args)
    assert wp.variation_token(*args) != wp.variation_token(*args[:-1], "scatter")
    assert wp.variation_token(*args) != wp.variation_token(124, *args[1:])
    with pytest.raises(wp.ContractError):
        wp.variation_token(True, *args[1:])


def test_headless_cli_and_offline_missing(tmp_path):
    command = [sys.executable, str(ROOT / "tools/world_packs/library_contract.py")]
    run = subprocess.run(command + ["--verify-fixtures"], capture_output=True, text=True, check=False)
    assert run.returncode == 0, run.stderr
    assert json.loads(run.stdout)["recipe"] == RECIPE
    run = subprocess.run(command + ["--locations", str(tmp_path / "missing.json")],
                         capture_output=True, text=True, check=False)
    assert run.returncode == 1 and "FAIL" in run.stderr and "Traceback" not in run.stderr


def test_legacy_wp0_manifests_and_contract():
    from jsonschema import Draft7Validator
    schema = wp.read_json(ROOT / "config/world_packs/pack_schema.v1.json")
    validator = Draft7Validator(schema)
    paths = sorted((ROOT / "config/world_packs/packs").glob("*.json"))
    required = {f"wp_{name}.v1.json" for name in ("moon_industrial", "mars_dust", "frozen",
                "volcanic", "temperate", "alien_wetland")}
    assert required <= {path.name for path in paths}
    for path in paths:
        value = wp.read_json(path)
        validator.validate(value)
        value["unknown_optional"] = {"retained_compatibility": True}
        validator.validate(value)
        del value["environment"]
        assert list(validator.iter_errors(value)), "missing required field accepted"
