#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, statistics
from pathlib import Path

PREFIX="FABRIC_R5_2_T8_RESULT="
PASS="FABRIC R5.2 T8 COOLING: PASS"

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
        assert d["lanes"]==64 and d["source_thermal_nodes"]==256 and d["state_scalars"]==4
        assert d["source_operations"]==1536 and d["compiled_operations"]==32
        assert d["runtime_source_thermal_node_traversals"]==0
        assert d["sequence_ticks"]==2048
        assert d["full_reference_thermal_node_traversals"]==256*2048
        for key in [
            "maximum_plate_temperature_error","maximum_hot_coolant_temperature_error",
            "maximum_cold_coolant_temperature_error","maximum_radiator_temperature_error",
            "maximum_state_parity_error","maximum_ambient_exchange_error_j","maximum_pump_energy_error_j"
        ]:
            assert d[key] <= 1e-9
        assert d["maximum_energy_residual_j"] <= 1e-8
        assert d["glycol_pump_energy_ratio"] > 3.0
        assert d["asymmetric_lane_error"]=="COOLING_LANE_SYMMETRY_BROKEN"
        assert d["asymmetric_detailed_reference_executes"] is True
        assert d["disabled_lane_error"]=="COOLING_LANE_DISABLED"
        assert d["off_manifold_error"]=="COOLING_STATE_NOT_IN_REDUCTION_MANIFOLD"
        assert d["nonfinite_projection_error"]=="COOLING_STATE_PROJECTOR_STATE_INVALID"
        assert d["nonfinite_reference_error"]=="COOLING_REFERENCE_STATE_INVALID"
        assert d["out_of_domain_projection_error"]=="COOLING_STATE_PROJECTOR_TEMPERATURE_OUT_OF_DOMAIN"
        assert d["out_of_domain_reference_error"]=="COOLING_REFERENCE_TEMPERATURE_OUT_OF_DOMAIN"
        assert d["descriptor_relation_error"]=="COOLING_LOOP_DESCRIPTOR_MAX_FLOW_RELATION_MISMATCH"
        assert d["flow_regime_descriptor_error"]=="COOLING_LOOP_DESCRIPTOR_FLOW_REGIME_UNSUPPORTED"
        assert d["t6_cooling_temperature_advantage_k"] > 0.10
        assert d["t6_composition_heat_j"] > 0.0
        assert d["t6_composition_pump_hydraulic_energy_j"] > 0.0
        hashes.add(canonical_hash(d))
        samples.append({"sample":i,"deterministic":d,"process":parse_time(root/f"sample-{i}.time.txt")})
    if len(hashes)!=1: raise ValueError("T8_DETERMINISM_MISMATCH")
    elapsed=[s["process"]["elapsed_s"] for s in samples]
    rss=[s["process"]["max_rss_kib"] for s in samples]
    result={
        "schema":"planet_simulator.fabric_r5_2_t8_evidence.v1",
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
            "coolant_viscosity_is_characterized_floor":True,
            "hydraulic_power_is_geometry_derived":True,
            "pump_electrical_efficiency_claimed":False,
            "runtime_source_traversal_zero":True,
            "t6_heat_composition_is_acceptance_semantics":True,
        }
    }
    result["evidence_hash"]=canonical_hash(result)
    out=Path(args.out); out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(result,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    print("FABRIC_R5_2_T8_DETERMINISTIC_HASH="+result["deterministic_hash"])
    print("FABRIC_R5_2_T8_EVIDENCE_HASH="+result["evidence_hash"])
    print("FABRIC_R5_2_T8_EVIDENCE=PASS")

if __name__=="__main__":
    main()
