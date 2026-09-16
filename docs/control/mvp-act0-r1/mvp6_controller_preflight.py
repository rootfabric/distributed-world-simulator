"""Read-only consumer of the canonical activation and executable Drive contract.

state_builder.py unconditionally emits runtime_authorized=False on its read-only
status envelope. That field is not a dispatch decision. Validate the actual
main-owned lease, exact Work Order/epoch, continuation and Human Attention instead.
This module never changes Harness policy or grants a new mutation lease.
"""
from __future__ import annotations
import copy
import json
import os
from pathlib import Path
import subprocess

CHECKPOINT = "V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE"
WORK_ORDER = "V0-MVP-R1-WO-001"
BRANCH = "feature/v0-mvp-playable-seamless-planet-r1"


def validate(value: dict, activation: dict, head: str) -> None:
    checks = {
        "controller_ok": value.get("ok") is True,
        "execution_envelope": value.get("source") == "GIT_ONLY_WORKER_DATA",
        "checkpoint": value.get("selected_checkpoint") == CHECKPOINT,
        "work_order": value.get("active_work_order", {}).get("work_order_id") == WORK_ORDER,
        "work_in_progress": value.get("reduced_work_order", {}).get("state") == "IN_PROGRESS",
        "branch": value.get("repository", {}).get("current_branch") == BRANCH,
        "head": value.get("repository", {}).get("current_branch_head_sha") == head,
        "clean_before": value.get("repository", {}).get("worktree_dirty") is False,
        "epoch": value.get("epoch", {}).get("validation", {}).get("action") == "CONTINUE",
        "continuation": value.get("continuation_blocked") is False,
        "next_action": value.get("next", {}).get("next_action") == "CONTINUE_ACTIVE_WORK_ORDER_TO_IMPLEMENTED_AND_VALIDATED",
        "no_human_hold": value.get("next", {}).get("human_decision_required") is False,
        "no_hard_block": value.get("next", {}).get("hard_blocked") is False,
        "lease_checkpoint": activation.get("mutation_lease", {}).get("holder_checkpoint") == CHECKPOINT,
        "lease_branch": activation.get("mutation_lease", {}).get("holder_branch") == BRANCH,
        "lease_capacity": type(activation.get("mutation_lease", {}).get("capacity")) is int and activation["mutation_lease"]["capacity"] == 1,
        "main_authorization": activation.get("mutation_lease", {}).get("runtime_mutation_authorized") is True,
        "activation": activation.get("state") == "DISPATCHED" and activation.get("work_order_id") == WORK_ORDER,
    }
    failed = [name for name, passed in checks.items() if not passed]
    if failed:
        raise ValueError("MVP6_CANONICAL_CONTINUATION_REJECTED:" + ",".join(failed))


def main() -> None:
    output = Path("artifacts/mvp6-exact/control")
    value = json.loads((output / "drive-before.json").read_text())
    activation_path = "config/control/harness/activation/V0-MVP-R1-ACTIVATION-001.v1.json"
    activation = json.loads(subprocess.check_output(["git", "show", "origin/main:" + activation_path], text=True))
    head = os.environ["EXPECTED_HEAD"]
    validate(value, activation, head)
    negatives = []
    cases = [
        ("value", ("continuation_blocked",), True),
        ("value", ("repository", "current_branch_head_sha"), "0" * 40),
        ("value", ("repository", "current_branch"), "main"),
        ("value", ("repository", "worktree_dirty"), True),
        ("value", ("next", "human_decision_required"), True),
        ("value", ("epoch", "validation", "action"), "REFRESH_REQUIRED"),
        ("activation", ("mutation_lease", "runtime_mutation_authorized"), False),
        ("activation", ("mutation_lease", "capacity"), 2),
    ]
    for target, path, replacement in cases:
        altered_value, altered_activation = copy.deepcopy(value), copy.deepcopy(activation)
        item = altered_value if target == "value" else altered_activation
        for key in path[:-1]:
            item = item[key]
        item[path[-1]] = replacement
        try:
            validate(altered_value, altered_activation, head)
        except ValueError:
            negatives.append(target + ":" + ".".join(path))
        else:
            raise RuntimeError("PREFLIGHT_FALSIFIER_ESCAPED:" + target + ":" + ".".join(path))
    result = {"passed": True, "source": "CANONICAL_MAIN_ACTIVATION_PLUS_EXECUTABLE_DRIVE", "subject_head": head, "canonical_main": subprocess.check_output(["git", "rev-parse", "origin/main"], text=True).strip(), "legacy_read_only_runtime_authorized": value.get("runtime_authorized"), "negative_controls": negatives, "runtime_policy_changed": False, "mvp6_predicate_verified": False}
    (output / "preflight.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result))


if __name__ == "__main__":
    main()
