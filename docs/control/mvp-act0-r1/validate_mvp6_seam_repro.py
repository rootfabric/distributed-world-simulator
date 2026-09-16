#!/usr/bin/env python3
"""Bounded native gap reproduction. Expected product rejection is NOT acceptance."""
from __future__ import annotations
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
BASE = "182d93872bfddbf52a72ab170371ebb9489690bb"
OUT = ROOT / "artifacts/mvp6-seam-repro"
TEST = "tests/runtime/test_v0_mvp_6_cross_authority_prerequisites.gd"
PIN = {"linux": "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7", "win32": "3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5"}
FATAL = re.compile(r"(?im)^\s*(?:SCRIPT ERROR|ERROR):|Parse Error|Compile Error")


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def run(name: str, command: list[str], timeout: int, env: dict[str, str]) -> dict:
    start = time.monotonic()
    log = OUT / (name + ".log")
    with log.open("w", encoding="utf-8") as stream:
        try:
            code = subprocess.run(command, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT, check=False, timeout=timeout).returncode
        except subprocess.TimeoutExpired:
            code = 124
        except OSError as exc:
            stream.write(str(exc))
            code = 127
    text = log.read_text(encoding="utf-8-sig", errors="replace")
    result = {"name": name, "command": command, "exit_code": code, "duration_seconds": round(time.monotonic() - start, 3), "fatal_markers": bool(FATAL.search(text)), "log_sha256": sha(log)}
    print(json.dumps(result), flush=True)
    if code and name not in ("drive", "closemission"):
        print(text[-2400:], flush=True)
    return result


def main() -> int:
    if OUT.exists():
        raise RuntimeError("PRESERVE_EXISTING_EVIDENCE:" + str(OUT))
    OUT.mkdir(parents=True)
    expected = os.environ.get("EXPECTED_HEAD", "")
    head, tree = git("rev-parse", "HEAD"), git("rev-parse", "HEAD^{tree}")
    env = os.environ.copy()
    env.update(EXPECTED_HEAD=head, EXPECTED_TREE=tree, PYTHONDONTWRITEBYTECODE="1", BREAKPOINT_RUNTIME_DISABLED="1", MVP6_SEAM_DIAGNOSTIC_RESULT=str(OUT / "result.json"))
    summary: dict = {"schema": "distributed_world_simulator.mvp6_seam_repro_execution.v1", "subject_head": head, "subject_tree": tree, "baseline_head": BASE, "run_id": env.get("GITHUB_RUN_ID", "local"), "run_attempt": env.get("GITHUB_RUN_ATTEMPT", "1"), "diagnostic_passed": False, "mvp6_predicate_verified": False, "independent_verdict": False, "main_merge": False, "full_world_core_executed": False}
    rows: list[dict] = []
    try:
        assert expected == head, "EXACT_SUBJECT_REQUIRED"
        assert not git("status", "--porcelain", "--untracked-files=no"), "TRACKED_DIRTY_BEFORE"
        subprocess.run(["git", "merge-base", "--is-ancestor", BASE, head], cwd=ROOT, check=True)
        subprocess.run(["git", "diff", "--check", BASE, head], cwd=ROOT, check=True)
        wo = json.loads((ROOT / "config/control/harness/executions/E2026-09-09-V0-MVP-R1/work-orders/V0-MVP-R1-WO-001.v1.json").read_text(encoding="utf-8"))
        assert wo["state"] == "IN_PROGRESS" and "MVP6_CROSS_AUTHORITY_CONSTRUCTION_SEAM" in wo["required_predicates"]
        for path in git("diff", "--name-only", BASE, head).splitlines():
            assert any(fnmatch.fnmatchcase(path, p) for p in wo["allowed_paths"]), "OUTSIDE_ALLOWED:" + path
            assert not any(fnmatch.fnmatchcase(path, p) for p in wo["forbidden_paths"]), "FORBIDDEN:" + path
        engine = Path(env["GODOT_BIN"]).resolve()
        summary["engine_sha256"] = sha(engine)
        assert summary["engine_sha256"] == PIN.get(sys.platform), "CANONICAL_DOUBLE_GODOT_REQUIRED"
        summary["test_blob"] = git("rev-parse", head + ":" + TEST)
        prefix = [str(engine), "--headless", "--path", str(ROOT)]
        imported = run("import", prefix + ["--editor", "--import", "--quit"], 240, env)
        rows.append(imported)
        assert imported["exit_code"] == 0 and not imported["fatal_markers"], "FRESH_IMPORT_FAILED"
        tested = run("seam-prerequisite", prefix + ["--script", "res://" + TEST], 240, env)
        rows.append(tested)
        result_path = OUT / "result.json"
        result = json.loads(result_path.read_text(encoding="utf-8")) if result_path.is_file() else {}
        summary["test_result"] = {k: v for k, v in result.items() if k != "observations"}
        assert tested["exit_code"] == 0 and not tested["fatal_markers"], "NATIVE_DIAGNOSTIC_FAILED"
        assert result.get("subject_head") == head and result.get("subject_tree") == tree, "RESULT_SUBJECT_MISMATCH"
        assert result.get("diagnostic_passed") is True and result.get("failures") == [], "EXPECTED_GAPS_NOT_BOTH_PROVEN"
        assert result.get("mvp6_predicate_verified") is False and result.get("live_five_process_executed") is False, "DIAGNOSTIC_MUST_NOT_ACCEPT_MVP6"
        summary["diagnostic_passed"] = True
    except Exception as exc:
        summary["error"] = type(exc).__name__ + ": " + str(exc)
        print(summary["error"], flush=True)
    finally:
        # Preserve real controller decisions. WAITING_HUMAN and exit 8 are not
        # rewritten as product PASS, nor used to erase diagnostic observations.
        controller = []
        for mode in ("Drive", "CloseMission"):
            name = mode.lower()
            row = run(name, ["pwsh", "-NoProfile", "-File", str(ROOT / "CONTROL_DEVELOPMENT.ps1"), "-" + mode, "-Checkpoint", "V0_PLAYABLE_SEAMLESS_PLANET_COMPOSITION_ACCEPTANCE"], 180, env)
            rows.append(row)
            text = (OUT / (name + ".log")).read_text(encoding="utf-8-sig", errors="replace")
            documents = []
            for line in text.splitlines():
                if line.startswith("{"):
                    try:
                        documents.append(json.loads(line))
                    except json.JSONDecodeError:
                        pass
            write(OUT / (name + ".json"), documents)
            controller.append({"mode": mode, "exit_code": row["exit_code"], "json_documents": len(documents)})
        summary["controller"] = controller
        summary["tracked_after"] = git("status", "--porcelain", "--untracked-files=no")
        summary["identity_unchanged"] = git("rev-parse", "HEAD") == head and git("rev-parse", "HEAD^{tree}") == tree
        summary["diagnostic_passed"] = summary["diagnostic_passed"] and not summary["tracked_after"] and summary["identity_unchanged"]
        write(OUT / "commands.json", rows)
        write(OUT / "summary.json", summary)
        files = [{"path": p.relative_to(OUT).as_posix(), "bytes": p.stat().st_size, "sha256": sha(p)} for p in sorted(OUT.rglob("*")) if p.is_file() and p.name != "manifest.json"]
        write(OUT / "manifest.json", {**summary, "files": files})
        print(json.dumps({"head": head, "tree": tree, "diagnostic_passed": summary["diagnostic_passed"], "manifest_sha256": sha(OUT / "manifest.json"), "files": len(files)}), flush=True)
    return 0 if summary["diagnostic_passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
