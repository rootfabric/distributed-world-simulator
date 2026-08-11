#!/usr/bin/env python3
"""PC0 directional dependency-watch hardening.

The primary PC0 auditor detects:
- main -> branch dependency drift,
- same-file cross-branch overlap.

This companion closes the directional blind spot:
an active producer branch can change a path that another active consumer branch
does not modify itself but explicitly watches.

It reads only main-owned registry/policy plus branch-local passports and never
changes project state.
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
HEALTH_RANK = {"GREEN": 0, "YELLOW": 1, "RED": 2}
NON_BLOCKING_GLOBAL_ROLES = {"RESEARCH_DESIGN_FRONTIER"}


def git(*args: str, allow_fail: bool = False) -> str:
    proc = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
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
    return sorted({line.strip() for line in out.splitlines() if line.strip()})


def matches_any(path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatch(path, pattern) for pattern in patterns)


def program_blocks_global_progress(central: dict[str, Any]) -> bool:
    if "blocks_global_progress" in central:
        return bool(central.get("blocks_global_progress"))
    return str(central.get("role", "")) not in NON_BLOCKING_GLOBAL_ROLES


def program_scope(
    key: str,
    central: dict[str, Any],
    policy: dict[str, Any],
) -> dict[str, Any] | None:
    branch = str(central.get("branch", ""))
    passport_path = str(central.get("passport_path", ""))
    if not branch or not passport_path:
        return None

    branch_ref = f"origin/{branch}"
    if not ref_exists(branch_ref):
        return None

    passport = load_branch_json(branch_ref, passport_path)
    if passport is None:
        return None

    base = str(passport.get("base_commit", ""))
    if not base or not ref_exists(base):
        base = git("merge-base", "origin/main", branch_ref, allow_fail=True)

    ignored = list(dict(policy.get("overlap_policy", {})).get("ignored_patterns", []))
    changed = [
        path
        for path in changed_files(base, branch_ref)
        if not matches_any(path, ignored)
    ]

    directional_policy = dict(policy.get("directional_watch_policy", {}))
    suppressed_statuses = {
        str(x)
        for x in directional_policy.get(
            "producer_suppression_stage_statuses",
            ["SOURCE_ACCEPTED_HANDOFF_COMPLETE"],
        )
    }
    stage_status = str(central.get("stage_status", ""))
    producer_enabled = stage_status not in suppressed_statuses

    return {
        "program": key,
        "branch": branch,
        "role": str(central.get("role", "")),
        "blocks_global_progress": program_blocks_global_progress(central),
        "stage_status": stage_status,
        "producer_enabled": producer_enabled,
        "changed_files": changed,
        "watched_paths": list(passport.get("watched_paths", [])),
        "critical_watched_paths": list(passport.get("critical_watched_paths", [])),
    }


def markdown_report(report: dict[str, Any]) -> str:
    lines = [
        "# Distributed World Simulator — Directional Watch Report",
        "",
        f"Generated: `{report['generated_at_utc']}`  ",
        f"Overall health: **{report['overall_health']}**",
        "",
        "This is the PC0 directional dependency supplement:",
        "",
        "```text",
        "producer branch changed files",
        "            ∩",
        "consumer watched_paths / critical_watched_paths",
        "            ↓",
        "consumer YELLOW / RED",
        "```",
        "",
    ]
    if not report["findings"]:
        lines.append("No active producer changes hit another program's watched dependencies.")
    else:
        for finding in report["findings"]:
            paths = ", ".join(f"`{x}`" for x in finding["files"][:20])
            gate = "BLOCKING" if finding.get("global_blocking", True) else "ADVISORY_RESEARCH"
            lines.append(
                f"- **{finding['level']}** `{finding['producer']} → {finding['consumer']}` "
                f"({finding['kind']}, {gate}): {paths}"
            )
    lines.extend(
        [
            "",
            "Accepted handoff/evidence stages listed in "
            "`directional_watch_policy.producer_suppression_stage_statuses` "
            "remain consumers but no longer act as active producers. "
            "RESEARCH_DESIGN_FRONTIER consumers remain fully visible but are advisory to global health. "
            "If a research producer touches a watched path of a blocking consumer, that consumer finding still affects global health.",
            "",
        ]
    )
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-fail-on-red", action="store_true")
    args = parser.parse_args()

    if not (ROOT / ".git").exists():
        print(f"ERROR: {ROOT} is not a Git checkout", file=sys.stderr)
        return 3

    registry = load_main_owned(REGISTRY_PATH)
    policy = load_main_owned(POLICY_PATH)
    scopes = [
        scope
        for key, central in dict(registry.get("programs", {})).items()
        if isinstance(central, dict)
        for scope in [program_scope(key, central, policy)]
        if scope is not None
    ]

    directional_policy = dict(policy.get("directional_watch_policy", {}))
    watched_level = str(directional_policy.get("watched_hit_health", "YELLOW"))
    critical_level = str(directional_policy.get("critical_hit_health", "RED"))
    if watched_level not in HEALTH_RANK or critical_level not in HEALTH_RANK:
        raise RuntimeError("directional_watch_policy contains an invalid health level")

    findings: list[dict[str, Any]] = []
    overall = "GREEN"

    for producer in scopes:
        if not producer["producer_enabled"] or not producer["changed_files"]:
            continue
        producer_files = list(producer["changed_files"])

        for consumer in scopes:
            if producer["program"] == consumer["program"]:
                continue

            critical_hits = [
                path
                for path in producer_files
                if matches_any(path, list(consumer["critical_watched_paths"]))
            ]
            critical_set = set(critical_hits)
            watched_hits = [
                path
                for path in producer_files
                if path not in critical_set
                and matches_any(path, list(consumer["watched_paths"]))
            ]
            global_blocking = bool(consumer.get("blocks_global_progress", True))

            if critical_hits:
                findings.append(
                    {
                        "level": critical_level,
                        "kind": "CRITICAL_WATCH_HIT",
                        "producer": producer["program"],
                        "producer_branch": producer["branch"],
                        "consumer": consumer["program"],
                        "consumer_branch": consumer["branch"],
                        "global_blocking": global_blocking,
                        "files": critical_hits,
                    }
                )
                if global_blocking and HEALTH_RANK[critical_level] > HEALTH_RANK[overall]:
                    overall = critical_level

            if watched_hits:
                findings.append(
                    {
                        "level": watched_level,
                        "kind": "WATCH_HIT",
                        "producer": producer["program"],
                        "producer_branch": producer["branch"],
                        "consumer": consumer["program"],
                        "consumer_branch": consumer["branch"],
                        "global_blocking": global_blocking,
                        "files": watched_hits,
                    }
                )
                if global_blocking and HEALTH_RANK[watched_level] > HEALTH_RANK[overall]:
                    overall = watched_level

    report = {
        "schema": "distributed_world_simulator.directional_watch_report.v1",
        "generated_at_utc": datetime.now(timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "control_plane_revision": registry.get("control_plane_revision"),
        "registry_generation": registry.get("registry_generation"),
        "architecture_revision": registry.get("architecture_revision"),
        "overall_health": overall,
        "program_scopes": scopes,
        "findings": findings,
    }

    ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)
    (ARTIFACT_DIR / "directional-watch-report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    (ARTIFACT_DIR / "DIRECTIONAL_WATCH_STATUS_RU.md").write_text(
        markdown_report(report),
        encoding="utf-8",
    )

    print("\nPC0 Directional Watch")
    print(f"Registry: {report['registry_generation']}")
    print(f"Overall:  {overall}")
    for finding in findings:
        gate = "BLOCK" if finding.get("global_blocking", True) else "ADVISORY"
        print(
            f"  {finding['level']:<6} "
            f"{finding['producer']} -> {finding['consumer']} "
            f"{finding['kind']} {gate}: {len(finding['files'])} path(s)"
        )
    print(f"Report: {ARTIFACT_DIR / 'DIRECTIONAL_WATCH_STATUS_RU.md'}")

    if overall == "RED" and not args.no_fail_on_red:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
