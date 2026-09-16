#!/usr/bin/env python3
"""Exact V0->NX dependency revalidation probe for the MVP6 M4 critical hit.

Build two executable compositions on pinned Godot:
A) current canonical main + exact registered NX-owned runtime/validation delta;
B) the same composition + exact current V0 critical M4 producer blob.

The registered NX tests were source-implemented but never exact-Godot verified.
Two tests call methods on a dynamically returned owner service but use `:=`,
which asks Godot 4.7.1 to infer a static return type that the dynamic expression
does not have. A third test uses `:=` with an untyped loop value. The NX runtime
leaf also has one dynamic movement-validator declaration. The probe normalizes
these explicitly recorded temporary declarations from `:=` to `=` in BOTH
compositions. No assertion, payload, method call or NX branch file is changed.
This proves only compatibility of the V0 delta with parser-normalized NX, not
unmodified NX source acceptance. Fatal logs override exit 0 and printed PASS.

Evidence only: PASS does not write a main-owned directional clearance, does not
accept NX, and does not accept MVP6.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import platform

ROOT = Path(__file__).resolve().parents[3]
NX_BRANCH = "feature/h0-2-nx-c1-owner-authority-r3"
NX_PASSPORT = "config/control/branches/feature__h0-2-nx-c1-owner-authority-r3.v1.json"
CRITICAL = "scripts/runtime/networked_gameplay/m4/canonical_multiplayer_item_graph_service.gd"
JOURNAL = "scripts/network/prediction/predicted_item_interaction_journal.gd"
OUT = Path(os.environ["MVP6_NX_PROBE_OUTPUT"]).resolve()
WORKTREE = Path(os.environ["MVP6_NX_PROBE_WORKTREE"]).resolve()
GODOT = Path(os.environ["GODOT_BIN"]).resolve()
EXPECTED_ENGINES = {
    "Windows": "3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5",
    "Linux": "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7",
}
TESTS = [
    "tests/network/test_nx_owner_movement_authority.gd",
    "tests/network/test_nx_render_physics_separation.gd",
    "tests/network/test_nx_owner_item_projection_rollback.gd",
    "tests/network/test_nx_client_tick_robustness.gd",
    "tests/network/test_nx6_predicted_item_interactions.gd",
]
DYNAMIC_TESTS = [
    "tests/network/test_nx_owner_movement_authority.gd",
    "tests/network/test_nx_owner_item_projection_rollback.gd",
]
DYNAMIC_DECLARATION = re.compile(r"(?m)^(\s*var\s+[A-Za-z_][A-Za-z0-9_]*)\s*:=\s*(service\.)")
FATAL = re.compile(r"SCRIPT ERROR:|(?:^|\n)\s*ERROR:|Parse Error:|Compile Error:|Assertion failed", re.I)
PASS_COUNT = re.compile(r"^.+: PASS \((\d+) assertions\)\s*$", re.M)
EXPECTED_COUNTS = dict(zip(TESTS, [44, 31, 37, 25, 940]))


def inspect_log(path: Path, *, require_assertions: bool) -> dict:
    source = path.read_text(encoding="utf-8-sig", errors="replace")
    counts = [int(n) for n in PASS_COUNT.findall(source)]
    fatal_lines = [line for line in source.splitlines() if FATAL.search(line)]
    valid = not fatal_lines and (not require_assertions or (len(counts) == 1 and counts[0] > 0))
    return {"log_valid": valid, "assertions": counts[0] if len(counts) == 1 else None,
            "fatal_lines": fatal_lines, "log_sha256": digest_file(path)}


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
    return proc(["git", "cat-file", "-e", f"{ref}:{path}"], ROOT).returncode == 0


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


def apply_parser_only_test_compatibility() -> list[dict]:
    records: list[dict] = []
    for path in DYNAMIC_TESTS:
        target = WORKTREE / path
        source = target.read_text(encoding="utf-8")
        patched, count = DYNAMIC_DECLARATION.subn(r"\1 = \2", source)
        if count < 1:
            raise RuntimeError(f"NX_DYNAMIC_DECLARATION_PATCH_PRECONDITION_FAILED:{path}")
        if patched.count("_assert(") != source.count("_assert("):
            raise RuntimeError(f"NX_TEST_ASSERTION_COUNT_CHANGED:{path}")
        before_lines = source.splitlines()
        after_lines = patched.splitlines()
        changed = [(a, b) for a, b in zip(before_lines, after_lines) if a != b]
        if len(changed) != count:
            raise RuntimeError(f"NX_TEST_PATCH_LINE_COUNT_MISMATCH:{path}")
        for before, after in changed:
            if before.replace(":=", "=") != after:
                raise RuntimeError(f"NX_TEST_NON_DECLARATION_CHANGE:{path}")
        target.write_text(patched, encoding="utf-8")
        records.append({
            "path": path,
            "change": "DYNAMIC_SERVICE_RESULT_DECLARATIONS_COLON_EQUALS_TO_EQUALS_ONLY",
            "changed_declarations": count,
            "before_sha256": hashlib.sha256(source.encode()).hexdigest(),
            "after_sha256": hashlib.sha256(patched.encode()).hexdigest(),
            "assertion_calls": source.count("_assert("),
        })

    tick_path = "tests/network/test_nx_client_tick_robustness.gd"
    tick_target = WORKTREE / tick_path
    tick_source = tick_target.read_text(encoding="utf-8")
    before = "var candidate := reference + offset"
    after = "var candidate = reference + offset"
    if tick_source.count(before) != 1 or after in tick_source:
        raise RuntimeError("NX_CLIENT_TICK_DECLARATION_PATCH_PRECONDITION_FAILED")
    tick_patched = tick_source.replace(before, after)
    if tick_patched.count("_assert(") != tick_source.count("_assert("):
        raise RuntimeError("NX_CLIENT_TICK_ASSERTION_COUNT_CHANGED")
    tick_changed = [(a, b) for a, b in zip(tick_source.splitlines(), tick_patched.splitlines()) if a != b]
    if len(tick_changed) != 1 or tick_changed[0][0].replace(":=", "=") != tick_changed[0][1]:
        raise RuntimeError("NX_CLIENT_TICK_NON_DECLARATION_CHANGE")
    tick_target.write_text(tick_patched, encoding="utf-8")
    records.append({
        "path": tick_path,
        "change": "UNTYPED_LOOP_RESULT_DECLARATION_COLON_EQUALS_TO_EQUALS_ONLY",
        "changed_declarations": 1,
        "before_sha256": hashlib.sha256(tick_source.encode()).hexdigest(),
        "after_sha256": hashlib.sha256(tick_patched.encode()).hexdigest(),
        "assertion_calls": tick_source.count("_assert("),
    })
    return records


def run_suite(label: str) -> list[dict]:
    rows: list[dict] = []
    folder = OUT / label
    folder.mkdir(parents=True, exist_ok=True)
    import_log = folder / "import.log"
    imported = proc([str(GODOT), "--headless", "--path", str(WORKTREE), "--editor", "--import", "--quit"], WORKTREE, log=import_log)
    rows.append({"name": "import", "exit_code": imported.returncode,
                 **inspect_log(import_log, require_assertions=False)})
    if imported.returncode != 0 or not rows[-1]["log_valid"]:
        return rows
    for test in TESTS:
        log = folder / (Path(test).stem + ".log")
        result = proc([str(GODOT), "--headless", "--path", str(WORKTREE), "--script", "res://" + test], WORKTREE, log=log)
        rows.append({"name": test, "exit_code": result.returncode,
                     **inspect_log(log, require_assertions=True)})
        rows[-1]["expected_assertions"] = EXPECTED_COUNTS[test]
        rows[-1]["log_valid"] = rows[-1]["log_valid"] and rows[-1]["assertions"] == EXPECTED_COUNTS[test]
    return rows


def passed(rows: list[dict]) -> bool:
    return len(rows) == len(TESTS) + 1 and all(row["exit_code"] == 0 and row["log_valid"] for row in rows)


def main() -> int:
    if not GODOT.is_file() or digest_file(GODOT) != EXPECTED_ENGINES.get(platform.system()):
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
    repair_head = os.environ.get("MVP6_NX_JOURNAL_REPAIR_HEAD", "")
    if repair_head and repair_head != producer_head:
        raise RuntimeError("JOURNAL_REPAIR_MUST_MATCH_EXACT_PRODUCER_HEAD")

    main_ref = "origin/main"
    main_head = text(["git", "rev-parse", main_ref])
    consumer_ref = f"origin/{NX_BRANCH}"
    consumer_head = text(["git", "rev-parse", consumer_ref])
    consumer_passport_blob = blob(consumer_ref, NX_PASSPORT)
    passport = json.loads(bytes_at(consumer_ref, NX_PASSPORT).decode("utf-8"))
    if passport.get("branch") != NX_BRANCH or passport.get("program") != "NX":
        raise RuntimeError("NX_PASSPORT_IDENTITY_INVALID")

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

    overlay: list[dict] = []
    try:
        for path in consumer_paths:
            previous = blob(main_ref, path) if object_exists(main_ref, path) else ""
            current = blob(consumer_ref, path) if object_exists(consumer_ref, path) else ""
            write_from_ref(consumer_ref, path)
            overlay.append({"path": path, "source": "NX", "main_blob": previous, "overlay_blob": current})

        repair_input = None
        if repair_head:
            repaired = bytes_at(repair_head, JOURNAL)
            patch_result = proc(["git", "apply", str(ROOT / "docs/control/mvp-act0-r1/mvp6_nx_same_revision_rollback_proposed.patch")], WORKTREE)
            if patch_result.returncode != 0 or (WORKTREE / JOURNAL).read_bytes().replace(b"\r\n", b"\n") != repaired.replace(b"\r\n", b"\n"):
                raise RuntimeError("JOURNAL_REPAIR_DIFFERS_FROM_APPROVED_PATCH")
            repair_input = {"head": repair_head, "path": JOURNAL,
                            "canonical_main_blob": blob(main_head, JOURNAL),
                            "repair_blob": blob(repair_head, JOURNAL),
                            "applied_identically_to_baseline_and_candidate": True,
                            "canonical_main_modified": False}

        parser_patches = apply_parser_only_test_compatibility()
        runtime_path = "scripts/runtime/networked_gameplay/networked_gameplay_service_owner_movement.gd"
        runtime_target = WORKTREE / runtime_path
        runtime_source = runtime_target.read_text(encoding="utf-8")
        before = "var validation := _movement.apply_authoritative_state("
        after = "var validation = _movement.apply_authoritative_state("
        if runtime_source.count(before) != 1 or after in runtime_source:
            raise RuntimeError("NX_RUNTIME_PARSER_PATCH_PRECONDITION_FAILED")
        runtime_patched = runtime_source.replace(before, after)
        runtime_target.write_text(runtime_patched, encoding="utf-8")
        runtime_parser_patch = {
            "path": runtime_path, "change": "ONE_DYNAMIC_DECLARATION_COLON_EQUALS_TO_EQUALS_ONLY",
            "before_sha256": hashlib.sha256(runtime_source.encode()).hexdigest(),
            "after_sha256": hashlib.sha256(runtime_patched.encode()).hexdigest(),
            "applied_identically_to_baseline_and_candidate": True,
            "nx_branch_modified": False,
        }
        baseline_rows = run_suite("baseline-main-plus-approved-repair-plus-nx" if repair_head else "baseline-current-main-plus-nx")

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
        if proc(["git", "diff", "--check"], WORKTREE).returncode != 0:
            raise RuntimeError("NX_COMPOSITE_DIFF_CHECK_FAILED")
        candidate_rows = run_suite("candidate-plus-mvp6-m4")

        baseline_pass = passed(baseline_rows)
        candidate_pass = passed(candidate_rows)
        same_counts = [r.get("assertions") for r in baseline_rows] == [r.get("assertions") for r in candidate_rows]
        summary = {
            "schema": "distributed_world_simulator.mvp6_nx_dependency_probe.v6",
            "composition": "MAIN_PLUS_EXPLICIT_APPROVED_JOURNAL_REPAIR_PLUS_PARSER_NORMALIZED_NX_THEN_V0_M4" if repair_head else "CURRENT_MAIN_PLUS_PARSER_NORMALIZED_NX_THEN_EXACT_CURRENT_V0_M4_CRITICAL",
            "journal_repair_input": repair_input,
            "unmodified_canonical_baseline": not bool(repair_head),
            "canonical_main": main_head,
            "producer_program": "V0",
            "producer_branch": producer_branch,
            "producer_head": producer_head,
            "producer_tree": producer_tree,
            "probe_sha256": digest_file(Path(__file__)),
            "producer_tracked_status": text(["git", "status", "--porcelain", "--untracked-files=no"]),
            "consumer_tree": text(["git", "rev-parse", consumer_head + "^{tree}"]),
            "canonical_main_tree": text(["git", "rev-parse", main_head + "^{tree}"]),
            "producer_critical_file": CRITICAL,
            "producer_critical_blob": producer_blob,
            "consumer_program": "NX",
            "consumer_branch": NX_BRANCH,
            "consumer_head": consumer_head,
            "consumer_passport_path": NX_PASSPORT,
            "consumer_passport_blob": consumer_passport_blob,
            "consumer_owned_overlay_paths": consumer_paths,
            "parser_only_test_compatibility": parser_patches,
            "runtime_parser_compatibility": runtime_parser_patch,
            "unmodified_nx_runtime_pass_claimed": False,
            "overlay_records": overlay,
            "engine_sha256": digest_file(GODOT),
            "engine_version": text([str(GODOT), "--version"]),
            "platform": platform.platform(),
            "baseline_tests": baseline_rows,
            "candidate_tests": candidate_rows,
            "baseline_passed": baseline_pass,
            "candidate_passed": candidate_pass,
            "same_assertion_counts": same_counts,
            "dependency_revalidated": baseline_pass and candidate_pass and same_counts and not repair_head,
            "repair_composition_revalidated": baseline_pass and candidate_pass and same_counts and bool(repair_head),
            "candidate_regressed_consumer": baseline_pass and not candidate_pass,
            "foundation_mutation_accepted": False,
            "clearance_written": False,
            "mvp6_predicate_verified": False,
            "nx_source_accepted": False,
            "independent_verdict": False,
        }
        (OUT / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(summary, sort_keys=True), flush=True)
        return 0 if summary["dependency_revalidated"] or summary["repair_composition_revalidated"] else 1
    finally:
        proc(["git", "worktree", "remove", "--force", str(WORKTREE)], ROOT)
        proc(["git", "worktree", "prune"], ROOT)


if __name__ == "__main__":
    raise SystemExit(main())
