"""WP1.2 Prepared Assets + Offline Lock.

Pipeline (all gates from WP-ASSET1 apply to the network step):

    versioned import recipe (in-repo, identity != storage URL)
    -> obtain_safe acquisition (approved hosts, DNS pinning, redirects,
       size/hash verification, immutable content-addressed raw cache)
    -> safe zip extraction (scan-then-extract, fail-closed)
    -> prepared bundle (raw hash + recipe version + Godot binary/version
       + renderer + platform + import settings) written to a prepared
       cache outside the repository
    -> offline sample boot (no HTTP/DNS; Godot loads the prepared maps)

Fail-closed everywhere; typed errors only. No network access happens
unless :func:`acquire` is explicitly called with a live resolver.
"""
from __future__ import annotations

import hashlib
import json
import socket
import sys
from dataclasses import dataclass
from pathlib import Path

_TOOLS_WORLD_PACKS = str(Path(__file__).resolve().parents[1])
if _TOOLS_WORLD_PACKS not in sys.path:
    sys.path.insert(0, _TOOLS_WORLD_PACKS)

from asset_fetch.archive import (  # noqa: E402
    ArchiveSafetyError,
    ArchiveSafetyPolicy,
    extract_zip_safe,
)
from asset_fetch.cache import RawContentAddressableCache  # noqa: E402
from asset_fetch.pipeline import obtain_safe  # noqa: E402
from asset_fetch.https import digest_of  # noqa: E402

RECIPE_SCHEMA = "dws.world_packs.prepared_import_recipe.v1"
IDENTITY_SCHEMA = "dws.world_packs.prepared_identity.v1"


class PreparedError(RuntimeError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(f"{code}: {message}")
        self.code = code


@dataclass(frozen=True)
class ImportRecipe:
    """Validated, versioned import recipe (durable identity, relocatable URL)."""

    recipe_id: str
    recipe_version: int
    candidate_id: str
    license_expression: str
    license_url: str
    sha256: str
    expected_size_bytes: int
    source_urls: tuple  # ordered, all https, all on approved hosts
    approved_hosts: frozenset
    archive_member_allow: tuple  # fnmatch patterns for members we keep
    import_settings: dict  # deterministic import parameters
    notes: tuple

    @property
    def asset_identity(self) -> str:
        return f"{self.recipe_id}@{self.recipe_version}"


def load_recipe(path: Path) -> ImportRecipe:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise PreparedError("RECIPE_UNREADABLE", f"cannot load {path}: {exc}") from exc
    if raw.get("schema") != RECIPE_SCHEMA:
        raise PreparedError("RECIPE_SCHEMA_MISMATCH", f"{path}: expected {RECIPE_SCHEMA}")
    try:
        recipe = ImportRecipe(
            recipe_id=raw["recipe_id"],
            recipe_version=int(raw["recipe_version"]),
            candidate_id=raw["candidate_id"],
            license_expression=raw["license"]["expression"],
            license_url=raw["license"]["license_url"],
            sha256=raw["raw_content"]["sha256"],
            expected_size_bytes=int(raw["raw_content"]["expected_size_bytes"]),
            source_urls=tuple(raw["source_urls"]),
            approved_hosts=frozenset(raw["approved_hosts"]),
            archive_member_allow=tuple(raw["extraction"]["member_allow"]),
            import_settings=dict(raw["import"]),
            notes=tuple(raw.get("notes", [])),
        )
    except (KeyError, TypeError, ValueError) as exc:
        raise PreparedError("RECIPE_INVALID", f"{path}: missing/invalid field: {exc}") from exc
    if recipe.recipe_version < 1:
        raise PreparedError("RECIPE_INVALID", "recipe_version must be >= 1")
    if len(recipe.sha256) != 64 or any(c not in "0123456789abcdef" for c in recipe.sha256):
        raise PreparedError("RECIPE_INVALID", "sha256 must be 64 lowercase hex")
    if not recipe.source_urls:
        raise PreparedError("RECIPE_INVALID", "at least one source URL required")
    for url in recipe.source_urls:
        if not url.startswith("https://"):
            raise PreparedError("RECIPE_INVALID", f"non-https source URL: {url}")
    return recipe


def _live_resolver(host: str) -> list:
    """Real DNS resolution (production). Raises on failure; used only in acquire."""
    try:
        infos = socket.getaddrinfo(host, 443, proto=socket.IPPROTO_TCP)
    except OSError as exc:
        raise PreparedError("RESOLUTION_FAILED", f"getaddrinfo failed for {host!r}: {exc}") from exc
    return sorted({info[4][0] for info in infos})


def _live_redirector(url: str):
    """Return the Location header for ``url`` without following redirects."""
    import urllib.error
    import urllib.request

    class _NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None

    opener = urllib.request.build_opener(_NoRedirect)
    request = urllib.request.Request(url, headers={"User-Agent": "DWS-WorldPacks/1.0"})
    try:
        response = opener.open(request, timeout=30)
        response.close()
        return None
    except urllib.error.HTTPError as exc:
        if 300 <= exc.code < 400:
            return exc.headers.get("Location")
        raise


def acquire(recipe: ImportRecipe, raw_cache_root: Path) -> str:
    """Acquire the recipe's raw bytes via the SAFE production entrypoint.

    Returns the verified sha256 (always equal to recipe.sha256). The
    content-addressed raw cache is populated immutably.
    """
    cache = RawContentAddressableCache(raw_cache_root)
    cache.initialize()
    contract = {
        "asset_id": recipe.recipe_id.replace("/", "-"),
        "version": str(recipe.recipe_version),
        "sha256": recipe.sha256,
        "expected_size_bytes": recipe.expected_size_bytes,
        "url": recipe.source_urls[0],
    }
    result = obtain_safe(
        contract,
        cache,
        approved_hosts=set(recipe.approved_hosts),
        resolver=_live_resolver,
        redirector=_live_redirector,
        max_asset_bytes=64 * 1024 * 1024,
    )
    if result.sha256 != recipe.sha256:
        raise PreparedError("HASH_MISMATCH", f"obtained {result.sha256}, recipe pins {recipe.sha256}")
    return result.sha256


def extract(recipe: ImportRecipe, raw_cache_root: Path, extract_root: Path) -> Path:
    """Safely extract the verified raw archive (scan-then-extract)."""
    cache = RawContentAddressableCache(raw_cache_root)
    blob = cache.blob_path(recipe.sha256)
    if not blob.is_file():
        raise PreparedError("RAW_MISSING", f"raw blob for {recipe.sha256} not in cache")
    data = blob.read_bytes()
    if digest_of(data) != recipe.sha256:
        raise PreparedError("RAW_CORRUPT", "raw blob no longer matches recipe sha256")
    extract_root.mkdir(parents=True, exist_ok=True)
    extract_zip_safe(data, extract_root, ArchiveSafetyPolicy())
    return extract_root


def prepared_identity(
    recipe: ImportRecipe,
    godot_version: str,
    godot_binary_sha256: str,
    renderer: str,
    target_platform: str,
) -> dict:
    """Deterministic prepared-cache identity inputs (campaign WP1.2 minimum)."""
    inputs = {
        "schema": IDENTITY_SCHEMA,
        "asset_identity": recipe.asset_identity,
        "raw_content_sha256": recipe.sha256,
        "recipe_version": recipe.recipe_version,
        "import_settings": recipe.import_settings,
        "godot_version": godot_version,
        "godot_binary_sha256": godot_binary_sha256,
        "renderer": renderer,
        "target_platform": target_platform,
    }
    canonical = json.dumps(inputs, sort_keys=True, separators=(",", ":"))
    inputs["prepared_identity_sha256"] = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    return inputs


def prepare(
    recipe: ImportRecipe,
    extract_root: Path,
    prepared_root: Path,
    identity: dict,
) -> Path:
    """Materialize the prepared bundle: selected maps + identity manifest."""
    import fnmatch

    kept: list = []
    for path in sorted(extract_root.rglob("*")):
        if path.is_file():
            rel = path.relative_to(extract_root).as_posix()
            if any(fnmatch.fnmatchcase(rel, pat) for pat in recipe.archive_member_allow):
                kept.append((rel, path))
    if not kept:
        raise PreparedError("NO_USABLE_MEMBERS", "no archive member matched member_allow patterns")
    bundle_dir = prepared_root / identity["prepared_identity_sha256"]
    if bundle_dir.exists():
        raise PreparedError("PREPARED_EXISTS", f"{bundle_dir} already prepared")
    (bundle_dir).mkdir(parents=True)
    manifest = {
        "identity": identity,
        "members": [],
        "license": {
            "expression": recipe.license_expression,
            "license_url": recipe.license_url,
            "candidate_id": recipe.candidate_id,
        },
    }
    for rel, path in kept:
        target = bundle_dir / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(path.read_bytes())
        manifest["members"].append(
            {"path": rel, "sha256": digest_of(path.read_bytes()), "bytes": path.stat().st_size}
        )
    (bundle_dir / "prepared_manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True), encoding="utf-8"
    )
    return bundle_dir


def verify_prepared(bundle_dir: Path) -> dict:
    """Offline verification of a prepared bundle (no network, no Godot)."""
    manifest_path = bundle_dir / "prepared_manifest.json"
    if not manifest_path.is_file():
        raise PreparedError("PREPARED_CORRUPT", f"missing manifest in {bundle_dir}")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise PreparedError("PREPARED_CORRUPT", f"manifest is not JSON: {exc}") from exc
    for member in manifest.get("members", []):
        path = bundle_dir / member["path"]
        if not path.is_file():
            raise PreparedError("PREPARED_CORRUPT", f"missing member {member['path']}")
        data = path.read_bytes()
        if len(data) != member["bytes"] or digest_of(data) != member["sha256"]:
            raise PreparedError(
                "PREPARED_CORRUPT", f"member {member['path']} fails size/hash verification"
            )
    return manifest


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
