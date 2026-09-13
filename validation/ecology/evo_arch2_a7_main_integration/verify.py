#!/usr/bin/env python3
"""Fail-closed exact verifier for the fresh current-main A7 convergence candidate."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
BASE_MAIN = "7dfc68ab5a1e90254a1b7039807f275b5da04eef"
ACCEPTED_A7 = "8eccf6304078bec3a3ccaa5860c5aab6ee311209"
GODOT_SHA = "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"
GODOT_VERSION = "4.7.1.stable.double.custom_build.a13da4feb"
RM_COUNTS = {11: 9, 12: 29, 13: 13, 14: 21, 15: 12, 16: 10, 17: 13,
             18: 12, 19: 10, 20: 12, 21: 8, 22: 13, 23: 16, 25: 11,
             26: 11, 27: 13, 28: 12, 29: 9, 30: 7, 32: 12, 33: 17, 34: 19}
ERRORS = re.compile(r"SCRIPT ERROR|Parse Error|ERROR:|FAIL:")
ALLOWED_PREFIXES = (
    "config/ecology/evo-arch2-a7-main-integration-",
    "config/ecology/evo-arch2-a7-protocol.v1.json",
    "docs/research/ecology/EVO_ARCH2_A7_MAIN_INTEGRATION",
    "scripts/research/ecology/v2/",
    "scripts/labs/ecology/arch2_a7_",
    "scenes/labs/ecology/arch2_a7_",
    "tests/research/ecology/v2/",
    "validation/ecology/evo_arch2_a5/",
    "validation/ecology/evo_arch2_a7_main_integration/",
)


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def git_proc(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", *args], cwd=ROOT, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE, check=False)


def git(*args: str) -> str:
    proc = git_proc(*args)
    if proc.returncode:
        raise RuntimeError(f"git {' '.join(args)}: {proc.stderr.strip()}")
    return proc.stdout.strip()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--head", required=True)
    parser.add_argument("--tree", required=True)
    args = parser.parse_args()
    os.chdir(ROOT)
    out = ROOT / "artifacts/a7-main-integration/exact"
    out.mkdir(parents=True, exist_ok=True)
    summary: dict = {
        "subject_head": args.head, "subject_tree": args.tree, "base_main": BASE_MAIN,
        "accepted_transfer_source": ACCEPTED_A7, "verdict": "FAIL", "checks": [],
        "repeat_pairs": [], "graphical_required": True, "main_owned_files_modified": False,
    }
    env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING="1")
    started = time.monotonic()

    def require(ok: bool, message: str) -> None:
        if not ok:
            raise RuntimeError(message)

    def run(name: str, command: list[str], marker: str = "", count: int = 0,
            timeout: int = 900, scan_errors: bool = True) -> Path:
        log = out / f"{name}.log"
        with log.open("wb") as stream:
            proc = subprocess.run(command, cwd=ROOT, env=env, stdout=stream,
                                  stderr=subprocess.STDOUT, timeout=timeout, check=False)
        text = log.read_text(encoding="utf-8-sig", errors="replace")
        bad = ERRORS.search(text) if scan_errors else None
        require(proc.returncode == 0 and bad is None and (not marker or marker in text),
                f"{name}: exit={proc.returncode} marker={marker!r}\n{text[-12000:]}")
        summary["checks"].append({"name": name, "result": "PASS", "exit_code": proc.returncode,
                                  "assertions": count, "sha256": digest(log), "command": command})
        print(f"PASS {name} {marker}", flush=True)
        return log

    def script(path: str, *extra: str) -> list[str]:
        return [str(args.godot), "--headless", "--audio-driver", "Dummy", "--path", str(ROOT),
                "--script", "res://" + path, *extra]

    def twice(name: str, path: str, marker: str, count: int) -> None:
        logs = [run(f"{name}-{n}", script(path), marker, count) for n in (1, 2)]
        require(logs[0].read_bytes() == logs[1].read_bytes(), f"REPEAT_MISMATCH:{name}")
        summary["repeat_pairs"].append(name)
        print(f"BYTE_IDENTICAL {name} SHA256={digest(logs[0])}", flush=True)

    try:
        require(shutil.which("xvfb-run") is not None, "XVFB_REQUIRED_FOR_INTEGRATION_GRAPHICS")
        require(git("rev-parse", "HEAD") == args.head, "EXACT_HEAD_MISMATCH")
        require(git("rev-parse", "HEAD^{tree}") == args.tree, "EXACT_TREE_MISMATCH")
        require(not git("status", "--porcelain", "--untracked-files=no"), "TRACKED_WORKTREE_DIRTY")
        require(git("merge-base", BASE_MAIN, args.head) == BASE_MAIN, "NOT_CURRENT_MAIN_DESCENDANT")
        parents = git("rev-list", "--parents", "-n", "1", args.head).split()
        require(len(parents) >= 2 and ACCEPTED_A7 not in parents[1:], "RESEARCH_COMMIT_USED_AS_INTEGRATION_PARENT")

        diff = git("diff", "--name-status", BASE_MAIN, args.head).splitlines()
        require(bool(diff), "EMPTY_INTEGRATION_DIFF")
        additions: list[str] = []
        for line in diff:
            parts = line.split("\t")
            require(len(parts) == 2, f"UNEXPECTED_DIFF_RECORD:{line}")
            status, path = parts
            require(status == "A", f"MAIN_FILE_NOT_ADDITION_ONLY:{line}")
            require(any(path == prefix or path.startswith(prefix) for prefix in ALLOWED_PREFIXES),
                    f"OUT_OF_SCOPE_PATH:{path}")
            additions.append(path)
        require(not any(path.startswith(".github/") for path in additions), "INTEGRATION_SOURCE_OWNS_WORKFLOW")
        require(not any(path.startswith(("scripts/ecology/production/", "scripts/network/", "scripts/simulation/",
                                         "config/control/", "config/architecture/")) or path == "project.godot"
                        for path in additions), "CANONICAL_MAIN_OWNERSHIP_VIOLATION")
        summary["added_paths"] = additions

        expected = json.loads((ROOT / "validation/ecology/evo_arch2_a7_main_integration/expected-transfer.v1.json").read_text())
        require(expected["base_main"] == BASE_MAIN and expected["accepted_a7"] == ACCEPTED_A7,
                "TRANSFER_MANIFEST_IDENTITY")
        for path, sha in expected["subtrees"].items():
            require(git("rev-parse", f"HEAD:{path}") == sha, f"TRANSFER_TREE_MISMATCH:{path}")
            require(git_proc("cat-file", "-e", f"{BASE_MAIN}:{path}").returncode != 0,
                    f"TRANSFER_TREE_ALREADY_EXISTED_ON_MAIN:{path}")
        for path, sha in expected["blobs"].items():
            require(git("rev-parse", f"HEAD:{path}") == sha, f"TRANSFER_BLOB_MISMATCH:{path}")
            require(git_proc("cat-file", "-e", f"{BASE_MAIN}:{path}").returncode != 0,
                    f"TRANSFER_BLOB_ALREADY_EXISTED_ON_MAIN:{path}")
        summary["transfer_identity"] = "PASS"
        summary["base_absence_gate"] = "PASS_BY_GIT_EXIT_STATUS"

        args.godot = args.godot.resolve(strict=True)
        require(digest(args.godot) == GODOT_SHA, "GODOT_BINARY_SHA_MISMATCH")
        version = subprocess.check_output([str(args.godot), "--version"], text=True).strip()
        require(version == GODOT_VERSION, "GODOT_VERSION_MISMATCH")
        summary["godot"] = {"version": version, "sha256": GODOT_SHA}

        shutil.rmtree(ROOT / ".godot", ignore_errors=True)
        run("cold-import", [str(args.godot), "--headless", "--audio-driver", "Dummy", "--editor",
                            "--path", str(ROOT), "--import"], timeout=300)

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
        for name, filename, marker, count in suites:
            twice(name, "tests/research/ecology/v2/" + filename, marker, count)

        for stage in ("a7", "a6"):
            for n in (1, 2):
                shutil.rmtree(ROOT / f"artifacts/{stage}/restart", ignore_errors=True)
                for phase in ("write", "read"):
                    run(f"{stage}-restart-{phase}-{n}",
                        script(f"tests/research/ecology/v2/arch2_{stage}_restart.gd", "--", phase),
                        f"EVO_ARCH2_{stage.upper()}_RESTART phase={phase} failed=0")
            for phase in ("write", "read"):
                a = out / f"{stage}-restart-{phase}-1.log"
                b = out / f"{stage}-restart-{phase}-2.log"
                require(a.read_bytes() == b.read_bytes(), f"RESTART_REPEAT_MISMATCH:{stage}:{phase}")
                summary["repeat_pairs"].append(f"{stage}-restart-{phase}")

        for number, count in RM_COUNTS.items():
            matches = list(ROOT.glob(f"validation/ecology/evo_arch2_a5/rm_a5_{number}_*.gd"))
            require(len(matches) == 1, f"RM{number}_SCRIPT_NOT_UNIQUE")
            twice(f"rm{number}", matches[0].relative_to(ROOT).as_posix(),
                  f"EVO_ARCH2_A5_RM{number} assertions={count} failed=0", count)

        graphical = run("a7-graphical",
            ["xvfb-run", "-a", "-s", "-screen 0 1600x1100x24", str(args.godot),
             "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy", "--path", str(ROOT),
             "--script", "res://tests/research/ecology/v2/arch2_a7_ui.gd", "--", "--capture"],
            "EVO_ARCH2_A7_UI assertions=32 failed=0", 32, timeout=300)
        png = ROOT / "artifacts/a7/observatory.png"
        report = ROOT / "artifacts/a7/capture-sources.json"
        require(png.is_file() and report.is_file(), "GRAPHICAL_EVIDENCE_MISSING")
        summary["viewport_sha256"] = digest(png)
        summary["viewport_source_report_sha256"] = digest(report)
        summary["graphical_log_sha256"] = digest(graphical)

        harness = run("main-harness-regression",
            [sys.executable, "-m", "unittest", "discover", "-s", str(ROOT / "tests/harness"), "-p", "test_*.py", "-v"],
            marker="OK", timeout=600, scan_errors=False)
        harness_text = harness.read_text(encoding="utf-8-sig", errors="replace")
        require("FAILED (" not in harness_text and "ERROR" not in harness_text, "HARNESS_REGRESSION_FAILURE")

        control_dir = ROOT / "artifacts/a7-main-integration/control"
        control_dir.mkdir(parents=True, exist_ok=True)
        control_results = []
        for name, script_name, extra, artifact_name in [
            ("standard", "project_control.py", ["--no-fetch", "--no-fail-on-red"], "project-control-report.json"),
            ("directional", "project_control_directional_watch.py", ["--no-fail-on-red"], "directional-watch-report.json")]:
            log = run(f"control-{name}", [sys.executable, str(ROOT / "scripts/control" / script_name), *extra],
                      timeout=300, scan_errors=False)
            target = ROOT / "artifacts/control" / artifact_name
            require(target.is_file(), f"CONTROL_REPORT_MISSING:{name}")
            parsed = json.loads(target.read_text(encoding="utf-8"))
            health = parsed.get("overall_health", "UNAVAILABLE")
            require(health != "RED", f"CONTROL_RED:{name}")
            shutil.copyfile(target, control_dir / artifact_name)
            shutil.copyfile(log, control_dir / f"{name}.log")
            control_results.append({"name": name, "overall_health": health,
                                    "report_sha256": digest(target), "log_sha256": digest(log)})
        summary["control"] = control_results

        require(git("rev-parse", "HEAD") == args.head, "FINAL_HEAD_MOVED")
        require(git("rev-parse", "HEAD^{tree}") == args.tree, "FINAL_TREE_MOVED")
        require(not git("status", "--porcelain", "--untracked-files=no"), "FINAL_TRACKED_DIRTY")
        summary["assertion_executions"] = sum(c["assertions"] for c in summary["checks"])
        summary["verdict"] = "PASS"
        print(f"SUBJECT_HEAD={args.head}\nSUBJECT_TREE={args.tree}\nVERDICT=PASS", flush=True)
        return 0
    except (RuntimeError, OSError, subprocess.SubprocessError, json.JSONDecodeError) as exc:
        summary["error"] = str(exc)
        print(f"VERDICT=FAIL\n{exc}", file=sys.stderr, flush=True)
        return 1
    finally:
        summary["elapsed_seconds"] = round(time.monotonic() - started, 3)
        (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
