#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${1:-}}"
[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || { echo "Double-precision Godot required" >&2; exit 2; }
PROFILE="$ROOT/artifacts/test-results/pre-m5-profile-$$"
mkdir -p "$PROFILE"
run_test() {
  local name="$1"; shift
  local home="$PROFILE/$name"
  mkdir -p "$home/data" "$home/config" "$home/cache"
  HOME="$home" APPDATA="$home/data" LOCALAPPDATA="$home/data" \
  XDG_DATA_HOME="$home/data" XDG_CONFIG_HOME="$home/config" XDG_CACHE_HOME="$home/cache" \
  BREAKPOINT_RUNTIME_DISABLED=1 "$GODOT_BIN" "$@"
}
run_test editor-import --headless --editor --path "$ROOT" --quit
TESTS=(
  res://tests/runtime/test_m5_graphical_acceptance_preparation.gd
  res://tests/runtime/test_m4_canonical_shared_gameplay_contracts.gd
  res://tests/runtime/test_m4_networked_playground_extension.gd
  res://tests/runtime/test_m4_graphical_shared_gameplay_processes.gd
  res://tests/runtime/test_m3_graphical_multiplayer_contracts.gd
  res://tests/ui/test_inventory_interaction_profiles.gd
  res://tests/ui/test_inventory_seven_days_interface.gd
  res://tests/items/test_item_stack_transfers.gd
  res://tests/ui/test_inventory_ui_i0_architecture.gd
  res://tests/ui/test_inventory_ui_i1_interactions.gd
  res://tests/ui/test_inventory_ui_i2_large_storage.gd
  res://tests/runtime/test_a2_networked_gameplay_architecture.gd
  res://tests/runtime/test_post_a2_single_server_multiplayer_roadmap.gd
)
for test in "${TESTS[@]}"; do
  run_test "$(basename "$test" .gd)" --headless --path "$ROOT" --script "$test"
done
echo "Pre-M5 graphical acceptance preparation: PASS (${#TESTS[@]}/${#TESTS[@]})"
