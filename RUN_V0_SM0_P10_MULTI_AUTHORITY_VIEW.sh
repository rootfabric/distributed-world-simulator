#!/usr/bin/env bash
set -Eeuo pipefail

project="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
godot="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
expected_godot="4.7.1.stable.double.custom_build.a13da4feb"

if [[ ! -x "$godot" ]]; then echo "Godot 4.7.1 double executable missing: $godot" >&2; exit 1; fi
if [[ ! -f "$project/project.godot" ]]; then echo "project.godot missing: $project" >&2; exit 1; fi
version="$($godot --version | tr -d '\r')"
if [[ "$version" != "$expected_godot" ]]; then echo "Unexpected Godot: $version (expected $expected_godot)" >&2; exit 1; fi
status_before="$(git -C "$project" status --porcelain 2>/dev/null || true)"
if [[ -n "$status_before" ]]; then echo "P10 gate requires a clean worktree." >&2; git -C "$project" status --short >&2; exit 1; fi

declare -A uid_before=()
while IFS= read -r uid; do [[ -n "$uid" ]] && uid_before["$uid"]=1; done < <(git -C "$project" ls-files --others --exclude-standard -- ':(glob)**/*.uid' 2>/dev/null || true)
run_id="$(date +%Y%m%d-%H%M%S)-$$"
log_root="$project/artifacts/runtime/sm0-p10-$run_id"
mkdir -p "$log_root"
pids=()
cleanup_processes(){ local pid; for pid in "${pids[@]:-}"; do [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true; done; for pid in "${pids[@]:-}"; do [[ -n "$pid" ]] && wait "$pid" 2>/dev/null || true; done; }
cleanup_new_uids(){ local uid; while IFS= read -r uid; do [[ -z "$uid" ]] && continue; if [[ -z "${uid_before[$uid]+x}" ]]; then rm -f -- "$project/$uid"; fi; done < <(git -C "$project" ls-files --others --exclude-standard -- ':(glob)**/*.uid' 2>/dev/null || true); }
trap 'cleanup_processes; cleanup_new_uids' EXIT
export BREAKPOINT_RUNTIME_DISABLED=1

echo "[SM0-P10] Godot: $version"
echo "[SM0-P10] HEAD : $(git -C "$project" rev-parse HEAD)"
echo "[SM0-P10] Logs : $log_root"

echo "[SM0-P10] Running inherited P9 full boundary gate..."
PROJECT_ROOT="$project" GODOT_BIN="$godot" bash "$project/RUN_V0_SM0_P9_FOREIGN_ITEM_BOUNDARY.sh" | tee "$log_root/inherited-p9.log"
grep -Fq 'SM0-P9 foreign item/interactions boundary: PASS' "$log_root/inherited-p9.log"

scripts=(
 "res://scripts/runtime/seamless/sm0/sm0_p10_view_contract.gd"
 "res://scripts/runtime/seamless/sm0/sm0_p10_multi_authority_view_composer.gd"
 "res://scripts/runtime/seamless/sm0/sm0_p10_projection_source_process.gd"
 "res://tests/runtime/seamless/sm0/test_sm0_p10_multi_authority_view.gd"
 "res://tests/runtime/seamless/sm0/test_sm0_p10_process_composition.gd"
)
for script in "${scripts[@]}"; do
  echo "[SM0-P10] Compile check: $script"
  "$godot" --headless --path "$project" --check-only --script "$script"
done

echo "[SM0-P10] Running focused multi-authority composition regression..."
p10_output="$("$godot" --headless --path "$project" --script res://tests/runtime/seamless/sm0/test_sm0_p10_multi_authority_view.gd 2>&1)"
printf '%s\n' "$p10_output" | tee "$log_root/focused.log"
grep -Fq 'SM0 P10 multi-authority view + LOD: PASS (91 assertions)' <<<"$p10_output"

wait_marker(){ local path="$1" marker="$2" pid="$3" label="$4" deadline=$((SECONDS+15)); while ((SECONDS<deadline)); do if [[ -f "$path" ]] && grep -Fq "$marker" "$path"; then return 0; fi; if ! kill -0 "$pid" 2>/dev/null; then echo "$label exited before marker $marker. See $path" >&2; return 1; fi; sleep 0.05; done; echo "Timeout waiting for $label marker $marker. See $path" >&2; return 1; }

log_a="$log_root/source-a.log"; log_b="$log_root/source-b.log"; log_c="$log_root/source-c.log"; scenario_log="$log_root/scenario.log"
"$godot" --headless --path "$project" --log-file "$log_a" --script res://scripts/runtime/seamless/sm0/sm0_p10_projection_source_process.gd -- --authority-id=authority/sm0/a --source-role=FOREIGN --listen-port=26920 >"$log_root/source-a.stdout.log" 2>&1 & pid_a=$!; pids+=("$pid_a")
"$godot" --headless --path "$project" --log-file "$log_b" --script res://scripts/runtime/seamless/sm0/sm0_p10_projection_source_process.gd -- --authority-id=authority/sm0/b --source-role=LOCAL --listen-port=26921 >"$log_root/source-b.stdout.log" 2>&1 & pid_b=$!; pids+=("$pid_b")
"$godot" --headless --path "$project" --log-file "$log_c" --script res://scripts/runtime/seamless/sm0/sm0_p10_projection_source_process.gd -- --authority-id=authority/sm0/c --source-role=FOREIGN --listen-port=26922 >"$log_root/source-c.stdout.log" 2>&1 & pid_c=$!; pids+=("$pid_c")
wait_marker "$log_a" '"event":"SM0_P10_SOURCE_READY"' "$pid_a" "source A"
wait_marker "$log_b" '"event":"SM0_P10_SOURCE_READY"' "$pid_b" "source B"
wait_marker "$log_c" '"event":"SM0_P10_SOURCE_READY"' "$pid_c" "source C"
echo "[SM0-P10] Source PIDs A=$pid_a B=$pid_b C=$pid_c"
if [[ "$pid_a" == "$pid_b" || "$pid_a" == "$pid_c" || "$pid_b" == "$pid_c" ]]; then echo "P10 projection source processes are not distinct." >&2; exit 1; fi

set +e
"$godot" --headless --path "$project" --script res://tests/runtime/seamless/sm0/test_sm0_p10_process_composition.gd 2>&1 | tee "$scenario_log"
scenario_code=${PIPESTATUS[0]}
set -e
if [[ $scenario_code -ne 0 ]]; then echo "P10 process-isolated scenario failed with exit code $scenario_code" >&2; exit "$scenario_code"; fi
grep -Fq 'SM0 P10 process-isolated composition: PASS (52 assertions)' "$scenario_log"

for pid in "$pid_a" "$pid_b" "$pid_c"; do
  for _ in {1..100}; do if ! kill -0 "$pid" 2>/dev/null; then break; fi; sleep 0.05; done
  if kill -0 "$pid" 2>/dev/null; then echo "P10 source process $pid did not shut down." >&2; exit 1; fi
done
pids=()
for log in "$log_a" "$log_b" "$log_c" "$scenario_log"; do
  if grep -E 'SCRIPT ERROR|Parse Error|Failed to load script|SM0_INVARIANT_VIOLATION' "$log" >/dev/null 2>&1; then echo "Fatal marker in $log" >&2; exit 1; fi
done
for log in "$log_a" "$log_b" "$log_c"; do
  grep -Fq '"event":"SM0_P10_SOURCE_READY"' "$log"
  grep -Fq '"event":"SM0_P10_SOURCE_SNAPSHOT_SENT"' "$log"
  grep -Fq '"event":"SM0_P10_SOURCE_EXIT"' "$log"
  grep -Eq '"exit_code"[[:space:]]*:[[:space:]]*0([[:space:]]*[,}])' "$log"
done

cleanup_new_uids
status_after="$(git -C "$project" status --porcelain 2>/dev/null || true)"
if [[ "$status_after" != "$status_before" ]]; then echo "P10 gate modified the source worktree." >&2; git -C "$project" status --short >&2; exit 1; fi
trap - EXIT

echo
echo "SM0-P10 multi-authority view + representation LOD: PASS"
echo "  focused    : P10 91 assertions"
echo "  process    : P10 52 assertions / 3 distinct projection-source processes"
echo "  inherited  : full P9 gate PASS (including P8 96 / P9 103 / P9 process 55)"
echo "  composition: LOCAL B + FOREIGN A/C -> one presentation view"
echo "  fencing    : per-source epoch / sequence / checksum fail-closed"
echo "  LOD        : distance + priority + bandwidth coarse/fine selection"
echo "  progressive: fine representation upgrade + content cache reuse"
echo "  dropout    : source A loss removes A dynamic state only; cached coarse A degrades read-only"
echo "  safety     : presentation artifacts cannot become canonical state"
echo "  logs       : $log_root"