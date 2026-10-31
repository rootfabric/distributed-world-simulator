#!/usr/bin/env python3
"""NET-SMOOTH1 P1 tail forensics v2 — measured-window only, per-run.

Server: top 20 measured frames by interval_ms. Frame window = [t_prev_frame, t_frame].
Attributes window time to: r31p22 loop stages (joined by engine_frame), compact wire
stages, flush packets, server_message handlers, checkpoint events on any thread.
Client: top 20 measured frames with snapshots/compact stages in window.
"""
from __future__ import annotations

import bisect
import json
import sys
from pathlib import Path

BASE = Path(r"C:\distributed-world-simulator\work\ns1-p0-r22-20261024\artifacts\net-smooth1")
RUNS = ["r31p23r22-p0-pair1-off", "r31p23r22-p0-pair1-on",
        "r31p23r22-p0-pair2-off", "r31p23r22-p0-pair2-on",
        "r31p23r22-p0-pair3-off", "r31p23r22-p0-pair3-on"]
OUT = Path(__file__).resolve().parents[2] / "work" / "p1-forensics"
TOP = 20
STAGE_KEYS = ("postcommit_ms", "item_completion_ms", "movement_completion_ms",
              "deferred_disconnect_ms", "deferred_admission_ms", "boundary_poll_ms",
              "message_dispatch_ms", "fixed_simulation_ms", "snapshot_publication_ms",
              "movement_persistence_ms", "telemetry_ms")


def load(path: Path) -> list[dict]:
    rows = []
    with path.open(encoding="utf-8") as fh:
        for line in fh:
            r = json.loads(line)
            r["_t"] = r["t_us"]
            rows.append(r)
    return rows


def measured(rows: list[dict]) -> list[dict]:
    lo = hi = None
    for r in rows:
        if r["kind"] == "measure_start":
            lo = r["_t"]
        elif r["kind"] == "measure_end":
            hi = r["_t"]
    return [r for r in rows if lo is not None and hi is not None and lo <= r["_t"] <= hi]


def server_report(run: Path) -> dict:
    trace = measured(load(run / "server" / "trace.jsonl"))
    t0 = trace[0]["_t"]
    frames = [r for r in trace if r["kind"] == "frame"]
    frames.sort(key=lambda r: r["_t"])
    stages = {r["data"]["engine_frame"]: r["data"] for r in trace if r["kind"] == "r31p22_loop_stages"}
    wire = {r["data"]["engine_frame"]: r["data"] for r in trace if r["kind"] == "r31p22_compact_wire_stages"}
    snap = {r["data"]["engine_frame"]: r["data"] for r in trace if r["kind"] == "movement_snapshot_stages"}
    flush_by_frame: dict[int, list[dict]] = {}
    for r in trace:
        if r["kind"] == "r31p23r2_flush_packet":
            flush_by_frame.setdefault(r["data"].get("engine_frame"), []).append(r["data"])
    msgs_by_frame: dict[int, list[dict]] = {}
    for r in trace:
        if r["kind"] == "server_message":
            msgs_by_frame.setdefault(r["data"].get("engine_frame"), []).append(r["data"])
    aux_kinds = ("checkpoint_capture", "checkpoint_complete", "periodic_checkpoint_dispatch",
                 "r3c4_periodic_capture_slot", "r3c4_periodic_frame_deferred",
                 "durable_checkpoint_stages", "p1b_item_async_stages",
                 "r3c_admission_queued", "r3c_admission_drained")
    aux = sorted((r for r in trace if r["kind"] in aux_kinds), key=lambda r: r["_t"])
    aux_ts = [r["_t"] for r in aux]

    ft = [f["_t"] for f in frames]
    top = sorted(frames, key=lambda f: f["data"].get("interval_ms", 0), reverse=True)[:TOP]
    out = []
    for fr in top:
        i = bisect.bisect_left(ft, fr["_t"])
        tstart = ft[i - 1] if i > 0 else fr["_t"] - int(fr["data"]["interval_ms"] * 1000)
        tend = fr["_t"]
        fid = fr["data"]["engine_frame"]
        st = stages.get(fid, {})
        covered = sum(float(st.get(k, 0) or 0) for k in STAGE_KEYS)
        lo = bisect.bisect_left(aux_ts, tstart); hi = bisect.bisect_right(aux_ts, tend)
        in_win = {}
        for r in aux[lo:hi]:
            d = r["data"]
            slot = in_win.setdefault(r["kind"], {"count": 0, "detail": []})
            slot["count"] += 1
            if len(slot["detail"]) < 2:
                brief = {k: d.get(k) for k in ("generation", "capture_ms", "worker_ms", "write_ms",
                                               "elapsed_ms", "build_ms", "stage", "kind", "origin",
                                               "route", "deferred_frames", "forced", "deferral_ms",
                                               "precapture_work_ms", "persist_atomic_ms", "wait_async_ms")
                         if k in d}
                slot["detail"].append(brief)
        w = wire.get(fid, {})
        out.append({
            "engine_frame": fid, "interval_ms": fr["data"]["interval_ms"],
            "t_rel_start_ms": round((tstart - t0) / 1000, 1), "t_rel_end_ms": round((tend - t0) / 1000, 1),
            "engine_process_ms": fr["data"].get("engine_process_ms"),
            "loop_stages": {k: st.get(k) for k in STAGE_KEYS if k in st},
            "covered_sum_ms": round(covered, 2),
            "measured_stage_gap_ms": round(fr["data"]["interval_ms"] - covered, 2),
            "compact_wire": {k: w.get(k) for k in ("payload_clone_ms", "frame_create_ms",
                                                   "boundary_send_ms", "outbound_flush_ms", "total_ms") if k in w},
            "flush_packets": [{k: p.get(k) for k in ("channel", "port_call_ms", "queue_stage_ms",
                                                     "detached_frame_copy_ms", "delivery_mode", "attempt_number")}
                              for p in flush_by_frame.get(fid, [])],
            "snapshot_stage": {k: snap[fid].get(k) for k in ("capture_ms", "encode_ms", "compact_send_ms",
                                                             "send_and_seam_ms", "peers", "tick")
                               if fid in snap and k in snap[fid]},
            "messages": [{"type": m.get("type"), "duration_ms": m.get("duration_ms")}
                         for m in msgs_by_frame.get(fid, [])],
            "aux_in_window": in_win,
        })
    # biggest single message handlers in the whole measured window
    big_msgs = sorted((r["data"] for r in trace if r["kind"] == "server_message"),
                      key=lambda d: d.get("duration_ms", 0), reverse=True)[:8]
    big_snaps = sorted(({"engine_frame": r["data"].get("engine_frame"),
                         "compact_send_ms": r["data"].get("compact_send_ms"),
                         "send_and_seam_ms": r["data"].get("send_and_seam_ms"),
                         "tick": r["data"].get("tick")}
                        for r in trace if r["kind"] == "movement_snapshot_stages"),
                       key=lambda d: d.get("compact_send_ms") or 0, reverse=True)[:8]
    # largest loop-stage components across measured window
    comp_max: dict[str, float] = {}
    comp_p: dict[str, list[float]] = {}
    for st in stages.values():
        for k in STAGE_KEYS:
            v = float(st.get(k, 0) or 0)
            comp_max[k] = max(comp_max.get(k, 0), v)
            comp_p.setdefault(k, []).append(v)
    return {"top_frames": out, "biggest_messages": big_msgs, "biggest_compact_sends": big_snaps,
            "stage_max_ms": comp_max,
            "stage_p99_ms": {k: sorted(v)[max(0, int(len(v) * 0.99) - 1)] for k, v in comp_p.items()}}


def client_report(run: Path, role: str) -> dict:
    trace = measured(load(run / role / "trace.jsonl"))
    frames = sorted((r for r in trace if r["kind"] == "frame"), key=lambda r: r["_t"])
    snaps = sorted((r for r in trace if r["kind"] == "snapshot_received"), key=lambda r: r["_t"])
    comp = sorted((r for r in trace if r["kind"] == "compact_snapshot_stages"), key=lambda r: r["_t"])
    s_ts = [r["_t"] for r in snaps]; c_ts = [r["_t"] for r in comp]
    loops = {r["data"].get("state") for r in trace if r["kind"] == "client_loop"}
    sessions = sorted({r["data"].get("session") for r in trace if r["kind"] == "client_loop"})
    ft = [f["_t"] for f in frames]
    top = sorted(frames, key=lambda f: f["data"].get("interval_ms", 0), reverse=True)[:TOP]
    out = []
    for fr in top:
        i = bisect.bisect_left(ft, fr["_t"])
        tstart = ft[i - 1] if i > 0 else fr["_t"]
        tend = fr["_t"]
        lo = bisect.bisect_left(s_ts, tstart); hi = bisect.bisect_right(s_ts, tend)
        cl = bisect.bisect_left(c_ts, tstart); ch = bisect.bisect_right(c_ts, tend)
        out.append({"engine_frame": fr["data"].get("engine_frame"),
                    "interval_ms": fr["data"].get("interval_ms"),
                    "process_ms": fr["data"].get("engine_process_ms"),
                    "snap_ticks": [s["data"].get("tick") for s in snaps[lo:hi]],
                    "compact_stages": [{k: d.get(k) for k in ("tick", "decode_ms", "accept_ms",
                                                              "reconcile_ms", "presentation_ms")}
                                       for d in (r["data"] for r in comp[cl:ch])]})
    # snapshot inter-arrival gaps (measured)
    gaps = []
    for a, b in zip(snaps, snaps[1:]):
        gaps.append((round((b["_t"] - a["_t"]) / 1000, 1), b["data"].get("tick")))
    gaps.sort(reverse=True)
    return {"top_frames": out, "client_states": sorted(x for x in loops if x),
            "sessions": sessions, "top_snapshot_gaps_ms_tick": gaps[:8]}


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    for run_name in RUNS:
        run = BASE / run_name
        doc = {"run": run_name,
               "server": server_report(run),
               "a": client_report(run, "a"), "b": client_report(run, "b")}
        dest = OUT / f"{run_name}.forensics2.json"
        dest.write_text(json.dumps(doc, indent=1), encoding="utf-8")
        print("WROTE", dest, flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
