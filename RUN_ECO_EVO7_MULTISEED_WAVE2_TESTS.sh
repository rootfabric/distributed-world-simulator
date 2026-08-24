#!/usr/bin/env bash
set -euo pipefail

# ECO.EVO7 multiseed wave-2 battery (Ubuntu twin of
# RUN_ECO_EVO7_MULTISEED_WAVE2_TESTS.ps1).
#
# Runs tests/research/ecology/eco_evo7_multiseed_wave2_acceptance.gd:
# the WATER (FFF4), LITTER (FFF5) and SUCCESSION (FFF6) deterministic bridges
# over fresh lineage seeds [20260824, 20260825, 20260826] with every
# directional/causality family required at 3/3 seeds and strict double-run
# determinism on seed 20260824.
#
# Required: double-precision Godot 4.7.1 custom build a13da4feb.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-${1:-}}"
[[ -n "$GODOT_BIN" && -x "$GODOT_BIN" ]] || {
  echo "Double-precision Godot required (GODOT_BIN or \$1)" >&2
  exit 2
}

PROFILE="$ROOT/artifacts/test-results/eco-evo7-multiseed-wave2-$$"
mkdir -p "$PROFILE"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1"
  local timeout_secs="$2"
  shift 2
  local home="$PROFILE/$name"
  local log="$PROFILE/$name.log"
  mkdir -p "$home/data" "$home/config" "$home/cache"

  set +e
  GODOT_SILENCE_ROOT_WARNING=1 BREAKPOINT_RUNTIME_DISABLED=1 \
  HOME="$home" APPDATA="$home/data" LOCALAPPDATA="$home/data" \
  XDG_DATA_HOME="$home/data" XDG_CONFIG_HOME="$home/config" XDG_CACHE_HOME="$home/cache" \
  timeout "$timeout_secs" "$GODOT_BIN" "$@" >"$log" 2>&1
  local exit_code=$?
  set -e

  # Fail-closed on non-zero exit, FAIL markers, script/parse/compile errors.
  if [[ $exit_code == 0 ]] \
     && grep -q ': PASS' "$log" \
     && ! grep -Eq '(: FAIL([[:space:]]|\()|SCRIPT ERROR:|Parse Error:|Compile Error:)' "$log"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "[eco-evo7-wave2-suite][stage] ${name^^}_PASS"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "[eco-evo7-wave2-suite] FAIL $name (exit code $exit_code)" >&2
    tail -n 40 "$log" >&2
  fi
}

run_preflight() {
  local name="editor-preflight"
  local home="$PROFILE/$name"
  local log="$PROFILE/$name.log"
  mkdir -p "$home/data" "$home/config" "$home/cache"

  set +e
  GODOT_SILENCE_ROOT_WARNING=1 BREAKPOINT_RUNTIME_DISABLED=1 \
  HOME="$home" APPDATA="$home/data" LOCALAPPDATA="$home/data" \
  XDG_DATA_HOME="$home/data" XDG_CONFIG_HOME="$home/config" XDG_CACHE_HOME="$home/cache" \
  timeout 600s "$GODOT_BIN" --headless --editor --import --path "$ROOT" >"$log" 2>&1
  local exit_code=$?
  set -e

  # Inherited defect NOT owned by this line: eco_evo4*/eco_evo5*.tscn carry a
  # BOM and may print "Parse Error: Expected '['" during the editor import
  # scan. Tolerate exactly those; anything else fails closed.
  local foreign_parse_errors
  foreign_parse_errors="$(grep 'Parse Error' "$log" | grep -Evc 'eco_evo[45]_.*\.tscn' || true)"
  if [[ $exit_code == 0 && "$foreign_parse_errors" == 0 ]] \
     && ! grep -Eq '(SCRIPT ERROR:|Compile Error:)' "$log"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "[eco-evo7-wave2-suite][stage] EDITOR_PREFLIGHT_OK"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "[eco-evo7-wave2-suite] FAIL $name (exit code $exit_code, non-inherited parse errors: $foreign_parse_errors)" >&2
    tail -n 40 "$log" >&2
  fi
}

run_preflight
run_test eco_evo7_multiseed_wave2_acceptance 900s \
  --headless --path "$ROOT" \
  --script res://tests/research/ecology/eco_evo7_multiseed_wave2_acceptance.gd

echo "[eco-evo7-wave2-suite] passed: $PASS_COUNT failed: $FAIL_COUNT (logs: $PROFILE)"
(( FAIL_COUNT == 0 )) || exit 1

echo "[eco-evo7-wave2-suite][stage] ECO_EVO7_MULTISEED_WAVE2_SUITE_PASS"
echo "[eco-evo7-wave2-suite][scope] directional/causality families only - exact result hashes are seed-dependent by design and are asserted solely as double-run determinism inside the probe"
