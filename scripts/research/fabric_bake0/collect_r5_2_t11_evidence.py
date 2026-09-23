#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, statistics
from pathlib import Path

PREFIX="FABRIC_R5_2_T11_RESULT="
PASS="FABRIC R5.2 T11 SMART SERVO: PASS"

def ch(v): return hashlib.sha256(json.dumps(v,sort_keys=True,separators=(",",":")).encode()).hexdigest()

def pt(path):
    d={}
    for raw in path.read_text(encoding="utf-8",errors="replace").splitlines():
        line=raw.strip()
        if ": " in line:
            k,v=line.rsplit(": ",1);d[k]=v.strip()
    key=next(k for k in d if k.startswith("Elapsed (wall clock) time"))
    p=d[key].split(":");e=float(p[-1])
    if len(p)>=2:e+=float(p[-2])*60
    if len(p)>=3:e+=float(p[-3])*3600
    return {"elapsed_s":e,"max_rss_kib":int(d["Maximum resident set size (kbytes)"].replace(",",""))}

def main():
    ap=argparse.ArgumentParser();ap.add_argument("--root",required=True);ap.add_argument("--out",required=True)
    a=ap.parse_args();root=Path(a.root);samples=[];hashes=set()
    for i in (1,2,3):
        text=(root/f"sample-{i}.log").read_text(encoding="utf-8",errors="replace")
        if PASS not in text:raise ValueError(f"PASS missing sample {i}")
        rows=[x[len(PREFIX):] for x in text.splitlines() if x.startswith(PREFIX)]
        if len(rows)!=1:raise ValueError(f"result row count sample {i}")
        d=json.loads(rows[0])
        assert d["leaf_source_components"]==495
        assert d["leaf_source_operations"]==2846
        assert d["compiled_operations"]==24
        assert d["runtime_source_component_traversals"]==0
        assert abs(d["gear_ratio"]+1/36)<=1e-15
        assert d["sequence_ticks"]==4096
        assert d["maximum_current_command_error_a"]==0.0
        assert d["maximum_terminal_voltage_error_v"]<=1e-12
        assert d["maximum_position_state_error_rad"]<=1e-12
        assert d["maximum_velocity_state_error_rad_s"]<=1e-12
        assert d["maximum_energy_residual_j"]<=1e-10
        assert d["saturation_seen"] is True and d["settled_seen"] is True
        assert 0.0<d["coupled_to_bare_acceleration_ratio"]<1.0
        assert d["light_gearbox_acceleration_ratio"]>1.0
        assert d["snapshot_replay_error"]==0.0
        assert d["descriptor_inertia_relation_error"]=="SMART_SERVO_DESCRIPTOR_INERTIA_RELATION_MISMATCH"
        assert d["child_descriptor_binding_error"]=="SMART_SERVO_GEARBOX_DESCRIPTOR_BINDING_MISMATCH"
        hashes.add(ch(d));samples.append({"sample":i,"deterministic":d,"process":pt(root/f"sample-{i}.time.txt")})
    if len(hashes)!=1:raise ValueError("T11_DETERMINISM_MISMATCH")
    es=[s["process"]["elapsed_s"] for s in samples];rs=[s["process"]["max_rss_kib"] for s in samples]
    result={
        "schema":"planet_simulator.fabric_r5_2_t11_evidence.v1",
        "sample_count":3,"deterministic_hash":next(iter(hashes)),
        "claims":samples[0]["deterministic"],
        "observations":{
            "process_elapsed_s":{"min":min(es),"median":statistics.median(es),"max":max(es)},
            "process_max_rss_kib":{"min":min(rs),"median":int(statistics.median(rs)),"max":max(rs)},
        },
        "samples":samples,
        "policy":{
            "timing_is_acceptance_threshold":False,
            "ideal_current_source_boundary":True,
            "power_stage_dynamics_claimed":False,
            "gearbox_reflected_inertia_in_coupled_solver":True,
            "caller_owned_state_only":True,
        }
    }
    result["evidence_hash"]=ch(result)
    out=Path(a.out);out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(result,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    print("FABRIC_R5_2_T11_DETERMINISTIC_HASH="+result["deterministic_hash"])
    print("FABRIC_R5_2_T11_EVIDENCE_HASH="+result["evidence_hash"])
    print("FABRIC_R5_2_T11_EVIDENCE=PASS")

if __name__=="__main__":main()
