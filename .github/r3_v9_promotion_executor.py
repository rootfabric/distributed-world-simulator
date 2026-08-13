#!/usr/bin/env python3
from __future__ import annotations

import copy
import hashlib
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO = Path.cwd()
WORK = Path("/tmp/r3-v9-promotion-worktree")
EVIDENCE = REPO / ".r3-validation"

MAIN = "ce40dd075045078ed70924f8d5a1011eb3eff03d"
R2 = "GLOBAL-P0-2026-08-10-R2"
R3 = "GLOBAL-P0-2026-08-12-R3-REFRESH-R1"
R3_LIFECYCLE = "c703a5e22622813169624f7ce4ec9ea9f362f8df"
ARCH_COMPAT = "53eed6dbfab38b95cdbac3bc8a621590c20a1208"
OWN_COMPAT = "5a08def5fa61bca913c7cab3d976fda4e77b7263"
FROZEN = "595263c4c925c122a09876cb29b87f5ca5fef1d2"
CANDIDATE_BLOB = "c569d90b9aa2d4675e8ef30cb524aef5771f1522"
OWNERSHIP_CANDIDATE_BLOB = "ad2aaac2c5f942b9748b5cf391038a7ce122d073"
HISTORICAL_OWNERSHIP_BLOB = "0cebf594ac7900292318d7533e4439cc7f3764d6"
CANDIDATE_BRANCH = "control/r3-v9-promotion-candidate-ephemeral"


def run(args: list[str], *, cwd: Path = REPO, check: bool = True, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    print("+", " ".join(args), flush=True)
    proc = subprocess.run(args, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)
    if proc.stdout:
        print(proc.stdout, end="" if proc.stdout.endswith("\n") else "\n", flush=True)
    if check and proc.returncode != 0:
        raise RuntimeError(f"command failed ({proc.returncode}): {' '.join(args)}")
    return proc


def git(*args: str, cwd: Path = REPO) -> str:
    return run(["git", *args], cwd=cwd).stdout.strip()


def load(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError(f"expected JSON object: {path}")
    return value


def dump(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def copy_from(ref: str, path: str) -> None:
    target = WORK / path
    target.parent.mkdir(parents=True, exist_ok=True)
    content = run(["git", "show", f"{ref}:{path}"], cwd=WORK).stdout
    target.write_text(content, encoding="utf-8")


def verify_epoch() -> None:
    git("fetch", "origin", "+refs/heads/*:refs/remotes/origin/*", "--prune")
    expected = {
        "origin/main": MAIN,
        "origin/control/global-p0-r3-refresh-r1": R3_LIFECYCLE,
        "origin/control/r3-promotion-passport-compat-r1": ARCH_COMPAT,
        "origin/control/r3-promotion-ownership-compat-r1": OWN_COMPAT,
    }
    for ref, sha in expected.items():
        actual = git("rev-parse", ref)
        if actual != sha:
            raise RuntimeError(f"R3_V9_PROMOTION_AUTHORIZATION_EPOCH_STALE {ref}: {actual} != {sha}")
    git("cat-file", "-e", f"{FROZEN}^{{commit}}")
    if git("rev-parse", f"{FROZEN}:config/architecture/global-p0-r3-architecture-candidate.v1.json") != CANDIDATE_BLOB:
        raise RuntimeError("frozen candidate blob mismatch")
    if git("rev-parse", f"{FROZEN}:config/control/architecture-ownership-r3-candidate.v1.json") != OWNERSHIP_CANDIDATE_BLOB:
        raise RuntimeError("frozen ownership candidate blob mismatch")


def prepare_worktree() -> None:
    if WORK.exists():
        run(["git", "worktree", "remove", "--force", str(WORK)], check=False)
        shutil.rmtree(WORK, ignore_errors=True)
    run(["git", "worktree", "prune"])
    run(["git", "worktree", "add", "--detach", str(WORK), MAIN])
    if git("rev-parse", "HEAD", cwd=WORK) != MAIN:
        raise RuntimeError("worktree is not exact main")


def project_reviewed_surfaces() -> None:
    compat = "origin/control/r3-promotion-ownership-compat-r1"
    for path in [
        ".github/workflows/project-control.yml",
        "config/control/project-control-policy.v1.json",
        "scripts/control/project_control.py",
        "scripts/control/project_control_architecture_compat.py",
        "scripts/control/project_control_core.py",
        "tests/harness/test_project_control_architecture_compatibility.py",
        "tests/harness/test_project_control_historical_ownership_compatibility.py",
        "tests/harness/test_project_control_proposed_r3_ownership_projection.py",
    ]:
        copy_from(compat, path)

    for path in [
        "config/architecture/global-p0-r3-architecture-candidate.v1.json",
        "config/control/architecture-ownership-r3-candidate.v1.json",
        "config/control/global-p0-r2-to-r3-transition-policy.v1.json",
        "config/control/global-p0-r3-prepromotion-guards.v1.json",
        "config/control/harness/checkpoint-catalog.v1.json",
    ]:
        copy_from(FROZEN, path)


def capture_and_build_projection() -> tuple[list[dict[str, str]], str]:
    registry_path = WORK / "config/control/project-program-registry.v1.json"
    policy_path = WORK / "config/control/project-control-policy.v1.json"
    roadmap_path = WORK / "config/architecture/global-program-roadmap.v1.json"
    ownership_candidate_path = WORK / "config/control/architecture-ownership-r3-candidate.v1.json"

    registry = load(registry_path)
    policy = load(policy_path)
    roadmap = load(roadmap_path)
    ownership_candidate = load(ownership_candidate_path)

    assert registry["registry_generation"] == 78
    assert registry["architecture_revision"] == R2
    assert policy["architecture_revision"] == R2
    assert roadmap["global_revision"] == R2
    assert ownership_candidate["architecture_revision"] == R3
    assert git("rev-parse", f"{MAIN}:config/control/architecture-ownership.v1.json", cwd=WORK) == HISTORICAL_OWNERSHIP_BLOB

    identities: list[dict[str, str]] = []
    for program, central in registry["programs"].items():
        if not isinstance(central, dict) or not central.get("requires_passport", False):
            continue
        branch = str(central["branch"])
        passport_path = str(central["passport_path"])
        ref = f"origin/{branch}"
        head = git("rev-parse", ref, cwd=WORK)
        blob = git("rev-parse", f"{ref}:{passport_path}", cwd=WORK)
        passport = json.loads(run(["git", "show", f"{ref}:{passport_path}"], cwd=WORK).stdout)
        if passport.get("program") != program or passport.get("branch") != branch or passport.get("architecture_revision") != R2:
            raise RuntimeError(f"historical passport identity invalid: {program}")
        identity = {
            "program": program,
            "branch": branch,
            "passport_path": passport_path,
            "architecture_revision": R2,
            "pinned_head_sha": head,
            "passport_blob_sha": blob,
        }
        identities.append(identity)
        central["historical_passport_architecture_revisions"] = [R2]
        central["historical_passport_identities"] = [copy.deepcopy(identity)]
        central.pop("historical_passport_ownership_transitions", None)

    actual_programs = {x["program"] for x in identities}
    expected_programs = {"G", "ECO", "T", "CH", "DOCTRINE", "NX"}
    if actual_programs != expected_programs:
        raise RuntimeError(f"requires_passport set changed: {actual_programs}")

    t_transitions = [
        {"program": "T", "architecture_revision": R2, "foundation": "WORLD_QUERY_FABRIC", "historical_owner": "P1_FUTURE", "canonical_owner": "WQ"},
        {"program": "T", "architecture_revision": R2, "foundation": "WORLD_TRANSACTION_MODEL", "historical_owner": "P0", "canonical_owner": "WT"},
    ]
    registry["programs"]["T"]["historical_passport_ownership_transitions"] = copy.deepcopy(t_transitions)

    now = datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    registry["registry_generation"] = 79
    registry["architecture_revision"] = R3
    registry["updated_at_utc"] = now
    registry["control_checkpoint"] = "GLOBAL-P0 R3 V9 canonical promotion boundary; mandatory post-R3 Project Control required before runtime dispatch"
    registry["project_summary"] = "GLOBAL-P0 R3 V9 is the canonical architecture at registry generation 79. Promotion is control/docs/config only. Mandatory post-R3 Project Control must be NON_RED before fresh H0.2/NX.C1 dispatch; H0.3 and V0 remain downstream of H0.2/NX source acceptance."

    harness = registry["programs"]["HARNESS"]
    harness["current_stage"] = "GLOBAL-P0 R3 Canonical Promotion Boundary"
    harness["stage_status"] = "R3_CANONICAL_POST_R3_PC0_PENDING"
    harness["progress_note"] = "Human-approved R3 V9 is projected canonically with no runtime/domain mutation. Mandatory post-R3 Project Control is next; the runtime slot remains released and H0.2/NX.C1 is not yet dispatched."
    harness["next_stage"] = "Run mandatory post-R3 Project Control. If NON_RED, resolve the H0.2 machine checkpoint contract and dispatch fresh H0.2/NX.C1 from exact canonical R3 main."

    g = registry["programs"]["G"]
    g["stage_status"] = "SOURCE_ACCEPTED_FROZEN_WAITING_MAT0"
    g["next_stage"] = "Keep G8 frozen. G9 remains off the V0 critical path and may start only after MAT0 canonical material identity."
    g["blockers"] = [x for x in g.get("blockers", []) if "CANONICAL_GLOBAL_P0_R3" not in x]

    registry["programs"]["T"]["next_stage"] = "Keep T1B frozen. T2.0 is off the V0 critical path and still waits post-R3 control plus TS0.4 ceiling evidence and PC0 convergence."

    ts = registry["programs"]["TS"]
    ts["stage_status"] = "C22_MAIN_INTEGRATED_FROZEN_WAITING_POST_R3_PC0"
    ts["next_stage"] = "Do not start TS0.4 on the V0 critical path. It remains gated by mandatory post-R3 Project Control."
    ts["blockers"] = ["POST_R3_PC0_REQUIRED_BEFORE_TS0_4"]

    nx = registry["programs"]["NX"]
    nx["stage_status"] = "PREPARATION_COMPLETE_WAITING_POST_R3_PC0"
    nx["progress_note"] = "Canonical R3 is established by this promotion boundary. NX runtime remains blocked until mandatory post-R3 Project Control passes and a fresh H0.2/NX.C1 Work Order is issued. CH->NX remains a blocking source-acceptance dependency revalidation gate."
    nx["next_stage"] = "After mandatory post-R3 PC0 NON_RED, create/register fresh H0.2/NX.C1 from exact canonical R3 main, apply HIGH-risk routing, and require fresh CH->NX dependency revalidation before NX source acceptance."
    nx["blockers"] = [
        "POST_R3_PC0_PLUS_FRESH_H0_2_DISPATCH_REQUIRED_BEFORE_H0_2_NX_C1",
        "CH_TO_NX_DIRECTIONAL_REVALIDATION_REQUIRED_BEFORE_NX_SOURCE_ACCEPTANCE",
    ]

    blocked = []
    for item in registry.get("global_blocked_transitions", []):
        if item.get("stage") == "GLOBAL-P0 R3 PROMOTION":
            continue
        item = copy.deepcopy(item)
        if item.get("stage") == "NX.C1 RUNTIME START":
            item["blocked_by"] = "POST_R3_PC0_PLUS_FRESH_H0_2_DISPATCH_REQUIRED"
        elif item.get("stage") == "G9 START":
            item["blocked_by"] = "MAT0_REQUIRED"
        elif item.get("stage") == "TS0.4 START":
            item["blocked_by"] = "POST_R3_PC0_REQUIRED"
        blocked.append(item)
    registry["global_blocked_transitions"] = blocked

    order = registry.get("convergence_order", {})
    order["now_parallel"] = [
        "mandatory post-R3 Project Control and lifecycle roll-forward",
        "ECO research/design-only work",
        "H0.2/NX.C1 preparation only until post-R3 PC0",
        "H0.3/V0 preparation only",
    ]
    order["architecture_train"] = ["GLOBAL-P0 R3 canonical promotion", "mandatory post-R3 PC0", "fresh H0.2/NX.C1", "then next declared runtime checkpoint"]

    architecture_compat = copy.deepcopy(policy["passport_architecture_compatibility"])
    ownership_compat = copy.deepcopy(policy["passport_ownership_compatibility"])
    policy["architecture_revision"] = R3
    assert policy["passport_architecture_compatibility"] == architecture_compat
    assert policy["passport_ownership_compatibility"] == ownership_compat
    source = policy["passport_ownership_compatibility"]["historical_canonical_ownership_source"]
    assert source == {"architecture_revision": R2, "commit_sha": MAIN, "path": "config/control/architecture-ownership.v1.json", "blob_sha": HISTORICAL_OWNERSHIP_BLOB}

    ownership = copy.deepcopy(ownership_candidate)
    ownership["schema"] = "distributed_world_simulator.architecture_ownership.v1"
    ownership["status"] = "CANONICAL_R3_V9"
    ownership["promoted_from_frozen_target"] = FROZEN
    ownership["promoted_from_candidate_blob"] = OWNERSHIP_CANDIDATE_BLOB
    assert ownership["foundations"] == ownership_candidate["foundations"]

    roadmap["global_revision"] = R3
    roadmap["updated_at_utc"] = now
    roadmap["operational_snapshot_note"] = "The detailed operational snapshot below may retain historical R2-era wording. Canonical fast-moving project state is registry generation 79; canonical R3 architecture semantics are pinned by canonical_architecture_source."
    roadmap["canonical_architecture_source"] = {"revision": R3, "path": "config/architecture/global-p0-r3-architecture-candidate.v1.json", "frozen_target_sha": FROZEN, "blob_sha": CANDIDATE_BLOB, "status": "PROMOTED_CANONICAL_V9"}
    frontiers = roadmap.setdefault("active_frontiers", {})
    frontiers.pop("architecture_candidate", None)
    frontiers["canonical_architecture"] = {"branch": "main", "stage": "GLOBAL-P0 R3 V9 canonical architecture", "status": "PROMOTED_CANONICAL_POST_R3_PC0_PENDING", "note": "Human-approved V9 promotion; mandatory post-R3 Project Control precedes runtime dispatch."}

    dump(registry_path, registry)
    dump(policy_path, policy)
    dump(WORK / "config/control/architecture-ownership.v1.json", ownership)
    dump(roadmap_path, roadmap)

    snapshot = json.dumps(identities, ensure_ascii=False, indent=2) + "\n"
    snapshot_digest = hashlib.sha256(snapshot.encode("utf-8")).hexdigest()
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    (EVIDENCE / "promotion-boundary-identities.json").write_text(snapshot, encoding="utf-8")
    (EVIDENCE / "promotion-boundary-identities.sha256").write_text(snapshot_digest + "\n", encoding="utf-8")

    current_lines = [
        "# Distributed World Simulator — Current Project Frontiers",
        "",
        "**Operational owner:** `main`  ",
        f"**Architecture baseline:** `{R3}`  ",
        "**Registry generation:** `79`  ",
        "**Control plane:** `PC0-2026-08-10-R1`  ",
        "**Harness:** `H0-2026-08-11-R1`",
        "",
        "> Machine truth remains `config/control/project-program-registry.v1.json`.",
        "",
        "## Canonical state",
        "",
        "GLOBAL-P0 R3 V9 is the Human-approved canonical architecture projection. Promotion contains no gameplay/runtime/domain mutation. Frozen R2 passports remain immutable historical evidence only through exact architecture-identity compatibility; T additionally has exactly the reviewed WORLD_QUERY_FABRIC P1_FUTURE -> WQ and WORLD_TRANSACTION_MODEL P0 -> WT historical ownership transitions.",
        "",
        "## Immediate gate",
        "",
        "Mandatory post-R3 Project Control must be NON_RED before any new runtime Work Order.",
        "",
        "## V0 critical path",
        "",
        "R3 canonical -> post-R3 PC0 NON_RED -> H0.2 machine checkpoint contract + fresh H0.2/NX.C1 -> NX SOURCE_ACCEPTED / H0_2_PASS -> H0.3 acceptance -> V0.0 -> V0-S0.",
        "",
        "Wave A, G9, MAT0 and TS0.4 are not inserted into the sequential V0 critical path unless a later machine gate proves a specific V0 scenario requires them.",
        "",
        "Historical R2 evidence is not rewritten merely to change labels and cannot authorize new post-promotion runtime work.",
        "",
    ]
    (WORK / "docs/control/CURRENT_PROJECT_FRONTIERS_RU.md").write_text("\n".join(current_lines), encoding="utf-8")
    return identities, snapshot_digest


def patch_projection_test_dual_mode() -> None:
    path = WORK / "tests/harness/test_project_control_proposed_r3_ownership_projection.py"
    text = path.read_text(encoding="utf-8")
    start = text.index("    def _projection(self)")
    end = text.index("    @staticmethod\n    def _standard_overall", start)
    replacement = '''    def _projection(self) -> tuple[dict, dict, dict, dict[str, dict[str, str]]]:
        if os.environ.get("GITHUB_ACTIONS") != "true":
            self.skipTest("live proposed-R3 projection requires GitHub Actions with all remote refs fetched")

        registry = copy.deepcopy(self._load_local_json("config/control/project-program-registry.v1.json"))
        policy = copy.deepcopy(self._load_local_json("config/control/project-control-policy.v1.json"))

        ownership_blob = pc._core.git("rev-parse", f"{FROZEN_R3_TARGET}:{FROZEN_R3_OWNERSHIP_PATH}", allow_fail=True)
        self.assertEqual(FROZEN_R3_OWNERSHIP_BLOB, ownership_blob)
        frozen_ownership = self._load_git_json(FROZEN_R3_TARGET, FROZEN_R3_OWNERSHIP_PATH)
        self.assertEqual(R3, frozen_ownership.get("architecture_revision"))

        identities: dict[str, dict[str, str]] = {}
        if registry.get("registry_generation") == 78 and registry.get("architecture_revision") == R2:
            ownership = frozen_ownership
            registry["registry_generation"] = 79
            registry["architecture_revision"] = R3
            policy["architecture_revision"] = R3
            for key in LEGACY_PROGRAMS:
                central = registry["programs"][key]
                branch = str(central["branch"])
                passport_path = str(central["passport_path"])
                branch_ref = pc._core.remote_ref(branch)
                passport = pc._core.load_branch_json(branch_ref, passport_path)
                self.assertIsNotNone(passport, (key, branch, passport_path))
                self.assertEqual(R2, passport.get("architecture_revision"), key)
                head = pc._core.git("rev-parse", branch_ref, allow_fail=True)
                blob = pc._core.git("rev-parse", f"{branch_ref}:{passport_path}", allow_fail=True)
                identity = {"program": key, "branch": branch, "passport_path": passport_path, "architecture_revision": R2, "pinned_head_sha": head, "passport_blob_sha": blob}
                central["historical_passport_architecture_revisions"] = [R2]
                central["historical_passport_identities"] = [identity]
                central.pop("historical_passport_ownership_transitions", None)
                identities[key] = identity
            registry["programs"]["T"]["historical_passport_ownership_transitions"] = copy.deepcopy(T_TRANSITIONS)
            return registry, policy, ownership, identities

        self.assertEqual(79, registry.get("registry_generation"))
        self.assertEqual(R3, registry.get("architecture_revision"))
        self.assertEqual(R3, policy.get("architecture_revision"))
        ownership = self._load_local_json("config/control/architecture-ownership.v1.json")
        self.assertEqual(R3, ownership.get("architecture_revision"))
        self.assertEqual(frozen_ownership.get("foundations"), ownership.get("foundations"))
        for key in LEGACY_PROGRAMS:
            central = registry["programs"][key]
            records = central.get("historical_passport_identities", [])
            self.assertEqual(1, len(records), key)
            identity = records[0]
            self.assertEqual(key, identity.get("program"), key)
            self.assertEqual(central.get("branch"), identity.get("branch"), key)
            self.assertEqual(central.get("passport_path"), identity.get("passport_path"), key)
            self.assertEqual(R2, identity.get("architecture_revision"), key)
            self.assertRegex(str(identity.get("pinned_head_sha", "")), r"^[0-9a-f]{40}$", key)
            self.assertRegex(str(identity.get("passport_blob_sha", "")), r"^[0-9a-f]{40}$", key)
            self.assertEqual([R2], central.get("historical_passport_architecture_revisions"), key)
            identities[key] = identity
        self.assertEqual(T_TRANSITIONS, registry["programs"]["T"].get("historical_passport_ownership_transitions"))
        return registry, policy, ownership, identities

'''
    path.write_text(text[:start] + replacement + text[end:], encoding="utf-8")


def create_candidate_commit() -> str:
    paths = [
        ".github/workflows/project-control.yml",
        "config/architecture/global-program-roadmap.v1.json",
        "config/architecture/global-p0-r3-architecture-candidate.v1.json",
        "config/control/architecture-ownership.v1.json",
        "config/control/architecture-ownership-r3-candidate.v1.json",
        "config/control/global-p0-r2-to-r3-transition-policy.v1.json",
        "config/control/global-p0-r3-prepromotion-guards.v1.json",
        "config/control/harness/checkpoint-catalog.v1.json",
        "config/control/project-control-policy.v1.json",
        "config/control/project-program-registry.v1.json",
        "docs/control/CURRENT_PROJECT_FRONTIERS_RU.md",
        "scripts/control/project_control.py",
        "scripts/control/project_control_architecture_compat.py",
        "scripts/control/project_control_core.py",
        "tests/harness/test_project_control_architecture_compatibility.py",
        "tests/harness/test_project_control_historical_ownership_compatibility.py",
        "tests/harness/test_project_control_proposed_r3_ownership_projection.py",
    ]
    run(["git", "config", "user.name", "GLOBAL-P0 R3 Promotion Executor"], cwd=WORK)
    run(["git", "config", "user.email", "r3-promotion@users.noreply.github.com"], cwd=WORK)
    run(["git", "add", *paths], cwd=WORK)
    changed = run(["git", "diff", "--cached", "--name-only"], cwd=WORK).stdout.splitlines()
    allowed_prefixes = (".github/workflows/project-control.yml", "config/architecture/", "config/control/", "docs/control/CURRENT_PROJECT_FRONTIERS_RU.md", "scripts/control/", "tests/harness/")
    bad = [p for p in changed if not any(p == prefix or p.startswith(prefix) for prefix in allowed_prefixes)]
    if bad:
        raise RuntimeError(f"unexpected/runtime promotion paths: {bad}")
    print("PROMOTION_FILES=\n" + "\n".join(changed))
    run(["git", "commit", "-m", "control(r3): promote canonical global architecture V9"], cwd=WORK)
    candidate = git("rev-parse", "HEAD", cwd=WORK)
    if git("rev-parse", "HEAD^", cwd=WORK) != MAIN:
        raise RuntimeError("candidate parent is not exact main")
    parents = run(["git", "rev-list", "--parents", "-n", "1", "HEAD"], cwd=WORK).stdout.split()
    if len(parents) != 2:
        raise RuntimeError(f"candidate parent count != 1: {parents}")
    print(f"PROPOSED_PROMOTION_COMMIT={candidate}")
    return candidate


def validate_future_main(candidate: str) -> tuple[str, str]:
    run(["git", "update-ref", "refs/remotes/origin/main", candidate], cwd=WORK)
    run(["python3", "-m", "py_compile", "scripts/control/project_control.py", "scripts/control/project_control_architecture_compat.py", "scripts/control/project_control_core.py", "scripts/control/project_control_directional_watch.py"], cwd=WORK)

    tests = run(["python3", "-m", "unittest", "tests.harness.test_project_control_architecture_compatibility", "tests.harness.test_project_control_historical_ownership_compatibility", "tests.harness.test_project_control_proposed_r3_ownership_projection"], cwd=WORK)
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    (EVIDENCE / "compatibility-tests.log").write_text(tests.stdout, encoding="utf-8")
    if "Ran 64 tests" not in tests.stdout or "OK" not in tests.stdout:
        raise RuntimeError("64-test compatibility regression did not pass")

    run(["python3", "scripts/control/project_control.py", "--no-fetch", "--no-fail-on-red"], cwd=WORK)
    run(["python3", "scripts/control/project_control_directional_watch.py", "--no-fail-on-red"], cwd=WORK)
    standard = load(WORK / "artifacts/control/project-control-report.json")
    directional = load(WORK / "artifacts/control/directional-watch-report.json")
    if standard.get("main_head") != candidate:
        raise RuntimeError(f"PC0 main_head mismatch: {standard.get('main_head')} != {candidate}")
    if standard.get("architecture_revision") != R3 or standard.get("registry_generation") != 79:
        raise RuntimeError("projected canonical identity mismatch")
    if standard.get("overall_health") == "RED" or directional.get("overall_health") == "RED":
        raise RuntimeError(f"projected future main RED standard={standard.get('overall_health')} directional={directional.get('overall_health')}")
    programs = {p["program"]: p for p in standard.get("programs", [])}
    t = programs["T"]
    if t.get("health") == "RED":
        raise RuntimeError(f"T is RED: {t}")
    arch = t.get("architecture_compatibility", {})
    if arch.get("mode") != "EXPLICIT_HISTORICAL_IDENTITY_ALLOWED" or arch.get("matching_historical_identities") != 1:
        raise RuntimeError(f"T architecture compatibility invalid: {arch}")
    authorized = t.get("ownership_compatibility", {}).get("authorized_conflicts")
    expected = [
        {"foundation": "WORLD_QUERY_FABRIC", "historical_owner": "P1_FUTURE", "canonical_owner": "WQ"},
        {"foundation": "WORLD_TRANSACTION_MODEL", "historical_owner": "P0", "canonical_owner": "WT"},
    ]
    if authorized != expected:
        raise RuntimeError(f"T ownership authorization mismatch: {authorized}")
    if standard.get("cross_branch_overlaps", []) != []:
        raise RuntimeError(f"cross_branch_overlaps not empty: {standard.get('cross_branch_overlaps')}")

    for name in ["project-control-report.json", "directional-watch-report.json", "PROJECT_STATUS_RU.md", "DIRECTIONAL_WATCH_STATUS_RU.md"]:
        shutil.copy2(WORK / "artifacts/control" / name, EVIDENCE / name)
    print(f"PROJECTED_STANDARD={standard.get('overall_health')}")
    print(f"PROJECTED_DIRECTIONAL={directional.get('overall_health')}")
    return str(standard.get("overall_health")), str(directional.get("overall_health"))


def validate_static(candidate: str) -> None:
    registry = load(WORK / "config/control/project-program-registry.v1.json")
    policy = load(WORK / "config/control/project-control-policy.v1.json")
    ownership = load(WORK / "config/control/architecture-ownership.v1.json")
    roadmap = load(WORK / "config/architecture/global-program-roadmap.v1.json")
    current = (WORK / "docs/control/CURRENT_PROJECT_FRONTIERS_RU.md").read_text(encoding="utf-8")
    assert registry["architecture_revision"] == R3 and registry["registry_generation"] == 79
    assert policy["architecture_revision"] == R3
    assert ownership["architecture_revision"] == R3
    assert roadmap["global_revision"] == R3
    assert R3 in current
    assert "GLOBAL-P0 R3 PROMOTION" not in {x.get("stage") for x in registry.get("global_blocked_transitions", [])}
    source = policy["passport_ownership_compatibility"]["historical_canonical_ownership_source"]
    assert source == {"architecture_revision": R2, "commit_sha": MAIN, "path": "config/control/architecture-ownership.v1.json", "blob_sha": HISTORICAL_OWNERSHIP_BLOB}
    transitions = registry["programs"]["T"]["historical_passport_ownership_transitions"]
    assert len(transitions) == 2
    for _, central in registry["programs"].items():
        if isinstance(central, dict) and central.get("requires_passport", False):
            assert central["historical_passport_architecture_revisions"] == [R2]
            assert len(central["historical_passport_identities"]) == 1

    expected_blobs = {
        "scripts/control/project_control_core.py": "3d68d65e58aff37ab04c971c942efb815fbd374f",
        "scripts/control/project_control_architecture_compat.py": "0f27934968960da14c44d7fd66f78b6d364e809b",
        "scripts/control/project_control.py": "b505bcba8fbd5f59389ca7971f71a6f55023043a",
        ".github/workflows/project-control.yml": "05c99c0464e4d86973fb31e0241a460c85e36d6d",
        "tests/harness/test_project_control_architecture_compatibility.py": "f25b71175f1318cedce395ad8372d18c5d52f8e6",
        "tests/harness/test_project_control_historical_ownership_compatibility.py": "af9ce23fe5a96f371bc859f33b19ab57a4c1e201",
    }
    for path, blob in expected_blobs.items():
        actual = git("rev-parse", f"{candidate}:{path}", cwd=WORK)
        if actual != blob:
            raise RuntimeError(f"reviewed blob changed {path}: {actual} != {blob}")
    projection_test_blob = git("rev-parse", f"{candidate}:tests/harness/test_project_control_proposed_r3_ownership_projection.py", cwd=WORK)
    (EVIDENCE / "projection-test-post-promotion.blob").write_text(projection_test_blob + "\n", encoding="utf-8")
    print("STATIC_CANONICAL_CONSISTENCY=PASS")


def final_race_recheck(identities: list[dict[str, str]]) -> None:
    run(["git", "fetch", "origin", "+refs/heads/*:refs/remotes/live/*", "--prune"], cwd=WORK)
    expected = {
        "refs/remotes/live/main": MAIN,
        "refs/remotes/live/control/global-p0-r3-refresh-r1": R3_LIFECYCLE,
        "refs/remotes/live/control/r3-promotion-passport-compat-r1": ARCH_COMPAT,
        "refs/remotes/live/control/r3-promotion-ownership-compat-r1": OWN_COMPAT,
    }
    for ref, sha in expected.items():
        actual = git("rev-parse", ref, cwd=WORK)
        if actual != sha:
            raise RuntimeError(f"R3_V9_PROMOTION_AUTHORIZATION_EPOCH_STALE {ref}: {actual} != {sha}")
    for identity in identities:
        ref = f"refs/remotes/live/{identity['branch']}"
        head = git("rev-parse", ref, cwd=WORK)
        blob = git("rev-parse", f"{ref}:{identity['passport_path']}", cwd=WORK)
        if head != identity["pinned_head_sha"] or blob != identity["passport_blob_sha"]:
            raise RuntimeError(f"R3_V9_PROMOTION_IDENTITY_EPOCH_STALE {identity['program']}: captured={identity['pinned_head_sha']}/{identity['passport_blob_sha']} live={head}/{blob}")
    print("FINAL_IDENTITY_RACE_RECHECK=PASS")


def publish_candidate(candidate: str, snapshot_digest: str, standard: str, directional: str) -> None:
    # Publish only the already validated one-parent candidate. main is intentionally untouched here.
    run(["git", "push", "origin", f"{candidate}:refs/heads/{CANDIDATE_BRANCH}"], cwd=WORK)
    summary = {
        "candidate": candidate,
        "parent": MAIN,
        "parent_count": 1,
        "candidate_branch": CANDIDATE_BRANCH,
        "snapshot_sha256": snapshot_digest,
        "projected_standard": standard,
        "projected_directional": directional,
        "compatibility_tests": "64/PASS",
        "main_mutated": False,
        "runtime_domain_delta": 0,
    }
    dump(EVIDENCE / "validation-summary.json", summary)
    print(json.dumps(summary, indent=2))


def main() -> int:
    try:
        EVIDENCE.mkdir(parents=True, exist_ok=True)
        verify_epoch()
        prepare_worktree()
        project_reviewed_surfaces()
        identities, snapshot_digest = capture_and_build_projection()
        patch_projection_test_dual_mode()
        candidate = create_candidate_commit()
        standard, directional = validate_future_main(candidate)
        validate_static(candidate)
        final_race_recheck(identities)
        publish_candidate(candidate, snapshot_digest, standard, directional)
        print("R3_V9_PROMOTION_CANDIDATE_VALIDATED_MAIN_NOT_MUTATED")
        return 0
    except Exception as exc:
        print(f"R3_V9_PROMOTION_VALIDATION_FAILED: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
