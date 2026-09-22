#!/usr/bin/env python3
"""Exercise two native M3 owners through one P6/SM1 gateway process."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import socket
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


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--engine", required=True, type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / "artifacts" / "mvp3-native-process")
    args = parser.parse_args()
    engine = args.engine.resolve()
    output = args.output.resolve()
    require(engine.is_file(), f"ENGINE_NOT_FOUND:{engine}")
    require(not output.exists(), f"PRESERVE_PREVIOUS_EVIDENCE:{output}")
    output.mkdir(parents=True)

    head = git("rev-parse", "HEAD")
    tree = git("rev-parse", "HEAD^{tree}")
    run_id = secrets.token_hex(16)
    ports = {"authority/a": free_port(), "authority/b": free_port()}
    require(ports["authority/a"] != ports["authority/b"], "PORT_COLLISION")
    keys = {"authority/a": secrets.token_hex(32), "authority/b": secrets.token_hex(32)}
    results = {
        "authority/a": output / "authority-a.json",
        "authority/b": output / "authority-b.json",
        "gateway": output / "gateway.json",
    }
    processes: dict[str, subprocess.Popen[str]] = {}
    logs: dict[str, object] = {}
    commands: list[dict] = []
    started = time.monotonic()

    def launch(role: str, script: str) -> None:
        env = os.environ.copy()
        env["PYTHONUTF8"] = "1"
        env["BREAKPOINT_RUNTIME_DISABLED"] = "1"
        config = {
            "run_id": run_id,
            "subject_head": head,
            "role": role,
            "result_file": str(results[role]),
            "ports": ports,
            "internal_keys": keys,
            "timeout_ms": 90000,
        }
        env[ENV_CONFIG] = json.dumps(config, separators=(",", ":"))
        argv = [str(engine), "--headless", "--path", str(ROOT), "--script", script]
        log_path = output / (role.replace("/", "-") + ".log")
        handle = log_path.open("w", encoding="utf-8")
        logs[role] = handle
        processes[role] = subprocess.Popen(argv, cwd=ROOT, env=env, stdout=handle, stderr=subprocess.STDOUT, text=True)
        commands.append({"role": role, "argv": argv, "log": log_path.name})

    error = ""
    try:
        launch("authority/a", "res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_authority_process.gd")
        launch("authority/b", "res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_authority_process.gd")
        deadline = time.monotonic() + 15
        for role in ("authority/a", "authority/b"):
            state = wait_state(results[role], {"LISTENING", "FAILED"}, deadline)
            require(state.get("state") == "LISTENING", f"AUTHORITY_NOT_LISTENING:{role}:{state}")
        launch("gateway", "res://scripts/runtime/networked_gameplay/mvp/v0_mvp3_gateway_process.gd")
        gateway_code = processes["gateway"].wait(timeout=75)
        require(gateway_code == 0, f"GATEWAY_EXIT:{gateway_code}")
        for role in ("authority/a", "authority/b"):
            code = processes[role].wait(timeout=15)
            require(code == 0, f"AUTHORITY_EXIT:{role}:{code}")
    except Exception as exc:  # evidence records the exact failure before re-raising
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
        for handle in logs.values():
            handle.close()

    gateway = read_json(results["gateway"])
    authorities = {role: read_json(results[role]) for role in ("authority/a", "authority/b")}
    checks = {
        "gateway_passed": gateway.get("passed") is True,
        "exact_subject": gateway.get("subject_head") == head and all(row.get("subject_head") == head for row in authorities.values()),
        "four_real_transfers": len(gateway.get("transfers", [])) == 4,
        "both_players_independent": gateway.get("two_independent_players") is True and all(int(gateway.get("sequences", {}).get(actor, 0)) >= 5 for actor in ("a", "b")),
        "distinct_processes": len({gateway.get("gateway_process_id"), *(row.get("process_id") for row in authorities.values())}) == 3,
        "single_backend_connections": all(row.get("connects") == 1 and row.get("disconnects") == 0 and not row.get("failure_code") for row in gateway.get("backend_links", {}).values()),
        "no_authority_disconnect": all(row.get("disconnects_during_workload") == 0 for row in authorities.values()),
        "authority_clean_exit": all(row.get("passed") is True and row.get("state") == "COMPLETE" for row in authorities.values()),
        "item_graph_not_transferred": all(row.get("initial_item_graph") == row.get("final_item_graph") for row in authorities.values()),
        "no_rebind_reconnect_respawn": gateway.get("identity", {}).get("counters", {}).get("rebinds") == 0 and gateway.get("gateway_reconnects") == 0 and gateway.get("respawns") == 0,
        "not_false_acceptance": gateway.get("graphical_scene_proven") is False and gateway.get("mvp3_predicate_verified") is False,
    }
    for role, process in processes.items():
        checks[f"exit_{role}"] = process.returncode == 0
    for role in processes:
        text = (output / (role.replace("/", "-") + ".log")).read_text(encoding="utf-8", errors="replace")
        checks[f"log_{role}_clean"] = not any(marker in text for marker in ERRORS)
    passed = not error and all(checks.values())

    manifest = {
        "schema": "distributed_world_simulator.mvp3_native_process_manifest.v1",
        "subject_head": head,
        "subject_tree": tree,
        "run_id": run_id,
        "engine": str(engine),
        "engine_sha256": digest(engine),
        "duration_seconds": round(time.monotonic() - started, 3),
        "commands": commands,
        "checks": checks,
        "error": error,
        "passed": passed,
        "secrets_recorded": False,
        "mvp3_predicate_verified": False,
        "files": [],
    }
    for path in sorted(output.iterdir()):
        if path.is_file() and path.name != "manifest.json":
            manifest["files"].append({"path": path.name, "bytes": path.stat().st_size, "sha256": digest(path)})
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"passed": passed, "error": error, "checks": checks, "output": str(output)}, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
