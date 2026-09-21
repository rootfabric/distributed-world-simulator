#!/usr/bin/env python3
from __future__ import annotations
import argparse, hashlib, json, statistics
from pathlib import Path

PREFIX="FABRIC_R5_2_T9_RESULT="
PASS="FABRIC R5.2 T9 LASER EMITTER: PASS"

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
        assert d["source_cells"]==128 and d["active_cells"]==128
        assert d["source_operations"]==768 and d["compiled_operations"]==20
        assert d["runtime_source_cell_traversals"]==0
        assert d["total_max_current_a"] > d["total_threshold_current_a"] > 0.0
        assert d["wavelength_m"] > 0.0 and d["beam_divergence_half_angle_rad"] > 0.0
        assert d["sequence_ticks"]==2048
        assert d["full_reference_cell_traversals"]==128*2048
        assert d["maximum_terminal_voltage_error_v"]<=1e-12
        assert d["maximum_optical_energy_error_j"]<=1e-12
        assert d["maximum_waste_heat_error_j"]<=1e-12
        assert d["maximum_photon_count_relative_error"]<=1e-12
        assert d["maximum_divergence_error_rad"]<=1e-15
        assert d["maximum_energy_residual_j"]<=1e-12
        assert d["optical_emission_seen_above_threshold"] is True
        assert d["below_threshold_zero_optical_seen"] is True
        assert 0.0 < d["thermal_derating_ratio_380k_to_300k"] < 1.0
        assert d["gan_wavelength_m"] < d["wavelength_m"]
        assert d["gan_forward_voltage_v"] > 0.0
        assert d["damage_active_cells"]==127
        assert d["damage_mass_retained"] is True
        assert d["damage_divergence_ratio"]>1.0
        assert d["geometry_mismatch_error"]=="LASER_GAIN_CELL_SYNCHRONY_UNSAFE"
        assert d["mixed_profile_error"]=="LASER_GAIN_PROFILE_MISMATCH"
        assert d["descriptor_relation_error"]=="LASER_EMITTER_DESCRIPTOR_RELATION_MISMATCH"
        assert d["composition_max_voltage_error_v"]<=1e-12
        assert d["composition_max_energy_error_j"]<=1e-12
        assert d["composition_stage_loss_j"]>0.0
        assert d["composition_optical_energy_j"]>0.0
        assert d["composition_laser_heat_j"]>0.0
        hashes.add(canonical_hash(d))
        samples.append({"sample":i,"deterministic":d,"process":parse_time(root/f"sample-{i}.time.txt")})
    if len(hashes)!=1: raise ValueError("T9_DETERMINISM_MISMATCH")
    elapsed=[s["process"]["elapsed_s"] for s in samples]
    rss=[s["process"]["max_rss_kib"] for s in samples]
    result={
        "schema":"planet_simulator.fabric_r5_2_t9_evidence.v1",
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
            "photonic_profile_is_characterized_floor":True,
            "pack_level_damage_or_dps_constant_claimed":False,
            "common_aperture_floor":True,
            "runtime_source_traversal_zero":True,
            "t6_electrical_composition_is_acceptance_semantics":True,
        }
    }
    result["evidence_hash"]=canonical_hash(result)
    out=Path(args.out); out.parent.mkdir(parents=True,exist_ok=True)
    out.write_text(json.dumps(result,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    print("FABRIC_R5_2_T9_DETERMINISTIC_HASH="+result["deterministic_hash"])
    print("FABRIC_R5_2_T9_EVIDENCE_HASH="+result["evidence_hash"])
    print("FABRIC_R5_2_T9_EVIDENCE=PASS")

if __name__=="__main__":
    main()
