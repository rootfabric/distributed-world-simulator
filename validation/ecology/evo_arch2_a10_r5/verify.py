#!/usr/bin/env python3
"""Whole-stack exact runtime verifier for EVO ARCH2 A10 R5."""
from __future__ import annotations
import argparse, hashlib, json, os, subprocess, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PARENT_R4 = "ef5a9ecccdc403631d11c2cebe0b95d8971243bf"
PARENT_TREE = "a2cd902fff7375f611fe5f1889d3111619da41d3"
GODOT_VERSION = "4.7.1.stable.double.custom_build.a13da4feb"
GODOT_SHA256 = "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"

ADDITIONS = {
    "config/ecology/evo-arch2-a10-r5-work-order.v1.json",
    "docs/research/ecology/EVO_ARCH2_A10_R5_FINAL_COMPOSITION_RU.md",
    "validation/ecology/evo_arch2_a10_r5/test_final_composition.gd",
    "validation/ecology/evo_arch2_a10_r5/verify.py",
    ".github/workflows/eco-evo-arch2-a10-r5-exact.yml",
}
IMMUTABLE = {
    "scripts/research/ecology/v2/world_binding_v1.gd",
    "scripts/research/ecology/v2/matter_resource_mapping_v1.gd",
    "scripts/research/ecology/v2/world_seam_binding_v1.gd",
    "scripts/research/ecology/v2/body_construction_binding_v1.gd",
    "scripts/research/ecology/v2/snapshot_seam_v1.gd",
}
RUNTIME_TESTS = [
    ("r1-world-binding", "res://validation/ecology/evo_arch2_a10/test_world_binding.gd", "EVO_ARCH2_A10_WORLD_BINDING PASS"),
    ("r2-resource-mapping", "res://validation/ecology/evo_arch2_a10_r2/test_resource_mapping.gd", "EVO_ARCH2_A10_R2_RESOURCE_MAPPING PASS"),
    ("r3-seam-binding", "res://validation/ecology/evo_arch2_a10_r3/test_seam_binding.gd", "EVO_ARCH2_A10_R3_SEAM_BINDING PASS"),
    ("r4-damage-overlay", "res://validation/ecology/evo_arch2_a10_r4/test_body_damage_overlay.gd", "EVO_ARCH2_A10_R4_DAMAGE_OVERLAY PASS"),
    ("r5-final-composition", "res://validation/ecology/evo_arch2_a10_r5/test_final_composition.gd", "EVO_ARCH2_A10_R5_FINAL_COMPOSITION PASS"),
]

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
    out = ROOT / "artifacts/a10-r5/exact"
    out.mkdir(parents=True, exist_ok=True)
    result = {"verdict":"FAIL","subject_head":args.head,"subject_tree":args.tree,
              "parent_r4":PARENT_R4,"parent_tree":PARENT_TREE,"runtime":[]}
    started=time.monotonic()
    try:
        require(git("rev-parse","HEAD")==args.head,"EXACT_HEAD")
        require(git("rev-parse","HEAD^{tree}")==args.tree,"EXACT_TREE")
        require(git("rev-parse",PARENT_R4+"^{tree}")==PARENT_TREE,"R4_PARENT_TREE")
        require(gp("merge-base","--is-ancestor",PARENT_R4,args.head).returncode==0,"R4_NOT_ANCESTOR")
        actual=set()
        for row in git("diff","--name-status",PARENT_R4,args.head).splitlines():
            cols=row.split("\t"); require(len(cols)==2 and cols[0]=="A","R4_SOURCE_CHANGED:"+row); actual.add(cols[1])
        require(actual==ADDITIONS,"A10_R5_ADDITIVE_SCOPE:"+json.dumps(sorted(actual)))
        for path in sorted(IMMUTABLE):
            require(git("rev-parse",f"{PARENT_R4}:{path}")==git("rev-parse",f"{args.head}:{path}"),
                    "A10_LAYER_SOURCE_CHANGED:"+path)

        args.godot=args.godot.resolve(strict=True)
        require(sha256(args.godot)==GODOT_SHA256,"GODOT_SHA256")
        version=subprocess.check_output([str(args.godot),"--version"],text=True).strip()
        require(version==GODOT_VERSION,"GODOT_VERSION:"+version)
        env=dict(os.environ,GODOT_SILENCE_ROOT_WARNING="1")

        for name, script, marker in RUNTIME_TESTS:
            log=out/(name+".log")
            cmd=[str(args.godot),"--headless","--audio-driver","Dummy","--path",str(ROOT),"--script",script]
            with log.open("wb") as stream:
                proc=subprocess.run(cmd,cwd=ROOT,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=600,check=False)
            text=log.read_text(encoding="utf-8-sig",errors="replace")
            require(proc.returncode==0,name+"_EXIT:"+text[-8000:])
            require(marker in text,name+"_MARKER:"+text[-8000:])
            require("SCRIPT ERROR:" not in text and "Parse Error:" not in text and "A10_" not in "\n".join(
                line for line in text.splitlines() if "_FAIL " in line or "_FAILURE " in line
            ), name+"_ERROR:"+text[-8000:])
            result["runtime"].append({"name":name,"exit_code":proc.returncode,"log_sha256":sha256(log)})
            print("PASS "+name,flush=True)

        require(not git("status","--porcelain","--untracked-files=no"),"TRACKED_SOURCE_DIRTY")
        result["verdict"]="PASS"
        print(f"EVO_ARCH2_A10_R5_EXACT verdict=PASS head={args.head} tree={args.tree}",flush=True)
        return 0
    except Exception as exc:
        result["error"]=str(exc); print("A10_R5_EXACT_FAILURE: "+str(exc),flush=True); return 1
    finally:
        result["elapsed_seconds"]=round(time.monotonic()-started,3)
        (out/"summary.json").write_text(json.dumps(result,indent=2)+"\n",encoding="utf-8")

if __name__=="__main__":
    raise SystemExit(main())
