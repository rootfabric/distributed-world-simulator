#!/usr/bin/env python3
"""Exact A7 mechanical verification. Does not declare research acceptance."""
from __future__ import annotations
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
BASE = "993271eb46880b77f0e7584f931131d4bd0a5125"
GODOT_SHA = "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"
VERSION = "4.7.1.stable.double.custom_build.a13da4feb"

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()

def require(ok: bool, message: str) -> None:
    if not ok:
        raise RuntimeError(message)

def allowed(path: str) -> bool:
    return any(path.startswith(prefix) for prefix in (
        "config/ecology/evo-arch2-a7", "docs/research/ecology/EVO_ARCH2_A7",
        "scripts/research/ecology/v2/observatory_", "scripts/labs/ecology/arch2_a7_",
        "scenes/labs/ecology/arch2_a7_", "tests/research/ecology/v2/arch2_a7_",
        "validation/ecology/evo_arch2_a7/"))

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--tree", required=True)
    parser.add_argument("--graphical", action="store_true", help="Require Xvfb viewport capture in addition to headless UI checks")
    args = parser.parse_args()
    os.chdir(ROOT)
    out = ROOT / "artifacts/a7/exact"
    out.mkdir(parents=True, exist_ok=True)
    summary = {"subject_head": args.head, "subject_tree": args.tree, "accepted_base": BASE,
               "verdict": "FAIL", "checks": [], "repeat_pairs": [], "graphical_requested": args.graphical}
    env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING="1")
    start = time.monotonic()
    spec = importlib.util.spec_from_file_location("a6_verifier", ROOT / "validation/ecology/evo_arch2_a6/verify.py")
    a6 = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(a6)

    def run(name: str, command: list[str], marker: str = "", count: int = 0) -> Path:
        path = out / (name + ".log")
        with path.open("wb") as stream:
            proc = subprocess.run(command, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT, timeout=600)
        text = path.read_text(encoding="utf-8-sig", errors="replace")
        require(proc.returncode == 0 and not a6.ERRORS.search(text) and (not marker or marker in text),
                f"{name}: exit={proc.returncode}, marker={marker!r}\n{text[-6000:]}")
        summary["checks"].append({"name": name, "result": "PASS", "exit_code": proc.returncode,
                                  "assertions": count, "sha256": sha(path), "command": command})
        print("PASS " + name + " " + marker, flush=True)
        return path

    def script(path: str, *extra: str) -> list[str]:
        return [str(args.godot), "--headless", "--audio-driver", "Dummy", "--path", str(ROOT), "--script", "res://" + path, *extra]

    def twice(name: str, path: str, marker: str, count: int) -> None:
        logs = [run(f"{name}-{i}", script(path), marker, count) for i in (1, 2)]
        require(logs[0].read_bytes() == logs[1].read_bytes(), "REPEAT_MISMATCH:" + name)
        summary["repeat_pairs"].append(name)

    try:
        require(git("rev-parse", "HEAD") == args.head and git("rev-parse", "HEAD^{tree}") == args.tree, "EXACT_SUBJECT")
        require(not git("status", "--porcelain", "--untracked-files=no"), "TRACKED_DIRTY")
        subprocess.run(["git", "merge-base", "--is-ancestor", BASE, args.head], cwd=ROOT, check=True)
        changed = git("diff", "--name-only", BASE, args.head).splitlines()
        require(bool(changed) and all(allowed(p) for p in changed), "A7_SCOPE_FENCE")
        summary["changed_paths"] = changed
        summary["source_fence"] = "PASS: all accepted A0-A6 and production paths unchanged"
        args.godot = args.godot.resolve(strict=True)
        require(sha(args.godot) == GODOT_SHA, "GODOT_SHA")
        require(subprocess.check_output([str(args.godot), "--version"], text=True).strip() == VERSION, "GODOT_VERSION")
        summary["godot"] = {"version": VERSION, "sha256": GODOT_SHA}
        shutil.rmtree(ROOT / ".godot", ignore_errors=True)
        run("cold-import", [str(args.godot), "--headless", "--audio-driver", "Dummy", "--editor", "--path", str(ROOT), "--import"])
        for name, filename, marker, count in [
            ("a7-core", "arch2_a7_acceptance.gd", "EVO_ARCH2_A7_EXACT assertions=158 failed=0", 158),
            ("a7-ui", "arch2_a7_ui.gd", "EVO_ARCH2_A7_UI assertions=30 failed=0", 30),
            ("a6-core", "arch2_a6_exact_acceptance.gd", "EVO_ARCH2_A6_EXACT assertions=77 failed=0", 77),
            ("a6-adversarial", "arch2_a6_adversarial.gd", "EVO_ARCH2_A6_ADVERSARIAL assertions=76 failed=0", 76),
            ("a6-lineage", "arch2_a6_lineage_energy.gd", "EVO_ARCH2_A6_LINEAGE assertions=11 failed=0", 11),
            ("a5-core", "arch2_a5_exact_acceptance.gd", "EVO_ARCH2_A5_EXACT assertions=69 failed=0", 69),
            ("a5-repairs", "arch2_a5_reviewer_repairs.gd", "EVO_ARCH2_A5_REPAIRS assertions=29 failed=0", 29)]:
            twice(name, "tests/research/ecology/v2/" + filename, marker, count)
        for stage in ("a7", "a6"):
            for n in (1, 2):
                shutil.rmtree(ROOT / f"artifacts/{stage}/restart", ignore_errors=True)
                for phase in ("write", "read"):
                    run(f"{stage}-restart-{phase}-{n}", script(f"tests/research/ecology/v2/arch2_{stage}_restart.gd", "--", phase),
                        f"EVO_ARCH2_{stage.upper()}_RESTART phase={phase} failed=0")
            for phase in ("write", "read"):
                require((out / f"{stage}-restart-{phase}-1.log").read_bytes() == (out / f"{stage}-restart-{phase}-2.log").read_bytes(), "RESTART_REPEAT")
                summary["repeat_pairs"].append(f"{stage}-restart-{phase}")
        for number, count in a6.RM_COUNTS.items():
            files = list(ROOT.glob(f"validation/ecology/evo_arch2_a5/rm_a5_{number}_*.gd"))
            require(len(files) == 1, f"RM{number}_UNIQUE")
            twice(f"rm{number}", files[0].relative_to(ROOT).as_posix(), f"EVO_ARCH2_A5_RM{number} assertions={count} failed=0", count)
        for short, count in (("a4", 32), ("a03", 86)):
            run(short, script(f"tests/research/ecology/v2/arch2_{short}_exact_acceptance.gd"), f"EVO_ARCH2_{short.upper()}_EXACT assertions={count} failed=0", count)
        for i, count in enumerate((87, 70, 57, 101, 92, 114)):
            files = list(ROOT.glob(f"tests/ecology/eco_evo7_vis5_{i}_*acceptance.gd"))
            require(len(files) == 1, f"VIS5_{i}_UNIQUE")
            run(f"vis5-{i}", script(files[0].relative_to(ROOT).as_posix()), f"PASS ({count} assertions)", count)
        if args.graphical:
            require(shutil.which("xvfb-run") is not None, "XVFB_REQUIRED")
            run("a7-graphical", ["xvfb-run", "-a", "-s", "-screen 0 1600x1100x24", str(args.godot),
                "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy", "--path", str(ROOT),
                "--script", "res://tests/research/ecology/v2/arch2_a7_ui.gd", "--", "--capture"],
                "EVO_ARCH2_A7_UI assertions=32 failed=0", 32)
            summary["viewport_sha256"] = sha(ROOT / "artifacts/a7/observatory.png")
            summary["viewport_source_report_sha256"] = sha(ROOT / "artifacts/a7/capture-sources.json")
        require(git("rev-parse", "HEAD") == args.head and git("rev-parse", "HEAD^{tree}") == args.tree
                and not git("status", "--porcelain", "--untracked-files=no"), "FINAL_EXACT_SEAL")
        summary["assertion_executions"] = sum(c["assertions"] for c in summary["checks"])
        summary["verdict"] = "PASS"
        print(f"SUBJECT_HEAD={args.head}\nSUBJECT_TREE={args.tree}\nVERDICT=PASS", flush=True)
        return 0
    except (RuntimeError, OSError, subprocess.SubprocessError) as exc:
        summary["error"] = str(exc)
        print("VERDICT=FAIL\n" + str(exc), file=sys.stderr, flush=True)
        return 1
    finally:
        summary["elapsed_seconds"] = round(time.monotonic() - start, 3)
        (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

if __name__ == "__main__":
    sys.exit(main())
