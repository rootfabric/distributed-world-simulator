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

RESULT_ROOT="$PROJECT_ROOT/artifacts/test-results/nx5-$$"
mkdir -p "$RESULT_ROOT/data" "$RESULT_ROOT/config" "$RESULT_ROOT/cache"
export HOME="$RESULT_ROOT"
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
run_checked nx5_contracts --headless --path "$PROJECT_ROOT" --script res://tests/network/test_nx5_remote_snapshot_interpolation.gd
run_checked nx5_integration --headless --path "$PROJECT_ROOT" --script res://tests/network/test_nx5_remote_snapshot_interpolation_integration.gd
run_checked m3_presenter_regression --headless --path "$PROJECT_ROOT" --script res://tests/runtime/test_m3_graphical_multiplayer_contracts.gd
run_checked m4_playground_regression --headless --path "$PROJECT_ROOT" --script res://tests/runtime/test_m4_networked_playground_extension.gd

if [[ "${NX5_INCLUDE_GRAPHICAL_PROCESS:-0}" == "1" ]]; then
  run_checked m3_graphical_process --headless --path "$PROJECT_ROOT" --script res://tests/runtime/test_m3_graphical_multiplayer_processes.gd
fi

echo "NX5 remote snapshot interpolation: PASS (5/5 focused)"
echo "Logs: $RESULT_ROOT"
