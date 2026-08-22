#!/usr/bin/env bash
# EG4 atomic summary runner (bash twin of RUN_EG3_EDGE_GATEWAY_TESTS.ps1):
# fresh import pass, then every EG4 test with exit-code + failure-marker
# gating, and an atomically published JSON suite summary.
set -Eeuo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
report_directory="$project_root/artifacts/test-results"
report_path="$report_directory/eg4-edge-gateway-summary.json"
mkdir -p "$report_directory"

godot_bin="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
if [[ ! -x "$godot_bin" ]]; then
  if command -v godot4 >/dev/null 2>&1; then
    godot_bin="$(command -v godot4)"
  elif command -v godot >/dev/null 2>&1; then
    godot_bin="$(command -v godot)"
  else
    echo "Double-precision Godot not found. Set GODOT_BIN." >&2
    exit 2
  fi
fi

tests=(
  "res://tests/network/test_eg4_world_fixture.gd"
  "res://tests/network/test_eg4_view_planner.gd"
  "res://tests/network/test_eg4_interest_aggregator.gd"
  "res://tests/network/test_eg4_projection_aggregation.gd"
  "res://tests/network/test_eg4_projection_lifecycle.gd"
  "res://tests/network/test_eg4_two_worlds_one_transport.gd"
)

# Failure markers any EG4 test may print on an assertion breach.
failure_markers=(
  '][FAIL]'
  '"verdict": "FAIL"'
  'SCRIPT ERROR:'
  'PREDICATE_NOT_DEMONSTRATED'
)

started_at_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
entries_file="$(mktemp)"
tmp_summary="$(mktemp "$report_directory/.eg4-edge-gateway-summary.json.$$.XXXXXX.tmp")"
transcript_file="$(mktemp)"
cleanup() {
  rm -f "$entries_file" "$tmp_summary" "$transcript_file"
}
trap cleanup EXIT

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

write_summary() {
  local passed="$1"
  {
    printf '{\n'
    printf '  "schema": "planet_simulator.eg4_edge_gateway_suite_summary.v1",\n'
    printf '  "stage": "EG4_WORLD_GRAPH_DRIVEN_PROJECTION_AGGREGATION",\n'
    printf '  "godot": "%s",\n' "$(json_escape "$godot_bin")"
    printf '  "started_at_utc": "%s",\n' "$started_at_utc"
    printf '  "passed": %s,\n' "$passed"
    printf '  "tests": [\n'
    local first=1
    local line
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      if (( first )); then
        first=0
      else
        printf ',\n'
      fi
      printf '    %s' "$line"
    done < "$entries_file"
    printf '\n  ]\n}\n'
  } > "$tmp_summary"
  if command -v python3 >/dev/null 2>&1; then
    python3 -m json.tool "$tmp_summary" >/dev/null
  fi
  mv -f "$tmp_summary" "$report_path"
}

echo "Godot: $godot_bin"
echo "Stage: EG4 WORLD_GRAPH_DRIVEN_PROJECTION_AGGREGATION"

if ! BREAKPOINT_RUNTIME_DISABLED=1 "$godot_bin" --headless --editor --path "$project_root" --quit >"$transcript_file" 2>&1; then
  write_summary false
  echo "Godot editor import/parse failed" >&2
  exit 1
fi
for marker in "${failure_markers[@]}"; do
  if grep -qF -- "$marker" "$transcript_file"; then
    write_summary false
    echo "Editor import transcript contains failure marker: $marker" >&2
    exit 1
  fi
done

for test_script in "${tests[@]}"; do
  echo "[$test_script]"
  set +e
  BREAKPOINT_RUNTIME_DISABLED=1 "$godot_bin" \
    --headless --path "$project_root" --script "$test_script" >"$transcript_file" 2>&1
  exit_code=$?
  set -e
  marker_hits=""
  for marker in "${failure_markers[@]}"; do
    if grep -qF -- "$marker" "$transcript_file"; then
      marker_hits="$marker_hits$marker,"
    fi
  done
  marker_hits="${marker_hits%,}"
  verdict_line="$(grep -E '"verdict"' "$transcript_file" | tail -1 || true)"
  entry_passed=1
  (( exit_code == 0 )) || entry_passed=0
  [[ -z "$marker_hits" ]] || entry_passed=0
  printf '{"test": "%s", "exit_code": %s, "failure_markers": [%s], "verdict_line": "%s", "passed": %s}\n' \
    "$(json_escape "$(basename "$test_script" .gd)")" \
    "$exit_code" \
    "$(json_escape "$(printf '"%s"' "${marker_hits//,/\", \"}")")" \
    "$(json_escape "$verdict_line")" \
    "$( (( entry_passed )) && echo true || echo false )" \
    >> "$entries_file"
  write_summary false
  echo "$verdict_line"
  if (( entry_passed == 0 )); then
    write_summary false
    echo "$test_script failed (exit code $exit_code, markers: $marker_hits)" >&2
    exit 1
  fi
done

write_summary true
echo "EG4 world-graph-driven projection aggregation suite: PASS"
echo "Report: $report_path"
