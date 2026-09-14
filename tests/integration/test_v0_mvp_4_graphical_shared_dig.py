#!/usr/bin/env python3
"""Five real processes: canonical dig from A, independently rebuilt A/B terrain.

Automatic execution is explicitly not Windows physical-keyboard evidence.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("mvp3_process_helpers", ROOT / "tests/integration/test_v0_mvp3_graphical_process_roundtrip.py")
assert SPEC is not None and SPEC.loader is not None
BASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BASE)
PINNED_ENGINES = {
    "linux": "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7",
    "win32": "3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5",
}
ROLES = ("authority/a", "authority/b", "gateway", "client/a", "client/b")


def evidence_checks(reports: dict, captures: dict, head: str, run_id: str) -> dict[str, bool]:
    checks: dict[str, bool] = {}
    try:
        gateway = reports["gateway"]
        source = reports["authority/a"]["mvp4"]
        clients = {a: reports["client/" + a] for a in ("a", "b")}
        checks["all_processes_pass"] = all(r.get("passed") is True for r in reports.values()) and set(reports) == set(ROLES)
        checks["exact_subject_run"] = all(r.get("subject_head") == head and r.get("run_id") == run_id for r in list(reports.values()) + list(captures.values()))
        pids = [r.get("process_id", r.get("gateway_process_id")) for r in reports.values()]
        checks["five_distinct_processes"] = len(pids) == 5 and all(isinstance(p, int) and not isinstance(p, bool) and p > 0 for p in pids) and len(set(pids)) == 5
        digs = source["dig_observations"]
        checks["real_canonical_single_dig"] = len(digs) == 1 and digs[0]["actor"] == "a" and source["stream_sequence"] == 1 and source["store_hash"] != source["initial_store_hash"] and digs[0]["before_store_hash"] != digs[0]["after_store_hash"] and bool(digs[0]["changed_bricks"]) and float(digs[0]["removed_mass_kg"]) > 0
        checks["one_matter_owner"] = source["matter_region_count"] == 1 and source["authority_id"] == "authority/a" and reports["authority/b"]["mvp4"].get("configured") is False
        checks["both_independently_move"] = all(
            int(gateway["sequences"][actor]) >= 2 and any(BASE.native_displacement(row["before"], row["after"], actor) and BASE.fixed_step(row["server_simulation"]) for row in gateway["input_observations"][actor])
            for actor in ("a", "b"))
        geometries = []
        for actor in ("a", "b"):
            client = clients[actor]
            capture = captures[actor]
            before = capture["captures"]["before"]["projection"]
            after = capture["captures"]["after"]["projection"]
            prefix = actor + ":"
            checks[prefix + "real_render_frames"] = capture["passed"] is True and capture["captures"]["after"]["frame"] > capture["captures"]["before"]["frame"]
            checks[prefix + "terrain_only_capture"] = all(
                label in capture["captures"] and capture["captures"][label].get("ui", {}).get("hidden") is True
                and bool(capture["captures"][label].get("ui", {}).get("region", {}))
                and len(capture["captures"][label].get("ui", {}).get("nodes", [])) > 0
                for label in ("before", "after"))
            checks[prefix + "canonical_store_convergence"] = before["store_hash"] == source["initial_store_hash"] and after["store_hash"] == source["store_hash"] and after["replica"]["state_hash"] == source["state_hash"] and after["replica"]["stream_sequence"] == 1
            checks[prefix + "physical_geometry_changes"] = after["geometry_hash"] != before["geometry_hash"] and after["network_mutation_proven"] is True and after["mesh_count"] > 0 and after["triangle_count"] > 0 and after["rebuild_count"] > before["rebuild_count"]
            checks[prefix + "read_only_replica"] = after["mode"] == "MW6_READ_ONLY_P7_REPLICA_PROJECTION" and after["canonical_state_owned"] is False and after["excavation_service_retained"] is False and after["read_only_replica_store_retained"] is True
            checks[prefix + "connection_identity_continuity"] = client["connects"] == 1 and all(client[k] == 0 for k in ("disconnects", "reconnects", "respawns", "identity_changes")) and client["initial_instance_ids"] == client["final_instance_ids"] and all(int(n) > 0 for n in client["final_instance_ids"].values())
            checks[prefix + "own_native_input_receipts"] = client["fixed_input_receipts"] == client["input_sequence"] and client["fixed_input_receipts"] >= 2
            checks[prefix + "both_players_visible"] = client["both_visible_snapshots"] == client["snapshots"] and client["snapshots"] > 2
            checks[prefix + "not_fake_manual_or_acceptance"] = capture["manual_input_executed"] is False and capture["mvp4_predicate_verified"] is False and after["mvp4_predicate_verified"] is False
            geometries.append(after["geometry_hash"])
        checks["independent_geometry_convergence"] = geometries[0] == geometries[1]
        checks["gateway_observers_match"] = gateway["mvp4"]["both_observed"] is True and all(gateway["mvp4"]["observed"][a]["geometry_hash"] == geometries[0] for a in ("a", "b"))
        checks["stable_backends"] = all(link["connects"] == 1 and link["disconnects"] == 0 and link["failure_code"] == "" for link in gateway["backend_links"].values()) and len(gateway["backend_links"]) == 2
        checks["no_claim_for_mvp5_or_handoff"] = source["mvp4_predicate_verified"] is False and source["mvp5_material_output_verified"] is False and gateway["transfers"] == []
    except (KeyError, IndexError, TypeError, ValueError, OverflowError):
        checks["well_formed_evidence"] = False
    return checks


def negative_controls(reports: dict, captures: dict, head: str, run_id: str) -> list[str]:
    cases = []
    mutations = {
        "unchanged_client_b_geometry": lambda r, c: c["b"]["captures"]["after"]["projection"].update(geometry_hash=c["b"]["captures"]["before"]["projection"]["geometry_hash"]),
        "wrong_client_a_canonical_store": lambda r, c: c["a"]["captures"]["after"]["projection"].update(store_hash="0" * 64),
        "recreated_camera": lambda r, c: r["client/a"]["final_instance_ids"].update(camera=0),
        "observer_b_without_input": lambda r, c: r["gateway"]["input_observations"].update(b=[]),
        "no_canonical_mutation": lambda r, c: r["authority/a"]["mvp4"].update(dig_observations=[]),
        "hud_visible_capture": lambda r, c: c["a"]["captures"]["before"]["ui"].update(hidden=False),
        "fake_manual": lambda r, c: c["a"].update(manual_input_executed=True),
        "shared_process": lambda r, c: r["client/b"].update(process_id=r["client/a"]["process_id"]),
        "reconnect": lambda r, c: r["client/b"].update(reconnects=1),
    }
    for name, mutation in mutations.items():
        altered, altered_captures = copy.deepcopy(reports), copy.deepcopy(captures)
        mutation(altered, altered_captures)
        BASE.require(not all(evidence_checks(altered, altered_captures, head, run_id).values()), "NEGATIVE_CONTROL_ACCEPTED:" + name)
        cases.append(name)
    return cases


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    engine, output = args.engine.resolve(), args.output.resolve()
    BASE.require(engine.is_file() and sys.platform in PINNED_ENGINES and BASE.sha(engine) == PINNED_ENGINES[sys.platform], "EXACT_DOUBLE_ENGINE_REQUIRED")
    BASE.require(not output.exists(), "PRESERVE_PREVIOUS_EVIDENCE")
    BASE.require(not BASE.git("status", "--porcelain", "--untracked-files=no"), "TRACKED_CHECKOUT_DIRTY")
    head, tree = BASE.git("rev-parse", "HEAD"), BASE.git("rev-parse", "HEAD^{tree}")
    output.mkdir(parents=True)
    run_id = secrets.token_hex(16)
    sockets = [socket.socket(socket.AF_INET, socket.SOCK_DGRAM) for _ in range(3)]
    try:
        for sock in sockets: sock.bind(("127.0.0.1", 0))
        allocated = [sock.getsockname()[1] for sock in sockets]
    finally:
        for sock in sockets: sock.close()
    ports = {"authority/a": allocated[0], "authority/b": allocated[1]}
    internal_keys = {a: secrets.token_hex(32) for a in ports}
    client_keys = {a: secrets.token_hex(32) for a in ("a", "b")}
    results = {role: output / (role.replace("/", "-") + ".json") for role in ROLES}
    processes, streams, commands = {}, {}, []
    def launch(role: str, tail: list[str], extra: dict) -> None:
        cfg = {"role": role, "run_id": run_id, "subject_head": head, "result_file": str(results[role]), "ports": ports, "gateway_port": allocated[2], "timeout_ms": 180000, "backend_rpc_timeout_ms": 30000, "client_reply_timeout_ms": 45000} | extra
        env = os.environ.copy()
        env.update(PYTHONUTF8="1", BREAKPOINT_RUNTIME_DISABLED="1", DWS_MVP3_LIVE_CONFIG=json.dumps(cfg, separators=(",", ":")))
        # Only owned child processes are managed and cleaned up by this runner.
        argv = [str(engine), *tail]
        log = output / (role.replace("/", "-") + ".log")
        streams[role] = log.open("w", encoding="utf-8")
        processes[role] = subprocess.Popen(argv, cwd=ROOT, env=env, stdout=streams[role], stderr=subprocess.STDOUT, text=True)
        commands.append({"role": role, "argv": argv, "log": log.name})
    started = time.monotonic()
    error = ""
    try:
        for role in ("authority/a", "authority/b"):
            launch(role, ["--headless", "--path", str(ROOT), "--script", "res://scripts/runtime/networked_gameplay/mvp/v0_mvp4_authority_process.gd"], {"internal_keys": internal_keys})
        for role in ("authority/a", "authority/b"):
            BASE.require(BASE.wait_state(results[role], {"LISTENING", "FAILED"}, time.monotonic() + 20).get("state") == "LISTENING", "AUTHORITY_NOT_LISTENING:" + role)
        launch("gateway", ["--headless", "--path", str(ROOT), "--script", "res://scripts/runtime/networked_gameplay/mvp/v0_mvp4_gateway_process.gd"], {"internal_keys": internal_keys, "client_keys": client_keys, "mode": "interactive"})
        BASE.require(BASE.wait_state(results["gateway"], {"LISTENING", "FAILED"}, time.monotonic() + 45).get("state") == "LISTENING", "GATEWAY_NOT_LISTENING")
        for i, actor in enumerate(("a", "b")):
            launch("client/" + actor, ["--path", str(ROOT), "--resolution", "720x480", "--position", f"{40 + i * 760},80", "res://scenes/labs/mvp/v0_mvp4_live_shared_dig.tscn"], {"automated": True, "client_key": client_keys[actor], "screenshot_file": str(output / f"client-{actor}.png"), "mvp4_capture_before": str(output / f"client-{actor}-before.png"), "mvp4_capture_after": str(output / f"client-{actor}-after.png"), "mvp4_evidence_file": str(output / f"capture-{actor}.json")})
        deadline = time.monotonic() + 175
        for role in ("client/a", "client/b", "gateway", "authority/a", "authority/b"):
            BASE.require(processes[role].wait(timeout=max(1, deadline - time.monotonic())) == 0, "PROCESS_FAILED:" + role)
    except Exception as exc:
        error = type(exc).__name__ + ":" + str(exc)
    finally:
        for p in processes.values():
            if p.poll() is None: p.terminate()
        for p in processes.values():
            if p.poll() is None:
                try: p.wait(timeout=5)
                except subprocess.TimeoutExpired: p.kill(); p.wait()
        for stream in streams.values(): stream.close()
    reports = {role: BASE.read_json(path) for role, path in results.items()}
    captures = {a: BASE.read_json(output / f"capture-{a}.json") for a in ("a", "b")}
    checks = evidence_checks(reports, captures, head, run_id)
    for role in ROLES:
        path = output / (role.replace("/", "-") + ".log")
        checks["exit:" + role] = role in processes and processes[role].returncode == 0
        text = path.read_text(encoding="utf-8", errors="replace") if path.is_file() else "SCRIPT ERROR: missing log"
        checks["log:" + role] = not any(marker in text for marker in BASE.ERRORS)
    for actor in ("a", "b"):
        for label in ("before", "after"):
            path = output / f"client-{actor}-{label}.png"
            try: width, height = BASE.png_size(path)
            except (OSError, RuntimeError, ValueError): width, height = 0, 0
            checks[f"viewport:{actor}:{label}"] = width == 720 and 400 <= height <= 480
    negatives = negative_controls(reports, captures, head, run_id) if not error and all(checks.values()) else []
    passed = not error and all(checks.values()) and len(negatives) == 9
    manifest = {"schema": "distributed_world_simulator.mvp4_graphical_process_manifest.v1", "subject_head": head, "subject_tree": tree, "run_id": run_id, "engine_sha256": BASE.sha(engine), "commands": commands, "error": error, "checks": checks, "negative_controls": negatives, "passed": passed, "duration_seconds": round(time.monotonic() - started, 3), "manual_input_executed": False, "mvp4_predicate_verified": False, "files": []}
    for p in sorted(output.iterdir()):
        if p.is_file() and p.name != "manifest.json": manifest["files"].append({"path": p.name, "bytes": p.stat().st_size, "sha256": BASE.sha(p)})
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": passed, "error": error, "checks": checks, "output": str(output)}, indent=2))
    return 0 if passed else 1

if __name__ == "__main__":
    raise SystemExit(main())
