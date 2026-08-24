"""Effective checkpoint acceptance resolution.

The historical P6 acceptance record
(V0-P6-R2-CHECKPOINT-ACCEPTED-001) is IMMUTABLE: it stays exactly as it was
written, including its later-disproven ``all_required_predicates_complete``
claim. Downstream consumers must never silently treat that claim as current
truth.

This module provides the append-only reconciliation layer:

- the ORIGINAL acceptance record remains readable verbatim;
- addendum records (schema
  ``distributed_world_simulator.v0_product_checkpoint_acceptance_addendum.v1``)
  referencing the acceptance id are discovered automatically;
- an EFFECTIVE view is produced in which:
    * the acceptance stands by owner authority,
    * post-acceptance evidence conflicts are surfaced (partially retracted),
    * successor runtime authorization is GATED: the original record alone -
      including ``machine_evidence.all_required_predicates_complete = true`` -
      can NEVER authorize successor runtime mutation while an unresolved
      evidence-reconciliation addendum exists or while the addendum keeps the
      routing open;
  - SM1-style successors must therefore be activated through an explicit
    main-owned control update that consumes the EFFECTIVE view, not the raw
    historical record.
"""

from __future__ import annotations

import json
from pathlib import Path

ACCEPTANCE_DIR = Path("config/control/harness/acceptance")
ADDENDUM_SCHEMA_MARKER = "acceptance_addendum"


def _read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


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
    """Build the EFFECTIVE acceptance view for downstream consumers.

    Guarantees consumed by tests/harness/test_v0_p6_acceptance_effective_state.py:

    - ``original`` keeps the immutable historical record verbatim;
    - ``evidence_reconciliation.status == "PARTIALLY_RETRACTED"`` whenever at
      least one addendum records a post-acceptance evidence conflict;
    - ``successor.runtime_mutation_authorized`` can only become True when the
      ORIGINAL record authorized it AND no unresolved reconciliation addendum
      exists - i.e. the historical ``all_required_predicates_complete`` flag
      alone is never sufficient;
    - ``successor.activation_requires_main_owned_control_update`` stays True
      for any gated successor such as V0_SM1_SEAMLESS_PRODUCT_INTEGRATION.
    """
    original = load_acceptance_record(acceptance_id, root)
    if original is None:
        return None
    addendums = find_addendums(acceptance_id, root)

    effective = {
        "acceptance_id": acceptance_id,
        "original": original,
        "addendums": [entry["record"] for entry in addendums],
        "acceptance_status": "ACCEPTED_BY_OWNER_AUTHORITY"
        if original.get("status") == "ACCEPTED"
        else original.get("status"),
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

    # Gate: historical completeness claims alone are never sufficient while an
    # evidence-reconciliation addendum is in force.
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


def sm1_eligibility(root: Path | None = None) -> dict:
    """SM1 entry-gate view over the effective P6 acceptance state."""
    effective = load_effective_acceptance(
        "V0-P6-R2-CHECKPOINT-ACCEPTED-001", root
    )
    if effective is None:
        return {"eligible_for_runtime_activation": False, "gates": ["NO_ACCEPTANCE_RECORD"]}
    gates = []
    recon = effective["evidence_reconciliation"]
    if recon.get("status") == "PARTIALLY_RETRACTED":
        gates.append("EVIDENCE_RECONCILIATION_MUST_BE_CONSUMED_BY_MAIN_OWNED_CONTROL_UPDATE")
    if effective.get("hardening") is None:
        gates.append("P6_R3_HARDENING_EVIDENCE_REQUIRED")
    if effective["successor"].get("runtime_mutation_authorized") is not True:
        gates.append("SUCCESSOR_RUNTIME_MUTATION_NOT_YET_AUTHORIZED")
    # EG5 edge locator defects are a declared separate entry blocker for SM1.
    gates.append("EG5_EDGE_LOCATOR_CORRECTNESS_REPAIR_REQUIRED_SEPARATE_MISSION")
    return {
        "eligible_for_runtime_activation": len(gates) == 0,
        "gates": gates,
        "effective_acceptance_id": effective["acceptance_id"],
    }
