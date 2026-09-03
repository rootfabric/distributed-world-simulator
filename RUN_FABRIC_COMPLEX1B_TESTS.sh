#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
EXPECTED_GODOT_VERSION="4.7.1.stable.double.custom_build.a13da4feb"
EXPECTED_GODOT_SHA256="bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"
TIMEOUT_SECONDS="${COMPLEX1B_SCRIPT_TIMEOUT_SECONDS:-300}"

test -x "$GODOT_BIN"
test "$("$GODOT_BIN" --version | head -n1 | tr -d '\r')" = "$EXPECTED_GODOT_VERSION"
test "$(sha256sum "$GODOT_BIN" | awk '{print $1}')" = "$EXPECTED_GODOT_SHA256"

run_script() {
  local script="$1"
  local marker="$2"
  local log status_file pid started marker_seen=0
  log="$(mktemp)"
  status_file="$(mktemp)"
  started="$(date +%s)"
  (
    set +e
    env BREAKPOINT_RUNTIME_DISABLED=1 "$GODOT_BIN" --headless --path "$ROOT" --script "$script" >"$log" 2>&1
    printf '%s\n' "$?" >"$status_file"
  ) &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script' "$log"; then
      kill -TERM "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      cat "$log"
      rm -f "$log" "$status_file"
      return 4
    fi
    if grep -Fq "$marker" "$log"; then
      marker_seen=1
      break
    fi
    if (( $(date +%s) - started >= TIMEOUT_SECONDS )); then
      kill -TERM "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      cat "$log"
      rm -f "$log" "$status_file"
      return 124
    fi
    sleep 0.25
  done
  if (( marker_seen == 1 )); then
    for _ in $(seq 1 20); do
      if ! kill -0 "$pid" 2>/dev/null; then break; fi
      sleep 0.1
    done
    kill -TERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  else
    wait "$pid" 2>/dev/null || true
  fi
  cat "$log"
  grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script' "$log" && { rm -f "$log" "$status_file"; return 4; }
  grep -Fq "$marker" "$log"
  rm -f "$log" "$status_file"
}

run_script   res://tests/research/fabric_bake0/fabric_bridge2_mixed_generic_machine_r1_acceptance.gd   "FABRIC BRIDGE-2 Mixed Generic Machine R1 Acceptance: PASS"

run_script   res://tests/research/fabric_bake0/fabric_bake_complex1b_mixed_powered_e2e_acceptance.gd   "FABRIC COMPLEX1B Mixed Powered E2E Acceptance: PASS"

echo "FABRIC COMPLEX1B MIXED POWERED E2E: PASS"
