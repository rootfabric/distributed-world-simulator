#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
EXPECTED_GODOT_VERSION="4.7.1.stable.double.custom_build.a13da4feb"
EXPECTED_GODOT_SHA256="bfa7ce632d8d4b1dcc96f64f5405ee52b57c4e25d15c3e0478acc26e08d517d7"
TIMEOUT_SECONDS="${COMPLEX2B_SCRIPT_TIMEOUT_SECONDS:-180}"

test -x "$GODOT_BIN"
test "$("$GODOT_BIN" --version | head -n1 | tr -d '\r')" = "$EXPECTED_GODOT_VERSION"
test "$(sha256sum "$GODOT_BIN" | awk '{print $1}')" = "$EXPECTED_GODOT_SHA256"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

copy_project() {
  local destination="$1"
  mkdir -p "$destination"
  tar \
    --exclude='./.git' \
    --exclude='./.godot' \
    --exclude='./.import' \
    -C "$ROOT" -cf - . | tar -C "$destination" -xf -
}

run_isolated() {
  local label="$1"
  local script="$2"
  local marker="$3"
  local project="$TMP_ROOT/$label/project"
  local home="$TMP_ROOT/$label/home"
  local data="$TMP_ROOT/$label/data"
  local config="$TMP_ROOT/$label/config"
  local cache="$TMP_ROOT/$label/cache"
  local log="$TMP_ROOT/$label/run.log"
  local status=0

  mkdir -p "$home" "$data" "$config" "$cache"
  copy_project "$project"

  set +e
  timeout "${TIMEOUT_SECONDS}s" env \
    HOME="$home" \
    XDG_DATA_HOME="$data" \
    XDG_CONFIG_HOME="$config" \
    XDG_CACHE_HOME="$cache" \
    BREAKPOINT_RUNTIME_DISABLED=1 \
    "$GODOT_BIN" --headless --path "$project" --script "$script" >"$log" 2>&1
  status=$?
  set -e

  cat "$log"
  if [[ "$status" -ne 0 ]]; then
    echo "COMPLEX2-B isolated run failed label=$label status=$status" >&2
    return "$status"
  fi
  if grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script' "$log"; then
    return 4
  fi
  grep -Fq "$marker" "$log"
}

run_isolated \
  replay-left \
  res://tests/research/fabric_bake0/fabric_bake_complex2b_compliant_response_acceptance.gd \
  "FABRIC COMPLEX2-B Compliant Response Acceptance: PASS"
run_isolated \
  replay-right \
  res://tests/research/fabric_bake0/fabric_bake_complex2b_compliant_response_acceptance.gd \
  "FABRIC COMPLEX2-B Compliant Response Acceptance: PASS"
run_isolated \
  scene-smoke \
  res://tests/research/fabric_bake0/fabric_bake_complex2b_scene_smoke.gd \
  "FABRIC COMPLEX2-B Scene Smoke: PASS"

left_log="$TMP_ROOT/replay-left/run.log"
right_log="$TMP_ROOT/replay-right/run.log"
left_hash="$(grep '^COMPLEX2B_EXPERIMENT_HASH=' "$left_log" | tail -n1 | cut -d= -f2-)"
right_hash="$(grep '^COMPLEX2B_EXPERIMENT_HASH=' "$right_log" | tail -n1 | cut -d= -f2-)"

test -n "$left_hash"
test -n "$right_hash"
test "$left_hash" = "$right_hash"

echo "COMPLEX2-B isolated replay hash=$left_hash"
echo "FABRIC COMPLEX2-B COMPLIANT RESPONSE TESTS: PASS"
