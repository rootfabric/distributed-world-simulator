#!/usr/bin/env python3
"""ACT0 R3: narrow MVP-only epoch evidence selector, no ref operations."""
from __future__ import annotations
import ast
from pathlib import Path
import subprocess

BASE = "c5d3eed5532c9dbe61b3ca13a87242bf6f2ea73d"
PATH = "scripts/harness/state_builder.py"


def main() -> None:
    path = Path(PATH)
    text = path.read_text(encoding="utf-8")
    expected = subprocess.check_output(["git", "show", f"{BASE}:{PATH}"]).decode("utf-8")
    if text != expected:
        raise ValueError("ACT0_R3_SELECTOR_SUBJECT_DRIFT")
    old = "from .evidence_provenance import load_hard_block_proof, validate_review_record"
    if text.count(old) != 1:
        raise ValueError("ACT0_R3_IMPORT_ANCHOR")
    text = text.replace(old, "from .evidence_provenance import committed_bytes, load_hard_block_proof, validate_review_record", 1)
    text = text.replace("import re\n", "import json\nimport re\n", 1)
    node = next(n for n in ast.walk(ast.parse(text)) if isinstance(n, ast.FunctionDef) and n.name == "_select_epoch_audit")
    lines = text.splitlines(keepends=True)
    function = ''.join(lines[node.lineno-1:node.end_lineno])
    anchor = "    return audits[-1] if audits else None\n"
    if function.count(anchor) != 1:
        raise ValueError("ACT0_R3_RETURN_ANCHOR")
    extension = '''    # ACT0 must audit a control-only main advance BEFORE product implementation.
    # Consume only a committed, identity-bound MVP recovery record; do not invent
    # IMPLEMENTED/VERIFIED/AUDITED states or mark product predicates complete.
    epoch = guard_context.get("epoch", {})
    mvp = "V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE"
    if epoch.get("eligible_checkpoints") == [mvp] and events[-1].get("work_state") == "DISPATCHED":
        for event in events:
            if not (event.get("event_type") == "RECOVERY_RESUMED"
                    and event.get("work_state") == "DISPATCHED"
                    and event.get("actor") == "INTEGRATOR"
                    and event.get("command") == "MVP_ACT0_POST_MERGE_EPOCH_AUDIT"
                    and type(event.get("exit_code")) is int and event["exit_code"] == 0
                    and event.get("project_epoch") == epoch.get("epoch_id")):
                continue
            for relative in event.get("evidence_paths", []):
                document = guard_context["documents"].get(relative, {})
                if document.get("schema") != "distributed_world_simulator.harness_epoch_audit.v1":
                    continue
                audit = json.loads(committed_bytes(guard_context["root"], relative))
                if (audit.get("project_epoch") != event["project_epoch"]
                        or audit.get("work_order_id") != event["work_order_id"]
                        or audit.get("base_sha") != epoch.get("base_sha")
                        or audit.get("main_sha") != event["head_sha"]):
                    raise ContractValidationError("MVP_RESUME_AUDIT_IDENTITY_MISMATCH")
                audits.append(audit)
'''
    function = function.replace(anchor, extension + anchor, 1)
    text = ''.join(lines[:node.lineno-1]) + function + ''.join(lines[node.end_lineno:])
    ast.parse(text)
    path.write_text(text, encoding="utf-8")
    destination = Path("tests/harness/test_v0_mvp_epoch_resume.py")
    if destination.exists():
        raise ValueError("ACT0_R3_TEST_ALREADY_PRESENT")
    destination.write_bytes(Path("docs/control/mvp-act0-r1/test_epoch_resume_template.py").read_bytes())
    print("ACT0_R3_SELECTOR_PATCH_APPLIED_NOT_ACCEPTED")


if __name__ == "__main__":
    main()
