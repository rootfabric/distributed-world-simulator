#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${1:-}}"
if [[ -z "$GODOT_BIN" ]]; then
  for candidate in godot4 godot; do
    if command -v "$candidate" >/dev/null 2>&1; then
      GODOT_BIN="$(command -v "$candidate")"
      break
    fi
  done
fi
[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || {
  echo "Double-precision Godot was not found. Set GODOT_BIN or pass the binary path." >&2
  exit 2
}

TESTS=(
  "res://tests/runtime/test_a2_networked_gameplay_architecture.gd"
  "res://tests/runtime/test_h3_multiplayer_gameplay_contracts.gd"
  "res://tests/runtime/test_h3_dedicated_multiplayer_processes.gd"
  "res://tests/runtime/test_h2_player_ownership_contracts.gd"
  "res://tests/runtime/test_h2_host_client_processes.gd"
  "res://tests/runtime/test_launch_options.gd"
  "res://tests/runtime/test_h0_listen_host_contracts.gd"
  "res://tests/runtime/test_h1_playable_listen_host_contracts.gd"
  "res://tests/runtime/test_h1_playable_listen_host_integration.gd"
  "res://tests/network/test_t1_multi_peer_transport_contracts.gd"
  "res://tests/network/test_t1_multi_peer_transport_processes.gd"
)

REPORT_ROOT="$PROJECT_ROOT/artifacts/test-results"
REPORT_PATH="$REPORT_ROOT/a2-networked-gameplay-audit-summary.json"
mkdir -p "$REPORT_ROOT"
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STEPS_FILE="$(mktemp)"
trap 'rm -f "$STEPS_FILE"' EXIT

write_summary() {
  local passed="$1"
  python3 - "$STEPS_FILE" "$REPORT_PATH" "$STARTED_AT" "$GODOT_BIN" "$PROJECT_ROOT" "$passed" <<'PY2'
import json,sys,datetime
steps_path,report_path,started,godot,root,passed=sys.argv[1:]
steps=[]
try:
    with open(steps_path,encoding='utf-8') as f:
        steps=[json.loads(line) for line in f if line.strip()]
except FileNotFoundError:
    pass
report={
  'schema':'planet_simulator.a2_networked_gameplay_audit_summary.v1',
  'checkpoint':'v16.9.4-architecture-a2-networked-gameplay',
  'build_id':'a2-networked-gameplay-audit-freeze',
  'decision':'FROZEN_WITH_GATES',
  'started_at_utc':started,
  'finished_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
  'godot':godot,'project_root':root,'declared_test_count':11,
  'passed':passed.lower()=='true','steps':steps,
}
with open(report_path,'w',encoding='utf-8',newline='\n') as f:
    json.dump(report,f,ensure_ascii=False,indent=2); f.write('\n')
PY2
}

run_checked() {
  local name="$1"; shift
  local target="$1"; shift
  local log="$REPORT_ROOT/a2-${name}.log"
  local started_ns ended_ns duration exit_code
  started_ns="$(date +%s%N)"
  set +e
  "$GODOT_BIN" "$@" 2>&1 | tee "$log"
  exit_code=${PIPESTATUS[0]}
  set -e
  if [[ $exit_code -eq 0 ]] && grep -Eq ': FAIL([[:space:]]|\()' "$log"; then exit_code=1; fi
  ended_ns="$(date +%s%N)"
  duration="$(python3 - <<PY2
print(round(($ended_ns-$started_ns)/1_000_000_000, 3))
PY2
)"
  python3 - "$STEPS_FILE" "$name" "$target" "$exit_code" "$duration" <<'PY2'
import json,sys
path,name,target,code,duration=sys.argv[1:]
with open(path,'a',encoding='utf-8') as f:
    f.write(json.dumps({'name':name,'target':target,'exit_code':int(code),'duration_seconds':float(duration),'passed':int(code)==0},ensure_ascii=False)+'\n')
PY2
  if [[ $exit_code -ne 0 ]]; then
    write_summary false
    echo "$name failed (exit code $exit_code)" >&2
    exit 1
  fi
  echo "$name: PASS"
}

run_checked editor_import res:// --headless --editor --path "$PROJECT_ROOT" --quit
for test_script in "${TESTS[@]}"; do
  run_checked "$(basename "$test_script" .gd)" "$test_script" --headless --path "$PROJECT_ROOT" --script "$test_script"
done
write_summary true

echo "A2 networked gameplay architecture audit: PASS"
echo "Report: $REPORT_PATH"
