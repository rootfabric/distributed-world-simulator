#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
EXPECTED_GODOT_VERSION="4.7.1.stable.double.custom_build.a13da4feb"
EXPECTED_GODOT_SHA256="bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"
TIMEOUT_SECONDS="${COMPLEX2B_SCRIPT_TIMEOUT_SECONDS:-240}"

test -x "$GODOT_BIN"
test "$("$GODOT_BIN" --version | head -n1 | tr -d '\r')" = "$EXPECTED_GODOT_VERSION"
test "$(sha256sum "$GODOT_BIN" | awk '{print $1}')" = "$EXPECTED_GODOT_SHA256"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

PROJECT="$TMP_ROOT/project"
HOME_DIR="$TMP_ROOT/home"
DATA_DIR="$TMP_ROOT/data"
CONFIG_DIR="$TMP_ROOT/config"
CACHE_DIR="$TMP_ROOT/cache"
LOG="$TMP_ROOT/run.log"
mkdir -p "$PROJECT" "$HOME_DIR" "$DATA_DIR" "$CONFIG_DIR" "$CACHE_DIR"

tar \
  --exclude='./.git' \
  --exclude='./.godot' \
  --exclude='./.import' \
  -C "$ROOT" -cf - . | tar -C "$PROJECT" -xf -

set +e
timeout "${TIMEOUT_SECONDS}s" env \
  HOME="$HOME_DIR" \
  XDG_DATA_HOME="$DATA_DIR" \
  XDG_CONFIG_HOME="$CONFIG_DIR" \
  XDG_CACHE_HOME="$CACHE_DIR" \
  BREAKPOINT_RUNTIME_DISABLED=1 \
  "$GODOT_BIN" --headless --path "$PROJECT" \
  --script res://tests/research/fabric_bake0/fabric_bake_complex2b_compliant_response_acceptance.gd \
  >"$LOG" 2>&1
status=$?
set -e

cat "$LOG"
if [[ "$status" -ne 0 ]]; then
  echo "COMPLEX2-B exact run failed status=$status" >&2
  exit "$status"
fi
if grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script' "$LOG"; then
  exit 4
fi
grep -Fq "FABRIC COMPLEX2-B Compliant Response Acceptance: PASS" "$LOG"
hash="$(grep '^COMPLEX2B_EXPERIMENT_HASH=' "$LOG" | tail -n1 | cut -d= -f2-)"
test -n "$hash"

echo "COMPLEX2-B exact hash=$hash"
echo "FABRIC COMPLEX2-B COMPLIANT RESPONSE TESTS: PASS"
