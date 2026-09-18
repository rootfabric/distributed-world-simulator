#!/usr/bin/env python3
"""Exact bounded verifier for EVO ARCH2 A10 world bindings R1."""
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
BASE_MAIN = "471210d781e521bc7897a8fe859636a07d7a3ab3"
BASE_TREE = "5a4576f365c60fe117e03b9aee31b2359249b7a5"
A9_MAIN_MERGE = "6982a563dd0c88c81449566131852c601ae89868"
GODOT_VERSION = "4.7.1.stable.double.custom_build.a13da4feb"
GODOT_SHA256 = "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"

ADDITIONS = {
    "config/ecology/evo-arch2-a10-work-order.v1.json",
    "docs/research/ecology/EVO_ARCH2_A10_WORLD_BINDINGS_R1_RU.md",
    "scripts/research/ecology/v2/world_binding_v1.gd",
    "validation/ecology/evo_arch2_a10/test_world_binding.gd",
    "validation/ecology/evo_arch2_a10/verify.py",
    ".github/workflows/eco-evo-arch2-a10-exact.yml",
}
IMMUTABLE_PRODUCTION = {
    "scripts/simulation/matter/query/matter_query_result.gd",
    "scripts/simulation/matter/contracts/matter_sample.gd",
    "scripts/network/contracts/authority_region_descriptor.gd",
    "scripts/network/contracts/handoff_ticket.gd",
    "scripts/construction/damage/construction_damage_request.gd",
    "scripts/construction/damage/construction_damage_record.gd",
    "scripts/research/ecology/v2/snapshot_seam_v1.gd",
    "scripts/research/ecology/v2/ecological_fidelity_v1.py",
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
    out = ROOT / "artifacts/a10/exact"
    out.mkdir(parents=True, exist_ok=True)
    result = {
        "verdict": "FAIL",
        "subject_head": args.head,
        "subject_tree": args.tree,
        "base_main": BASE_MAIN,
        "base_tree": BASE_TREE,
        "checks": [],
    }
    started = time.monotonic()
    try:
        require(git("rev-parse", "HEAD") == args.head, "EXACT_HEAD")
        require(git("rev-parse", "HEAD^{tree}") == args.tree, "EXACT_TREE")
        require(git("rev-parse", BASE_MAIN + "^{tree}") == BASE_TREE, "BASE_TREE_MOVED")
        require(gp("merge-base", "--is-ancestor", BASE_MAIN, args.head).returncode == 0, "NOT_CURRENT_MAIN_DESCENT")
        require(gp("merge-base", "--is-ancestor", A9_MAIN_MERGE, args.head).returncode == 0, "A9_NOT_IN_ANCESTRY")
        require(git("rev-parse", "--is-shallow-repository") == "false", "SHALLOW_HISTORY")
        actual = set()
        for row in git("diff", "--name-status", BASE_MAIN, args.head).splitlines():
            cols = row.split("\t")
            require(len(cols) == 2 and cols[0] == "A", "MAIN_OWNED_PATH_CHANGED:" + row)
            actual.add(cols[1])
        require(actual == ADDITIONS, "A10_ADDITIVE_SCOPE:" + json.dumps(sorted(actual)))
        result["scope"] = sorted(actual)
        for path in sorted(IMMUTABLE_PRODUCTION):
            require(git("rev-parse", f"{BASE_MAIN}:{path}") == git("rev-parse", f"{args.head}:{path}"),
                    "PRODUCTION_SOURCE_CHANGED:" + path)
        result["checks"].append("production_sources_byte_identical")

        args.godot = args.godot.resolve(strict=True)
        require(sha256(args.godot) == GODOT_SHA256, "GODOT_SHA256")
        version = subprocess.check_output([str(args.godot), "--version"], text=True).strip()
        require(version == GODOT_VERSION, "GODOT_VERSION:" + version)
        result["godot"] = {"version": version, "sha256": GODOT_SHA256}

        log = out / "world-binding.log"
        env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING="1")
        cmd = [
            str(args.godot), "--headless", "--audio-driver", "Dummy",
            "--path", str(ROOT),
            "--script", "res://validation/ecology/evo_arch2_a10/test_world_binding.gd",
        ]
        with log.open("wb") as stream:
            proc = subprocess.run(cmd, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT,
                                  timeout=300, check=False)
        text = log.read_text(encoding="utf-8-sig", errors="replace")
        require(proc.returncode == 0, "A10_GODOT_EXIT:" + text[-5000:])
        require("EVO_ARCH2_A10_WORLD_BINDING PASS" in text, "A10_PASS_MARKER:" + text[-5000:])
        require("A10_FAILURE " not in text and "SCRIPT ERROR:" not in text and "Parse Error:" not in text,
                "A10_RUNTIME_ERROR:" + text[-5000:])
        marker = next((line for line in text.splitlines() if line.startswith("EVO_ARCH2_A10_WORLD_BINDING checks=")), "")
        require("failed=0" in marker, "A10_ASSERTIONS:" + marker)
        result["checks"].append("a10_world_binding_godot")
        result["runtime"] = {"marker": marker, "log_sha256": sha256(log), "exit_code": proc.returncode}

        # R1 must never derive ecological stock fields from a point Matter sample.
        source = (ROOT / "scripts/research/ecology/v2/world_binding_v1.gd").read_text(encoding="utf-8")
        require('"resource_stock_authority": "NOT_DERIVED_FROM_POINT_SAMPLE"' in source, "POINT_SAMPLE_GUARD")
        for forbidden in ['"water_mg":', '"nutrient_mg":', '"organic_mg":']:
            require(forbidden not in source, "POINT_SAMPLE_STOCK_DERIVATION:" + forbidden)
        result["checks"].append("no_point_sample_resource_minting")

        require(not git("status", "--porcelain", "--untracked-files=no"), "TRACKED_SOURCE_DIRTY")
        result["verdict"] = "PASS"
        print(f"EVO_ARCH2_A10_EXACT verdict=PASS head={args.head} tree={args.tree}")
        return 0
    except Exception as exc:
        result["error"] = str(exc)
        print("A10_EXACT_FAILURE: " + str(exc))
        return 1
    finally:
        result["elapsed_seconds"] = round(time.monotonic() - started, 3)
        (out / "summary.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")

if __name__ == "__main__":
    raise SystemExit(main())
