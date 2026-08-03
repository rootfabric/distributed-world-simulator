#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMEOUT_SECONDS="${RL1_TIMEOUT_SECONDS:-300}"
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

if command -v timeout >/dev/null 2>&1; then
  set +e
  timeout --foreground "${TIMEOUT_SECONDS}s" \
    "$GODOT_EXECUTABLE" \
    --headless \
    --path "$ROOT_DIR" \
    --script res://tests/representation/test_rl1_matter_summary_pyramid.gd
  status=$?
  set -e
  if [[ $status -eq 124 ]]; then
    echo "RL1 focused test exceeded ${TIMEOUT_SECONDS}s and was terminated." >&2
  fi
  exit $status
fi

"$GODOT_EXECUTABLE" \
  --headless \
  --path "$ROOT_DIR" \
  --script res://tests/representation/test_rl1_matter_summary_pyramid.gd
