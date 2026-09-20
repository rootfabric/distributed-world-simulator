#!/usr/bin/env python3
"""Aggregate R5.1 5k/20k/100k quantitative scaling evidence."""
from __future__ import annotations
import argparse, hashlib, json, re, statistics
from pathlib import Path
from typing import Any

COUNTS = [5000, 20000, 100000]
SAMPLES_PER_COUNT = 3
PREFIX = "FABRIC_R5_1_SCALE="
PASS = "FABRIC R5.1 QUANTITATIVE SCALE: PASS"
STAGES = [
    "source_create_with_expanded_digests",
    "source_full_rehash_validation",
    "range_index_build",
    "parent_aggregate_compile",
    "range_index_parent_query",
    "bake_start",
    "baked_boundary_hot_loop_before",
    "local_unbake_20",
    "local_capsule_capture",
    "local_capsule_restore",
    "canonical_successor_create",
    "canonical_mutation_fence",
    "fenced_capsule_capture",
    "fenced_capsule_restore",
    "local_rebake_after_settle",
    "baked_boundary_hot_loop_after",
    "final_capsule_capture",
    "final_capsule_restore",
    "global_control_full_aggregate",
]

def cbytes(v: Any) -> bytes:
    return json.dumps(v, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()

def sha(v: Any) -> str:
    return hashlib.sha256(cbytes(v)).hexdigest()

def parse_time(path: Path) -> dict[str, Any]:
    values = {}
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if ": " in line:
            k, v = line.rsplit(": ", 1)
            values[k] = v.strip()
    elapsed_key = next((k for k in values if k.startswith("Elapsed (wall clock) time")), None)
    if elapsed_key is None:
        raise ValueError(f"elapsed missing: {path}")
    def elapsed(s: str) -> float:
        p=s.split(":")
        if len(p)==2: return float(p[0])*60+float(p[1])
        if len(p)==3: return float(p[0])*3600+float(p[1])*60+float(p[2])
        return float(s)
    cpu=values.get("Percent of CPU this job got","")
    if not cpu.endswith("%"): raise ValueError(f"cpu missing: {path}")
    return {
        "elapsed_s": elapsed(values[elapsed_key]),
        "user_time_s": float(values["User time (seconds)"]),
        "system_time_s": float(values["System time (seconds)"]),
        "cpu_percent": float(cpu[:-1]),
        "max_rss_kb": int(values["Maximum resident set size (kbytes)"].replace(",","")),
        "minor_page_faults": int(values["Minor (reclaiming a frame) page faults"].replace(",","")),
        "major_page_faults": int(values["Major (requiring I/O) page faults"].replace(",","")),
    }

def parse_log(path: Path, expected_count: int) -> dict[str, Any]:
    text=path.read_text(encoding="utf-8", errors="replace")
    if PASS not in text: raise ValueError(f"PASS missing: {path}")
    rows=[x[len(PREFIX):] for x in text.splitlines() if x.startswith(PREFIX)]
    if len(rows)!=1: raise ValueError(f"expected one scale row: {path}")
    data=json.loads(rows[0])
    c=data.get("counters",{})
    if c.get("canonical_parts")!=expected_count: raise ValueError("R5_1_COUNT_DRIFT")
    if c.get("parent_compile_parts_scanned")!=expected_count: raise ValueError("R5_1_PARENT_SCAN_DRIFT")
    if c.get("range_index_build_parts_scanned")!=expected_count: raise ValueError("R5_1_INDEX_BUILD_SCAN_DRIFT")
    if c.get("lifecycle_metadata_parts_scanned")!=0: raise ValueError("R5_1_LIFECYCLE_SCAN_NOT_ELIMINATED")
    if c.get("range_query_count")!=4: raise ValueError("R5_1_RANGE_QUERY_COUNT_DRIFT")
    if c.get("range_query_prefix_reads")!=80: raise ValueError("R5_1_RANGE_QUERY_WORK_DRIFT")
    if c.get("global_control_parts_scanned")!=expected_count: raise ValueError("R5_1_GLOBAL_CONTROL_SCAN_DRIFT")
    if c.get("active_full_peak")!=20: raise ValueError("R5_1_FULL_PEAK_DRIFT")
    if c.get("local_reconstructed_parts")!=20: raise ValueError("R5_1_LOCAL_RECONSTRUCTION_DRIFT")
    if c.get("rebake_local_validations")!=20: raise ValueError("R5_1_REBAKE_VALIDATION_DRIFT")
    if c.get("global_physical_rebuilds")!=0: raise ValueError("R5_1_GLOBAL_REBUILD_PRESENT")
    if c.get("duplicate_ownership_count")!=0: raise ValueError("R5_1_DUPLICATE_OWNER_PRESENT")
    if c.get("boundary_execute_calls")!=128: raise ValueError("R5_1_BOUNDARY_CALL_DRIFT")
    missing=[s for s in STAGES if s not in data.get("stages",{})]
    if missing: raise ValueError(f"R5_1_STAGE_MISSING {missing}")
    return data

def med(xs):
    return statistics.median(xs)

def main() -> int:
    ap=argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--out", required=True)
    args=ap.parse_args()
    root=Path(args.root)
    by_count={}
    deterministic_rows=[]
    for count in COUNTS:
        samples=[]
        hashes=set()
        payload_hashes=set()
        for sample in range(1,SAMPLES_PER_COUNT+1):
            stem=f"count-{count}-sample-{sample}"
            baseline=parse_log(root/f"{stem}.log", count)
            proc=parse_time(root/f"{stem}.time.txt")
            hashes.add(str(baseline["deterministic_hash"]))
            payload_hashes.add(sha(baseline["deterministic"]))
            samples.append({"sample":sample,"baseline":baseline,"process":proc})
        if len(hashes)!=1 or len(payload_hashes)!=1:
            raise ValueError(f"R5_1_DETERMINISM_MISMATCH count={count}")
        stage_summary={}
        for stage in STAGES:
            vals=[int(s["baseline"]["stages"][stage]["duration_us"]) for s in samples]
            stage_summary[stage]={"min":min(vals),"median":int(med(vals)),"max":max(vals)}
        rss=[s["process"]["max_rss_kb"] for s in samples]
        elapsed=[s["process"]["elapsed_s"] for s in samples]
        static=[int(s["baseline"]["memory_static_peak_bytes"]) for s in samples]
        row={
            "count":count,
            "deterministic_hash":next(iter(hashes)),
            "deterministic_payload_sha256":next(iter(payload_hashes)),
            "active_full_peak":20,
            "active_fraction":20.0/count,
            "local_reconstructed_parts":20,
            "rebake_local_validations":20,
            "global_physical_rebuilds":0,
            "parent_compile_parts_scanned":count,
            "range_index_build_parts_scanned":count,
            "lifecycle_metadata_parts_scanned":0,
            "range_query_count":4,
            "range_query_prefix_reads":80,
            "global_control_parts_scanned":count,
            "stage_us":stage_summary,
            "process_elapsed_s":{"min":min(elapsed),"median":med(elapsed),"max":max(elapsed)},
            "process_max_rss_kb":{"min":min(rss),"median":int(med(rss)),"max":max(rss)},
            "godot_memory_static_peak_bytes":{"min":min(static),"median":int(med(static)),"max":max(static)},
            "samples":samples,
        }
        by_count[str(count)]=row
        deterministic_rows.append({
            "count":count,
            "deterministic_hash":row["deterministic_hash"],
            "payload_sha256":row["deterministic_payload_sha256"],
            "active_full_peak":20,
            "parent_scan":count,
            "index_build_scan":count,
            "lifecycle_scan":0,
            "range_queries":4,
            "global_control_scan":count,
        })

    base=by_count["5000"]
    derived={}
    for count in COUNTS:
        row=by_count[str(count)]
        derived[str(count)]={
            "N_ratio_vs_5k":count/5000.0,
            "active_fraction":row["active_fraction"],
            "source_create_ratio_vs_5k":row["stage_us"]["source_create_with_expanded_digests"]["median"]/max(1,base["stage_us"]["source_create_with_expanded_digests"]["median"]),
            "full_rehash_ratio_vs_5k":row["stage_us"]["source_full_rehash_validation"]["median"]/max(1,base["stage_us"]["source_full_rehash_validation"]["median"]),
            "range_index_build_ratio_vs_5k":row["stage_us"]["range_index_build"]["median"]/max(1,base["stage_us"]["range_index_build"]["median"]),
            "range_index_parent_query_ratio_vs_5k":row["stage_us"]["range_index_parent_query"]["median"]/max(1,base["stage_us"]["range_index_parent_query"]["median"]),
            "parent_aggregate_ratio_vs_5k":row["stage_us"]["parent_aggregate_compile"]["median"]/max(1,base["stage_us"]["parent_aggregate_compile"]["median"]),
            "global_control_ratio_vs_5k":row["stage_us"]["global_control_full_aggregate"]["median"]/max(1,base["stage_us"]["global_control_full_aggregate"]["median"]),
            "local_unbake_ratio_vs_5k":row["stage_us"]["local_unbake_20"]["median"]/max(1,base["stage_us"]["local_unbake_20"]["median"]),
            "local_rebake_ratio_vs_5k":row["stage_us"]["local_rebake_after_settle"]["median"]/max(1,base["stage_us"]["local_rebake_after_settle"]["median"]),
            "baked_boundary_before_ratio_vs_5k":row["stage_us"]["baked_boundary_hot_loop_before"]["median"]/max(1,base["stage_us"]["baked_boundary_hot_loop_before"]["median"]),
            "rss_ratio_vs_5k":row["process_max_rss_kb"]["median"]/max(1,base["process_max_rss_kb"]["median"]),
        }

    result={
        "schema":"planet_simulator.fabric_r5_1_quantitative_scale_evidence.v1",
        "counts":COUNTS,
        "samples_per_count":SAMPLES_PER_COUNT,
        "correctness":{
            "active_full_peak_constant":20,
            "local_reconstructed_constant":20,
            "local_rebake_validations_constant":20,
            "global_physical_rebuilds":0,
            "duplicate_ownership_count":0,
            "metadata_scan_contract":"range_index_build=N once; parent_reference=N; online_local_residual_scan=0; range_queries=4 O(1); explicit_global_control=N",
        },
        "cases":by_count,
        "derived_scaling_observations":derived,
        "policy":{
            "timing_is_acceptance_threshold":False,
            "rss_is_acceptance_threshold":False,
            "global_control_is_natural_physical_propagation":False,
            "purpose":"R5.1 separates deterministic bounded-local correctness from observational O(N) metadata/global-control scaling.",
        },
        "scale_hash":sha({"schema":"r5.1.scale.identity.v1","rows":deterministic_rows}),
    }
    result["evidence_hash"]=sha(result)
    out=Path(args.out); out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(result,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    print("FABRIC_R5_1_SCALE_HASH="+result["scale_hash"])
    print("FABRIC_R5_1_EVIDENCE_HASH="+result["evidence_hash"])
    print("FABRIC_R5_1_EVIDENCE=PASS")
    return 0

if __name__=="__main__":
    raise SystemExit(main())
