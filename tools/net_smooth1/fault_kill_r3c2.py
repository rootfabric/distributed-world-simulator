#!/usr/bin/env python3
"""Two *real OS process* M6 crash windows for NET-SMOOTH R3C.2.

This is deliberately separate from the legacy diagnostic-only fault script.
Exits nonzero on incomplete proof. No synthetic ACK, cached report or faked
commit; reads exact repository active JSON *and* starts server2 from that root.

Run one invocation per --window. It owns/kills only the children it spawns.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import threading
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/live2"))
from live2_automation_client import request  # noqa: E402


def find_port(udp: bool = False) -> int:
    family = socket.SOCK_DGRAM if udp else socket.SOCK_STREAM
    with socket.socket(socket.AF_INET, family) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def active_checkpoint(root: Path) -> dict:
    path = root / "authoritative-checkpoint.json"
    record = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(record, dict) or int(record.get("generation", -1)) < 1:
        raise ValueError(f"invalid durable checkpoint: {path}")
    if record.get("schema") != "planet_simulator.authoritative_checkpoint.v1":
        raise ValueError("durable checkpoint schema mismatch")
    generation = int(record["generation"])
    if int(record.get("previous_generation", -1)) != generation - 1:
        raise ValueError("non-contiguous checkpoint generation")
    if record.get("schema_version") != 1:
        raise ValueError("durable checkpoint schema version mismatch")
    if not isinstance(record.get("replay_state"), dict):
        raise ValueError("checkpoint has no M6 replay_state")
    if not isinstance(record.get("authority_state"), dict):
        raise ValueError("checkpoint has no M6 authority_state")
    if not isinstance(record.get("checksum"), str) or not re.fullmatch(r"[0-9a-f]{64}", record["checksum"]):
        raise ValueError("checkpoint checksum must be lowercase SHA-256")
    # This is structural verification, not a SHA proof. The independent
    # Godot Repository.load_committed() validates the actual M6 checksum.
    # Do not claim Python structural check alone is scientific recovery.
    return record


def committed_operation(checkpoint: dict, operation_id: str) -> bool:
    outbox = checkpoint["replay_state"].get("committed_outbox", [])
    if not isinstance(outbox, list):
        raise ValueError("corrupt M6 outbox in durable checkpoint")
    matches = [r for r in outbox if isinstance(r, dict) and r.get("operation_id") == operation_id]
    if len(matches) > 1:
        raise ValueError("duplicate durable operation in M6 outbox")
    return len(matches) == 1


def require(condition: bool, label: str, evidence: list[str]) -> None:
    if not condition:
        raise AssertionError(label)
    evidence.append(label)


def role_env(target: Path, role: str, window: str) -> dict[str, str]:
    env = dict(os.environ)
    for key in list(env):
        if key.startswith("DWS_NET_SMOOTH_") or key.startswith("DWS_NET_R3C"):
            del env[key]
    userdata = target / "userdata"
    userdata.mkdir(parents=True, exist_ok=True)
    # Windows and Linux Godot use different data/cache base directories.
    # Redirect both so no process inherits another runner job's user:// state.
    dirs = {
        "APPDATA": userdata / "appdata",
        "LOCALAPPDATA": userdata / "localappdata",
        "XDG_DATA_HOME": userdata / "xdg-data",
        "XDG_CONFIG_HOME": userdata / "xdg-config",
        "XDG_CACHE_HOME": userdata / "xdg-cache",
    }
    for directory in dirs.values():
        directory.mkdir(parents=True, exist_ok=True)
    env.update({key: str(value) for key, value in dirs.items()})
    env.update(
        HOME=str(userdata),
        BREAKPOINT_RUNTIME_DISABLED="1",
        GODOT_SILENCE_ROOT_WARNING="1",
        DWS_NET_P1B_ITEM_ASYNC="1",
        DWS_NET_R3C_ASYNC_ADMISSION="1",
        DWS_NET_R3C2_PHASED_ITEM_PUBLICATION="1",
        DWS_NET_SMOOTH_TRACE_DIR=str(target),
        DWS_NET_SMOOTH_RUN_ID="r3c2-fault-process",
        DWS_NET_SMOOTH_ROLE=role,
    )
    if role == "server":
        env.update(
            DWS_NET_SMOOTH_TEST_HOOKS="1",
            DWS_NET_SMOOTH_TEST_ITEM_DELAY_MS="1800",
        )
        if window == "after-commit-before-ack":
            env["DWS_NET_R3C2_TEST_FORCE_PRE_ACK_HOLD"] = "1"
    return env


class Run:
    def __init__(self, godot: Path, output: Path, window: str):
        self.godot = godot
        self.output = output
        self.window = window
        self.children: list[subprocess.Popen] = []
        self.logs = []
        self.world = output / "world"
        self.server_report1 = output / "server1-report.json"
        self.server_report2 = output / "server2-report.json"
        self.port = find_port(udp=True)
        self.bridge_port = find_port()
        self.token = uuid.uuid4().hex + uuid.uuid4().hex
        self.operation = f"operation/r3c2/fault/{uuid.uuid4().hex[:16]}"
        self.operation_hash = hashlib.sha256(self.operation.encode()).hexdigest()[:16]
        self.settled_generation = 0
        self.submit_thread = None
        self.submit_received: dict = {}
        self.evidence: list[str] = []
        self.summary: dict = {"schema": "dws.net_smooth.r3c2_fault_process.v1",
            "window": window, "operation_id": self.operation,
            "operation_hash": self.operation_hash, "checks": self.evidence,
            "completed": False, "passed": False}

    def spawn(self, name: str, role: str, args: list[str], *, fault_server: bool = False):
        target = self.output / name
        target.mkdir(parents=True, exist_ok=True)
        stream = (target / "runtime.log").open("w", encoding="utf-8")
        self.logs.append(stream)
        env = role_env(target, role, self.window if fault_server else "none")
        if role == "server":
            # A test-hook-guarded boolean in the actual server2 memory; this
            # is not inferred from rereading the same disk file twice.
            env["DWS_NET_R3C2_TEST_OPERATION_ID"] = self.operation
        cmd = [str(self.godot), "--path", str(ROOT), "--headless",
               "--max-fps", "60", "--disable-vsync", "--"] + args
        proc = subprocess.Popen(cmd, cwd=ROOT, env=env, stdout=stream, stderr=subprocess.STDOUT)
        self.children.append(proc)
        self.summary.setdefault("pids", {})[name] = proc.pid
        return proc

    def server(self, name: str, report: Path, *, fault_server: bool) -> subprocess.Popen:
        args = ["--role=dedicated-server", "--network-mvp", "--world=earth",
            "--server-address=127.0.0.1", f"--server-port={self.port}",
            "--network-debug", "--network-debug-stay-open",
            "--network-profile=LOCAL", "--node-id=fault-r3c2-server",
            "--instance-id=fault-r3c2-server", "--product-seam",
            f"--persistence-root={self.world}",
            f"--m6-persistence-root={self.world}",
            f"--m6-result-file={report}",
            "--shutdown-after-ms=420000"]
        return self.spawn(name, "server", args, fault_server=fault_server)

    def client(self) -> subprocess.Popen:
        target = self.output / "client"
        args = ["--role=game-client", "--network-mvp", "--world=earth",
            "--server-address=127.0.0.1", f"--server-port={self.port}",
            "--network-debug", "--network-debug-stay-open",
            "--network-profile=LOCAL", "--node-id=fault-r3c2-a",
            "--instance-id=fault-r3c2-a", "--player-identity=a",
            "--automation-control", f"--automation-control-port={self.bridge_port}",
            f"--automation-control-token={self.token}",
            f"--automation-control-output-dir={target/'captures'}",
            "--shutdown-after-ms=420000"]
        return self.spawn("client", "a", args)

    @staticmethod
    def read_report(path: Path) -> dict:
        if not path.exists():
            return {}
        try:
            result = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            return {}
        return result if isinstance(result, dict) else {}

    def wait_server(self, proc: subprocess.Popen, path: Path, *,
                    recovered: bool | None, deadline: float = 120) -> dict:
        stop = time.monotonic() + deadline
        while time.monotonic() < stop:
            if proc.poll() is not None:
                raise RuntimeError(f"server exited unexpectedly: {proc.returncode}")
            report = self.read_report(path)
            if report.get("state") == "FAILED":
                raise RuntimeError("server reported FAILED: " + str(report.get("last_error_code")))
            if report.get("state") == "READY":
                actual = report.get("persistence", {}).get("recovered")
                if recovered is None or actual is recovered:
                    return report
            time.sleep(.10)
        raise TimeoutError(f"server recovery marker missing at {path}")

    def bridge(self, method: str, params: dict, timeout: float = 30) -> dict:
        reply = request(self.bridge_port, self.token, method, params, timeout=timeout)
        if not reply.get("ok"):
            raise RuntimeError(f"{method}: {reply}")
        return reply["result"]

    def wait_client_connected(self, proc: subprocess.Popen, deadline: float = 120) -> None:
        stop = time.monotonic() + deadline
        while time.monotonic() < stop:
            if proc.poll() is not None:
                raise RuntimeError(f"client exited: {proc.returncode}")
            try:
                state = self.bridge("state.get", {"kind": "automation"}, timeout=2)
                if state.get("automation", {}).get("connection_state") == "CONNECTED":
                    return
            except (OSError, RuntimeError, KeyError, ValueError):
                pass
            time.sleep(.25)
        raise TimeoutError("client never reached connected state")

    def wait_periodic_settled(self, trace: Path, min_generation: int,
                              deadline: float = 90) -> None:
        """Wait until the in-flight periodic checkpoint generation has landed.

        The exact ITEM submit must not race a busy async writer: a reservation
        while a periodic checkpoint is still committing is rejected with
        P1A_WAIT_PRIOR_PERIODIC backpressure (observed on the Windows double).
        checkpoint_complete rows are flush-pinned by the trace IO worker, so
        this observes real durable generation progress, not buffered state.
        """
        stop = time.monotonic() + deadline
        seen_events = 0
        while time.monotonic() < stop:
            try:
                event, seen_events = self.next_checkpoint_complete(
                    trace, seen_events, deadline=deadline)
                if int(event.get("data", {}).get("generation", 0)) >= min_generation:
                    self.settled_generation = int(
                        event.get("data", {}).get("generation", 0))
                    return
                # An older generation completed; keep waiting for a newer one.
                deadline = max(5.0, stop - time.monotonic())
            except TimeoutError:
                break
        raise TimeoutError(
            f"no checkpoint_complete generation >= {min_generation}")

    def next_checkpoint_complete(self, trace: Path, already_seen: int,
                                 deadline: float) -> tuple[dict, int]:
        """Return the `already_seen+1`-th flush-pinned checkpoint_complete."""
        stop = time.monotonic() + deadline
        while time.monotonic() < stop:
            if trace.exists():
                raw = trace.read_text(encoding="utf-8", errors="replace")
                lines = raw.splitlines()
                if not raw.endswith("\n") and lines:
                    lines = lines[:-1]
                matches = 0
                for line in lines:
                    try:
                        event = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if event.get("kind") != "checkpoint_complete":
                        continue
                    matches += 1
                    if matches > already_seen:
                        return event, matches
            time.sleep(.05)
        raise TimeoutError("no new checkpoint_complete event")

    def submit_exact_item(self, trace: Path, attempts: int = 3) -> dict:
        """Submit the exact fault ITEM, tolerating bounded writer backpressure.

        A rejected submit is never durable (no ledger entry, no checkpoint
        mutation), so retrying the same operation_id cannot replay or double
        commit. Each attempt waits for a fresh settled generation first.
        """
        last_error: Exception | None = None
        for _ in range(attempts):
            received: dict = {}
            def submit() -> None:
                try:
                    received["reply"] = self.bridge("item.command", {
                        "command_type": "inventory.select_hotbar",
                        "payload": {"selected_hotbar_index": 3},
                        "operation_id": self.operation,
                    }, timeout=30)
                except (OSError, RuntimeError, ValueError, KeyError) as exc:
                    received["transport_error"] = str(exc)
            thread = threading.Thread(target=submit, daemon=True)
            thread.start()
            self.submit_thread = thread
            self.submit_received = received
            try:
                self.wait_trace_event(trace, "p1b_item_async_stages", "SUBMIT")
                return received
            except TimeoutError as exc:
                last_error = exc
                reply = received.get("reply", {})
                error_code = str(reply.get("item_command", {}).get("error_code", ""))
                if error_code not in (
                    "P1A_WAIT_PRIOR_PERIODIC",
                    "P1A_GATE_BACKPRESSURE",
                    "P1A_MUTATION_FENCED",
                ):
                    raise
                self.wait_periodic_settled(trace, self.settled_generation + 1)
        raise TimeoutError(f"no exact p1b_item_async_stages/SUBMIT marker: {last_error}")

    def wait_trace_event(self, path: Path, expected_kind: str, stage: str | None = None,
                         deadline: float = 40) -> dict:
        stop = time.monotonic() + deadline
        while time.monotonic() < stop:
            if path.exists():
                # Append-only writer: tolerate only the *unfinished last line*
                # while OS writes. No invented trace events.
                raw = path.read_text(encoding="utf-8", errors="replace")
                lines = raw.splitlines()
                # Preserve the last event when it has a terminating newline.
                # Drop only an actual incomplete final JSONL fragment.
                if not raw.endswith("\n") and lines:
                    lines = lines[:-1]
                for line in reversed(lines):
                    try:
                        event = json.loads(line)
                    except json.JSONDecodeError:
                        continue
                    if event.get("kind") != expected_kind:
                        continue
                    data = event.get("data", {})
                    if data.get("operation_hash") != self.operation_hash:
                        continue
                    if stage is not None and data.get("stage") != stage:
                        continue
                    return event
            time.sleep(.01)
        raise TimeoutError(f"no exact {expected_kind}/{stage}/{self.operation_hash} marker")

    def finish(self) -> dict:
        server1 = self.server("server1", self.server_report1, fault_server=True)
        seeded = self.wait_server(server1, self.server_report1, recovered=False)
        before = active_checkpoint(self.world)
        require(int(before["generation"]) == int(seeded["persistence"]["checkpoint_generation"]),
                "server1 bootstrap generation bound to active disk", self.evidence)
        client = self.client()
        self.wait_client_connected(client)
        require(client.poll() is None, "client A independently connected", self.evidence)

        # The exact ITEM submit must not race the join's deferred periodic
        # checkpoint: wait for a settled generation, then submit with bounded
        # backpressure retry (a rejected submit is never durable). After the
        # settle the writer is idle and periodic dispatch is skipped while the
        # exact ITEM occupies the writer, so re-reading `before` here is the
        # last generation the precommit/commit assertions can be pinned to.
        trace = self.output / "server1" / "trace.jsonl"
        self.wait_periodic_settled(trace, int(before["generation"]) + 1)
        before = active_checkpoint(self.world)
        require(int(before["generation"]) == self.settled_generation,
                "settled baseline equals last durable generation", self.evidence)
        self.submit_exact_item(trace)
        require(server1.poll() is None, "exact ITEM writer submitted under live server1", self.evidence)
        if self.window == "after-commit-before-ack":
            commit = self.wait_trace_event(trace, "p1b_item_async_stages", "DURABLE_COMMIT")
            hold = self.wait_trace_event(trace, "r3c2_pre_ack_hold")
            require(commit["t_us"] < hold["t_us"],
                    "exact durable generation committed before test-only no-ACK hold", self.evidence)
            require(hold.get("data", {}).get("forced_until_kill") is True,
                    "test-only pre-ACK hold cannot expire before server1 is killed", self.evidence)
            on_disk = active_checkpoint(self.world)
            require(int(on_disk["generation"]) == int(before["generation"]) + 1,
                    "single atomic checkpoint generation durable BEFORE ACK", self.evidence)
            require(committed_operation(on_disk, self.operation),
                    "replay + M6 outbox exact operation durable before ACK", self.evidence)
        else:
            # During a true worker-only 1800ms delay, uncommitted mutation
            # cannot appear in active checkpoint, even though it is in memory.
            on_disk = active_checkpoint(self.world)
            require(int(on_disk["generation"]) == int(before["generation"]),
                    "precommit kill observes old generation only", self.evidence)
            require(not committed_operation(on_disk, self.operation),
                    "no uncommitted ITEM in active durable checkpoint", self.evidence)

        # Kill in this proven stage window. Never send a graceful shutdown.
        server1.kill()
        server1.wait(timeout=15)
        self.summary["server1_exit"] = server1.returncode
        require(server1.returncode is not None, "server1 killed without final checkpoint", self.evidence)
        # Stop the old client before bringing up a new server. No client
        # mutates the recovered world or retries this operation implicitly.
        client.terminate()
        try:
            client.wait(timeout=10)
        except subprocess.TimeoutExpired:
            client.kill()
            client.wait(timeout=10)
        received = self.submit_received
        if self.submit_thread is not None:
            self.submit_thread.join(timeout=1)
        self.summary["old_client_reply"] = received.get("reply", {})
        self.summary["old_client_transport_error"] = received.get("transport_error", "")

        disk_after_kill = active_checkpoint(self.world)
        same_generation = int(disk_after_kill["generation"]) == int(on_disk["generation"])
        same_checksum = disk_after_kill["checksum"] == on_disk["checksum"]
        require(same_generation and same_checksum, "hard kill did not invent new generation/checksum", self.evidence)
        has_record = committed_operation(disk_after_kill, self.operation)
        require(has_record == (self.window == "after-commit-before-ack"),
                "M6 outbox record matches precisely the killed durability window", self.evidence)

        # Verify real new process server2, same root and owner identity.
        server2 = self.server("server2", self.server_report2, fault_server=False)
        require(server2.pid != server1.pid, "server2 is a different OS process", self.evidence)
        recovered = self.wait_server(server2, self.server_report2, recovered=True)
        recovery = recovered.get("persistence", {})
        require(recovery.get("recovered") is True and recovery.get("recovery_source") == "ACTIVE",
                "server2 independently loaded ACTIVE recovery checkpoint", self.evidence)
        require(int(recovery.get("checkpoint_generation", -1)) == int(disk_after_kill["generation"]),
                "server2 generation equals exact durable active checkpoint", self.evidence)
        item = recovered.get("item_graph_snapshot", {})
        require(bool(item.get("checksum", "")) and int(item.get("revision", -1)) >= 0,
                "server2 exposes validated canonical Item Graph after recovery", self.evidence)
        committed_replay = committed_operation(active_checkpoint(self.world), self.operation)
        require(committed_replay == has_record,
                "server2 persisted active M6 replay identity without duplication", self.evidence)
        in_memory = recovery.get("r3c2_test_operation_recovered")
        require(type(in_memory) is bool and in_memory is has_record,
                "actual server2 service holds exact expected M6 operation replay", self.evidence)
        outbox_count = int(recovery.get("outbox", {}).get("outbox_count", -1))
        expected_outbox = len(disk_after_kill["replay_state"]["committed_outbox"])
        require(outbox_count == expected_outbox,
                "server2 in-memory outbox count matches validated active M6 checkpoint", self.evidence)
        self.summary.update({
            "before_generation": before["generation"],
            "killed_generation": disk_after_kill["generation"],
            "recovered_generation": recovery["checkpoint_generation"],
            "disk_checksum_before_kill": on_disk["checksum"],
            "disk_checksum_after_kill": disk_after_kill["checksum"],
            "outbox_has_operation": committed_replay,
            "server2_in_memory_operation_recovered": in_memory,
            "server2_outbox_count": outbox_count,
            "server2_recovered": True,
            "server2_recovery_source": recovery["recovery_source"],
            "server2_item_revision": item.get("revision"),
            "server2_item_checksum": item.get("checksum"),
            "passed": True, "completed": True,
        })
        return self.summary

    def close(self) -> None:
        for proc in reversed(self.children):
            if proc.poll() is not None:
                continue
            proc.kill()
            try:
                proc.wait(timeout=15)
            except subprocess.TimeoutExpired:
                pass
        for stream in self.logs:
            stream.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--window", choices=("before-commit", "after-commit-before-ack"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not args.godot.is_file():
        parser.error("exact Godot binary absent")
    if args.output.exists():
        parser.error("output must not already exist; never overwrite kill evidence")
    args.output.mkdir(parents=True)
    run = Run(args.godot.resolve(), args.output.resolve(), args.window)
    try:
        report = run.finish()
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 0
    except (OSError, ValueError, KeyError, TypeError, RuntimeError,
            TimeoutError, AssertionError, subprocess.TimeoutExpired) as exc:
        run.summary["completed"] = False
        run.summary["passed"] = False
        run.summary["failure"] = type(exc).__name__ + ": " + str(exc)
        print(json.dumps(run.summary, ensure_ascii=False, indent=2), file=sys.stderr)
        return 1
    finally:
        run.close()
        (run.output / "fault-result.json").write_text(
            json.dumps(run.summary, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
