#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${1:-}}"
CHECKPOINT="v16.14.0-network-nx4-client-prediction-reconciliation"
[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || {
  echo "Double-precision Godot required for $CHECKPOINT" >&2
  exit 2
}
PROFILE="$ROOT/artifacts/test-results/nx4-prediction-$$"
mkdir -p "$PROFILE"
run_step() {
  local name="$1"; shift
  local profile="$PROFILE/$name" log="$PROFILE/$name.log"
  mkdir -p "$profile/data" "$profile/config" "$profile/cache"
  set +e
  GODOT_SILENCE_ROOT_WARNING=1 BREAKPOINT_RUNTIME_DISABLED=1 TERM=xterm \
  APPDATA="$profile/data" LOCALAPPDATA="$profile/data" \
  XDG_DATA_HOME="$profile/data" XDG_CONFIG_HOME="$profile/config" XDG_CACHE_HOME="$profile/cache" \
  timeout --kill-after=15s 540s "$GODOT_BIN" "$@" >"$log" 2>&1
  local exit_code=$?
  set -e
  cat "$log"
  if (( exit_code != 0 )) || grep -Eq '(: FAIL([[:space:]]|\()|SCRIPT ERROR:|Parse Error:|Compile Error:)' "$log"; then
    echo "NX4 prediction step failed: $name (exit code $exit_code)" >&2
    exit 1
  fi
}
run_step editor-import --headless --editor --path "$ROOT" --import --quit
run_step preparation-contracts --headless --path "$ROOT" --script res://tests/network/test_nx0_network_experience_preparation.gd
run_step baseline-contracts --headless --path "$ROOT" --script res://tests/network/test_nx0_observability_baseline.gd
run_step nx1-contracts --headless --path "$ROOT" --script res://tests/network/test_nx1_deterministic_network_condition_simulator.gd
run_step nx2-contracts --headless --path "$ROOT" --script res://tests/network/test_nx2_realtime_traffic_separation.gd
run_step nx3-contracts --headless --path "$ROOT" --script res://tests/network/test_nx3_fixed_tick_authoritative_simulation.gd
run_step nx4-contracts --headless --path "$ROOT" --script res://tests/network/test_nx4_client_prediction_reconciliation.gd
run_step compatibility-regression --headless --path "$ROOT" --script res://tests/network/test_nx0_observability_handshake_processes.gd
run_step conditioned-enet-processes --headless --path "$ROOT" --script res://tests/network/test_nx1_network_condition_processes.gd
run_step physical-channel-processes --headless --path "$ROOT" --script res://tests/network/test_nx2_physical_channel_processes.gd
run_step nx4-playable-processes --headless --path "$ROOT" --script res://tests/runtime/test_m7_playable_networked_processes.gd
NX4_TEST_CLIENT_NETWORK_PROFILE=AVERAGE_BROADBAND run_step nx4-conditioned-playable-processes --headless --path "$ROOT" --script res://tests/runtime/test_m7_playable_networked_processes.gd
run_step nx4-recovery-processes --headless --path "$ROOT" --script res://tests/runtime/test_m7_playable_networked_recovery_processes.gd
echo "NX4 client prediction and reconciliation: PASS (13/13) [$CHECKPOINT]"
