#!/usr/bin/env python3
"""Process-level lifecycle check for PlanetSimulator simulation-server."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def parse_lifecycle_lines(output: str) -> list[dict]:
    events: list[dict] = []
    prefix = "[lifecycle] "
    for line in output.splitlines():
        if line.startswith(prefix):
            events.append(json.loads(line[len(prefix) :]))
    return events


def parse_descriptor(output: str) -> dict:
    prefix = "[runtime_descriptor] "
    for line in output.splitlines():
        if line.startswith(prefix):
            return json.loads(line[len(prefix) :])
    raise AssertionError("runtime descriptor was not printed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", required=True)
    parser.add_argument("--project", default=str(Path(__file__).resolve().parents[2]))
    parser.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()

    godot = Path(args.godot).resolve()
    project = Path(args.project).resolve()
    if not godot.is_file():
        raise SystemExit(f"Godot executable not found: {godot}")
    if not (project / "project.godot").is_file():
        raise SystemExit(f"Godot project not found: {project}")

    with tempfile.TemporaryDirectory(prefix="planet-sim-lifecycle-") as temp_value:
        temp_root = Path(temp_value).resolve()
        env = os.environ.copy()
        env["HOME"] = str(temp_root)
        env["XDG_DATA_HOME"] = str(temp_root / "xdg-data")
        env["APPDATA"] = str(temp_root / "appdata")
        env["LOCALAPPDATA"] = str(temp_root / "localappdata")
        env["GODOT_SILENCE_ROOT_WARNING"] = "1"

        command = [
            str(godot),
            "--headless",
            "--path",
            str(project),
            "--",
            "--role=simulation-server",
            "--world=earth_moon",
            "--node-id=process-lifecycle-test",
            "--shutdown-after-ms=1000",
            "--shutdown-timeout-ms=30000",
            f"--user-data-dir={temp_root}",
            "--print-runtime-descriptor",
        ]
        completed = subprocess.run(
            command,
            cwd=project,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=args.timeout,
            check=False,
        )
        output = completed.stdout
        if completed.returncode != 0:
            print(output)
            raise AssertionError(f"simulation-server exited with {completed.returncode}")
        if "SCRIPT ERROR" in output:
            print(output)
            raise AssertionError("simulation-server emitted SCRIPT ERROR")
        if "The InputMap action" in output:
            print(output)
            raise AssertionError("simulation-server queried an undefined InputMap action")

        descriptor = parse_descriptor(output)
        assert descriptor["runtime_role"] == "simulation-server"
        assert descriptor["presentation_enabled"] is False
        assert descriptor["local_input_enabled"] is False
        assert descriptor["authoritative"] is True
        assert descriptor["requested_user_data_dir"] == str(temp_root)
        resolved_user_dir = Path(descriptor["resolved_user_data_dir"]).resolve()
        assert temp_root == resolved_user_dir or temp_root in resolved_user_dir.parents

        events = parse_lifecycle_lines(output)
        event_by_name = {event["event"]: event for event in events}
        assert list(event["event"] for event in events) == [
            "node_ready",
            "node_draining",
            "node_stopped",
        ]
        ready = event_by_name["node_ready"]
        stopped = event_by_name["node_stopped"]
        assert ready["active_presentation_nodes"] == 0
        assert ready["local_input_enabled"] is False
        assert ready["simulation_kernel"]["initialized"] is True
        assert ready["simulation_kernel"]["presentation_free"] is True
        assert ready["simulation_kernel"]["has_world_entity_store"] is True
        assert ready["simulation_kernel"]["has_entity_registry_port"] is True
        assert ready["simulation_kernel"]["has_world_repository_port"] is True
        assert ready["presentation_host"]["enabled"] is False
        assert ready["presentation_host"]["active_node_count"] == 0
        assert stopped["exit_code"] == 0
        assert stopped["lifecycle"]["state"] == "STOPPED"
        assert stopped["last_runtime_drain"]["drained"] is True
        terrain = stopped["last_runtime_drain"]["details"]["terrain"]
        assert terrain["drained"] is True
        assert terrain["state"] == "STOPPED"
        assert terrain["within_timeout"] is True

        print("Simulation-server process lifecycle: PASS")
        print(f"Resolved user data: {resolved_user_dir}")
        print(f"Terrain drain elapsed: {terrain['elapsed_ms']} ms")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (AssertionError, subprocess.TimeoutExpired) as error:
        print(f"Simulation-server process lifecycle: FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
