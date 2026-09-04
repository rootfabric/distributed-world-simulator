#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
EXPECTED_GODOT_VERSION="4.7.1.stable.double.custom_build.a13da4feb"
CASE="${BRIDGE2_E_CASE:-all}"
SLOT="${BRIDGE2_E_SLOT:-A}"
ARTIFACT_DIR="${BRIDGE2_E_ARTIFACT_DIR:-$ROOT/artifacts/fabric-bake-bridge2-e}"
PREPASS_TIMEOUT_S="${BRIDGE2_E_PREPASS_TIMEOUT_S:-300}"

if [[ ! -x "$GODOT_BIN" ]]; then
  echo "BRIDGE-2-E: canonical double Godot not executable: $GODOT_BIN" >&2
  exit 2
fi
version="$("$GODOT_BIN" --version | head -n1 | tr -d '\r')"
if [[ "$version" != "$EXPECTED_GODOT_VERSION" ]]; then
  echo "BRIDGE-2-E: wrong Godot version: $version" >&2
  exit 3
fi
mkdir -p "$ARTIFACT_DIR"

run_capture() {
  local phase="$1"
  local label="$2"
  local slot="$3"
  local out="$ARTIFACT_DIR/${phase,,}-${slot}.json"
  local log="$ARTIFACT_DIR/${phase,,}-${slot}.log"
  local marker="FABRIC-BAKE BRIDGE-2-E ${label} Capture: PASS"
  : > "$log"
  setsid env GODOT_SILENCE_ROOT_WARNING=1 BREAKPOINT_RUNTIME_DISABLED=1 BRIDGE2_E_PHASE="$phase" \
    "$GODOT_BIN" --headless --path "$ROOT" \
    --script res://tests/research/fabric_bake0/fabric_bake_bridge2_e_capture.gd >"$log" 2>&1 &
  local pid=$!
  local found=0
  for ((i=0; i<PREPASS_TIMEOUT_S; i++)); do
    if grep -Fq "$marker" "$log" 2>/dev/null; then
      found=1
      break
    fi
    if grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script|CAPTURE FAILURE|Parse Error' "$log" 2>/dev/null; then
      cat "$log"
      kill -TERM -- "-$pid" 2>/dev/null || true
      sleep 0.2
      kill -KILL -- "-$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 4
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  cat "$log"
  if [[ "$found" -ne 1 ]]; then
    echo "BRIDGE-2-E: PASS marker missing before timeout for phase=$phase slot=$slot" >&2
    kill -TERM -- "-$pid" 2>/dev/null || true
    sleep 0.2
    kill -KILL -- "-$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    return 5
  fi
  if grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script|CAPTURE FAILURE|Parse Error' "$log"; then
    return 6
  fi
  grep '^BRIDGE2_E_CAPSULE_JSON=' "$log" | tail -n1 | sed 's/^BRIDGE2_E_CAPSULE_JSON=//' > "$out"
  python3 -m json.tool "$out" >/dev/null
  test -n "$(grep '^BRIDGE2_E_CAPSULE_HASH=' "$log" | tail -n1)"
  kill -TERM -- "-$pid" 2>/dev/null || true
  sleep 0.2
  kill -KILL -- "-$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  echo "BRIDGE-2-E: captured phase=$phase slot=$slot file=$out"
}

run_light() {
  local script="$1"
  local marker="$2"
  local log="$3"
  env GODOT_SILENCE_ROOT_WARNING=1 BREAKPOINT_RUNTIME_DISABLED=1 \
    BRIDGE2_E_INVALIDATION_A="$ARTIFACT_DIR/invalidation-A.json" \
    BRIDGE2_E_INVALIDATION_B="$ARTIFACT_DIR/invalidation-B.json" \
    BRIDGE2_E_RECOVERY_A="$ARTIFACT_DIR/recovery-A.json" \
    BRIDGE2_E_RECOVERY_B="$ARTIFACT_DIR/recovery-B.json" \
    "$GODOT_BIN" --headless --path "$ROOT" --script "$script" 2>&1 | tee "$log"
  if grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script|Acceptance: FAIL|Parse Error' "$log"; then
    return 7
  fi
  grep -Fq "$marker" "$log"
}

case "$CASE" in
  capture-invalidation)
    run_capture INVALIDATION Invalidation "$SLOT"
    ;;
  capture-recovery)
    run_capture RECOVERY Recovery "$SLOT"
    ;;
  compare)
    for f in invalidation-A invalidation-B recovery-A recovery-B; do
      test -s "$ARTIFACT_DIR/$f.json"
    done
    cmp -s "$ARTIFACT_DIR/invalidation-A.json" "$ARTIFACT_DIR/invalidation-B.json"
    cmp -s "$ARTIFACT_DIR/recovery-A.json" "$ARTIFACT_DIR/recovery-B.json"
    run_light \
      res://tests/research/fabric_bake0/fabric_bake_bridge2_e_acceptance.gd \
      "FABRIC-BAKE BRIDGE-2-E Deterministic Mixed Replay Acceptance: PASS" \
      "$ARTIFACT_DIR/acceptance.log"
    ;;
  playground)
    test -s "$ARTIFACT_DIR/invalidation-A.json"
    test -s "$ARTIFACT_DIR/recovery-A.json"
    run_light \
      res://tests/research/fabric_bake0/fabric_bake_bridge2_e_playground.gd \
      "FABRIC-BAKE BRIDGE-2-E Playground: PASS" \
      "$ARTIFACT_DIR/playground.log"
    ;;
  all)
    BRIDGE2_E_CASE=capture-invalidation BRIDGE2_E_SLOT=A "$0"
    BRIDGE2_E_CASE=capture-invalidation BRIDGE2_E_SLOT=B "$0"
    BRIDGE2_E_CASE=capture-recovery BRIDGE2_E_SLOT=A "$0"
    BRIDGE2_E_CASE=capture-recovery BRIDGE2_E_SLOT=B "$0"
    BRIDGE2_E_CASE=compare "$0"
    BRIDGE2_E_CASE=playground "$0"
    ;;
  *)
    echo "BRIDGE-2-E: unsupported case '$CASE'" >&2
    exit 8
    ;;
esac

echo "FABRIC-BAKE BRIDGE-2-E ${CASE}: PASS"
