#!/usr/bin/env python3
"""WP1.0 metadata-only contract probe. No network, extraction or engine runtime."""
from __future__ import annotations

import argparse
import hashlib
import ipaddress
import json
import re
import sys
from pathlib import Path, PurePosixPath
from urllib.parse import urlsplit

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "config/world_packs/library_schema.v1.json"
CATALOG_PATH = ROOT / "config/world_packs/library/catalog.v1.json"
LOCATIONS_PATH = ROOT / "config/world_packs/library/source_locations.v1.json"
GROUPS = ("assets", "surfaces", "environments", "recipes")


class ContractError(ValueError):
    """An invalid or unsupported library contract."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)


def read_json(path: Path) -> dict:
    def unique_object(pairs: list[tuple[str, object]]) -> dict:
        result = {}
        for key, value in pairs:
            require(key not in result, f"duplicate JSON key: {key}")
            result[key] = value
        return result

    def reject_constant(value: str) -> None:
        raise ContractError(f"non-finite JSON number: {value}")

    return json.loads(path.read_text(encoding="utf-8"),
                      object_pairs_hook=unique_object, parse_constant=reject_constant)


def canonical_bytes(value: object) -> bytes:
    """WP set-json-v1: all schema arrays are sets; numbers are bounded integers."""
    if isinstance(value, dict):
        normalized = {key: json.loads(canonical_bytes(item)) for key, item in value.items()}
    elif isinstance(value, list):
        normalized = [json.loads(item) for item in sorted(canonical_bytes(x) for x in value)]
    else:
        normalized = value
    return json.dumps(normalized, sort_keys=True, ensure_ascii=True,
                      separators=(",", ":"), allow_nan=False).encode("ascii")


def digest(value: object) -> str:
    return hashlib.sha256(canonical_bytes(value)).hexdigest()


def reference(entry: dict) -> str:
    return f"{entry['id']}@{entry['version']}"


def safe_relative_path(value: str) -> PurePosixPath:
    require(bool(value) and not any(ord(c) < 32 for c in value), "invalid path text")
    require(not any(c in value for c in "\\:%"), "unsafe path encoding")
    path = PurePosixPath(value)
    require(not path.is_absolute() and all(p not in ("", ".", "..")
            for p in value.split("/")), "unsafe relative path")
    return path


def local_file(root: Path, relative: str) -> Path:
    path = safe_relative_path(relative)
    root = root.resolve(strict=True)
    current = root
    for part in path.parts:
        current = current / part
        require(not current.is_symlink(), "symlinks are not allowed")
    resolved = current.resolve(strict=True)
    require(resolved.is_relative_to(root) and resolved.is_file(), "file escapes root")
    return resolved


def public_https(value: str) -> None:
    require(not any(c.isspace() or ord(c) < 32 for c in value), "invalid URL text")
    try:
        url = urlsplit(value)
        host = url.hostname or ""
        port = url.port
    except ValueError as exc:
        raise ContractError("invalid URL") from exc
    require(url.scheme == "https" and bool(host) and not url.username
            and not url.password and not url.fragment and port in (None, 443), "unsafe HTTPS URL")
    require("\\" not in value and "%" not in host, "ambiguous URL")
    host = host.rstrip(".").lower()
    require(host not in ("localhost", "localhost.localdomain")
            and not host.endswith((".local", ".localhost", ".internal")), "non-public host")
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        require(bool(re.fullmatch(r"[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?", host))
                and all(re.fullmatch(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?", label)
                        for label in host.split("."))
                and "." in host and not re.fullmatch(r"[0-9.]+", host), "invalid hostname")
    else:
        require(address.is_global, "non-public IP address")
    # A future fetcher must additionally validate DNS results and EVERY redirect.


def verify_bytes(path: Path, asset: dict) -> None:
    require(path.stat().st_size == asset["expected_bytes"], "asset size mismatch")
    with path.open("rb") as stream:
        actual = hashlib.file_digest(stream, "sha256").hexdigest()
    require(actual == asset["sha256"], "asset checksum mismatch")


def validate(catalog: dict, locations: dict, schema: dict) -> dict[str, dict]:
    Draft202012Validator.check_schema(schema)
    for name, document in (("catalog", catalog), ("locations", locations)):
        validator = Draft202012Validator({**schema, "$ref": f"#/$defs/{name}"})
        errors = sorted(validator.iter_errors(document), key=lambda x: str(list(x.path)))
        require(not errors, f"{name}: {errors[0].message}" if errors else "")
    index = {}
    for group in GROUPS:
        for entry in catalog[group]:
            key = reference(entry)
            safe_relative_path(entry["id"])
            require(key not in index, f"duplicate identity: {key}")
            index[key] = entry
    for asset in catalog["assets"]:
        rights = asset["license"]
        require(all(rights[field].strip() for field in ("author", "provenance")),
                "blank author or provenance")
        require(rights["redistribution"] == "allowed" and rights["commercial_use"] == "allowed",
                "baseline library requires reviewed redistributable commercial-compatible assets")
        require(not rights["attribution_required"] or bool(rights["attribution"].strip()),
                "required attribution is empty")
        require(rights["expression"] == "CC0-1.0" or rights["attribution_required"],
                "non-CC0 license requires preservation of notices/attribution")
        public_https(rights["license_url"])
    for surface in catalog["surfaces"]:
        ids = [v["id"] for v in surface["variants"]]
        require(len(ids) == len(set(ids)), "duplicate surface variant")
        for variant in surface["variants"]:
            for asset_ref in variant["assets"]:
                require(asset_ref in index, f"missing asset: {asset_ref}")
    for recipe in catalog["recipes"]:
        for parent in recipe["includes"]:
            require(parent in index, f"missing recipe: {parent}")
        for binding in recipe["bindings"]:
            surface = index.get(binding["surface"])
            require(surface is not None, f"missing surface: {binding['surface']}")
            require(binding["material_id"] in surface["canonical_material_ids"],
                    "presentation cannot silently rebind a physical material")
        for env in recipe["environments"]:
            require(env in index, f"missing environment: {env}")
    located = set()
    for item in locations["entries"]:
        key = item["asset"]
        require(key in index and key not in located, "unknown or duplicate asset location")
        located.add(key)
        require(item["sha256"] == index[key]["sha256"], "location content hash mismatch")
        for source in item["sources"]:
            require(bool(source["source_version"].strip()), "blank source version")
            if source["type"] == "repo_fixture":
                safe_relative_path(source["locator"])
            else:
                public_https(source["locator"])
    require(located == {reference(a) for a in catalog["assets"]}, "missing asset source")
    for recipe in catalog["recipes"]:
        resolve(index, reference(recipe))
    return index


def resolve(index: dict[str, dict], recipe_ref: str) -> dict:
    """Compose exact-version sets. Identical diamonds deduplicate; conflicts fail."""
    require(recipe_ref.startswith("recipe/") and recipe_ref in index, "unknown recipe")
    visiting, visited, bindings, environments, closure = set(), set(), {}, set(), set()

    def visit(key: str) -> None:
        require(key not in visiting, "recipe composition cycle")
        if key in visited:
            return
        visiting.add(key)
        recipe = index[key]
        for parent in sorted(recipe["includes"]):
            visit(parent)
        for binding in recipe["bindings"]:
            material, surface = binding["material_id"], binding["surface"]
            require(material not in bindings or bindings[material] == surface,
                    f"conflicting material binding: {material}")
            bindings[material] = surface
            closure.add(surface)
            for variant in index[surface]["variants"]:
                closure.update(variant["assets"])
        environments.update(recipe["environments"])
        closure.add(key)
        visiting.remove(key)
        visited.add(key)

    visit(recipe_ref)
    require(len(environments) <= 1, "conflicting environment profiles")
    closure.update(environments)
    lock = {"schema": "dws.world_presentation_lock.v1", "resolver": "wp-set-json-v1",
            "recipe": recipe_ref, "bindings": bindings, "environments": sorted(environments),
            "descriptors": {key: digest(index[key]) for key in sorted(closure)}}
    lock["presentation_lock_hash"] = digest(lock)
    return lock


def variation_token(seed: int, body_id: str, spatial_key: str, surface_ref: str, channel: str) -> str:
    require(type(seed) is int and -(2**53) < seed < 2**53, "seed outside portable integer range")
    require(all(isinstance(x, str) and x for x in (body_id, spatial_key, surface_ref, channel)),
            "empty variation identity")
    # A dictionary, not a set-like positional array: every domain has a named key.
    return digest({"domain": "wp-variation-v1", "seed": seed, "body": body_id,
                   "spatial_key": spatial_key, "surface": surface_ref, "channel": channel})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--catalog", type=Path, default=CATALOG_PATH)
    parser.add_argument("--locations", type=Path, default=LOCATIONS_PATH)
    parser.add_argument("--recipe", default="recipe/lunar-swatch@1.0.0")
    parser.add_argument("--verify-fixtures", action="store_true")
    args = parser.parse_args()
    try:
        catalog, locations = read_json(args.catalog), read_json(args.locations)
        index = validate(catalog, locations, read_json(SCHEMA_PATH))
        if args.verify_fixtures:
            for item in locations["entries"]:
                fixtures = [s for s in item["sources"] if s["type"] == "repo_fixture"]
                require(bool(fixtures), f"no repository fixture source: {item['asset']}")
                for source in fixtures:
                    verify_bytes(local_file(ROOT, source["locator"]), index[item["asset"]])
        print(json.dumps(resolve(index, args.recipe), sort_keys=True, indent=2))
        print("WORLD_PACKS_LIBRARY_CONTRACT: PASS (metadata only)", file=sys.stderr)
        return 0
    except (ContractError, OSError, ValueError, RecursionError) as exc:
        print(f"WORLD_PACKS_LIBRARY_CONTRACT: FAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
