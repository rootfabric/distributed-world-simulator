"""Command implementations for the WORLD PACKS authoring CLI.

Every command returns an int exit code: 0 = success, 1 = contract/data
failure reported on stderr without a traceback, 2 = usage error (argparse).
Resolver semantics always come from :mod:`wp_cli.contract` (the existing
WP1.0 library contract module); this file only formats output.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

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


def _doctor_checks(catalog_path, locations_path, schema_path, packs_dir, pack_schema_path,
                   verify_fixtures: bool):
    """Yield (name, status, detail) triples. status in OK/FAIL/SKIP."""
    import platform

    results = []
    failed = set()

    def record(name, ok, detail, skip_reason=None):
        if skip_reason is not None:
            status = "SKIP"
        elif ok:
            status = "OK"
        else:
            status = "FAIL"
            failed.add(name)
        results.append((name, status, detail if skip_reason is None else skip_reason))
        return status == "OK"

    ok_python = contract.python_ok()
    record("python_runtime", ok_python,
           f"{platform.python_version()} (contract requires >= 3.11 for hashlib.file_digest)")
    try:
        import jsonschema
        from importlib.metadata import version as pkg_version
        record("jsonschema", True, f"{pkg_version('jsonschema')} (Draft202012 + Draft7 used)")
    except Exception as exc:  # pragma: no cover - only when dependency is missing
        record("jsonschema", False, f"import failed: {exc}")

    catalog = locations = schema = None
    try:
        schema = contract.wp.read_json(schema_path)
        from jsonschema import Draft202012Validator
        Draft202012Validator.check_schema(schema)
        record("library_schema", True, f"{schema_path}")
    except Exception as exc:
        record("library_schema", False, f"{schema_path}: {exc}")
    try:
        catalog = contract.wp.read_json(catalog_path)
        record("catalog_document", True,
               f"{catalog_path}: {len(catalog.get('assets', []))} assets, "
               f"{len(catalog.get('surfaces', []))} surfaces, "
               f"{len(catalog.get('recipes', []))} recipes, "
               f"{len(catalog.get('environments', []))} environments")
    except Exception as exc:
        record("catalog_document", False, f"{catalog_path}: {exc}")
    try:
        locations = contract.wp.read_json(locations_path)
        record("locations_document", True,
               f"{locations_path}: {len(locations.get('entries', []))} entries")
    except Exception as exc:
        record("locations_document", False, f"{locations_path}: {exc}")

    index = None
    if catalog is not None and locations is not None and schema is not None:
        try:
            index = contract.wp.validate(catalog, locations, schema)
            record("contract_validate", True,
                   f"WP1.0 validate: index_size={len(index)}")
        except Exception as exc:
            record("contract_validate", False, str(exc))
    else:
        record("contract_validate", True, "", skip_reason="skipped: documents unreadable")

    if not verify_fixtures:
        record("repo_fixture_bytes", True, "", skip_reason="skipped: --skip-fixtures")
    elif index is not None and locations is not None:
        fixture_errors = []
        checked = 0
        for item in locations["entries"]:
            for source in item["sources"]:
                if source["type"] != "repo_fixture":
                    continue
                checked += 1
                try:
                    path = contract.wp.local_file(contract.wp.ROOT, source["locator"])
                    contract.wp.verify_bytes(path, index[item["asset"]])
                except Exception as exc:
                    fixture_errors.append(f"{item['asset']} ({source['locator']}): {exc}")
        record("repo_fixture_bytes", not fixture_errors,
               f"{checked} fixture payload(s) verified (size + sha256)"
               if not fixture_errors else "; ".join(fixture_errors))
    elif verify_fixtures:
        record("repo_fixture_bytes", True, "",
               skip_reason="skipped: contract validation unavailable")

    if index is not None:
        try:
            lock = contract.wp.resolve(index, contract.DEFAULT_RECIPE)
            record("default_recipe_resolve", True,
                   f"{contract.DEFAULT_RECIPE} -> lock {lock['presentation_lock_hash']}")
        except Exception as exc:
            record("default_recipe_resolve", False, str(exc))
    else:
        record("default_recipe_resolve", True, "",
               skip_reason="skipped: contract validation unavailable")

    try:
        from jsonschema import Draft7Validator
        pack_schema = contract.wp.read_json(pack_schema_path)
        Draft7Validator.check_schema(pack_schema)
        pack_paths = sorted(Path(packs_dir).glob("*.json")) if Path(packs_dir).is_dir() else []
        bad_packs = []
        for path in pack_paths:
            try:
                Draft7Validator(pack_schema).validate(contract.wp.read_json(path))
            except Exception as exc:
                bad_packs.append(f"{path.name}: {exc}")
        record("legacy_pack_manifests", not bad_packs,
               f"{len(pack_paths)} pack manifest(s) valid against {pack_schema_path.name}"
               if not bad_packs else "; ".join(bad_packs))
    except Exception as exc:
        record("legacy_pack_manifests", False, str(exc))

    return results


def cmd_doctor(args) -> int:
    """Diagnostics over the whole authoring environment and contract state."""
    from pathlib import Path

    defaults_ = contract.defaults()
    catalog_path = Path(args.catalog) if args.catalog else defaults_["catalog"]
    locations_path = Path(args.locations) if args.locations else defaults_["locations"]
    schema_path = Path(args.schema) if args.schema else defaults_["schema"]
    packs_dir = Path(args.packs_dir) if args.packs_dir else defaults_["packs_dir"]
    results = _doctor_checks(catalog_path, locations_path, schema_path, packs_dir,
                             defaults_["pack_schema"], verify_fixtures=not args.skip_fixtures)
    failures = [name for name, status, _ in results if status == "FAIL"]
    if args.json:
        emit_json({
            "result": "FAIL" if failures else "PASS",
            "resolver": "wp-set-json-v1 (tools/world_packs/library_contract.py)",
            "checks": [{"name": n, "status": s, "detail": d} for n, s, d in results],
        })
    else:
        for name, status, detail in results:
            print(f"{status:>4}  {name}: {detail}")
        print(f"wp doctor: {'FAIL (' + ', '.join(failures) + ')' if failures else 'PASS'}",
              file=sys.stderr)
    return 1 if failures else 0
