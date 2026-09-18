#!/usr/bin/env python3
"""Exact verifier for stacked EVO ARCH2 A10 R3 production seam binding."""
from __future__ import annotations
import argparse, hashlib, json, os, subprocess, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PARENT_R2 = "bbd8fa6f0479169c6b1638ea97146976e298e52f"
PARENT_TREE = "f0ce4b0dd6ee7c7c0b00a6016e739e9dd8175d56"
GODOT_VERSION = "4.7.1.stable.double.custom_build.a13da4feb"
GODOT_SHA256 = "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"

ADDITIONS = {
    "config/ecology/evo-arch2-a10-r3-work-order.v1.json",
    "docs/research/ecology/EVO_ARCH2_A10_R3_PRODUCTION_SEAM_BINDING_RU.md",
    "scripts/research/ecology/v2/world_seam_binding_v1.gd",
    "validation/ecology/evo_arch2_a10_r3/test_seam_binding.gd",
    "validation/ecology/evo_arch2_a10_r3/verify.py",
    ".github/workflows/eco-evo-arch2-a10-r3-exact.yml",
}
IMMUTABLE = {
    "scripts/research/ecology/v2/snapshot_seam_v1.gd",
    "scripts/research/ecology/v2/world_binding_v1.gd",
    "scripts/network/contracts/authority_region_descriptor.gd",
    "scripts/network/contracts/handoff_ticket.gd",
    "scripts/network/handoff/handoff_state_machine.gd",
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
    out = ROOT / "artifacts/a10-r3/exact"
    out.mkdir(parents=True, exist_ok=True)
    result = {"verdict": "FAIL", "subject_head": args.head, "subject_tree": args.tree,
              "parent_r2": PARENT_R2, "parent_tree": PARENT_TREE, "checks": []}
    started = time.monotonic()
    try:
        require(git("rev-parse", "HEAD") == args.head, "EXACT_HEAD")
        require(git("rev-parse", "HEAD^{tree}") == args.tree, "EXACT_TREE")
        require(git("rev-parse", PARENT_R2 + "^{tree}") == PARENT_TREE, "R2_PARENT_TREE")
        require(gp("merge-base", "--is-ancestor", PARENT_R2, args.head).returncode == 0, "R2_NOT_ANCESTOR")
        actual = set()
        for row in git("diff", "--name-status", PARENT_R2, args.head).splitlines():
            cols = row.split("\t")
            require(len(cols) == 2 and cols[0] == "A", "R2_SOURCE_CHANGED:" + row)
            actual.add(cols[1])
        require(actual == ADDITIONS, "A10_R3_ADDITIVE_SCOPE:" + json.dumps(sorted(actual)))
        for path in sorted(IMMUTABLE):
            require(git("rev-parse", f"{PARENT_R2}:{path}") == git("rev-parse", f"{args.head}:{path}"),
                    "IMMUTABLE_SOURCE_CHANGED:" + path)
        result["checks"].append("stacked_additive_scope")

        args.godot = args.godot.resolve(strict=True)
        require(sha256(args.godot) == GODOT_SHA256, "GODOT_SHA256")
        version = subprocess.check_output([str(args.godot), "--version"], text=True).strip()
        require(version == GODOT_VERSION, "GODOT_VERSION:" + version)
        result["godot"] = {"version": version, "sha256": GODOT_SHA256}

        log = out / "seam-binding.log"
        env = dict(os.environ, GODOT_SILENCE_ROOT_WARNING="1")
        cmd = [str(args.godot), "--headless", "--audio-driver", "Dummy", "--path", str(ROOT),
               "--script", "res://validation/ecology/evo_arch2_a10_r3/test_seam_binding.gd"]
        with log.open("wb") as stream:
            proc = subprocess.run(cmd, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT,
                                  timeout=600, check=False)
        text = log.read_text(encoding="utf-8-sig", errors="replace")
        require(proc.returncode == 0, "A10_R3_GODOT_EXIT:" + text[-8000:])
        require("EVO_ARCH2_A10_R3_SEAM_BINDING PASS" in text, "A10_R3_PASS_MARKER:" + text[-8000:])
        require("A10_R3_FAILURE " not in text and "SCRIPT ERROR:" not in text and "Parse Error:" not in text,
                "A10_R3_RUNTIME_ERROR:" + text[-8000:])
        marker = next((line for line in text.splitlines() if line.startswith("EVO_ARCH2_A10_R3_SEAM_BINDING checks=")), "")
        require("failed=0" in marker, "A10_R3_ASSERTIONS:" + marker)
        result["runtime"] = {"marker": marker, "log_sha256": sha256(log), "exit_code": proc.returncode}
        result["checks"].append("real_a8_production_handoff")

        bridge = (ROOT / "scripts/research/ecology/v2/world_seam_binding_v1.gd").read_text(encoding="utf-8")
        require("handoff_state_machine" not in bridge, "A10_R3_PRIVATE_STATE_MACHINE")
        require("Ticket.create" in bridge and "Ticket.validate" in bridge, "A10_R3_PRODUCTION_TICKET_REQUIRED")
        result["checks"].append("no_private_network_owner")

        require(not git("status", "--porcelain", "--untracked-files=no"), "TRACKED_SOURCE_DIRTY")
        result["verdict"] = "PASS"
        print(f"EVO_ARCH2_A10_R3_EXACT verdict=PASS head={args.head} tree={args.tree}")
        return 0
    except Exception as exc:
        result["error"] = str(exc)
        print("A10_R3_EXACT_FAILURE: " + str(exc))
        return 1
    finally:
        result["elapsed_seconds"] = round(time.monotonic() - started, 3)
        (out / "summary.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")

if __name__ == "__main__":
    raise SystemExit(main())
