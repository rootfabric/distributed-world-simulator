"""End-to-end CLI tests for the WP-TOOLS1 authoring CLI.

The CLI is invoked exactly as a human would invoke it (subprocess, real
interpreter) so exit codes, stderr contract and stdout JSON are all covered.
Resolver identity is asserted against the existing WP1.0 contract module to
prove there is no second incompatible resolver.
"""
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


def run_cli(*argv, check=None):
    result = subprocess.run([sys.executable, str(CLI), *argv],
                            capture_output=True, text=True, check=False)
    if check is not None:
        assert result.returncode == check, (result.returncode, result.stdout, result.stderr)
    return result


def test_version_and_help():
    version = run_cli("--version", check=0)
    assert "wp 1." in version.stdout and "library_contract" in version.stdout
    help_text = run_cli("--help", check=0)
    for token in ("validate", "WP1.0", "no second resolver"):
        assert token in help_text.stdout
    validate_help = run_cli("validate", "--help", check=0)
    assert "--catalog" in validate_help.stdout and "--locations" in validate_help.stdout


def test_unknown_command_is_usage_error_without_traceback():
    result = run_cli("definitely-not-a-command", check=2)
    assert "Traceback" not in result.stderr


def test_no_command_prints_help():
    result = run_cli(check=2)
    assert "usage:" in result.stderr


def test_validate_repo_defaults_pass():
    result = run_cli("validate", check=0)
    summary = json.loads(result.stdout)
    assert summary["result"] == "PASS"
    assert summary["resolver"].endswith("library_contract.py)")
    assert summary["counts"]["recipes"] >= 1
    assert "wp validate: PASS" in result.stderr


def test_validate_missing_file_fails_cleanly(tmp_path):
    result = run_cli("validate", "--locations", str(tmp_path / "missing.json"), check=1)
    assert result.stdout.strip() == ""
    assert "wp: FAIL:" in result.stderr and "Traceback" not in result.stderr


def test_validate_rejects_contract_violation(tmp_path):
    catalog = wp.read_json(wp.CATALOG_PATH)
    catalog["surfaces"][0]["variants"][0]["assets"] = ["asset/missing@1.0.0"]
    bad = tmp_path / "catalog.bad.json"
    bad.write_text(json.dumps(catalog), encoding="utf-8")
    result = run_cli("validate", "--catalog", str(bad), check=1)
    assert "missing asset" in result.stderr
