#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMEOUT_SECONDS="${MW10_TIMEOUT_SECONDS:-300}"
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

run_suite() {
  local name="$1"
  local script="$2"
  local marker="$3"
  local output_file
  output_file="$(mktemp)"
  echo "MW10 runner: suite [$name]"
  "$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR" --script "$script" \
    >"$output_file" 2>&1 &
  local pid=$!
  local started=$SECONDS
  local timed_out=0
  while kill -0 "$pid" 2>/dev/null; do
    if (( SECONDS - started >= TIMEOUT_SECONDS )); then
      timed_out=1
      kill "$pid" 2>/dev/null || true
      sleep 1
      kill -9 "$pid" 2>/dev/null || true
      break
    fi
    if (( (SECONDS - started) > 0 && (SECONDS - started) % 5 == 0 )); then
      echo "MW10 runner: suite [$name] still running ($((SECONDS - started))s)"
      sleep 1
    else
      sleep 1
    fi
  done
  set +e
  wait "$pid"
  local exit_code=$?
  set -e
  cat "$output_file"
  if [[ $timed_out -eq 1 ]]; then
    echo "MW10 runner: suite [$name] exceeded ${TIMEOUT_SECONDS}s." >&2
    rm -f "$output_file"
    return 124
  fi
  if [[ $exit_code -ne 0 ]]; then
    echo "MW10 runner: suite [$name] exited with code $exit_code." >&2
    rm -f "$output_file"
    return "$exit_code"
  fi
  if ! grep -Fq "$marker" "$output_file"; then
    echo "MW10 runner: suite [$name] did not print required marker: $marker" >&2
    rm -f "$output_file"
    return 1
  fi
  rm -f "$output_file"
}


failures=0
run_suite   "contracts/runtime"   "res://tests/matter/transactions/test_mw10_cross_region_transactions.gd"   "MW10 cross-region Matter transactions: PASS (184 assertions)" || failures=$((failures + 1))
run_suite   "multi-process"   "res://tests/matter/transactions/test_mw10_cross_region_processes.gd"   "MW10 cross-region Matter processes: PASS (51 assertions)" || failures=$((failures + 1))

if [[ $failures -ne 0 ]]; then
  echo "MW10 runner: FAIL ($failures/2 suites failed)." >&2
  exit 1
fi

echo "MW10 runner: PASS (2/2 suites)"
