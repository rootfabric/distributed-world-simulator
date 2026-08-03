#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMEOUT_SECONDS="${MW9_TIMEOUT_SECONDS:-300}"
GODOT_EXECUTABLE="${GODOT_BIN:-}"

if [[ -z "$GODOT_EXECUTABLE" ]]; then
  candidates=(
    "$ROOT_DIR/tools/godot/godot.linuxbsd.editor.double.x86_64"
    "$ROOT_DIR/godot.linuxbsd.editor.double.x86_64"
    "$HOME/build/godot-4.7.1-double/bin/godot.linuxbsd.editor.double.x86_64"
  )
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      GODOT_EXECUTABLE="$candidate"
      break
    fi
  done
fi

if [[ -z "$GODOT_EXECUTABLE" || ! -x "$GODOT_EXECUTABLE" ]]; then
  echo "Godot 4.7.1 double executable not found. Set GODOT_BIN." >&2
  exit 2
fi

run_test() {
  local script="$1"
  if command -v timeout >/dev/null 2>&1; then
    timeout --foreground "${TIMEOUT_SECONDS}s" \
      "$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR" --script "$script"
  else
    "$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR" --script "$script"
  fi
}

run_test res://tests/matter/handoff/test_mw9_durable_handoff_recovery.gd
run_test res://tests/matter/handoff/test_mw9_lock_release_retry.gd
run_test res://tests/matter/handoff/test_mw9_durable_handoff_processes.gd
