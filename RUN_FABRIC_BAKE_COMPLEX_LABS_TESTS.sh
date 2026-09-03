#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
EXPECTED_GODOT_VERSION="4.7.1.stable.double.custom_build.a13da4feb"
SCRIPT_TIMEOUT_SECONDS="${COMPLEX_LABS_SCRIPT_TIMEOUT_SECONDS:-180}"

if [[ ! -x "$GODOT_BIN" ]]; then
  echo "COMPLEX LABS: canonical double Godot not executable: $GODOT_BIN" >&2
  exit 2
fi
version="$("$GODOT_BIN" --version | head -n1 | tr -d '\r')"
if [[ "$version" != "$EXPECTED_GODOT_VERSION" ]]; then
  echo "COMPLEX LABS: wrong Godot version: $version" >&2
  exit 3
fi

run_script() {
  local script="$1"
  local marker="$2"
  local env_pair="${3:-}"
  local log status_file pid started marker_seen=0
  log="$(mktemp)"
  status_file="$(mktemp)"
  started="$(date +%s)"

  (
    set +e
    if [[ -n "$env_pair" ]]; then
      env BREAKPOINT_RUNTIME_DISABLED=1 "$env_pair" "$GODOT_BIN" \
        --headless --path "$ROOT" --script "$script" >"$log" 2>&1
    else
      env BREAKPOINT_RUNTIME_DISABLED=1 "$GODOT_BIN" \
        --headless --path "$ROOT" --script "$script" >"$log" 2>&1
    fi
    printf '%s\n' "$?" >"$status_file"
  ) &
  pid=$!

  while kill -0 "$pid" 2>/dev/null; do
    if grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script' "$log"; then
      kill -TERM "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      cat "$log"
      echo "COMPLEX LABS: fatal Godot script marker detected in $script" >&2
      rm -f "$log" "$status_file"
      return 4
    fi
    if grep -Fq "$marker" "$log"; then
      marker_seen=1
      break
    fi
    if (( $(date +%s) - started >= SCRIPT_TIMEOUT_SECONDS )); then
      kill -TERM "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      cat "$log"
      echo "COMPLEX LABS: timeout before PASS marker in $script" >&2
      rm -f "$log" "$status_file"
      return 124
    fi
    sleep 0.25
  done

  if (( marker_seen == 1 )); then
    for _ in $(seq 1 20); do
      if ! kill -0 "$pid" 2>/dev/null; then
        break
      fi
      sleep 0.1
    done
    if kill -0 "$pid" 2>/dev/null; then
      echo "COMPLEX LABS: PASS marker reached; terminating post-pass teardown for $script ${env_pair:-}" >>"$log"
      kill -TERM "$pid" 2>/dev/null || true
    fi
    wait "$pid" 2>/dev/null || true
  else
    wait "$pid" 2>/dev/null || true
  fi

  cat "$log"
  if grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script' "$log"; then
    echo "COMPLEX LABS: fatal Godot script marker detected in $script" >&2
    rm -f "$log" "$status_file"
    return 4
  fi
  if ! grep -Fq "$marker" "$log"; then
    local status="unknown"
    [[ -s "$status_file" ]] && status="$(cat "$status_file")"
    echo "COMPLEX LABS: PASS marker missing in $script (status=$status)" >&2
    rm -f "$log" "$status_file"
    return 5
  fi
  rm -f "$log" "$status_file"
}

for scale in 50 100 500 2000; do
  run_script \
    res://tests/research/fabric_bake0/fabric_bake_complex0_acceptance.gd \
    "FABRIC-BAKE COMPLEX0 Acceptance: PASS" \
    "COMPLEX0_SCALE=$scale"
done

run_script \
  res://tests/research/fabric_bake0/fabric_bake_complex0_perf1_acceptance.gd \
  "FABRIC-BAKE COMPLEX0-PERF1 Acceptance: PASS"

run_script \
  res://tests/research/fabric_bake0/fabric_bake_complex1a_acceptance.gd \
  "FABRIC-BAKE COMPLEX1A Acceptance: PASS"

echo "FABRIC-BAKE COMPLEX LABS: PASS"
