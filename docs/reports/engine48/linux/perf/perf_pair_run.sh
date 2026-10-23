#!/usr/bin/env bash
# ENGINE48 paired performance run: one M7 playground session (dedicated server
# + 2 graphical gl_compatibility clients) with product-native entrypoints.
# Usage: perf_pair_run.sh <engine-label> <godot-bin> <port> <worktree> <outdir>
set -uo pipefail

LABEL="$1"; GODOT="$2"; PORT="$3"; ROOT="$4"; OUT="$5"
DURATION="${PERF_DURATION:-180}"
mkdir -p "$OUT"
PERSIST="$OUT/persistence"

start_isolated() {
  local profile="$1"; shift
  mkdir -p "$profile/data" "$profile/config" "$profile/cache"
  env HOME="$profile" APPDATA="$profile/data" LOCALAPPDATA="$profile/data" \
      XDG_DATA_HOME="$profile/data" XDG_CONFIG_HOME="$profile/config" XDG_CACHE_HOME="$profile/cache" \
      BREAKPOINT_RUNTIME_DISABLED=1 GODOT_SILENCE_ROOT_WARNING=1 \
      DISPLAY="${PERF_DISPLAY:-:99}" LIBGL_ALWAYS_SOFTWARE=1 \
      "$GODOT" "$@" >>"$OUT/proc.log" 2>&1 &
  STARTED_PID=$!
}

run_root="$OUT/session"
mkdir -p "$run_root/profiles"
TOKEN="session-id/perf-$LABEL-$PORT"

start_isolated "$run_root/profiles/server" --headless --path "$ROOT" --log-file "$run_root/server.log" -- \
  --role=dedicated-server --network-playground --network-debug --world=playground \
  --network-session-token="$TOKEN" \
  --node-id=m7-playground-server --instance-id=m7-playground \
  --server-address=127.0.0.1 --server-port="$PORT" --m7-result-file="$run_root/server.json" \
  --network-profile=LOCAL --network-presets-file=res://config/network/network-condition-presets.v1.json \
  --m6-persistence-root="$PERSIST" --print-runtime-descriptor
SERVER_PID=$STARTED_PID

ready=0
for i in $(seq 1 60); do
  if [ -f "$run_root/server.json" ] && python3 -c "
import json,sys
try: sys.exit(0 if json.load(open('$run_root/server.json')).get('state')=='READY' else 1)
except Exception: sys.exit(1)"; then ready=1; break; fi
  sleep 1
done
echo "server_ready=$ready pid=$SERVER_PID" >> "$OUT/meta.txt"
[ "$ready" = "1" ] || { kill "$SERVER_PID" 2>/dev/null; echo "RESULT server_ready=0" > "$OUT/result.txt"; exit 1; }

IDS=(a b); CLIENT_PIDS=()
for cid in "${IDS[@]}"; do
  start_isolated "$run_root/profiles/client-$cid" --path "$ROOT" --rendering-method gl_compatibility --print-fps \
    --log-file "$run_root/client-$cid.log" -- \
    --role=game-client --network-playground --network-debug --network-debug-stay-open --world=playground \
    --network-session-token="$TOKEN" \
    --node-id="m7-client-$cid" --instance-id="m7-client-$cid" --player-identity="$cid" \
    --server-address=127.0.0.1 --server-port="$PORT" \
    --network-profile=LOCAL --network-presets-file=res://config/network/network-condition-presets.v1.json \
    --print-runtime-descriptor
  CLIENT_PIDS+=("$STARTED_PID")
  sleep 1
done
echo "clients=${CLIENT_PIDS[*]}" >> "$OUT/meta.txt"

# settle 30s, then sample for DURATION seconds
sleep 30
SAMPLE_END=$((SECONDS + DURATION))
: > "$OUT/samples.csv"
echo "t,server_utime,server_stime,server_rss_kb,c_a_utime,c_a_stime,c_a_rss_kb,c_b_utime,c_b_stime,c_b_rss_kb" >> "$OUT/samples.csv"
read_stat() { awk '{print $14, $15, $24}' "/proc/$1/stat" 2>/dev/null; }
read_rss() { awk '{print $2}' "/proc/$1/statm" 2>/dev/null; }
while (( SECONDS < SAMPLE_END )); do
  s=$(read_stat "$SERVER_PID"); a=$(read_stat "${CLIENT_PIDS[0]}"); b=$(read_stat "${CLIENT_PIDS[1]}")
  sr=$(read_rss "$SERVER_PID"); ar=$(read_rss "${CLIENT_PIDS[0]}"); br=$(read_rss "${CLIENT_PIDS[1]}")
  echo "$SECONDS,$(echo $s | tr ' ' ','),${sr:-0},$(echo $a | tr ' ' ','),${ar:-0},$(echo $b | tr ' ' ','),${br:-0}" >> "$OUT/samples.csv"
  sleep 2
done

# stop everything
kill "${CLIENT_PIDS[@]}" "$SERVER_PID" 2>/dev/null
sleep 3
kill -9 "${CLIENT_PIDS[@]}" "$SERVER_PID" 2>/dev/null
wait 2>/dev/null

echo "RESULT done label=$LABEL" > "$OUT/result.txt"
