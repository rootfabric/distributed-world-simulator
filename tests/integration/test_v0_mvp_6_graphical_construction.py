#!/usr/bin/env python3
"""MVP6 live gate: two graphical clients + gateway + two real authorities.

The inherited MVP3/MVP4/MVP5 story runs first. Then one canonical ~100-part
Construction is derived on both clients; ADD/REMOVE enter authority/b and commit
on authority/a with exact replay. This runner never marks the predicate verified.
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

P5 = load("mvp6_unchanged_mvp5_graphical", "tests/integration/test_v0_mvp_5_graphical_material.py")
P4, V4, BASE, ROLES = P5.P4, P5.V4, P5.BASE, P5.ROLES


def construction_checks(reports: dict, clients: dict, head: str, run_id: str) -> dict[str, bool]:
    checks: dict[str, bool] = {}
    try:
        gateway = reports["gateway"]["mvp6"]
        owner = reports["authority/a"]["mvp6"]
        replica = reports["authority/b"]["mvp6"]
        checks["gateway_complete"] = gateway["complete"] is True and gateway["phase"] == "REMOVED" and gateway["mutation_count"] == 2
        checks["exact_replays"] = gateway["replays"] == {"ADD": True, "REMOVE": True}
        checks["single_canonical_owner"] = owner["canonical_construction_owned"] is True and replica["canonical_construction_owned"] is False and replica["replica_read_only"] is True
        checks["final_owner_replica_equal"] = owner["construction"]["checksum"] == replica["construction"]["checksum"] == gateway["construction"]["checksum"] == gateway["authority_b_replica"]["checksum"]
        checks["final_part_count_100"] = len(owner["construction"]["parts"]) == 100 and len(replica["construction"]["parts"]) == 100
        checks["same_item_graph_not_private_material"] = owner["predicate_verified"] is False and gateway["canonical_state_owned"] is False
        apid = reports["authority/a"]["process_id"]
        bpid = reports["authority/b"]["process_id"]
        route_rows = gateway["route_processes"]
        checks["real_a_b_route_processes"] = len(route_rows) == 4 and all(r["authority_a_process_id"] == apid and r["authority_b_process_id"] == bpid and apid != bpid for r in route_rows)
        checks["two_clients_exact_subject"] = set(clients) == {"a", "b"} and all(clients[a]["subject_head"] == head and clients[a]["run_id"] == run_id and clients[a]["actor"] == a for a in clients)
        checks["two_clients_passed_read_only"] = all(clients[a]["passed"] is True and clients[a]["canonical_state_owned"] is False and clients[a]["direct_authority_references"] == 0 and clients[a]["mvp6_predicate_verified"] is False for a in clients)
        checks["five_distinct_processes"] = len({reports["authority/a"]["process_id"], reports["authority/b"]["process_id"], reports["gateway"]["gateway_process_id"], clients["a"]["process_id"], clients["b"]["process_id"]}) == 5
        expected = {"BASE": 100, "ADDED": 101, "REMOVED": 100}
        for phase, count in expected.items():
            arow, brow = clients["a"]["phases"][phase], clients["b"]["phases"][phase]
            checks[f"{phase}:canonical_checksum_converged"] = arow["construction_checksum"] == brow["construction_checksum"] and len(arow["construction_checksum"]) == 64
            checks[f"{phase}:derived_descriptor_converged"] = arow["descriptor_checksum"] == brow["descriptor_checksum"] and len(arow["descriptor_checksum"]) == 64
            checks[f"{phase}:parts_collision_exact"] = all(row["part_count"] == count and row["collision_part_count"] == count and row["canonical_truth_owner"] is False and row["direct_authority_references"] == 0 for row in (arow, brow))
        checks["add_changes_checksum"] = clients["a"]["phases"]["BASE"]["construction_checksum"] != clients["a"]["phases"]["ADDED"]["construction_checksum"]
        checks["remove_changes_checksum"] = clients["a"]["phases"]["ADDED"]["construction_checksum"] != clients["a"]["phases"]["REMOVED"]["construction_checksum"]
        checks["both_clients_observed_every_phase"] = all(len(gateway["observed"][phase]) == 2 for phase in expected)
    except (KeyError, TypeError, IndexError, ValueError):
        checks["well_formed_mvp6_evidence"] = False
    return checks


def construction_negatives(reports: dict, clients: dict, head: str, run_id: str) -> list[str]:
    mutations = {
        "duplicate_owner": lambda r, c: r["authority/b"]["mvp6"].update(canonical_construction_owned=True),
        "one_sided_replica": lambda r, c: r["authority/b"]["mvp6"]["construction"].update(checksum="0" * 64),
        "missing_add_replay": lambda r, c: r["gateway"]["mvp6"]["replays"].update(ADD=False),
        "fake_same_process_route": lambda r, c: r["gateway"]["mvp6"]["route_processes"][0].update(authority_b_process_id=r["authority/a"]["process_id"]),
        "duplicate_client_process": lambda r, c: c["b"].update(process_id=c["a"]["process_id"]),
        "client_claims_truth": lambda r, c: c["a"].update(canonical_state_owned=True),
        "missing_collision_part": lambda r, c: c["b"]["phases"]["ADDED"].update(collision_part_count=100),
        "stale_subject": lambda r, c: c["a"].update(subject_head="0" * 40),
    }
    rejected: list[str] = []
    for name, mutate in mutations.items():
        r, c = copy.deepcopy(reports), copy.deepcopy(clients)
        mutate(r, c)
        BASE.require(not all(construction_checks(r, c, head, run_id).values()), "MVP6_FALSE_POSITIVE:" + name)
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
    output.mkdir(parents=True)
    run_id = secrets.token_hex(16)
    sockets = [socket.socket(socket.AF_INET, socket.SOCK_DGRAM) for _ in range(3)]
    try:
        for sock in sockets: sock.bind(("127.0.0.1", 0))
        ports = [sock.getsockname()[1] for sock in sockets]
    finally:
        for sock in sockets: sock.close()
    authority_ports = {"authority/a": ports[0], "authority/b": ports[1]}
    internal_keys = {a: secrets.token_hex(32) for a in authority_ports}
    client_keys = {a: secrets.token_hex(32) for a in ("a", "b")}
    paths = {role: output / (role.replace("/", "-") + ".json") for role in ROLES}
    processes: dict[str, subprocess.Popen] = {}
    streams, commands = {}, []
    profiles = tempfile.TemporaryDirectory(prefix="dws-mvp6-profile-")

    def launch(role: str, tail: list[str], extra: dict) -> None:
        cfg = {"role": role, "run_id": run_id, "subject_head": head, "result_file": str(paths[role]), "ports": authority_ports, "gateway_port": ports[2], "timeout_ms": 240000, "backend_rpc_timeout_ms": 90000, "client_reply_timeout_ms": 120000} | extra
        env = os.environ.copy()
        env.update(PYTHONUTF8="1", BREAKPOINT_RUNTIME_DISABLED="1", DWS_MVP3_LIVE_CONFIG=json.dumps(cfg, separators=(",", ":")))
        profile = Path(profiles.name) / role.replace("/", "-")
        for variable, directory in {"XDG_DATA_HOME":"data", "XDG_CONFIG_HOME":"config", "XDG_CACHE_HOME":"cache", "APPDATA":"roaming", "LOCALAPPDATA":"local"}.items():
            p = profile / directory; p.mkdir(parents=True, exist_ok=True); env[variable] = str(p)
        argv = [str(engine), "--audio-driver", "Dummy", *tail]
        log = output / (role.replace("/", "-") + ".log")
        streams[role] = log.open("w", encoding="utf-8")
        processes[role] = subprocess.Popen(argv, cwd=ROOT, env=env, stdout=streams[role], stderr=subprocess.STDOUT, text=True)
        commands.append({"role":role, "argv":argv, "log":log.name, "isolated_user_data":True})

    start, error = time.monotonic(), ""
    try:
        for role in ("authority/a", "authority/b"):
            launch(role, ["--headless", "--path", str(ROOT), "--script", "res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_guarded_authority_process.gd"], {"internal_keys":internal_keys})
        for role in ("authority/a", "authority/b"):
            BASE.require(BASE.wait_state(paths[role], {"LISTENING", "FAILED"}, time.monotonic() + 30).get("state") == "LISTENING", "AUTHORITY_NOT_LISTENING:" + role)
        launch("gateway", ["--headless", "--path", str(ROOT), "--script", "res://scripts/runtime/networked_gameplay/mvp/v0_mvp6_guarded_gateway_process.gd"], {"internal_keys":internal_keys, "client_keys":client_keys, "mode":"interactive"})
        BASE.require(BASE.wait_state(paths["gateway"], {"LISTENING", "FAILED"}, time.monotonic() + 50).get("state") == "LISTENING", "GATEWAY_NOT_LISTENING")
        for i, actor in enumerate(("a", "b")):
            launch("client/" + actor, ["--path", str(ROOT), "--resolution", "720x480", "--position", f"{40 + i * 760},80", "res://scenes/labs/mvp/v0_mvp6_live_construction.tscn"], {
                "automated":True, "client_key":client_keys[actor], "screenshot_file":str(output/f"client-{actor}.png"),
                "mvp4_capture_before":str(output/f"client-{actor}-before.png"), "mvp4_capture_after":str(output/f"client-{actor}-after.png"),
                "mvp4_evidence_file":str(output/f"capture-{actor}.json"), "mvp5_evidence_file":str(output/f"material-{actor}.json"),
                "mvp6_evidence_file":str(output/f"construction-{actor}.json"),
            })
        deadline = time.monotonic() + 235
        for role in ("client/a", "client/b", "gateway", "authority/a", "authority/b"):
            BASE.require(processes[role].wait(timeout=max(1, deadline-time.monotonic())) == 0, "PROCESS_FAILED:" + role)
    except Exception as exc:
        error = type(exc).__name__ + ":" + str(exc)
    finally:
        for proc in processes.values():
            if proc.poll() is None: proc.terminate()
        for proc in processes.values():
            if proc.poll() is None:
                try: proc.wait(timeout=5)
                except subprocess.TimeoutExpired: proc.kill(); proc.wait()
        for stream in streams.values(): stream.close()
        profiles.cleanup()

    reports = {role: BASE.read_json(path) for role, path in paths.items()}
    captures = {a: BASE.read_json(output/f"capture-{a}.json") for a in ("a", "b")}
    materials = {a: BASE.read_json(output/f"material-{a}.json") for a in ("a", "b")}
    clients = {a: BASE.read_json(output/f"construction-{a}.json") for a in ("a", "b")}
    checks = {"mvp4:" + k:v for k,v in P4.evidence_checks(reports, captures, head, run_id).items()}
    checks.update({"mvp5:" + k:v for k,v in P5.material_checks(reports, materials, head, run_id).items()})
    checks.update({"mvp6:" + k:v for k,v in construction_checks(reports, clients, head, run_id).items()})
    for role in ROLES:
        log = output / (role.replace("/", "-") + ".log")
        checks["exit:" + role] = role in processes and processes[role].returncode == 0
        text = log.read_text(errors="replace") if log.is_file() else "SCRIPT ERROR: missing log"
        checks["log:" + role] = not any(marker in text for marker in BASE.ERRORS) and not re.search(r"(?im)^\s*(?:SCRIPT ERROR|ERROR):|Parse Error|Compile Error", text)

    visible, hud_cases, negatives = {}, [], []
    try:
        for actor in ("a", "b"):
            before, after = output/f"client-{actor}-before.png", output/f"client-{actor}-after.png"
            ca, cb = V4.certified_region(captures[actor], actor, "before"), V4.certified_region(captures[actor], actor, "after")
            width, height, _ = V4.pixels.rgba(before)
            region = V4.pixels.union_region(ca, cb, width, height)
            visible[actor] = V4.pixels.terrain_change(before, after, dict(zip(("x","y","w","h"), region)))
            checks["visible_terrain:" + actor] = visible[actor]["passed"] and visible[actor]["terrain_changed_pixels"] >= 32
            checks["viewport:" + actor] = width == 720 and 400 <= height <= 480
            hud_cases.append(V4.hud_only_falsification(output, actor, before, ca, cb))
        if not error and all(checks.values()):
            negatives = construction_negatives(reports, clients, head, run_id)
    except (OSError, KeyError, ValueError, RuntimeError, TypeError) as exc:
        error += ";" + type(exc).__name__ + ":" + str(exc)

    passed = not error and all(checks.values()) and len(negatives) == 8 and len(hud_cases) == 2
    manifest = {
        "schema":"distributed_world_simulator.mvp6_graphical_construction_manifest.v1",
        "subject_head":head, "subject_tree":tree, "run_id":run_id, "engine_sha256":BASE.sha(engine),
        "commands":commands, "error":error, "checks":checks, "visible_terrain":visible,
        "hud_only_falsification":hud_cases, "negative_controls":negatives, "passed":passed,
        "duration_seconds":time.monotonic()-start, "five_process_graphical_executed":True,
        "manual_input_executed":False, "restart_executed":False,
        "mvp6_cross_authority_construction_seam_verified":False,
        "mvp6_predicate_verified":False, "independent_verdict":False, "files":[],
    }
    for path in sorted(output.iterdir()):
        if path.is_file() and path.name != "manifest.json":
            manifest["files"].append({"path":path.name, "bytes":path.stat().st_size, "sha256":BASE.sha(path)})
    (output/"manifest.json").write_text(json.dumps(manifest, indent=2)+"\n")
    print(json.dumps({"passed":passed, "error":error, "failed_checks":[k for k,v in checks.items() if not v], "negative_controls":negatives}, indent=2))
    return 0 if passed else 1

if __name__ == "__main__":
    raise SystemExit(main())
