"""Scale fixture tests: determinism, contract compliance, measured scale runs.

1,000 and 10,000 descriptor runs exercise the EXISTING WP1.0 resolver; no
payload bytes are created, fetched or committed.
"""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
CLI = ROOT / "tools" / "world_packs" / "wp_cli" / "__main__.py"

_spec_lib = importlib.util.spec_from_file_location(
    "wp_library", ROOT / "tools" / "world_packs" / "library_contract.py")
wp = importlib.util.module_from_spec(_spec_lib)
_spec_lib.loader.exec_module(wp)

sys.path.insert(0, str(ROOT / "tools" / "world_packs"))
from wp_cli import scale  # noqa: E402


def run_cli(*argv, check=None):
    result = subprocess.run([sys.executable, str(CLI), *argv],
                            capture_output=True, text=True, check=False)
    if check is not None:
        assert result.returncode == check, (result.returncode, result.stdout, result.stderr)
    return result


def test_generated_documents_are_deterministic(tmp_path):
    first = tmp_path / "a"
    second = tmp_path / "b"
    r1 = run_cli("scale-fixture", "--count", "1000", "--seed", "7",
                 "--out", str(first), check=0)
    r2 = run_cli("scale-fixture", "--count", "1000", "--seed", "7",
                 "--out", str(second), check=0)
    for name in sorted(p.name for p in first.iterdir()):
        assert (first / name).read_bytes() == (second / name).read_bytes(), name
    assert json.loads(r1.stdout)["presentation_lock_hash"] == \
        json.loads(r2.stdout)["presentation_lock_hash"]


def test_generator_counts_and_contract_compliance(tmp_path):
    catalog, locations = scale.generate(1000, 7)
    assert scale.descriptor_total(catalog) == 1000
    assert len(catalog["recipes"]) <= scale.MAX_RECIPES
    schema = wp.read_json(wp.SCHEMA_PATH)
    index = wp.validate(catalog, locations, schema)  # full WP1.0 validation
    lock = wp.resolve(index, scale.ROOT_RECIPE)
    assert lock["schema"] == "dws.world_presentation_lock.v1"
    # no payload files were created anywhere by generation itself
    assert not list(tmp_path.iterdir())


def test_different_seed_changes_documents():
    c1, _ = scale.generate(1000, 7)
    c2, _ = scale.generate(1000, 8)
    assert c1["assets"][0]["sha256"] != c2["assets"][0]["sha256"]


def test_synthetic_1k_scale_measured(tmp_path):
    result = run_cli("scale-fixture", "--count", "1000", "--seed", "7",
                     "--out", str(tmp_path), check=0)
    report = json.loads(result.stdout)
    assert report["result"] == "PASS"
    assert report["descriptor_total"] == 1000
    assert report["resolver"].endswith("library_contract.py)")
    assert set(report["timings_sec"]) == {"read", "validate", "resolve"}
    # the emitted documents also pass the standalone validate command
    run_cli("validate", "--catalog", report["catalog"],
            "--locations", report["locations"], check=0)
    run_cli("resolve", "--recipe", scale.ROOT_RECIPE,
            "--catalog", report["catalog"],
            "--locations", report["locations"], check=0)


def test_synthetic_10k_scale_measured(tmp_path):
    result = run_cli("scale-fixture", "--count", "10000", "--seed", "7",
                     "--out", str(tmp_path), check=0)
    report = json.loads(result.stdout)
    assert report["result"] == "PASS"
    assert report["descriptor_total"] == 10000
    assert report["counts"]["assets"] + report["counts"]["surfaces"] > 9000
    run_cli("validate", "--catalog", report["catalog"],
            "--locations", report["locations"], check=0)


def test_rejects_tiny_count():
    run_cli("scale-fixture", "--count", "3", "--seed", "1",
            "--out", str(Path(".")), check=1)
