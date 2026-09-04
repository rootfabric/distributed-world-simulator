#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
EXPECTED_GODOT_VERSION="4.7.1.stable.double.custom_build.a13da4feb"
EXPECTED_GODOT_SHA256="bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"
TIMEOUT_SECONDS="${COMPLEX2_SCRIPT_TIMEOUT_SECONDS:-180}"

test -x "$GODOT_BIN"
test "$("$GODOT_BIN" --version | head -n1 | tr -d '\r')" = "$EXPECTED_GODOT_VERSION"
test "$(sha256sum "$GODOT_BIN" | awk '{print $1}')" = "$EXPECTED_GODOT_SHA256"

run_to_log() {
  local script="$1"
  local marker="$2"
  local log="$3"
  local pid started marker_seen=0
  started="$(date +%s)"
  env BREAKPOINT_RUNTIME_DISABLED=1 "$GODOT_BIN" --headless --path "$ROOT" --script "$script" >"$log" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script' "$log"; then
      kill -TERM "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 4
    fi
    if grep -Fq "$marker" "$log"; then
      marker_seen=1
      break
    fi
    if (( $(date +%s) - started >= TIMEOUT_SECONDS )); then
      kill -TERM "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 0.25
  done
  if (( marker_seen == 1 )); then
    for _ in $(seq 1 20); do
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi
      sleep 0.1
    done
    kill -TERM "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  else
    wait "$pid" 2>/dev/null || true
  fi
  grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script' "$log" && return 4
  grep -Fq "$marker" "$log"
}

left_log="$(mktemp)"
right_log="$(mktemp)"
trap 'rm -f "$left_log" "$right_log"' EXIT

run_to_log \
  res://tests/research/fabric_bake0/fabric_bake_complex2_modular_machine_acceptance.gd \
  "FABRIC COMPLEX2 Modular Machine Acceptance: PASS" \
  "$left_log"
run_to_log \
  res://tests/research/fabric_bake0/fabric_bake_complex2_modular_machine_acceptance.gd \
  "FABRIC COMPLEX2 Modular Machine Acceptance: PASS" \
  "$right_log"

cat "$left_log"
cat "$right_log"

left_hash="$(grep '^COMPLEX2_EXPERIMENT_HASH=' "$left_log" | tail -n1 | cut -d= -f2-)"
right_hash="$(grep '^COMPLEX2_EXPERIMENT_HASH=' "$right_log" | tail -n1 | cut -d= -f2-)"
test -n "$left_hash"
test -n "$right_hash"
test "$left_hash" = "$right_hash"

echo "COMPLEX2 isolated replay hash=$left_hash"
echo "FABRIC COMPLEX2 MODULAR MACHINE TESTS: PASS"
