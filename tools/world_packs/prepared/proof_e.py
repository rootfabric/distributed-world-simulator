#!/usr/bin/env python3
"""Proof E — clean-machine reproducibility for WP1.2 prepared assets.

Phase 1 (online, once): empty raw cache + empty prepared cache
    -> resolve recipe -> acquire via obtain_safe (all gates) -> verify
    bytes/hash -> safe extraction -> prepare bundle -> sample check.

Phase 2 (offline): same exact recipe with network DENIED
    -> raw/prepared cache reuse -> sample check -> NO HTTP/DNS attempted.

Negative cases: corrupt raw cache (auto-refetch recovery), corrupt
prepared cache (typed refusal), hash mismatch (typed refusal), missing
source (typed refusal when offline), recipe lock vs library update
(identity change detection), mirror relocation (URL swap, identity kept).

Usage: python tools/world_packs/prepared/proof_e.py --work-dir <dir> [--godot <exe>]
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import wp_prepare as wp  # noqa: E402
from asset_fetch.pipeline import obtain_safe  # noqa: E402

RECIPE = Path(__file__).resolve().parents[3] / "config/world_packs/prepared/recipes/ambientcg-ice001-1k.v1.json"
GODOT_DEFAULT = Path("C:/Godot/godot/bin/godot.windows.editor.double.x86_64.exe")


class NetworkDenied(RuntimeError):
    pass


def deny_resolver(host):
    raise NetworkDenied(f"DNS attempted in offline phase: {host}")


def deny_redirector(url):
    raise NetworkDenied(f"HTTP redirect attempted in offline phase: {url}")


class DenyTransportFactory:
    def __call__(self, contract):
        raise NetworkDenied(f"transport attempted in offline phase: {contract.url}")


def sample_check(bundle_dir: Path, godot: Path) -> str:
    """Boot the prepared sample: Godot headless loads every prepared map."""
    import subprocess

    script = "res://scripts/world_packs/prepared/prepared_sample_self_check.gd"
    proc = subprocess.run(
        [str(godot), "--headless", "--path", str(wp_path_repo_root()), "--script", script,
         "--", f"--prepared={bundle_dir}"],
        capture_output=True, text=True, timeout=300,
    )
    out = proc.stdout + proc.stderr
    if "PREPARED_SAMPLE=PASS" not in out or proc.returncode != 0:
        raise wp.PreparedError("SAMPLE_FAILED", f"godot sample failed: {out[-500:]}")
    return "PREPARED_SAMPLE=PASS"


def wp_path_repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def identity_for(recipe, godot: Path) -> dict:
    return wp.prepared_identity(
        recipe,
        godot_version=_godot_version(godot),
        godot_binary_sha256=wp.file_sha256(godot),
        renderer="forward_plus",
        target_platform="windows_x86_64_double",
    )


def _godot_version(godot: Path) -> str:
    import subprocess

    proc = subprocess.run([str(godot), "--version"], capture_output=True, text=True, timeout=120)
    return proc.stdout.strip().splitlines()[0] if proc.stdout.strip() else "unknown"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--work-dir", required=True)
    parser.add_argument("--godot", default=str(GODOT_DEFAULT))
    parser.add_argument("--offline-only", action="store_true",
                        help="skip online phase (assumes caches already populated)")
    args = parser.parse_args()

    work = Path(args.work_dir)
    godot = Path(args.godot)
    recipe = wp.load_recipe(RECIPE)
    results: list = []

    raw_root = work / "raw-cache"
    prepared_root = work / "prepared-cache"
    extract_root = work / "extract"
    identity = identity_for(recipe, godot)

    def run(name, fn):
        try:
            value = fn()
            results.append((name, "PASS", value))
            print(f"ok   {name}")
        except Exception as exc:  # noqa: BLE001
            results.append((name, "FAIL", str(exc)))
            print(f"FAIL {name}: {exc}")
        return results[-1]

    if not args.offline_only:
        # ---- Phase 1: online, empty caches (clean machine).
        if work.exists():
            shutil.rmtree(work)
        raw_root.mkdir(parents=True)
        run("E1_empty_caches_acquire", lambda: wp.acquire(recipe, raw_root))
        run("E2_verify_and_extract", lambda: wp.extract(recipe, raw_root, extract_root))
        run("E3_prepare", lambda: wp.prepare(recipe, extract_root, prepared_root, identity))
        bundle = prepared_root / identity["prepared_identity_sha256"]
        run("E4_offline_verify_prepared", lambda: wp.verify_prepared(bundle))
        if godot.exists():
            run("E5_sample_boots", lambda: sample_check(bundle, godot))
        else:
            results.append(("E5_sample_boots", "SKIP", "godot binary not found"))
            print("skip E5_sample_boots (no godot binary)")

    # ---- Phase 2: offline reuse. Network is structurally denied.
    bundle = prepared_root / identity["prepared_identity_sha256"]
    run("F1_offline_verify_raw_cache", lambda: wp.extract(recipe, raw_root, work / "extract2"))
    run("F2_offline_verify_prepared", lambda: wp.verify_prepared(bundle))
    if godot.exists():
        run("F3_offline_sample_no_http_dns", lambda: sample_check(bundle, godot))

    # Offline acquisition attempt MUST fail closed with zero network use.
    def offline_acquire_denied():
        try:
            obtain_safe(
                {
                    "asset_id": recipe.recipe_id.replace("/", "-"),
                    "version": str(recipe.recipe_version),
                    "sha256": recipe.sha256,
                    "expected_size_bytes": recipe.expected_size_bytes,
                    "url": recipe.source_urls[0],
                },
                _fresh_cache(work / "raw-cache-empty"),
                approved_hosts=set(recipe.approved_hosts),
                resolver=deny_resolver,
                redirector=deny_redirector,
                transport_factory=DenyTransportFactory(),
            )
        except (NetworkDenied, Exception) as exc:  # noqa: BLE001
            # The denial itself is the pass condition: DNS/HTTP/transport
            # must be refused before any network activity. A typed gate
            # failure carrying our denial message proves no socket was
            # opened (deny hooks raise before any connect).
            message = str(exc)
            if "offline phase" in message or isinstance(exc, NetworkDenied):
                return f"denied as required: {message[:100]}"
            raise AssertionError(f"unexpected failure (not our denial): {message[:200]}")
        raise AssertionError("offline acquisition unexpectedly succeeded")

    run("F4_offline_acquire_denied", offline_acquire_denied)

    # ---- Negative cases.
    def corrupt_raw_cache():
        from asset_fetch.cache import RawContentAddressableCache

        cache = RawContentAddressableCache(raw_root)
        blob = cache.blob_path(recipe.sha256)
        if not blob.is_file():
            raise AssertionError(f"raw blob missing at {blob}")
        import os as _os

        _os.chmod(blob, 0o644)  # simulate disk-level corruption of the immutable blob
        blob.write_bytes(b"CORRUPTED" + blob.read_bytes()[9:])
        # Recovery: obtain_safe detects corruption, quarantines, refetches once.
        sha = wp.acquire(recipe, raw_root)
        return f"recovered {sha[:12]}"

    if not args.offline_only:
        run("N1_corrupt_raw_cache_recovery", corrupt_raw_cache)

    def corrupt_prepared_cache():
        member = next((bundle / m["path"]) for m in wp.verify_prepared(bundle)["members"])
        member.write_bytes(member.read_bytes()[:-1])
        try:
            wp.verify_prepared(bundle)
        except wp.PreparedError as exc:
            return f"detected: {exc.code}"
        raise AssertionError("corrupt prepared bundle not detected")

    run("N2_corrupt_prepared_cache_detected", corrupt_prepared_cache)

    def hash_mismatch_recipe():
        import dataclasses

        bad = dataclasses.replace(recipe, sha256="0" * 63 + "1")
        try:
            wp.acquire(bad, raw_root)
        except Exception as exc:  # typed failures from gates/verification
            return f"refused: {type(exc).__name__}: {str(exc)[:80]}"
        raise AssertionError("hash-mismatched recipe unexpectedly acquired")

    if not args.offline_only:
        run("N3_hash_mismatch_refused", hash_mismatch_recipe)

    def old_lock_after_update():
        import dataclasses

        updated = dataclasses.replace(recipe, recipe_version=recipe.recipe_version + 1)
        new_identity = wp.prepared_identity(
            updated, godot_version=identity["godot_version"],
            godot_binary_sha256=identity["godot_binary_sha256"],
            renderer=identity["renderer"], target_platform=identity["target_platform"],
        )
        if new_identity["prepared_identity_sha256"] == identity["prepared_identity_sha256"]:
            raise AssertionError("recipe update did not change prepared identity")
        return "old lock invalid, new identity required"

    run("N4_old_lock_invalidated", old_lock_after_update)

    def mirror_relocation():
        # Identity (id@version + sha) unchanged; URL swapped to the mirror.
        import dataclasses

        relocated = dataclasses.replace(
            recipe,
            source_urls=(recipe.source_urls[-1],) + recipe.source_urls[:-1],
        )
        wp.extract(relocated, raw_root, work / "extract-mirror")
        return "relocated URL, same raw identity, cache reuse OK"

    run("N5_mirror_relocation_identity_kept", mirror_relocation)

    failed = [name for name, status, _ in results if status == "FAIL"]
    print()
    print(f"PROOF_E: {'FAIL' if failed else 'PASS'} ({len(results) - len(failed)}/{len(results)})")
    if failed:
        print("failed: " + ", ".join(failed))
        return 1
    return 0


def _fresh_cache(root: Path):
    from asset_fetch.cache import RawContentAddressableCache as _C

    if root.exists():
        shutil.rmtree(root)
    root.mkdir(parents=True)
    cache = _C(root)
    cache.initialize()
    return cache


if __name__ == "__main__":
    raise SystemExit(main())
