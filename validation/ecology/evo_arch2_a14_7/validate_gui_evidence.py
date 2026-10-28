#!/usr/bin/env python3
"""A14.7 R1 fail-closed validator: only REAL drawable native GUI results pass.

Headless fallback, spoofed percentiles, no camera input, missing actual GPU
draw calls, absent full serialized sample set or skipped populations fail.
p99/CPU debt are *observations*, not an asserted SLA.
"""
import argparse
import json
import math
import pathlib
import sys

SCHEMA = "dws.ecology.a14-7-r1-native-gui-soak.v1"
EXPECTED_FIRST = {
    4: "7b56b22193534e2a77c33be3e02b1cb33fc37f189e6d68b4b1535a548fc06062",
    32: "62128cea01410626cfda7556c39afb2ae110606cee229a875476143a240ed129",
    96: "23b11ab4c0454d08de1e82b93a1a5913a2bed4116e29dc2f6bcc2bb448",
    256: "f38c44896ffc8028c00b1c1f74e5b99d41f12620d60f99f7a95690b3f6419906",
}
# Correct the fixed reference to the full accepted R3.2.3 96-pop hash.
EXPECTED_FIRST[96] = "23b11ab4c0454d08de1e82b93a1a5913a2bed4116e29dc2f6bcc765cfd2bb448"
SOFTWARE = ("llvmpipe", "softpipe", "swiftshader", "microsoft basic render",
            "gdi generic", "software rasterizer")


def rank(values, q):
    return sorted(values)[math.ceil(q * len(values)) - 1] / 1000.0


def validate(profile, expected_population=None, require_hardware=True):
    errors = []
    def require(test, message):
        if not test:
            errors.append(message)
    p = profile
    pop = p.get("population")
    require(p.get("schema") == SCHEMA and p.get("mode") == "native-gui", "GUI_SCHEMA")
    require(pop in EXPECTED_FIRST and (expected_population is None or pop == expected_population), "POPULATION")
    require(p.get("drawable_window") is True, "DRAWABLE_WINDOW")
    require(p.get("rendering_display") not in ("", "headless", None), "NOT_HEADLESS")
    adapter = str(p.get("rendering_adapter", ""))
    require(bool(adapter.strip()), "RENDERER_ADAPTER")
    if require_hardware:
        require(not any(token in adapter.lower() for token in SOFTWARE), "NOT_SOFTWARE_RENDERER")
        require(p.get("renderer_real_gpu_claim") is True, "HARDWARE_CLAIM")
    require(p.get("p3_p6_actual_lab_scene") is True, "REAL_LAB_SCENE")
    require(p.get("renderer_draw_calls_peak", 0) > 0, "ACTUAL_DRAWCALLS")
    require(p.get("completed") is True and p.get("timed_out") is False, "SOAK_COMPLETION")
    require(p.get("failed") == 0 and not p.get("errors"), "FALSIFIER_FAILURE")
    require(p.get("hard_frame_deadline_claim") is False and
            p.get("production_activation_claim") is False, "UNSUPPORTED_CLAIM")
    require(p.get("sample_single_run") is True, "SAMPLE_PROVENANCE")
    require(p.get("requested_ticks", 0) >= 1 and
            p.get("committed_ticks") == p.get("requested_ticks"), "TICK_COUNT")
    input_data = p.get("real_input", {})
    require(input_data.get("camera_moved") is True and
            input_data.get("mouse_received", 0) >= 10 and
            input_data.get("key_received", 0) >= 4 and
            input_data.get("received", 0) > 0, "REAL_INPUT")
    require(p.get("max_backlog_ticks", -1) >= 0 and
            p.get("last_backlog_ticks", -1) >= 0, "BACKLOG_RECEIPT")
    deliveries = p.get("completed_visual_snapshots", [])
    ticks = p.get("requested_ticks", 0)
    require([x.get("tick") for x in deliveries] == list(range(1, ticks + 1)),
            "SINGLE_ORDERED_SNAPSHOT_PER_TICK")
    if pop in EXPECTED_FIRST:
        require(p.get("first_tick_hash") == EXPECTED_FIRST[pop], "CANONICAL_FIRST_TICK")
    require(isinstance(p.get("canonical_hash"), str) and
            len(p.get("canonical_hash", "")) == 64, "FINAL_CANONICAL_HASH")
    require(p.get("a8_checkpoint_hash") == p.get("canonical_hash"), "A8_CHECKPOINT_HASH")
    mem = p.get("static_memory_bytes", {})
    require(all(isinstance(mem.get(k), int) and mem.get(k) >= 0
                for k in ("first", "peak", "last")), "STATIC_MEMORY")
    if all(isinstance(mem.get(k), int) for k in ("first", "peak", "last", "delta")):
        require(mem["peak"] >= mem["first"] and mem["peak"] >= mem["last"] and
                mem["last"] - mem["first"] == mem["delta"], "MEMORY_DELTA")
    rows = p.get("frame_samples", [])
    require(isinstance(rows, list) and len(rows) >= 240 and
            len(rows) == p.get("frames"), "FRAME_SAMPLES_COMPLETE")
    if len(rows) >= 240:
        vals = [x.get("interval_us", 0) for x in rows]
        require(all(isinstance(x, int) and x > 0 for x in vals), "FRAME_INTERVAL_VALUES")
        require([x.get("frame") for x in rows] == list(range(len(rows))), "FRAME_MONOTONIC_INDEX")
        if all(isinstance(x, int) and x > 0 for x in vals):
            declared = p.get("frame_interval_ms", {})
            for key, q in (("p50", 0.50), ("p95", 0.95), ("p99", 0.99)):
                require(isinstance(declared.get(key), (int, float)) and
                        math.isclose(declared[key], rank(vals, q), abs_tol=0.002),
                        "PERCENTILE_" + key.upper())
            require(math.isclose(declared.get("max", -1), max(vals) / 1000.0,
                                 abs_tol=0.002), "PEAK_FRAME_WALL")
            require(declared.get("p50", -1) <= declared.get("p95", -2) <=
                    declared.get("p99", -3) <= declared.get("max", -4), "PERCENTILE_ORDER")
            require(p.get("frame_over_50ms") ==
                    sum(v > 50000 for v in vals), "JANK_COUNT")
            require(math.isclose(p.get("frame_under_25ms_ratio", -1),
                sum(v <= 25000 for v in vals) / len(vals), abs_tol=0.00001),
                "UNDER_25MS_RATIO")
    return errors


def selftest():
    ticks = 2
    row = {"frame": 0, "elapsed_ms": 10, "interval_us": 16000,
           "canonical_tick": 0, "ui_pending": False, "debt_ticks": 0, "draw_calls": 17}
    rows = [{**row, "frame": i, "elapsed_ms": 16 * (i + 1)} for i in range(240)]
    good = {"schema": SCHEMA, "mode": "native-gui", "population": 4,
        "drawable_window": True, "rendering_display": "windows",
        "rendering_adapter": "NVIDIA RTX", "renderer_real_gpu_claim": True,
        "p3_p6_actual_lab_scene": True, "renderer_draw_calls_peak": 17,
        "completed": True, "timed_out": False, "failed": 0, "errors": [],
        "hard_frame_deadline_claim": False, "production_activation_claim": False,
        "sample_single_run": True, "requested_ticks": ticks, "committed_ticks": ticks,
        "real_input": {"camera_moved": True, "mouse_received": 20, "key_received": 5, "received": 25},
        "max_backlog_ticks": 0, "last_backlog_ticks": 0,
        "completed_visual_snapshots": [{"tick": 1}, {"tick": 2}],
        "first_tick_hash": EXPECTED_FIRST[4],
        "canonical_hash": EXPECTED_FIRST[4], "a8_checkpoint_hash": EXPECTED_FIRST[4],
        "static_memory_bytes": {"first": 1, "peak": 2, "last": 1, "delta": 0},
        "frame_samples": rows, "frames": len(rows),
        "frame_interval_ms": {"p50": 16.0, "p95": 16.0, "p99": 16.0, "max": 16.0},
        "frame_over_50ms": 0, "frame_under_25ms_ratio": 1.0}
    assert not validate(good, 4), validate(good, 4)
    for mutation in [
        {"rendering_display": "headless"},
        {"renderer_draw_calls_peak": 0},
        {"frame_interval_ms": {**good["frame_interval_ms"], "p99": 0.5}},
        {"first_tick_hash": "a" * 64},
        {"completed": False},
        {"renderer_real_gpu_claim": False},
    ]:
        bad = {**good, **mutation}
        assert validate(bad, 4), mutation
    print("A147_R1_VALIDATOR_SELFTEST_PASS")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("reports", nargs="*", type=pathlib.Path)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--allow-software", action="store_true",
                        help="diagnostic only; never hardware acceptance")
    args = parser.parse_args()
    if args.self_test:
        selftest()
        return 0
    if not args.reports:
        parser.error("Provide each native GUI JSON evidence file")
    profiles = []
    for path in args.reports:
        obj = json.loads(path.read_text(encoding="utf-8"))
        errors = validate(obj, require_hardware=not args.allow_software)
        if errors:
            print(f"A147_R1_GUI_INVALID path={path} errors={errors}")
            return 1
        profiles.append(obj)
        print("A147_R1_GUI_VALID population=%d frames=%d p99_ms=%.3f "
              "backlog_max=%d memory_delta=%d" % (
              obj["population"], obj["frames"], obj["frame_interval_ms"]["p99"],
              obj["max_backlog_ticks"], obj["static_memory_bytes"]["delta"]))
    if [p["population"] for p in profiles] != [4, 32, 96, 256]:
        print("A147_R1_GUI_INVALID mandatory 4/32/96/256 evidence incomplete")
        return 1
    print("A147_R1_NATIVE_GUI_EVIDENCE_PASS")
    print("A147_R1_PERF_VERDICT=MEASURED_NOT_ACCEPTED: GUI p99, CPU tick debt "
          "and memory trend require independent multi-run review.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
