#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
EXPECTED_GODOT_VERSION="4.7.1.stable.double.custom_build.a13da4feb"
SCRIPT_TIMEOUT_SECONDS="${CX_VIS_SCRIPT_TIMEOUT_SECONDS:-240}"

if [[ ! -x "$GODOT_BIN" ]]; then
  echo "FABRIC CX-VIS: canonical double Godot not executable: $GODOT_BIN" >&2
  exit 2
fi

version="$("$GODOT_BIN" --version | head -n1 | tr -d '\r')"
if [[ "$version" != "$EXPECTED_GODOT_VERSION" ]]; then
  echo "FABRIC CX-VIS: wrong Godot version: $version" >&2
  exit 3
fi

run_script() {
  local script="$1"
  local marker="$2"
  local log status_file pid started marker_seen=0
  log="$(mktemp)"
  status_file="$(mktemp)"
  started="$(date +%s)"

  (
    set +e
    env BREAKPOINT_RUNTIME_DISABLED=1 "$GODOT_BIN"       --headless --path "$ROOT" --script "$script" >"$log" 2>&1
    printf '%s\n' "$?" >"$status_file"
  ) &
  pid=$!

  while kill -0 "$pid" 2>/dev/null; do
    if grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script' "$log"; then
      kill -TERM "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      cat "$log"
      echo "FABRIC CX-VIS: fatal Godot script marker detected in $script" >&2
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
      echo "FABRIC CX-VIS: timeout before PASS marker in $script" >&2
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
      echo "FABRIC CX-VIS: PASS marker reached; terminating post-pass teardown for $script" >>"$log"
      kill -TERM "$pid" 2>/dev/null || true
    fi
    wait "$pid" 2>/dev/null || true
  else
    wait "$pid" 2>/dev/null || true
  fi

  cat "$log"
  if grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script' "$log"; then
    echo "FABRIC CX-VIS: fatal Godot script marker detected in $script" >&2
    rm -f "$log" "$status_file"
    return 4
  fi
  if ! grep -Fq "$marker" "$log"; then
    local status="unknown"
    [[ -s "$status_file" ]] && status="$(cat "$status_file")"
    echo "FABRIC CX-VIS: PASS marker missing in $script (status=$status)" >&2
    rm -f "$log" "$status_file"
    return 5
  fi
  rm -f "$log" "$status_file"
}

run_script   res://tests/research/fabric_bake0/fabric_bake_complex0_2000_exact_closure.gd   "FABRIC-BAKE COMPLEX0 2000 Exact Closure: PASS"

run_script   res://tests/research/fabric_bake0/fabric_bake_complex1a_acceptance.gd   "FABRIC-BAKE COMPLEX1A Acceptance: PASS"

run_script   res://tests/research/fabric_bake0/fabric_bake_cx_vis_observatory_acceptance.gd   "FABRIC CX-VIS0/1 Observatory Acceptance: PASS"

echo "FABRIC CX-VIS0/1: PASS"
