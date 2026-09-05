"""Read-only project coordination. A snapshot never grants dispatch or acceptance."""
from __future__ import annotations

import re
import subprocess
from pathlib import Path
from typing import Any

from .contracts import ContractValidationError
from .mission import _canonical_ref, _parse_json_object, load_checkpoint_acceptance

REGISTRY = "config/control/project-program-registry.v1.json"
GOALS = "config/control/harness/project-goals.v1.json"
SCHEDULER = "config/control/harness/scheduler-policy.v1.json"
TRAIN = "config/control/harness/v0-product-train-policy.v1.json"
WORK_MAP = "config/control/harness/v0-current-work-map.v1.json"
CATALOG = "config/control/harness/checkpoint-catalog.v1.json"
P7 = "V0_P7_BOUNDED_TERRAIN_MUTATION"
HOLD = "P7_MERGED_CLOSURE_RECONCILIATION"


def _git(root: Path, *args: str) -> tuple[int, str]:
    result = subprocess.run(["git", *args], cwd=root, capture_output=True, text=True, check=False)
    return result.returncode, result.stdout.strip()


def read_control(root: Path, path: str, ref: str | None) -> dict[str, Any]:
    if ref is None:
        raw = (root / path).read_text(encoding="utf-8")
    else:
        code, raw = _git(root, "show", f"{ref}:{path}")
        if code:
            raise ContractValidationError(f"PROJECT_CONTROL_BLOB_UNAVAILABLE:{ref}:{path}")
    return _parse_json_object(raw, path)


def project_overview(root: Path, *, candidate: bool = False) -> dict[str, Any]:
    canonical_ref = _canonical_ref(root, "main")
    _, canonical_head = _git(root, "rev-parse", canonical_ref)
    # Pin reads to the resolved commit so a concurrent fetch cannot mix documents.
    ref = None if candidate else canonical_head
    registry = read_control(root, REGISTRY, ref)
    goals = read_control(root, GOALS, ref)
    scheduler = read_control(root, SCHEDULER, ref)
    coordination = registry.get("coordination", {})
    findings: list[dict[str, str]] = []

    def issue(code: str, scope: str, detail: str, severity: str = "ERROR") -> None:
        findings.append(dict(code=code, scope=scope, detail=detail, severity=severity))

    provenance = {
        "authority": "CANDIDATE_NON_AUTHORIZING" if candidate else "CANONICAL_MAIN_SNAPSHOT",
        "canonical_ref": canonical_ref,
        "canonical_head": canonical_head,
        "candidate_preview": candidate,
        "observed_main": coordination.get("observed_main"),
        "remote_observation": "LOCAL_GIT_REFS_ONLY_NO_FETCH",
    }
    if not coordination:
        issue("COORDINATION_NOT_DECLARED", "observability", "Project overview metadata is not present at this source.")
        return dict(provenance=provenance, lanes={}, consistency_findings=findings,
                    runtime_authorized=False, dispatch_authority="EXISTING_HARNESS_ONLY")

    if candidate and coordination.get("observed_main") != canonical_head:
        issue("CANDIDATE_MAIN_DRIFT", "product_blocking",
              f"Observed main {coordination.get('observed_main')} != canonical main {canonical_head}; refresh and re-review the candidate.")

    train = read_control(root, TRAIN, ref)
    work_map = read_control(root, WORK_MAP, ref)
    catalog = read_control(root, CATALOG, ref)
    lanes = coordination["lanes"]
    primary = coordination["primary_lane"]
    product = lanes[primary]
    routing = scheduler["v0_product_train_routing"]
    lease = scheduler["pre_h0_3_runtime_mutation_lease"]
    revision = coordination["revision"]
    for label, value in (
        ("goals", goals.get("policy_amendment_revision")),
        ("scheduler", scheduler.get("project_focus_revision")),
        ("train", train.get("policy_revision")),
        ("work_map", work_map.get("revision")),
    ):
        if value != revision:
            issue("FOCUS_REVISION_MISMATCH", "product_blocking", label)
    if lease.get("effective_registry_generation") != registry.get("registry_generation"):
        issue("LEASE_GENERATION_MISMATCH", "product_blocking", "Registry and lease must advance together.")
    if routing.get("current_checkpoint") != product.get("current_checkpoint"):
        issue("CURRENT_CHECKPOINT_MISMATCH", "product_blocking", "Registry / scheduler")
    for label, checkpoint in (("train", train.get("current_checkpoint")), ("work_map", work_map.get("current_campaign"))):
        if checkpoint != product.get("current_checkpoint"):
            issue("CURRENT_CHECKPOINT_MISMATCH", "product_blocking", label)
    program = registry["programs"]["V0"]
    if program.get("stage_status") != product.get("phase"):
        issue("PROGRAM_PHASE_MISMATCH", "product_blocking", "programs.V0 / coordination")
    for goal in goals.get("current_goal_graph", []):
        if goal.get("target_checkpoint") == product.get("current_checkpoint") and goal.get("current_phase") != product.get("phase"):
            issue("GOAL_PHASE_MISMATCH", "product_blocking", goal["id"])
    if any(value != product.get("phase") for value in (routing.get("current_phase"), work_map.get("status"), train.get("current_phase"))):
        issue("CURRENT_PHASE_MISMATCH", "product_blocking", "Registry / scheduler / work map")
    # Existing catalogs represent checkpoints as an object keyed by ID.
    entries = catalog["checkpoints"]
    known = set(entries) if isinstance(entries, dict) else {entry["id"] for entry in entries}
    for checkpoint in (product["current_checkpoint"], routing.get("next_runtime_checkpoint")):
        if checkpoint not in known:
            issue("UNDECLARED_PRODUCT_CHECKPOINT", "product_blocking", str(checkpoint))
    if product.get("phase") == HOLD and routing.get("runtime_mutation_allowed_now") is not False:
        issue("RECONCILIATION_RUNTIME_CONFLICT", "product_blocking", "Merged closure reconciliation cannot dispatch runtime.")
    if product.get("phase") == HOLD:
        for label, owner in (("program", program), ("scheduler", routing), ("work_map", work_map)):
            if owner.get("p7_7", {}).get("runtime_mutation_authorized") is not False:
                issue("RECONCILIATION_RUNTIME_CONFLICT", "product_blocking", f"{label}.p7_7")
        prebuild = program.get("prebuild_state", {})
        if not prebuild.get("historical_only") and prebuild.get("runtime_mutation_authorized") is True:
            issue("RECONCILIATION_RUNTIME_CONFLICT", "product_blocking", "program.prebuild_state")
        for stage in train.get("checkpoint_sequence", []):
            if stage.get("id") == P7 and stage.get("p7_7", {}).get("runtime_mutation_authorized") is not False:
                issue("RECONCILIATION_RUNTIME_CONFLICT", "product_blocking", "train.P7.p7_7")
    for path in product.get("evidence_paths", []):
        available = (root / path).is_file() if candidate else _git(root, "cat-file", "-e", f"{canonical_head}:{path}")[0] == 0
        if not available:
            issue("PRODUCT_EVIDENCE_MISSING", "product_blocking", path)

    reports: dict[str, Any] = {}
    for lane_id, lane in lanes.items():
        scope = "product_blocking" if lane_id == primary else f"family_local:{lane_id}"
        goal = goals.get("lane_goals", {}).get(lane_id)
        if not goal:
            issue("LANE_GOAL_MISSING", scope, lane_id)
        tracks = lane.get("tracks", {})
        track_reports = {}
        for track_id, track in tracks.items():
            label = f"{lane_id}/{track_id}"
            pin = track["observed_head"]
            branch = track["branch"]
            evidence = []
            if not re.fullmatch(r"[0-9a-f]{40}", pin):
                issue("INVALID_TRACK_PIN", scope, label)
                track_reports[track_id] = {**track, "observation": "INVALID_TRACK_PIN"}
                continue
            branch_code, branch_head = _git(root, "rev-parse", "--verify", f"refs/remotes/origin/{branch}")
            if branch_code:
                observation = "BRANCH_REF_UNAVAILABLE"
            elif branch_head == pin:
                observation = "PINNED_HEAD_CURRENT"
            else:
                ancestor, _ = _git(root, "merge-base", "--is-ancestor", pin, branch_head)
                observation = "BRANCH_ADVANCED_SINCE_SNAPSHOT" if ancestor == 0 else (
                    "PIN_NOT_ON_BRANCH" if ancestor == 1 else "PIN_ANCESTRY_UNAVAILABLE")
            if observation != "PINNED_HEAD_CURRENT":
                issue(observation, f"observability:{lane_id}", label, "WARNING")
            for path in track.get("evidence_paths", []):
                code, _ = _git(root, "cat-file", "-e", f"{pin}:{path}")
                status = "PINNED_EVIDENCE_AVAILABLE" if code == 0 else "EVIDENCE_MISSING_AT_PIN"
                evidence.append(dict(path=path, status=status))
                if code:
                    issue(status, scope, f"{label}:{path}")
            if not evidence:
                issue("TRACK_EVIDENCE_NOT_DECLARED", scope, label)
            for dependency in track.get("consumes", []):
                if dependency not in tracks:
                    issue("TRACK_DEPENDENCY_MISSING", scope, f"{label}:{dependency}")
            if track.get("runtime_authorized_by_registry") is not False:
                issue("TRACK_CANNOT_GRANT_RUNTIME", scope, label)
            track_reports[track_id] = {**track, "observed_branch_head": branch_head if branch_code == 0 else None,
                                       "observation": observation, "evidence_observation": evidence}
        # Reject cycles without importing a second scheduler/dependency engine.
        def visit(node: str, visiting: set[str], visited: set[str]) -> bool:
            if node in visiting:
                return True
            if node in visited or node not in tracks:
                return False
            visiting.add(node)
            cycle = any(visit(child, visiting, visited) for child in tracks[node].get("consumes", []))
            visiting.remove(node)
            visited.add(node)
            return cycle
        if any(visit(node, set(), set()) for node in tracks):
            issue("TRACK_DEPENDENCY_CYCLE", scope, lane_id)
        reports[lane_id] = {**lane, "goal": goal, "tracks": track_reports,
                            "next_action_is_advisory": True}
    if product.get("current_checkpoint") == P7:
        acceptance = load_checkpoint_acceptance(root, P7, "main", canonical_head=canonical_head)
        reports[primary]["canonical_checkpoint_acceptance"] = acceptance
        if acceptance is not None and product.get("phase") == HOLD:
            reports[primary]["next_action"] = "ACTIVATE_MVP_FROM_ACCEPTED_P7"
            reports[primary]["snapshot_debt_superseded_by_canonical_acceptance"] = True
    return dict(provenance=provenance, registry_generation=registry["registry_generation"],
                primary_lane=primary, lanes=reports, routing=routing,
                consistency_findings=findings, runtime_authorized=False,
                dispatch_authority="EXISTING_HARNESS_ONLY")


def canonical_reconciliation_route(root: Path, checkpoint: str | None) -> dict[str, Any] | None:
    """Route the held product to Director before loading obsolete execution epochs.

    Research requests retain their existing path. An explicit execution must not
    bypass this product hold; the CLI resolves its checkpoint before calling us.
    """
    ref = _canonical_ref(root, "main")
    _, head = _git(root, "rev-parse", ref)
    scheduler = read_control(root, SCHEDULER, head)
    routing = scheduler.get("v0_product_train_routing", {})
    if routing.get("current_phase") != HOLD:
        return None
    selected = checkpoint or routing.get("current_checkpoint")
    if selected not in (P7, routing.get("next_runtime_checkpoint")):
        return None
    acceptance = load_checkpoint_acceptance(root, P7, "main", canonical_head=head)
    return {
        "authority": "CANONICAL_MAIN_SNAPSHOT", "canonical_ref": ref, "canonical_head": head,
        "checkpoint": selected, "runtime_authorized": False,
        "checkpoint_acceptance": acceptance,
        "mission_complete": selected == P7 and acceptance is not None,
        "mission_exit_allowed": selected == P7 and acceptance is not None,
        # The routing snapshot contains no role result. CLI derives role exit
        # separately from a validated execution ledger, never from acceptance.
        "role_exit_allowed": False,
        "next_actor": "DIRECTOR",
        "next_action": "ACTIVATE_MVP_FROM_ACCEPTED_P7" if acceptance else "RECONCILE_P7_DURABLE_CLOSURE",
        "resume_condition": "Main-owned successor activation, fresh exact-base epoch and Work Order, reviewed lease rotation.",
        "instruction": "Reconcile existing durable evidence first; this routing record grants no runtime or acceptance authority.",
    }
