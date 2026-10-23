#!/usr/bin/env python3
"""A14.7 R2 Stage A: fail-closed exact full-state CPU phase profile validator.

A performance chart is not an acceptance SLA. Multiple canonical hashing,
conservation and A8 comparisons occur *outside* the measured CPU worker.
"""
import argparse
import json
from pathlib import Path
import sys

SIZES = (4, 32, 96, 256)
EXPECTED = {
    4: "7b56b22193534e2a77c33be3e02b1cb33fc37f189e6d68b4b1535a548fc06062",
    32: "62128cea01410626cfda7556c39afb2ae110606cee229a875476143a240ed129",
    96: "23b11ab4c0454d08de1e82b93a1a5913a2bed4116e29dc2f6bcc765cfd2bb448",
    256: "f38c44896ffc8028c00b1c1f74e5b99d41f12620d60f99f7a95690b3f6419906",
}
SCHEMA = "dws.ecology.a14-7-r2-stage-a-cpu-attribution.v1"
PHASES = ("prepare", "allocate_begin", "allocate_resume", "advance")
DURATIONS = ("begin_us", "cursor_encode_us", "resume_total_us")
EXTRA = ("source_full_validate_us", "candidate_full_validate_us", "snapshot_projection_us")


def errors(p):
    result = []
    def req(condition, label):
        if not condition:
            result.append(label)
    n = p.get("population")
    req(p.get("schema") == SCHEMA and n in EXPECTED, "SCHEMA/POPULATION")
    if n in EXPECTED:
        req(p.get("canonical_hash") == EXPECTED[n], "CANONICAL_HASH")
    req(p.get("checkpoint_equal") is True, "CHECKPOINT_NOT_EXACT")
    req(p.get("source_unchanged") is True, "SOURCE_MUTATED")
    req(p.get("single_global_allocator") is True, "GLOBAL_ALLOCATOR_REQUIRED")
    req(p.get("canonical_biology_changed") is False, "BIOLOGY_CHANGED")
    req(p.get("throughput_sla_met_claim") is False, "UNPROVEN_SLA_CLAIM")
    req(p.get("phase_finalization_is_subset") is True, "SUBSET_DEFINITION")
    phase = p.get("phase", {})
    req(isinstance(phase, dict), "PHASE_SCHEMA")
    if not isinstance(phase, dict):
        return result
    for key in list(DURATIONS) + [f"{b}_us" for b in PHASES] + [
        f"{b}_calls" for b in PHASES] + ["finalize_us", "finalize_calls",
        "max_single_resume_us", "max_cursor_encode_us", "max_cursor_bytes"]:
        req(type(phase.get(key)) is int and phase.get(key, -1) >= 0, "PHASE_" + key)
    for key in ("worker_wall_us", "worker_unattributed_us", "resumes",
                "pending_frames", "host_poll_peak_us", "host_wall_us") + EXTRA:
        req(type(p.get(key)) is int and p.get(key, -1) >= 0, "PROFILE_" + key)
    if result:
        return result
    count = sum(phase[f"{b}_calls"] for b in PHASES)
    resume_sum = sum(phase[f"{b}_us"] for b in PHASES)
    req(count == p["resumes"] and count > 0, "RESUME_COUNT")
    req(resume_sum == phase["resume_total_us"] and resume_sum > 0, "RESUME_PHASE_SUM")
    req(phase["prepare_calls"] > 0 and phase["advance_calls"] > 0
        and phase["allocate_begin_calls"] == 1 and phase["finalize_calls"] == 1,
        "CANONICAL_PHASE_COUNTS")
    req(0 < phase["finalize_us"] <= phase["advance_us"], "FINALIZE_SUBSET_OF_ADVANCE")
    req(phase["max_single_resume_us"] <= phase["resume_total_us"], "RESUME_PEAK")
    req(phase["max_cursor_encode_us"] <= phase["cursor_encode_us"], "ENCODE_PEAK")
    req(0 < phase["max_cursor_bytes"] <= 8388608, "CURSOR_CAP")
    require_full = p["worker_wall_us"] - (
        phase["begin_us"] + phase["cursor_encode_us"] + phase["resume_total_us"] +
        sum(p[k] for k in EXTRA)
    )
    req(require_full == p["worker_unattributed_us"], "UNATTRIBUTED_WALL_ACCOUNTING")
    req(p["worker_wall_us"] > 0 and p["source_full_validate_us"] > 0 and
        p["candidate_full_validate_us"] > 0 and p["snapshot_projection_us"] > 0,
        "FULL_VALIDATIONS_AND_PROJECTION")
    return result


def selftest():
    p = {"schema": SCHEMA, "population": 4, "canonical_hash": EXPECTED[4],
         "checkpoint_equal": True, "source_unchanged": True,
         "single_global_allocator": True, "canonical_biology_changed": False,
         "throughput_sla_met_claim": False, "phase_finalization_is_subset": True,
         "resumes": 4, "worker_wall_us": 45, "worker_unattributed_us": 5,
         "source_full_validate_us": 3, "candidate_full_validate_us": 3,
         "snapshot_projection_us": 2, "pending_frames": 4,
         "host_poll_peak_us": 1, "host_wall_us": 30000,
         "phase": {
             "begin_us": 2, "cursor_encode_us": 1, "resume_total_us": 29,
             "prepare_us": 5, "allocate_begin_us": 5,
             "allocate_resume_us": 5, "advance_us": 14,
             "prepare_calls": 1, "allocate_begin_calls": 1,
             "allocate_resume_calls": 1, "advance_calls": 1,
             "finalize_us": 14, "finalize_calls": 1,
             "max_single_resume_us": 14, "max_cursor_encode_us": 1,
             "max_cursor_bytes": 256}}
    assert not errors(p), errors(p)
    for k,v in [("checkpoint_equal", False), ("canonical_hash", "0"*64),
                ("worker_unattributed_us", 17),
                ("single_global_allocator", False)]:
        mutated = dict(p)
        mutated[k] = v
        assert errors(mutated), k
    print("A147_R2_VALIDATOR_SELFTEST_PASS")


def main():
    a = argparse.ArgumentParser()
    a.add_argument("files", type=Path, nargs="*")
    a.add_argument("--self-test", action="store_true")
    args = a.parse_args()
    if args.self_test:
        selftest()
        return 0
    if len(args.files) != 4:
        print("A147_R2_PROFILE_REQUIRES_EXACTLY_FOUR_FILES")
        return 1
    profiles = []
    for path in args.files:
        p = json.loads(path.read_text(encoding="utf-8-sig"))
        if errors(p):
            print(f"A147_R2_PROFILE_REJECT path={path} reason={errors(p)}")
            return 1
        profiles.append(p)
    if [p["population"] for p in profiles] != list(SIZES):
        print("A147_R2_PROFILE_MISSING_SCALE_OR_WRONG_ORDER")
        return 1
    print("POPULATION | WORKER_MS | PREPARE_% | ALLOCATE_% | ADVANCE_% | CURSOR_ENCODE_% | SOURCE_VALIDATE_% | CANDIDATE_VALIDATE_% | PROJECTION_%")
    for p in profiles:
        phase = p["phase"]
        denom = p["worker_wall_us"]
        pct = lambda count: round(100 * count / denom, 2)
        print("%d | %.3f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f | %.2f" %
              (p["population"], denom / 1000.0,
               pct(phase["prepare_us"]),
               pct(phase["allocate_begin_us"] + phase["allocate_resume_us"]),
               pct(phase["advance_us"]),
               pct(phase["cursor_encode_us"]),
               pct(p["source_full_validate_us"]),
               pct(p["candidate_full_validate_us"]),
               pct(p["snapshot_projection_us"])))
    print("A147_R2_ALL_FOUR_EXACT_PROFILES_PASS")
    print("SIMULATION_THROUGHPUT_ACCEPTANCE=NOT_YET_MEASURED_OR_ACHIEVED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
