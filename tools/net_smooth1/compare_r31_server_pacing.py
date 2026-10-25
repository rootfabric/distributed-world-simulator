#!/usr/bin/env python3
"""Read-only exact-source GUI comparator: server headless engine 60 vs 90/120.

No performance acceptance. Never changes or filters the original normative
report, client FPS, fixed 60Hz authority, 20Hz snapshot cadence or trace rows.
Comparing p99 alone is insufficient: increasing server engine FPS changes
sample count. Report >25ms gaps PER SECOND and verify 20Hz snapshot packets.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any

from analyze_r31p22_loop_stages import read_trace, number, dist

ROOT_LABEL = "dws.net_smooth.server_frame_pacing_diagnostic.v1"
REQUIRED_FLAGS = (
    "r3c4r2_worker_envelope", "r31bp1_durable_chunks",
    "r31p22_loop_attribution", "r31p23r2_flush_attribution",
    "r31p23r21_single_pass_compact", "r31p23r22_attested_compact",
    "r31p1_snapshot_batching",
)


def sha(path: Path) -> str:
    digest=hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda:stream.read(1024*1024),b""):
            digest.update(chunk)
    return digest.hexdigest()


def max_fps_from_command(command: Any, role: str) -> int:
    if (not isinstance(command,list) or any(type(x) is not str for x in command)
        or command.count("--max-fps")!=1):
        raise ValueError(f"INVALID_{role}_ENGINE_FPS_COMMAND")
    i=command.index("--max-fps")
    if (i+1>=len(command) or not command[i+1].isdigit()
        or "--disable-vsync" not in command):
        raise ValueError(f"INVALID_{role}_VSYNC_OR_FPS")
    if role=="server" and "--headless" not in command:
        raise ValueError("PACING_SERVER_NOT_HEADLESS")
    if role in ("a","b") and (
        "--headless" in command or "--rendering-driver" not in command
        or "opengl3" not in command
    ):
        raise ValueError("PACING_CLIENT_HARDWARE_GUI_NOT_PROVEN")
    return int(command[i+1])


def frame_profile_ms(frames: list[float], duration_s: float) -> dict[str, Any]:
    if len(frames)<100 or not 100.0<=duration_s<=140.0:
        raise ValueError("INSUFFICIENT_MEASURED_PACING_COVERAGE")
    values=[number(x,"PACING_FRAME_MS") for x in frames]
    return {
        "frames_per_second":len(values)/duration_s,
        "original_frame_interval_ms":dist(values),
        "over_25ms_count":sum(x>25 for x in values),
        "over_25ms_per_second":sum(x>25 for x in values)/duration_s,
        "over_50ms_per_second":sum(x>50 for x in values)/duration_s,
        "over_100ms_per_second":sum(x>100 for x in values)/duration_s,
        "in_double_60hz_slot_29_to_37ms":sum(29<=x<=37 for x in values),
        "in_double_60hz_slot_per_second":
            sum(29<=x<=37 for x in values)/duration_s,
        "note":"1/60s quantization is an association, not VSync/OS causal proof",
    }


def inspect_run(root: Path) -> dict[str, Any]:
    manifest_path=root/"manifest.json"
    report_path=root/"report.json"
    manifest=json.loads(manifest_path.read_text(encoding="utf-8"))
    report=json.loads(report_path.read_text(encoding="utf-8"))
    if (manifest.get("mode")!="gui" or manifest.get("profile")!="LOCAL"
        or manifest.get("scenario")!="r31-reconnect-roundtrip"
        or manifest.get("completed") is not True
        or manifest.get("errors")
        or manifest.get("max_fps")!=60
        or manifest.get("duration_s")!=120):
        raise ValueError("INVALID_GUI_120_SECOND_PACING_SOURCE")
    identity=manifest.get("identity",{})
    if not isinstance(identity,dict):
        raise ValueError("PACING_IDENTITY_MISSING")
    for k in ("head","tree","godot_sha256","asset_manifest_sha256"):
        if type(identity.get(k)) is not str or not identity[k]:
            raise ValueError("PACING_IDENTITY_MISSING_"+k)
    if identity.get("asset_count")!=123:
        raise ValueError("NONCANONICAL_RAW_QUATERNIUS_COUNT")
    for key in REQUIRED_FLAGS:
        if manifest.get(key) is not True:
            raise ValueError("PACING_REQUIRED_NATIVE_CANARY_MISSING_"+key)
    cap=manifest.get("server_max_fps")
    if type(cap) is not int or cap not in (60,90,120):
        raise ValueError("PACING_INVALID_SERVER_CAP")
    cmds=manifest.get("commands",{})
    if not isinstance(cmds,dict):
        raise ValueError("PACING_MISSING_ACTUAL_SPAWN_COMMANDS")
    for role in ("server","a","b"):
        observed=max_fps_from_command(cmds.get(role),role)
        expected=cap if role=="server" else 60
        if observed!=expected:
            raise ValueError("PACING_EXECUTED_ROLE_CAP_MISMATCH_"+role)
        if not (root/role/"measure.end.ack").is_file():
            raise ValueError("PACING_MISSING_MEASUREMENT_ACK_"+role)
    if (report.get("evidence_class")!="GUI_LOCAL_CANDIDATE"
        or report.get("verdict") not in ("PASS","FAIL")
        or report.get("infrastructure")):
        raise ValueError("PACING_ORIGINAL_NORMATIVE_RESULT_INCOMPLETE")
    results=report.get("processes",[])
    if (type(results) is not list or len(results)!=3 or
        {r.get("role") for r in results} != {"server","a","b"}):
        raise ValueError("PACING_MISSING_ORIGINAL_ROLE_REPORTS")
    by_role={r["role"]:r for r in results}
    if any(r.get("verdict")=="INCONCLUSIVE" for r in results):
        raise ValueError("PACING_INCONCLUSIVE_ROLE")
    trace_path=root/"server"/"trace.jsonl"
    trace=read_trace(trace_path,manifest["run_id"])
    measured_s=(trace["end_us"]-trace["start_us"])/1e6
    if measured_s<108 or measured_s>145:
        raise ValueError("PACING_DURATION_OUT_OF_BOUND")
    frame_ms=[
        number(row["data"].get("interval_ms"),"PACING_INTERVAL")
        for row in trace["frame"]
    ]
    stats=frame_profile_ms(frame_ms,measured_s)
    batch_count=0
    with trace_path.open(encoding="utf-8") as stream:
        for line in stream:
            data=json.loads(line)
            if (data.get("kind")=="r31p1_snapshot_batch_flush"
                and data.get("measure") is True):
                batch_count+=1
                if data.get("data",{}).get("complete") is not True:
                    raise ValueError("PACING_INCOMPLETE_BATCH")
    batch_hz=batch_count/measured_s
    if not 19.0<=batch_hz<=21.0:
        raise ValueError("PACING_COMPACT_20HZ_CADENCE_BROKEN")
    tick=number(by_role["server"].get("tick_hz"),"PACING_SERVER_TICK_HZ")
    if tick<59 or number(by_role["server"].get("dropped_time_delta_s"),"PACING_DROPPED_DELTA")>0:
        raise ValueError("PACING_SIMULATION_TICK_REGRESSION")
    if manifest.get("cleanup",{}).get("verified") is not True:
        raise ValueError("PACING_OWNED_CLEANUP_UNVERIFIED")
    return {
        "root":str(root),
        "source_identity":{k:identity[k] for k in (
            "head","tree","godot_sha256","asset_manifest_sha256")},
        "manifest_sha256":sha(manifest_path),
        "report_sha256":sha(report_path),
        "server_trace_sha256":trace["trace_sha256"],
        "server_max_fps":cap,
        "client_max_fps":60,
        "run_id":manifest["run_id"],
        "original_normative_verdict":report["verdict"],
        "original_process_verdicts":{k:by_role[k]["verdict"] for k in ("server","a","b")},
        "original_role_frame_p99_ms":{
            k:by_role[k]["metrics"]["frame_ms"]["p99"] for k in ("server","a","b")},
        "server_tick_hz":tick,
        "measured_seconds":measured_s,
        "snapshot_batch_count":batch_count,
        "snapshot_batches_per_second":batch_hz,
        "server_frame_profile":stats,
    }


def compare_pairs(paths: list[tuple[Path,Path]]) -> dict[str, Any]:
    if not paths:
        raise ValueError("PACING_NO_PAIRS")
    paired=[]
    candidate_caps=set()
    for idx,(base_path,trial_path) in enumerate(paths,1):
        base=inspect_run(base_path)
        trial=inspect_run(trial_path)
        for k in ("head","tree","godot_sha256","asset_manifest_sha256"):
            if base["source_identity"][k]!=trial["source_identity"][k]:
                raise ValueError(f"PACING_PAIR_{idx}_SOURCE_DRIFT_{k}")
        if base["server_max_fps"]!=60 or trial["server_max_fps"] not in (90,120):
            raise ValueError("PACING_INVALID_AB_PAIR_CAPS")
        if base["run_id"]==trial["run_id"]:
            raise ValueError("PACING_DUPLICATE_RUN_ID")
        candidate_caps.add(trial["server_max_fps"])
        paired.append({
            "pair":idx,"baseline_60":base,"candidate":trial,
            "delta_server_p99_ms":
                trial["original_role_frame_p99_ms"]["server"]-
                base["original_role_frame_p99_ms"]["server"],
            "delta_over25_gaps_per_second":
                trial["server_frame_profile"]["over_25ms_per_second"]-
                base["server_frame_profile"]["over_25ms_per_second"],
        })
    if len(candidate_caps)!=1:
        raise ValueError("PACING_MIXED_CANDIDATE_CAPS")
    all_runs=[run for pair in paired for run in (
        pair["baseline_60"],pair["candidate"])]
    if len({run["run_id"] for run in all_runs})!=len(all_runs):
        raise ValueError("PACING_DUPLICATE_GLOBAL_RUN")
    if len({run["source_identity"]["head"] for run in all_runs})!=1:
        raise ValueError("PACING_CROSS_PAIR_SOURCE_DRIFT")
    return {
        "schema":ROOT_LABEL,
        "verdict":"DIAGNOSTIC_ONLY_NEVER_ACCEPTS_RELEASE",
        "candidate_fps":next(iter(candidate_caps)),
        "pairs":paired,
        "comparative_hypothesis":"60-fps engine cap oversleep vs 90/120 cap",
        "limitations":[
            "The authoritative fixed simulation stays at 60Hz; 20Hz snapshots must remain.",
            "Increasing engine frame count can dilute percentile; inspect slow gaps PER SECOND.",
            "Reported CPU process stage vs interval is not proof of Windows OS/VSync causality.",
            "Do not claim release while any original p99/p999/max or gameplay safety gate fails.",
            "Non-default server cap is a diagnostic opt-in, not approved production config.",
        ],
    }


def main() -> int:
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--pair",nargs=2,action="append",required=True,
                   metavar=("CAP60_RUN_ROOT","CAP90_OR_120_RUN_ROOT"),type=Path)
    p.add_argument("--output",required=True,type=Path)
    args=p.parse_args()
    try:
        result=compare_pairs(args.pair)
    except (OSError,ValueError,TypeError,KeyError,json.JSONDecodeError) as exc:
        print("PACING_DIAGNOSTIC_INCONCLUSIVE:"+str(exc))
        return 2
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2),
                          encoding="utf-8")
    print(json.dumps({"verdict":result["verdict"],
                      "candidate":result["candidate_fps"],
                      "pairs":len(result["pairs"])}))
    return 0


if __name__=="__main__":
    raise SystemExit(main())
