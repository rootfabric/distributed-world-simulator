#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, statistics
from pathlib import Path

PREFIX="FABRIC_R5_2_T2_RESULT="
PASS="FABRIC R5.2 T2 LOGIC ADDER COUNTER: PASS"
STAGES=[
 "adder_compile","counter_compile","runtime_prepare",
 "adder_exhaustive_capsule","counter_exhaustive_capsule","counter_sequence",
 "adder_interpreter_hot_loop","adder_lookup_hot_loop",
 "counter_interpreter_hot_loop","counter_lookup_hot_loop",
 "mutation_recompile","cycle_fail_closed","oversize_fail_closed",
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
        assert c["adder_source_components"]==40
        assert c["counter_source_components"]==32
        assert c["adder_lut_entries"]==131072
        assert c["counter_lut_entries"]==1024
        assert c["adder_exhaustive_cases"]==131072
        assert c["counter_exhaustive_cases"]==1024
        assert c["counter_sequence_ticks"]==2048
        assert c["runtime_source_traversals_per_execute"]==0
        assert c["interpreter_hot_calls"]==4096
        assert c["lookup_hot_calls"]==65536
        for stage in STAGES:
            if stage not in data["stages"]: raise ValueError(f"missing stage {stage}")
        hashes.add(data["deterministic_hash"]); payloads.add(canonical_hash(data["deterministic"]))
        samples.append({"sample":i,"result":data,"process":parse_time(root/f"sample-{i}.time.txt")})
    if len(hashes)!=1 or len(payloads)!=1: raise ValueError("T2_DETERMINISM_MISMATCH")
    stage={}
    for name in STAGES:
        vals=[int(s["result"]["stages"][name]["duration_us"]) for s in samples]
        stage[name]={"min":min(vals),"median":int(statistics.median(vals)),"max":max(vals)}
    d=samples[0]["result"]["deterministic"]
    adder_interpreter_per=stage["adder_interpreter_hot_loop"]["median"]/4096.0
    adder_lookup_per=stage["adder_lookup_hot_loop"]["median"]/65536.0
    counter_interpreter_per=stage["counter_interpreter_hot_loop"]["median"]/4096.0
    counter_lookup_per=stage["counter_lookup_hot_loop"]["median"]/65536.0
    elapsed=[s["process"]["elapsed_s"] for s in samples]; rss=[s["process"]["max_rss_kb"] for s in samples]
    result={
      "schema":"planet_simulator.fabric_r5_2_t2_evidence.v1",
      "sample_count":3,
      "deterministic_hash":next(iter(hashes)),
      "deterministic_payload_sha256":next(iter(payloads)),
      "claims":{
        "adder_source_components":40,
        "counter_source_components":32,
        "adder_lut_entries":131072,
        "counter_lut_entries":1024,
        "adder_lookup_bytes":d["adder_lookup_bytes"],
        "counter_lookup_bytes":d["counter_lookup_bytes"],
        "adder_exhaustive_cases":131072,
        "counter_exhaustive_cases":1024,
        "counter_sequence_ticks":2048,
        "runtime_source_traversals_per_execute":0,
        "compiled_operations":3,
        "counter_event_order":d["counter_event_order"],
        "mutation_changed_lookup":d["mutation_changed_lookup"],
        "cycle_error":d["cycle_error"],
        "oversize_error":d["oversize_error"],
      },
      "observations":{
        "stage_us":stage,
        "adder_interpreter_us_per_call":adder_interpreter_per,
        "adder_lookup_us_per_call":adder_lookup_per,
        "adder_observed_speedup":adder_interpreter_per/max(adder_lookup_per,1e-12),
        "counter_interpreter_us_per_call":counter_interpreter_per,
        "counter_lookup_us_per_call":counter_lookup_per,
        "counter_observed_speedup":counter_interpreter_per/max(counter_lookup_per,1e-12),
        "process_elapsed_s":{"min":min(elapsed),"median":statistics.median(elapsed),"max":max(elapsed)},
        "process_max_rss_kb":{"min":min(rss),"median":int(statistics.median(rss)),"max":max(rss)},
      },
      "samples":samples,
      "policy":{
        "timing_is_acceptance_threshold":False,
        "speedup_is_acceptance_threshold":False,
        "device_specific_kernel":False,
        "capsule_is_derived":True,
        "runtime_owns_persistent_state":False,
      }
    }
    result["evidence_hash"]=canonical_hash(result)
    out=Path(args.out); out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(result,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    print("FABRIC_R5_2_T2_EVIDENCE_HASH="+result["evidence_hash"])
    print("FABRIC_R5_2_T2_DETERMINISTIC_HASH="+result["deterministic_hash"])
    print("FABRIC_R5_2_T2_EVIDENCE=PASS")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
