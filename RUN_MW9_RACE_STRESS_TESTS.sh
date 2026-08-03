#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BATCH_TIMEOUT_SECONDS="${MW9_RACE_BATCH_TIMEOUT_SECONDS:-180}"
ITERATIONS="${MW9_RACE_ITERATIONS:-100}"
BATCH_SIZE="${MW9_RACE_BATCH_SIZE:-8}"
GODOT_EXECUTABLE="${GODOT_BIN:-}"

for value_name in ITERATIONS BATCH_SIZE BATCH_TIMEOUT_SECONDS; do
  value="${!value_name}"
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    echo "$value_name must be a positive integer." >&2
    exit 2
  fi
done
if (( ITERATIONS < 1 || ITERATIONS > 1000 )); then
  echo "MW9_RACE_ITERATIONS must be from 1 to 1000." >&2
  exit 2
fi
if (( BATCH_SIZE < 1 || BATCH_SIZE > 32 )); then
  echo "MW9_RACE_BATCH_SIZE must be from 1 to 32." >&2
  exit 2
fi
if (( BATCH_TIMEOUT_SECONDS < 30 || BATCH_TIMEOUT_SECONDS > 3600 )); then
  echo "MW9_RACE_BATCH_TIMEOUT_SECONDS must be from 30 to 3600." >&2
  exit 2
fi

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

completed=0
batch_index=0
while (( completed < ITERATIONS )); do
  remaining=$((ITERATIONS - completed))
  rounds=$BATCH_SIZE
  if (( remaining < rounds )); then
    rounds=$remaining
  fi
  batch_index=$((batch_index + 1))
  log_file="$(mktemp)"
  trap 'rm -f "$log_file"' EXIT
  echo "MW9 race stress runner: batch $batch_index, rounds $((completed + 1))-$((completed + rounds))/$ITERATIONS"
  command=(
    "$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR"
    --script res://tests/matter/handoff/test_mw9_durable_handoff_processes.gd --
    --claim-race-only=true "--claim-race-rounds=$rounds"
  )

  set +e
  if command -v timeout >/dev/null 2>&1; then
    timeout --foreground "${BATCH_TIMEOUT_SECONDS}s" "${command[@]}" 2>&1 | tee "$log_file"
    exit_code=${PIPESTATUS[0]}
  else
    "${command[@]}" 2>&1 | tee "$log_file"
    exit_code=${PIPESTATUS[0]}
  fi
  set -e

  if (( exit_code != 0 )); then
    echo "MW9 race stress runner: batch $batch_index exited with code $exit_code." >&2
    rm -f "$log_file"
    exit "$exit_code"
  fi
  if grep -Eq 'SCRIPT ERROR:|Parse Error:' "$log_file"; then
    echo "MW9 race stress runner: batch $batch_index reported a script or parse error." >&2
    rm -f "$log_file"
    exit 1
  fi
  if ! grep -Fq "MW9 claim race stress: PASS (" "$log_file" \
      || ! grep -Fq ", $rounds rounds)" "$log_file"; then
    echo "MW9 race stress runner: batch $batch_index did not print the required marker for $rounds rounds." >&2
    rm -f "$log_file"
    exit 1
  fi
  rm -f "$log_file"
  trap - EXIT
  completed=$((completed + rounds))
done

echo "MW9 race stress runner: PASS ($ITERATIONS rounds in $batch_index batches)"
