"""Reuse bridge to the single existing WORLD PACKS library contract.

Loads ``tools/world_packs/library_contract.py`` by file location so the CLI
shares the canonical WP1.0 resolver (validate/resolve/digest/lock) instead of
duplicating it. All default paths come from the contract module itself.
"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

# tools/world_packs/wp_cli/contract.py -> repository root is three levels up.
REPO_ROOT = Path(__file__).resolve().parents[3]
CONTRACT_PATH = REPO_ROOT / "tools" / "world_packs" / "library_contract.py"
PACK_SCHEMA_PATH = REPO_ROOT / "config" / "world_packs" / "pack_schema.v1.json"
PACKS_DIR = REPO_ROOT / "config" / "world_packs" / "packs"
DEFAULT_RECIPE = "recipe/lunar-swatch@1.0.0"

if not CONTRACT_PATH.is_file():
    raise FileNotFoundError(f"library contract not found: {CONTRACT_PATH}")

_spec = importlib.util.spec_from_file_location("wp_library_contract", CONTRACT_PATH)
wp = importlib.util.module_from_spec(_spec)
if _spec.loader is None:  # pragma: no cover - defensive, loader always exists
    raise ImportError(f"cannot load contract module: {CONTRACT_PATH}")
_spec.loader.exec_module(wp)

MIN_PYTHON = (3, 11)  # hashlib.file_digest is used by the contract fixture check


def python_ok() -> bool:
    return sys.version_info >= MIN_PYTHON


def defaults() -> dict:
    """Default document paths, sourced from the contract module (no drift)."""
    return {
        "catalog": wp.CATALOG_PATH,
        "locations": wp.LOCATIONS_PATH,
        "schema": wp.SCHEMA_PATH,
        "pack_schema": PACK_SCHEMA_PATH,
        "packs_dir": PACKS_DIR,
        "root": wp.ROOT,
    }
