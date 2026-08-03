#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMEOUT_SECONDS="${RL3_TIMEOUT_SECONDS:-300}"
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

names=("contracts/runtime" "multi-process")
scripts=(
  "res://tests/representation/test_rl3_representation_aware_network_streaming.gd"
  "res://tests/representation/test_rl3_representation_streaming_processes.gd"
)
markers=(
  "RL3 representation-aware network streaming: PASS (175 assertions)"
  "RL3 representation streaming processes: PASS (37 assertions)"
)
pids=()
outputs=()

cleanup() {
  for pid in "${pids[@]:-}"; do
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done
  for output in "${outputs[@]:-}"; do
    rm -f "$output"
  done
}
trap cleanup EXIT

for index in "${!scripts[@]}"; do
  output="$(mktemp)"
  outputs+=("$output")
  echo "RL3 runner: starting suite $((index + 1))/${#scripts[@]} [${names[$index]}]"
  timeout --signal=TERM --kill-after=10s "${TIMEOUT_SECONDS}s" \
    "$GODOT_EXECUTABLE" --headless --path "$ROOT_DIR" --script "${scripts[$index]}" \
    >"$output" 2>&1 &
  pids+=("$!")
done

failures=0
timed_out=0
for index in "${!pids[@]}"; do
  set +e
  wait "${pids[$index]}"
  exit_code=$?
  set -e
  cat "${outputs[$index]}"
  marker_found=0
  script_error_found=0
  if grep -Fq "${markers[$index]}" "${outputs[$index]}"; then
    marker_found=1
  fi
  if grep -Eq '^SCRIPT ERROR:|Parse Error:' "${outputs[$index]}"; then
    script_error_found=1
  fi
  if [[ $exit_code -eq 124 || $exit_code -eq 137 ]]; then
    echo "RL3 runner: suite [${names[$index]}] exceeded ${TIMEOUT_SECONDS}s." >&2
    failures=$((failures + 1))
    timed_out=1
  elif [[ $script_error_found -eq 1 ]]; then
    echo "RL3 runner: suite [${names[$index]}] printed a Godot script error." >&2
    failures=$((failures + 1))
  elif [[ $exit_code -ne 0 ]]; then
    echo "RL3 runner: suite [${names[$index]}] exited with code $exit_code." >&2
    failures=$((failures + 1))
  elif [[ $marker_found -ne 1 ]]; then
    echo "RL3 runner: suite [${names[$index]}] did not print required marker: ${markers[$index]}" >&2
    failures=$((failures + 1))
  else
    echo "RL3 runner: suite [${names[$index]}] PASS"
  fi
done

if [[ $failures -ne 0 ]]; then
  echo "RL3 runner: FAIL ($failures/${#scripts[@]} suites failed)." >&2
  if [[ $timed_out -eq 1 ]]; then
    exit 124
  fi
  exit 1
fi

echo "RL3 runner: PASS (${#scripts[@]}/${#scripts[@]} suites)"
