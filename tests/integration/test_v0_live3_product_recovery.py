#!/usr/bin/env python3
"""LIVE3: ordinary main.tscn server, native network clients and real disk cuts.

No world state is synthesized. P2's unchanged actor performs pickup, container
transfer, mining and foundation construction. Resident clients then exercise
current-state rejoin, equipment, more mining/building, planned server restart,
replay and continuation. This is implementer evidence, not human acceptance.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
WIN_SHA = "3633c3e609c8ce2f9bae334a9c7e75c7f974de3af0415ab4a8050a625a15a7a5"
LINUX_SHA = "bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"


def read(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def write(path: Path, value: dict) -> None:
    temp = path.with_suffix(path.suffix + ".pending")
    temp.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    os.replace(temp, path)


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_digests(path: Path) -> dict:
    return {str(p.relative_to(path)): digest(p) for p in sorted(path.rglob("*")) if p.is_file()}


def wait(predicate, label: str, seconds: float = 60):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.15)
    raise AssertionError("TIMEOUT:" + label)


def durable(checkpoint: dict) -> dict:
    return checkpoint["authority_state"]["current_snapshot"]["domain_components"]["networked_gameplay_state"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--engine", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    engine, out = args.engine.resolve(), args.output.resolve()
    if not engine.is_file() or digest(engine) != (WIN_SHA if sys.platform == "win32" else LINUX_SHA):
        raise RuntimeError("EXACT_DOUBLE_ENGINE_REQUIRED")
    if out.exists():
        raise RuntimeError("PRESERVE_PREVIOUS_EVIDENCE")
    out.mkdir(parents=True)
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(("127.0.0.1", 0))
        port = sock.getsockname()[1]
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    tree = subprocess.check_output(["git", "rev-parse", "HEAD^{tree}"], cwd=ROOT, text=True).strip()
    owned: list[dict] = []
    checks: list[dict] = []
    errors = ""
    saves = out / "saves"
    request = out / "p2-control.json"

    def check(value: bool, label: str) -> None:
        checks.append({"label": label, "passed": bool(value)})
        if not value:
            raise AssertionError(label)
        print("PASS:", label, flush=True)

    def launch(name: str, tail: list[str], extra: dict | None = None) -> dict:
        profile = out / "profiles" / name
        profile.mkdir(parents=True)
        env = os.environ.copy()
        env.update(PYTHONUTF8="1", BREAKPOINT_RUNTIME_DISABLED="1", GODOT_SILENCE_ROOT_WARNING="1")
        for key in ("APPDATA", "LOCALAPPDATA", "HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
            directory = profile / key.lower()
            directory.mkdir()
            env[key] = str(directory)
        env.update(extra or {})
        log = out / (name + ".log")
        stream = log.open("w", encoding="utf-8")
        proc = subprocess.Popen([str(engine), "--headless", "--audio-driver", "Dummy", "--path", str(ROOT), *tail], cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT)
        row = {"name": name, "process": proc, "stream": stream, "log": log, "report": out / (name + ".json")}
        owned.append(row)
        return row

    def start_server(name: str, save_root: Path = saves, slot: str = "recovery", expect_ready: bool = True) -> dict:
        nonce = secrets.token_hex(32)
        control = out / (name + "-control.json")
        status = out / (name + "-status.json")
        row = launch(name, ["--", "--network-mvp", "--role=dedicated-server", "--world=earth", "--network-debug",
                            "--server-port=" + str(port), "--world-slot=" + slot, "--world-save-root=" + str(save_root),
                            "--world-control-file=" + str(control), "--world-control-token=" + nonce,
                            "--world-status-file=" + str(status), "--m6-result-file=" + str(out / (name + "-native.json"))])
        row.update(control=control, status=status, nonce=nonce, slot=slot, save_root=save_root)
        if expect_ready:
            ready = wait(lambda: read(status) if read(status).get("phase") == "READY" else None, name + " ready")
            check(row["process"].poll() is None and ready["native_construction_bound"] is True, name + " product native recovery ready")
            row["real_pid"] = ready["process_id"]
        return row

    def stop_server(row: dict, expected_success: bool = True) -> None:
        status = read(row["status"])
        write(row["control"], {"schema": "dws.live3.host_request.v1", "action": "SAVE_AND_STOP", "token": row["nonce"],
                               "process_id": row["real_pid"], "request_id": secrets.token_hex(8)})
        code = row["process"].wait(timeout=40)
        status = read(row["status"])
        if expected_success:
            check(code == 0 and status.get("phase") == "STOPPED" and status.get("saved") is True, row["name"] + " graceful save confirmed before exit")
        else:
            check(code != 0 and status.get("saved") is False and status.get("phase") == "FAILED", "unavailable save directory cannot produce successful shutdown")

    def p2(name: str, mode: str, extra: dict | None = None) -> dict:
        report = out / (name + ".json")
        tail = ["--script", "res://tools/runtime/v0_p2_live_reconnect_client_p5.gd", "--", "--host=127.0.0.1",
                "--port=" + str(port), "--mode=" + mode, "--result-file=" + str(report), "--control-file=" + str(request)]
        tail += [f"--{key}={value}" for key, value in (extra or {}).items()]
        return launch(name, tail)

    def phase(row: dict, expected: str) -> dict:
        result = wait(lambda: read(row["report"]) if read(row["report"]).get("state") in (expected, "FAILED") else None, expected, 90)
        check(result.get("state") == expected and result.get("passed") is True, expected + ":" + str(result.get("error_code", "")))
        return result["details"]

    def resident(name: str, identity: str) -> dict:
        report, control = out / (name + ".json"), out / (name + "-control.json")
        cfg = {"port": port, "identity": identity, "report": str(report), "control": str(control)}
        row = launch(name, ["--script", "res://tools/live3/live3_recovery_probe.gd"], {"DWS_LIVE3_PROBE": json.dumps(cfg)})
        row["control"] = control
        connected(row)
        return row

    def connected(row: dict, old_session: str = "") -> dict:
        def ready():
            report = read(row["report"])
            s = report.get("snapshot", {})
            player = s.get("player", {})
            return report if (s.get("runtime", {}).get("connection_state") == "CONNECTED" and s.get("construction", {}).get("checksum")
                              and player.get("transport_session_id") and player.get("transport_session_id") != old_session) else None
        return wait(ready, row["name"] + " connected/current domains", 60)

    def command(row: dict, action: str, **kwargs) -> dict:
        key = secrets.token_hex(8)
        write(row["control"], {"id": key, "action": action, **kwargs})
        result = wait(lambda: read(row["report"]).get("results", {}).get(key), action, 35)
        check(result.get("success") is True, action + ":" + str(result.get("error_code", "")))
        return result

    def stop_client(row: dict) -> None:
        command(row, "quit")
        check(row["process"].wait(timeout=20) == 0, row["name"] + " clean exit")

    try:
        write(request, {"phase": "BOOT"})
        server = start_server("server-1")
        actor = p2("actor", "actor")
        phase(actor, "ACTOR_READY")
        before_client = p2("before", "before")
        before = phase(before_client, "BEFORE_COMPLETE")
        check(before_client["process"].wait(timeout=20) == 0, "B absent before canonical mutations")
        write(request, {"phase": "MUTATE"})
        mutated = phase(actor, "ACTOR_MUTATED")
        after_client = p2("after", "after", {
            "expected-item-checksum": mutated["item_graph_checksum"], "expected-construction-checksum": mutated["construction_checksum"],
            "expected-construction-generation": mutated["construction_generation"], "previous-session-id": before["transport_session_id"],
            "previous-player-entity-id": before["player_entity_id"], "previous-ownership-epoch": before["ownership_epoch"]})
        phase(after_client, "RECONNECT_READY")
        phase(actor, "ACTOR_RECONNECT_SEEN")
        check(mutated["beacon_location"] == "CONTAINER" and mutated["crate_contains_beacon"] is True, "real item transferred to canonical shared container")
        write(request, {"phase": "FINISH"})
        check(actor["process"].wait(timeout=25) == 0 and after_client["process"].wait(timeout=25) == 0, "unchanged P2 real mutations and current-state reconnect complete")

        a, b = resident("resident-a1", "a"), resident("resident-b", "b")
        command(a, "equip")
        command(a, "mine", amount=4, operation_id="operation/live3/mine-shell")
        command(a, "build", stage=1, operation_id="operation/live3/build-shell")
        command(a, "mine", amount=1, operation_id="operation/live3/mine-retained")
        time.sleep(1)
        old_a = connected(a)["snapshot"]
        stop_client(a)
        command(b, "move")
        current_b = connected(b)["snapshot"]["player"]
        a = resident("resident-a2", "a")
        rejoined = connected(a)["snapshot"]
        check(rejoined["player"]["player_entity_id"] == old_a["player"]["player_entity_id"] == "player/a", "closed A process rejoins with stable player identity")
        check(rejoined["items"]["checksum"] == old_a["items"]["checksum"], "A rejoin preserves current inventory/equipment/container")
        wait(lambda: read(a["report"]).get("snapshot", {}).get("players", {}).get("b", {}).get("position") == current_b["position"], "A observes B movement during absence")
        check(True, "rejoined A receives current B state, not private cached world")
        before_a, before_b = connected(a), connected(b)
        write(out / "before-restart-a.json", before_a)
        write(out / "before-restart-b.json", before_b)
        old_a_session = before_a["snapshot"]["player"]["transport_session_id"]
        old_b_session = before_b["snapshot"]["player"]["transport_session_id"]
        stop_server(server)
        checkpoint_path = saves / "recovery" / "authoritative-checkpoint.json"
        first_cut = read(checkpoint_path)
        write(out / "first-cut.json", first_cut)
        state = durable(first_cut)
        check(state["live3_construction"]["build_plans"]["ghosts"][0]["next_stage_index"] == 2, "saved cut includes real two-stage Construction progress")
        server = start_server("server-2")
        check(read(server["status"]).get("recovered") is True, "new server process recovered existing slot")
        recovered_a, recovered_b = connected(a, old_a_session), connected(b, old_b_session)
        for label, old, new in (("A", before_a, recovered_a), ("B", before_b, recovered_b)):
            check(new["process_id"] == old["process_id"], label + " stays in same client process through server restart")
            check(new["snapshot"]["player"]["player_entity_id"] == old["snapshot"]["player"]["player_entity_id"], label + " stable canonical player after restart")
            for domain in ("items", "resources", "construction"):
                check(new["snapshot"][domain]["checksum"] == old["snapshot"][domain]["checksum"], label + " exact restored " + domain)
            check(new["snapshot"]["player"]["position"] == old["snapshot"]["player"]["position"], label + " position preserved")
            check(any(t["state"] == "RECONNECTING" for t in new["transitions"]), label + " product reconnect state observed")
        write(out / "after-restart-a.json", recovered_a)
        write(out / "after-restart-b.json", recovered_b)
        replay_before = recovered_a["snapshot"]
        command(a, "mine", amount=1, operation_id="operation/live3/mine-retained")
        command(a, "build", stage=1, operation_id="operation/live3/build-shell")
        time.sleep(0.8)
        replay_after = connected(a)["snapshot"]
        for domain in ("items", "resources", "construction"):
            check(replay_after[domain]["checksum"] == replay_before[domain]["checksum"], "post-restart replay creates no duplicate " + domain)
        command(a, "mine", amount=1, operation_id="operation/live3/new-after-restart")
        wait(lambda: read(b["report"]).get("snapshot", {}).get("items", {}).get("checksum") == read(a["report"]).get("snapshot", {}).get("items", {}).get("checksum"), "B sees new material after restart")
        check(connected(a)["snapshot"]["items"]["checksum"] != replay_before["items"]["checksum"], "new gameplay mutation succeeds after recovery")
        command(a, "move")
        stop_client(a)
        stop_client(b)
        stop_server(server)

        original = tree_digests(saves / "recovery")
        other = start_server("server-other", slot="other")
        stop_server(other)
        check(tree_digests(saves / "recovery") == original, "another slot cannot mutate original world")
        empty = durable(read(saves / "other" / "authoritative-checkpoint.json"))
        check(not empty["live3_construction"]["authority"]["construct_store"]["constructs"], "new slot has no recovered construction from another world")

        corrupt_root = out / "corrupt-saves"
        shutil.copytree(saves / "recovery", corrupt_root / "recovery")
        (corrupt_root / "recovery" / "authoritative-checkpoint.json").write_text('{"corrupted":true}', encoding="utf-8")
        corrupt_before = tree_digests(corrupt_root)
        bad = start_server("server-corrupt", corrupt_root, expect_ready=False)
        check(bad["process"].wait(timeout=40) != 0 and read(bad["status"]).get("phase") != "READY", "corrupt slot fails before admission")
        check(tree_digests(corrupt_root) == corrupt_before, "corrupt slot is not overwritten with empty world")

        failure_root = out / "unavailable-saves"
        shutil.copytree(saves / "recovery", failure_root / "recovery")
        fault = start_server("server-save-fault", failure_root)
        own_slot = failure_root / "recovery"
        backup = failure_root / "preserved-before-fault"
        own_slot.rename(backup)
        own_slot.write_text("test-owned directory unavailable", encoding="utf-8")
        backup_before = tree_digests(backup)
        stop_server(fault, expected_success=False)
        check(tree_digests(backup) == backup_before, "failed save preserves previous durable cut")
        check(tree_digests(saves / "recovery") == original, "fault injection never touches healthy world slot")
    except Exception as exc:
        errors = type(exc).__name__ + ":" + str(exc)
        print(errors, file=sys.stderr, flush=True)
    finally:
        for row in reversed(owned):
            proc = row["process"]
            if proc.poll() is None:
                if sys.platform == "win32":
                    subprocess.run(["taskkill", "/PID", str(proc.pid), "/T", "/F"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
                else:
                    proc.terminate()
                try:
                    proc.wait(timeout=8)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=5)
            row["stream"].close()
        # Negative startup/save tests may log the intentional error; all normal
        # product and client logs must remain free of script/compile failures.
        for row in owned:
            text = row["log"].read_text(encoding="utf-8-sig", errors="replace")
            if any(t in text for t in ("SCRIPT ERROR:", "Parse Error:", "Compile Error:")):
                errors += "\nSCRIPT_ERRORS:" + row["name"]
        result = {"schema": "dws.live3.product_recovery_evidence.v1", "subject_head": head, "subject_tree": tree,
                  "passed": not errors and bool(checks) and all(c["passed"] for c in checks), "error": errors, "checks": checks,
                  "manual_input_executed": False, "independent_verdict": False,
                  "processes": [{"name": r["name"], "wrapper_pid": r["process"].pid, "exit_code": r["process"].returncode} for r in owned]}
        write(out / "manifest.json", result)
        print(json.dumps({k: result[k] for k in ("passed", "error", "subject_head")}, indent=2))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
