#!/usr/bin/env python3
"""Exact V0->NX dependency revalidation probe for the MVP6 M4 critical hit.

The registered NX branch predates the current split M4 implementation, while its
passport owns only four opt-in owner-movement runtime leaves plus focused tests.
A root-only overlay on that historical tree is therefore not a valid dependency
composition. This probe builds the actual compatibility candidate instead:
current canonical main + exact current NX-owned runtime/validation delta + exact
current V0 critical M4 producer blob. It then runs the consumer-owned H0.2/NX.C1
focused suite on pinned double Godot.

Evidence only: PASS does not write a main-owned directional clearance, does not
accept NX, and does not accept MVP6.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
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


def digest_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def object_exists(ref: str, path: str) -> bool:
    result = proc(["git", "cat-file", "-e", f"{ref}:{path}"], ROOT)
    return result.returncode == 0


def blob(ref: str, path: str) -> str:
    return text(["git", "rev-parse", f"{ref}:{path}"])


def bytes_at(ref: str, path: str) -> bytes:
    return subprocess.check_output(["git", "show", f"{ref}:{path}"], cwd=ROOT)


def write_from_ref(ref: str, path: str) -> None:
    target = WORKTREE / path
    if object_exists(ref, path):
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(bytes_at(ref, path))
    elif target.exists():
        target.unlink()


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
    producer_branch = os.environ.get("GITHUB_REF_NAME", "feature/v0-mvp-playable-seamless-planet-r1")
    producer_ref = f"origin/{producer_branch}"
    if text(["git", "rev-parse", producer_ref]) != producer_head:
        raise RuntimeError("PRODUCER_REMOTE_REF_DRIFT")
    producer_blob = blob(producer_head, CRITICAL)

    main_ref = "origin/main"
    main_head = text(["git", "rev-parse", main_ref])
    expected_main = os.environ.get("MVP6_EXPECTED_MAIN_SHA", "").strip()
    if expected_main and main_head != expected_main:
        raise RuntimeError(f"MAIN_MOVED_DURING_NX_PROBE:{main_head}:expected:{expected_main}")

    consumer_ref = f"origin/{NX_BRANCH}"
    consumer_head = text(["git", "rev-parse", consumer_ref])
    consumer_passport_blob = blob(consumer_ref, NX_PASSPORT)
    passport = json.loads(bytes_at(consumer_ref, NX_PASSPORT).decode("utf-8"))
    if passport.get("branch") != NX_BRANCH or passport.get("program") != "NX":
        raise RuntimeError("NX_PASSPORT_IDENTITY_INVALID")

    # Only the consumer-owned executable leaves and its focused validation are
    # replayed on current main. Watched foundations such as M4 are deliberately
    # NOT copied from the historical NX tree.
    consumer_paths = sorted(set(passport.get("runtime_paths", [])) | set(passport.get("validation_paths", [])))
    if not consumer_paths or CRITICAL in consumer_paths:
        raise RuntimeError("NX_OWNED_DELTA_INVALID")
    for required in TESTS:
        if required not in consumer_paths:
            raise RuntimeError(f"NX_REQUIRED_TEST_NOT_DECLARED:{required}")

    if WORKTREE.exists():
        raise RuntimeError("NX_PROBE_WORKTREE_ALREADY_EXISTS")
    add = proc(["git", "worktree", "add", "--detach", str(WORKTREE), main_head], ROOT)
    if add.returncode != 0:
        raise RuntimeError("NX_PROBE_WORKTREE_ADD_FAILED")

    rows: list[dict] = []
    overlay: list[dict] = []
    try:
        for path in consumer_paths:
            previous = blob(main_ref, path) if object_exists(main_ref, path) else ""
            current = blob(consumer_ref, path) if object_exists(consumer_ref, path) else ""
            write_from_ref(consumer_ref, path)
            overlay.append({"path": path, "source": "NX", "main_blob": previous, "overlay_blob": current})

        # Overlay the single current V0 critical producer file last. Its split
        # M4 dependencies remain current-main blobs, exactly as they would after
        # a future integration on canonical main.
        target = WORKTREE / CRITICAL
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(bytes_at(producer_head, CRITICAL))
        overlay.append({
            "path": CRITICAL,
            "source": "V0",
            "main_blob": blob(main_ref, CRITICAL),
            "overlay_blob": producer_blob,
        })
        if text(["git", "hash-object", CRITICAL], WORKTREE) != producer_blob:
            raise RuntimeError("V0_CRITICAL_OVERLAY_BLOB_MISMATCH")

        changed = sorted(set(text(["git", "status", "--porcelain"], WORKTREE).splitlines()))
        if not changed:
            raise RuntimeError("NX_COMPOSITE_HAS_NO_DELTA")
        diff_check = proc(["git", "diff", "--check"], WORKTREE)
        if diff_check.returncode != 0:
            raise RuntimeError("NX_COMPOSITE_DIFF_CHECK_FAILED")

        import_log = OUT / "import.log"
        imported = proc([str(GODOT), "--headless", "--path", str(WORKTREE), "--editor", "--import", "--quit"], WORKTREE, log=import_log)
        rows.append({"name": "import", "exit_code": imported.returncode, "log_sha256": digest_file(import_log)})
        if imported.returncode != 0:
            raise RuntimeError("NX_COMPOSITE_IMPORT_FAILED")

        for test in TESTS:
            log = OUT / (Path(test).stem + ".log")
            result = proc([str(GODOT), "--headless", "--path", str(WORKTREE), "--script", "res://" + test], WORKTREE, log=log)
            rows.append({"name": test, "exit_code": result.returncode, "log_sha256": digest_file(log)})
            if result.returncode != 0:
                raise RuntimeError(f"NX_COMPOSITE_TEST_FAILED:{test}")

        summary = {
            "schema": "distributed_world_simulator.mvp6_nx_dependency_probe.v2",
            "composition": "CURRENT_MAIN_PLUS_EXACT_NX_OWNED_DELTA_PLUS_CURRENT_V0_M4_CRITICAL",
            "canonical_main": main_head,
            "producer_program": "V0",
            "producer_branch": producer_branch,
            "producer_head": producer_head,
            "producer_tree": producer_tree,
            "producer_critical_file": CRITICAL,
            "producer_critical_blob": producer_blob,
            "consumer_program": "NX",
            "consumer_branch": NX_BRANCH,
            "consumer_head": consumer_head,
            "consumer_passport_path": NX_PASSPORT,
            "consumer_passport_blob": consumer_passport_blob,
            "consumer_owned_overlay_paths": consumer_paths,
            "overlay_records": overlay,
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
