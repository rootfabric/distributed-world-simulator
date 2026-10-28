#!/usr/bin/env python3
"""Fail-closed exact A6 research verifier; Python standard library only."""
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

BASE = "ce98434481c90f7661f787ceb89b07104a586a2f"
GODOT_SHA = "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"
VERSION = "4.7.1.stable.double.custom_build.a13da4feb"
RM_COUNTS = {11: 9, 12: 29, 13: 13, 14: 21, 15: 12, 16: 10, 17: 13,
             18: 12, 19: 10, 20: 12, 21: 8, 22: 13, 23: 16, 25: 11,
             26: 11, 27: 13, 28: 12, 29: 9, 30: 7, 32: 12, 33: 17, 34: 19}
ERRORS = re.compile(r"SCRIPT ERROR|Parse Error|ERROR:|FAIL:")


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        value = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
        return value.hexdigest()


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], text=True).strip()


def allowed(path: str) -> bool:
    return (path.startswith("config/ecology/evo-arch2-a6")
            or path.startswith("docs/research/ecology/EVO_ARCH2_A6")
            or path.startswith("tests/research/ecology/v2/arch2_a6")
            or path.startswith("validation/ecology/evo_arch2_a6/")
            or path in {"scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd",
                        "scripts/research/ecology/v2/persistent_environmental_feedback_v1.gd.uid"})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    parser.add_argument("--head", required=True)
    parser.add_argument("--tree", required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    os.chdir(root)
    out = root / "artifacts/a6/exact"
    out.mkdir(parents=True, exist_ok=True)
    summary: dict = {"subject_head": args.head, "subject_tree": args.tree,
                     "accepted_base": BASE, "verdict": "FAIL", "checks": []}
    env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING="1")
    started = time.monotonic()

    def run(name: str, command: list[str], marker: str | None = None,
            count: int = 0, timeout: int = 600) -> Path:
        log = out / (name + ".log")
        with log.open("wb") as stream:
            result = subprocess.run(command, env=env, stdout=stream,
                                    stderr=subprocess.STDOUT, timeout=timeout, check=False)
        text = log.read_text(encoding="utf-8-sig", errors="replace")
        if result.returncode or ERRORS.search(text) or (marker is not None and marker not in text):
            raise RuntimeError(f"{name}: exit={result.returncode}, expected={marker!r}\n{text[-12000:]}")
        summary["checks"].append({"name": name, "result": "PASS", "assertions": count,
                                  "sha256": digest(log)})
        print(f"PASS {name}: {marker or 'exit 0, no runtime errors'}", flush=True)
        return log

    def twice(name: str, script: str, marker: str, count: int) -> None:
        logs = [run(f"{name}-{n}", [str(args.godot), "--headless", "--audio-driver", "Dummy",
                                    "--path", str(root), "--script", "res://" + script], marker, count)
                for n in (1, 2)]
        if logs[0].read_bytes() != logs[1].read_bytes():
            raise RuntimeError(f"{name}: non-identical repeated logs")
        print(f"BYTE_IDENTICAL {name} SHA256={digest(logs[0])}", flush=True)

    try:
        if git("rev-parse", "HEAD") != args.head or git("rev-parse", "HEAD^{tree}") != args.tree:
            raise RuntimeError("EXACT_SUBJECT_MISMATCH")
        if git("status", "--porcelain", "--untracked-files=no"):
            raise RuntimeError("TRACKED_WORKTREE_DIRTY")
        subprocess.run(["git", "merge-base", "--is-ancestor", BASE, args.head], check=True)
        changed = git("diff", "--name-only", BASE, args.head).splitlines()
        if not changed or any(not allowed(path) for path in changed):
            raise RuntimeError(f"BOUNDED_SCOPE_FAILURE: {changed}")
        summary["changed_paths"] = changed
        summary["source_fence"] = "PASS: accepted A0-A5, production, simulation, network unchanged"
        args.godot = args.godot.resolve(strict=True)
        if digest(args.godot) != GODOT_SHA:
            raise RuntimeError("GODOT_BINARY_SHA_MISMATCH")
        version = subprocess.check_output([str(args.godot), "--version"], text=True).strip()
        if version != VERSION:
            raise RuntimeError("GODOT_VERSION_MISMATCH")
        summary["godot"] = {"version": version, "sha256": GODOT_SHA}
        shutil.rmtree(root / ".godot", ignore_errors=True)
        run("cold-import", [str(args.godot), "--headless", "--audio-driver", "Dummy",
                            "--editor", "--path", str(root), "--import"])
        for name, filename, marker, count in [
            ("a6-core", "arch2_a6_exact_acceptance.gd", "EVO_ARCH2_A6_EXACT assertions=77 failed=0", 77),
            ("a6-adversarial", "arch2_a6_adversarial.gd", "EVO_ARCH2_A6_ADVERSARIAL assertions=76 failed=0", 76),
            ("a6-lineage", "arch2_a6_lineage_energy.gd", "EVO_ARCH2_A6_LINEAGE assertions=11 failed=0", 11),
        ]:
            twice(name, "tests/research/ecology/v2/" + filename, marker, count)
        for n in (1, 2):
            shutil.rmtree(root / "artifacts/a6/restart", ignore_errors=True)
            for phase in ("write", "read"):
                run(f"restart-{phase}-{n}", [str(args.godot), "--headless", "--audio-driver", "Dummy",
                    "--path", str(root), "--script", "res://tests/research/ecology/v2/arch2_a6_restart.gd", "--", phase],
                    f"EVO_ARCH2_A6_RESTART phase={phase} failed=0")
        for phase in ("write", "read"):
            if (out / f"restart-{phase}-1.log").read_bytes() != (out / f"restart-{phase}-2.log").read_bytes():
                raise RuntimeError(f"RESTART_{phase}_NONDETERMINISTIC")
        twice("a5-core", "tests/research/ecology/v2/arch2_a5_exact_acceptance.gd", "EVO_ARCH2_A5_EXACT assertions=69 failed=0", 69)
        twice("a5-repairs", "tests/research/ecology/v2/arch2_a5_reviewer_repairs.gd", "EVO_ARCH2_A5_REPAIRS assertions=29 failed=0", 29)
        for number, count in RM_COUNTS.items():
            matches = list(root.glob(f"validation/ecology/evo_arch2_a5/rm_a5_{number}_*.gd"))
            if len(matches) != 1:
                raise RuntimeError(f"RM{number}_SCRIPT_NOT_UNIQUE")
            twice(f"rm{number}", matches[0].relative_to(root).as_posix(),
                  f"EVO_ARCH2_A5_RM{number} assertions={count} failed=0", count)
        for short, count in (("a4", 32), ("a03", 86)):
            run(short, [str(args.godot), "--headless", "--audio-driver", "Dummy", "--path", str(root),
                "--script", f"res://tests/research/ecology/v2/arch2_{short}_exact_acceptance.gd"],
                f"EVO_ARCH2_{short.upper()}_EXACT assertions={count} failed=0", count)
        for i, count in enumerate((87, 70, 57, 101, 92, 114)):
            matches = list(root.glob(f"tests/ecology/eco_evo7_vis5_{i}_*acceptance.gd"))
            if len(matches) != 1:
                raise RuntimeError(f"VIS5_{i}_SCRIPT_NOT_UNIQUE")
            run(f"vis5-{i}", [str(args.godot), "--headless", "--audio-driver", "Dummy", "--path", str(root),
                "--script", "res://" + matches[0].relative_to(root).as_posix()], f"PASS ({count} assertions)", count)
        if (git("rev-parse", "HEAD") != args.head or git("rev-parse", "HEAD^{tree}") != args.tree
                or git("status", "--porcelain", "--untracked-files=no")):
            raise RuntimeError("FINAL_EXACT_SEAL_FAILURE")
        summary["verdict"] = "PASS"
        print(f"SUBJECT_HEAD={args.head}\nSUBJECT_TREE={args.tree}\nVERDICT=PASS", flush=True)
        return 0
    except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
        summary["error"] = str(exc)
        print(f"VERDICT=FAIL\n{exc}", file=sys.stderr, flush=True)
        return 1
    finally:
        summary["elapsed_seconds"] = round(time.monotonic() - started, 3)
        (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    sys.exit(main())
