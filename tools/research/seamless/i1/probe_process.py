from __future__ import annotations

import argparse
import json
import os
import signal
import time


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--heartbeat-ms", type=int, default=100)
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()

    payload = {
        "schema": "distributed_world_simulator.sm1_i1_probe.v1",
        "research_only": os.environ.get("DWS_I1_RESEARCH_ONLY") == "1",
        "process_role": os.environ.get("DWS_I1_PROCESS_ROLE", "unknown"),
        "process_id": os.environ.get("DWS_I1_PROCESS_ID", "unknown"),
        "process_incarnation": int(os.environ.get("DWS_I1_PROCESS_INCARNATION", "0")),
        "pid": os.getpid(),
    }
    print(json.dumps(payload, sort_keys=True), flush=True)
    if args.once:
        return 0

    running = True

    def stop(*_: object) -> None:
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, stop)
    if hasattr(signal, "SIGINT"):
        signal.signal(signal.SIGINT, stop)
    interval = max(1, args.heartbeat_ms) / 1000.0
    while running:
        time.sleep(interval)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
