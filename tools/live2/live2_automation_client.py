#!/usr/bin/env python3
import argparse
import json
import socket
import sys
import time
import uuid

REQUEST_SCHEMA = "dws.live2.automation.request.v1"


def request(port: int, token: str, method: str, params: dict, timeout: float) -> dict:
    payload = {
        "schema": REQUEST_SCHEMA,
        "id": str(uuid.uuid4()),
        "token": token,
        "method": method,
        "params": params,
    }
    wire = (json.dumps(payload, separators=(",", ":")) + "\n").encode("utf-8")
    with socket.create_connection(("127.0.0.1", port), timeout=timeout) as sock:
        sock.settimeout(timeout)
        sock.sendall(wire)
        data = bytearray()
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            chunk = sock.recv(65536)
            if not chunk:
                break
            data.extend(chunk)
            newline = data.find(b"\n")
            if newline >= 0:
                return json.loads(data[:newline].decode("utf-8"))
    raise RuntimeError("automation bridge response timeout")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Control one LIVE.2 game client through the localhost automation bridge."
    )
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--token", required=True)
    parser.add_argument("--timeout", type=float, default=5.0)
    sub = parser.add_subparsers(dest="action", required=True)

    sub.add_parser("ping")
    sub.add_parser("commands")

    command = sub.add_parser("command")
    command.add_argument("line")

    move = sub.add_parser("move")
    move.add_argument("--x", type=float, default=0.0)
    move.add_argument("--z", type=float, default=0.0)
    move.add_argument("--yaw", type=float)
    move.add_argument("--pitch", type=float)
    move.add_argument("--sprint", action="store_true")
    move.add_argument("--jump", action="store_true")
    move.add_argument("--ttl-ms", type=int, default=750)

    sub.add_parser("stop")

    view = sub.add_parser("view")
    view.add_argument("--yaw", type=float, required=True)
    view.add_argument("--pitch", type=float, default=0.0)

    state = sub.add_parser("state")
    state.add_argument(
        "--kind",
        choices=["runtime", "jitter", "automation"],
        default="runtime",
    )

    shot = sub.add_parser("screenshot")
    shot.add_argument("--filename", default="")

    raw = sub.add_parser("raw")
    raw.add_argument("method")
    raw.add_argument("--params", default="{}")

    return parser


def main() -> int:
    args = build_parser().parse_args()
    params = {}
    method = args.action

    if args.action == "commands":
        method = "commands.list"
    elif args.action == "command":
        method = "command.execute"
        params = {"line": args.line}
    elif args.action == "move":
        method = "movement.set"
        params = {
            "move_x": args.x,
            "move_z": args.z,
            "sprint": args.sprint,
            "jump": args.jump,
            "ttl_ms": args.ttl_ms,
        }
        if args.yaw is not None:
            params["look_yaw"] = args.yaw
        if args.pitch is not None:
            params["look_pitch"] = args.pitch
    elif args.action == "stop":
        method = "movement.stop"
    elif args.action == "view":
        method = "view.set"
        params = {"yaw": args.yaw, "pitch": args.pitch}
    elif args.action == "state":
        method = "state.get"
        params = {"kind": args.kind}
    elif args.action == "screenshot":
        method = "screenshot.capture"
        params = {"filename": args.filename}
    elif args.action == "raw":
        method = args.method
        parsed = json.loads(args.params)
        if not isinstance(parsed, dict):
            raise ValueError("--params must decode to a JSON object")
        params = parsed

    response = request(args.port, args.token, method, params, args.timeout)
    print(json.dumps(response, indent=2, ensure_ascii=False))
    return 0 if response.get("ok", False) else 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(json.dumps({"ok": False, "client_error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(3)
