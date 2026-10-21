#!/usr/bin/env python3
"""Paired R31b P1 ON/OFF long-gap summary: both arms have R31a + P0 ON.

This is DIFFERENT from historical R31a diagnose_r31_long_gaps.py where
OFF meant replay cache disabled. No process-local cross-machine clock joins.
Uses its proven per-role trace reader, not a new normative analyzer.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path

from diagnose_r31_long_gaps import role_metrics


def read_arm(root:Path, *, enabled:bool)->dict:
    manifest=json.loads((root/"manifest.json").read_text(encoding="utf-8"))
    if (
        manifest.get("mode")!="gui" or manifest.get("profile")!="LOCAL"
        or manifest.get("scenario")!="r31-reconnect-roundtrip"
        or manifest.get("completed") is not True or manifest.get("errors")
        or float(manifest.get("duration_s",0))<120
    ):
        raise ValueError("P1_INVALID_GUI_MANIFEST: "+str(root))
    for key in ("r3c4r31_replay_projection","r3c4r31b_durable_attribution",
                "r3c4r2_worker_envelope","r3c4_periodic_frame_pacing"):
        if manifest.get(key) is not True:
            raise ValueError("P1_MISSING_COMMON_FLAG_"+key)
    if manifest.get("r31bp1_durable_chunks") is not enabled:
        raise ValueError("P1_WRONG_OPT_IN_ARM: "+str(root))
    ident=manifest.get("identity",{})
    if not isinstance(ident,dict) or ident.get("tracked_dirty") is not False:
        raise ValueError("P1_TRACKED_WORKTREE_DIRTY")
    if ident.get("asset_count",0)<120:
        raise ValueError("P1_QUATERNIUS_ASSET_COVERAGE_MISSING")
    return {
        "root":str(root), "identity":ident,
        "roles":{role:role_metrics(root,role) for role in ("server","a","b")},
    }


def compare(pairs:list[tuple[Path,Path]])->dict:
    if len(pairs)!=3:
        raise ValueError("P1_NEEDS_THREE_MATCHED_PAIRS")
    results=[]
    first_identity=None
    for n,(off_root,on_root) in enumerate(pairs,1):
        off=read_arm(off_root,enabled=False)
        on=read_arm(on_root,enabled=True)
        required=("head","tree","godot_sha256","asset_manifest_sha256","asset_count")
        for k in required:
            x=off["identity"].get(k)
            if not x or x!=on["identity"].get(k):
                raise ValueError(f"P1_PAIR_{n}_{k}_MISMATCH")
            if first_identity is not None and x!=first_identity[k]:
                raise ValueError(f"P1_ACROSS_PAIR_{k}_DRIFT")
        first_identity=off["identity"] if first_identity is None else first_identity
        results.append({"pair":n,"off":off,"on":on})
    def coll(arm,role,field):
        return [rec[arm]["roles"][role][field] for rec in results]
    return {
        "schema":"dws.net_smooth.r31bp1.paired_gap_comparison.v1",
        "verdict":"PAIRED_GAP_DIAGNOSTIC_ONLY",
        "head":first_identity["head"],"tree":first_identity["tree"],
        "engine_sha256":first_identity["godot_sha256"],
        "assets_sha256":first_identity["asset_manifest_sha256"],
        "arm_summary":{
            arm:{
                role:{
                    "frame_gap_over_100ms":coll(arm,role,"gaps_over_100ms"),
                    "frame_max_ms":coll(arm,role,"max_gap_ms"),
                    "frame_p99_ms":coll(arm,role,"p99_gap_ms"),
                    "server_loop_gaps_over_100ms":coll(arm,role,"server_loop_gaps_over_100ms"),
                    "server_process_p99_ms":coll(arm,role,"server_process_p99_ms"),
                } for role in ("server","a","b")
            } for arm in ("off","on")
        },
        "pairs":results,
        "notes":[
            "R31b P0 attribution and R31a replay cache are enabled in BOTH arms",
            "OFF means P1 durable chunks disabled, NOT replay cache disabled",
            "Unmodified normative analyzer owns PASS/FAIL; this report is diagnostic only",
            "Process-local clock associations cannot prove host root cause",
            "New or unexplained >100ms gaps block merge even when p99 improves",
        ],
    }


def main()->int:
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--pair",nargs=2,action="append",required=True,
                   metavar=("P1_OFF","P1_ON"),type=Path)
    p.add_argument("--output",type=Path,required=True)
    a=p.parse_args()
    try:
        output=compare(a.pair)
    except (ValueError,TypeError,OSError,KeyError,json.JSONDecodeError) as exc:
        print("P1_GAP_INCONCLUSIVE: "+str(exc))
        return 2
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(output,ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps({"verdict":output["verdict"],"arms":output["arm_summary"]}))
    return 0


if __name__=="__main__":
    raise SystemExit(main())
