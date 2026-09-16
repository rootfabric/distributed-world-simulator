#!/usr/bin/env python3
"""MVP5: five real processes, three deliveries of one operation, one output.

Reuses the unchanged MVP4 evidence and terrain-only pixel validators. This
runner proves automated native-path composition, not manual/restart acceptance.
"""
from __future__ import annotations
import argparse
import copy
import importlib.util
import json
import math
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

P4 = load("mvp5_unchanged_mvp4_process", "tests/integration/test_v0_mvp_4_graphical_shared_dig.py")
V4 = load("mvp5_unchanged_mvp4_visible", "tests/integration/test_v0_mvp_4_visible_graphical_shared_dig.py")
BASE, ROLES = P4.BASE, P4.ROLES

def integer(value) -> bool:
    return not isinstance(value, bool) and isinstance(value, (int, float)) and math.isfinite(value) and value == int(value)

def material_checks(reports: dict, material: dict, head: str, run_id: str) -> dict[str, bool]:
    checks = {}
    try:
        source = reports["authority/a"]["mvp4"]
        canonical = source["material_projection"]["details"]
        gateway = reports["gateway"]["mvp5"]
        checks["canonical_material_owner"] = source["material_projection"]["success"] is True and source["exactly_once_owner"] == "CANONICAL_ITEM_GRAPH_REPLAY_LEDGER" and source["mvp5_receipt_store_owned"] is False and canonical["canonical_state_owned"] is False and canonical["item_owner"] == "CANONICAL_ITEM_GRAPH"
        checks["two_material_observers"] = set(material) == {"a", "b"} and gateway["both_material_observed"] is True
        for actor in ("a", "b"):
            row = material[actor]
            checks[actor + ":exact_material_subject"] = row["subject_head"] == head and row["run_id"] == run_id and row["actor"] == actor and row["process_id"] == reports["client/" + actor]["process_id"]
            checks[actor + ":material_observation_pass"] = row["passed"] is True and row["canonical_state_owned"] is False and row["mvp5_predicate_verified"] is False and row["manual_input_executed"] is False
            checks[actor + ":actual_owner_material"] = row["after"] == canonical and gateway["observed"][actor] == canonical and row["before"] == gateway["baselines"][actor]
            checks[actor + ":baseline_precedes_mutation"] = row["before"]["matter_stream_sequence"] == 0 and row["after"]["matter_stream_sequence"] == 1
        receipts = material["a"]["receipts"]
        checks["three_actual_requests_one_actor"] = len(receipts) == 3 and material["b"]["receipts"] == []
        first = receipts[0]
        quantity = first["output_quantity"]
        checks["positive_integral_output"] = integer(quantity) and quantity > 0 and first["logical_player_id"] == "a"
        stable = ("batch_id", "batch_checksum", "source_operation_id", "output_operation_id", "output_item_id", "output_definition_id", "output_quantity", "source_id", "total_mass_kg", "represented_mass_kg", "residual_mass_kg")
        checks["retries_keep_exact_output"] = all(all(r[k] == first[k] for k in stable) for r in receipts)
        checks["fresh_then_replayed"] = first["output_created_this_call"] is True and first["item_graph_replay"] is False and first["matter_replay"] is False and all(r["output_created_this_call"] is False and r["item_graph_replay"] is True and r["matter_replay"] is True for r in receipts[1:])
        checks["replay_does_not_advance_graph"] = all(r["current_item_graph_revision"] == canonical["item_graph_revision"] and r["current_item_graph_tick"] == canonical["item_graph_tick"] for r in receipts)
        native = source["dig_observations"][0]["output_delivery"]["delivery"]
        checks["receipt_is_actual_p7_delivery"] = all(first[k] == native[k] for k in stable) and first["receipt_source"] == "MW4_BATCH_AND_CANONICAL_ITEM_GRAPH_REPLAY_LOOKUP" and all(r["receipt_store_owned"] is False for r in receipts)
        checks["mass_conserved_with_residual"] = math.isfinite(first["total_mass_kg"]) and abs(first["total_mass_kg"] - first["represented_mass_kg"] - first["residual_mass_kg"]) <= 1e-9 and first["represented_mass_kg"] == quantity and 0 <= first["residual_mass_kg"] < 1
        items = canonical["items"]
        ids = [item["item_id"] for item in items]
        checks["no_duplicate_item_ids"] = len(ids) == len(set(ids))
        minted = [item for item in items if item["item_id"] == first["output_item_id"]]
        checks["one_actual_inventory_output"] = len(minted) == 1 and minted[0]["quantity"] == quantity and minted[0]["player_id"] == "a" and minted[0]["definition_id"] == "item/ore"
        checks["inventory_totals_derived_from_items"] = all(integer(item["quantity"]) and item["quantity"] > 0 for item in items) and all(canonical["totals"][a] == sum(item["quantity"] for item in items if item["player_id"] == a) for a in ("a", "b"))
        checks["single_issuance_delta"] = canonical["totals"]["a"] - material["a"]["before"]["totals"]["a"] == quantity and canonical["totals"]["b"] == material["b"]["before"]["totals"]["b"]
        checks["baseline_material_agrees"] = material["a"]["before"]["material_digest"] == material["b"]["before"]["material_digest"]
    except (KeyError, TypeError, IndexError, ValueError, OverflowError):
        checks["well_formed_material_evidence"] = False
    return checks

def material_negatives(reports: dict, material: dict, head: str, run_id: str) -> list[str]:
    mutations = {
        "inflated_receipt": lambda r, m: m["a"]["receipts"][0].update(output_quantity=m["a"]["receipts"][0]["output_quantity"] + 1),
        "different_replay_item": lambda r, m: m["a"]["receipts"][1].update(output_item_id="item/forged"),
        "replay_mutates_graph": lambda r, m: m["a"]["receipts"][1].update(current_item_graph_revision=-1),
        "missing_retry": lambda r, m: m["a"]["receipts"].pop(),
        "lost_residual": lambda r, m: m["a"]["receipts"][0].update(residual_mass_kg=-1),
        "client_b_disagrees": lambda r, m: m["b"]["after"]["totals"].update(a=-1),
        "duplicate_canonical_item": lambda r, m: r["authority/a"]["mvp4"]["material_projection"]["details"]["items"].append(copy.deepcopy(r["authority/a"]["mvp4"]["material_projection"]["details"]["items"][0])),
        "stale_subject": lambda r, m: m["a"].update(subject_head="0" * 40),
        "client_owns_material": lambda r, m: m["b"].update(canonical_state_owned=True),
        "fake_native_receipt": lambda r, m: r["authority/a"]["mvp4"]["dig_observations"][0]["output_delivery"]["delivery"].update(output_item_id="item/forged"),
    }
    rejected = []
    for name, mutate in mutations.items():
        r, m = copy.deepcopy(reports), copy.deepcopy(material)
        mutate(r, m)
        BASE.require(not all(material_checks(r, m, head, run_id).values()), "MVP5_FALSE_POSITIVE:" + name)
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
    processes, streams, commands = {}, {}, []
    profiles = tempfile.TemporaryDirectory(prefix="dws-mvp5-profile-")
    def launch(role: str, tail: list[str], extra: dict) -> None:
        cfg = {"role": role, "run_id": run_id, "subject_head": head, "result_file": str(paths[role]), "ports": authority_ports, "gateway_port": ports[2], "timeout_ms": 210000, "backend_rpc_timeout_ms": 30000, "client_reply_timeout_ms": 45000} | extra
        env = os.environ.copy()
        env.update(PYTHONUTF8="1", BREAKPOINT_RUNTIME_DISABLED="1", DWS_MVP3_LIVE_CONFIG=json.dumps(cfg, separators=(",", ":")))
        # Engine user-data/cache initialization is per owned child, not a race
        # between two clients or a write into the operator's personal profile.
        profile = Path(profiles.name) / role.replace("/", "-")
        for variable, directory in {"XDG_DATA_HOME": "data", "XDG_CONFIG_HOME": "config", "XDG_CACHE_HOME": "cache", "APPDATA": "roaming", "LOCALAPPDATA": "local"}.items():
            directory_path = profile / directory
            directory_path.mkdir(parents=True, exist_ok=True)
            env[variable] = str(directory_path)
        argv = [str(engine), "--audio-driver", "Dummy", *tail]
        log = output / (role.replace("/", "-") + ".log")
        streams[role] = log.open("w", encoding="utf-8")
        processes[role] = subprocess.Popen(argv, cwd=ROOT, env=env, stdout=streams[role], stderr=subprocess.STDOUT, text=True)
        commands.append({"role": role, "argv": argv, "log": log.name, "isolated_user_data": True})
    start, error = time.monotonic(), ""
    try:
        for role in ("authority/a", "authority/b"):
            launch(role, ["--headless", "--path", str(ROOT), "--script", "res://scripts/runtime/networked_gameplay/mvp/v0_mvp5_authority_process.gd"], {"internal_keys": internal_keys})
        for role in ("authority/a", "authority/b"):
            BASE.require(BASE.wait_state(paths[role], {"LISTENING", "FAILED"}, time.monotonic() + 25).get("state") == "LISTENING", "AUTHORITY_NOT_LISTENING:" + role)
        launch("gateway", ["--headless", "--path", str(ROOT), "--script", "res://scripts/runtime/networked_gameplay/mvp/v0_mvp5_gateway_process.gd"], {"internal_keys": internal_keys, "client_keys": client_keys, "mode": "interactive"})
        BASE.require(BASE.wait_state(paths["gateway"], {"LISTENING", "FAILED"}, time.monotonic() + 45).get("state") == "LISTENING", "GATEWAY_NOT_LISTENING")
        for i, actor in enumerate(("a", "b")):
            launch("client/" + actor, ["--path", str(ROOT), "--resolution", "720x480", "--position", f"{40 + i * 760},80", "res://scenes/labs/mvp/v0_mvp5_live_material_output.tscn"], {"automated": True, "client_key": client_keys[actor], "screenshot_file": str(output / f"client-{actor}.png"), "mvp4_capture_before": str(output / f"client-{actor}-before.png"), "mvp4_capture_after": str(output / f"client-{actor}-after.png"), "mvp4_evidence_file": str(output / f"capture-{actor}.json"), "mvp5_evidence_file": str(output / f"material-{actor}.json")})
        deadline = time.monotonic() + 205
        for role in ("client/a", "client/b", "gateway", "authority/a", "authority/b"):
            BASE.require(processes[role].wait(timeout=max(1, deadline - time.monotonic())) == 0, "PROCESS_FAILED:" + role)
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
    captures = {a: BASE.read_json(output / f"capture-{a}.json") for a in ("a", "b")}
    materials = {a: BASE.read_json(output / f"material-{a}.json") for a in ("a", "b")}
    checks = {"mvp4:" + k: v for k, v in P4.evidence_checks(reports, captures, head, run_id).items()}
    checks.update(material_checks(reports, materials, head, run_id))
    for role in ROLES:
        log = output / (role.replace("/", "-") + ".log")
        checks["exit:" + role] = role in processes and processes[role].returncode == 0
        text = log.read_text(errors="replace") if log.is_file() else "SCRIPT ERROR: missing log"
        checks["log:" + role] = not any(marker in text for marker in BASE.ERRORS) and not re.search(r"(?im)^\s*(?:SCRIPT ERROR|ERROR):|Parse Error|Compile Error", text)
    visible, hud_cases, negatives = {}, [], []
    try:
        for actor in ("a", "b"):
            before, after = output / f"client-{actor}-before.png", output / f"client-{actor}-after.png"
            ca, cb = V4.certified_region(captures[actor], actor, "before"), V4.certified_region(captures[actor], actor, "after")
            width, height, _ = V4.pixels.rgba(before)
            region = V4.pixels.union_region(ca, cb, width, height)
            visible[actor] = V4.pixels.terrain_change(before, after, dict(zip(("x", "y", "w", "h"), region)))
            checks["visible_terrain:" + actor] = visible[actor]["passed"] and visible[actor]["terrain_changed_pixels"] >= 32
            checks["viewport:" + actor] = width == 720 and 400 <= height <= 480
            for player in ("a", "b"):
                checks[f"static_capture_players:{actor}:{player}"] = captures[actor]["captures"]["before"]["snapshot"]["players"][player]["position"] == captures[actor]["captures"]["after"]["snapshot"]["players"][player]["position"]
            hud_cases.append(V4.hud_only_falsification(output, actor, before, ca, cb))
        if not error and all(checks.values()):
            negatives = material_negatives(reports, materials, head, run_id)
            negatives += ["mvp4:" + name for name in P4.negative_controls(reports, captures, head, run_id)]
    except (OSError, KeyError, ValueError, RuntimeError, TypeError) as exc:
        error += ";" + type(exc).__name__ + ":" + str(exc)
    passed = not error and all(checks.values()) and len(negatives) == 19 and len(hud_cases) == 2
    manifest = {"schema": "distributed_world_simulator.mvp5_graphical_material_manifest.v1", "subject_head": head, "subject_tree": tree, "run_id": run_id, "engine_sha256": BASE.sha(engine), "commands": commands, "error": error, "checks": checks, "visible_terrain": visible, "hud_only_falsification": hud_cases, "negative_controls": negatives, "passed": passed, "duration_seconds": time.monotonic() - start, "manual_input_executed": False, "restart_executed": False, "mvp5_predicate_verified": False, "files": []}
    for path in sorted(output.iterdir()):
        if path.is_file() and path.name != "manifest.json": manifest["files"].append({"path": path.name, "bytes": path.stat().st_size, "sha256": BASE.sha(path)})
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"passed": passed, "error": error, "failed_checks": [k for k, v in checks.items() if not v], "negative_controls": negatives}, indent=2))
    return 0 if passed else 1

if __name__ == "__main__":
    raise SystemExit(main())
