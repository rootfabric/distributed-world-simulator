#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${1:-}}"
CHECKPOINT="v16.10.8-network-nx0-observability-baseline"
[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || {
  echo "Double-precision Godot required for $CHECKPOINT" >&2
  exit 2
}

PROFILE="$ROOT/artifacts/test-results/nx0-observability-$$"
mkdir -p "$PROFILE"

run_step() {
  local name="$1"
  shift
  local profile="$PROFILE/$name"
  local log="$PROFILE/$name.log"
  mkdir -p "$profile/data" "$profile/config" "$profile/cache"
  set +e
  GODOT_SILENCE_ROOT_WARNING=1 BREAKPOINT_RUNTIME_DISABLED=1 \
  APPDATA="$profile/data" LOCALAPPDATA="$profile/data" \
  XDG_DATA_HOME="$profile/data" XDG_CONFIG_HOME="$profile/config" XDG_CACHE_HOME="$profile/cache" \
  timeout 420s "$GODOT_BIN" "$@" >"$log" 2>&1
  local exit_code=$?
  set -e
  cat "$log"
  if (( exit_code != 0 )) || grep -Eq '(: FAIL([[:space:]]|\()|SCRIPT ERROR:|Parse Error:|Compile Error:)' "$log"; then
    echo "NX0 observability step failed: $name (exit code $exit_code)" >&2
    exit 1
  fi
}

run_step editor-import --headless --editor --path "$ROOT" --quit
run_step preparation-contracts --headless --path "$ROOT" --script res://tests/network/test_nx0_network_experience_preparation.gd
run_step baseline-contracts --headless --path "$ROOT" --script res://tests/network/test_nx0_observability_baseline.gd
run_step compatibility-processes --headless --path "$ROOT" --script res://tests/network/test_nx0_observability_handshake_processes.gd

echo "NX0 observability baseline: PASS (4/4) [$CHECKPOINT]"
