#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTIVE="$ROOT/artifacts/runtime/m7-network-playground-active.json"
[[ -f "$ACTIVE" ]] || { echo "No active M7 playground session was found."; exit 0; }
mapfile -t VALUES < <(python3 - "$ACTIVE" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); print(d.get('run_root',''))
for p in [*d.get('client_pids',[]),d.get('server_pid',0)]: print(p)
PY
)
RUN_ROOT="${VALUES[0]}"
for pid in "${VALUES[@]:1}"; do
  [[ "$pid" =~ ^[0-9]+$ ]] || continue
  kill "$pid" 2>/dev/null || true
done
sleep .5
for pid in "${VALUES[@]:1}"; do
  [[ "$pid" =~ ^[0-9]+$ ]] || continue
  kill -9 "$pid" 2>/dev/null || true
done
rm -f "$ACTIVE"
echo "M7 network playground stopped. Logs remain in $RUN_ROOT"
