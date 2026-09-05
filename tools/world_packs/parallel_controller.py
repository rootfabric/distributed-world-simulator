#!/usr/bin/env python3
"""Branch-local WORLD PACKS parallel workstream controller.

This is deliberately not a replacement for DWS Project Control/Harness.
It only reads Git refs plus branch-owned workstream state and reports:
- divergence from the frozen WORLD PACKS controller branch;
- changed-file scope violations and pairwise overlaps;
- critical main drift since the recorded baseline;
- durable progress, validation freshness, blockers and the next bounded action.
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
CONFIG_PATH = ROOT / "config/world_packs/parallel/controller.v1.json"
VALID_STATUSES = {
    "PLANNED",
    "IN_PROGRESS",
    "BLOCKED",
    "IMPLEMENTED",
    "VERIFYING",
    "VERIFIED",
    "READY_FOR_INTEGRATION",
    "INTEGRATED",
}
STATE_SCHEMA = "dws.world_packs.parallel_workstream_state.v1"


class ControlError(RuntimeError):
    pass


@dataclass
class GitResult:
    code: int
    stdout: str
    stderr: str


def run_git(*args: str, check: bool = True) -> GitResult:
    process = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    result = GitResult(process.returncode, process.stdout.strip(), process.stderr.strip())
    if check and result.code != 0:
        raise ControlError(f"git {' '.join(args)} failed: {result.stderr or result.stdout}")
    return result


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ControlError(f"cannot load {path.relative_to(ROOT)}: {exc}") from exc
    if not isinstance(value, dict):
        raise ControlError(f"{path.relative_to(ROOT)} must contain a JSON object")
    return value


def path_matches(path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatchcase(path, pattern) for pattern in patterns)


def resolve_ref(branch: str, remote: str) -> str | None:
    candidates = (f"refs/remotes/{remote}/{branch}", f"refs/heads/{branch}", branch)
    for candidate in candidates:
        probe = run_git("rev-parse", "--verify", "--quiet", candidate, check=False)
        if probe.code == 0 and probe.stdout:
            return candidate
    return None


def head_sha(ref: str) -> str:
    return run_git("rev-parse", ref).stdout


def divergence(base_ref: str, head_ref: str) -> tuple[int, int]:
    raw = run_git("rev-list", "--left-right", "--count", f"{base_ref}...{head_ref}").stdout.split()
    if len(raw) != 2:
        raise ControlError("unexpected git rev-list output")
    return int(raw[0]), int(raw[1])


def merge_base(base_ref: str, head_ref: str) -> str:
    return run_git("merge-base", base_ref, head_ref).stdout


def changed_files(base_ref: str, head_ref: str) -> list[str]:
    output = run_git("diff", "--name-only", f"{base_ref}...{head_ref}").stdout
    return [line for line in output.splitlines() if line]


def changed_files_range(base_ref: str, head_ref: str) -> list[str]:
    output = run_git("diff", "--name-only", f"{base_ref}..{head_ref}").stdout
    return [line for line in output.splitlines() if line]


def json_from_ref(ref: str, path: str) -> dict[str, Any] | None:
    result = run_git("show", f"{ref}:{path}", check=False)
    if result.code != 0:
        return None
    try:
        value = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise ControlError(f"{ref}:{path} is invalid JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise ControlError(f"{ref}:{path} must contain a JSON object")
    return value


def state_path(config: dict[str, Any], track_id: str) -> str:
    return config["policy"]["state_path_template"].format(track_id=track_id)


def validate_state(
    config: dict[str, Any],
    track: dict[str, Any],
    state: dict[str, Any] | None,
) -> list[str]:
    if state is None:
        return ["STATE_MISSING"]
    errors: list[str] = []
    expected = {
        "schema": STATE_SCHEMA,
        "controller_id": config["controller_id"],
        "track_id": track["id"],
        "branch": track["branch"],
    }
    for key, wanted in expected.items():
        if state.get(key) != wanted:
            errors.append(f"STATE_{key.upper()}_MISMATCH")
    status = state.get("status")
    if status not in VALID_STATUSES:
        errors.append("STATE_STATUS_INVALID")
    completed = state.get("completed_milestones")
    if not isinstance(completed, list) or any(not isinstance(item, str) for item in completed):
        errors.append("STATE_COMPLETED_INVALID")
    else:
        declared = set(track["milestones"])
        if not set(completed).issubset(declared):
            errors.append("STATE_UNKNOWN_MILESTONE")
        if len(completed) != len(set(completed)):
            errors.append("STATE_DUPLICATE_MILESTONE")
    blockers = state.get("blockers")
    if not isinstance(blockers, list) or any(not isinstance(item, str) for item in blockers):
        errors.append("STATE_BLOCKERS_INVALID")
    if not isinstance(state.get("next_action"), str) or not state.get("next_action", "").strip():
        errors.append("STATE_NEXT_ACTION_MISSING")
    validations = state.get("validation")
    if not isinstance(validations, list):
        errors.append("STATE_VALIDATION_INVALID")
    else:
        for item in validations:
            if not isinstance(item, dict):
                errors.append("STATE_VALIDATION_INVALID")
                break
            required = {"name", "command", "result", "head"}
            if not required.issubset(item) or any(not isinstance(item[key], str) for key in required):
                errors.append("STATE_VALIDATION_INVALID")
                break
    return errors


def first_incomplete(track: dict[str, Any], state: dict[str, Any] | None) -> str:
    completed = set(state.get("completed_milestones", [])) if state else set()
    for milestone in track["milestones"]:
        if milestone not in completed:
            return milestone
    return "HANDOFF_READY"


def progress_percent(track: dict[str, Any], state: dict[str, Any] | None) -> int:
    if not track["milestones"]:
        return 100
    completed = set(state.get("completed_milestones", [])) if state else set()
    return round(100 * len(completed.intersection(track["milestones"])) / len(track["milestones"]))


def validation_stale(
    config: dict[str, Any],
    track_ref: str,
    state: dict[str, Any] | None,
) -> tuple[bool, list[str]]:
    if not state:
        return False, []
    tested = state.get("tested_head")
    if not isinstance(tested, str) or not tested:
        return False, []
    exists = run_git("cat-file", "-e", f"{tested}^{{commit}}", check=False)
    if exists.code != 0:
        return True, ["TESTED_HEAD_MISSING"]
    head = head_sha(track_ref)
    ancestor = run_git("merge-base", "--is-ancestor", tested, head, check=False)
    if ancestor.code != 0:
        return True, ["TESTED_HEAD_NOT_ANCESTOR"]
    changed = changed_files_range(tested, head)
    exempt = config["validation_exempt_paths"]
    relevant = [path for path in changed if not path_matches(path, exempt)]
    return bool(relevant), relevant


def collect(config: dict[str, Any]) -> dict[str, Any]:
    remote = config["remote"]
    controller_ref = resolve_ref(config["controller_branch"], remote)
    if controller_ref is None:
        raise ControlError(f"controller branch not found: {config['controller_branch']}")
    controller_head = head_sha(controller_ref)

    execution_base_ref = resolve_ref(config["execution_base_branch"], remote)
    execution_base_head = head_sha(execution_base_ref) if execution_base_ref else None
    execution_base_changed_files: list[str] = []
    controller_vs_base: tuple[int, int] | None = None
    if execution_base_ref:
        controller_vs_base = divergence(execution_base_ref, controller_ref)
        if execution_base_head != config["execution_base_sha"]:
            baseline_probe = run_git("cat-file", "-e", f"{config['execution_base_sha']}^{{commit}}", check=False)
            if baseline_probe.code == 0:
                execution_base_changed_files = changed_files_range(
                    config["execution_base_sha"], execution_base_ref
                )

    main_ref = resolve_ref("main", remote)
    main_drift_files: list[str] = []
    critical_main_drift: list[str] = []
    if main_ref:
        baseline_probe = run_git("cat-file", "-e", f"{config['main_baseline_sha']}^{{commit}}", check=False)
        if baseline_probe.code == 0:
            main_drift_files = changed_files_range(config["main_baseline_sha"], main_ref)
            critical_main_drift = [
                path for path in main_drift_files
                if path_matches(path, config["critical_main_watched_paths"])
            ]

    records: list[dict[str, Any]] = []
    for track in config["tracks"]:
        ref = resolve_ref(track["branch"], remote)
        path = state_path(config, track["id"])
        if ref is None:
            records.append({
                "id": track["id"],
                "branch": track["branch"],
                "exists": False,
                "head": None,
                "behind": None,
                "ahead": None,
                "merge_base": None,
                "changed_files": [],
                "scope_violations": [],
                "hard_forbidden": [],
                "state": None,
                "state_errors": ["BRANCH_MISSING"],
                "progress": 0,
                "validation_stale": False,
                "stale_paths": [],
                "next_milestone": track["milestones"][0] if track["milestones"] else "HANDOFF_READY",
            })
            continue

        files = changed_files(controller_ref, ref)
        state = json_from_ref(ref, path)
        allowed = track["allowed_paths"]
        scope_violations = [p for p in files if not path_matches(p, allowed)]
        forbidden = [p for p in files if path_matches(p, config["hard_forbidden_paths"])]
        behind, ahead = divergence(controller_ref, ref)
        stale, stale_paths = validation_stale(config, ref, state)
        errors = validate_state(config, track, state)
        if forbidden:
            errors.append("HARD_FORBIDDEN_PATH_CHANGED")
        if scope_violations:
            errors.append("WORKSTREAM_SCOPE_VIOLATION")
        if stale:
            errors.append("VALIDATION_STALE")
        records.append({
            "id": track["id"],
            "branch": track["branch"],
            "exists": True,
            "head": head_sha(ref),
            "behind": behind,
            "ahead": ahead,
            "merge_base": merge_base(controller_ref, ref),
            "changed_files": files,
            "scope_violations": scope_violations,
            "hard_forbidden": forbidden,
            "state": state,
            "state_errors": sorted(set(errors)),
            "progress": progress_percent(track, state),
            "validation_stale": stale,
            "stale_paths": stale_paths,
            "next_milestone": first_incomplete(track, state),
        })

    ignored_overlap_patterns = [
        "config/world_packs/parallel/workstreams/**",
        "docs/world_packs/evidence/**",
    ]
    overlaps: list[dict[str, Any]] = []
    for index, left in enumerate(records):
        if not left["exists"]:
            continue
        left_files = {
            path for path in left["changed_files"]
            if not path_matches(path, ignored_overlap_patterns)
        }
        for right in records[index + 1:]:
            if not right["exists"]:
                continue
            right_files = {
                path for path in right["changed_files"]
                if not path_matches(path, ignored_overlap_patterns)
            }
            common = sorted(left_files.intersection(right_files))
            if common:
                overlaps.append({"left": left["id"], "right": right["id"], "files": common})

    return {
        "controller_id": config["controller_id"],
        "controller_branch": config["controller_branch"],
        "controller_head": controller_head,
        "execution_base_branch": config["execution_base_branch"],
        "execution_base_sha": config["execution_base_sha"],
        "execution_base_head": execution_base_head,
        "execution_base_changed_files": execution_base_changed_files,
        "controller_vs_base": list(controller_vs_base) if controller_vs_base else None,
        "main_baseline_sha": config["main_baseline_sha"],
        "main_ref": main_ref,
        "main_head": head_sha(main_ref) if main_ref else None,
        "main_drift_files": main_drift_files,
        "critical_main_drift": critical_main_drift,
        "tracks": records,
        "overlaps": overlaps,
    }


def recommended_action(config: dict[str, Any], snapshot: dict[str, Any], record: dict[str, Any]) -> str:
    track = next(item for item in config["tracks"] if item["id"] == record["id"])
    if not record["exists"]:
        return f"Create/restore {track['branch']} from {snapshot['controller_head']} and initialize its workstream state."
    if record["hard_forbidden"]:
        return "STOP: move/revert forbidden-path work; this track may not own canonical simulation/control files."
    if record["scope_violations"]:
        return "STOP: split out-of-scope changes into the correct track before further implementation."
    state = record["state"]
    if state is None:
        return f"Create {state_path(config, track['id'])}, set IN_PROGRESS, then execute {record['next_milestone']}."
    if record["validation_stale"]:
        return f"Re-run focused validation on the current implementation head before claiming progress; stale paths: {', '.join(record['stale_paths'])}."
    if state.get("status") == "BLOCKED":
        blockers = ", ".join(state.get("blockers", [])) or "unspecified blocker"
        return f"Resolve or durably escalate blocker: {blockers}. Do not hide the blocked state."
    if state.get("status") == "READY_FOR_INTEGRATION":
        if snapshot["execution_base_changed_files"]:
            return "Hold integration: the reviewed/execution base moved since dispatch. Revalidate/compose on a fresh integration branch; do not rebase/force-push the worker."
        if snapshot["critical_main_drift"]:
            return "Hold integration and review critical main drift; do not rebase/force-push the worker branch."
        return f"Request independent review and integrate only through {config['policy']['integration_target']}; worker must not self-merge."
    if record["next_milestone"] == "HANDOFF_READY":
        return "Record exact validation/evidence, set READY_FOR_INTEGRATION, push, and open/update the child PR."
    prefix = ""
    if snapshot["execution_base_changed_files"]:
        prefix += "Execution base moved since dispatch; continue only within bounded scope and require fresh integration revalidation. "
    if record["behind"]:
        prefix += f"Controller advanced by {record['behind']} commit(s); keep history, note BASE_DRIFT and revalidate before integration. "
    return prefix + f"Execute next milestone {record['next_milestone']}: {state.get('next_action') or track['first_action']}"


def print_status(config: dict[str, Any], snapshot: dict[str, Any]) -> None:
    print(f"WORLD_PACKS_PARALLEL_CONTROLLER={snapshot['controller_id']}")
    print(f"CONTROLLER={snapshot['controller_branch']}@{snapshot['controller_head']}")
    base_div = snapshot["controller_vs_base"]
    base_div_label = "UNAVAILABLE" if base_div is None else f"controller_ahead={base_div[1]} controller_behind={base_div[0]}"
    print(f"EXECUTION_BASE={snapshot['execution_base_branch']}@{snapshot['execution_base_head'] or 'UNAVAILABLE'} recorded={snapshot['execution_base_sha']} {base_div_label}")
    if snapshot["execution_base_changed_files"]:
        print("EXECUTION_BASE_DRIFT=" + ",".join(snapshot["execution_base_changed_files"]))
    else:
        print("EXECUTION_BASE_DRIFT=NONE")
    print(f"MAIN={snapshot['main_head'] or 'UNAVAILABLE'} baseline={snapshot['main_baseline_sha']}")
    if snapshot["critical_main_drift"]:
        print("CRITICAL_MAIN_DRIFT=" + ",".join(snapshot["critical_main_drift"]))
    else:
        print("CRITICAL_MAIN_DRIFT=NONE")
    if snapshot["overlaps"]:
        for overlap in snapshot["overlaps"]:
            print(f"OVERLAP {overlap['left']} <-> {overlap['right']}: {','.join(overlap['files'])}")
    else:
        print("WORKSTREAM_OVERLAPS=NONE")
    print()
    print(f"{'TRACK':12} {'STATE':22} {'PROG':>5} {'A/B':>9} {'SCOPE':>7} {'VALID':>7} NEXT")
    for record in snapshot["tracks"]:
        state = record["state"]["status"] if record["state"] else ("MISSING" if record["exists"] else "NO_BRANCH")
        divergence_label = "-" if not record["exists"] else f"{record['ahead']}/{record['behind']}"
        scope = "FAIL" if record["scope_violations"] or record["hard_forbidden"] else "OK"
        valid = "STALE" if record["validation_stale"] else ("OK" if record["state"] else "NONE")
        print(
            f"{record['id']:12} {state:22} {record['progress']:>4}% "
            f"{divergence_label:>9} {scope:>7} {valid:>7} {record['next_milestone']}"
        )
        if record["state_errors"]:
            print(" " * 4 + "flags: " + ", ".join(record["state_errors"]))


def print_next(config: dict[str, Any], snapshot: dict[str, Any]) -> None:
    for record in snapshot["tracks"]:
        print(f"[{record['id']}] {recommended_action(config, snapshot, record)}")
    queued = config["queued_integration"]
    ready = all(
        any(r["id"] == track_id and r["state"] and r["state"].get("status") == "READY_FOR_INTEGRATION"
            for r in snapshot["tracks"])
        for track_id in queued["requires_tracks"]
    )
    gates_ready = all(
        any(gate["id"] == gate_id and gate["status"] == "PASS" for gate in config["external_gates"])
        for gate_id in queued["requires_gates"]
    )
    print()
    if ready and gates_ready and not snapshot["execution_base_changed_files"] and not snapshot["critical_main_drift"] and not snapshot["overlaps"]:
        print(f"[{queued['id']}] READY: {queued['next_when_ready']}")
    else:
        missing_tracks = [
            track_id for track_id in queued["requires_tracks"]
            if not any(r["id"] == track_id and r["state"] and r["state"].get("status") == "READY_FOR_INTEGRATION"
                       for r in snapshot["tracks"])
        ]
        missing_gates = [
            gate_id for gate_id in queued["requires_gates"]
            if not any(g["id"] == gate_id and g["status"] == "PASS" for g in config["external_gates"])
        ]
        print(f"[{queued['id']}] WAIT")
        if missing_tracks:
            print("  missing tracks: " + ", ".join(missing_tracks))
        if missing_gates:
            print("  missing gates: " + ", ".join(missing_gates))
        if snapshot["execution_base_changed_files"]:
            print("  execution base moved since controller dispatch")
        if snapshot["critical_main_drift"]:
            print("  critical main drift requires review")
        if snapshot["overlaps"]:
            print("  cross-track file overlaps require resolution")


def print_instructions(config: dict[str, Any], snapshot: dict[str, Any], track_id: str) -> None:
    track = next((item for item in config["tracks"] if item["id"] == track_id), None)
    if track is None:
        raise ControlError(f"unknown track: {track_id}")
    record = next(item for item in snapshot["tracks"] if item["id"] == track_id)
    path = state_path(config, track_id)
    print(f"# WORLD PACKS WORK ORDER — {track_id}")
    print()
    print(f"Branch: `{track['branch']}`")
    print(f"Controller: `{config['controller_branch']}@{snapshot['controller_head']}`")
    print(f"Risk: `{track['risk']}`")
    print(f"Purpose: {track['purpose']}")
    print()
    print("## Start")
    print("```bash")
    print("git fetch --all --prune")
    print("git status --short")
    print(f"git switch {track['branch']} || git switch --track origin/{track['branch']}")
    print("git pull --ff-only")
    print(f"python tools/world_packs/parallel_controller.py verify {track_id} --no-fetch")
    print("```")
    print()
    print("If the worktree is not clean, do not discard somebody else's changes. Use a clean worktree/checkout.")
    print("Read root AGENTS.md and the canonical Project/Harness documents before implementation.")
    print()
    print("## Allowed paths")
    for pattern in track["allowed_paths"]:
        print(f"- `{pattern}`")
    print()
    print("Hard forbidden paths include canonical simulation/control/network ownership. Do not widen scope silently.")
    print()
    print("## Milestones")
    completed = set(record["state"].get("completed_milestones", [])) if record["state"] else set()
    for milestone in track["milestones"]:
        mark = "x" if milestone in completed else " "
        print(f"- [{mark}] {milestone}")
    print()
    print("## Current next action")
    print(recommended_action(config, snapshot, record))
    print()
    print("## Durable checkpoint protocol")
    print("1. Implement exactly one bounded milestone.")
    print("2. Run its focused tests and required predecessor regressions.")
    print("3. `git add` only allowed paths; inspect `git diff --cached`.")
    print("4. Commit implementation with a Conventional Commit; never amend/rebase/force-push.")
    print("5. Push normally: `git push origin HEAD`.")
    print("6. Re-run/confirm validation on that exact implementation commit.")
    print(f"7. Update `{path}` with `tested_head`, validation results, completed milestones, blockers and the next action.")
    print("8. Commit the state/evidence update separately and push it. State/evidence-only commits after tested_head are allowed.")
    print("9. On a blocker, commit BLOCKED state before stopping. Chat-only blockers/progress do not count.")
    print("10. At completion set READY_FOR_INTEGRATION, open/update a child PR into the controller branch, and request independent review. Do not self-merge.")
    print()
    print("## Before every handoff")
    print("```bash")
    print(f"python tools/world_packs/parallel_controller.py verify {track_id}")
    print("python tools/world_packs/parallel_controller.py status --no-fetch")
    print("git status --short")
    print("git log -n 10 --oneline --decorate")
    print("```")
    print("Report exact branch, HEAD, tests actually run, changed files, blockers, controller flags and the generated next action.")


def verify_track(config: dict[str, Any], snapshot: dict[str, Any], track_id: str) -> int:
    record = next((item for item in snapshot["tracks"] if item["id"] == track_id), None)
    if record is None:
        raise ControlError(f"unknown track: {track_id}")
    action = recommended_action(config, snapshot, record)
    print(f"TRACK={track_id}")
    print(f"HEAD={record['head'] or 'MISSING'}")
    print(f"PROGRESS={record['progress']}%")
    print(f"NEXT={action}")
    if snapshot["critical_main_drift"]:
        print("MAIN_WATCH=DRIFT:" + ",".join(snapshot["critical_main_drift"]))
    if record["state_errors"]:
        print("RESULT=NOT_READY")
        for error in record["state_errors"]:
            print(f"ERROR={error}")
        return 2
    print("RESULT=OK")
    return 0


def maybe_fetch(config: dict[str, Any], no_fetch: bool) -> None:
    if no_fetch:
        return
    result = run_git("fetch", "--all", "--prune", check=False)
    if result.code != 0:
        print(f"WARNING: git fetch failed; using existing refs: {result.stderr or result.stdout}", file=sys.stderr)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("status", "next"):
        item = sub.add_parser(name)
        item.add_argument("--no-fetch", action="store_true")
        item.add_argument("--json", action="store_true")
    for name in ("instructions", "verify"):
        item = sub.add_parser(name)
        item.add_argument("track")
        item.add_argument("--no-fetch", action="store_true")
    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        config = load_json(CONFIG_PATH)
        maybe_fetch(config, args.no_fetch)
        snapshot = collect(config)
        if getattr(args, "json", False):
            print(json.dumps(snapshot, indent=2, sort_keys=True))
            return 0
        if args.command == "status":
            print_status(config, snapshot)
            return 0
        if args.command == "next":
            print_next(config, snapshot)
            return 0
        if args.command == "instructions":
            print_instructions(config, snapshot, args.track)
            return 0
        if args.command == "verify":
            return verify_track(config, snapshot, args.track)
        raise ControlError(f"unsupported command: {args.command}")
    except ControlError as exc:
        print(f"WORLD_PACKS_PARALLEL_CONTROL: FAIL: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
