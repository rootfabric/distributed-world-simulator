#!/usr/bin/env python3
"""Run gateway, two native owners and two real graphical MVP3 clients."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import secrets
import socket
import struct
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[2]
ENV_CONFIG = "DWS_MVP3_LIVE_CONFIG"
ERRORS = ("SCRIPT ERROR:", "Parse Error", "Compile Error")


def require(ok: bool, message: str) -> None:
    if not ok:
        raise RuntimeError(message)


def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True, encoding="utf-8").strip()


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def read_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, json.JSONDecodeError):
        return {}


def wait_state(path: Path, states: set[str], deadline: float) -> dict:
    while time.monotonic() < deadline:
        value = read_json(path)
        if value.get("state") in states:
            return value
        time.sleep(0.025)
    return {}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    require(data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR", f"INVALID_PNG:{path}")
    return struct.unpack(">II", data[16:24])


def native_displacement(before: dict, after: dict, actor: str) -> bool:
    """Reject a no-op, identity replacement, stale state or missing coordinate."""
    try:
        identity = ("logical_player_id", "player_entity_id", "transport_session_id", "ownership_epoch")
        x0, x1 = float(before["position"]["x"]), float(after["position"]["x"])
        return (
            all(before[key] == after[key] for key in identity)
            and after["logical_player_id"] == actor
            and after["player_entity_id"] == "player/" + actor
            and bool(after["transport_session_id"])
            and math.isfinite(x0) and math.isfinite(x1) and abs(x1 - x0) > 1e-6
            and int(after["last_input_sequence"]) > int(before["last_input_sequence"])
            and int(after["state_revision"]) > int(before["state_revision"])
        )
    except (KeyError, TypeError, ValueError, OverflowError):
        return False


def fixed_step(value: dict) -> bool:
    try:
        dt = float(value["delta_seconds"])
        return value["fixed_tick"] is True and math.isfinite(dt) and abs(dt - 1 / 60) < 1e-12
    except (KeyError, TypeError, ValueError, OverflowError):
        return False


def movement_evidence_checks(gateway: dict, clients: dict[str, dict], manual: bool = False) -> dict[str, bool]:
    """Independent reductions of raw records, not self-reported PASS flags."""
    result = {"both_players_independent": False, "post_activation_movement": False,
              "canonical_fixed_receipts": False, "manual_input_proven_when_requested": False}
    try:
        observations = gateway.get("input_observations", {})
        result["both_players_independent"] = all(
            int(gateway.get("sequences", {}).get(actor, 0)) >= 2
            and any(native_displacement(row.get("before", {}), row.get("after", {}), actor)
                    and fixed_step(row.get("server_simulation", {}))
                    for row in observations.get(actor, []))
            for actor in ("a", "b")
        )
        transfers = gateway.get("transfers", [])
        result["post_activation_movement"] = len(transfers) == 2 and all(
            row.get("actor") == "a"
            and native_displacement(row.get("before", {}), row.get("after", {}), "a")
            and fixed_step(row.get("post_activation_server_simulation", {}))
            and str(row.get("post_activation_operation_id", "")).startswith("operation/")
            and int(row.get("post_activation_server_tick", 0)) > 0
            for row in transfers
        )
        result["canonical_fixed_receipts"] = all(
            int(clients[actor].get("fixed_input_receipts", 0)) == int(clients[actor].get("input_sequence", -1))
            and int(clients[actor].get("fixed_input_receipts", 0)) >= 2
            for actor in ("a", "b")
        )
        result["manual_input_proven_when_requested"] = not manual or all(
            int(clients[actor].get("manual_input_events", 0)) >= 2 for actor in ("a", "b")
        )
    except (KeyError, TypeError, ValueError, OverflowError):
        return {key: False for key in result}
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--engine", required=True, type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts" / "mvp3-graphical-process")
    parser.add_argument("--manual", action="store_true", help="wait for keyboard input in both client windows")
    args = parser.parse_args()
    engine = args.engine.resolve()
    output = args.output.resolve()
    require(engine.is_file(), f"ENGINE_NOT_FOUND:{engine}")
    require(not output.exists(), f"PRESERVE_PREVIOUS_EVIDENCE:{output}")
    output.mkdir(parents=True)

    head = git("rev-parse", "HEAD")
    tree = git("rev-parse", "HEAD^{tree}")
    run_id = secrets.token_hex(16)
    allocated = [free_port(), free_port(), free_port()]
    require(len(set(allocated)) == 3, "PORT_COLLISION")
    ports = {"authority/a": allocated[0], "authority/b": allocated[1]}
    gateway_port = allocated[2]
    internal_keys = {"authority/a": secrets.token_hex(32), "authority/b": secrets.token_hex(32)}
    client_keys = {"a": secrets.token_hex(32), "b": secrets.token_hex(32)}
    results = {role: output / (role.replace("/", "-") + ".json") for role in ("authority/a", "authority/b", "gateway", "client/a", "client/b")}
    screenshots = {actor: output / f"client-{actor}.png" for actor in ("a", "b")}
    processes: dict[str, subprocess.Popen[str]] = {}
    handles: dict[str, object] = {}
    commands: list[dict] = []
    started = time.monotonic()

    def common(role: str) -> dict:
        return {"run_id": run_id, "subject_head": head, "role": role, "result_file": str(results[role]), "ports": ports, "gateway_port": gateway_port, "timeout_ms": 600000 if args.manual else 120000, "backend_rpc_timeout_ms": 15000, "client_reply_timeout_ms": 30000}

    def launch(role: str, argv_tail: list[str], config: dict) -> None:
        env = os.environ.copy()
        env.update({"PYTHONUTF8": "1", "BREAKPOINT_RUNTIME_DISABLED": "1", ENV_CONFIG: json.dumps(config, separators=(",", ":"))})
        argv = [str(engine), *argv_tail]
        path = output / (role.replace("/", "-") + ".log")
        handle = path.open("w", encoding="utf-8")
        handles[role] = handle
        processes[role] = subprocess.Popen(argv, cwd=ROOT, env=env, stdout=handle, stderr=subprocess.STDOUT, text=True)
        commands.append({"role": role, "argv": argv, "log": path.name})

    error = ""
    try:
        for authority in ("authority/a", "authority/b"):
            config = common(authority) | {"internal_keys": internal_keys}
            launch(authority, ["--headless", "--path", str(ROOT), "--script", "res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_authority_process.gd"], config)
        deadline = time.monotonic() + 15
        for authority in ("authority/a", "authority/b"):
            require(wait_state(results[authority], {"LISTENING", "FAILED"}, deadline).get("state") == "LISTENING", f"AUTHORITY_NOT_LISTENING:{authority}")
        gateway_config = common("gateway") | {"internal_keys": internal_keys, "client_keys": client_keys, "mode": "interactive"}
        launch("gateway", ["--headless", "--path", str(ROOT), "--script", "res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_gateway_process.gd"], gateway_config)
        require(wait_state(results["gateway"], {"LISTENING", "FAILED"}, time.monotonic() + 20).get("state") == "LISTENING", "GATEWAY_NOT_LISTENING")
        for index, actor in enumerate(("a", "b")):
            role = "client/" + actor
            config = common(role) | {"client_key": client_keys[actor], "automated": not args.manual, "screenshot_file": str(screenshots[actor])}
            launch(role, ["--path", str(ROOT), "--resolution", "720x480", "--position", f"{40 + index * 760},80", "res://scenes/labs/mvp/v0_mvp3_live_shared_world.tscn"], config)
        if args.manual:
            print("MANUAL: hold A/D or Left/Right in each window. Move A right across the seam, left back across it, then right again; move B in both directions. Keep both clients observing A->B->A. Release keys and press Esc in both windows after completion.", flush=True)
        for role in ("client/a", "client/b", "gateway", "authority/a", "authority/b"):
            code = processes[role].wait(timeout=590 if args.manual else 105)
            require(code == 0, f"PROCESS_EXIT:{role}:{code}")
    except Exception as exc:
        error = str(exc)
    finally:
        for process in processes.values():
            if process.poll() is None:
                process.terminate()
        for process in processes.values():
            if process.poll() is None:
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
        for handle in handles.values():
            handle.close()

    reports = {role: read_json(path) for role, path in results.items()}
    client_reports = {actor: reports["client/" + actor] for actor in ("a", "b")}
    gateway = reports["gateway"]
    sizes = {actor: png_size(path) if path.is_file() else (0, 0) for actor, path in screenshots.items()}
    expected_routes = ["authority/a", "authority/b", "authority/a"]
    checks = {
        "all_processes_passed": all(report.get("passed") is True for report in reports.values()),
        "exact_subject": all(report.get("subject_head") == head for report in reports.values()),
        "five_distinct_processes": len({report.get("process_id", report.get("gateway_process_id")) for report in reports.values()}) == 5,
        "a_roundtrip": [(row.get("source"), row.get("target")) for row in gateway.get("transfers", [])] == [("authority/a", "authority/b"), ("authority/b", "authority/a")],
        "both_clients_observed_routes": all(report.get("route_history") == expected_routes and report.get("route_history_observed_actor") == "a" for report in client_reports.values()),
        "stable_client_connections": all(report.get("connects") == 1 and report.get("disconnects") == 0 and report.get("reconnects") == 0 for report in client_reports.values()),
        "stable_body_camera_instances": all(report.get("initial_instance_ids") == report.get("final_instance_ids") and all(int(v) > 0 for v in report.get("final_instance_ids", {}).values()) for report in client_reports.values()),
        "both_players_always_visible": all(int(report.get("both_visible_snapshots", 0)) == int(report.get("snapshots", -1)) and int(report.get("snapshots", 0)) > 2 for report in client_reports.values()),
        "viewport_pngs": all(width == 720 and 400 <= height <= 405 for width, height in sizes.values()),
        "no_respawn_or_rebind": gateway.get("respawns") == 0 and gateway.get("identity", {}).get("counters", {}).get("rebinds") == 0 and all(report.get("identity_changes") == 0 for report in client_reports.values()),
        "no_false_acceptance": gateway.get("mvp3_predicate_verified") is False and all(report.get("mvp3_predicate_verified") is False for report in client_reports.values()),
    }
    # Replaces a hard-coded 22 delta packets with actual canonical movement
    # evidence under fixed ticks. Neither neutral input nor route labels pass.
    checks.update(movement_evidence_checks(gateway, client_reports, args.manual))
    for role, process in processes.items():
        checks[f"exit_{role}"] = process.returncode == 0
        log_text = (output / (role.replace("/", "-") + ".log")).read_text(encoding="utf-8", errors="replace")
        checks[f"log_{role}_clean"] = not any(marker in log_text for marker in ERRORS)
    passed = not error and all(checks.values())
    manifest = {
        "schema": "distributed_world_simulator.mvp3_graphical_process_manifest.v1",
        "subject_head": head, "subject_tree": tree, "run_id": run_id,
        "engine": str(engine), "engine_sha256": sha(engine),
        "duration_seconds": round(time.monotonic() - started, 3),
        "commands": commands, "checks": checks,
        "viewport_sizes": {actor: list(size) for actor, size in sizes.items()},
        "error": error, "passed": passed,
        "manual_input_mode": args.manual,
        "manual_input_executed": args.manual and all(int(report.get("manual_input_events", 0)) >= 2 for report in client_reports.values()),
        "secrets_recorded": False, "mvp3_predicate_verified": False, "files": [],
    }
    for path in sorted(output.iterdir()):
        if path.is_file() and path.name != "manifest.json":
            manifest["files"].append({"path": path.name, "bytes": path.stat().st_size, "sha256": sha(path)})
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": passed, "error": error, "checks": checks, "viewport_sizes": manifest["viewport_sizes"], "output": str(output)}, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
