#!/usr/bin/env python3
import argparse
import json
import math
import re
from collections import defaultdict
from pathlib import Path


def read_jsonl(path: Path):
    rows = []
    if not path.exists():
        return rows
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            rows.append(value)
    return rows


def number(value, default=0.0):
    try:
        result = float(value)
    except (TypeError, ValueError):
        return default
    return result if math.isfinite(result) else default


def integer(value, default=0):
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def delta(last, first, key):
    return integer(last.get(key, 0)) - integer(first.get(key, 0))


def dict_delta(last, first):
    keys = set(first) | set(last)
    return {
        key: max(0.0, number(last.get(key, 0.0)) - number(first.get(key, 0.0)))
        for key in sorted(keys)
    }


def read_text(path: Path):
    if not path.exists():
        return ""
    return path.read_text(encoding="utf-8", errors="replace")


def summarize_phase(rows):
    first = rows[0]["jitter"]
    last = rows[-1]["jitter"]
    result = {
        "samples": len(rows),
        "first_at": rows[0].get("at", ""),
        "last_at": rows[-1].get("at", ""),
        "connection_state": last.get("connection_state", ""),
        "async_pending_final": integer(last.get("async_pending", 0)),
    }

    local_first = first.get("local", {}) if isinstance(first.get("local"), dict) else {}
    local_last = last.get("local", {}) if isinstance(last.get("local"), dict) else {}
    result["local"] = {
        "hard_corrections_delta": delta(local_last, local_first, "hard_corrections"),
        "history_miss_resets_delta": delta(local_last, local_first, "history_miss_resets"),
        "ticks_replayed_delta": delta(local_last, local_first, "ticks_replayed"),
        "maximum_error_m": number(local_last.get("maximum_error_m", 0.0)),
        "last_error_m": number(local_last.get("last_error_m", 0.0)),
        "correction_mode": local_last.get("correction_mode", ""),
        "submit_failures_delta": delta(local_last, local_first, "submit_failures"),
        "reconcile_failures_delta": delta(local_last, local_first, "reconcile_failures"),
    }

    remotes_first = first.get("remotes", {}) if isinstance(first.get("remotes"), dict) else {}
    remotes_last = last.get("remotes", {}) if isinstance(last.get("remotes"), dict) else {}
    remote_summary = {}
    for remote_id in sorted(set(remotes_first) | set(remotes_last)):
        rf = remotes_first.get(remote_id, {}) if isinstance(remotes_first.get(remote_id), dict) else {}
        rl = remotes_last.get(remote_id, {}) if isinstance(remotes_last.get(remote_id), dict) else {}
        mode_delta = dict_delta(
            rl.get("sample_mode_time_ms", {}) if isinstance(rl.get("sample_mode_time_ms"), dict) else {},
            rf.get("sample_mode_time_ms", {}) if isinstance(rf.get("sample_mode_time_ms"), dict) else {},
        )
        mode_total = sum(mode_delta.values())
        interpolate_ms = mode_delta.get("INTERPOLATE", 0.0)
        extrapolate_ms = mode_delta.get("EXTRAPOLATE", 0.0)
        hold_ms = sum(v for k, v in mode_delta.items() if "HOLD" in k or "SNAP_DISCONTINUITY" in k)
        buffering_ms = sum(v for k, v in mode_delta.items() if "BUFFER" in k)
        remote_summary[remote_id] = {
            "mode": rl.get("mode", ""),
            "buffer_size": integer(rl.get("buffer_size", 0)),
            "interpolation_samples_delta": delta(rl, rf, "interpolation_samples"),
            "extrapolation_samples_delta": delta(rl, rf, "extrapolation_samples"),
            "hold_samples_delta": delta(rl, rf, "hold_samples"),
            "buffering_samples_delta": delta(rl, rf, "buffering_samples"),
            "identity_resets_delta": delta(rl, rf, "identity_resets"),
            "teleport_segments_delta": delta(rl, rf, "teleport_segments"),
            "presenter_arrivals_delta": delta(rl, rf, "presenter_arrivals"),
            "accepted_presenter_samples_delta": delta(rl, rf, "accepted_presenter_samples"),
            "duplicate_presenter_samples_delta": delta(rl, rf, "duplicate_presenter_samples"),
            "stale_presenter_samples_delta": delta(rl, rf, "stale_presenter_samples"),
            "rejected_presenter_samples_delta": delta(rl, rf, "rejected_presenter_samples"),
            "max_presenter_arrival_interval_ms": integer(rl.get("max_presenter_arrival_interval_ms", 0)),
            "max_accepted_sample_interval_ms": integer(rl.get("max_accepted_sample_interval_ms", 0)),
            "max_snapshot_interval_ms": integer(rl.get("max_snapshot_interval_ms", 0)),
            "snapshot_clock_source": rl.get("snapshot_clock_source", ""),
            "snapshot_clock_context": rl.get("snapshot_clock_context", {}),
            "long_render_frames_delta": delta(rl, rf, "long_render_frames"),
            "max_render_delta_ms": number(rl.get("max_render_delta_ms", 0.0)),
            "mode_time_delta_ms": mode_delta,
            "mode_time_total_ms": mode_total,
            "interpolate_ratio": interpolate_ms / mode_total if mode_total else 0.0,
            "extrapolate_ratio": extrapolate_ms / mode_total if mode_total else 0.0,
            "hold_ratio": hold_ms / mode_total if mode_total else 0.0,
            "buffering_ratio": buffering_ms / mode_total if mode_total else 0.0,
        }
    result["remotes"] = remote_summary
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("session", type=Path)
    args = parser.parse_args()
    session = args.session.resolve()
    jitter_path = session / "jitter-samples.jsonl"
    rows = read_jsonl(jitter_path)

    grouped = defaultdict(list)
    for row in rows:
        if not isinstance(row.get("jitter"), dict):
            continue
        grouped[(str(row.get("label", "")), str(row.get("client", "")))].append(row)

    phases = {}
    for (label, client), group in sorted(grouped.items()):
        phases[f"{label}|{client}"] = summarize_phase(group)

    server_log = read_text(session / "server.log")
    client_a_log = read_text(session / "client-a.log")
    client_b_log = read_text(session / "client-b.log")
    all_client_logs = client_a_log + "\n" + client_b_log

    events = {
        "server_pump_stall": len(re.findall(r"SERVER_PUMP_STALL", server_log)),
        "server_pump_hard_stall": len(re.findall(r"SERVER_PUMP_HARD_STALL", server_log)),
        "physical_delivery_mode_mismatch": len(re.findall(r"PHYSICAL_DELIVERY_MODE_MISMATCH", server_log + all_client_logs)),
        "input_queue_full": len(re.findall(r"INPUT_QUEUE_FULL", server_log + all_client_logs)),
        "async_command_rejected": len(re.findall(r"ASYNC_COMMAND_REJECTED", all_client_logs)),
        "peer_local_quarantine": len(re.findall(r"PEER_LOCAL_QUARANTINE", server_log + all_client_logs)),
        "script_errors": len(re.findall(r"SCRIPT ERROR:|Parse Error:|Compile Error:", server_log + all_client_logs)),
    }

    movement_phase_keys = [
        key for key in phases
        if any(token in key for token in ("forward", "zig", "post-reconnect"))
    ]
    max_hold_ratio = 0.0
    max_render_delta = 0.0
    max_presenter_gap = 0
    max_accepted_gap = 0
    hard_delta = 0
    miss_delta = 0
    clock_sources = set()

    for key in movement_phase_keys:
        phase = phases[key]
        local = phase.get("local", {})
        hard_delta += integer(local.get("hard_corrections_delta", 0))
        miss_delta += integer(local.get("history_miss_resets_delta", 0))
        for remote in phase.get("remotes", {}).values():
            max_hold_ratio = max(max_hold_ratio, number(remote.get("hold_ratio", 0.0)))
            max_render_delta = max(max_render_delta, number(remote.get("max_render_delta_ms", 0.0)))
            max_presenter_gap = max(max_presenter_gap, integer(remote.get("max_presenter_arrival_interval_ms", 0)))
            max_accepted_gap = max(max_accepted_gap, integer(remote.get("max_accepted_sample_interval_ms", 0)))
            source = str(remote.get("snapshot_clock_source", ""))
            if source:
                clock_sources.add(source)

    findings = []
    if clock_sources and clock_sources != {"CANONICAL_SNAPSHOT_CONTEXT"}:
        findings.append("NON_CANONICAL_SNAPSHOT_CLOCK")
    if max_hold_ratio > 0.25:
        findings.append("REMOTE_HOLD_MAJOR")
    elif max_hold_ratio > 0.05:
        findings.append("REMOTE_HOLD_NOTABLE")
    if max_presenter_gap > 1000:
        findings.append("PRESENTER_ARRIVAL_GAP_SEVERE")
    elif max_presenter_gap > 250:
        findings.append("PRESENTER_ARRIVAL_GAP")
    if max_accepted_gap > 1000:
        findings.append("ACCEPTED_SAMPLE_GAP_SEVERE")
    elif max_accepted_gap > 250:
        findings.append("ACCEPTED_SAMPLE_GAP")
    if max_render_delta > 100:
        findings.append("RENDER_STALL_SEVERE")
    elif max_render_delta > 50:
        findings.append("RENDER_STALL_NOTABLE")
    if hard_delta > 0:
        findings.append("LOCAL_HARD_CORRECTIONS")
    if miss_delta > 0:
        findings.append("LOCAL_HISTORY_MISS_RESETS")
    if events["server_pump_hard_stall"] > 0:
        findings.append("SERVER_HARD_STALL")
    elif events["server_pump_stall"] > 0:
        findings.append("SERVER_SOFT_STALL")
    if events["physical_delivery_mode_mismatch"] > 0:
        findings.append("PHYSICAL_DELIVERY_MODE_MISMATCH")
    if events["input_queue_full"] > 0:
        findings.append("INPUT_QUEUE_FULL")

    report = {
        "schema": "dws.live2.r3_4.autonomous_lag_analysis.v1",
        "session": str(session),
        "jitter_samples": len(rows),
        "movement_phase_count": len(movement_phase_keys),
        "phases": phases,
        "events": events,
        "summary": {
            "max_remote_hold_ratio": max_hold_ratio,
            "max_render_delta_ms": max_render_delta,
            "max_presenter_arrival_interval_ms": max_presenter_gap,
            "max_accepted_sample_interval_ms": max_accepted_gap,
            "local_hard_corrections_delta": hard_delta,
            "local_history_miss_resets_delta": miss_delta,
            "snapshot_clock_sources": sorted(clock_sources),
            "findings": findings,
        },
    }

    json_path = session / "AUTONOMOUS-LAG-ANALYSIS.json"
    json_path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")

    md = [
        "# LIVE.2 R3.4 Autonomous Lag Analysis",
        "",
        f"- Jitter samples: {len(rows)}",
        f"- Movement phases: {len(movement_phase_keys)}",
        f"- Max remote HOLD ratio: {max_hold_ratio:.3f}",
        f"- Max presenter arrival interval: {max_presenter_gap} ms",
        f"- Max accepted sample interval: {max_accepted_gap} ms",
        f"- Max render delta: {max_render_delta:.1f} ms",
        f"- Local hard corrections delta: {hard_delta}",
        f"- Local history miss resets delta: {miss_delta}",
        f"- Snapshot clock sources: {', '.join(sorted(clock_sources)) or 'none'}",
        "",
        "## Findings",
        "",
    ]
    if findings:
        md.extend(f"- {finding}" for finding in findings)
    else:
        md.append("- No threshold finding in the bounded autonomous movement phases.")
    md.extend([
        "",
        "## Event counts",
        "",
    ])
    md.extend(f"- {key}: {value}" for key, value in events.items())
    (session / "AUTONOMOUS-LAG-ANALYSIS.md").write_text("\n".join(md) + "\n", encoding="utf-8")

    print(json.dumps(report["summary"], indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
