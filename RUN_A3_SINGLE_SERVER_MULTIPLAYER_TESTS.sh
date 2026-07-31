#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${1:-}}"
CHECKPOINT="v16.10.6-architecture-a3-single-server-multiplayer"
[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || {
  echo "Double-precision Godot required for $CHECKPOINT" >&2
  exit 2
}

PROFILE="$ROOT/artifacts/test-results/a3-focused-profile-$$"
mkdir -p "$PROFILE"

run_test() {
  local name="$1"
  shift
  local home="$PROFILE/$name"
  local log="$PROFILE/$name.log"
  mkdir -p "$home/data" "$home/config" "$home/cache"

  set +e
  GODOT_SILENCE_ROOT_WARNING=1 BREAKPOINT_RUNTIME_DISABLED=1 \
  HOME="$home" APPDATA="$home/data" LOCALAPPDATA="$home/data" \
  XDG_DATA_HOME="$home/data" XDG_CONFIG_HOME="$home/config" XDG_CACHE_HOME="$home/cache" \
  timeout 420s "$GODOT_BIN" "$@" >"$log" 2>&1
  local exit_code=$?
  set -e

  cat "$log"
  if (( exit_code != 0 )) || grep -Eq '(: FAIL([[:space:]]|\()|SCRIPT ERROR:|Parse Error:|Compile Error:)' "$log"; then
    echo "A3 architecture step failed: $name (exit code $exit_code)" >&2
    exit 1
  fi
}

run_test editor-import --headless --editor --path "$ROOT" --quit

TESTS=(
  res://tests/runtime/test_a3_single_server_multiplayer_architecture.gd
  res://tests/runtime/test_launch_options.gd
  res://tests/runtime/test_m1_networked_gameplay_contracts.gd
  res://tests/runtime/test_m1_unified_networked_gameplay_service.gd
  res://tests/runtime/test_m2_graphical_client_contracts.gd
  res://tests/runtime/test_m3_graphical_multiplayer_contracts.gd
  res://tests/runtime/test_m4_canonical_shared_gameplay_contracts.gd
  res://tests/runtime/test_m5_graphical_acceptance_contracts.gd
  res://tests/runtime/test_m6_dedicated_recovery_contracts.gd
  res://tests/runtime/test_m6_dedicated_recovery_processes.gd
  res://tests/runtime/test_a2_networked_gameplay_architecture.gd
  res://tests/runtime/test_post_a2_single_server_multiplayer_roadmap.gd
)

for test in "${TESTS[@]}"; do
  run_test "$(basename "$test" .gd)" --headless --path "$ROOT" --script "$test"
done

echo "A3 single-server multiplayer architecture: PASS (${#TESTS[@]}/${#TESTS[@]}) [$CHECKPOINT]"
