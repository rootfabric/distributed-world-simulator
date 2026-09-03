#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
EXPECTED_GODOT_VERSION="4.7.1.stable.double.custom_build.a13da4feb"

if [[ ! -x "$GODOT_BIN" ]]; then
  echo "BRIDGE-2-A: canonical double Godot not executable: $GODOT_BIN" >&2
  exit 2
fi
version="$("$GODOT_BIN" --version | head -n1 | tr -d '\r')"
if [[ "$version" != "$EXPECTED_GODOT_VERSION" ]]; then
  echo "BRIDGE-2-A: wrong Godot version: $version" >&2
  exit 3
fi

run_script() {
  local script="$1"
  local marker="$2"
  local log
  log="$(mktemp)"
  set +e
  env BREAKPOINT_RUNTIME_DISABLED=1 "$GODOT_BIN" --headless --path "$ROOT" --script "$script" >"$log" 2>&1
  local status=$?
  set -e
  cat "$log"
  if [[ $status -ne 0 ]]; then
    rm -f "$log"
    return "$status"
  fi
  if grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script' "$log"; then
    echo "BRIDGE-2-A: fatal Godot script marker in $script" >&2
    rm -f "$log"
    return 4
  fi
  if ! grep -Fq "$marker" "$log"; then
    echo "BRIDGE-2-A: PASS marker missing in $script" >&2
    rm -f "$log"
    return 5
  fi
  rm -f "$log"
}

run_script \
  res://tests/research/fabric_bake0/fabric_bake_bridge2_a_acceptance.gd \
  "FABRIC-BAKE BRIDGE-2-A Mixed Representation Ownership Acceptance: PASS"

run_script \
  res://tests/research/fabric_bake0/fabric_bake_bridge2_a_playground.gd \
  "FABRIC-BAKE BRIDGE-2-A Playground: PASS"

echo "FABRIC-BAKE BRIDGE-2-A: PASS"
