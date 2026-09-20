#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, statistics
from pathlib import Path

PREFIX="FABRIC_R5_2_T1_RESULT="
PASS="FABRIC R5.2 T1 BOUNDARY NETWORK CAPSULE: PASS"
STAGES=[
 "component_graph_to_linear_system",
 "behavior_capsule_compile",
 "full_reference_excitation_batch",
 "capsule_excitation_batch",
 "prepared_session_start",\n "full_gate_hot_loop",\n "prepared_capsule_hot_loop",
 "mutation_recompile",
 "singular_fail_closed",
]

def parse_time(path: Path):
    values={}
    for raw in path.read_text(encoding="utf-8",errors="replace").splitlines():
        line=raw.strip()
        if ": " in line:
            k,v=line.rsplit(": ",1); values[k]=v.strip()
    elapsed_key=next(k for k in values if k.startswith("Elapsed (wall clock) time"))
    p=values[elapsed_key].split(":")
    elapsed=float(p[-1]) + (float(p[-2])*60 if len(p)>=2 else 0) + (float(p[-3])*3600 if len(p)>=3 else 0)
    return {"elapsed_s":elapsed,"max_rss_kb":int(values["Maximum resident set size (kbytes)"].replace(",",""))}

def canonical_hash(v):
    return hashlib.sha256(json.dumps(v,sort_keys=True,separators=(",",":")).encode()).hexdigest()

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--root",required=True); ap.add_argument("--out",required=True)
    args=ap.parse_args(); root=Path(args.root)
    samples=[]; deterministic=set(); payloads=set()
    for i in (1,2,3):
        text=(root/f"sample-{i}.log").read_text(encoding="utf-8",errors="replace")
        if PASS not in text: raise ValueError(f"PASS missing sample {i}")
        rows=[x[len(PREFIX):] for x in text.splitlines() if x.startswith(PREFIX)]
        if len(rows)!=1: raise ValueError(f"result row count sample {i}: {len(rows)}")
        data=json.loads(rows[0])
        counters=data["counters"]
        if counters["source_components"] < 500: raise ValueError("T1_COMPONENT_COMPLEXITY_TOO_LOW")
        if counters["internal_nodes"] != 128 or counters["boundary_ports"] != 4: raise ValueError("T1_TOPOLOGY_DRIFT")
        if counters["full_equations"] != 132 or counters["executable_equations"] != 4: raise ValueError("T1_EQUATION_DRIFT")
        if counters["runtime_source_traversals_per_execute"] != 0: raise ValueError("T1_RUNTIME_SOURCE_TRAVERSAL_PRESENT")
        if counters["full_gate_hot_loop_calls"] != 128: raise ValueError("T1_FULL_GATE_LOOP_DRIFT")\n        if counters["prepared_hot_loop_calls"] != 4096: raise ValueError("T1_PREPARED_LOOP_DRIFT")
        for s in STAGES:
            if s not in data["stages"]: raise ValueError(f"T1_STAGE_MISSING {s}")
        deterministic.add(data["deterministic_hash"])
        payloads.add(canonical_hash(data["deterministic"]))
        samples.append({"sample":i,"result":data,"process":parse_time(root/f"sample-{i}.time.txt")})
    if len(deterministic)!=1 or len(payloads)!=1: raise ValueError("T1_DETERMINISM_MISMATCH")
    stage_summary={}
    for s in STAGES:
        vals=[int(x["result"]["stages"][s]["duration_us"]) for x in samples]
        stage_summary[s]={"min":min(vals),"median":int(statistics.median(vals)),"max":max(vals)}
    elapsed=[x["process"]["elapsed_s"] for x in samples]
    rss=[x["process"]["max_rss_kb"] for x in samples]
    d=samples[0]["result"]["deterministic"]
    result={
      "schema":"planet_simulator.fabric_r5_2_t1_evidence.v1",
      "sample_count":3,
      "deterministic_hash":next(iter(deterministic)),
      "deterministic_payload_sha256":next(iter(payloads)),
      "claims":{
        "source_component_count":d["source_component_count"],
        "internal_node_count":d["internal_node_count"],
        "boundary_port_count":d["boundary_port_count"],
        "full_equation_count":d["full_equation_count"],
        "executable_equation_count":d["executable_equation_count"],
        "equation_compression_ratio":d["equation_compression_ratio"],
        "component_to_executable_ratio":d["component_to_executable_ratio"],
        "runtime_source_traversals_per_execute":0,
        "maximum_flow_error":d["maximum_flow_error"],
        "maximum_power_error":d["maximum_power_error"],
        "singular_status":d["singular_status"],
        "singular_reason":d["singular_reason"],
      },
      "observations":{
        "stage_us":stage_summary,
        "elapsed_s":{"min":min(elapsed),"median":statistics.median(elapsed),"max":max(elapsed)},
        "max_rss_kb":{"min":min(rss),"median":int(statistics.median(rss)),"max":max(rss)},
      },
      "samples":samples,
      "policy":{
        "timing_is_acceptance_threshold":False,
        "device_specific_kernel":False,
        "canonical_truth_owner":"Construction/Matter",
        "capsule_is_derived":True,
      }
    }
    result["evidence_hash"]=canonical_hash(result)
    out=Path(args.out); out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(result,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    print("FABRIC_R5_2_T1_EVIDENCE_HASH="+result["evidence_hash"])
    print("FABRIC_R5_2_T1_DETERMINISTIC_HASH="+result["deterministic_hash"])
    print("FABRIC_R5_2_T1_EVIDENCE=PASS")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
