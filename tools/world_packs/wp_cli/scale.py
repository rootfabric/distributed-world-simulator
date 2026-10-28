"""Deterministic synthetic scale fixtures (SYNTHETIC_1K/10K milestones).

Generates metadata-only descriptors that satisfy the existing WP1.0 contract:
assets, surfaces, recipes, environments and matching source-location entries.
No payloads are created or fetched — synthetic sources use reserved example
hostnames, which the contract validates syntactically offline.

Determinism: identical (count, seed) inputs produce byte-identical documents
and an identical presentation lock for the synthetic root recipe.
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

from . import contract
from .app import emit_json, fail

MAX_RECIPES = 128  # library_schema.v1.json: catalog recipes maxItems
SYNTHETIC_SOURCE_HOST = "https://assets.example.org/synthetic"
ROOT_RECIPE = "recipe/syn-0@1.0.0"


def _asset(seed: int, i: int) -> dict:
    return {
        "id": f"asset/syn/a-{i}",
        "version": "1.0.0",
        "sha256": contract.wp.digest({"kind": "asset", "seed": seed, "i": i}),
        "expected_bytes": 100 + (i % 9000),
        "media_type": "text/plain",
        "archive_type": "none",
        "import_recipe": {"id": "import/synthetic", "version": "1.0.0"},
        "license": {
            "expression": "CC0-1.0",
            "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
            "author": "WP-TOOLS1 synthetic scale generator",
            "attribution_required": False,
            "attribution": "",
            "redistribution": "allowed",
            "commercial_use": "allowed",
            "provenance": "Deterministic synthetic descriptor generated offline; no external asset content.",
        },
        "tags": ["synthetic", "scale-fixture"],
    }


def _surface(i: int, asset_count: int) -> dict:
    return {
        "id": f"surface/syn/s-{i}",
        "version": "1.0.0",
        "canonical_material_ids": [f"matter/syn-m-{i}"],
        "variants": [{
            "id": "diagnostic",
            "tier": "casual",
            "evidence_class": "artistic",
            "assets": [f"asset/syn/a-{i % asset_count}@1.0.0"],
            "states": ["default"],
            "coordinate_space": "body_fixed",
            "mapping": "triplanar",
            "scale_bands": ["local"],
            "requires": [],
        }],
        "tags": ["synthetic", "scale-fixture"],
    }


def _locations_entry(seed: int, asset: dict) -> dict:
    return {
        "asset": f"{asset['id']}@{asset['version']}",
        "sha256": asset["sha256"],
        "sources": [{
            "type": "https",
            "locator": f"{SYNTHETIC_SOURCE_HOST}/{seed}/{asset['id'].split('/')[-1]}.txt",
            "source_version": f"synthetic-{seed}",
            "role": "upstream",
        }],
    }


def generate(count: int, seed: int) -> tuple[dict, dict]:
    """Build (catalog, locations) with exactly `count` descriptors total."""
    if count < 10:
        raise ValueError("count must be >= 10")
    recipe_count = min(MAX_RECIPES, max(2, count // 200))
    remaining = count - recipe_count - 1  # 1 environment
    asset_count = remaining * 3 // 5
    surface_count = remaining - asset_count
    assets = [_asset(seed, i) for i in range(asset_count)]
    surfaces = [_surface(i, asset_count) for i in range(surface_count)]
    environment = {"id": "environment/syn-airless", "version": "1.0.0",
                   "presentation_only": True, "tags": ["synthetic"]}
    recipes = [{
        "id": "recipe/syn-0",
        "version": "1.0.0",
        "includes": [f"recipe/syn-{j}@1.0.0" for j in range(1, recipe_count)],
        "bindings": [],
        "environments": ["environment/syn-airless@1.0.0"],
        "tags": ["synthetic", "scale-fixture"],
    }]
    children = recipe_count - 1
    for j in range(1, recipe_count):
        bindings = []
        for i in range(surface_count):
            if i % children == j - 1:
                bindings.append({"material_id": f"matter/syn-m-{i}",
                                 "surface": f"surface/syn/s-{i}@1.0.0"})
        recipes.append({"id": f"recipe/syn-{j}", "version": "1.0.0",
                        "includes": [], "bindings": bindings, "environments": [],
                        "tags": ["synthetic", "scale-fixture"]})
    # rounding guard: pad surfaces so the descriptor total is exactly `count`
    for extra in range(count - (len(assets) + len(surfaces) + len(recipes) + 1)):
        surfaces.append(_surface(surface_count + extra, asset_count))
    catalog = {"schema": "dws.world_library.v1", "status": "DRAFT_CONTRACT_FIXTURE",
               "assets": assets, "surfaces": surfaces, "environments": [environment],
               "recipes": recipes}
    locations = {"schema": "dws.world_asset_sources.v1",
                 "entries": [_locations_entry(seed, a) for a in assets]}
    return catalog, locations


def descriptor_total(catalog: dict) -> int:
    return sum(len(catalog[group]) for group in contract.wp.GROUPS)


def measure(catalog_path: Path, locations_path: Path) -> dict:
    """Time read/validate/resolve on generated documents (existing resolver)."""
    timings = {}
    start = time.perf_counter()
    catalog = contract.wp.read_json(catalog_path)
    locations = contract.wp.read_json(locations_path)
    schema = contract.wp.read_json(contract.wp.SCHEMA_PATH)
    timings["read"] = round(time.perf_counter() - start, 4)
    start = time.perf_counter()
    index = contract.wp.validate(catalog, locations, schema)
    timings["validate"] = round(time.perf_counter() - start, 4)
    start = time.perf_counter()
    lock = contract.wp.resolve(index, ROOT_RECIPE)
    timings["resolve"] = round(time.perf_counter() - start, 4)
    return {
        "resolver": "wp-set-json-v1 (tools/world_packs/library_contract.py)",
        "counts": {group: len(catalog[group]) for group in contract.wp.GROUPS},
        "descriptor_total": descriptor_total(catalog),
        "location_entries": len(locations["entries"]),
        "timings_sec": timings,
        "presentation_lock_hash": lock["presentation_lock_hash"],
        "result": "PASS",
    }


def cmd_scale_fixture(args) -> int:
    try:
        catalog, locations = generate(args.count, args.seed)
        if descriptor_total(catalog) != args.count:
            return fail(f"scale-fixture: generated {descriptor_total(catalog)} "
                        f"descriptors, expected {args.count}")
        out_dir = Path(args.out)
        out_dir.mkdir(parents=True, exist_ok=True)
        catalog_path = out_dir / f"synthetic-catalog-{args.count}-{args.seed}.json"
        locations_path = out_dir / f"synthetic-locations-{args.count}-{args.seed}.json"
        catalog_path.write_text(json.dumps(catalog, indent=2) + "\n",
                                encoding="utf-8", newline="\n")
        locations_path.write_text(json.dumps(locations, indent=2) + "\n",
                                  encoding="utf-8", newline="\n")
        report = measure(catalog_path, locations_path)
    except (ValueError, OSError) as exc:
        return fail(f"scale-fixture: {exc}")
    report["count"] = args.count
    report["seed"] = args.seed
    report["catalog"] = str(catalog_path)
    report["locations"] = str(locations_path)
    emit_json(report)
    print(f"wp scale-fixture: PASS ({args.count} descriptors, seed {args.seed})",
          file=sys.stderr)
    return 0
