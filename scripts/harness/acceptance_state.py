"""Effective checkpoint acceptance resolution.

The historical P6 acceptance record is immutable.  This module overlays later
append-only addendums and current main-owned activation evidence so successor
routing never trusts a stale historical completeness claim.
"""

from __future__ import annotations

import json
from pathlib import Path

ACCEPTANCE_DIR = Path("config/control/harness/acceptance")
ACTIVATION_PATH = Path("config/control/harness/activation/V0-SM1-R1-ACTIVATION-001.v1.json")
SCHEDULER_PATH = Path("config/control/harness/scheduler-policy.v1.json")
ADDENDUM_SCHEMA_MARKER = "acceptance_addendum"
SM1_CHECKPOINT = "V0_SM1_SEAMLESS_PRODUCT_INTEGRATION"


def _read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _read_optional_json(path: Path) -> dict:
    try:
        value = _read_json(path)
    except (OSError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def load_acceptance_record(acceptance_id: str, root: Path | None = None):
    """Return the immutable original acceptance record, or None."""
    base = (root or Path(".")) / ACCEPTANCE_DIR
    path = base / f"{acceptance_id}.v1.json"
    if not path.exists():
        return None
    return _read_json(path)


def find_addendums(acceptance_id: str, root: Path | None = None):
    """Return all addendum records referencing the given acceptance id."""
    base = (root or Path(".")) / ACCEPTANCE_DIR
    found = []
    if not base.exists():
        return found
    for path in sorted(base.glob("*.json")):
        try:
            record = _read_json(path)
        except (json.JSONDecodeError, OSError):
            continue
        if not isinstance(record, dict):
            continue
        schema = str(record.get("schema", ""))
        if ADDENDUM_SCHEMA_MARKER not in schema:
            continue
        if record.get("references_acceptance_id") == acceptance_id:
            found.append({"path": str(path), "record": record})
    return found


def load_effective_acceptance(acceptance_id: str, root: Path | None = None) -> dict | None:
    """Build the append-only effective acceptance view for downstream control."""
    original = load_acceptance_record(acceptance_id, root)
    if original is None:
        return None
    addendums = find_addendums(acceptance_id, root)

    effective = {
        "acceptance_id": acceptance_id,
        "original": original,
        "addendums": [entry["record"] for entry in addendums],
        "acceptance_status": (
            "ACCEPTED_BY_OWNER_AUTHORITY"
            if original.get("status") == "ACCEPTED"
            else original.get("status")
        ),
        "evidence_reconciliation": {"status": "NONE", "details": []},
        "hardening": None,
        "successor": dict(original.get("successor", {})),
    }

    successor = effective["successor"]
    authorized_by_original = bool(
        original.get("successor", {}).get("runtime_mutation_authorized_by_this_record")
    )

    reconciled = False
    for entry in addendums:
        record = entry["record"]
        conflict = record.get("post_acceptance_evidence_conflict")
        if conflict:
            reconciled = True
            effective["evidence_reconciliation"]["status"] = "PARTIALLY_RETRACTED"
            effective["evidence_reconciliation"]["details"].append(
                {
                    "addendum_id": record.get("addendum_id"),
                    "summary": str(conflict.get("summary", "")),
                    "resolution_route": str(conflict.get("resolution_route", "")),
                }
            )
        if record.get("hardening_evidence_now_durable"):
            effective["hardening"] = record["hardening_evidence_now_durable"]

    if reconciled:
        effective["evidence_reconciliation"]["unresolved"] = True
        successor["runtime_mutation_authorized"] = False
        successor["activation_gate"] = (
            "MAIN_OWNED_CONTROL_UPDATE_REQUIRED_AFTER_EFFECTIVE_RECONCILIATION"
        )
    else:
        effective["evidence_reconciliation"]["unresolved"] = False
        successor["runtime_mutation_authorized"] = authorized_by_original
        successor.setdefault("activation_gate", "NONE")

    successor["activation_requires_main_owned_control_update"] = bool(
        original.get("successor", {}).get(
            "activation_requires_main_owned_control_update", True
        )
    )
    return effective


def _current_sm1_control(root: Path) -> tuple[dict, dict]:
    activation = _read_optional_json(root / ACTIVATION_PATH)
    scheduler = _read_optional_json(root / SCHEDULER_PATH)
    return activation, scheduler


def _reconciliation_consumed(activation: dict, scheduler: dict) -> bool:
    routing = scheduler.get("v0_product_train_routing", {})
    if not isinstance(routing, dict):
        return False
    activation_state = str(activation.get("state", ""))
    return (
        activation.get("checkpoint") == SM1_CHECKPOINT
        and activation_state in {"PRE_DISPATCH_CONTROL_READY", "DISPATCHED", "IN_PROGRESS"}
        and routing.get("current_checkpoint") == SM1_CHECKPOINT
        and routing.get("accepted_predecessor_base")
        == activation.get("main_declared_exact_successor_base")
    )


def _eg5_repair_consumed(activation: dict, scheduler: dict) -> bool:
    evidence = activation.get("control_evidence", {})
    if isinstance(evidence, dict):
        if (
            evidence.get("eg5_repair_pr") == 215
            and evidence.get("eg5_project_control_result") == "SUCCESS"
            and bool(evidence.get("eg5_repair_merge"))
        ):
            return True
    routing = scheduler.get("v0_product_train_routing", {})
    repair = routing.get("eg5_correctness_repair", {}) if isinstance(routing, dict) else {}
    return (
        isinstance(repair, dict)
        and repair.get("pr") == 215
        and repair.get("project_control_result") == "SUCCESS"
        and bool(repair.get("main_merge"))
    )


def sm1_eligibility(root: Path | None = None) -> dict:
    """Return fail-closed SM1 runtime-entry gates from effective + live control.

    Crucially, the EG5 gate is evidence-driven.  It disappears only after the
    main-owned activation/scheduler state cites the reviewed #215 repair; it is
    never an unconditional permanent blocker.
    """
    repo_root = root or Path(".")
    effective = load_effective_acceptance(
        "V0-P6-R2-CHECKPOINT-ACCEPTED-001", repo_root
    )
    if effective is None:
        return {"eligible_for_runtime_activation": False, "gates": ["NO_ACCEPTANCE_RECORD"]}

    activation, scheduler = _current_sm1_control(repo_root)
    gates = []
    recon = effective["evidence_reconciliation"]
    reconciliation_consumed = _reconciliation_consumed(activation, scheduler)
    if recon.get("status") == "PARTIALLY_RETRACTED" and not reconciliation_consumed:
        gates.append("EVIDENCE_RECONCILIATION_MUST_BE_CONSUMED_BY_MAIN_OWNED_CONTROL_UPDATE")
    if effective.get("hardening") is None:
        gates.append("P6_R3_HARDENING_EVIDENCE_REQUIRED")
    if not _eg5_repair_consumed(activation, scheduler):
        gates.append("EG5_EDGE_LOCATOR_CORRECTNESS_REPAIR_REQUIRED_SEPARATE_MISSION")
    if effective["successor"].get("runtime_mutation_authorized") is not True:
        gates.append("SUCCESSOR_RUNTIME_MUTATION_NOT_YET_AUTHORIZED")

    return {
        "eligible_for_runtime_activation": len(gates) == 0,
        "gates": gates,
        "effective_acceptance_id": effective["acceptance_id"],
        "reconciliation_consumed": reconciliation_consumed,
        "eg5_repair_consumed": _eg5_repair_consumed(activation, scheduler),
    }
