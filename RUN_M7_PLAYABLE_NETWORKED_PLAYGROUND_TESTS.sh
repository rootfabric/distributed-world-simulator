#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${1:-}}"
CHECKPOINT="v16.10.6.1-testing-m7-playable-networked-playground"
[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || { echo "Double-precision Godot required for $CHECKPOINT" >&2; exit 2; }
PROFILE="$ROOT/artifacts/test-results/m7-focused-profile-$$"
mkdir -p "$PROFILE"

run_test() {
  local name="$1"; shift
  local home="$PROFILE/$name" log="$PROFILE/$name.log"
  mkdir -p "$home/data" "$home/config" "$home/cache"
  set +e
  TERM="${TERM:-xterm}" GODOT_SILENCE_ROOT_WARNING=1 BREAKPOINT_RUNTIME_DISABLED=1 \
  HOME="$home" APPDATA="$home/data" LOCALAPPDATA="$home/data" \
  XDG_DATA_HOME="$home/data" XDG_CONFIG_HOME="$home/config" XDG_CACHE_HOME="$home/cache" \
  timeout --kill-after=10s 420s "$GODOT_BIN" "$@" >"$log" 2>&1
  local exit_code=$?
  set -e
  cat "$log"
  if (( exit_code != 0 )) || grep -Eq '(: FAIL([[:space:]]|\()|SCRIPT ERROR:|Parse Error:|Compile Error:)' "$log"; then
    echo "M7 playable network step failed: $name (exit code $exit_code)" >&2
    exit 1
  fi
}

run_test editor-import --headless --editor --path "$ROOT" --quit
TESTS=(
  res://tests/runtime/test_launch_options.gd
  res://tests/runtime/test_m7_playable_networked_playground.gd
  res://tests/runtime/test_m7_playable_networked_processes.gd
  res://tests/runtime/test_m7_playable_networked_recovery_processes.gd
  res://tests/runtime/test_m4_canonical_shared_gameplay_contracts.gd
  res://tests/runtime/test_m4_networked_playground_extension.gd
  res://tests/runtime/test_m5_graphical_acceptance_contracts.gd
  res://tests/runtime/test_m6_dedicated_recovery_contracts.gd
  res://tests/runtime/test_a3_single_server_multiplayer_architecture.gd
  res://tests/ui/test_inventory_interaction_profiles.gd
  res://tests/ui/test_inventory_seven_days_interface.gd
  res://tests/items/test_player_inventory_flow.gd
  res://tests/items/test_item_placement_and_admin.gd
)
for test in "${TESTS[@]}"; do run_test "$(basename "$test" .gd)" --headless --path "$ROOT" --script "$test"; done
echo "M7 playable networked playground: PASS (${#TESTS[@]}/${#TESTS[@]}) [$CHECKPOINT]"
