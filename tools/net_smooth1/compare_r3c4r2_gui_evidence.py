#!/usr/bin/env python3
"""Read-only paired GUI evidence reducer for NET-SMOOTH1 R3C.4 R2 (#787).

This does not replace analyze_net_smooth1.py, alter normative thresholds,
perform Windows tests, or grant independent merge acceptance.
Expected directories: gui-off-1..3 and gui-on-1..3 under --root.
"""
from __future__ import annotations

import argparse
import json
import math
import statistics
from pathlib import Path

EXPECTED_HEAD = "f64fed2430f1292773d1561f881e5c8a4cc89075"
EXPECTED_TREE = "01731ee75418c58c2f2d2e16fb39d29b9a167def"
EXPECTED_GODOT_SHA = "3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5"
PERF_FAILURES = (
    "frame p99 >25ms", "frame p99.9 >50ms", "frame gap >100ms",
    "simulation <59Hz", "scheduler dropped time",
    "server loop gap >100ms", "main-thread persistence >50ms",
)
STAGES = {
    "checkpoint_capture": ("capture_ms", "quiesce_ms", "authority_ms", "replay_ms", "handoff_ms"),
    "checkpoint_complete": ("wrap_ms", "build_ms", "write_ms", "worker_ms"),
}


def percentile(values: list[float], q: float) -> float | None:
    if not values:
        return None
    a = sorted(values)
    return a[min(len(a) - 1, math.ceil(q * len(a)) - 1)]


def number(value: object) -> float:
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        raise ValueError(f"not a number: {value!r}")
    result = float(value)
    if not math.isfinite(result) or result < 0:
        raise ValueError(f"invalid timing: {value!r}")
    return result


def stage_metrics(trace: Path, is_on: bool) -> dict:
    timings = {key: [] for fields in STAGES.values() for key in fields}
    counts = {kind: 0 for kind in STAGES}
    with trace.open(encoding="utf-8") as stream:
        for line in stream:
            row = json.loads(line)
            if not row.get("measure", False) or row.get("kind") not in STAGES:
                continue
            kind = row["kind"]
            data = row.get("data", {})
            if not isinstance(data, dict):
                raise ValueError("invalid stage record data")
            if kind == "checkpoint_capture" and data.get("r3c4r2_worker_envelope") is not is_on:
                raise ValueError("R2 flag in checkpoint capture differs from paired arm")
            counts[kind] += 1
            for field in STAGES[kind]:
                if field in data:
                    timings[field].append(number(data[field]))
                elif field == "wrap_ms" and is_on:
                    raise ValueError("R2 worker wrap_ms missing")
    if any(count == 0 for count in counts.values()):
        raise ValueError(f"missing measured checkpoint capture/completion: {counts}")
    return {
        "counts": counts,
        "timings": {field: {"count": len(values), "p50": percentile(values, .5),
                           "p99": percentile(values, .99), "max": max(values, default=None)}
                    for field, values in timings.items()},
    }


def inspect_run(path: Path, arm: str, idx: int) -> dict:
    entry = {"name": path.name, "arm": arm, "pair": idx, "problems": [],
             "functional_failures": [], "perf_failures": [], "metrics": {}, "stages": {}}
    try:
        manifest = json.loads((path / "manifest.json").read_text(encoding="utf-8"))
        report = json.loads((path / "report.json").read_text(encoding="utf-8"))
        ident = manifest["identity"]
        expected_r2 = arm == "on"
        expected = {
            "head": EXPECTED_HEAD, "tree": EXPECTED_TREE,
            "godot_sha256": EXPECTED_GODOT_SHA,
        }
        for key, value in expected.items():
            if str(ident.get(key, "")).lower() != value:
                entry["problems"].append(f"wrong {key}: {ident.get(key)!r}")
        if ident.get("tracked_dirty") is not False:
            entry["problems"].append("tracked tree not clean")
        if not str(ident.get("godot_version", "")).startswith("4.7.1.stable.double.custom_build.a13da4feb"):
            entry["problems"].append("incorrect pinned Godot double version")
        if "Windows" not in str(ident.get("platform", "")):
            entry["problems"].append("not a Windows run")
        if int(ident.get("asset_count", 0)) < 220:
            entry["problems"].append("Quaternius asset gate (<220 files)")
        entry["assets_sha256"] = ident.get("asset_manifest_sha256", "")
        if manifest.get("mode") != "gui" or manifest.get("profile") != "LOCAL":
            entry["problems"].append("not a real GUI LOCAL run")
        if manifest.get("scenario") != "r31-reconnect-roundtrip":
            entry["problems"].append("wrong GUI scenario")
        if number(manifest.get("duration_s", 0)) < 120:
            entry["problems"].append("requested measurement duration <120s")
        for key, value in (("r3c4_periodic_frame_pacing", True),
                           ("r3c4r2_worker_envelope", expected_r2),
                           ("r3c_async_admission", True),
                           ("r3c2_avatar_prewarm", True),
                           ("r3c2_server_phased", True),
                           ("r3c3_staged_earth", True),
                           ("r3c21_frame_paced_presentation", True)):
            if manifest.get(key) is not value:
                entry["problems"].append(f"incorrect mode {key}={manifest.get(key)!r}")
        if manifest.get("completed") is not True or manifest.get("errors"):
            entry["problems"].append(f"orchestrator incomplete/errors: {manifest.get('errors')}")
        codes = manifest.get("process_exit_codes", {})
        if set(codes) != {"server", "a", "b"} or any(v != 0 for v in codes.values()):
            entry["problems"].append(f"nonzero/missing process exit codes: {codes}")
        if report.get("evidence_class") != "GUI_LOCAL_CANDIDATE":
            entry["problems"].append("wrong evidence class")
        if not any(x.get("phase") == "r31_reconnect_roundtrip"
                   for x in manifest.get("phase_results", [])):
            entry["functional_failures"].append("missing R31 authoritative roundtrip")
        if not (path / "r31-roundtrip.json").is_file():
            entry["functional_failures"].append("missing R31 roundtrip evidence")
        if report.get("functional_scenario") != "PASS":
            entry["functional_failures"].append("functional_scenario != PASS")
        processes = {x["role"]: x for x in report["processes"]}
        if set(processes) != {"server", "a", "b"}:
            raise ValueError(f"incomplete process roles: {list(processes)}")
        for role, item in processes.items():
            if item.get("problems") or item.get("verdict") == "INCONCLUSIVE":
                entry["problems"].append(f"{role} trace invalid: {item.get('problems')}")
            for failure in item.get("failures", []):
                bucket = "perf_failures" if failure in PERF_FAILURES else "functional_failures"
                entry[bucket].append(f"{role}: {failure}")
            if number(item.get("duration_s", 0)) < 118:
                entry["problems"].append(f"{role}: short measured interval")
            metrics = item["metrics"]["frame_ms"]
            frames = {key: number(metrics[key]) for key in ("p99", "p999", "max")}
            entry["metrics"][role] = {**frames, "tick_hz": item.get("tick_hz")}
            if frames["p99"] > 25 or frames["p999"] > 50 or frames["max"] > 100:
                entry["perf_failures"].append(f"{role}: independent frame thresholds")
            if role == "server":
                if item.get("tick_hz") is None or number(item["tick_hz"]) < 59:
                    entry["perf_failures"].append("server: simulation <59Hz")
                if number(item.get("dropped_time_delta_s") or 0) > 0:
                    entry["perf_failures"].append("server: scheduler dropped time")
                if item.get("durable_stage_failures", 0):
                    entry["functional_failures"].append("server: durable stage failures")
        for role in ("a", "b"):
            screenshot = path / role / "screenshot.json"
            avatar_file = path / role / "avatar-status.json"
            if not screenshot.is_file() or not avatar_file.is_file():
                entry["problems"].append(f"{role}: GUI screenshot/avatar evidence missing")
                continue
            avatar = json.loads(avatar_file.read_text(encoding="utf-8"))
            details = avatar.get("details", {})
            remote = list(details.get("remote_players", {}).values())
            if (len(remote) != 1 or remote[0].get("provider_id") != "avatar/quaternius"
                    or remote[0].get("asset_mode") != "QUATERNIUS_RETARGET"
                    or remote[0].get("ready") is not True
                    or remote[0].get("legacy_capsule_visible") is not False):
                entry["functional_failures"].append(f"{role}: fallback/nonready Quaternius avatar")
        for role in ("server", "a", "b"):
            if not (path / role / "trace.jsonl").is_file():
                entry["problems"].append(f"{role}: trace missing")
            if not (path / role / "runtime.log").is_file():
                entry["problems"].append(f"{role}: runtime log missing")
        entry["stages"] = stage_metrics(path / "server" / "trace.jsonl", expected_r2)
        if entry["problems"]:
            entry["status"] = "INCONCLUSIVE"
        elif entry["functional_failures"]:
            entry["status"] = "FUNCTIONAL_FAIL"
        elif entry["perf_failures"]:
            entry["status"] = "PERF_FAIL"
        else:
            entry["status"] = "GUI_PERF_GATE_PASS_ONLY"
    except (OSError, KeyError, IndexError, TypeError, ValueError, json.JSONDecodeError) as exc:
        entry["problems"].append(f"{type(exc).__name__}: {exc}")
        entry["status"] = "INCONCLUSIVE"
    return entry


def textnum(n: float | None) -> str:
    return "n/a" if n is None else f"{n:.2f}"


def make_markdown(runs: list[dict], verdict: str) -> str:
    byname = {r["name"]: r for r in runs}
    lines = ["# NET-SMOOTH1 R3C.4 R2 — paired GUI evidence", "",
             f"**Result: {verdict} / NO_MERGE (external independent acceptance still required)**",
             "", "Pinned: #787 " + EXPECTED_HEAD + " / tree " + EXPECTED_TREE,
             "", "| Pair | OFF p99 ms | ON p99 ms | Δ ON−OFF ms | OFF status | ON status |",
             "|---|---:|---:|---:|---|---|"]
    for i in range(1, 4):
        off, on = byname[f"gui-off-{i}"], byname[f"gui-on-{i}"]
        op = off["metrics"].get("server", {}).get("p99")
        np = on["metrics"].get("server", {}).get("p99")
        diff = (np-op) if op is not None and np is not None else None
        lines.append(f"| {i} | {textnum(op)} | {textnum(np)} | {textnum(diff)} | {off['status']} | {on['status']} |")
    lines += ["", "| Arm | authority p50 ms | handoff p50 ms | worker wrap p50 ms | write p50 ms |",
              "|---|---:|---:|---:|---:|"]
    for arm in ("off", "on"):
        for i in range(1, 4):
            r = byname[f"gui-{arm}-{i}"]
            t = r["stages"].get("timings", {})
            values = [t.get(field, {}).get("p50") for field in
                      ("authority_ms", "handoff_ms", "wrap_ms", "write_ms")]
            lines.append(f"| {arm} {i} | " + " | ".join(map(textnum, values)) + " |")
    lines += ["", "## Invalid runs or failures"]
    for r in runs:
        notes = r["problems"] + r["functional_failures"] + r["perf_failures"]
        lines.append(f"- **{r['name']} [{r['status']}]**: " +
                     ("; ".join(notes) if notes else "no recorded violations"))
    lines += ["", "Analyzer is unchanged; GUI comparison cannot certify crash/replay, slow ITEM,",
              "Project Control or independent merge acceptance. Raw traces and manifests remain mandatory.", ""]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path,
                        help="Directory containing gui-off-1..3 and gui-on-1..3")
    args = parser.parse_args()
    root = args.root.resolve()
    runs = [inspect_run(root / f"gui-{arm}-{i}", arm, i)
            for i in range(1, 4) for arm in ("off", "on")]
    assets = {r.get("assets_sha256") for r in runs if r.get("assets_sha256")}
    if len(assets) != 1:
        for r in runs:
            r["problems"].append("asset manifest inconsistent across six runs")
            r["status"] = "INCONCLUSIVE"
    on = [r for r in runs if r["arm"] == "on"]
    if any(r["status"] == "INCONCLUSIVE" for r in runs):
        verdict, code = "INCONCLUSIVE", 2
    elif any(r["status"] == "FUNCTIONAL_FAIL" for r in runs):
        verdict, code = "FUNCTIONAL_FAIL", 3
    elif any(r["status"] == "PERF_FAIL" for r in on):
        verdict, code = "PERF_FAIL", 1
    else:
        verdict, code = "GUI_PERF_GATE_PASS_ONLY", 0
    result = {
        "schema": "dws.net_smooth.r3c4r2.paired_gui_review.v1",
        "exact_head": EXPECTED_HEAD, "exact_tree": EXPECTED_TREE,
        "verdict": verdict, "no_merge": True, "runs": runs,
    }
    root.mkdir(parents=True, exist_ok=True)
    (root / "comparison.json").write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf-8")
    (root / "comparison.md").write_text(make_markdown(runs, verdict), encoding="utf-8")
    print(f"{verdict} / NO_MERGE; {root / 'comparison.md'}")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
