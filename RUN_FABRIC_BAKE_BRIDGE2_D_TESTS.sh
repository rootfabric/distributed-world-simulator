#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
EXPECTED_GODOT_VERSION="4.7.1.stable.double.custom_build.a13da4feb"
CASE="${BRIDGE2_D_CASE:-all}"
PREPASS_TIMEOUT_S="${BRIDGE2_D_PREPASS_TIMEOUT_S:-90}"

if [[ ! -x "$GODOT_BIN" ]]; then
  echo "BRIDGE-2-D: canonical double Godot not executable: $GODOT_BIN" >&2
  exit 2
fi
version="$("$GODOT_BIN" --version | head -n1 | tr -d '\r')"
if [[ "$version" != "$EXPECTED_GODOT_VERSION" ]]; then
  echo "BRIDGE-2-D: wrong Godot version: $version" >&2
  exit 3
fi

run_until_marker() {
  local script="$1"
  local marker="$2"
  local log
  log="$(mktemp)"
  setsid env BREAKPOINT_RUNTIME_DISABLED=1 GODOT_SILENCE_ROOT_WARNING=1 \
    "$GODOT_BIN" --headless --path "$ROOT" --script "$script" >"$log" 2>&1 &
  local pid=$!
  local found=0
  for ((i=0; i<PREPASS_TIMEOUT_S; i++)); do
    if grep -Fq "$marker" "$log" 2>/dev/null; then
      found=1
      break
    fi
    if grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script|Acceptance: FAIL' "$log" 2>/dev/null; then
      cat "$log"
      kill -TERM -- "-$pid" 2>/dev/null || true
      sleep 0.2
      kill -KILL -- "-$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      rm -f "$log"
      return 4
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  cat "$log"
  if [[ "$found" -ne 1 ]]; then
    echo "BRIDGE-2-D: PASS marker missing before timeout for $script" >&2
    kill -TERM -- "-$pid" 2>/dev/null || true
    sleep 0.2
    kill -KILL -- "-$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    rm -f "$log"
    return 5
  fi
  if grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script|Acceptance: FAIL' "$log"; then
    rm -f "$log"
    return 6
  fi
  # The physics acceptance is complete once the final marker is emitted. Some
  # large Godot dictionaries linger in engine teardown, so terminate the whole
  # fresh process-group after the semantic boundary has passed.
  kill -TERM -- "-$pid" 2>/dev/null || true
  sleep 0.2
  kill -KILL -- "-$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  rm -f "$log"
}

case "$CASE" in
  invalidation)
    run_until_marker \
      res://tests/research/fabric_bake0/fabric_bake_bridge2_d_acceptance.gd \
      "FABRIC-BAKE BRIDGE-2-D Invalidation Ordering Acceptance: PASS"
    ;;
  recovery)
    run_until_marker \
      res://tests/research/fabric_bake0/fabric_bake_bridge2_d_recovery_acceptance.gd \
      "FABRIC-BAKE BRIDGE-2-D Recovery Ordering Acceptance: PASS"
    ;;
  playground)
    run_until_marker \
      res://tests/research/fabric_bake0/fabric_bake_bridge2_d_playground.gd \
      "FABRIC-BAKE BRIDGE-2-D Playground: PASS"
    ;;
  all)
    BRIDGE2_D_CASE=invalidation "$0"
    BRIDGE2_D_CASE=recovery "$0"
    BRIDGE2_D_CASE=playground "$0"
    ;;
  *)
    echo "BRIDGE-2-D: unsupported case '$CASE'" >&2
    exit 7
    ;;
esac

echo "FABRIC-BAKE BRIDGE-2-D ${CASE}: PASS"
