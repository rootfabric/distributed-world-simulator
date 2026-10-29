#!/usr/bin/env python3
"""NET-SMOOTH1 P2.3 R2.0: per-frame COMPACT transport flush layer reducer.

Read only. Reads original P2.2 frame/compact stage data and additional R2.0
boundary -> simulated-network -> ENet diagnostics. Does NOT modify evidence,
change original normative verdict, or prove actual network delivery latency.
"""
from __future__ import annotations

from collections import Counter, defaultdict
import argparse
import json
import math
from pathlib import Path

from analyze_r31p22_loop_stages import read_trace, positive_int, number, dist, analyze_events

SIM_STAGES=("frame_validate_ms","canonical_json_ms","pre_delegate_ms","delegate_ms")
ENET_STAGES=("validate_ms","frame_encode_ms","channel_setup_ms","put_packet_ms","peer_stats_ms")
BOUNDARY_STAGES=("queue_stage_ms","detached_frame_copy_ms","port_call_ms")
TOLERANCE_MS=0.5


def analyze(root:Path,minimum_wire_events:int=10)->dict:
    manifest=json.loads((root/"manifest.json").read_text(encoding="utf-8"))
    run_id=manifest.get("run_id")
    if (type(run_id) is not str or len(run_id)!=16
        or manifest.get("r31p23r2_flush_attribution") is not True
        or manifest.get("r31p22_loop_attribution") is not True):
        raise ValueError("P23R2_INVALID_CANARY_OR_RUN_ID")
    # Exact R2.2 requires ALL R2.1 / durable / worker prerequisite canaries.
    # Never allow a claimed attestation to waive their actual source lineage.
    r22_expected=manifest.get("r31p23r22_attested_compact")
    if r22_expected is not None and type(r22_expected) is not bool:
        raise ValueError("R22_INVALID_MANIFEST_CANARY")
    legacy_durable_canaries=(
        manifest.get("r31bp1_durable_chunks") is True
        and manifest.get("r3c4r2_worker_envelope") is True)
    r22_attribution_arm=(r22_expected is True)
    if not legacy_durable_canaries:
        raise ValueError("P23R2_INVALID_CANARY_OR_RUN_ID")
    # Historical R2.0 traces have no R2.1 field; on a NEW R2.1
    # OFF/ON comparison the run's own manifest and every COMPACT's actual
    # nested simulator+ENet receipt MUST agree. A disabled/unexecuted fast
    # path can never masquerade as the optimized ON arm.
    r21_expected=manifest.get("r31p23r21_single_pass_compact")
    if r21_expected is not None and type(r21_expected) is not bool:
        raise ValueError("R21_INVALID_MANIFEST_CANARY")
    # R2.2 attested-compact is fail-closed ON TOP of R2.1 single-pass compact;
    # an R2.2 claim without the R2.1 canary can never be analyzed as ON.
    if r22_attribution_arm and r21_expected is not True:
        raise ValueError("R22_REQUIRES_R21_CANARY")
    r21_confirmed=0
    r22_confirmed=0
    p1_batch_expected=manifest.get("r31p1_snapshot_batching",False)
    if type(p1_batch_expected) is not bool:
        raise ValueError("P1_INVALID_BATCH_MANIFEST_CANARY")
    trace_path=root/"server"/"trace.jsonl"
    trace=read_trace(trace_path,run_id)
    old=analyze_events(trace, minimum_frames=100, minimum_snapshots=10)
    originals=defaultdict(list)
    for row in trace["r31p22_compact_wire_stages"]:
        frame=positive_int(row["data"].get("engine_frame"),"BASE_COMPACT")
        originals[frame].append(number(row["data"].get("outbound_flush_ms"),"BASE_COMPACT_FLUSH"))
    present_frames={int(row["engine_frame"]) for row in old["worst_frame_samples"]}
    observed=defaultdict(list)
    stage_series={key:[] for key in BOUNDARY_STAGES}
    simulator_series={key:[] for key in SIM_STAGES}
    enet_series={key:[] for key in ENET_STAGES+("attestation_ms",)}
    ids=set()
    passthrough_count=0
    nonpassthrough_count=0
    batch_by_frame={}
    with trace_path.open(encoding="utf-8") as stream:
        for line_no,raw in enumerate(stream,1):
            if len(raw)>1048576:
                raise ValueError("P23R2_OVERSIZED_TRACE_ROW")
            row=json.loads(raw)
            if row.get("kind")=="r31p1_snapshot_batch_flush" and row.get("measure") is True:
                d=row.get("data")
                if not isinstance(d,dict):
                    raise ValueError("P1_BATCH_MALFORMED")
                frame=positive_int(d.get("engine_frame"),"P1_BATCH_FRAME")
                if frame in batch_by_frame:
                    raise ValueError("P1_BATCH_DUPLICATE_FRAME")
                if d.get("complete") is not True:
                    raise ValueError("P1_BATCH_DISPATCH_INCOMPLETE")
                queued=positive_int(d.get("queued_compact_frames"),"P1_BATCH_QUEUED")
                attempted=positive_int(d.get("attempted"),"P1_BATCH_ATTEMPTED")
                dispatched=positive_int(d.get("dispatched"),"P1_BATCH_DISPATCHED")
                count=positive_int(d.get("target_peers"),"P1_BATCH_PEERS")
                if queued>count or attempted<dispatched or dispatched<queued:
                    raise ValueError("P1_BATCH_COUNT_INCONSISTENT")
                if (d.get("failed_count")!=0 or d.get("blocked_stream_count")!=0
                    or d.get("pending_messages")!=0 or d.get("pending_bytes")!=0):
                    raise ValueError("P1_BATCH_UNFLUSHED_MESSAGES")
                batch_by_frame[frame]={
                    "queued_compact_frames":queued,
                    "attempted":attempted,"dispatched":dispatched,
                    "batch_flush_ms":number(d.get("batch_flush_ms"),"P1_BATCH_DURATION"),
                }
                continue
            if row.get("kind")!="r31p23r2_flush_packet" or row.get("measure") is not True:
                continue
            d=row.get("data")
            if not isinstance(d,dict):
                raise ValueError("P23R2_MALFORMED_FLUSH_PACKET")
            frame=positive_int(d.get("engine_frame"),"R2_FLUSH")
            identity=d.get("frame_id")
            if type(identity) is not str or not identity.startswith("frame/") or identity in ids:
                raise ValueError("P23R2_DUPLICATE_OR_INVALID_FRAME_ID")
            ids.add(identity)
            positive_int(d.get("session_sequence"),"SESSION_SEQUENCE")
            positive_int(d.get("attempt_number"),"ATTEMPT_NUMBER")
            if d.get("success") is not True or d.get("error_code") not in ("",None):
                raise ValueError("P23R2_FAILED_COMPACT_WIRE_SEND")
            if d.get("channel")!="SNAPSHOT" or d.get("delivery_mode")!="UNRELIABLE_SEQUENCED":
                raise ValueError("P23R2_UNEXPECTED_COMPACT_CHANNEL_OR_MODE")
            bstage={key:number(d.get(key),key) for key in BOUNDARY_STAGES}
            for key,v in bstage.items():
                stage_series[key].append(v)
            sim=d.get("simulator")
            if not isinstance(sim,dict) or type(sim.get("passthrough")) is not bool:
                raise ValueError("P23R2_SIMULATOR_PROFILE_MISSING")
            if r21_expected is not None and sim["passthrough"]:
                # R2.2 keeps the canonical packet-size receipt, but does
                # NOT use R2.1 fast encode: it consumes native attestation.
                expected_fast=r21_expected and not r22_attribution_arm
                if (sim.get("r31p23r21_size_reused") is not r21_expected
                    or sim.get("r31p23r21_fast_encode") is not expected_fast):
                    raise ValueError("R21_FAST_ENCODE_OR_SIZE_RECEIPT_MISMATCH")
                r21_confirmed+=1
            sim_parts={key:number(sim.get(key),key) for key in SIM_STAGES}
            if sum(sim_parts.values())>bstage["port_call_ms"]+TOLERANCE_MS:
                raise ValueError("P23R2_SIMULATOR_EXCEEDS_PORT_CALL")
            for key,v in sim_parts.items():
                simulator_series[key].append(v)
            enet_parts={}
            if sim["passthrough"]:
                passthrough_count+=1
                enet=sim.get("enet")
                if not isinstance(enet,dict):
                    raise ValueError("P23R2_ENET_DETAILS_MISSING")
                if r22_attribution_arm:
                    if ("attestation_ms" not in enet
                        or enet.get("validate_ms") != 0.0
                        or enet.get("frame_encode_ms") != 0.0):
                        raise ValueError("R22_ATTESTATION_STAGE_MISSING_OR_INVALID")
                    stage_keys=ENET_STAGES+("attestation_ms",)
                    r22_confirmed+=1
                else:
                    if "attestation_ms" in enet:
                        raise ValueError("R22_UNEXPECTED_ATTESTATION_OFF")
                    stage_keys=ENET_STAGES
                enet_parts={key:number(enet.get(key),key) for key in stage_keys}
                enet_total=number(enet.get("total_ms"),"ENET_TOTAL")
                if abs(sum(enet_parts.values())-enet_total)>TOLERANCE_MS:
                    raise ValueError("P23R2_ENET_COMPONENTS_NOT_ADDITIVE")
                if enet_total>sim_parts["delegate_ms"]+TOLERANCE_MS:
                    raise ValueError("P23R2_ENET_EXCEEDS_DELEGATE")
                for key,v in enet_parts.items():
                    enet_series[key].append(v)
            else:
                nonpassthrough_count+=1
                if sim.get("enet"):
                    raise ValueError("P23R2_NONPASSTHROUGH_CANNOT_PRETEND_ENET")
            observed[frame].append({
                "frame_id":identity,"session_sequence":d["session_sequence"],
                "queue":bstage,"simulator":sim_parts,
                "enet":enet_parts,"passthrough":sim["passthrough"],
            })

    if r22_attribution_arm and r22_confirmed < minimum_wire_events:
        raise ValueError("R22_NO_CONFIRMED_PASSTHROUGH_ATTESTATIONS")
    expected_total=sum(map(len,originals.values()))
    observed_total=sum(map(len,observed.values()))
    if expected_total<minimum_wire_events or observed_total!=expected_total:
        raise ValueError(f"P23R2_INCOMPLETE_COMPACT_COVERAGE:{observed_total}/{expected_total}")
    if set(observed)!=set(originals):
        raise ValueError("P23R2_INCOMPLETE_ENGINE_FRAME_COVERAGE")
    if p1_batch_expected:
        if set(batch_by_frame)!=set(originals):
            raise ValueError("P1_BATCH_MISSING_OR_UNEXPECTED_FRAME")
    elif batch_by_frame:
        raise ValueError("P1_BATCH_EVENT_WITHOUT_CANARY")
    by_frame=[]
    for frame in sorted(originals):
        outer=originals[frame]
        inner=observed[frame]
        if len(outer)!=len(inner):
            raise ValueError("P23R2_FRAME_PEER_SEND_COUNT_MISMATCH")
        boundaries=sum(sum(p["queue"].values()) for p in inner)
        batch=batch_by_frame.get(frame,{})
        if batch and batch["queued_compact_frames"] != len(inner):
            raise ValueError("P1_BATCH_PEER_PACKET_COUNT_MISMATCH")
        actual_flush=sum(outer)+batch.get("batch_flush_ms",0.0)
        if boundaries>actual_flush+TOLERANCE_MS:
            raise ValueError("P23R2_LAYER_STAGES_EXCEED_ORIGINAL_FLUSH")
        by_frame.append({
            "engine_frame":frame,
            "wire_count":len(inner),
            "original_flush_ms":sum(outer),
            "batch_flush_ms":batch.get("batch_flush_ms",0.0),
            "combined_flush_ms":actual_flush,
            "boundary_queue_ms":sum(p["queue"]["queue_stage_ms"] for p in inner),
            "boundary_frame_copy_ms":sum(p["queue"]["detached_frame_copy_ms"] for p in inner),
            "simulator_validate_ms":sum(p["simulator"]["frame_validate_ms"] for p in inner),
            "simulator_canonical_json_ms":sum(p["simulator"]["canonical_json_ms"] for p in inner),
            "enet_validate_ms":sum(p["enet"].get("validate_ms",0.0) for p in inner),
            "enet_encode_ms":sum(p["enet"].get("frame_encode_ms",0.0) for p in inner),
            "enet_put_packet_ms":sum(p["enet"].get("put_packet_ms",0.0) for p in inner),
            "unaccounted_flush_ms":max(0.0,actual_flush-boundaries),
        })
    slow_frame_ids={int(r["engine_frame"]) for r in old["worst_frame_samples"]
                    if number(r.get("frame_interval_ms"),"frame_interval")>25}
    # The complete top-100 list is intentionally retained; it is not the whole
    # population of all >25ms frames unless all are in the top 100.
    slow_wire=[row for row in by_frame if row["engine_frame"] in slow_frame_ids]
    norm=json.loads((root/"report.json").read_text(encoding="utf-8"))
    return {
        "schema":"dws.net_smooth.r31p23r2.flush_attribution.v1",
        "verdict":"R31P23R2_TRANSPORT_ATTRIBUTION_VALID_ONLY_NOT_PERF_PASS",
        "normative_original_verdict":norm.get("verdict"),
        "trace_sha256":trace["trace_sha256"],
        "run_id":run_id,
        "all_original_compact_events":expected_total,
        "all_nested_flush_events":observed_total,
        "passthrough_events":passthrough_count,
        "condition_queued_events":nonpassthrough_count,
        "r21_requested":r21_expected,
        "r21_confirmed_passthrough_events":r21_confirmed,
        "r22_attested_requested":bool(r22_expected),
        "r22_confirmed_passthrough_events":r22_confirmed,
        "p1_batch_expected":p1_batch_expected,
        "p1_batch_event_count":len(batch_by_frame),
        "boundary_stage_ms":{k:dist(v) for k,v in stage_series.items()},
        "simulator_stage_ms":{k:dist(v) for k,v in simulator_series.items()},
        "enet_stage_ms":{k:dist(v) for k,v in enet_series.items()},
        "slow_frames_in_p22_top100":len(slow_wire),
        "top100_slow_frame_flush_breakdown":sorted(
            slow_wire,key=lambda x:x["combined_flush_ms"],reverse=True)[:100],
        "worst_flush_frames":sorted(by_frame,
            key=lambda x:x["combined_flush_ms"],reverse=True)[:100],
        "limitations":[
            "Only original same-process engine frames are compared.",
            "ENet put_packet elapsed time is NOT end-to-end network delivery latency.",
            "Existing COMPACT frame/checksum and queue semantics are unchanged.",
            "The parent p22 top-100 is not a substitute for the full normative p99.",
            "This result never changes the original runner verdict."
        ],
    }


def main()->int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_root",type=Path)
    parser.add_argument("--output",type=Path,required=True)
    args=parser.parse_args()
    try:
        out=analyze(args.run_root)
    except (OSError,ValueError,TypeError,KeyError,json.JSONDecodeError) as ex:
        print("P23R2_FLUSH_INCONCLUSIVE: "+str(ex))
        return 2
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps({"verdict":out["verdict"],"wire_events":out["all_nested_flush_events"],
                      "original_verdict":out["normative_original_verdict"]}))
    return 0


if __name__=="__main__":
    raise SystemExit(main())
