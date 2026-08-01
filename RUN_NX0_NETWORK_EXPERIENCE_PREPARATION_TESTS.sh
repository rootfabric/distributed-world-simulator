#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${1:-}}"
CHECKPOINT="v16.10.7-network-nx0-observability-preparation"
[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || {
  echo "Double-precision Godot required for $CHECKPOINT" >&2
  exit 2
}

PROFILE="$ROOT/artifacts/test-results/nx0-preparation-$$"
mkdir -p "$PROFILE"

run_step() {
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
    echo "NX0 preparation step failed: $name (exit code $exit_code)" >&2
    exit 1
  fi
}

run_step editor-import --headless --editor --path "$ROOT" --quit
run_step contracts --headless --path "$ROOT" --script res://tests/network/test_nx0_network_experience_preparation.gd

echo "NX0 network experience preparation: PASS (2/2) [$CHECKPOINT]"
