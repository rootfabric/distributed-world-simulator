#!/usr/bin/env python3
"""PC0 project control auditor.

origin/main owns operational project state. Active branches only report local
facts through unique branch passports. The auditor compares those declarations
with real Git refs and writes a derived dashboard/report.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
ARTIFACT_DIR = ROOT / "artifacts" / "control"
REGISTRY_PATH = "config/control/project-program-registry.v1.json"
POLICY_PATH = "config/control/project-control-policy.v1.json"
OWNERSHIP_PATH = "config/control/architecture-ownership.v1.json"
HEALTH_RANK = {"GREEN": 0, "YELLOW": 1, "RED": 2}


def git(*args: str, allow_fail: bool = False) -> str:
    proc = subprocess.run(
        ["git", *args], cwd=ROOT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    if proc.returncode != 0 and not allow_fail:
        raise RuntimeError(f"git {' '.join(args)} failed: {proc.stderr.strip()}")
    return proc.stdout.strip() if proc.returncode == 0 else ""


def load_json_text(text: str, label: str) -> dict[str, Any]:
    try:
        value = json.loads(text)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"Invalid JSON in {label}: {exc}") from exc
    if not isinstance(value, dict):
        raise RuntimeError(f"Expected JSON object in {label}")
    return value


def load_main_owned(path: str) -> dict[str, Any]:
    text = git("show", f"origin/main:{path}", allow_fail=True)
    if text:
        return load_json_text(text, f"origin/main:{path}")
    local = ROOT / path
    if local.exists():
        return load_json_text(local.read_text(encoding="utf-8"), str(local))
    raise RuntimeError(f"Control-plane file missing in origin/main and checkout: {path}")


def load_branch_json(branch_ref: str, path: str) -> dict[str, Any] | None:
    text = git("show", f"{branch_ref}:{path}", allow_fail=True)
    return load_json_text(text, f"{branch_ref}:{path}") if text else None


def ref_exists(ref: str) -> bool:
    return bool(git("rev-parse", "--verify", ref, allow_fail=True))


def changed_files(base: str, head: str) -> list[str]:
    if not base or not head or not ref_exists(base) or not ref_exists(head):
        return []
    out = git("diff", "--name-only", f"{base}..{head}", allow_fail=True)
    return sorted({x.strip() for x in out.splitlines() if x.strip()})


def matches_any(path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatch(path, pattern) for pattern in patterns)


def set_health(record: dict[str, Any], level: str, code: str, detail: str) -> None:
    if HEALTH_RANK[level] > HEALTH_RANK.get(str(record.get("health", "GREEN")), 0):
        record["health"] = level
    record.setdefault("findings", []).append({"level": level, "code": code, "detail": detail})


def remote_ref(branch: str) -> str:
    return f"origin/{branch}"


def branch_divergence(branch_ref: str) -> tuple[int, int, str]:
    raw = git("rev-list", "--left-right", "--count", f"origin/main...{branch_ref}", allow_fail=True)
    behind = ahead = 0
    if raw:
        parts = raw.replace("\t", " ").split()
        if len(parts) >= 2:
            behind, ahead = int(parts[0]), int(parts[1])
    return behind, ahead, git("merge-base", "origin/main", branch_ref, allow_fail=True)


def audit_program(
    key: str,
    central: dict[str, Any],
    registry: dict[str, Any],
    policy: dict[str, Any],
    ownership: dict[str, Any],
) -> dict[str, Any]:
    declared = str(central.get("health_declared", "GREEN"))
    result: dict[str, Any] = {
        "program": key,
        "program_name": central.get("program_name", key),
        "branch": central.get("branch", ""),
        "role": central.get("role", ""),
        "short_description": central.get("short_description", ""),
        "purpose": central.get("purpose", ""),
        "expected_outcome": central.get("expected_outcome", ""),
        "current_stage": central.get("current_stage", ""),
        "stage_status": central.get("stage_status", ""),
        "progress_note": central.get("progress_note", ""),
        "last_accepted_checkpoint": central.get("last_accepted_checkpoint", ""),
        "next_stage": central.get("next_stage", ""),
        "blockers": list(central.get("blockers", [])),
        "health_declared": declared,
        "health": declared if declared in HEALTH_RANK else "YELLOW",
        "findings": [],
    }

    branch = str(central.get("branch", ""))
    if not branch:
        if central.get("requires_passport", False):
            set_health(result, "RED", "ACTIVE_BRANCH_REQUIRED", "Program requires a passport but main declares no active branch.")
        return result

    branch_ref = remote_ref(branch)
    if not ref_exists(branch_ref):
        set_health(result, "RED", "BRANCH_REF_MISSING", branch_ref)
        return result

    result["head"] = git("rev-parse", branch_ref)
    behind, ahead, merge_base = branch_divergence(branch_ref)
    result["main_commits_since_merge_base"] = behind
    result["branch_commits_since_merge_base"] = ahead
    result["merge_base"] = merge_base

    passport_path = str(central.get("passport_path", ""))
    passport = load_branch_json(branch_ref, passport_path) if passport_path else None
    if central.get("requires_passport", False) and passport is None:
        set_health(result, "RED", "BRANCH_PASSPORT_MISSING", f"Missing {passport_path} on {branch}")
        return result
    if passport is None:
        return result

    result["passport_path"] = passport_path
    result["passport_loaded"] = True

    missing = [f for f in policy.get("required_branch_passport_fields", []) if f not in passport]
    if missing:
        set_health(result, "RED", "PASSPORT_FIELDS_MISSING", ", ".join(missing))

    if str(passport.get("branch", "")) != branch or str(passport.get("program", "")) != key:
        set_health(result, "RED", "PASSPORT_IDENTITY_MISMATCH", "Branch/program differs from main registry")

    expected_arch = str(registry.get("architecture_revision", ""))
    if str(passport.get("architecture_revision", "")) != expected_arch:
        set_health(result, "RED", "ARCHITECTURE_REVISION_MISMATCH", f"passport={passport.get('architecture_revision')} main={expected_arch}")

    expected_control = str(registry.get("control_plane_revision", ""))
    if str(passport.get("control_plane_revision", "")) != expected_control:
        set_health(result, "YELLOW", "CONTROL_REVISION_MISMATCH", f"passport={passport.get('control_plane_revision')} main={expected_control}")

    drift = [
        field for field in policy.get("central_registry_mirror_fields", [])
        if passport.get(field) != central.get(field)
    ]
    if drift:
        set_health(result, "YELLOW", "CENTRAL_PASSPORT_DRIFT", ", ".join(drift))

    foundations = dict(ownership.get("foundations", {}))
    for claim in passport.get("ownership_claims", []):
        if not isinstance(claim, dict):
            set_health(result, "RED", "INVALID_OWNERSHIP_CLAIM", str(claim))
            continue
        foundation = str(claim.get("foundation", ""))
        claimed_owner = str(claim.get("claimed_owner", ""))
        canonical = foundations.get(foundation)
        if canonical and claimed_owner and claimed_owner != str(canonical.get("owner", "")):
            set_health(result, "RED", "FOUNDATION_OWNERSHIP_CONFLICT", f"{foundation}: claimed={claimed_owner}, canonical={canonical.get('owner')}")

    # Main dependency drift since the real merge-base.
    main_changes = changed_files(merge_base, "origin/main") if merge_base else []
    watched = list(passport.get("watched_paths", []))
    critical = list(passport.get("critical_watched_paths", []))
    watched_hits = [p for p in main_changes if matches_any(p, watched)]
    critical_hits = [p for p in watched_hits if matches_any(p, critical)]
    result["dependency_drift"] = watched_hits
    result["critical_dependency_drift"] = critical_hits
    if critical_hits:
        set_health(result, "RED", "CRITICAL_DEPENDENCY_DRIFT", "; ".join(critical_hits[:12]))
    elif watched_hits:
        set_health(result, "YELLOW", "DEPENDENCY_DRIFT", "; ".join(watched_hits[:12]))

    # Only branches that own runtime paths need runtime-tested-head freshness.
    runtime_paths = list(passport.get("runtime_paths", []))
    tested = passport.get("tested_heads", {}) if isinstance(passport.get("tested_heads"), dict) else {}
    runtime_tested = str(tested.get("runtime", ""))
    result["runtime_tested_head"] = runtime_tested
    if runtime_paths:
        if runtime_tested:
            if not ref_exists(runtime_tested):
                set_health(result, "RED", "TESTED_HEAD_MISSING", runtime_tested)
            else:
                post_test = changed_files(runtime_tested, branch_ref)
                runtime_after = [p for p in post_test if matches_any(p, runtime_paths)]
                result["runtime_changes_after_test"] = runtime_after
                if runtime_after:
                    set_health(result, "RED", "RUNTIME_VALIDATION_STALE", "; ".join(runtime_after[:12]))
        elif str(central.get("stage_status", "")) == "ACCEPTED":
            set_health(result, "RED", "ACCEPTED_WITHOUT_RUNTIME_TESTED_HEAD", "Accepted active stage has no tested_heads.runtime")
        else:
            set_health(result, "YELLOW", "RUNTIME_TEST_PENDING", "No runtime tested head declared for the active candidate/stage")
    else:
        result["runtime_validation_not_applicable"] = True

    scope_base = str(passport.get("base_commit", ""))
    if scope_base and ref_exists(scope_base) and bool(passport.get("cross_branch_overlap_enabled", True)):
        result["scope_changed_files"] = changed_files(scope_base, branch_ref)
    else:
        result["scope_changed_files"] = []
    return result


def apply_cross_branch_overlap(programs: list[dict[str, Any]], policy: dict[str, Any]) -> list[dict[str, Any]]:
    overlap_policy = dict(policy.get("overlap_policy", {}))
    ignored = list(overlap_policy.get("ignored_patterns", []))
    yellow_patterns = list(overlap_policy.get("yellow_patterns", []))
    overlaps: list[dict[str, Any]] = []
    active = [p for p in programs if p.get("branch") and p.get("scope_changed_files")]
    for i, left in enumerate(active):
        left_files = set(left.get("scope_changed_files", []))
        for right in active[i + 1:]:
            common = sorted(left_files.intersection(set(right.get("scope_changed_files", []))))
            common = [p for p in common if not matches_any(p, ignored)]
            if not common:
                continue
            yellow_only = all(matches_any(p, yellow_patterns) for p in common)
            level = "YELLOW" if yellow_only else "RED"
            code = "CROSS_BRANCH_DOCUMENT_OVERLAP" if yellow_only else "CROSS_BRANCH_RUNTIME_OR_CONTRACT_OVERLAP"
            detail = f"{left['program']} <-> {right['program']}: " + "; ".join(common[:20])
            set_health(left, level, code, detail)
            set_health(right, level, code, detail)
            overlaps.append({"left": left["program"], "right": right["program"], "level": level, "files": common})
    return overlaps


def markdown_report(report: dict[str, Any]) -> str:
    lines: list[str] = [
        "# Distributed World Simulator — Project Control Report",
        "",
        f"Generated: `{report['generated_at_utc']}`  ",
        f"Control plane: `{report['control_plane_revision']}`  ",
        f"Architecture: `{report['architecture_revision']}`  ",
        f"Registry generation: `{report['registry_generation']}`  ",
        f"Overall health: **{report['overall_health']}**",
        "",
        "## Project dynamics",
        "",
        "| Program | Branch | Что это / зачем | Current stage | Сейчас | Next | Health |",
        "|---|---|---|---|---|---|---|",
    ]
    for p in report["programs"]:
        branch = p.get("branch") or "—"
        why = f"{p.get('short_description','')} {p.get('purpose','')}".replace("|", "/")
        progress = str(p.get("progress_note", "")).replace("|", "/")
        lines.append(f"| {p['program']} | `{branch}` | {why} | {p.get('current_stage','')} | {progress} | {p.get('next_stage','')} | **{p.get('health','')}** |")

    lines.extend(["", "## Detailed branch cards", ""])
    for p in report["programs"]:
        lines.extend([
            f"### {p['program']} — {p.get('program_name','')}",
            "",
            f"**Branch:** `{p.get('branch') or 'not declared'}`  ",
            f"**Role:** `{p.get('role','')}`  ",
            f"**Health:** **{p.get('health','')}**  ",
            f"**Stage:** {p.get('current_stage','')} (`{p.get('stage_status','')}`)  ",
            f"**Last accepted:** {p.get('last_accepted_checkpoint','')}  ",
            f"**Next:** {p.get('next_stage','')}",
            "",
            f"**Что это:** {p.get('short_description','')}",
            "",
            f"**Зачем:** {p.get('purpose','')}",
            "",
            f"**Ожидаемый результат:** {p.get('expected_outcome','')}",
            "",
            f"**Сейчас:** {p.get('progress_note','')}",
        ])
        if p.get("blockers"):
            lines.extend(["", "**Blockers:** " + ", ".join(f"`{x}`" for x in p["blockers"])])
        if p.get("branch"):
            lines.extend(["", f"Git: head `{p.get('head','?')}`, main-only `{p.get('main_commits_since_merge_base','?')}`, branch-only `{p.get('branch_commits_since_merge_base','?')}`."])
        if p.get("findings"):
            lines.extend(["", "Findings:"])
            for finding in p["findings"]:
                lines.append(f"- **{finding['level']}** `{finding['code']}` — {finding['detail']}")
        lines.append("")

    lines.extend(["## Cross-branch overlap", ""])
    if report.get("cross_branch_overlaps"):
        for item in report["cross_branch_overlaps"]:
            files = ", ".join(f"`{x}`" for x in item["files"][:20])
            lines.append(f"- **{item['level']}** `{item['left']} ↔ {item['right']}`: {files}")
    else:
        lines.append("No overlap detected in enabled branch-local audit scopes.")

    lines.extend([
        "",
        "## Interpretation",
        "",
        "`GREEN` — continue. `YELLOW` — converge/review before next major acceptance. `RED` — the affected program's next declared major stage/acceptance is blocked until resolved or explicitly reclassified in main.",
        "",
    ])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-fetch", action="store_true")
    parser.add_argument("--no-fail-on-red", action="store_true")
    args = parser.parse_args()

    if not (ROOT / ".git").exists():
        print(f"ERROR: {ROOT} is not a Git checkout", file=sys.stderr)
        return 3
    if not args.no_fetch:
        print("PC0: fetching origin refs...")
        git("fetch", "origin", "--prune")

    registry = load_main_owned(REGISTRY_PATH)
    policy = load_main_owned(POLICY_PATH)
    ownership = load_main_owned(OWNERSHIP_PATH)
    if registry.get("architecture_revision") != policy.get("architecture_revision"):
        raise RuntimeError("Central registry and control policy architecture revisions differ")
    if registry.get("control_plane_revision") != policy.get("control_plane_revision"):
        raise RuntimeError("Central registry and control policy revisions differ")

    programs = [
        audit_program(key, central, registry, policy, ownership)
        for key, central in dict(registry.get("programs", {})).items()
        if isinstance(central, dict)
    ]
    overlaps = apply_cross_branch_overlap(programs, policy)
    overall = "GREEN"
    for program in programs:
        if HEALTH_RANK.get(str(program.get("health", "GREEN")), 0) > HEALTH_RANK[overall]:
            overall = str(program["health"])

    report = {
        "schema": "distributed_world_simulator.project_control_report.v1",
        "generated_at_utc": datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
        "control_plane_revision": registry.get("control_plane_revision"),
        "registry_generation": registry.get("registry_generation"),
        "architecture_revision": registry.get("architecture_revision"),
        "main_head": git("rev-parse", "origin/main", allow_fail=True),
        "overall_health": overall,
        "programs": programs,
        "cross_branch_overlaps": overlaps,
        "global_blocked_transitions": registry.get("global_blocked_transitions", []),
    }

    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    (ARTIFACT_DIR / "project-control-report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (ARTIFACT_DIR / "PROJECT_STATUS_RU.md").write_text(markdown_report(report), encoding="utf-8")

    print("\nDistributed World Simulator — Project Control")
    print(f"Architecture: {report['architecture_revision']}")
    print(f"Control:      {report['control_plane_revision']}")
    print(f"Registry:     {report['registry_generation']}")
    print(f"Overall:      {overall}")
    for p in programs:
        branch = p.get("branch") or "tracked/stable"
        print(f"  {p['program']:<10} {p.get('health',''):<6} {p.get('current_stage','')} [{branch}]")
    print(f"\nReport: {ARTIFACT_DIR / 'PROJECT_STATUS_RU.md'}")
    print(f"JSON:   {ARTIFACT_DIR / 'project-control-report.json'}")

    if overall == "RED" and not args.no_fail_on_red:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
