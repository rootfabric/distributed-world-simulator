#!/usr/bin/env python3
"""Exact verifier for stacked EVO ARCH2 A10 R4 persistent body damage overlay."""
from __future__ import annotations
import argparse, hashlib, json, os, subprocess, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PARENT_R3 = "1872fe20437a525c5982266d0fc09bfd4af49fcc"
PARENT_TREE = "53d7627afde687b92beb6ebe43700da9896f5af1"
GODOT_VERSION = "4.7.1.stable.double.custom_build.a13da4feb"
GODOT_SHA256 = "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"

ADDITIONS = {
    "config/ecology/evo-arch2-a10-r4-work-order.v1.json",
    "docs/research/ecology/EVO_ARCH2_A10_R4_BODY_DAMAGE_OVERLAY_RU.md",
    "scripts/research/ecology/v2/body_construction_binding_v1.gd",
    "validation/ecology/evo_arch2_a10_r4/test_body_damage_overlay.gd",
    "validation/ecology/evo_arch2_a10_r4/verify.py",
    ".github/workflows/eco-evo-arch2-a10-r4-exact.yml",
}
IMMUTABLE = {
    "scripts/research/ecology/v2/body_graph_v1.gd",
    "scripts/research/ecology/v2/world_binding_v1.gd",
    "scripts/construction/contracts/construct_snapshot.gd",
    "scripts/research/ecology/v2/organism_life_state_v1.gd",
    "scripts/research/ecology/v2/resource_lifecycle_runtime_v1.gd",
}

def require(ok, message):
    if not ok:
        raise RuntimeError(message)

def git(*args):
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()

def gp(*args):
    return subprocess.run(["git", *args], cwd=ROOT, text=True, capture_output=True, check=False)

def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--godot", required=True, type=Path)
    ap.add_argument("--head", required=True)
    ap.add_argument("--tree", required=True)
    args = ap.parse_args()
    out = ROOT / "artifacts/a10-r4/exact"
    out.mkdir(parents=True, exist_ok=True)
    result = {"verdict": "FAIL", "subject_head": args.head, "subject_tree": args.tree,
              "parent_r3": PARENT_R3, "parent_tree": PARENT_TREE, "checks": []}
    started = time.monotonic()
    try:
        require(git("rev-parse", "HEAD") == args.head, "EXACT_HEAD")
        require(git("rev-parse", "HEAD^{tree}") == args.tree, "EXACT_TREE")
        require(git("rev-parse", PARENT_R3 + "^{tree}") == PARENT_TREE, "R3_PARENT_TREE")
        require(gp("merge-base", "--is-ancestor", PARENT_R3, args.head).returncode == 0, "R3_NOT_ANCESTOR")
        actual = set()
        for row in git("diff", "--name-status", PARENT_R3, args.head).splitlines():
            cols = row.split("\t")
            require(len(cols) == 2 and cols[0] == "A", "R3_SOURCE_CHANGED:" + row)
            actual.add(cols[1])
        require(actual == ADDITIONS, "A10_R4_ADDITIVE_SCOPE:" + json.dumps(sorted(actual)))
        for path in sorted(IMMUTABLE):
            require(git("rev-parse", f"{PARENT_R3}:{path}") == git("rev-parse", f"{args.head}:{path}"),
                    "IMMUTABLE_SOURCE_CHANGED:" + path)
        result["checks"].append("stacked_additive_scope")

        args.godot = args.godot.resolve(strict=True)
        require(sha256(args.godot) == GODOT_SHA256, "GODOT_SHA256")
        version = subprocess.check_output([str(args.godot), "--version"], text=True).strip()
        require(version == GODOT_VERSION, "GODOT_VERSION:" + version)
        result["godot"] = {"version": version, "sha256": GODOT_SHA256}

        log = out / "body-damage-overlay.log"
        env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING="1")
        cmd = [str(args.godot), "--headless", "--audio-driver", "Dummy", "--path", str(ROOT),
               "--script", "res://validation/ecology/evo_arch2_a10_r4/test_body_damage_overlay.gd"]
        with log.open("wb") as stream:
            proc = subprocess.run(cmd, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT,
                                  timeout=300, check=False)
        text = log.read_text(encoding="utf-8-sig", errors="replace")
        require(proc.returncode == 0, "A10_R4_GODOT_EXIT:" + text[-8000:])
        require("EVO_ARCH2_A10_R4_DAMAGE_OVERLAY PASS" in text, "A10_R4_PASS_MARKER:" + text[-8000:])
        require("A10_R4_FAILURE " not in text and "SCRIPT ERROR:" not in text and "Parse Error:" not in text,
                "A10_R4_RUNTIME_ERROR:" + text[-8000:])
        marker = next((line for line in text.splitlines() if line.startswith("EVO_ARCH2_A10_R4_DAMAGE_OVERLAY checks=")), "")
        require("failed=0" in marker, "A10_R4_ASSERTIONS:" + marker)
        result["runtime"] = {"marker": marker, "log_sha256": sha256(log), "exit_code": proc.returncode}
        result["checks"].append("persistent_damage_overlay")

        source = (ROOT / "scripts/research/ecology/v2/body_construction_binding_v1.gd").read_text(encoding="utf-8")
        require("organism_life_state_v1.gd" not in source and "resource_lifecycle_runtime_v1.gd" not in source,
                "R4_MUTATES_ACCEPTED_A5_PATH")
        require("PARTIAL_PHYSICAL_PROXY" in source, "R4_COVERAGE_SCOPE_MISSING")
        result["checks"].append("a5_history_not_rewritten")

        require(not git("status", "--porcelain", "--untracked-files=no"), "TRACKED_SOURCE_DIRTY")
        result["verdict"] = "PASS"
        print(f"EVO_ARCH2_A10_R4_EXACT verdict=PASS head={args.head} tree={args.tree}")
        return 0
    except Exception as exc:
        result["error"] = str(exc)
        print("A10_R4_EXACT_FAILURE: " + str(exc))
        return 1
    finally:
        result["elapsed_seconds"] = round(time.monotonic() - started, 3)
        (out / "summary.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")

if __name__ == "__main__":
    raise SystemExit(main())
