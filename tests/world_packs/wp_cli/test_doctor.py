"""DOCTOR_DIAGNOSTICS tests: doctor reports every layer and fails precisely."""
from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
CLI = ROOT / "tools" / "world_packs" / "wp_cli" / "__main__.py"


def run_cli(*argv, check=None):
    result = subprocess.run([sys.executable, str(CLI), *argv],
                            capture_output=True, text=True, check=False)
    if check is not None:
        assert result.returncode == check, (result.returncode, result.stdout, result.stderr)
    return result


EXPECTED_CHECKS = {
    "python_runtime", "jsonschema", "library_schema", "catalog_document",
    "locations_document", "contract_validate", "repo_fixture_bytes",
    "default_recipe_resolve", "legacy_pack_manifests",
}


def test_doctor_repo_environment_passes():
    result = run_cli("doctor", check=0)
    names = set()
    for line in result.stdout.splitlines():
        parts = line.split(":", 1)
        names.add(parts[0].strip().removeprefix("OK").strip())
    assert EXPECTED_CHECKS <= names
    assert "wp doctor: PASS" in result.stderr


def test_doctor_json_report_structure():
    result = run_cli("doctor", "--json", check=0)
    report = json.loads(result.stdout)
    assert report["result"] == "PASS"
    assert report["resolver"].endswith("library_contract.py)")
    assert EXPECTED_CHECKS == {c["name"] for c in report["checks"]}
    assert all(c["status"] in ("OK", "SKIP") for c in report["checks"])
    assert report["checks"][0]["name"] == "python_runtime"


def test_doctor_detects_corrupt_locations(tmp_path):
    bad = tmp_path / "locations.json"
    bad.write_text(json.dumps({"schema": "dws.world_asset_sources.v1", "entries": []}),
                   encoding="utf-8")
    result = run_cli("doctor", "--locations", str(bad), check=1)
    assert "OK  locations_document" in result.stdout
    assert "FAIL" in result.stdout
    assert "missing asset source" in result.stdout
    assert "wp doctor: FAIL" in result.stderr
    # dependent checks are skipped, not falsely failed
    assert "SKIP  repo_fixture_bytes" in result.stdout


def test_doctor_detects_missing_schema(tmp_path):
    result = run_cli("doctor", "--schema", str(tmp_path / "nope.json"), check=1)
    assert "FAIL  library_schema" in result.stdout


def test_doctor_skip_fixtures_still_resolves():
    result = run_cli("doctor", "--skip-fixtures", check=0)
    assert "SKIP  repo_fixture_bytes" in result.stdout
    assert "OK  default_recipe_resolve" in result.stdout
