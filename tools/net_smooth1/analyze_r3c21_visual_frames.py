#!/usr/bin/env python3
"""R3C3 R2.1: per-client first-visible-frame attribution from raw trace files.

Diagnostic only. A successful report NEVER overrides analyze_net_smooth1.py,
or the 25/50/100ms client, 59Hz server, and exact M6 durability gates.
"""
from __future__ import annotations
import argparse
from collections import defaultdict
import json
import math
from pathlib import Path


KINDS = {
    "frame",
    "r3c21_first_visible_frame",
    "r3c21_preattach_slice",
    "r3c3r2_visual_commit",
    "r3c2_client_connect_attach",
    "r3c2_join_ack_breakdown",
    "r3c3r2_vegetation_cpu_slice",
    "r3c3r2_gpu_upload_slice",
}
FIELDS_MS = {
    "frame": ("interval_ms",),
    "r3c21_first_visible_frame": ("frame_gap_ms",),
    "r3c21_preattach_slice": ("elapsed_us",),
    "r3c3r2_visual_commit": ("commit_ms", "mesh_upload_ms", "cpu_slice_max_ms", "verify_ms"),
    "r3c2_client_connect_attach": ("attach_ms", "total_ms"),
    "r3c2_join_ack_breakdown": ("total_ms", "session_ready_signal_ms"),
    "r3c3r2_vegetation_cpu_slice": ("elapsed_us",),
    "r3c3r2_gpu_upload_slice": ("elapsed_us",),
}


def stats(samples: list[float]) -> dict:
    ordered = sorted(samples)
    def p(q: float):
        return ordered[max(0, min(len(ordered)-1, math.ceil(len(ordered)*q)-1))] if ordered else None
    return {"count": len(ordered), "p50": p(.5), "p95": p(.95),
            "p99": p(.99), "p999": p(.999), "max": max(ordered, default=None)}


def inspect(path: Path, role: str, run_id: str) -> dict:
    stages: dict[str, dict[str, list[float]]] = defaultdict(lambda: defaultdict(list))
    commits = []
    first_visible = []
    previous_us = -1
    sequence = 0
    header = None
    footer = None
    with path.open(encoding="utf-8") as f:
        for line_num, line in enumerate(f, 1):
            if len(line) > 1024*1024:
                raise ValueError(f"{role}: oversized trace row {line_num}")
            e = json.loads(line)
            if not isinstance(e, dict) or not isinstance(e.get("data"), dict):
                raise ValueError(f"{role}: invalid row {line_num}")
            now = e.get("t_us")
            if not isinstance(now, (float, int)) or not math.isfinite(now) or now < previous_us:
                raise ValueError(f"{role}: invalid monotonic clock {line_num}")
            previous_us = now
            k = e.get("kind")
            data = e["data"]
            if k == "end":
                if footer is not None:
                    raise ValueError(f"{role}: duplicate END")
                footer = data
                continue
            if footer is not None:
                raise ValueError(f"{role}: records after END")
            sequence += 1
            if e.get("n") != sequence:
                raise ValueError(f"{role}: lost sequence")
            if k == "header":
                if header is not None or sequence != 1:
                    raise ValueError(f"{role}: invalid header")
                header = data
            if k not in KINDS:
                continue
            for field in FIELDS_MS[k]:
                if field not in data:
                    continue
                v = data[field]
                if type(v) not in (float, int) or not math.isfinite(v) or v < 0:
                    raise ValueError(f"{role}: non-finite/negative {k}.{field}")
                stages[k][field].append(v/1000 if field == "elapsed_us" else float(v))
            if k == "r3c3r2_visual_commit":
                commits.append({"t_us": now, "token": data.get("token"),
                                "ms": data.get("commit_ms")})
            if k == "r3c21_first_visible_frame":
                first_visible.append({"t_us": now, "token": data.get("token"),
                                      "gap_ms": data.get("frame_gap_ms")})
    if not header or header.get("role") != role or header.get("run_id") != run_id:
        raise ValueError(f"{role}: incorrect trace header")
    if not footer:
        raise ValueError(f"{role}: missing END")
    if footer.get("dropped") != 0 or footer.get("io_errors") != 0:
        raise ValueError(f"{role}: trace dropped/error")
    if footer.get("produced") != sequence or footer.get("written") != sequence:
        raise ValueError(f"{role}: incomplete trace")
    # The first eight process frames after each committed visual form the
    # attribution window; never compare monotonic timestamps across clients.
    committed_tokens = {row["token"] for row in commits}
    if any(row["token"] not in committed_tokens for row in first_visible):
        raise ValueError(f"{role}: unbound first-visible token")
    maxima = [row["gap_ms"] for row in first_visible]
    if any(type(x) not in (int, float) or not math.isfinite(x) or x < 0 for x in maxima):
        raise ValueError(f"{role}: invalid first-visible frame")
    return {
        "role": role,
        "counts": {kind: len(rows[next(iter(rows))]) for kind, rows in stages.items() if rows},
        "stages_ms": {kind: {field: stats(values) for field, values in fields.items()}
                      for kind, fields in stages.items()},
        "committed_visual_tokens": sorted(committed_tokens),
        "postcommit_frame_gap_ms": stats(maxima),
        "postcommit_over_100ms": sum(v > 100.0 for v in maxima),
        "postcommit_over_50ms": sum(v > 50.0 for v in maxima),
        "diagnostic_only": True,
    }


def analyze(root: Path) -> dict:
    manifest = json.loads((root/"manifest.json").read_text(encoding="utf-8"))
    if manifest.get("completed") is not True:
        raise ValueError("orchestrator incomplete")
    run_id = manifest.get("run_id")
    if not isinstance(run_id, str) or not run_id:
        raise ValueError("missing run_id")
    if not manifest.get("r3c21_frame_paced_presentation"):
        raise ValueError("R2.1 candidate not enabled in manifest")
    clients = {role: inspect(root/role/"trace.jsonl", role, run_id) for role in ("a", "b")}
    return {
        "schema": "dws.net_smooth.r3c21_client_frame_diagnostics.v1",
        "evidence_class": "DIAGNOSTIC_ONLY_NOT_ACCEPTANCE",
        "run_id": run_id,
        "clients": clients,
        "normative_acceptance": "tools/net_smooth1/analyze_net_smooth1.py",
        "acceptance_bypass": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("run_root", type=Path)
    args = parser.parse_args()
    try:
        report = analyze(args.run_root)
    except (ValueError, KeyError, TypeError, OSError, OverflowError) as exc:
        print("R3C21 INCONCLUSIVE:", exc)
        return 2
    out = args.run_root / "r3c21-visual-frame-diagnostics.json"
    out.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
