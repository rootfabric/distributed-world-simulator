#!/usr/bin/env python3
"""Fail-closed, process-local trace analysis. Python standard library only."""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
from typing import Any


def percentile(values: list[float], q: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    return ordered[min(len(ordered)-1, max(0, math.ceil(q*len(ordered))-1))]


def stats(values: list[float]) -> dict[str, Any]:
    return {"count": len(values), "p50": percentile(values, .5),
            "p95": percentile(values, .95), "p99": percentile(values, .99),
            "p999": percentile(values, .999), "max": max(values, default=None)}


def analyze_trace(path: Path, role: str, run_id: str, min_seconds: float = 10.0,
                  local_profile: bool = True, checkpoint_mode: str | None = None,
                  require_snapshot_stages: bool = False) -> dict[str, Any]:
    problems: list[str] = []
    failures: list[str] = []
    samples: dict[str, list[float]] = {k: [] for k in (
        "frame_ms", "server_ms", "message_ms", "fixed_ms", "snapshot_ms", "persistence_ms",
        "capture_ms", "reconcile_ms", "correction_m", "replayed_ticks", "snapshot_interval_ms")}
    stage_samples: dict[str, list[float]] = {k: [] for k in (
        "capture_ms", "encode_ms", "compact_send_ms", "seam_check_send_ms", "send_and_seam_ms",
        "decode_ms", "accept_ms", "reconcile_ms", "presentation_ms")}
    seam_sent = 0; seam_skipped = 0
    first: dict[str, Any] = {}; last: dict[str, Any] = {}
    header: dict[str, Any] = {}; footer: dict[str, Any] = {}
    previous: dict[str, dict[str, Any]] = {}
    previous_snapshot: dict[str, int] = {}
    anomalies: list[dict[str, Any]] = []
    counts: dict[str, int] = {}
    n = 0; last_time = -1; start_time = None; end_time = None
    distance = 0.0; backwards_holds = 0; max_silence = 0.0
    client_state = None; client_errors = 0; unexpected_states = 0
    measure_started = 0; measure_ended = 0
    try:
        with path.open(encoding="utf-8") as stream:
            for line_number, line in enumerate(stream, 1):
                if len(line) > 1024*1024:
                    raise ValueError(f"oversized trace record {line_number}")
                event = json.loads(line)
                if not isinstance(event,dict) or not isinstance(event.get("data",{}),dict):
                    raise ValueError("invalid record shape")
                kind = event.get("kind"); data = event.get("data", {})
                timestamp = event.get("t_us")
                if not isinstance(timestamp, (int, float)) or not math.isfinite(timestamp) or timestamp < last_time:
                    raise ValueError(f"invalid/nonmonotonic local clock line {line_number}")
                last_time = timestamp
                if kind == "end":
                    if footer: problems.append("duplicate END")
                    footer = data
                    continue
                if footer: problems.append("records after END")
                if event.get("n") != n+1: problems.append(f"event sequence gap at line {line_number}")
                n = int(event.get("n", n+1))
                if kind == "header":
                    if header or n != 1: problems.append("invalid header order")
                    header = data
                if kind == "measure_start": measure_started += 1
                if kind == "measure_end": measure_ended += 1
                if not event.get("measure", False): continue
                if start_time is None: start_time = timestamp
                end_time = timestamp
                counts[kind] = counts.get(kind, 0)+1
                if kind == "frame":
                    value = float(data["interval_ms"])
                    if not math.isfinite(value) or value < 0: raise ValueError("invalid frame duration")
                    samples["frame_ms"].append(value)
                    if value > 50 and len(anomalies) < 200:
                        anomalies.append({"kind":"frame_gap", "local_t_us":timestamp, "ms":value})
                elif kind == "server_loop":
                    if any(not isinstance(data[k],(float,int)) or not math.isfinite(data[k]) or data[k]<0
                           for k in ('tick','peers','rejections','dropped_time_s')):
                        raise ValueError('invalid server counters')
                    if checkpoint_mode is not None and data.get('async_enabled') is not (checkpoint_mode=='async'):
                        if 'checkpoint mode differs from manifest' not in problems:
                            problems.append('checkpoint mode differs from manifest')
                    point = dict(data, t_us=timestamp)
                    if not first: first = point
                    if last: max_silence = max(max_silence, (timestamp-last["t_us"])/1000)
                    last = point
                    for source,target in (("process_ms","server_ms"),("message_ms","message_ms"),
                        ("fixed_ms","fixed_ms"),("snapshot_ms","snapshot_ms"),
                        ("persistence_ms","persistence_ms"),("capture_ms","capture_ms")):
                        samples[target].append(float(data[source]))
                    if float(data["process_ms"]) > 50 and len(anomalies)<200:
                        anomalies.append({"kind":"server_stall", "local_t_us":timestamp, **data})
                elif kind == "movement_snapshot_stages" and role == "server":
                    fields = ("capture_ms", "encode_ms", "compact_send_ms", "seam_check_send_ms", "send_and_seam_ms")
                    for field in fields:
                        if field in data:
                            value = float(data[field])
                            if not math.isfinite(value) or value < 0:
                                raise ValueError(f"invalid movement snapshot stage {field}")
                            stage_samples[field].append(value)
                    for name in ("seam_sent", "seam_skipped_unchanged"):
                        if name in data and (type(data[name]) is not int or data[name] < 0):
                            raise ValueError(f"invalid seam counter {name}")
                    seam_sent += data.get("seam_sent", 0)
                    seam_skipped += data.get("seam_skipped_unchanged", 0)
                elif kind == "compact_snapshot_stages" and role != "server":
                    for field in ("decode_ms", "accept_ms", "reconcile_ms", "presentation_ms"):
                        if field in data:
                            value = float(data[field])
                            if not math.isfinite(value) or value < 0:
                                raise ValueError(f"invalid client snapshot stage {field}")
                            stage_samples[field].append(value)
                elif kind == "client_loop":
                    client_state = data["state"]
                    if client_state != "CONNECTED": unexpected_states += 1
                    client_errors = max(client_errors, int(data["reconcile_failures"]))
                elif kind == "snapshot_received":
                    session = str(data["session"])
                    if session in previous_snapshot:
                        samples["snapshot_interval_ms"].append((timestamp-previous_snapshot[session])/1000)
                    previous_snapshot[session] = timestamp
                elif kind == "reconcile":
                    for source,target in (("duration_ms","reconcile_ms"),("error_m","correction_m"),
                                          ("replayed_ticks","replayed_ticks")):
                        samples[target].append(float(data[source]))
                elif kind == "remote_visual":
                    if any(len(data[k])!=3 or any(not math.isfinite(v) for v in data[k]) for k in ('position','velocity')):
                        raise ValueError('invalid visual vectors')
                    key = str(data["id"])
                    prior = previous.get(key)
                    if prior:
                        displacement = [a-b for a,b in zip(data["position"], prior["position"])]
                        distance += math.sqrt(sum(x*x for x in displacement))
                        if prior["mode"] == "EXTRAPOLATE" and data["mode"] == "HOLD_EXTRAPOLATION_LIMIT":
                            if sum(x*v for x,v in zip(displacement,prior["velocity"])) < -1e-5:
                                backwards_holds += 1
                    previous[key] = data
    except (OSError, ValueError, TypeError, KeyError, OverflowError) as exc:
        problems.append(f"trace unreadable: {exc}")
    if require_snapshot_stages:
        required_kind = "movement_snapshot_stages" if role == "server" else "compact_snapshot_stages"
        required_fields = (
            ("compact_send_ms", "seam_check_send_ms", "send_and_seam_ms")
            if role == "server" else ("decode_ms", "accept_ms", "reconcile_ms", "presentation_ms")
        )
        if counts.get(required_kind, 0) < 10:
            problems.append(f"missing/incomplete {required_kind} evidence")
        for key in required_fields:
            if len(stage_samples[key]) < 10:
                problems.append(f"missing/incomplete snapshot stage {key}")
    if header.get("schema") != "dws.net_smooth.trace.v1": problems.append("missing/invalid header")
    if header.get("run_id") != run_id or header.get("role") != role: problems.append("identity mismatch")
    if not footer: problems.append("missing END / process did not drain")
    elif (footer.get("dropped") != 0 or footer.get("io_errors") != 0 or
          footer.get("written") != n or footer.get("produced") != n):
        problems.append("trace loss / writer failure / incomplete coverage")
    duration = ((end_time-start_time)/1e6) if start_time is not None and end_time is not None else 0
    if measure_started != 1 or measure_ended != 1: problems.append("missing/duplicate measurement boundaries")
    if duration < min_seconds: problems.append("insufficient measured duration")
    if len(samples["frame_ms"]) < max(10, min_seconds*10): problems.append("insufficient frame coverage")
    # Reject NaN/Inf in every numerical metric, not only frame times.
    if any(not math.isfinite(v) or v < 0 for values in samples.values() for v in values):
        problems.append("non-finite/negative metric")
    if local_profile and samples["frame_ms"]:
        if percentile(samples["frame_ms"], .99) > 25: failures.append("frame p99 >25ms")
        if percentile(samples["frame_ms"], .999) > 50: failures.append("frame p99.9 >50ms")
        if max(samples["frame_ms"]) > 100: failures.append("frame gap >100ms")
    tick_hz = None; dropped_delta = None
    if role == "server":
        if not first or not last or last.get("t_us",0) <= first.get("t_us",0):
            problems.append("missing server tick coverage")
        else:
            tick_hz = (last["tick"]-first["tick"])*1e6/(last["t_us"]-first["t_us"])
            dropped_delta = last["dropped_time_s"]-first["dropped_time_s"]
            if min(first.get("peers",0),last.get("peers",0))<2: failures.append("server does not have both clients")
            if last["rejections"]>first["rejections"]: failures.append("new server command rejections")
            if local_profile:
                if tick_hz<59: failures.append("simulation <59Hz")
                if dropped_delta>1e-6: failures.append("scheduler dropped time")
                if max_silence>100: failures.append("server loop gap >100ms")
                if max(samples["persistence_ms"],default=0)>50: failures.append("main-thread persistence >50ms")
    else:
        if counts.get("client_loop",0)<10 or counts.get("snapshot_received",0)<2:
            problems.append("missing live client/snapshot coverage")
        if client_state != "CONNECTED" or unexpected_states: failures.append("client not continuously connected in measured phase")
        if client_errors: failures.append("prediction reconcile failures")
        if counts.get("remote_visual",0)<10 or distance<.2: problems.append("no demonstrated remote movement")
        if backwards_holds: failures.append("backwards EXTRAPOLATE->HOLD jump")
    verdict = "INCONCLUSIVE" if problems else "FAIL" if failures else "PASS"
    return {"role":role,"verdict":verdict,"duration_s":duration,"problems":problems,
            "failures":failures,"metrics":{k:stats(v) for k,v in samples.items()},
            "snapshot_stage_metrics":{k:stats(v) for k,v in stage_samples.items()},
            "seam_messages_sent":seam_sent,"seam_unchanged_skipped":seam_skipped,
            "tick_hz":tick_hz,"dropped_time_delta_s":dropped_delta,
            "max_server_event_gap_ms":max_silence,"remote_distance_m":distance,
            "backwards_holds":backwards_holds,"counts":counts,"anomalies":anomalies}


def analyze_run(root: Path) -> dict[str, Any]:
    manifest = json.loads((root/"manifest.json").read_text(encoding="utf-8"))
    reports = [analyze_trace(root/role/"trace.jsonl",role,manifest["run_id"],
                            max(10,manifest["duration_s"]*.90), manifest["profile"]=="LOCAL",
                            manifest.get("checkpoint_mode"),
                            manifest.get("snapshot_stages_required", False))
               for role in ("server","a","b")]
    infrastructure = manifest.get("errors", [])
    if manifest.get("completed") is not True: infrastructure = infrastructure+["orchestrator incomplete"]
    if any(x != 0 for x in manifest.get("process_exit_codes",{}).values()): infrastructure += ["nonzero process exit"]
    verdict = "INCONCLUSIVE" if infrastructure or any(r["verdict"]=="INCONCLUSIVE" for r in reports) else (
        "FAIL" if any(r["verdict"]=="FAIL" for r in reports) else "PASS")
    # Headless evidence can be functional/perf diagnostics, never GUI acceptance.
    label = "GUI_LOCAL_CANDIDATE" if manifest["mode"]=="gui" and manifest["profile"]=="LOCAL" else "DIAGNOSTIC_ONLY"
    return {"schema":"dws.net_smooth.report.v1","run_id":manifest["run_id"],"verdict":verdict,
            "evidence_class":label,"independent_acceptance":False,"infrastructure":infrastructure,
            "functional_scenario": "PASS" if not infrastructure and all(r["remote_distance_m"]>.2 for r in reports if r["role"]!="server") else "INCONCLUSIVE",
            "processes":reports,"thresholds":{"frame_p99_ms":25,"frame_p999_ms":50,
            "max_frame_ms":100,"server_min_hz":59},"one_way_latency_measured":False}


def write_report(root: Path) -> dict[str, Any]:
    report = analyze_run(root)
    (root/"report.json").write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding="utf-8")
    rows=[f'# NET-SMOOTH1 — {report["verdict"]}',f'Evidence: {report["evidence_class"]}',
          'Implementer diagnostics; independent Windows acceptance is separate.','']
    for r in report['processes']:
        rows += [f'## {r["role"]}: {r["verdict"]}',
                 f'Duration: {r["duration_s"]:.2f}s; tick Hz: {r["tick_hz"]}',
                 f'Frame: {r["metrics"]["frame_ms"]}',
                 'Problems: '+ '; '.join(r['problems']+r['failures']), '']
    (root/"report.md").write_text('\n'.join(rows),encoding="utf-8")
    return report

if __name__ == "__main__":
    parser=argparse.ArgumentParser();parser.add_argument('root',type=Path)
    result=write_report(parser.parse_args().root)
    print(json.dumps({"verdict":result['verdict'],"evidence_class":result['evidence_class']}))
    raise SystemExit({"PASS":0,"FAIL":1,"INCONCLUSIVE":2}[result['verdict']])
