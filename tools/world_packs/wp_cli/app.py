"""Command implementations for the WORLD PACKS authoring CLI.

Every command returns an int exit code: 0 = success, 1 = contract/data
failure reported on stderr without a traceback, 2 = usage error (argparse).
Resolver semantics always come from :mod:`wp_cli.contract` (the existing
WP1.0 library contract module); this file only formats output.
"""
from __future__ import annotations

import json
import sys

from . import contract

FAILURE_PREFIX = "wp: FAIL:"


def load_documents(catalog_path, locations_path, schema_path):
    """Read catalog/locations/schema through the contract's canonical reader."""
    return (contract.wp.read_json(catalog_path),
            contract.wp.read_json(locations_path),
            contract.wp.read_json(schema_path))


def emit_json(value, stream=None) -> None:
    json.dump(value, stream or sys.stdout, sort_keys=True, indent=2)
    (stream or sys.stdout).write("\n")


def fail(message: str) -> int:
    print(f"{FAILURE_PREFIX} {message}", file=sys.stderr)
    return 1


def cmd_validate(args) -> int:
    """Validate catalog + locations via the existing contract (single resolver)."""
    from pathlib import Path

    defaults_ = contract.defaults()
    catalog_path = Path(args.catalog) if args.catalog else defaults_["catalog"]
    locations_path = Path(args.locations) if args.locations else defaults_["locations"]
    schema_path = Path(args.schema) if args.schema else defaults_["schema"]
    try:
        catalog, locations, schema = load_documents(catalog_path, locations_path, schema_path)
        index = contract.wp.validate(catalog, locations, schema)
    except (contract.wp.ContractError, OSError, ValueError, RecursionError) as exc:
        return fail(f"validate: {exc}")
    summary = {
        "result": "PASS",
        "resolver": "wp-set-json-v1 (tools/world_packs/library_contract.py)",
        "catalog": str(catalog_path),
        "locations": str(locations_path),
        "counts": {group: len(catalog[group]) for group in contract.wp.GROUPS},
        "location_entries": len(locations["entries"]),
        "index_size": len(index),
    }
    emit_json(summary)
    print("wp validate: PASS", file=sys.stderr)
    return 0


def cmd_resolve(args) -> int:
    """Print the WP1.0 presentation lock for a recipe (existing resolver)."""
    from pathlib import Path

    defaults_ = contract.defaults()
    catalog_path = Path(args.catalog) if args.catalog else defaults_["catalog"]
    locations_path = Path(args.locations) if args.locations else defaults_["locations"]
    schema_path = Path(args.schema) if args.schema else defaults_["schema"]
    try:
        catalog, locations, schema = load_documents(catalog_path, locations_path, schema_path)
        index = contract.wp.validate(catalog, locations, schema)
        lock = contract.wp.resolve(index, args.recipe)
    except (contract.wp.ContractError, OSError, ValueError, RecursionError) as exc:
        return fail(f"resolve: {exc}")
    emit_json(lock)
    print(f"wp resolve: PASS ({args.recipe} -> lock {lock['presentation_lock_hash']})",
          file=sys.stderr)
    return 0
