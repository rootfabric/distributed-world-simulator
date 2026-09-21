#!/usr/bin/env python3
"""MVP8 bounded connected two-client workload over the accepted MVP3-MVP7 owners.

The same canonical world lineage executes twelve deterministic rounds. Client A
is replaced once by a fresh ENet process, then the authority/gateway stack is
stopped after an acknowledged quiescent checkpoint and restarted in new OS
processes. Both logical clients reconnect and continue the remaining rounds.
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


P7 = load("mvp8_mvp7", "tests/integration/test_v0_mvp_7_graphical_reconnect.py")
P6, P5, P4, BASE = P7.P6, P7.P5, P7.P4, P7.BASE
ROLES = ("authority/a", "authority/b", "gateway", "client/a", "client/b")

TOTAL_ROUNDS = 12
EXPECTED_ACTIONS = {"DIG": 4, "ITEM": 4, "BUILD_ADD": 2, "BUILD_REMOVE": 2}


def ports3() -> list[int]:
    sockets = [socket.socket(socket.AF_INET, socket.SOCK_DGRAM) for _ in range(3)]
    try:
        for sock in sockets:
            sock.bind(("127.0.0.1", 0))
        return [sock.getsockname()[1] for sock in sockets]
    finally:
        for sock in sockets:
            sock.close()


def read(path: Path) -> dict:
    return BASE.read_json(path)


def prepare_project_import(engine: Path, output: Path) -> dict:
    """Build Godot's project-local script class cache before multi-process startup.

    Direct --script launches on a cold source checkout can race global class_name
    discovery across authority processes. A single deterministic editor import
    establishes the same project metadata that normal editor/CI startup creates.
    The import log is preserved under output and is still covered by the existing
    fatal-log scan; this does not suppress or downgrade parse/compile errors.
    """
    log = output / "editor-import.log"
    argv = [
        str(engine),
        "--headless",
        "--path",
        str(ROOT),
        "--editor",
        "--import",
        "--quit",
    ]
    env = os.environ.copy()
    env.update(
        PYTHONUTF8="1",
        BREAKPOINT_RUNTIME_DISABLED="1",
    )
    started = time.monotonic()
    with log.open("w", encoding="utf-8") as stream:
        completed = subprocess.run(
            argv,
            cwd=ROOT,
            env=env,
            stdout=stream,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=180,
            check=False,
        )
    class_cache = ROOT / ".godot" / "global_script_class_cache.cfg"
    BASE.require(completed.returncode == 0, "MVP8_EDITOR_IMPORT_FAILED:" + str(completed.returncode))
    BASE.require(class_cache.is_file() and class_cache.stat().st_size > 0, "MVP8_GLOBAL_SCRIPT_CLASS_CACHE_MISSING")
    return {
        "argv": argv,
        "returncode": completed.returncode,
        "duration_seconds": time.monotonic() - started,
        "log": str(log.relative_to(output)),
        "global_script_class_cache": str(class_cache.relative_to(ROOT)).replace("\\", "/"),
        "global_script_class_cache_bytes": class_cache.stat().st_size,
    }


def start_process(
    engine: Path,
    output: Path,
    profiles: Path,
    commands: list[dict],
    processes: dict[str, subprocess.Popen],
    streams: dict[str, object],
    *,
    alias: str,
    cfg_role: str,
    cfg: dict,
    tail: list[str],
    result_path: Path,
) -> None:
    value = dict(cfg)
    value["role"] = cfg_role
    value["result_file"] = str(result_path)
    env = os.environ.copy()
    env.update(
        PYTHONUTF8="1",
        BREAKPOINT_RUNTIME_DISABLED="1",
        DWS_MVP3_LIVE_CONFIG=json.dumps(value, separators=(",", ":")),
    )
    profile = profiles / alias.replace("/", "-")
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
    processes[alias] = subprocess.Popen(
        argv, cwd=ROOT, env=env, stdout=streams[alias], stderr=subprocess.STDOUT, text=True
    )
    commands.append(
        {
            "alias": alias,
            "cfg_role": cfg_role,
            "argv": argv,
            "log": log.name,
            "result": str(result_path.relative_to(output)),
            "isolated_user_data": True,
        }
    )


def stop_all(processes: dict[str, subprocess.Popen], streams: dict[str, object]) -> None:
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


def wait_listening(path: Path, label: str, seconds: float = 40) -> None:
    state = BASE.wait_state(path, {"LISTENING", "FAILED"}, time.monotonic() + seconds)
    BASE.require(state.get("state") == "LISTENING", label + ":" + str(state))


def wait_zero(proc: subprocess.Popen, label: str, deadline: float) -> None:
    BASE.require(proc.wait(timeout=max(1, deadline - time.monotonic())) == 0, "PROCESS_FAILED:" + label)


def phase_config(
    *,
    run_id: str,
    head: str,
    tree: str,
    ports: list[int],
    internal_keys: dict,
    client_keys: dict,
    checkpoint_root: Path,
    restart_file: Path,
    recovery: bool,
    start_round: int,
    epochs: dict,
    sequences: dict,
    player_epochs: dict | None = None,
    action_counts: dict | None = None,
    fixed_receipts: int = 0,
    round_history: list | None = None,
    seam_crossings: int = 0,
    dig_hits: list | None = None,
) -> dict:
    return {
        "run_id": run_id,
        "subject_head": head,
        "subject_tree": tree,
        "ports": {"authority/a": ports[0], "authority/b": ports[1]},
        "gateway_port": ports[2],
        "internal_keys": internal_keys,
        "client_keys": client_keys,
        "mode": "interactive",
        "timeout_ms": 420000,
        "backend_rpc_timeout_ms": 45000,
        "client_reply_timeout_ms": 60000,
        "mvp8_root": str(checkpoint_root),
        "mvp8_construction_root": str(checkpoint_root / "construction-m0"),
        "mvp8_construction_cut_file": str(checkpoint_root / "construction-cut.json"),
        "mvp8_restart_file": str(restart_file),
        "mvp8_recovery": recovery,
        "mvp8_generation": 1,
        "mvp8_start_round": start_round,
        "mvp8_authority_epochs": epochs,
        "mvp8_player_ownership_epochs": player_epochs or epochs,
        "mvp8_initial_sequences": sequences,
        "mvp8_initial_action_counts": action_counts or {"DIG": 0, "ITEM": 0, "BUILD_ADD": 0, "BUILD_REMOVE": 0},
        "mvp8_initial_fixed_receipts": fixed_receipts,
        "mvp8_initial_round_history": round_history or [],
        "mvp8_initial_seam_crossings": seam_crossings,
        "mvp8_initial_dig_hits": dig_hits or [],
    }


def run_phase1(engine: Path, output: Path, checkpoint_root: Path, head: str, tree: str) -> dict:
    phase = output / "phase1"
    phase.mkdir()
    profiles = phase / "profiles"
    profiles.mkdir()
    ports = ports3()
    run_id = secrets.token_hex(16)
    internal_keys = {a: secrets.token_hex(32) for a in ("authority/a", "authority/b")}
    client_keys = {a: secrets.token_hex(32) for a in ("a", "b")}
    restart_file = checkpoint_root / "restart.json"
    cfg = phase_config(
        run_id=run_id,
        head=head,
        tree=tree,
        ports=ports,
        internal_keys=internal_keys,
        client_keys=client_keys,
        checkpoint_root=checkpoint_root,
        restart_file=restart_file,
        recovery=False,
        start_round=0,
        epochs={"a": 1, "b": 1},
        sequences={"a": 0, "b": 0},
        player_epochs={"a": 1, "b": 1},
    )
    paths = {role: phase / (role.replace("/", "-") + ".json") for role in ROLES}
    cfg["mvp8_progress_file"] = str(phase / "gateway-progress.json")
    original_mvp8 = {a: phase / f"initial-{a}-mvp8.json" for a in ("a", "b")}
    reconnect_path = phase / "reconnect-a.json"
    processes: dict[str, subprocess.Popen] = {}
    streams: dict[str, object] = {}
    commands: list[dict] = []
    error = ""
    start = time.monotonic()
    try:
        for role in ("authority/a", "authority/b"):
            start_process(
                engine, phase, profiles, commands, processes, streams,
                alias=role, cfg_role=role, cfg=cfg,
                tail=["--headless", "--path", str(ROOT), "--script", "res://scripts/runtime/networked_gameplay/mvp/v0_mvp8_authority_process.gd"],
                result_path=paths[role],
            )
        for role in ("authority/a", "authority/b"):
            wait_listening(paths[role], "AUTHORITY_NOT_LISTENING:" + role)
        start_process(
            engine, phase, profiles, commands, processes, streams,
            alias="gateway", cfg_role="gateway", cfg=cfg,
            tail=["--headless", "--path", str(ROOT), "--script", "res://scripts/runtime/networked_gameplay/mvp/v0_mvp8_gateway_process.gd"],
            result_path=paths["gateway"],
        )
        wait_listening(paths["gateway"], "GATEWAY_NOT_LISTENING", 60)

        for i, actor in enumerate(("a", "b")):
            role = "client/" + actor
            client_cfg = dict(cfg)
            client_cfg.update(
                automated=True,
                mvp8_progress_file=str(phase / f"client-{actor}-progress.json"),
                client_key=client_keys[actor],
                screenshot_file=str(phase / f"client-{actor}.png"),
                mvp4_capture_before=str(phase / f"client-{actor}-before.png"),
                mvp4_capture_after=str(phase / f"client-{actor}-after.png"),
                mvp4_evidence_file=str(phase / f"capture-{actor}.json"),
                mvp5_evidence_file=str(phase / f"material-{actor}.json"),
                mvp6_evidence_file=str(phase / f"construction-{actor}.json"),
                mvp8_evidence_file=str(original_mvp8[actor]),
            )
            start_process(
                engine, phase, profiles, commands, processes, streams,
                alias=role, cfg_role=role, cfg=client_cfg,
                tail=[
                    "--path", str(ROOT), "--resolution", "720x480",
                    "--position", f"{40 + i * 760},80",
                    "res://scenes/labs/mvp/v0_mvp8_bounded_workload.tscn",
                ],
                result_path=paths[role],
            )

        original_a_deadline = time.monotonic() + 260
        wait_zero(processes["client/a"], "client/a-original", original_a_deadline)

        reconnect_cfg = dict(cfg)
        reconnect_cfg.update(
            client_key=client_keys["a"],
            mvp8_client_phase="client-reconnect",
        )
        start_process(
            engine, phase, profiles, commands, processes, streams,
            alias="reconnect/a", cfg_role="client/a", cfg=reconnect_cfg,
            tail=["--headless", "--path", str(ROOT), "--script", "res://scripts/runtime/networked_gameplay/mvp/v0_mvp8_resume_client.gd"],
            result_path=reconnect_path,
        )

        deadline = time.monotonic() + 260
        for alias in ("reconnect/a", "client/b", "gateway", "authority/a", "authority/b"):
            wait_zero(processes[alias], alias, deadline)
        BASE.require(restart_file.is_file(), "MVP8_RESTART_RECEIPT_MISSING")
    except Exception as exc:
        error = type(exc).__name__ + ":" + str(exc)
    finally:
        stop_all(processes, streams)

    return {
        "phase": "phase1",
        "run_id": run_id,
        "error": error,
        "duration_seconds": time.monotonic() - start,
        "paths": {k: str(v) for k, v in paths.items()},
        "mvp8_evidence": {k: str(v) for k, v in original_mvp8.items()},
        "reconnect_path": str(reconnect_path),
        "restart_file": str(restart_file),
        "commands": commands,
        "returncodes": {k: p.returncode for k, p in processes.items()},
    }


def run_phase2(engine: Path, output: Path, checkpoint_root: Path, receipt: dict, head: str, tree: str) -> dict:
    phase = output / "phase2"
    phase.mkdir()
    profiles = phase / "profiles"
    profiles.mkdir()
    ports = ports3()
    run_id = secrets.token_hex(16)
    internal_keys = {a: secrets.token_hex(32) for a in ("authority/a", "authority/b")}
    client_keys = {a: secrets.token_hex(32) for a in ("a", "b")}
    restart_file = checkpoint_root / "restart.json"
    cfg = phase_config(
        run_id=run_id,
        head=head,
        tree=tree,
        ports=ports,
        internal_keys=internal_keys,
        client_keys=client_keys,
        checkpoint_root=checkpoint_root,
        restart_file=restart_file,
        recovery=True,
        start_round=int(receipt["next_round"]),
        epochs=dict(receipt["authority_epochs"]),
        sequences=dict(receipt["initial_sequences"]),
        player_epochs=dict(receipt["player_ownership_epochs"]),
        action_counts=dict(receipt["action_counts"]),
        fixed_receipts=int(receipt["fixed_receipts"]),
        round_history=list(receipt["round_history"]),
        seam_crossings=int(receipt["seam_crossings"]),
        dig_hits=list(receipt["dig_hits"]),
    )
    paths = {role: phase / (role.replace("/", "-") + ".json") for role in ROLES}
    processes: dict[str, subprocess.Popen] = {}
    streams: dict[str, object] = {}
    commands: list[dict] = []
    error = ""
    start = time.monotonic()
    try:
        for role in ("authority/a", "authority/b"):
            start_process(
                engine, phase, profiles, commands, processes, streams,
                alias=role, cfg_role=role, cfg=cfg,
                tail=["--headless", "--path", str(ROOT), "--script", "res://scripts/runtime/networked_gameplay/mvp/v0_mvp8_authority_process.gd"],
                result_path=paths[role],
            )
        for role in ("authority/a", "authority/b"):
            wait_listening(paths[role], "RECOVERED_AUTHORITY_NOT_LISTENING:" + role, 60)
        start_process(
            engine, phase, profiles, commands, processes, streams,
            alias="gateway", cfg_role="gateway", cfg=cfg,
            tail=["--headless", "--path", str(ROOT), "--script", "res://scripts/runtime/networked_gameplay/mvp/v0_mvp8_gateway_process.gd"],
            result_path=paths["gateway"],
        )
        wait_listening(paths["gateway"], "RECOVERED_GATEWAY_NOT_LISTENING", 70)
        for actor in ("a", "b"):
            role = "client/" + actor
            client_cfg = dict(cfg)
            client_cfg.update(client_key=client_keys[actor], mvp8_client_phase="post-server-restart")
            start_process(
                engine, phase, profiles, commands, processes, streams,
                alias=role, cfg_role=role, cfg=client_cfg,
                tail=["--headless", "--path", str(ROOT), "--script", "res://scripts/runtime/networked_gameplay/mvp/v0_mvp8_resume_client.gd"],
                result_path=paths[role],
            )
        deadline = time.monotonic() + 260
        for alias in ("client/a", "client/b", "gateway", "authority/a", "authority/b"):
            wait_zero(processes[alias], "recovered-" + alias, deadline)
    except Exception as exc:
        error = type(exc).__name__ + ":" + str(exc)
    finally:
        stop_all(processes, streams)

    return {
        "phase": "phase2",
        "run_id": run_id,
        "error": error,
        "duration_seconds": time.monotonic() - start,
        "paths": {k: str(v) for k, v in paths.items()},
        "commands": commands,
        "returncodes": {k: p.returncode for k, p in processes.items()},
    }


def spatially_distinct_hits(hits: list, minimum_m: float = 1.0) -> bool:
    if len(hits) != 4:
        return False
    for i, left in enumerate(hits):
        if not isinstance(left, list) or len(left) != 3:
            return False
        for right in hits[i + 1:]:
            if not isinstance(right, list) or len(right) != 3:
                return False
            squared = sum((float(a) - float(b)) ** 2 for a, b in zip(left, right))
            if squared < minimum_m * minimum_m:
                return False
    return True


def evidence_checks(phase1: dict, phase2: dict, receipt: dict, head: str, tree: str) -> dict[str, bool]:
    checks: dict[str, bool] = {}
    try:
        p1 = {role: read(Path(path)) for role, path in phase1["paths"].items()}
        p2 = {role: read(Path(path)) for role, path in phase2["paths"].items()}
        reconnect = read(Path(phase1["reconnect_path"]))
        initial = {a: read(Path(path)) for a, path in phase1["mvp8_evidence"].items()}
        g1, g2 = p1["gateway"], p2["gateway"]
        w1, w2 = g1["mvp8"], g2["mvp8"]

        p1_pids = {
            p1["authority/a"]["process_id"], p1["authority/b"]["process_id"],
            g1["gateway_process_id"], p1["client/a"]["process_id"], p1["client/b"]["process_id"],
            reconnect["process_id"],
        }
        p2_pids = {
            p2["authority/a"]["process_id"], p2["authority/b"]["process_id"],
            g2["gateway_process_id"], p2["client/a"]["process_id"], p2["client/b"]["process_id"],
        }
        checks["phase1_processes_distinct"] = len(p1_pids) == 6
        checks["server_restart_processes_distinct"] = len(p2_pids) == 5 and p1_pids.isdisjoint(p2_pids)
        checks["exact_subject"] = all(
            r.get("subject_head") == head for r in (
                p1["authority/a"], p1["authority/b"], g1, p2["authority/a"], p2["authority/b"], g2, reconnect,
                initial["a"], initial["b"], p2["client/a"], p2["client/b"],
            )
        )
        checks["phase1_passed"] = not phase1["error"] and g1["passed"] is True and w1["checkpointed"] is True and w1["round"] == 8
        checks["one_client_reconnect"] = (
            w1["reconnect_count"] == 1
            and w1["reconnect_complete"] is True
            and w1["original_peer"]
            and w1["reconnect_peer"]
            and w1["original_peer"] != w1["reconnect_peer"]
            and reconnect["passed"] is True
        )
        checkpoint_players = receipt["checkpoint"]["players"]
        checks["restart_receipt_exact"] = (
            receipt["schema"] == "distributed_world_simulator.mvp8_restart_receipt.v1"
            and receipt["subject_head"] == head
            and receipt["subject_tree"] == tree
            and receipt["next_round"] == 8
            and receipt["generation"] == 1
            and len(receipt["checkpoint"]["checkpoint_checksum"]) == 64
            and len(receipt["dig_hits"]) == 3
            and receipt.get("checkpoint_player_a_normalized") is True
            and set(receipt["authority_epochs"]) == {"a", "b"}
            and set(receipt["player_ownership_epochs"]) == {"a", "b"}
        )
        checks["checkpoint_both_players_durable"] = all(
            isinstance(checkpoint_players.get(actor), dict)
            and int(checkpoint_players[actor].get("ownership_epoch", 0)) >= 1
            and set(checkpoint_players[actor].get("position", {})) >= {"x", "y", "z"}
            for actor in ("a", "b")
        )
        checks["phase2_passed"] = not phase2["error"] and g2["passed"] is True and w2["recovery_boot"] is True and w2["round"] == TOTAL_ROUNDS
        checks["matter_resync_after_restart"] = (
            w2.get("matter_resynced") == {"a": True, "b": True}
            and p2["client/a"].get("matter_resynced") is True
            and p2["client/b"].get("matter_resynced") is True
        )
        checks["twelve_rounds_same_lineage"] = (
            len(w2["round_history"]) == TOTAL_ROUNDS
            and [row["round"] for row in w2["round_history"]] == list(range(TOTAL_ROUNDS))
        )
        checks["repeated_operations"] = w2["action_counts"] == EXPECTED_ACTIONS
        checks["four_spatially_distinct_digs"] = spatially_distinct_hits(list(w2.get("dig_hits", [])))
        checks["seam_crossings"] = int(w2["seam_crossings"]) >= 4
        checks["responsive_fixed_tick"] = (
            int(w2["fixed_receipts"]) >= 24
            and reconnect["fixed_input_receipts"] > 0
            and p2["client/a"]["fixed_input_receipts"] > 0
            and p2["client/b"]["fixed_input_receipts"] > 0
            and reconnect["max_reply_ms"] < 30000
            and p2["client/a"]["max_reply_ms"] < 30000
            and p2["client/b"]["max_reply_ms"] < 30000
        )
        bounds = w2["bounds"]
        authority = bounds["authority"]
        checks["bounded_gateway_state"] = (
            bounds["operation_fingerprints"] <= 256
            and bounds["ledger"]["tracked_count"] <= 512
            and all(v <= 512 for v in bounds["backend_sequences"].values())
            and all(v <= 512 for v in bounds["client_sequences"].values())
            and all(v <= 128 for v in bounds["input_observations"].values())
        )
        checks["bounded_owner_state"] = (
            authority["durable_replay_pending"] <= 32
            and authority["construction_terminal_commands"] <= 16
            and authority["matter_stream_sequence"] <= 64
            and authority["duplicate_item_identity"] is False
            and authority["item_count"] == authority["unique_item_count"]
        )
        checks["construction_identity_stable"] = (
            authority["construction_id"]
            and p1["authority/a"]["mvp6"]["construction"]["construct_id"]
            == p2["authority/a"]["mvp6"]["construction"]["construct_id"]
            == authority["construction_id"]
        )
        checks["current_state_after_restart"] = (
            p2["client/a"]["collision_part_count"] == 100
            and p2["client/b"]["collision_part_count"] == 100
            and len(p2["client/a"]["current_world_digest"]) == 64
            and len(p2["client/b"]["current_world_digest"]) == 64
        )
        checks["initial_graphical_clients_passed"] = initial["a"]["passed"] is True and initial["b"]["passed"] is True
        checks["no_self_acceptance"] = (
            g1["mvp8"]["mvp8_predicate_verified"] is False
            and g2["mvp8"]["mvp8_predicate_verified"] is False
        )
    except (KeyError, TypeError, ValueError, IndexError):
        checks["well_formed_mvp8_evidence"] = False
    return checks


def negative_controls(phase1: dict, phase2: dict, receipt: dict, head: str, tree: str) -> list[str]:
    p1 = {role: read(Path(path)) for role, path in phase1["paths"].items()}
    p2 = {role: read(Path(path)) for role, path in phase2["paths"].items()}
    reconnect = read(Path(phase1["reconnect_path"]))
    initial = {a: read(Path(path)) for a, path in phase1["mvp8_evidence"].items()}

    def packed():
        return {
            "p1": copy.deepcopy(p1), "p2": copy.deepcopy(p2),
            "reconnect": copy.deepcopy(reconnect), "initial": copy.deepcopy(initial),
            "receipt": copy.deepcopy(receipt),
        }

    def check_pack(x: dict) -> bool:
        q1 = dict(phase1); q2 = dict(phase2)
        # Temporary objects are evaluated through a local equivalent of the
        # core invariants instead of rewriting raw evidence files.
        g1, g2 = x["p1"]["gateway"]["mvp8"], x["p2"]["gateway"]["mvp8"]
        b = g2.get("bounds", {})
        a = b.get("authority", {})
        return all([
            g1.get("reconnect_count") == 1,
            g1.get("original_peer") != g1.get("reconnect_peer"),
            x["receipt"].get("next_round") == 8,
            x["receipt"].get("checkpoint_player_a_normalized") is True,
            all(
                isinstance(x["receipt"].get("checkpoint", {}).get("players", {}).get(actor), dict)
                and int(x["receipt"]["checkpoint"]["players"][actor].get("ownership_epoch", 0)) >= 1
                and set(x["receipt"]["checkpoint"]["players"][actor].get("position", {})) >= {"x", "y", "z"}
                for actor in ("a", "b")
            ),
            g2.get("round") == 12,
            len(g2.get("round_history", [])) == 12,
            g2.get("action_counts") == EXPECTED_ACTIONS,
            int(g2.get("seam_crossings", 0)) >= 4,
            int(g2.get("fixed_receipts", 0)) >= 24,
            spatially_distinct_hits(list(g2.get("dig_hits", []))),
            g2.get("matter_resynced") == {"a": True, "b": True},
            int(b.get("operation_fingerprints", 9999)) <= 256,
            int(b.get("ledger", {}).get("tracked_count", 9999)) <= 512,
            a.get("duplicate_item_identity") is False,
            int(a.get("construction_terminal_commands", 9999)) <= 16,
            x["p2"]["client/a"].get("collision_part_count") == 100,
        ])

    mutations = {
        "skip_reconnect": lambda x: x["p1"]["gateway"]["mvp8"].update(reconnect_count=0),
        "reuse_same_peer": lambda x: x["p1"]["gateway"]["mvp8"].update(reconnect_peer=x["p1"]["gateway"]["mvp8"]["original_peer"]),
        "wrong_restart_round": lambda x: x["receipt"].update(next_round=7),
        "missing_round": lambda x: x["p2"]["gateway"]["mvp8"]["round_history"].pop(),
        "missing_postrestart_motion": lambda x: x["p2"]["gateway"]["mvp8"].update(fixed_receipts=20),
        "queue_overflow": lambda x: x["p2"]["gateway"]["mvp8"]["bounds"].update(operation_fingerprints=257),
        "duplicate_item_identity": lambda x: x["p2"]["gateway"]["mvp8"]["bounds"]["authority"].update(duplicate_item_identity=True),
        "terminal_overflow": lambda x: x["p2"]["gateway"]["mvp8"]["bounds"]["authority"].update(construction_terminal_commands=17),
        "missing_collision": lambda x: x["p2"]["client/a"].update(collision_part_count=99),
        "lost_build_cycle": lambda x: x["p2"]["gateway"]["mvp8"]["action_counts"].update(BUILD_ADD=1),
        "missing_dig_hit": lambda x: x["p2"]["gateway"]["mvp8"]["dig_hits"].pop(),
        "missing_matter_resync": lambda x: x["p2"]["gateway"]["mvp8"]["matter_resynced"].update(a=False),
        "overlapping_dig_hit": lambda x: x["p2"]["gateway"]["mvp8"]["dig_hits"].__setitem__(3, list(x["p2"]["gateway"]["mvp8"]["dig_hits"][2])),
        "missing_checkpoint_player": lambda x: x["receipt"]["checkpoint"]["players"].pop("a"),
    }
    rejected: list[str] = []
    for name, mutate in mutations.items():
        x = packed()
        mutate(x)
        BASE.require(not check_pack(x), "MVP8_FALSE_POSITIVE:" + name)
        rejected.append(name)
    return rejected


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    engine, output = args.engine.resolve(), args.output.resolve()
    BASE.require(engine.is_file(), "ENGINE_REQUIRED")
    BASE.require(sys.platform in P4.PINNED_ENGINES and BASE.sha(engine) == P4.PINNED_ENGINES[sys.platform], "EXACT_DOUBLE_ENGINE_REQUIRED")
    BASE.require(not output.exists(), "PRESERVE_PREVIOUS_EVIDENCE")
    BASE.require(not BASE.git("status", "--porcelain", "--untracked-files=no"), "TRACKED_CHECKOUT_DIRTY")
    head, tree = BASE.git("rev-parse", "HEAD"), BASE.git("rev-parse", "HEAD^{tree}")
    BASE.require(head == os.environ.get("EXPECTED_HEAD", head), "EXACT_HEAD_MISMATCH")
    output.mkdir(parents=True)
    checkpoint_root = output / "checkpoint"
    checkpoint_root.mkdir()

    started = time.monotonic()
    error = ""
    project_import: dict = {}
    phase1: dict = {}
    phase2: dict = {}
    receipt: dict = {}
    checks: dict[str, bool] = {}
    negatives: list[str] = []
    try:
        project_import = prepare_project_import(engine, output)
        phase1 = run_phase1(engine, output, checkpoint_root, head, tree)
        BASE.require(not phase1["error"], "MVP8_PHASE1_FAILED:" + phase1["error"])
        receipt = read(Path(phase1["restart_file"]))
        BASE.require(bool(receipt), "MVP8_RESTART_RECEIPT_REQUIRED")
        phase2 = run_phase2(engine, output, checkpoint_root, receipt, head, tree)
        BASE.require(not phase2["error"], "MVP8_PHASE2_FAILED:" + phase2["error"])
        checks = evidence_checks(phase1, phase2, receipt, head, tree)
        BASE.require(all(checks.values()), "MVP8_CHECK_FAILURE:" + ",".join(k for k, v in checks.items() if not v))
        negatives = negative_controls(phase1, phase2, receipt, head, tree)
    except Exception as exc:
        error = type(exc).__name__ + ":" + str(exc)
        if phase1 and phase2:
            checks = evidence_checks(phase1, phase2, receipt, head, tree)

    fatal_logs: list[str] = []
    for log in output.rglob("*.log"):
        text = log.read_text(encoding="utf-8", errors="replace")
        if any(marker in text for marker in BASE.ERRORS) or re.search(r"(?im)^\s*(?:SCRIPT ERROR|ERROR):|Parse Error|Compile Error", text):
            fatal_logs.append(str(log.relative_to(output)))

    passed = (
        not error
        and checks
        and all(checks.values())
        and len(negatives) == 14
        and not fatal_logs
        and not BASE.git("status", "--porcelain", "--untracked-files=no")
    )
    manifest = {
        "schema": "distributed_world_simulator.mvp8_bounded_workload_manifest.v1",
        "subject_head": head,
        "subject_tree": tree,
        "engine_sha256": BASE.sha(engine),
        "passed": passed,
        "error": error,
        "checks": checks,
        "negative_controls": negatives,
        "fatal_logs": fatal_logs,
        "phase1": phase1,
        "phase2": phase2,
        "restart_receipt": receipt,
        "duration_seconds": time.monotonic() - started,
        "project_import": project_import,
        "one_connected_two_client_gameplay_loop_executed": bool(phase1 and phase2),
        "client_reconnect_inside_workload_executed": bool(receipt),
        "server_world_restart_inside_workload_executed": bool(phase2),
        "bounded_state_checked": bool(checks.get("bounded_gateway_state") and checks.get("bounded_owner_state")),
        "mvp8_predicate_verified": False,
        "independent_verdict": False,
        "files": [],
    }
    for path in sorted(p for p in output.rglob("*") if p.is_file() and p.name != "manifest.json"):
        manifest["files"].append({
            "path": str(path.relative_to(output)).replace("\\", "/"),
            "bytes": path.stat().st_size,
            "sha256": BASE.sha(path),
        })
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "passed": passed,
        "error": error,
        "failed_checks": [k for k, v in checks.items() if not v],
        "negative_controls": negatives,
        "fatal_logs": fatal_logs,
    }, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
