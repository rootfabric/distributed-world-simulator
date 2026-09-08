#!/usr/bin/env python3
"""Audit downloaded P7 evidence without issuing an independent role verdict."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import stat
import zipfile

HEAD = "d24f38da6ab230fdd76cf622801e18280f05848a"
TREE = "9652b4f99aa6c0ae7f584604f576539a60c8a330"
RUN = "34121804645"
ENGINE = "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"
FATAL = re.compile(r"SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to instantiate an autoload|Failed to load script")


def require(condition: bool, label: str) -> None:
    if not condition:
        raise ValueError(label)


def no_duplicates(pairs: list[tuple[str, object]]) -> dict:
    result = {}
    for key, value in pairs:
        require(key not in result, f"DUPLICATE_JSON_KEY:{key}")
        result[key] = value
    return result


def parse(raw: bytes) -> dict:
    value = json.loads(raw.decode("utf-8-sig"), object_pairs_hook=no_duplicates)
    require(isinstance(value, dict), "JSON_OBJECT_REQUIRED")
    return value


def safe_path(name: str) -> str:
    path = PurePosixPath(name)
    require(bool(name) and path.as_posix() == name and not path.is_absolute()
            and all(part not in (".", "..", ".git") for part in path.parts)
            and not any(c in name for c in "\\:\x00\r\n"), "UNSAFE_ARTIFACT_PATH")
    return name


def load_zip(path: Path, sha256: str) -> dict[str, bytes]:
    require(hashlib.sha256(path.read_bytes()).hexdigest() == sha256, "ARCHIVE_SHA256_MISMATCH")
    files = {}
    with zipfile.ZipFile(path) as archive:
        require(sum(item.file_size for item in archive.infolist()) <= 256 * 1024**2, "ARCHIVE_TOO_LARGE")
        for item in archive.infolist():
            if item.is_dir():
                continue
            name = safe_path(item.filename)
            require(name not in files and not stat.S_ISLNK(item.external_attr >> 16), "DUPLICATE_OR_LINK_MEMBER")
            files[name] = archive.read(item)
    return files


def audit_manifest(files: dict[str, bytes], kind: str) -> dict:
    manifest = parse(files["manifest.json"])
    subject = {"head": HEAD, "tree": TREE, "tracked_status": ""}
    require(manifest["subject"] == subject and manifest["workflow_sha"] == HEAD,
            "SUBJECT_NOT_EXACT")
    require(manifest["run_id"] == RUN and manifest["run_attempt"] == "1"
            and manifest["godot_sha256"] == ENGINE and bool(manifest["runner"]), "RUN_NOT_BOUND")
    seen = set()
    for member in manifest["files"]:
        name = safe_path(member["path"])
        require(name not in seen and name != "manifest.json", "INVALID_MANIFEST_MEMBERSHIP")
        seen.add(name)
        require(name in files and len(files[name]) == member["bytes"]
                and hashlib.sha256(files[name]).hexdigest() == member["sha256"], "FILE_DIGEST_MISMATCH")
    require(seen == set(files) - {"manifest.json"}, "INCOMPLETE_MANIFEST")
    require(parse(files["preflight.json"]) == parse(files["postflight.json"]) == subject,
            "CHECKOUT_CHANGED")
    result = parse(files["result.json"])
    require(result["kind"] == kind and result["subject"] == subject
            and result["passed"] is True and result["exit_code"] == 0
            and result["checkout_unchanged"] is True, "RUN_NOT_PASS")
    return manifest


def audit_command(files: dict[str, bytes], name: str, expected: int = 0) -> dict:
    result = parse(files[f"{name}.result.json"])
    command = parse(files[f"{name}.command.json"])
    log = files[f"{name}.log"]
    require(result["exit_code"] == result["expected_exit"] == command["expected_exit"] == expected,
            f"EXIT_MISMATCH:{name}")
    require(result["command"] == command["command"] and result["cwd"] == command["cwd"],
            f"COMMAND_MISMATCH:{name}")
    require(hashlib.sha256(log).hexdigest() == result["log_sha256"]
            and not result["fatal_matches"] and not FATAL.search(log.decode("utf-8", errors="replace")),
            f"LOG_NOT_VALID:{name}")
    return result


def terminal(files: dict[str, bytes], name: str, test: str) -> dict:
    records = [parse(line.encode()) for line in files[f"{name}.log"].decode().splitlines() if line.startswith("{")]
    records = [r for r in records if r.get("test") == test]
    require(len(records) == 1, f"TERMINAL_NOT_UNIQUE:{test}")
    return records[0]


def audit_world(files: dict[str, bytes]) -> dict:
    manifest = audit_manifest(files, "world")
    expected_negative = [f"{case}:{suffix}" for case in
        ("empty", "missing-last", "duplicate", "injected", "foreign-session", "extra", "malformed")
        for suffix in ("withdrawal-must-wait", "no-outbound-withdrawal")] + ["late-receipt:wait"]
    for name, expected in (("baseline-eg4-completion", 1), ("candidate-eg4-completion", 0)):
        audit_command(files, name, expected)
        report = terminal(files, name, "eg4_receipt_completion")
        require(report["assertions"] == 23 and report["verdict"] == ("FAIL" if expected else "PASS")
                and sorted(report["failures"]) == sorted(expected_negative if expected else []), "EG4_CAUSE_NOT_PROVEN")
    for name, expected in (("baseline-probe", 1), ("candidate-probe", 0)):
        audit_command(files, name, expected)
        report = parse(files[f"{name}.json"])
        require(report["passed"] is (expected == 0) and len(report["cases"]) == 2, "ENET_CAUSE_NOT_PROVEN")
        for case in report["cases"]:
            require(case["statistics_before_input"]["limit"] == (1 if expected else 32)
                    and case["statistics_before_input"]["deceleration"] == 2
                    and case["reliable_valid"] and case["input_received"] is (expected == 0), "ENET_OBSERVATION_INVALID")
    campaigns = {"eg1": (5, 36, "eg1_gateway_processes_l2"), "eg4": (3, 46, "eg4_gateway_processes_l2")}
    for prefix, (attempts, assertions, test) in campaigns.items():
        for attempt in range(1, attempts + 1):
            name = f"{prefix}-{attempt}"
            audit_command(files, name)
            report = terminal(files, name, test)
            require(report["verdict"] == "PASS" and report["assertions"] == assertions and not report["failures"],
                    f"PROCESS_CAMPAIGN_NOT_PASS:{name}")
    siblings = json.loads(files["focused-sibling-manifest.json"])
    require(len(siblings) == len(set(siblings)) and len(siblings) > 3, "SIBLING_COVERAGE_INVALID")
    for sibling in siblings:
        audit_command(files, sibling.removesuffix(".gd"))
    full = audit_command(files, "full-world-core")
    summary = parse(files["test-results/world-regression-summary.json"])
    require(summary["passed"] is True and summary["declared_test_count"] == summary["discovered_test_count"] == 325,
            "FULL_TEST_DISCOVERY_NOT_PROVEN")
    steps = summary["steps"]
    require(len(steps) == 328 and len({s["name"] for s in steps}) == 328, "FULL_STEP_SET_INCOMPLETE")
    require(all(s["exit_code"] == 0 and s["passed"] is True for s in steps), "WORLD_STEP_FAILED")
    scripts = [s for s in steps if s["kind"] == "headless_script"]
    require(len(scripts) == 325 and len({s["target"] for s in scripts}) == 325, "SCRIPT_SET_INCOMPLETE")
    require([s["name"] for s in steps if s["kind"] != "headless_script"] ==
            ["test_manifest_coverage", "editor_import_parse", "main_scene_cli_all"], "AGGREGATE_MISSING")
    return {"kind": "IMPLEMENTER_ARTIFACT_AUDIT_NOT_INDEPENDENT_VERDICT", "passed": True,
            "subject": manifest["subject"], "runner": manifest["runner"], "manifest_file_count": len(manifest["files"]),
            "world_stages": len(steps), "world_scripts": len(scripts), "world_exit_code": full["exit_code"],
            "eg1_fixed_campaign": 5, "eg4_fixed_campaign": 3, "siblings": len(siblings),
            "baseline_eg4_expected_failures": 15, "candidate_eg4_assertions": 23,
            "canonical_acceptance": False, "independent_verdict": None}
