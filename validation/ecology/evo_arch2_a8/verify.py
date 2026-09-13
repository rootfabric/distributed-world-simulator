#!/usr/bin/env python3
"""Fail-closed exact Linux verifier for EVO ARCH2 A8 Snapshot / Seam."""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
BASE_MAIN = "9e10e640ffc53f82195f1fd930ebafbbc85e482f"
BASE_TREE = "27c62c3774117c5163d0d5dacf789b1310638a92"
GODOT_SHA = "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"
GODOT_VERSION = "4.7.1.stable.double.custom_build.a13da4feb"
PINNED_JSONSCHEMA = "4.22.0"
ERRORS = re.compile(r"SCRIPT ERROR|Parse Error|ERROR:|FAIL:")
EXPECTED_ADDITIONS = {
    "config/ecology/evo-arch2-a8-work-order.v1.json",
    "docs/research/ecology/EVO_ARCH2_A8_SNAPSHOT_SEAM_R1_RU.md",
    "scripts/research/ecology/v2/snapshot_seam_v1.gd",
    "scripts/research/ecology/v2/snapshot_store.py",
    "tests/research/ecology/v2/arch2_a8_acceptance.gd",
    "tests/research/ecology/v2/arch2_a8_restart.gd",
    "validation/ecology/evo_arch2_a8/store_godot_integration.py",
    "validation/ecology/evo_arch2_a8/test_store.py",
    "validation/ecology/evo_arch2_a8/verify.py",
}
CRITICAL_MAIN_PATHS = {
    "scripts/research/ecology/v2/observatory_session_v1.gd",
    "scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd",
    "scripts/research/ecology/v2/local_environment_field_v1.gd",
    "scripts/network/contracts/handoff_ticket.gd",
    "scripts/network/handoff/handoff_state_machine.gd",
    "scripts/network/handoff/world_entity_handoff_session.gd",
    "config/control/project-program-registry.v1.json",
    "config/control/harness/project-goals.v1.json",
    "config/control/harness/checkpoint-catalog.v1.json",
    "project.godot",
}
GENERATED = {
    "artifacts/a7/observatory.png",
    "artifacts/a7/capture-sources.json",
}
RES_PATTERNS = [
    re.compile(r'(?:preload|load)\(\s*["\']res://([^"\']+)["\']\s*\)'),
    re.compile(r'path=["\']res://([^"\']+)["\']'),
]
RM = {11:9,12:29,13:13,14:21,15:12,16:10,17:13,18:12,19:10,20:12,21:8,22:13,
      23:16,25:11,26:11,27:13,28:12,29:9,30:7,32:12,33:17,34:19}


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def gp(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", *args], cwd=ROOT, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=False,
                          env=dict(os.environ, GIT_NO_REPLACE_OBJECTS="1"))


def git(*args: str) -> str:
    p = gp(*args)
    if p.returncode:
        raise RuntimeError(f"git {' '.join(args)}: {p.stderr.strip()}")
    return p.stdout.strip()


def require_exact_resource(head: str, rel: str) -> str:
    path = PurePosixPath(rel)
    if (not rel or rel != rel.strip() or path.is_absolute() or path.as_posix() != rel
            or any(part in (".", "..") for part in path.parts) or "\\" in rel or ":" in rel
            or any(ord(char) < 32 for char in rel)):
        raise RuntimeError("NONCANONICAL_RESOURCE_PATH:" + rel)
    listing = gp("ls-tree", "-z", head, "--", ":(literal)" + rel)
    if listing.returncode:
        raise RuntimeError("RESOURCE_TREE_READ_FAILED:" + rel)
    rows = [row for row in listing.stdout.split("\0") if row]
    if len(rows) != 1:
        raise RuntimeError("RESOURCE_NOT_IN_FROZEN_TREE:" + rel)
    metadata, recorded = rows[0].split("\t", 1)
    mode, kind, oid = metadata.split()
    if recorded != rel or kind != "blob" or mode not in ("100644", "100755"):
        raise RuntimeError("RESOURCE_NOT_REGULAR_BLOB:" + rel)
    target = ROOT
    for part in path.parts:
        target = target / part
        if target.is_symlink():
            raise RuntimeError("RESOURCE_WORKTREE_SYMLINK:" + rel)
    if not target.is_file() or git("hash-object", "--no-filters", "--", rel) != oid:
        raise RuntimeError("RESOURCE_WORKTREE_BYTES_MISMATCH:" + rel)
    return oid


def require_source_closure(head: str) -> dict:
    seeds = [
        "scripts/research/ecology/v2/snapshot_seam_v1.gd",
        "tests/research/ecology/v2/arch2_a8_acceptance.gd",
        "tests/research/ecology/v2/arch2_a8_restart.gd",
    ]
    pending = list(seeds)
    objects: dict[str, str] = {}
    refs = 0
    generated: list[dict[str, str]] = []
    while pending:
        rel = pending.pop()
        if rel in objects:
            continue
        objects[rel] = require_exact_resource(head, rel)
        if not rel.endswith((".gd", ".tscn", ".tres", ".gdshader")):
            continue
        text = (ROOT / rel).read_text(encoding="utf-8-sig")
        for pattern in RES_PATTERNS:
            for match in pattern.finditer(text):
                refs += 1
                dependency = match.group(1)
                if dependency in GENERATED:
                    generated.append({"source": rel, "target": dependency})
                else:
                    pending.append(dependency)
    return {"result": "PASS", "authority": "FROZEN_GIT_TREE_AND_WORKING_BYTES",
            "sources": len(objects), "references": refs, "objects": objects,
            "generated": generated}


def require_unittest_result(text: str, expected: int) -> int:
    counts = re.findall(r"^Ran (\d+) tests? in .+$", text, re.MULTILINE)
    if (counts != [str(expected)] or not re.search(r"^OK\s*$", text, re.MULTILINE)
            or re.search(r"^(?:FAILED|ERROR:|FAIL:)", text, re.MULTILINE) or "skipped=" in text):
        raise RuntimeError(f"MANDATORY_UNITTEST_SUITE_INCOMPLETE:expected={expected}")
    return expected


def require_harness_dependency() -> str:
    declarations = [line.strip() for line in (ROOT / "scripts/harness/requirements.txt").read_text().splitlines()
                    if line.strip().lower().startswith("jsonschema")]
    if declarations != ["jsonschema==" + PINNED_JSONSCHEMA]:
        raise RuntimeError("CANONICAL_HARNESS_DEPENDENCY_PIN_MISMATCH")
    version = importlib.metadata.version("jsonschema")
    if version != PINNED_JSONSCHEMA:
        raise RuntimeError("PINNED_JSONSCHEMA_VERSION_REQUIRED:" + version)
    return version


def require_control_health(value: object) -> str:
    if value not in ("GREEN", "YELLOW"):
        raise RuntimeError("CONTROL_HEALTH_NOT_EXPLICIT_NON_RED:" + repr(value))
    return str(value)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--godot", required=True, type=Path)
    ap.add_argument("--head", required=True)
    ap.add_argument("--tree", required=True)
    args = ap.parse_args()
    os.chdir(ROOT)
    out = ROOT / "artifacts/a8/exact"
    shutil.rmtree(out, ignore_errors=True)
    out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING="1", GIT_NO_REPLACE_OBJECTS="1")
    summary: dict = {"verdict": "FAIL", "subject_head": args.head, "subject_tree": args.tree,
                     "base_main": BASE_MAIN, "base_tree": BASE_TREE, "checks": [], "repeat_pairs": []}
    started = time.monotonic()

    def req(ok: bool, message: str) -> None:
        if not ok:
            raise RuntimeError(message)

    def run(name: str, cmd: list[str], marker: str = "", assertions: int = 0,
            timeout: int = 900, scan: bool = True) -> Path:
        log = out / (name + ".log")
        with log.open("wb") as stream:
            p = subprocess.run(cmd, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT,
                               timeout=timeout, check=False)
        text = log.read_text(encoding="utf-8-sig", errors="replace")
        req(p.returncode == 0 and (not scan or not ERRORS.search(text)) and (not marker or marker in text),
            f"{name}: exit={p.returncode} marker={marker!r}\n{text[-12000:]}")
        summary["checks"].append({"name": name, "result": "PASS", "exit_code": p.returncode,
                                  "assertions": assertions, "sha256": sha(log), "command": cmd})
        print("PASS", name, marker, flush=True)
        return log

    def gd(path: str, *extra: str) -> list[str]:
        return [str(args.godot), "--headless", "--audio-driver", "Dummy", "--path", str(ROOT),
                "--script", "res://" + path, *extra]

    def twice(name: str, path: str, marker: str, assertions: int) -> None:
        first = run(name + "-1", gd(path), marker, assertions)
        second = run(name + "-2", gd(path), marker, assertions)
        req(first.read_bytes() == second.read_bytes(), "REPEAT_MISMATCH:" + name)
        summary["repeat_pairs"].append(name)

    try:
        req(git("rev-parse", "HEAD") == args.head and git("rev-parse", "HEAD^{tree}") == args.tree,
            "EXACT_SUBJECT")
        req(git("rev-parse", BASE_MAIN + "^{tree}") == BASE_TREE, "BASE_TREE_MISMATCH")
        req(gp("merge-base", "--is-ancestor", BASE_MAIN, args.head).returncode == 0,
            "NOT_FRESH_MAIN_DESCENDANT")
        req(git("rev-parse", "--is-shallow-repository") == "false", "SHALLOW_HISTORY_NOT_ALLOWED")
        req(not git("status", "--porcelain", "--untracked-files=no"), "TRACKED_DIRTY")
        records = git("diff", "--name-status", BASE_MAIN, args.head).splitlines()
        actual = set()
        for record in records:
            parts = record.split("\t")
            req(len(parts) == 2 and parts[0] == "A", "A8_NON_ADDITIVE_DIFF:" + record)
            actual.add(parts[1])
        req(actual == EXPECTED_ADDITIONS, "A8_SCOPE_PATH_SET:" + repr(sorted(actual ^ EXPECTED_ADDITIONS)))
        for path in CRITICAL_MAIN_PATHS:
            req(git("rev-parse", args.head + ":" + path) == git("rev-parse", BASE_MAIN + ":" + path),
                "MAIN_OWNER_BYTES_CHANGED:" + path)
        summary["scope"] = {"result": "PASS", "additions": sorted(actual), "modifications": 0,
                            "critical_main_bytes_unchanged": sorted(CRITICAL_MAIN_PATHS)}
        summary["resource_closure"] = require_source_closure(args.head)

        jsonschema = require_harness_dependency()
        store_log = run("a8-store-controls", [sys.executable, "-m", "unittest", "discover", "-s",
                        "validation/ecology/evo_arch2_a8", "-p", "test_store.py", "-v"],
                        "OK", timeout=180, scan=False)
        summary["store_controls"] = {"tests": require_unittest_result(
            store_log.read_text(encoding="utf-8-sig", errors="replace"), 26), "sha256": sha(store_log)}

        args.godot = args.godot.resolve(strict=True)
        req(sha(args.godot) == GODOT_SHA, "GODOT_SHA")
        req(subprocess.check_output([str(args.godot), "--version"], text=True).strip() == GODOT_VERSION,
            "GODOT_VERSION")
        summary["godot"] = {"version": GODOT_VERSION, "sha256": GODOT_SHA}
        shutil.rmtree(ROOT / ".godot", ignore_errors=True)
        shutil.rmtree(ROOT / "artifacts/a8", ignore_errors=True)
        run("cold-import", [str(args.godot), "--headless", "--audio-driver", "Dummy", "--editor",
                            "--path", str(ROOT), "--import"], timeout=300)

        # A8 itself: deterministic controller run, then fresh-process durable CAS/recovery integration.
        first = run("a8-core-1", gd("tests/research/ecology/v2/arch2_a8_acceptance.gd"),
                    "EVO_ARCH2_A8_EXACT", timeout=600)
        manifest1 = (ROOT / "artifacts/a8/checkpoints/manifest.json").read_bytes()
        shutil.rmtree(ROOT / "artifacts/a8/checkpoints", ignore_errors=True)
        second = run("a8-core-2", gd("tests/research/ecology/v2/arch2_a8_acceptance.gd"),
                     "EVO_ARCH2_A8_EXACT", timeout=600)
        manifest2 = (ROOT / "artifacts/a8/checkpoints/manifest.json").read_bytes()
        req(first.read_bytes() == second.read_bytes() and manifest1 == manifest2, "A8_CORE_REPEAT_MISMATCH")
        summary["repeat_pairs"].append("a8-core-and-fixture-manifest")
        store_integration = run("a8-store-godot",
            [sys.executable, "validation/ecology/evo_arch2_a8/store_godot_integration.py", "--godot", str(args.godot)],
            "EVO_ARCH2_A8_STORE_GODOT checkpoints=17 crash_cases=7 semantic_processes=42 failed=0",
            timeout=1200)
        integration_summary = ROOT / "artifacts/a8/store-integration/summary.json"
        req(integration_summary.is_file(), "A8_STORE_INTEGRATION_SUMMARY_MISSING")
        data = json.loads(integration_summary.read_text())
        req(data.get("verdict") == "PASS" and data.get("checkpoint_count") == 17
            and data.get("crash_case_count") == 7 and data.get("semantic_process_count") == 42,
            "A8_STORE_INTEGRATION_SUMMARY_FAIL")
        summary["a8_store_integration"] = {"result": "PASS", "summary_sha256": sha(integration_summary),
                                            "log_sha256": sha(store_integration), **{
                                                key: data[key] for key in ("checkpoint_count", "crash_case_count", "semantic_process_count",
                                                                          "semantic_admission")}}

        suites = [
            ("a7-protocol", "arch2_a7_protocol_guard.gd", "EVO_ARCH2_A7_PROTOCOL assertions=106 failed=0", 106),
            ("a7-core", "arch2_a7_acceptance.gd", "EVO_ARCH2_A7_EXACT assertions=158 failed=0", 158),
            ("a7-ui", "arch2_a7_ui.gd", "EVO_ARCH2_A7_UI assertions=30 failed=0", 30),
            ("a6-core", "arch2_a6_exact_acceptance.gd", "EVO_ARCH2_A6_EXACT assertions=77 failed=0", 77),
            ("a6-adversarial", "arch2_a6_adversarial.gd", "EVO_ARCH2_A6_ADVERSARIAL assertions=76 failed=0", 76),
            ("a6-lineage", "arch2_a6_lineage_energy.gd", "EVO_ARCH2_A6_LINEAGE assertions=11 failed=0", 11),
            ("a5-core", "arch2_a5_exact_acceptance.gd", "EVO_ARCH2_A5_EXACT assertions=69 failed=0", 69),
            ("a5-repairs", "arch2_a5_reviewer_repairs.gd", "EVO_ARCH2_A5_REPAIRS assertions=29 failed=0", 29),
            ("a4", "arch2_a4_exact_acceptance.gd", "EVO_ARCH2_A4_EXACT assertions=32 failed=0", 32),
            ("a03", "arch2_a03_exact_acceptance.gd", "EVO_ARCH2_A03_EXACT assertions=86 failed=0", 86),
        ]
        for name, file, marker, assertions in suites:
            twice(name, "tests/research/ecology/v2/" + file, marker, assertions)

        for stage in ("a7", "a6"):
            for rep in (1, 2):
                shutil.rmtree(ROOT / f"artifacts/{stage}/restart", ignore_errors=True)
                for phase in ("write", "read"):
                    run(f"{stage}-restart-{phase}-{rep}",
                        gd(f"tests/research/ecology/v2/arch2_{stage}_restart.gd", "--", phase),
                        f"EVO_ARCH2_{stage.upper()}_RESTART phase={phase} failed=0")
            for phase in ("write", "read"):
                a = out / f"{stage}-restart-{phase}-1.log"
                b = out / f"{stage}-restart-{phase}-2.log"
                req(a.read_bytes() == b.read_bytes(), f"RESTART_REPEAT:{stage}:{phase}")
                summary["repeat_pairs"].append(f"{stage}-restart-{phase}")

        for number, assertions in RM.items():
            files = list(ROOT.glob(f"validation/ecology/evo_arch2_a5/rm_a5_{number}_*.gd"))
            req(len(files) == 1, f"RM{number}_UNIQUE")
            twice(f"rm{number}", files[0].relative_to(ROOT).as_posix(),
                  f"EVO_ARCH2_A5_RM{number} assertions={assertions} failed=0", assertions)

        req(shutil.which("xvfb-run") is not None, "XVFB_REQUIRED_FOR_A7_GRAPHICS")
        for path in GENERATED:
            target = ROOT / path
            if target.exists() or target.is_symlink():
                target.unlink()
        glog = run("a7-graphical",
            ["xvfb-run", "-a", "-s", "-screen 0 1600x1100x24", str(args.godot),
             "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy", "--path", str(ROOT),
             "--script", "res://tests/research/ecology/v2/arch2_a7_ui.gd", "--", "--capture"],
            "EVO_ARCH2_A7_UI assertions=32 failed=0", 32, timeout=300)
        png = ROOT / "artifacts/a7/observatory.png"
        report = ROOT / "artifacts/a7/capture-sources.json"
        req(png.is_file() and report.is_file(), "A7_GRAPHICAL_EVIDENCE_MISSING")
        summary["graphical"] = {"result": "PASS", "viewport_sha256": sha(png),
                                "source_report_sha256": sha(report), "log_sha256": sha(glog)}

        hlog = run("main-harness-regression",
            [sys.executable, "-m", "unittest", "discover", "-s", "tests/harness", "-p", "test_*.py", "-v"],
            "OK", timeout=600, scan=False)
        htext = hlog.read_text(encoding="utf-8-sig", errors="replace")
        req("FAILED (" not in htext and "ERROR" not in htext and "skipped=" not in htext,
            "HARNESS_REGRESSION_FAILURE_OR_SKIP")
        ran = re.search(r"Ran (\d+) tests", htext)
        req(ran is not None and int(ran.group(1)) >= 325, "HARNESS_DISCOVERY_INCOMPLETE")
        summary["harness"] = {"result": "PASS", "tests": int(ran.group(1)), "jsonschema": jsonschema,
                              "sha256": sha(hlog)}

        cdir = ROOT / "artifacts/a8/control"
        cdir.mkdir(parents=True, exist_ok=True)
        controls = []
        for name, script, extra, artifact in [
            ("standard", "project_control.py", ["--no-fetch", "--no-fail-on-red"], "project-control-report.json"),
            ("directional", "project_control_directional_watch.py", ["--no-fail-on-red"], "directional-watch-report.json")]:
            log = run("control-" + name, [sys.executable, str(ROOT / "scripts/control" / script), *extra],
                      timeout=300, scan=False)
            src = ROOT / "artifacts/control" / artifact
            req(src.is_file(), "CONTROL_REPORT_MISSING:" + name)
            health = require_control_health(json.loads(src.read_text()).get("overall_health"))
            shutil.copyfile(src, cdir / artifact)
            shutil.copyfile(log, cdir / (name + ".log"))
            controls.append({"name": name, "overall_health": health,
                             "report_sha256": sha(src), "log_sha256": sha(log)})
        summary["control"] = controls

        req(git("rev-parse", "HEAD") == args.head and git("rev-parse", "HEAD^{tree}") == args.tree,
            "FINAL_SUBJECT_MOVED")
        req(not git("status", "--porcelain", "--untracked-files=no"), "FINAL_TRACKED_DIRTY")
        req(require_source_closure(args.head) == summary["resource_closure"], "FINAL_RESOURCE_CLOSURE_CHANGED")
        summary["assertion_executions"] = sum(item["assertions"] for item in summary["checks"])
        summary["verdict"] = "PASS"
        print(f"SUBJECT_HEAD={args.head}\nSUBJECT_TREE={args.tree}\nVERDICT=PASS", flush=True)
        return 0
    except (RuntimeError, OSError, subprocess.SubprocessError, json.JSONDecodeError, KeyError) as exc:
        summary["error"] = str(exc)
        print("VERDICT=FAIL\n" + str(exc), file=sys.stderr, flush=True)
        return 1
    finally:
        summary["elapsed_seconds"] = round(time.monotonic() - started, 3)
        (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
