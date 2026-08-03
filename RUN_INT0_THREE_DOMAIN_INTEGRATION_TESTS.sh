#!/usr/bin/env bash
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_PATH="${1:-${GODOT_BIN:-}}"
PROFILE="${2:-full}"
REPORT_DIRECTORY="$PROJECT_ROOT/artifacts/test-results"
REPORT_PATH="$REPORT_DIRECTORY/int0-three-domain-integration-summary.json"
mkdir -p "$REPORT_DIRECTORY"

if [[ "$PROFILE" != "focused" && "$PROFILE" != "full" ]]; then
  echo "Profile must be focused or full." >&2
  exit 2
fi

if [[ -z "$GODOT_PATH" ]]; then
  for candidate in \
    "$PROJECT_ROOT/tools/godot/godot.linuxbsd.editor.double.x86_64" \
    "$PROJECT_ROOT/godot.linuxbsd.editor.double.x86_64" \
    "$(command -v godot 2>/dev/null || true)" \
    "$(command -v godot4 2>/dev/null || true)"; do
    if [[ -n "$candidate" && -x "$candidate" ]]; then
      GODOT_PATH="$candidate"
      break
    fi
  done
fi

if [[ -z "$GODOT_PATH" || ! -x "$GODOT_PATH" ]]; then
  echo "Godot executable not found. Set GODOT_BIN or pass Godot 4.7.1 double as the first argument." >&2
  exit 2
fi

export GODOT_BIN="$GODOT_PATH"
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
PASSED=true
FAILURE=""
STEPS=()

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  printf '%s' "$value"
}

record_step() {
  local name="$1"
  local target="$2"
  local passed="$3"
  local duration="$4"
  local exit_code="$5"
  local error_message="${6:-}"
  STEPS+=("{\"name\":\"$(json_escape "$name")\",\"target\":\"$(json_escape "$target")\",\"passed\":$passed,\"duration_seconds\":$duration,\"exit_code\":$exit_code,\"error\":\"$(json_escape "$error_message")\"}")
}

run_command_step() {
  local name="$1"
  local target="$2"
  shift 2
  local started finished code duration
  started="$(date +%s)"
  echo "INT0 runner: $target"
  "$@"
  code=$?
  finished="$(date +%s)"
  duration=$((finished - started))
  if [[ $code -eq 0 ]]; then
    record_step "$name" "$target" true "$duration" "$code"
    return 0
  fi
  record_step "$name" "$target" false "$duration" "$code" "command failed"
  FAILURE="INT0 step failed: $target (exit $code)"
  PASSED=false
  return "$code"
}

run_editor_import_step() {
  local started finished code duration
  local project_hash_before project_hash_after
  local untracked_uid_before untracked_uid_after new_uid_files
  local error_message=""

  project_hash_before="$(git -C "$PROJECT_ROOT" hash-object project.godot)"
  untracked_uid_before="$(git -C "$PROJECT_ROOT" ls-files --others --exclude-standard -- ':(glob)**/*.uid')"

  started="$(date +%s)"
  echo "INT0 runner: res://"
  "$GODOT_PATH" --headless --editor --path "$PROJECT_ROOT" --quit
  code=$?
  finished="$(date +%s)"
  duration=$((finished - started))

  project_hash_after="$(git -C "$PROJECT_ROOT" hash-object project.godot)"
  untracked_uid_after="$(git -C "$PROJECT_ROOT" ls-files --others --exclude-standard -- ':(glob)**/*.uid')"
  new_uid_files="$(comm -13 \
    <(printf '%s\n' "$untracked_uid_before" | sed '/^$/d' | sort) \
    <(printf '%s\n' "$untracked_uid_after" | sed '/^$/d' | sort))"

  if [[ $code -ne 0 ]]; then
    error_message="Godot exit code $code"
  fi
  if [[ "$project_hash_before" != "$project_hash_after" ]]; then
    error_message="${error_message:+$error_message; }project.godot changed during editor import"
  fi
  if [[ -n "$new_uid_files" ]]; then
    error_message="${error_message:+$error_message; }new untracked UID files: $new_uid_files"
  fi

  if [[ $code -eq 0 && "$project_hash_before" == "$project_hash_after" && -z "$new_uid_files" ]]; then
    record_step editor_import res:// true "$duration" 0
    return 0
  fi

  record_step editor_import res:// false "$duration" 1 "$error_message"
  FAILURE="INT0 editor import cleanliness failed: $error_message"
  PASSED=false
  return 1
}

run_suite() {
  local script_name="$1"
  local script_path="$PROJECT_ROOT/$script_name"
  if [[ ! -f "$script_path" ]]; then
    record_step "${script_name%.sh}" "$script_name" false 0 2 "required suite missing"
    FAILURE="Required INT0 suite is missing: $script_name"
    PASSED=false
    return 2
  fi
  run_command_step "${script_name%.sh}" "$script_name" bash "$script_path" "$GODOT_PATH"
}

FOCUSED_SUITES=(
  RUN_INT0_RL3_MW10_COMPOSITION_TESTS.sh
  RUN_NX6_PREDICTED_ITEM_INTERACTIONS_TESTS.sh
  RUN_MW10_CROSS_REGION_MATTER_TRANSACTIONS_TESTS.sh
  RUN_RL3_REPRESENTATION_AWARE_NETWORK_STREAMING_TESTS.sh
  RUN_C24_PROXY_MESH_BACKEND_TESTS.sh
)

FULL_SUITES=(
  RUN_INT0_RL3_MW10_COMPOSITION_TESTS.sh
  RUN_NX6_PREDICTED_ITEM_INTERACTIONS_TESTS.sh
  RUN_M7_PLAYABLE_NETWORKED_PLAYGROUND_TESTS.sh
  RUN_MW8_MATTER_HANDOFF_TESTS.sh
  RUN_MW9_DURABLE_HANDOFF_RECOVERY_TESTS.sh
  RUN_MW9_RACE_STRESS_TESTS.sh
  RUN_MW10_CROSS_REGION_MATTER_TRANSACTIONS_TESTS.sh
  RUN_RL2_MATTER_MULTIRESOLUTION_MESHING_TESTS.sh
  RUN_RL3_REPRESENTATION_AWARE_NETWORK_STREAMING_TESTS.sh
  RUN_C2B_AUTHORITATIVE_ITEM_GRAPH_TESTS.sh
  RUN_C9_DAMAGE_SPLIT_REPAIR_TESTS.sh
  RUN_C22_COMPILED_PROXY_TESTS.sh
  RUN_C23_PRODUCTION_HARDENING_TESTS.sh
  RUN_C24_PROXY_MESH_BACKEND_TESTS.sh
  RUN_NETWORK_CONTRACT_TESTS.sh
  RUN_WORLD_REGRESSION_TESTS.sh
)

SELECTED_SUITES=("${FULL_SUITES[@]}")
if [[ "$PROFILE" == "focused" ]]; then
  SELECTED_SUITES=("${FOCUSED_SUITES[@]}")
fi

echo "INT0 three-domain integration gate [$PROFILE]"
echo "Godot: $GODOT_PATH"

run_editor_import_step || true

if [[ "$PASSED" == true ]]; then
  for suite in "${SELECTED_SUITES[@]}"; do
    run_suite "$suite" || break
  done
fi

if [[ "$PASSED" == true ]]; then
  run_command_step git_diff_check "git diff --check" git -C "$PROJECT_ROOT" diff --check || true
fi

if [[ "$PASSED" == true ]]; then
  started="$(date +%s)"
  conflict_output="$(git -C "$PROJECT_ROOT" grep -n -E '^(<<<<<<< |=======|>>>>>>> )' -- . ':!artifacts' 2>&1)"
  conflict_code=$?
  finished="$(date +%s)"
  duration=$((finished - started))
  if [[ $conflict_code -eq 1 ]]; then
    record_step conflict_marker_scan "git grep conflict markers" true "$duration" "$conflict_code"
  else
    record_step conflict_marker_scan "git grep conflict markers" false "$duration" "$conflict_code" "$conflict_output"
    FAILURE="Conflict-marker scan failed."
    PASSED=false
  fi
fi

if [[ "$PASSED" == true ]]; then
  started="$(date +%s)"
  remaining="$(ps -eo pid=,comm=,args= | awk '$2 ~ /^godot/ {print}')"
  finished="$(date +%s)"
  duration=$((finished - started))
  if [[ -z "$remaining" ]]; then
    record_step remaining_godot_processes "ps process-name scan" true "$duration" 0
  else
    record_step remaining_godot_processes "ps process-name scan" false "$duration" 1 "$remaining"
    FAILURE="Godot processes remain after INT0 runner."
    PASSED=false
  fi
fi

step_json=""
for step in "${STEPS[@]}"; do
  if [[ -n "$step_json" ]]; then
    step_json+=","
  fi
  step_json+="$step"
done

FINISHED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$REPORT_PATH" <<JSON
{
  "schema": "distributed_world_simulator.int0_three_domain_summary.v1",
  "checkpoint": "v18.0.0-integration-int0-three-domain-base",
  "profile": "$PROFILE",
  "passed": $PASSED,
  "started_at_utc": "$STARTED_AT",
  "finished_at_utc": "$FINISHED_AT",
  "godot": "$(json_escape "$GODOT_PATH")",
  "suite_count": ${#SELECTED_SUITES[@]},
  "failure": "$(json_escape "$FAILURE")",
  "steps": [$step_json]
}
JSON

echo "INT0 report: $REPORT_PATH"
if [[ "$PASSED" != true ]]; then
  echo "$FAILURE" >&2
  exit 1
fi

echo "INT0 three-domain integration gate: PASS [$PROFILE]"
