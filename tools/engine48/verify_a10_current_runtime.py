#!/usr/bin/env python3
"""ENGINE48 A10 current-snapshot runtime regression, not historical A10 handoff acceptance.

The original A10 R1..R5 verify.py files intentionally validate an exact historical
add-only PR diff and MUST remain unchanged. On a later 4.8 product integration,
exercise the same five gameplay tests against a SHA-pinned 4.8 double editor.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import platform
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXPECTED_SHA = {
    "Linux": "4d72a93edf3b4193bdbf22f72c0c9d15c14aa7130c07cf1638f88ca1f9744f6f",
    "Windows": "f53f90f686a4eb05df076692c1b67a9e3d12d7c6c981cf86f1015d1ec36a2636",
}
VERSION = "4.8.beta1.double.custom_build.4d10419ca"
CASES = [
    ("r1", "res://validation/ecology/evo_arch2_a10/test_world_binding.gd", "EVO_ARCH2_A10_WORLD_BINDING PASS"),
    ("r2", "res://validation/ecology/evo_arch2_a10_r2/test_resource_mapping.gd", "EVO_ARCH2_A10_R2_RESOURCE_MAPPING PASS"),
    ("r3", "res://validation/ecology/evo_arch2_a10_r3/test_seam_binding.gd", "EVO_ARCH2_A10_R3_SEAM_BINDING PASS"),
    ("r4", "res://validation/ecology/evo_arch2_a10_r4/test_body_damage_overlay.gd", "EVO_ARCH2_A10_R4_DAMAGE_OVERLAY PASS"),
    ("r5", "res://validation/ecology/evo_arch2_a10_r5/test_final_composition.gd", "EVO_ARCH2_A10_R5_FINAL_COMPOSITION PASS"),
]
FATAL = re.compile(r"SCRIPT ERROR:|Parse Error:|Compile Error:|Failed to load script|_FAILURE\b|_FAIL\b", re.I)

def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for data in iter(lambda: stream.read(1048576), b""):
            h.update(data)
    return h.hexdigest()

def git(*args: str) -> str:
    return subprocess.check_output(["git", "-C", str(ROOT), *args], text=True).strip()

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", type=Path, required=True)
    ap.add_argument("--stage", choices=[c[0] for c in CASES], required=True)
    args = ap.parse_args()
    dest = ROOT / "artifacts" / "engine48" / "eco-a10-current" / args.stage
    dest.mkdir(parents=True, exist_ok=True)
    result = {"schema": "dws.engine48.a10.current-regression.v1",
              "stage": args.stage, "engine_sha256_expected": EXPECTED_SHA.get(platform.system()),
              "runs": [], "verdict": "FAIL"}
    try:
        result["head"] = git("rev-parse", "HEAD")
        result["tree"] = git("rev-parse", "HEAD^{tree}")
        if git("status", "--porcelain", "--untracked-files=no"):
            raise RuntimeError("TRACKED_SOURCE_DIRTY_BEFORE")
        marker = (ROOT / "project.godot").read_text(encoding="utf-8")
        if '"4.8"' not in marker:
            raise RuntimeError("PROJECT_48_MARKER_REQUIRED")
        engine = args.godot.expanduser().resolve(strict=True)
        digest = sha256(engine)
        result["engine_sha256"] = digest
        if digest != EXPECTED_SHA.get(platform.system()):
            raise RuntimeError("ENGINE48_EDITOR_SHA256_MISMATCH")
        version = subprocess.check_output([str(engine), "--version"], text=True).strip()
        if version != VERSION:
            raise RuntimeError("ENGINE48_EDITOR_VERSION_MISMATCH:" + version)
        for stage, script, marker in CASES[:int(args.stage[1])]:
            log = dest / (stage + ".log")
            command = [str(engine), "--headless", "--audio-driver", "Dummy", "--path", str(ROOT), "--script", script]
            with log.open("wb") as output:
                run = subprocess.run(command, cwd=ROOT, stdout=output, stderr=subprocess.STDOUT, timeout=600, check=False)
            content = log.read_text(encoding="utf-8-sig", errors="replace")
            checked = {"stage": stage, "script": script, "exit_code": run.returncode, "marker": marker,
                       "marker_count": content.splitlines().count(marker), "sha256_log": sha256(log)}
            result["runs"].append(checked)
            if run.returncode != 0 or checked["marker_count"] != 1 or FATAL.search(content):
                raise RuntimeError("A10_R3_RUNTIME_FAIL:" + stage + ":" + content[-1200:])
        if git("rev-parse", "HEAD") != result["head"] or git("rev-parse", "HEAD^{tree}") != result["tree"]:
            raise RuntimeError("EXACT_GIT_IDENTITY_CHANGED")
        if git("status", "--porcelain", "--untracked-files=no"):
            raise RuntimeError("TRACKED_SOURCE_DIRTY_AFTER")
        result["verdict"] = "PASS"
        print("ENGINE48_A10_CURRENT_REGRESSION_PASS stage=" + args.stage)
        return 0
    except Exception as exc:
        result["error"] = str(exc)
        print("ENGINE48_A10_CURRENT_REGRESSION_FAIL " + str(exc), file=sys.stderr)
        return 1
    finally:
        (dest / "evidence.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")

if __name__ == "__main__":
    sys.exit(main())
