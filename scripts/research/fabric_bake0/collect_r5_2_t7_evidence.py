#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, statistics
from pathlib import Path

PREFIX="FABRIC_R5_2_T7_RESULT="
PASS="FABRIC R5.2 T7 GEARBOX: PASS"

def canonical_hash(v):
    return hashlib.sha256(json.dumps(v,sort_keys=True,separators=(",",":")).encode()).hexdigest()

def parse_time(path: Path):
    values={}
    for raw in path.read_text(encoding="utf-8",errors="replace").splitlines():
        line=raw.strip()
        if ": " in line:
            k,v=line.rsplit(": ",1); values[k]=v.strip()
    key=next(k for k in values if k.startswith("Elapsed (wall clock) time"))
    p=values[key].split(":")
    elapsed=float(p[-1])
    if len(p)>=2: elapsed+=float(p[-2])*60
    if len(p)>=3: elapsed+=float(p[-3])*3600
    return {"elapsed_s":elapsed,"max_rss_kib":int(values["Maximum resident set size (kbytes)"].replace(",",""))}

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--root",required=True)
    ap.add_argument("--out",required=True)
    args=ap.parse_args()
    root=Path(args.root)
    samples=[]; hashes=set()
    for i in (1,2,3):
        text=(root/f"sample-{i}.log").read_text(encoding="utf-8",errors="replace")
        if PASS not in text: raise ValueError(f"PASS missing sample {i}")
        rows=[x[len(PREFIX):] for x in text.splitlines() if x.startswith(PREFIX)]
        if len(rows)!=1: raise ValueError(f"result row count sample {i}: {len(rows)}")
        d=json.loads(rows[0])
        assert d["source_gears"]==6 and d["source_teeth"]==232 and d["source_components"]==238
        assert d["stages"]==3 and abs(d["total_speed_ratio"]+1/36)<=1e-15
        assert d["source_operations"]==1428 and d["compiled_operations"]==16
        assert d["runtime_source_component_traversals"]==0
        assert d["sequence_ticks"]==2048
        assert d["full_reference_component_traversals"]==238*2048
        assert d["maximum_output_omega_error"]<=1e-12
        assert d["maximum_output_torque_error"]<=1e-9
        assert d["maximum_reflected_inertia_error"]<=1e-12
        assert d["maximum_energy_residual_j"]<=1e-12
        assert d["reverse_power_seen"] is True
        assert d["disabled_tooth_error"]=="GEARBOX_TOOTH_DISABLED"
        assert d["module_mismatch_error"]=="GEARBOX_MESH_MODULE_MISMATCH"
        assert d["descriptor_relation_error"]=="GEARBOX_DESCRIPTOR_OUTPUT_TORQUE_MISMATCH"
        assert d["composition_max_ratio_error"]<=1e-12
        assert d["composition_max_power_error"]<=1e-12
        assert d["composition_torque_gain_seen"] is True
        assert 0.0 < d["coupled_acceleration_ratio"] < 1.0
        hashes.add(canonical_hash(d))
        samples.append({"sample":i,"deterministic":d,"process":parse_time(root/f"sample-{i}.time.txt")})
    if len(hashes)!=1: raise ValueError("T7_DETERMINISM_MISMATCH")
    elapsed=[s["process"]["elapsed_s"] for s in samples]
    rss=[s["process"]["max_rss_kib"] for s in samples]
    result={
        "schema":"planet_simulator.fabric_r5_2_t7_evidence.v1",
        "sample_count":3,
        "deterministic_hash":next(iter(hashes)),
        "claims":samples[0]["deterministic"],
        "observations":{
            "process_elapsed_s":{"min":min(elapsed),"median":statistics.median(elapsed),"max":max(elapsed)},
            "process_max_rss_kib":{"min":min(rss),"median":int(statistics.median(rss)),"max":max(rss)},
        },
        "samples":samples,
        "policy":{
            "timing_is_acceptance_threshold":False,
            "lossless_rigid_gear_floor":True,
            "tribology_loss_claimed":False,
            "runtime_source_traversal_zero":True,
            "t5_composition_is_acceptance_semantics":True,
        }
    }
    result["evidence_hash"]=canonical_hash(result)
    out=Path(args.out); out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(result,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    print("FABRIC_R5_2_T7_DETERMINISTIC_HASH="+result["deterministic_hash"])
    print("FABRIC_R5_2_T7_EVIDENCE_HASH="+result["evidence_hash"])
    print("FABRIC_R5_2_T7_EVIDENCE=PASS")

if __name__=="__main__":
    main()
