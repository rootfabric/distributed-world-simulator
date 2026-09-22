#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, statistics
from pathlib import Path

PREFIX="FABRIC_R5_2_T10_RESULT="
PASS="FABRIC R5.2 T10 LASER CANNON: PASS"

def canonical_hash(v):
    return hashlib.sha256(json.dumps(v,sort_keys=True,separators=(",",":")).encode()).hexdigest()

def parse_time(path:Path):
    values={}
    for raw in path.read_text(encoding="utf-8",errors="replace").splitlines():
        line=raw.strip()
        if ": " in line:
            k,v=line.rsplit(": ",1);values[k]=v.strip()
    key=next(k for k in values if k.startswith("Elapsed (wall clock) time"))
    p=values[key].split(":");elapsed=float(p[-1])
    if len(p)>=2:elapsed+=float(p[-2])*60
    if len(p)>=3:elapsed+=float(p[-3])*3600
    return {"elapsed_s":elapsed,"max_rss_kib":int(values["Maximum resident set size (kbytes)"].replace(",",""))}

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--root",required=True);ap.add_argument("--out",required=True)
    args=ap.parse_args();root=Path(args.root)
    samples=[];hashes=set()
    for i in (1,2,3):
        text=(root/f"sample-{i}.log").read_text(encoding="utf-8",errors="replace")
        if PASS not in text:raise ValueError(f"PASS missing sample {i}")
        rows=[x[len(PREFIX):] for x in text.splitlines() if x.startswith(PREFIX)]
        if len(rows)!=1:raise ValueError(f"result row count sample {i}: {len(rows)}")
        d=json.loads(rows[0])
        assert d["leaf_source_components"]==642
        assert d["leaf_source_operations"]==3848
        assert d["assembly_operations"]==24
        assert d["runtime_source_component_traversals"]==0
        assert d["optical_expansion_ratio"]==4.0
        assert 0.0<d["optics_total_transmission_ratio"]<1.0
        assert d["sequence_ticks"]==2048
        assert d["maximum_manual_muzzle_error_j"]<=1e-12
        assert d["maximum_manual_heat_error_j"]<=1e-12
        assert d["maximum_manual_spot_radius_error_m"]<=1e-12
        assert d["maximum_manual_state_error_k"]<=1e-12
        assert d["maximum_whole_energy_residual_j"]<=1e-8
        assert d["total_muzzle_optical_energy_j"]>0.0
        assert d["total_pump_hydraulic_energy_j"]>0.0
        assert d["max_plate_temperature_k"]>300.0
        assert abs(d["divergence_ratio_vs_bare_emitter"]-0.25)<=1e-12
        assert 0.0<d["lossy_optics_muzzle_ratio"]<1.0
        assert d["clipped_geometry_error"]=="LASER_CANNON_INPUT_APERTURE_CLIPS_EMITTER"
        assert d["fluence_limit_error"]=="LASER_CANNON_RUNTIME_OPTICS_FLUENCE_LIMIT"
        assert d["snapshot_replay_error"]==0.0
        assert d["descriptor_relation_error"]=="LASER_CANNON_DESCRIPTOR_TRANSMISSION_RELATION_MISMATCH"
        hashes.add(canonical_hash(d))
        samples.append({"sample":i,"deterministic":d,"process":parse_time(root/f"sample-{i}.time.txt")})
    if len(hashes)!=1:raise ValueError("T10_DETERMINISM_MISMATCH")
    elapsed=[s["process"]["elapsed_s"] for s in samples];rss=[s["process"]["max_rss_kib"] for s in samples]
    result={
        "schema":"planet_simulator.fabric_r5_2_t10_evidence.v1",
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
            "target_damage_model_claimed":False,
            "free_space_atmosphere_claimed":False,
            "hierarchical_subcapsules_are_not_reexpanded":True,
            "caller_owned_state_only":True,
        }
    }
    result["evidence_hash"]=canonical_hash(result)
    out=Path(args.out);out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(result,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    print("FABRIC_R5_2_T10_DETERMINISTIC_HASH="+result["deterministic_hash"])
    print("FABRIC_R5_2_T10_EVIDENCE_HASH="+result["evidence_hash"])
    print("FABRIC_R5_2_T10_EVIDENCE=PASS")

if __name__=="__main__":
    main()
