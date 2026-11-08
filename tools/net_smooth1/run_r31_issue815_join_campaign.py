#!/usr/bin/env python3
"""External, exact-R2.2 fresh JOIN experiment for NET-SMOOTH1 issue #815.

Separate tools worktree; --product must be frozen product worktree. Every
failed attempt is retained, with no silent retry. This is NOT p99 acceptance.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time
from typing import Any

EXPECTED_GODOT_VERSION = "4.7.1.stable.double.custom_build.a13da4feb"
CHECKSUM_CODE = "PAYLOAD_CHECKSUM_MISMATCH"
ROLES = ("server", "a", "b")
COMMON = (
    "--r3c-async-admission", "--r3c2-avatar-prewarm", "--r3c2-server-phased",
    "--r3c3-staged-earth", "--r3c21-frame-paced-presentation",
    "--r3c4-periodic-frame-pacing", "--r3c4r2-worker-envelope",
    "--r3c4r31-replay-projection", "--r3c4r31b-durable-attribution",
    "--r31bp1-durable-chunks", "--r31p22-loop-attribution",
    "--r31p23r2-flush-attribution", "--r31p23r21-single-pass-compact",
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def git(path: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", "-C", str(path), *args], text=True).strip()


def json_read(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return value if isinstance(value, dict) else {}


def hash_tree(root: Path, exclude: tuple[str, ...] = ()) -> list[dict[str, str]]:
    if not root.is_dir():
        return []
    output = []
    for file in sorted(root.rglob("*")):
        if file.is_file() and file.relative_to(root).as_posix() not in exclude:
            output.append({"path": file.relative_to(root).as_posix(),
                           "sha256": sha256_file(file)})
    return output


def join_connected(root: Path) -> bool:
    for role in ("a", "b"):
        raw = json_read(root / role / "initial-state.json")
        state = raw.get("automation")
        if not isinstance(state, dict) or state.get("connection_state") != "CONNECTED":
            return False
    return True


def checksum_evidence(root: Path) -> list[dict[str, Any]]:
    results = []
    for role in ROLES:
        file = root / role / "runtime.log"
        if not file.is_file():
            continue
        with file.open(encoding="utf-8", errors="replace") as stream:
            for number, line in enumerate(stream, 1):
                if CHECKSUM_CODE in line:
                    results.append({"role": role, "line": number, "code": CHECKSUM_CODE})
    return results


def classify_attempt(root: Path, exit_code: int, expected: dict[str, Any]) -> dict[str, Any]:
    manifest, report = json_read(root / "manifest.json"), json_read(root / "report.json")
    raw = manifest.get("identity")
    actual = raw if isinstance(raw, dict) else {}
    mismatches = sorted(
        key for key in ("head", "tree", "godot_sha256",
                        "asset_manifest_sha256", "asset_count")
        if key in expected and actual.get(key) != expected[key])
    identity_ok = bool(actual) and not mismatches and actual.get("tracked_dirty") is False
    connected, hits = join_connected(root), checksum_evidence(root)
    cleanup = manifest.get("cleanup")
    cleanup_ok = isinstance(cleanup, dict) and cleanup.get("verified") is True
    if not identity_ok:
        verdict = "INVALID_IDENTITY"
    elif hits:
        verdict = ("CHECKSUM_BEFORE_INITIAL_STATE_CANDIDATE"
                   if not connected else "CHECKSUM_DURING_ATTEMPT")
    elif not connected:
        verdict = "JOIN_INCONCLUSIVE"
    elif not cleanup_ok:
        verdict = "PROCESS_ISOLATION_FAILED"
    else:
        verdict = "JOIN_PASS"
    return {
        "run_id": manifest.get("run_id"), "join_verdict": verdict,
        "full_process_exit_code": exit_code,
        "full_process_verdict": report.get("verdict", "MISSING_REPORT"),
        "full_process_completed": manifest.get("completed") is True,
        "initial_both_connected": connected, "identity_match": identity_ok,
        "identity_mismatches": mismatches, "checksum_occurrences": hits,
        "cleanup_verified": cleanup_ok,
        "manifest_errors": manifest.get("errors", ["MISSING_MANIFEST"]),
        "measurement_complete_ack": manifest.get("measurement_close_ack_complete") is True,
        "raw_run": str(root),
    }


def command_for_attempt(
    product: Path, godot: Path, output: Path, on: bool, startup_timeout: int
) -> list[str]:
    cmd = [sys.executable, str(product / "tools/net_smooth1/run_net_smooth1.py"),
           "--godot", str(godot), "--mode", "gui",
           "--scenario", "local", "--duration", "12", "--warmup", "0",
           "--startup-timeout", str(startup_timeout), "--profile", "LOCAL",
           "--output", str(output), "--skip-import"]
    cmd.extend(COMMON)
    if on:
        cmd.append("--r31p23r22-attested-compact")
    return cmd


def scan_asset_pack(asset_root: Path) -> dict[str, Any]:
    """Match product runner's raw-source hash EXACTLY, not sidecar count.

    .import and .uid files are *not* members of asset_count nor the raw
    source SHA256 manifest. The full pack count remains informational.
    """
    if not asset_root.is_dir():
        raise ValueError("QUATERNIUS_ASSET_DIRECTORY_MISSING")
    all_files = sorted(path for path in asset_root.rglob("*") if path.is_file())
    source_files = [path for path in all_files
                    if path.suffix not in (".import", ".uid")]
    fingerprints = {
        str(path.relative_to(asset_root)).replace("\\", "/"): sha256_file(path)
        for path in source_files
    }
    return {
        "asset_count": len(source_files),
        "asset_manifest_sha256": hashlib.sha256(
            json.dumps(fingerprints, sort_keys=True).encode()).hexdigest(),
        "asset_import_sidecars": sum(path.suffix == ".import" for path in all_files),
        "asset_uid_sidecars": sum(path.suffix == ".uid" for path in all_files),
        "asset_pack_file_count": len(all_files),
    }


def check_asset_pack(
    pack: dict[str, Any], expected_raw_count: int,
    expected_manifest_sha256: str = ""
) -> None:
    if pack.get("asset_count") != expected_raw_count:
        raise ValueError("QUATERNIUS_ASSET_COUNT_MISMATCH")
    if (expected_manifest_sha256
            and pack.get("asset_manifest_sha256") != expected_manifest_sha256):
        raise ValueError("QUATERNIUS_ASSET_MANIFEST_SHA_MISMATCH")


def validate_product(args: argparse.Namespace) -> dict[str, Any]:
    product, godot = args.product.resolve(), args.godot.resolve()
    if product == Path(__file__).resolve().parents[2]:
        raise ValueError("SEPARATE_TOOLS_WORKTREE_REQUIRED")
    if not (product / "project.godot").is_file() or not (
            product / "tools/net_smooth1/run_net_smooth1.py").is_file():
        raise ValueError("PRODUCT_PROJECT_OR_RUNNER_MISSING")
    if not godot.is_file():
        raise ValueError("GODOT_BINARY_MISSING")
    head, tree = git(product, "rev-parse", "HEAD"), git(product, "rev-parse", "HEAD^{tree}")
    if (head != args.expected_head or tree != args.expected_tree
            or git(product, "status", "--porcelain", "--untracked-files=no")):
        raise ValueError("EXACT_PRODUCT_IDENTITY_OR_TRACKED_CLEAN_FAILED")
    binary_sha = sha256_file(godot)
    if binary_sha != args.expected_godot_sha256:
        raise ValueError("GODOT_PINNED_SHA256_MISMATCH")
    version = subprocess.check_output([str(godot), "--version"], text=True).strip()
    if version != EXPECTED_GODOT_VERSION:
        raise ValueError("GODOT_DOUBLE_VERSION_MISMATCH")
    # The canonical 224-file Quaternius package includes 101 .import
    # sidecars. The PRODUCT runner identity intentionally counts/hashes
    # ONLY 123 raw sources (ignoring .import and .uid). Do not confuse
    # full pack count with asset_count or weaken the raw SHA manifest.
    pack = scan_asset_pack(product / "assets/external/quaternius")
    check_asset_pack(pack, args.expected_asset_count,
                     args.expected_asset_manifest_sha256)
    return {
        "head": head, "tree": tree, "godot_sha256": binary_sha,
        "godot_version": version, **pack,
        "tools_head": git(Path(__file__).resolve().parents[2], "rev-parse", "HEAD"),
        "platform": platform.platform(),
    }


def arm_for(index: int, order: str) -> str:
    if order in ("OFF_ONLY", "ON_ONLY"):
        return order[:2] if order == "ON_ONLY" else "OFF"
    return ("OFF" if index % 2 == 0 else "ON") if order == "OFF_ON" else (
        "ON" if index % 2 == 0 else "OFF")


def summary_status(items: list[dict[str, Any]], requested: int) -> str:
    if len(items) != requested:
        return "INCOMPLETE"
    if not all(x.get("join_verdict") == "JOIN_PASS" for x in items):
        return "JOIN_CAMPAIGN_HAS_FAILURES"
    if len({str(x.get("run_id")) for x in items}) != len(items):
        return "RUN_ID_REUSE"
    return "NO_INCIDENT_OBSERVED_ISSUE_815_STILL_OPEN"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--product", type=Path, required=True)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--expected-head", required=True)
    parser.add_argument("--expected-tree", required=True)
    parser.add_argument("--expected-godot-sha256", required=True)
    parser.add_argument("--expected-asset-count", type=int, default=123,
                        help="raw Quaternius source count (123), ignoring .import/.uid sidecars")
    parser.add_argument("--expected-asset-manifest-sha256", default="",
                        help="optional full canonical SHA256 of raw-file content hash map")
    parser.add_argument("--attempts", type=int, default=10)
    parser.add_argument("--order", choices=("OFF_ON", "ON_OFF", "OFF_ONLY", "ON_ONLY"),
                        default="OFF_ON")
    parser.add_argument("--startup-timeout", type=int, default=240)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    if not 10 <= args.attempts <= 40 or args.startup_timeout < 60:
        parser.error("attempts must be 10..40; startup timeout >=60")
    for key in ("expected_head", "expected_tree", "expected_godot_sha256"):
        val = getattr(args, key)
        if len(val) != (64 if key == "expected_godot_sha256" else 40) or any(
                c not in "0123456789abcdef" for c in val):
            parser.error("bad lowercase hexadecimal expected hash")
    if args.expected_asset_count < 1:
        parser.error("raw asset count must be positive")
    pin = args.expected_asset_manifest_sha256
    if pin and (len(pin) != 64 or any(c not in "0123456789abcdef" for c in pin)):
        parser.error("expected asset manifest SHA256 must be 64 lowercase hex digits")
    if os.name != "nt":
        parser.error("native Windows GUI desktop is required")
    try:
        expected = validate_product(args)
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        parser.error(str(exc))
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    (root / "attempts").mkdir()
    (root / "logs").mkdir()
    campaign: dict[str, Any] = {
        "schema": "dws.net_smooth.issue815_join_campaign.v1",
        "identity": expected, "requested": args.attempts, "order": args.order,
        "stage": "INITIAL_FRESH_JOIN_NON_NORMATIVE",
        "attempts": [], "status": "IN_PROGRESS",
    }
    def publish() -> None:
        (root / "campaign.json").write_text(
            json.dumps(campaign, indent=2, ensure_ascii=False)+"\n", encoding="utf-8")
    publish()
    import_log = root / "cold-import.log"
    with import_log.open("wb") as stream:
        process = subprocess.run(
            [str(args.godot.resolve()), "--headless", "--editor",
             "--path", str(args.product.resolve()), "--import", "--quit"],
            cwd=args.product.resolve(), stdout=stream, stderr=subprocess.STDOUT,
            env={**os.environ, "GODOT_SILENCE_ROOT_WARNING": "1",
                 "BREAKPOINT_RUNTIME_DISABLED": "1"}, check=False)
    campaign["import_sha256"] = sha256_file(import_log)
    contents = import_log.read_text(encoding="utf-8", errors="replace")
    if process.returncode or any(x in contents for x in (
            "SCRIPT ERROR:", "Parse Error:", "Compile Error:")):
        campaign["status"] = "COLD_IMPORT_FAILED"
        publish()
        return 2
    publish()
    seen: set[str] = set()
    for index in range(args.attempts):
        try:
            current = validate_product(args)
            if any(current[k] != expected[k] for k in (
                    "head", "tree", "godot_sha256",
                    "asset_count", "asset_manifest_sha256")):
                raise ValueError("RUNTIME_IDENTITY_DRIFT")
        except (OSError, ValueError, subprocess.CalledProcessError) as exc:
            campaign["status"] = "IDENTITY_DRIFT_ABORTED"
            campaign["abort_reason"] = str(exc)
            publish()
            return 2
        arm = arm_for(index, args.order)
        stem = f"attempt-{index+1:02d}-{arm.lower()}"
        work_root = root / "attempts" / stem
        stdout = root / "logs" / f"{stem}.stdout.log"
        command = command_for_attempt(args.product.resolve(), args.godot.resolve(),
                                      work_root, arm == "ON", args.startup_timeout)
        started = time.time()
        with stdout.open("wb") as stream:
            result = subprocess.run(command, cwd=args.product.resolve(),
                                    stdout=stream, stderr=subprocess.STDOUT,
                                    check=False)
        classified = classify_attempt(work_root, result.returncode, expected)
        classified.update(index=index+1, arm=arm,
                          wall_seconds=round(time.time()-started, 3),
                          stdout_sha256=sha256_file(stdout))
        inventory = hash_tree(work_root, ("sha256-manifest.json",))
        if work_root.is_dir():
            (work_root / "sha256-manifest.json").write_text(
                json.dumps(inventory, indent=2)+"\n", encoding="utf-8")
        classified["evidence_file_count"] = len(inventory)
        if not classified["run_id"] or classified["run_id"] in seen:
            classified["join_verdict"] = "RUN_ID_MISSING_OR_REUSED"
        else:
            seen.add(str(classified["run_id"]))
        campaign["attempts"].append(classified)
        publish()
        # Do not launch another attempt if any native child is uncontained.
        if not classified["cleanup_verified"] or not classified["identity_match"]:
            campaign["status"] = "ABORTED_ISOLATION_OR_IDENTITY"
            publish()
            return 2
    campaign["status"] = summary_status(campaign["attempts"], args.attempts)
    publish()
    print(f"ISSUE815: {campaign['status']} -- not normative PERF acceptance")
    return 0 if campaign["status"].startswith("NO_INCIDENT_OBSERVED") else 1


if __name__ == "__main__":
    raise SystemExit(main())
