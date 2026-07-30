#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${1:-}}"
if [[ -z "$GODOT_BIN" ]]; then
  for candidate in godot4 godot; do command -v "$candidate" >/dev/null 2>&1 && GODOT_BIN="$(command -v "$candidate")" && break; done
fi
[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || { echo "Double-precision Godot was not found." >&2; exit 2; }
REPORT_ROOT="$PROJECT_ROOT/artifacts/test-results"; mkdir -p "$REPORT_ROOT"
REPORT_PATH="$REPORT_ROOT/m3-dedicated-graphical-multiplayer-summary.json"
PROFILE_ROOT="$REPORT_ROOT/m3-runner-profile-$$"; mkdir -p "$PROFILE_ROOT"
TESTS=(
  "res://tests/runtime/test_launch_options.gd"
  "res://tests/runtime/test_h0_listen_host_contracts.gd"
  "res://tests/runtime/test_h1_playable_listen_host_contracts.gd"
  "res://tests/runtime/test_h1_playable_listen_host_integration.gd"
  "res://tests/runtime/test_h2_player_ownership_contracts.gd"
  "res://tests/runtime/test_h2_host_client_processes.gd"
  "res://tests/runtime/test_h3_multiplayer_gameplay_contracts.gd"
  "res://tests/runtime/test_h3_dedicated_multiplayer_processes.gd"
  "res://tests/runtime/test_m1_networked_gameplay_contracts.gd"
  "res://tests/runtime/test_m1_unified_networked_gameplay_service.gd"
  "res://tests/runtime/test_m2_graphical_client_contracts.gd"
  "res://tests/runtime/test_m2_dedicated_graphical_processes.gd"
  "res://tests/runtime/test_m3_graphical_multiplayer_contracts.gd"
  "res://tests/runtime/test_m3_graphical_multiplayer_processes.gd"
  "res://tests/network/test_t1_multi_peer_transport_contracts.gd"
  "res://tests/network/test_t1_multi_peer_transport_processes.gd"
  "res://tests/runtime/test_a2_networked_gameplay_architecture.gd"
  "res://tests/runtime/test_post_a2_single_server_multiplayer_roadmap.gd"
)
steps='[]'
write_summary() {
  python3 - "$REPORT_PATH" "$steps" "$1" "$GODOT_BIN" "$PROJECT_ROOT" "$PROFILE_ROOT" "${#TESTS[@]}" <<'PY2'
import json,sys,datetime
path,steps,passed,godot,root,profile,count=sys.argv[1:]
obj={'schema':'planet_simulator.m3_dedicated_graphical_multiplayer_summary.v1','checkpoint':'v16.10.2-runtime-m3-dedicated-graphical-multiplayer','build_id':'m3-dedicated-two-graphical-clients','decision':'DEDICATED_PLUS_TWO_GRAPHICAL_CLIENTS','finished_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'godot':godot,'project_root':root,'isolated_user_profile':profile,'declared_test_count':int(count),'passed':passed=='true','steps':json.loads(steps)}
with open(path,'w',encoding='utf-8') as f: json.dump(obj,f,ensure_ascii=False,indent=2); f.write('\n')
PY2
}
run() {
  local name="$1" target="$2"; shift 2
  local step_root="$PROFILE_ROOT/$name" data="$PROFILE_ROOT/$name/data" config="$PROFILE_ROOT/$name/config" cache="$PROFILE_ROOT/$name/cache"
  mkdir -p "$step_root" "$data" "$config" "$cache"
  local log="$REPORT_ROOT/m3-${name}.log" started ended code text
  started=$(date +%s%N)
  set +e
  HOME="$step_root" XDG_DATA_HOME="$data" XDG_CONFIG_HOME="$config" XDG_CACHE_HOME="$cache" APPDATA="$data" LOCALAPPDATA="$data" \
    "$GODOT_BIN" "$@" 2>&1 | tee "$log"
  code=${PIPESTATUS[0]}
  set -e
  ended=$(date +%s%N)
  text="$(cat "$log")"
  if [[ $code -eq 0 ]] && grep -Eq '(^|[[:space:]])(: FAIL([[:space:]]|\()|SCRIPT ERROR:|Parse Error:|Compile Error:)' <<<"$text"; then code=1; fi
  steps=$(python3 - "$steps" "$name" "$target" "$code" "$started" "$ended" "$log" <<'PY2'
import json,sys
steps,name,target,code,start,end,log=sys.argv[1:]
a=json.loads(steps); a.append({'name':name,'target':target,'exit_code':int(code),'duration_seconds':round((int(end)-int(start))/1e9,3),'passed':int(code)==0,'log_path':log}); print(json.dumps(a))
PY2
)
  [[ $code -eq 0 ]] || { write_summary false; exit "$code"; }
}
run editor_import res:// --headless --editor --path "$PROJECT_ROOT" --quit
for test in "${TESTS[@]}"; do run "$(basename "$test" .gd)" "$test" --headless --path "$PROJECT_ROOT" --script "$test"; done
write_summary true
echo "M3 dedicated graphical multiplayer: PASS"
echo "Report: $REPORT_PATH"
