#!/usr/bin/env python3
"""Exact verifier for stacked EVO ARCH2 A10 R2 resource mapping."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
PARENT_R1 = "9ff2d13e31318bd0f323d29a3efd03f0850d8c7b"
PARENT_TREE = "9eaa57d22101c0fdc3caca8225079068c96d3ab0"
GODOT_VERSION = "4.7.1.stable.double.custom_build.a13da4feb"
GODOT_SHA256 = "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"

ADDITIONS = {
    "config/ecology/evo-arch2-a10-r2-work-order.v1.json",
    "docs/research/ecology/EVO_ARCH2_A10_R2_MATTER_RESOURCE_MAPPING_RU.md",
    "scripts/research/ecology/v2/matter_resource_mapping_v1.gd",
    "validation/ecology/evo_arch2_a10_r2/test_resource_mapping.gd",
    "validation/ecology/evo_arch2_a10_r2/verify.py",
    ".github/workflows/eco-evo-arch2-a10-r2-exact.yml",
}
IMMUTABLE = {
    "scripts/research/ecology/v2/world_binding_v1.gd",
    "scripts/research/ecology/v2/environment_field_contract_v1.gd",
    "scripts/simulation/matter/catalog/matter_material_catalog.gd",
    "scripts/simulation/matter/contracts/matter_material_batch.gd",
    "scripts/simulation/matter/contracts/matter_composition.gd",
}

def require(ok: bool, message: str) -> None:
    if not ok:
        raise RuntimeError(message)

def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()

def gp(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(["git", *args], cwd=ROOT, text=True, capture_output=True, check=False)

def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--godot", required=True, type=Path)
    ap.add_argument("--head", required=True)
    ap.add_argument("--tree", required=True)
    args = ap.parse_args()
    out = ROOT / "artifacts/a10-r2/exact"
    out.mkdir(parents=True, exist_ok=True)
    result = {
        "verdict": "FAIL",
        "subject_head": args.head,
        "subject_tree": args.tree,
        "parent_r1": PARENT_R1,
        "parent_tree": PARENT_TREE,
        "checks": [],
    }
    started = time.monotonic()
    try:
        require(git("rev-parse", "HEAD") == args.head, "EXACT_HEAD")
        require(git("rev-parse", "HEAD^{tree}") == args.tree, "EXACT_TREE")
        require(git("rev-parse", PARENT_R1 + "^{tree}") == PARENT_TREE, "R1_PARENT_TREE")
        require(gp("merge-base", "--is-ancestor", PARENT_R1, args.head).returncode == 0, "R1_NOT_ANCESTOR")
        actual = set()
        for row in git("diff", "--name-status", PARENT_R1, args.head).splitlines():
            cols = row.split("\t")
            require(len(cols) == 2 and cols[0] == "A", "R1_SOURCE_CHANGED:" + row)
            actual.add(cols[1])
        require(actual == ADDITIONS, "A10_R2_ADDITIVE_SCOPE:" + json.dumps(sorted(actual)))
        for path in sorted(IMMUTABLE):
            require(git("rev-parse", f"{PARENT_R1}:{path}") == git("rev-parse", f"{args.head}:{path}"),
                    "IMMUTABLE_SOURCE_CHANGED:" + path)
        result["checks"].append("stacked_additive_scope")

        args.godot = args.godot.resolve(strict=True)
        require(sha256(args.godot) == GODOT_SHA256, "GODOT_SHA256")
        version = subprocess.check_output([str(args.godot), "--version"], text=True).strip()
        require(version == GODOT_VERSION, "GODOT_VERSION:" + version)
        result["godot"] = {"version": version, "sha256": GODOT_SHA256}

        log = out / "resource-mapping.log"
        env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING="1")
        cmd = [
            str(args.godot), "--headless", "--audio-driver", "Dummy",
            "--path", str(ROOT),
            "--script", "res://validation/ecology/evo_arch2_a10_r2/test_resource_mapping.gd",
        ]
        with log.open("wb") as stream:
            proc = subprocess.run(cmd, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT,
                                  timeout=300, check=False)
        text = log.read_text(encoding="utf-8-sig", errors="replace")
        require(proc.returncode == 0, "A10_R2_GODOT_EXIT:" + text[-5000:])
        require("EVO_ARCH2_A10_R2_RESOURCE_MAPPING PASS" in text, "A10_R2_PASS_MARKER:" + text[-5000:])
        require("A10_R2_FAILURE " not in text and "SCRIPT ERROR:" not in text and "Parse Error:" not in text,
                "A10_R2_RUNTIME_ERROR:" + text[-5000:])
        marker = next((line for line in text.splitlines() if line.startswith("EVO_ARCH2_A10_R2_RESOURCE_MAPPING checks=")), "")
        require("failed=0" in marker, "A10_R2_ASSERTIONS:" + marker)
        result["runtime"] = {"marker": marker, "log_sha256": sha256(log), "exit_code": proc.returncode}
        result["checks"].append("resource_mapping_godot")

        source = (ROOT / "scripts/research/ecology/v2/matter_resource_mapping_v1.gd").read_text(encoding="utf-8")
        require("default_catalog" not in source, "HIDDEN_DEFAULT_MAPPING")
        require("CANONICAL_BATCH_ADMISSION_NOT_ENVIRONMENT_EXTRACTION" in source, "SCOPE_MARKER")
        result["checks"].append("no_default_semantics")

        require(not git("status", "--porcelain", "--untracked-files=no"), "TRACKED_SOURCE_DIRTY")
        result["verdict"] = "PASS"
        print(f"EVO_ARCH2_A10_R2_EXACT verdict=PASS head={args.head} tree={args.tree}")
        return 0
    except Exception as exc:
        result["error"] = str(exc)
        print("A10_R2_EXACT_FAILURE: " + str(exc))
        return 1
    finally:
        result["elapsed_seconds"] = round(time.monotonic() - started, 3)
        (out / "summary.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")

if __name__ == "__main__":
    raise SystemExit(main())
