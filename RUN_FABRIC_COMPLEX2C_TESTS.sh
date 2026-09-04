#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
EXPECTED_GODOT_VERSION="4.7.1.stable.double.custom_build.a13da4feb"
EXPECTED_GODOT_SHA256="bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"
TIMEOUT_SECONDS="${COMPLEX2C_SCRIPT_TIMEOUT_SECONDS:-240}"
test -x "$GODOT_BIN"
test "$("$GODOT_BIN" --version | head -n1 | tr -d '\r')" = "$EXPECTED_GODOT_VERSION"
test "$(sha256sum "$GODOT_BIN" | awk '{print $1}')" = "$EXPECTED_GODOT_SHA256"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
PROJECT="$TMP_ROOT/project"
HOME_DIR="$TMP_ROOT/home"
mkdir -p "$PROJECT" "$HOME_DIR/data" "$HOME_DIR/config" "$HOME_DIR/cache"
tar --exclude='./.git' --exclude='./.godot' --exclude='./.import' -C "$ROOT" -cf - . | tar -C "$PROJECT" -xf -
LOG="$TMP_ROOT/run.log"
timeout "${TIMEOUT_SECONDS}s" env \
  HOME="$HOME_DIR" XDG_DATA_HOME="$HOME_DIR/data" XDG_CONFIG_HOME="$HOME_DIR/config" XDG_CACHE_HOME="$HOME_DIR/cache" \
  BREAKPOINT_RUNTIME_DISABLED=1 GODOT_SILENCE_ROOT_WARNING=1 \
  "$GODOT_BIN" --headless --path "$PROJECT" --script res://tests/research/fabric_bake0/fabric_bake_complex2c_coupled_motion_acceptance.gd >"$LOG" 2>&1
cat "$LOG"
! grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script' "$LOG"
grep -Fq "FABRIC COMPLEX2-C Coupled Motion Acceptance: PASS" "$LOG"
grep -Eq '^COMPLEX2C_EXPERIMENT_HASH=[0-9a-f]{64}$' "$LOG"
echo "FABRIC COMPLEX2-C COUPLED MOTION TESTS: PASS"
