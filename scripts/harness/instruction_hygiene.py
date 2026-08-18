"""Cheap fail-closed audits for instruction entropy and rule lifecycle."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

class HygieneError(ValueError):
    pass

def _read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict): raise HygieneError(f"JSON_OBJECT_REQUIRED:{path}")
    return value

def audit_rule_registry(policy: dict[str, Any], registry: dict[str, Any]) -> list[str]:
    findings: list[str] = []
    lifecycle = policy["rule_lifecycle"]
    required = lifecycle["required_fields"]
    protected = set(lifecycle["protected_classes"])
    seen: set[str] = set()
    for rule in registry.get("rules", []):
        missing = [field for field in required if not rule.get(field)]
        if missing:
            findings.append(f"RULE_FIELDS_MISSING:{rule.get('rule_id','?')}:{','.join(missing)}"); continue
        rule_id = str(rule["rule_id"])
        if rule_id in seen: findings.append(f"RULE_ID_DUPLICATE:{rule_id}")
        seen.add(rule_id)
        if rule["class"] in protected and str(rule["retirement"]).upper() in {"AUTO", "AGE", "UNUSED"}:
            findings.append(f"PROTECTED_RULE_AUTO_RETIREMENT:{rule_id}")
    if lifecycle.get("auto_retirement_forbidden") is not True: findings.append("AUTO_RETIREMENT_MUST_BE_FORBIDDEN")
    return findings

def audit_router(root: Path, policy: dict[str, Any]) -> list[str]:
    findings: list[str] = []
    for relative in policy["router_files"]:
        path = root / relative
        if not path.exists(): findings.append(f"ROUTER_MISSING:{relative}"); continue
        text = path.read_text(encoding="utf-8")
        lines = text.count("\n") + (0 if not text or text.endswith("\n") else 1)
        size = len(text.encode("utf-8"))
        budget = policy["budgets"].get(relative, {})
        if lines > int(budget.get("max_lines", 10**9)): findings.append(f"ROUTER_LINE_BUDGET_EXCEEDED:{relative}:{lines}")
        if size > int(budget.get("max_bytes", 10**9)): findings.append(f"ROUTER_BYTE_BUDGET_EXCEEDED:{relative}:{size}")
        for forbidden in policy.get("mutable_state_forbidden_in_router", []):
            if forbidden in text: findings.append(f"MUTABLE_STATE_IN_ROUTER:{relative}:{forbidden}")
        markers = sum(text.count(token) for token in policy.get("importance_markers", {}).get("tokens", []))
        if markers > int(policy.get("importance_markers", {}).get("warn_above_per_file", 10**9)): findings.append(f"IMPORTANCE_MARKER_BUDGET_EXCEEDED:{relative}:{markers}")
    return findings

def audit(root: Path) -> list[str]:
    policy = _read_json(root / "config/control/harness/instruction-hygiene-policy.v1.json")
    registry = _read_json(root / "config/control/harness/rule-registry.v1.json")
    return audit_router(root, policy) + audit_rule_registry(policy, registry)

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(); parser.add_argument("--root", type=Path, default=Path.cwd()); args = parser.parse_args(argv)
    findings = audit(args.root.resolve())
    print(json.dumps({"schema":"distributed_world_simulator.harness_instruction_hygiene_report.v1","ok":not findings,"findings":findings}, ensure_ascii=False, sort_keys=True))
    return 0 if not findings else 1

if __name__ == "__main__": raise SystemExit(main())
