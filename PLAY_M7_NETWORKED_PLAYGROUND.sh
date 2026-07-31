#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${1:-}}"
HOST="${M7_HOST:-127.0.0.1}"
PORT="${M7_PORT:-24580}"
CLIENT_COUNT="${M7_CLIENT_COUNT:-2}"
ACTIVE="$ROOT/artifacts/runtime/m7-network-playground-active.json"
[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || { echo "Set GODOT_BIN to Godot 4.7.1 double." >&2; exit 2; }
[[ "$CLIENT_COUNT" =~ ^[1-8]$ ]] || { echo "M7_CLIENT_COUNT must be 1..8" >&2; exit 2; }
if [[ -f "$ACTIVE" ]]; then
  python3 - "$ACTIVE" <<'PY'
import json,os,sys
p=sys.argv[1]; d=json.load(open(p)); pids=[d.get('server_pid',0),*d.get('client_pids',[])]
if any(pid and os.path.exists(f'/proc/{pid}') for pid in pids):
    raise SystemExit('M7 playground is already running. Use ./STOP_M7_NETWORKED_PLAYGROUND.sh')
PY
  rm -f "$ACTIVE"
fi
RUN_ID="$(date -u +%Y%m%d-%H%M%S)"
RUN_ROOT="$ROOT/artifacts/runtime/m7-network-playground/$RUN_ID"
PERSISTENCE_ROOT="${M7_PERSISTENCE_ROOT:-$ROOT/artifacts/runtime/m7-network-playground-persistence}"
mkdir -p "$RUN_ROOT/profiles" "$PERSISTENCE_ROOT"

STARTED_PID=0
start_isolated() {
  local profile="$1"; shift
  mkdir -p "$profile/data" "$profile/config" "$profile/cache"
  env HOME="$profile" APPDATA="$profile/data" LOCALAPPDATA="$profile/data" \
      XDG_DATA_HOME="$profile/data" XDG_CONFIG_HOME="$profile/config" XDG_CACHE_HOME="$profile/cache" \
      BREAKPOINT_RUNTIME_DISABLED=1 GODOT_SILENCE_ROOT_WARNING=1 \
      "$GODOT_BIN" "$@" >/dev/null 2>&1 &
  STARTED_PID=$!
}

SERVER_RESULT="$RUN_ROOT/server.json"
start_isolated "$RUN_ROOT/profiles/server" --headless --path "$ROOT" --log-file "$RUN_ROOT/server.log" -- \
  --role=dedicated-server --network-playground --network-debug --world=playground \
  --node-id=m7-playground-server --instance-id=m7-playground \
  --server-address="$HOST" --server-port="$PORT" --m7-result-file="$SERVER_RESULT" \
  --m6-persistence-root="$PERSISTENCE_ROOT" --print-runtime-descriptor
SERVER_PID=$STARTED_PID

python3 - "$SERVER_RESULT" "$SERVER_PID" <<'PY'
import json,os,sys,time
path,pid=sys.argv[1],int(sys.argv[2]); deadline=time.time()+40
while time.time()<deadline:
    if not os.path.exists(f'/proc/{pid}'): break
    try:
        d=json.load(open(path))
        if d.get('state')=='READY': raise SystemExit(0)
        if d.get('state')=='FAILED': break
    except (FileNotFoundError,json.JSONDecodeError): pass
    time.sleep(.1)
raise SystemExit('M7 dedicated server did not become READY')
PY

IDS=(a b c d e f g h)
CLIENT_PIDS=()
for ((i=0;i<CLIENT_COUNT;i++)); do
  id="${IDS[$i]}"
  start_isolated "$RUN_ROOT/profiles/client-$id" --path "$ROOT" --rendering-method gl_compatibility \
    --log-file "$RUN_ROOT/client-$id.log" -- --role=game-client --network-playground --network-debug --network-debug-stay-open --world=playground \
    --node-id="m7-client-$id" --instance-id="m7-client-$id" --player-identity="$id" \
    --server-address="$HOST" --server-port="$PORT" --print-runtime-descriptor
  CLIENT_PIDS+=("$STARTED_PID")
  sleep .35
done
python3 - "$ACTIVE" "$RUN_ROOT/session.json" "$ROOT" "$GODOT_BIN" "$HOST" "$PORT" "$SERVER_PID" "$RUN_ROOT" "$PERSISTENCE_ROOT" "${CLIENT_PIDS[*]}" <<'PY'
import json,sys,datetime
active,copy,root,godot,host,port,server,run,persist,clients=sys.argv[1:]
d={"schema":"planet_simulator.m7_playable_networked_playground_session.v1","checkpoint":"v16.10.6.1-testing-m7-playable-networked-playground","started_at_utc":datetime.datetime.now(datetime.timezone.utc).isoformat(),"project_root":root,"godot":godot,"server_address":host,"server_port":int(port),"server_pid":int(server),"client_pids":[int(x) for x in clients.split()],"run_root":run,"persistence_root":persist}
for p in (active,copy):
    with open(p,'w') as f: json.dump(d,f,indent=2)
PY

echo "M7 network playground started: $HOST:$PORT"
echo "Server PID: $SERVER_PID; client PIDs: ${CLIENT_PIDS[*]}"
echo "Logs: $RUN_ROOT"
echo "Controls: click viewport; WASD; Shift; Space; Tab; E; G; F; 1-0; Esc."
echo "Stop: ./STOP_M7_NETWORKED_PLAYGROUND.sh"
