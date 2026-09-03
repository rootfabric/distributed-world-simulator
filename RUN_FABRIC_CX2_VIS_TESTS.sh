#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
EXPECTED="4.7.1.stable.double.custom_build.a13da4feb"

test -x "$GODOT_BIN"
test "$("$GODOT_BIN" --version | head -n1 | tr -d '\r')" = "$EXPECTED"

run() {
  local script="$1" marker="$2" log
  log="$(mktemp)"
  set +e
  BREAKPOINT_RUNTIME_DISABLED=1 "$GODOT_BIN" --headless --path "$ROOT" --script "$script" >"$log" 2>&1
  status=$?
  set -e
  cat "$log"
  grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script' "$log" && { rm -f "$log"; return 4; }
  [[ $status -eq 0 ]]
  grep -Fq "$marker" "$log"
  rm -f "$log"
}

run res://tests/research/fabric_bake0/fabric_bake_complex1a_acceptance.gd "FABRIC-BAKE COMPLEX1A Acceptance: PASS"
run res://tests/research/fabric_bake0/fabric_bake_cx2_vis_redundant_power_acceptance.gd "FABRIC CX2-VIS Redundant Power Acceptance: PASS"
echo "FABRIC CX2-VIS TESTS: PASS"
