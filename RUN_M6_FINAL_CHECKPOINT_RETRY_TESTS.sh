#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
  local marker="$2"
  local output
  output="$("$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR" --script "$script" 2>&1)"
  printf '%s\n' "$output"
  grep -Fq "$marker" <<<"$output"
}

run_test \
  res://tests/persistence/test_m6_final_checkpoint_retry.gd \
  "M6 final checkpoint retry: PASS (22 assertions)"
run_test \
  res://tests/runtime/test_m6_dedicated_recovery_processes.gd \
  "M6 dedicated recovery processes: 128 assertions, 0 failures"

echo "M6 final checkpoint retry runner: PASS (2/2 suites)"
