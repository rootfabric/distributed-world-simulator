#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
EXPECTED_GODOT_VERSION="4.7.1.stable.double.custom_build.a13da4feb"

if [[ ! -x "$GODOT_BIN" ]]; then
  echo "COMPLEX LABS: canonical double Godot not executable: $GODOT_BIN" >&2
  exit 2
fi
version="$("$GODOT_BIN" --version | head -n1 | tr -d '\r')"
if [[ "$version" != "$EXPECTED_GODOT_VERSION" ]]; then
  echo "COMPLEX LABS: wrong Godot version: $version" >&2
  exit 3
fi

run_script() {
  local script="$1"
  local marker="$2"
  local log
  log="$(mktemp)"
  set +e
  BREAKPOINT_RUNTIME_DISABLED=1 "$GODOT_BIN"     --headless --path "$ROOT"     --script "$script"     2>&1 | tee "$log"
  local status=${PIPESTATUS[0]}
  set -e
  if [[ $status -ne 0 ]]; then
    rm -f "$log"
    return "$status"
  fi
  if grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script' "$log"; then
    echo "COMPLEX LABS: fatal Godot script marker detected in $script" >&2
    rm -f "$log"
    return 4
  fi
  grep -Fq "$marker" "$log"
  rm -f "$log"
}

run_script   res://tests/research/fabric_bake0/fabric_bake_complex0_acceptance.gd   "FABRIC-BAKE COMPLEX0 Acceptance: PASS"
run_script   res://tests/research/fabric_bake0/fabric_bake_complex1a_acceptance.gd   "FABRIC-BAKE COMPLEX1A Acceptance: PASS"

echo "FABRIC-BAKE COMPLEX LABS: PASS"
