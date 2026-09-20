#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, statistics
from pathlib import Path

PREFIX="FABRIC_R5_2_T3_RESULT="
PASS="FABRIC R5.2 T3 BATTERY CELLS MATERIALS: PASS"
STAGES=[
 "base_compile","runtime_prepare","full_vs_capsule_sequence",
 "full_reference_hot_loop","capsule_hot_loop","material_variant_compile",
 "quality_variant_compile","damage_recompile","mixed_parallel_fail_closed",
 "unsafe_geometry_fail_closed","open_group_fail_closed",
]

def canonical_hash(v):
    return hashlib.sha256(json.dumps(v,sort_keys=True,separators=(",",":")).encode()).hexdigest()

def parse_time(path: Path):
    values={}
    for raw in path.read_text(encoding="utf-8",errors="replace").splitlines():
        line=raw.strip()
        if ": " in line:
            k,v=line.rsplit(": ",1); values[k]=v.strip()
    elapsed_key=next(k for k in values if k.startswith("Elapsed (wall clock) time"))
    p=values[elapsed_key].split(":")
    elapsed=float(p[-1])+(float(p[-2])*60 if len(p)>=2 else 0)+(float(p[-3])*3600 if len(p)>=3 else 0)
    return {"elapsed_s":elapsed,"max_rss_kb":int(values["Maximum resident set size (kbytes)"].replace(",",""))}

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--root",required=True); ap.add_argument("--out",required=True)
    args=ap.parse_args(); root=Path(args.root)
    samples=[]; hashes=set(); payloads=set()
    for i in (1,2,3):
        text=(root/f"sample-{i}.log").read_text(encoding="utf-8",errors="replace")
        if PASS not in text: raise ValueError(f"PASS missing sample {i}")
        rows=[x[len(PREFIX):] for x in text.splitlines() if x.startswith(PREFIX)]
        if len(rows)!=1: raise ValueError(f"result row count sample {i}: {len(rows)}")
        data=json.loads(rows[0]); c=data["counters"]
        assert c["source_cells"]==96 and c["active_cells"]==96
        assert c["series_groups"]==12 and c["state_scalars"]==13
        assert c["sequence_ticks"]==2048
        assert c["full_reference_cell_traversals"]==2048*96
        assert c["runtime_source_cell_traversals_per_execute"]==0
        assert c["full_hot_calls"]==4096 and c["capsule_hot_calls"]==32768
        for stage in STAGES:
            if stage not in data["stages"]: raise ValueError(f"missing stage {stage}")
        hashes.add(data["deterministic_hash"]); payloads.add(canonical_hash(data["deterministic"]))
        samples.append({"sample":i,"result":data,"process":parse_time(root/f"sample-{i}.time.txt")})
    if len(hashes)!=1 or len(payloads)!=1: raise ValueError("T3_DETERMINISM_MISMATCH")
    stage={}
    for name in STAGES:
        vals=[int(s["result"]["stages"][name]["duration_us"]) for s in samples]
        stage[name]={"min":min(vals),"median":int(statistics.median(vals)),"max":max(vals)}
    d=samples[0]["result"]["deterministic"]
    full_per=stage["full_reference_hot_loop"]["median"]/4096.0
    capsule_per=stage["capsule_hot_loop"]["median"]/32768.0
    elapsed=[s["process"]["elapsed_s"] for s in samples]; rss=[s["process"]["max_rss_kb"] for s in samples]
    result={
      "schema":"planet_simulator.fabric_r5_2_t3_evidence.v1",
      "sample_count":3,
      "deterministic_hash":next(iter(hashes)),
      "deterministic_payload_sha256":next(iter(payloads)),
      "claims":{
        "source_cells":96,
        "active_cells":96,
        "series_groups":12,
        "state_scalars":13,
        "sequence_ticks":2048,
        "full_reference_cell_traversals":2048*96,
        "runtime_source_cell_traversals_per_execute":0,
        "maximum_voltage_error":d["maximum_voltage_error"],
        "maximum_heat_error":d["maximum_heat_error"],
        "maximum_charge_state_error":d["maximum_charge_state_error"],
        "maximum_temperature_error":d["maximum_temperature_error"],
        "maximum_energy_residual_j":d["maximum_energy_residual_j"],
        "damage_active_cells":d["damage_active_cells"],
        "mixed_error":d["mixed_error"],
        "unsafe_geometry_error":d["unsafe_geometry_error"],
        "open_group_error":d["open_group_error"],
      },
      "observations":{
        "stage_us":stage,
        "full_reference_us_per_call":full_per,
        "capsule_us_per_call":capsule_per,
        "observed_speedup":full_per/max(capsule_per,1e-12),
        "process_elapsed_s":{"min":min(elapsed),"median":statistics.median(elapsed),"max":max(elapsed)},
        "process_max_rss_kb":{"min":min(rss),"median":int(statistics.median(rss)),"max":max(rss)},
      },
      "samples":samples,
      "policy":{
        "timing_is_acceptance_threshold":False,
        "speedup_is_acceptance_threshold":False,
        "cell_material_properties_are_derived":True,
        "runtime_owns_persistent_state":False,
        "atom_level_chemistry_claimed":False,
      }
    }
    result["evidence_hash"]=canonical_hash(result)
    out=Path(args.out); out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(result,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    print("FABRIC_R5_2_T3_EVIDENCE_HASH="+result["evidence_hash"])
    print("FABRIC_R5_2_T3_DETERMINISTIC_HASH="+result["deterministic_hash"])
    print("FABRIC_R5_2_T3_EVIDENCE=PASS")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
