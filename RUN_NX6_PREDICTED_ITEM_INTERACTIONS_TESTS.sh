#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT="${GODOT_BIN:-}"
if [[ -z "$GODOT" ]]; then
  for candidate in \
    "$PROJECT_ROOT/tools/godot/linux-x86_64/godot.linuxbsd.editor.double.x86_64" \
    "$(command -v godot4 2>/dev/null || true)" \
    "$(command -v godot 2>/dev/null || true)"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then GODOT="$candidate"; break; fi
  done
fi
if [[ -z "$GODOT" || ! -x "$GODOT" ]]; then
  echo "Double-precision Godot not found. Set GODOT_BIN." >&2
  exit 2
fi
RESULT_ROOT="$PROJECT_ROOT/artifacts/test-results/nx6-fix3-$$"
mkdir -p "$RESULT_ROOT/data" "$RESULT_ROOT/config" "$RESULT_ROOT/cache"
OLD_XDG_DATA_HOME="${XDG_DATA_HOME-}"
OLD_XDG_CONFIG_HOME="${XDG_CONFIG_HOME-}"
OLD_XDG_CACHE_HOME="${XDG_CACHE_HOME-}"
restore_env() {
  if [[ -n "$OLD_XDG_DATA_HOME" ]]; then export XDG_DATA_HOME="$OLD_XDG_DATA_HOME"; else unset XDG_DATA_HOME; fi
  if [[ -n "$OLD_XDG_CONFIG_HOME" ]]; then export XDG_CONFIG_HOME="$OLD_XDG_CONFIG_HOME"; else unset XDG_CONFIG_HOME; fi
  if [[ -n "$OLD_XDG_CACHE_HOME" ]]; then export XDG_CACHE_HOME="$OLD_XDG_CACHE_HOME"; else unset XDG_CACHE_HOME; fi
}
trap restore_env EXIT
export XDG_DATA_HOME="$RESULT_ROOT/data"
export XDG_CONFIG_HOME="$RESULT_ROOT/config"
export XDG_CACHE_HOME="$RESULT_ROOT/cache"
export GODOT_SILENCE_ROOT_WARNING=1
run_checked() {
  local name="$1"; shift
  local log="$RESULT_ROOT/${name}.log"
  echo "--- $name ---"
  set +e
  "$GODOT" "$@" 2>&1 | tee "$log"
  local status=${PIPESTATUS[0]}
  set -e
  if [[ $status -ne 0 ]] || grep -Eq '(: FAIL([[:space:]]|\()|SCRIPT ERROR:|Parse Error:|Compile Error:)' "$log"; then
    echo "$name: FAIL" >&2
    exit 1
  fi
  echo "$name: PASS"
}
run_checked editor_import --headless --editor --path "$PROJECT_ROOT" --quit
run_checked nx6_contracts --headless --path "$PROJECT_ROOT" --script res://tests/network/test_nx6_predicted_item_interactions.gd
run_checked nx6_integration --headless --path "$PROJECT_ROOT" --script res://tests/network/test_nx6_predicted_item_interactions_integration.gd
run_checked m7_playable_contracts --headless --path "$PROJECT_ROOT" --script res://tests/runtime/test_m7_playable_networked_playground.gd

# Fix3 keeps the graphical M7 multiprocess suite to a mandatory gate.
GODOT_BIN="$GODOT" "$PROJECT_ROOT/RUN_M7_PLAYABLE_NETWORKED_PLAYGROUND_TESTS.sh"
if [[ "${NX6_INCLUDE_ACCEPTED_REGRESSION:-0}" == "1" ]]; then
  GODOT_BIN="$GODOT" "$PROJECT_ROOT/RUN_NX5_REMOTE_SNAPSHOT_INTERPOLATION_TESTS.sh"
fi
echo "NX6 predicted item interactions fix3: PASS (5/5 mandatory)"
echo "Logs: $RESULT_ROOT"
