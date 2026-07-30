#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${1:-}}"
[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || { echo "Double-precision Godot required" >&2; exit 2; }
PROFILE="$ROOT/artifacts/test-results/m4-profile-$$"; mkdir -p "$PROFILE"
IMPORT_HOME="$PROFILE/editor_import"; mkdir -p "$IMPORT_HOME/data" "$IMPORT_HOME/config" "$IMPORT_HOME/cache"
HOME="$IMPORT_HOME" XDG_DATA_HOME="$IMPORT_HOME/data" XDG_CONFIG_HOME="$IMPORT_HOME/config" XDG_CACHE_HOME="$IMPORT_HOME/cache" APPDATA="$IMPORT_HOME/data" LOCALAPPDATA="$IMPORT_HOME/data" \
 "$GODOT_BIN" --headless --editor --path "$ROOT" --quit
TESTS=(
 res://tests/runtime/test_m1_networked_gameplay_contracts.gd
 res://tests/runtime/test_m1_unified_networked_gameplay_service.gd
 res://tests/runtime/test_m2_graphical_client_contracts.gd
 res://tests/runtime/test_m3_graphical_multiplayer_contracts.gd
 res://tests/runtime/test_m4_canonical_shared_gameplay_contracts.gd
 res://tests/runtime/test_m4_graphical_shared_gameplay_processes.gd
 res://tests/network/test_t1_multi_peer_transport_contracts.gd
 res://tests/runtime/test_a2_networked_gameplay_architecture.gd
 res://tests/runtime/test_post_a2_single_server_multiplayer_roadmap.gd
)
for test in "${TESTS[@]}"; do
 name="$(basename "$test" .gd)"; home="$PROFILE/$name"; mkdir -p "$home/data" "$home/config" "$home/cache"
 HOME="$home" XDG_DATA_HOME="$home/data" XDG_CONFIG_HOME="$home/config" XDG_CACHE_HOME="$home/cache" APPDATA="$home/data" LOCALAPPDATA="$home/data" \
  "$GODOT_BIN" --headless --path "$ROOT" --script "$test"
done
echo "M4 canonical shared gameplay: PASS (${#TESTS[@]}/${#TESTS[@]})"
