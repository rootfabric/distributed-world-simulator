#!/usr/bin/env python3
"""MVP7 live reconnect gate over the unchanged MVP6 five-process graphical story.

Two original graphical clients complete MVP3-MVP6 first. Client A then exits,
a fresh sixth process creates a new ENet peer, receives the CURRENT terrain,
material/Item Graph and Construction projection, derives collision locally, and
continues movement through the existing gateway/authority route. This runner
never marks the whole MVP7 accepted; server restart is proven by the separate
three-process durable recovery gate on the same exact subject.
"""
from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import os
from pathlib import Path
import re
import secrets
import socket
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]


def load(name: str, relative: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    if spec is None or spec.loader is None:
        raise RuntimeError("VALIDATOR_IMPORT_FAILED:" + relative)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


P6 = load("mvp7_unchanged_mvp6_graphical", "tests/integration/test_v0_mvp_6_graphical_construction.py")
P5, P4, V4, BASE, ROLES = P6.P5, P6.P4, P6.V4, P6.BASE, P6.ROLES


def reconnect_checks(reports: dict, clients: dict, reconnect: dict, head: str, run_id: str) -> dict[str, bool]:
    checks: dict[str, bool] = {}
    try:
        gateway = reports["gateway"]
        proof = gateway["mvp7_reconnect"]
        current = proof["current"]
        current_snapshot = current["snapshot"]
        current_matter = current["matter_source"]
        current_material = current["material"]
        current_construction = current["construction"]
        owner = reports["authority/a"]
        liveness = gateway["mvp7_backend_liveness"]
        pids = {
            reports["authority/a"]["process_id"],
            reports["authority/b"]["process_id"],
            gateway["gateway_process_id"],
            clients["a"]["process_id"],
            clients["b"]["process_id"],
            reconnect["process_id"],
        }
        checks["fresh_sixth_process"] = len(pids) == 6
        checks["exact_subject_and_run"] = reconnect["subject_head"] == head and reconnect["run_id"] == run_id
        checks["one_peer_replacement"] = (
            proof["reconnect_count"] == 1
            and proof["original_peer"]
            and proof["reconnect_peer"]
            and proof["original_peer"] != proof["reconnect_peer"]
        )
        checks["gateway_proved_reconnect"] = (
            proof["proved"] is True
            and proof["continue_ok"] is True
            and proof["finish_ack_disconnect"] is True
        )
        checks["backend_liveness_until_reconnect"] = (
            liveness["cycles"] >= 2
            and liveness["failures"] == 0
            and set(liveness["last"]["observed"]) == {"authority/a", "authority/b"}
            and liveness["mutation_performed"] is False
            and liveness["backend_reconnect_performed"] is False
            and liveness["timeout_policy_changed"] is False
        )
        checks["reconnect_client_passed"] = reconnect["passed"] is True and reconnect["canonical_state_owned"] is False
        checks["stable_world_digest"] = (
            len(proof["hello_world_digest"]) == 64
            and proof["hello_world_digest"] == proof["after_world_digest"]
            and proof["hello_world_digest"] == reconnect["hello_world_digest"] == reconnect["after_world_digest"]
        )
        checks["continued_fixed_tick_control"] = (
            reconnect["fixed_input_receipt"] is True
            and reconnect["position_changed"] is True
            and proof["position_changed"] is True
            and proof["position_before"] != proof["position_after"]
        )
        checks["current_terrain_state"] = (
            current_snapshot["mvp4"]["both_observed"] is True
            and current_matter["stream_sequence"] >= 1
            and reconnect["matter_store_hash"] == current_matter["store_hash"]
            and reconnect["matter_state_hash"] == current_matter["state_hash"]
            and reconnect["matter_store_hash"] == owner["mvp4"]["store_hash"]
            and reconnect["matter_state_hash"] == owner["mvp4"]["state_hash"]
        )
        checks["current_item_material_state"] = (
            len(current_material["material_digest"]) == 64
            and len(current_material["item_graph_checksum"]) == 64
            and reconnect["material_digest"] == current_material["material_digest"]
            and current_material["material_digest"] == owner["mvp4"]["material_projection"]["details"]["material_digest"]
            and current_material["item_graph_checksum"] == owner["mvp4"]["material_projection"]["details"]["item_graph_checksum"]
        )
        checks["current_construction_and_collision"] = (
            current_snapshot["mvp6"]["complete"] is True
            and len(current_construction["parts"]) == 100
            and reconnect["construction_checksum"] == current_construction["checksum"]
            and current_construction["checksum"] == gateway["mvp6"]["construction"]["checksum"]
            and reconnect["collision_part_count"] == 100
        )
        checks["original_two_clients_remain_valid"] = all(clients[a]["passed"] is True for a in ("a", "b"))
        checks["no_restart_relabel"] = reconnect.get("mvp7_predicate_verified") is False
    except (KeyError, TypeError, ValueError, IndexError):
        checks["well_formed_reconnect_evidence"] = False
    return checks


def reconnect_negatives(reports: dict, clients: dict, reconnect: dict, head: str, run_id: str) -> list[str]:
    mutations = {
        "no_reconnect": lambda r, c, x: r["gateway"]["mvp7_reconnect"].update(reconnect_count=0),
        "same_peer": lambda r, c, x: r["gateway"]["mvp7_reconnect"].update(reconnect_peer=r["gateway"]["mvp7_reconnect"]["original_peer"]),
        "no_post_reconnect_motion": lambda r, c, x: x.update(position_changed=False),
        "stale_construction": lambda r, c, x: x.update(construction_checksum="0" * 64),
        "stale_matter": lambda r, c, x: x.update(matter_store_hash="0" * 64),
        "no_backend_liveness": lambda r, c, x: r["gateway"]["mvp7_backend_liveness"].update(cycles=0),
        "no_finish_ack_disconnect": lambda r, c, x: r["gateway"]["mvp7_reconnect"].update(finish_ack_disconnect=False),
    }
    rejected: list[str] = []
    for name, mutate in mutations.items():
        r, c, x = copy.deepcopy(reports), copy.deepcopy(clients), copy.deepcopy(reconnect)
        mutate(r, c, x)
        BASE.require(not all(reconnect_checks(r, c, x, head, run_id).values()), "MVP7_RECONNECT_FALSE_POSITIVE:" + name)
        rejected.append(name)
    return rejected


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    engine, output = args.engine.resolve(), args.output.resolve()
    BASE.require(engine.is_file() and sys.platform in P4.PINNED_ENGINES and BASE.sha(engine) == P4.PINNED_ENGINES[sys.platform], "EXACT_DOUBLE_ENGINE_REQUIRED")
    BASE.require(not output.exists(), "PRESERVE_PREVIOUS_EVIDENCE")
    BASE.require(not BASE.git("status", "--porcelain", "--untracked-files=no"), "TRACKED_CHECKOUT_DIRTY")
    head, tree = BASE.git("rev-parse", "HEAD"), BASE.git("rev-parse", "HEAD^{tree}")
    BASE.require(head == os.environ.get("EXPECTED_HEAD", head), "EXACT_HEAD_MISMATCH")
    output.mkdir(parents=True)

    run_id = secrets.token_hex(16)
    sockets = [socket.socket(socket.AF_INET, socket.SOCK_DGRAM) for _ in range(3)]
    try:
        for sock in sockets:
            sock.bind(("127.0.0.1", 0))
        ports = [sock.getsockname()[1] for sock in sockets]
    finally:
        for sock in sockets:
            sock.close()
    authority_ports = {"authority/a": ports[0], "authority/b": ports[1]}
    internal_keys = {a: secrets.token_hex(32) for a in authority_ports}
    client_keys = {a: secrets.token_hex(32) for a in ("a", "b")}
    paths = {role: output / (role.replace("/", "-") + ".json") for role in ROLES}
    reconnect_path = output / "reconnect-a.json"
    processes: dict[str, subprocess.Popen] = {}
    streams: dict[str, object] = {}
    commands: list[dict] = []
    profiles = tempfile.TemporaryDirectory(prefix="dws-mvp7-reconnect-profile-")

    def launch(alias: str, cfg_role: str, tail: list[str], extra: dict, result_path: Path) -> None:
        cfg = {
            "role": cfg_role,
            "run_id": run_id,
            "subject_head": head,
            "result_file": str(result_path),
            "ports": authority_ports,
            "gateway_port": ports[2],
            "timeout_ms": 240000,
            "backend_rpc_timeout_ms": 90000,
            "client_reply_timeout_ms": 120000,
        } | extra
        env = os.environ.copy()
        env.update(
            PYTHONUTF8="1",
            BREAKPOINT_RUNTIME_DISABLED="1",
            DWS_MVP3_LIVE_CONFIG=json.dumps(cfg, separators=(",", ":")),
        )
        profile = Path(profiles.name) / alias.replace("/", "-")
        for variable, directory in {
            "XDG_DATA_HOME": "data",
            "XDG_CONFIG_HOME": "config",
            "XDG_CACHE_HOME": "cache",
            "APPDATA": "roaming",
            "LOCALAPPDATA": "local",
        }.items():
            p = profile / directory
            p.mkdir(parents=True, exist_ok=True)
            env[variable] = str(p)
        argv = [str(engine), "--audio-driver", "Dummy", *tail]
        log = output / (alias.replace("/", "-") + ".log")
        streams[alias] = log.open("w", encoding="utf-8")
        processes[alias] = subprocess.Popen(argv, cwd=ROOT, env=env, stdout=streams[alias], stderr=subprocess.STDOUT, text=True)
        commands.append({"alias": alias, "cfg_role": cfg_role, "argv": argv, "log": log.name, "isolated_user_data": True})

    start = time.monotonic()
    error = ""
    try:
        for role in ("authority/a", "authority/b"):
            launch(
                role,
                role,
                ["--headless", "--path", str(ROOT), "--script", "res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_guarded_authority_process.gd"],
                {"internal_keys": internal_keys},
                paths[role],
            )
        for role in ("authority/a", "authority/b"):
            BASE.require(BASE.wait_state(paths[role], {"LISTENING", "FAILED"}, time.monotonic() + 30).get("state") == "LISTENING", "AUTHORITY_NOT_LISTENING:" + role)

        launch(
            "gateway",
            "gateway",
            ["--headless", "--path", str(ROOT), "--script", "res://scripts/runtime/networked_gameplay/mvp/v0_mvp7_reconnect_gateway_process.gd"],
            {"internal_keys": internal_keys, "client_keys": client_keys, "mode": "interactive"},
            paths["gateway"],
        )
        BASE.require(BASE.wait_state(paths["gateway"], {"LISTENING", "FAILED"}, time.monotonic() + 50).get("state") == "LISTENING", "GATEWAY_NOT_LISTENING")

        for i, actor in enumerate(("a", "b")):
            role = "client/" + actor
            launch(
                role,
                role,
                ["--path", str(ROOT), "--resolution", "720x480", "--position", f"{40 + i * 760},80", "res://scenes/labs/mvp/v0_mvp6_live_construction.tscn"],
                {
                    "automated": True,
                    "client_key": client_keys[actor],
                    "screenshot_file": str(output / f"client-{actor}.png"),
                    "mvp4_capture_before": str(output / f"client-{actor}-before.png"),
                    "mvp4_capture_after": str(output / f"client-{actor}-after.png"),
                    "mvp4_evidence_file": str(output / f"capture-{actor}.json"),
                    "mvp5_evidence_file": str(output / f"material-{actor}.json"),
                    "mvp6_evidence_file": str(output / f"construction-{actor}.json"),
                },
                paths[role],
            )

        original_deadline = time.monotonic() + 220
        for role in ("client/a", "client/b"):
            BASE.require(processes[role].wait(timeout=max(1, original_deadline - time.monotonic())) == 0, "ORIGINAL_CLIENT_FAILED:" + role)

        # The original A process is gone. A fresh process and ENet peer now
        # reconnect to the still-running same authoritative world.
        time.sleep(0.15)
        launch(
            "reconnect/a",
            "client/a",
            ["--headless", "--path", str(ROOT), "--script", "res://scripts/runtime/networked_gameplay/mvp/v0_mvp7_reconnect_client.gd"],
            {"automated": True, "client_key": client_keys["a"]},
            reconnect_path,
        )

        deadline = time.monotonic() + 100
        for role in ("reconnect/a", "gateway", "authority/a", "authority/b"):
            BASE.require(processes[role].wait(timeout=max(1, deadline - time.monotonic())) == 0, "PROCESS_FAILED:" + role)
    except Exception as exc:
        error = type(exc).__name__ + ":" + str(exc)
    finally:
        for proc in processes.values():
            if proc.poll() is None:
                proc.terminate()
        for proc in processes.values():
            if proc.poll() is None:
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
        for stream in streams.values():
            stream.close()
        profiles.cleanup()

    reports = {role: BASE.read_json(path) for role, path in paths.items()}
    captures = {a: BASE.read_json(output / f"capture-{a}.json") for a in ("a", "b")}
    materials = {a: BASE.read_json(output / f"material-{a}.json") for a in ("a", "b")}
    clients = {a: BASE.read_json(output / f"construction-{a}.json") for a in ("a", "b")}
    reconnect = BASE.read_json(reconnect_path)

    checks = {"mvp4:" + k: v for k, v in P4.evidence_checks(reports, captures, head, run_id).items()}
    try:
        frozen_mvp5 = P6.mvp5_checkpoint_reports(reports, materials)
        checks.update({"mvp5:" + k: v for k, v in P5.material_checks(frozen_mvp5, materials, head, run_id).items()})
    except (KeyError, TypeError, ValueError, RuntimeError) as exc:
        checks["mvp5:authenticated_preconstruction_checkpoint"] = False
        error += ";" + type(exc).__name__ + ":" + str(exc)
    checks.update({"mvp6:" + k: v for k, v in P6.construction_checks(reports, clients, head, run_id).items()})
    checks.update({"mvp7:" + k: v for k, v in reconnect_checks(reports, clients, reconnect, head, run_id).items()})

    for role in (*ROLES, "reconnect/a"):
        log = output / (role.replace("/", "-") + ".log")
        checks["exit:" + role] = role in processes and processes[role].returncode == 0
        text = log.read_text(errors="replace") if log.is_file() else "SCRIPT ERROR: missing log"
        checks["log:" + role] = not any(marker in text for marker in BASE.ERRORS) and not re.search(r"(?im)^\s*(?:SCRIPT ERROR|ERROR):|Parse Error|Compile Error", text)

    visible: dict = {}
    hud_cases: list = []
    negatives: list[str] = []
    reconnect_rejected: list[str] = []
    try:
        for actor in ("a", "b"):
            before, after = output / f"client-{actor}-before.png", output / f"client-{actor}-after.png"
            ca, cb = V4.certified_region(captures[actor], actor, "before"), V4.certified_region(captures[actor], actor, "after")
            width, height, _ = V4.pixels.rgba(before)
            region = V4.pixels.union_region(ca, cb, width, height)
            visible[actor] = V4.pixels.terrain_change(before, after, dict(zip(("x", "y", "w", "h"), region)))
            checks["visible_terrain:" + actor] = visible[actor]["passed"] and visible[actor]["terrain_changed_pixels"] >= 32
            checks["viewport:" + actor] = width == 720 and 400 <= height <= 480
            hud_cases.append(V4.hud_only_falsification(output, actor, before, ca, cb))
        if not error and all(checks.values()):
            negatives = P6.construction_negatives(reports, clients, head, run_id)
            reconnect_rejected = reconnect_negatives(reports, clients, reconnect, head, run_id)
    except (OSError, KeyError, ValueError, RuntimeError, TypeError) as exc:
        error += ";" + type(exc).__name__ + ":" + str(exc)

    passed = (
        not error
        and all(checks.values())
        and len(negatives) == 13
        and len(reconnect_rejected) == 7
        and len(hud_cases) == 2
        and not BASE.git("status", "--porcelain", "--untracked-files=no")
    )
    manifest = {
        "schema": "distributed_world_simulator.mvp7_graphical_reconnect_manifest.v1",
        "subject_head": head,
        "subject_tree": tree,
        "run_id": run_id,
        "engine_sha256": BASE.sha(engine),
        "commands": commands,
        "error": error,
        "checks": checks,
        "visible_terrain": visible,
        "hud_only_falsification": hud_cases,
        "mvp6_negative_controls": negatives,
        "mvp7_reconnect_negative_controls": reconnect_rejected,
        "passed": passed,
        "duration_seconds": time.monotonic() - start,
        "two_original_graphical_clients_executed": True,
        "fresh_reconnect_process_executed": bool(reconnect),
        "enet_reconnect_executed": bool(reconnect.get("passed", False)),
        "current_state_resync_executed": bool(reconnect.get("passed", False)),
        "server_restart_executed": False,
        "mvp7_predicate_verified": False,
        "independent_verdict": False,
        "files": [],
    }
    for path in sorted(output.iterdir()):
        if path.is_file() and path.name != "manifest.json":
            manifest["files"].append({"path": path.name, "bytes": path.stat().st_size, "sha256": BASE.sha(path)})
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "passed": passed,
        "error": error,
        "failed_checks": [k for k, v in checks.items() if not v],
        "mvp6_negative_controls": negatives,
        "mvp7_reconnect_negative_controls": reconnect_rejected,
    }, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
