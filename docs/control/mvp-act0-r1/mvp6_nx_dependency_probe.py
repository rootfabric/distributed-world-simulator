#!/usr/bin/env python3
"""Exact V0->NX dependency revalidation probe for the MVP6 M4 critical hit.

Creates a detached worktree at the current registered NX consumer HEAD, overlays
only the exact current V0 critical M4 producer file, and runs the consumer-owned
H0.2/NX.C1 focused suite.  The probe is evidence only: PASS does not write a
main-owned clearance, does not accept NX, and does not accept MVP6.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
NX_BRANCH = "feature/h0-2-nx-c1-owner-authority-r3"
NX_PASSPORT = "config/control/branches/feature__h0-2-nx-c1-owner-authority-r3.v1.json"
CRITICAL = "scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd"
OUT = Path(os.environ["MVP6_NX_PROBE_OUTPUT"]).resolve()
WORKTREE = Path(os.environ["MVP6_NX_PROBE_WORKTREE"]).resolve()
GODOT = Path(os.environ["GODOT_BIN"]).resolve()
EXPECTED_ENGINE = "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"
TESTS = [
    "tests/network/test_nx_owner_movement_authority.gd",
    "tests/network/test_nx_render_physics_separation.gd",
    "tests/network/test_nx_owner_item_projection_rollback.gd",
    "tests/network/test_nx_client_tick_robustness.gd",
    "tests/network/test_nx6_predicted_item_interactions.gd",
]


def proc(argv: list[str], cwd: Path, *, log: Path | None = None) -> subprocess.CompletedProcess:
    if log is None:
        return subprocess.run(argv, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    with log.open("wb") as stream:
        return subprocess.run(argv, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT, check=False)


def text(argv: list[str], cwd: Path = ROOT) -> str:
    result = proc(argv, cwd)
    if result.returncode != 0:
        raise RuntimeError(f"COMMAND_FAILED:{' '.join(argv)}:{result.stderr.decode(errors='replace').strip()}")
    return result.stdout.decode().strip()


def digest_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def digest_file(path: Path) -> str:
    return digest_bytes(path.read_bytes())


def git_blob(ref: str, path: str) -> str:
    return text(["git", "rev-parse", f"{ref}:{path}"])


def main() -> int:
    if not GODOT.is_file() or digest_file(GODOT) != EXPECTED_ENGINE:
        raise RuntimeError("EXACT_DOUBLE_ENGINE_REQUIRED")
    OUT.mkdir(parents=True, exist_ok=True)
    if any(OUT.iterdir()):
        raise RuntimeError("PRESERVE_EXISTING_NX_PROBE_OUTPUT")
    producer_head = text(["git", "rev-parse", "HEAD"])
    expected_head = os.environ.get("EXPECTED_HEAD", "")
    if expected_head and producer_head != expected_head:
        raise RuntimeError("EXACT_PRODUCER_HEAD_REQUIRED")
    producer_tree = text(["git", "rev-parse", "HEAD^{tree}"])
    producer_ref = f"origin/{os.environ.get('GITHUB_REF_NAME', 'feature/v0-mvp-playable-seamless-planet-r1')}"
    if text(["git", "rev-parse", producer_ref]) != producer_head:
        raise RuntimeError("PRODUCER_REMOTE_REF_DRIFT")
    producer_blob = git_blob(producer_head, CRITICAL)
    producer_bytes = subprocess.check_output(["git", "show", f"{producer_head}:{CRITICAL}"], cwd=ROOT)

    consumer_ref = f"origin/{NX_BRANCH}"
    consumer_head = text(["git", "rev-parse", consumer_ref])
    consumer_passport_blob = git_blob(consumer_ref, NX_PASSPORT)
    baseline_blob = git_blob(consumer_ref, CRITICAL)

    if WORKTREE.exists():
        raise RuntimeError("NX_PROBE_WORKTREE_ALREADY_EXISTS")
    add = proc(["git", "worktree", "add", "--detach", str(WORKTREE), consumer_head], ROOT)
    if add.returncode != 0:
        raise RuntimeError("NX_PROBE_WORKTREE_ADD_FAILED")
    rows: list[dict] = []
    try:
        target = WORKTREE / CRITICAL
        target.write_bytes(producer_bytes)
        if text(["git", "hash-object", CRITICAL], WORKTREE) != producer_blob:
            raise RuntimeError("NX_OVERLAY_BLOB_MISMATCH")
        changed = text(["git", "diff", "--name-only"], WORKTREE).splitlines()
        if changed != [CRITICAL]:
            raise RuntimeError(f"NX_OVERLAY_NOT_SINGLE_FILE:{changed}")
        diff_check = proc(["git", "diff", "--check"], WORKTREE)
        if diff_check.returncode != 0:
            raise RuntimeError("NX_OVERLAY_DIFF_CHECK_FAILED")

        import_log = OUT / "import.log"
        imported = proc([str(GODOT), "--headless", "--path", str(WORKTREE), "--editor", "--import", "--quit"], WORKTREE, log=import_log)
        rows.append({"name": "import", "exit_code": imported.returncode, "log_sha256": digest_file(import_log)})
        if imported.returncode != 0:
            raise RuntimeError("NX_OVERLAY_IMPORT_FAILED")

        for test in TESTS:
            log = OUT / (Path(test).stem + ".log")
            result = proc([str(GODOT), "--headless", "--path", str(WORKTREE), "--script", "res://" + test], WORKTREE, log=log)
            rows.append({"name": test, "exit_code": result.returncode, "log_sha256": digest_file(log)})
            if result.returncode != 0:
                raise RuntimeError(f"NX_OVERLAY_TEST_FAILED:{test}")

        summary = {
            "schema": "distributed_world_simulator.mvp6_nx_dependency_probe.v1",
            "producer_program": "V0",
            "producer_branch": os.environ.get("GITHUB_REF_NAME", "feature/v0-mvp-playable-seamless-planet-r1"),
            "producer_head": producer_head,
            "producer_tree": producer_tree,
            "producer_critical_file": CRITICAL,
            "producer_critical_blob": producer_blob,
            "consumer_program": "NX",
            "consumer_branch": NX_BRANCH,
            "consumer_head": consumer_head,
            "consumer_passport_path": NX_PASSPORT,
            "consumer_passport_blob": consumer_passport_blob,
            "consumer_original_critical_blob": baseline_blob,
            "overlay_changed_files": [CRITICAL],
            "engine_sha256": digest_file(GODOT),
            "focused_tests": rows,
            "focused_test_count": len(TESTS),
            "passed": all(row["exit_code"] == 0 for row in rows),
            "dependency_revalidated": all(row["exit_code"] == 0 for row in rows),
            "foundation_mutation_accepted": False,
            "clearance_written": False,
            "mvp6_predicate_verified": False,
            "nx_source_accepted": False,
            "independent_verdict": False,
        }
        (OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(summary, sort_keys=True), flush=True)
        return 0
    finally:
        proc(["git", "worktree", "remove", "--force", str(WORKTREE)], ROOT)
        proc(["git", "worktree", "prune"], ROOT)


if __name__ == "__main__":
    raise SystemExit(main())
