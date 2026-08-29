#!/usr/bin/env bash
set -Eeuo pipefail

project="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
godot="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"

if [[ ! -x "$godot" ]]; then echo "Godot 4.7.1 double executable missing: $godot" >&2; exit 1; fi
if [[ ! -f "$project/project.godot" ]]; then echo "project.godot missing: $project" >&2; exit 1; fi
status_before="$(git -C "$project" status --porcelain 2>/dev/null || true)"
if [[ -n "$status_before" ]]; then echo "P9 gate requires a clean worktree." >&2; git -C "$project" status --short >&2; exit 1; fi

declare -A uid_before=()
while IFS= read -r uid; do [[ -n "$uid" ]] && uid_before["$uid"]=1; done < <(git -C "$project" ls-files --others --exclude-standard -- ':(glob)**/*.uid' 2>/dev/null || true)
run_id="$(date +%Y%m%d-%H%M%S)-$$"; log_root="$project/artifacts/runtime/sm0-p9-$run_id"; mkdir -p "$log_root"; pids=()
cleanup_processes(){ local pid; for pid in "${pids[@]:-}"; do [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true; done; for pid in "${pids[@]:-}"; do [[ -n "$pid" ]] && wait "$pid" 2>/dev/null || true; done; }
cleanup_new_uids(){ local uid; while IFS= read -r uid; do [[ -z "$uid" ]] && continue; if [[ -z "${uid_before[$uid]+x}" ]]; then rm -f -- "$project/$uid"; fi; done < <(git -C "$project" ls-files --others --exclude-standard -- ':(glob)**/*.uid' 2>/dev/null || true); }
trap 'cleanup_processes; cleanup_new_uids' EXIT
export BREAKPOINT_RUNTIME_DISABLED=1

scripts=(
 "res://scripts/runtime/seamless/sm0/sm0_p9_foreign_item_boundary_contract.gd"
 "res://scripts/runtime/seamless/sm0/sm0_p9_item_authority_node.gd"
 "res://scripts/runtime/seamless/sm0/sm0_p9_boundary_coordinator.gd"
 "res://scripts/runtime/seamless/sm0/sm0_p9_item_authority_process.gd"
 "res://tests/runtime/seamless/sm0/test_sm0_p9_foreign_item_boundary.gd"
 "res://tests/runtime/seamless/sm0/test_sm0_p9_process_boundary.gd")
for script in "${scripts[@]}"; do echo "[SM0-P9] Compile check: $script"; "$godot" --headless --path "$project" --check-only --script "$script"; done

echo "[SM0-P9] Running inherited P8 moving nested-island regression..."
p8_output="$("$godot" --headless --path "$project" --script res://tests/runtime/seamless/sm0/test_sm0_p8_moving_nested_island.gd 2>&1)"; printf '%s\n' "$p8_output"; grep -Fq 'SM0 P8 moving nested authority island: PASS (96 assertions)' <<<"$p8_output"
echo "[SM0-P9] Running focused foreign item/interactions boundary regression..."
p9_output="$("$godot" --headless --path "$project" --script res://tests/runtime/seamless/sm0/test_sm0_p9_foreign_item_boundary.gd 2>&1)"; printf '%s\n' "$p9_output"; grep -Fq 'SM0 P9 foreign item boundary: PASS (103 assertions)' <<<"$p9_output"

wait_marker(){ local path="$1" marker="$2" pid="$3" label="$4" deadline=$((SECONDS+15)); while ((SECONDS<deadline)); do if [[ -f "$path" ]] && grep -Fq "$marker" "$path"; then return 0; fi; if ! kill -0 "$pid" 2>/dev/null; then echo "$label exited before marker $marker. See $path" >&2; return 1; fi; sleep 0.05; done; echo "Timeout waiting for $label marker $marker. See $path" >&2; return 1; }
log_a="$log_root/world-a.log"; log_c="$log_root/world-c.log"; log_ship="$log_root/ship.log"; scenario_log="$log_root/scenario.log"
"$godot" --headless --path "$project" --log-file "$log_a" --script res://scripts/runtime/seamless/sm0/sm0_p9_item_authority_process.gd -- --authority-id=authority/sm0/a --listen-port=26820 >"$log_root/world-a.stdout.log" 2>&1 & pid_a=$!; pids+=("$pid_a")
"$godot" --headless --path "$project" --log-file "$log_c" --script res://scripts/runtime/seamless/sm0/sm0_p9_item_authority_process.gd -- --authority-id=authority/sm0/c --listen-port=26822 >"$log_root/world-c.stdout.log" 2>&1 & pid_c=$!; pids+=("$pid_c")
"$godot" --headless --path "$project" --log-file "$log_ship" --script res://scripts/runtime/seamless/sm0/sm0_p9_item_authority_process.gd -- --authority-id=authority/island/ship/01 --listen-port=26823 >"$log_root/ship.stdout.log" 2>&1 & pid_ship=$!; pids+=("$pid_ship")
wait_marker "$log_a" '"event":"SM0_P9_PROCESS_READY"' "$pid_a" "world A"; wait_marker "$log_c" '"event":"SM0_P9_PROCESS_READY"' "$pid_c" "world C"; wait_marker "$log_ship" '"event":"SM0_P9_PROCESS_READY"' "$pid_ship" "ship"
echo "[SM0-P9] Process PIDs A=$pid_a C=$pid_c ship=$pid_ship"
if [[ "$pid_a" == "$pid_c" || "$pid_a" == "$pid_ship" || "$pid_c" == "$pid_ship" ]]; then echo "P9 authority processes are not distinct." >&2; exit 1; fi
set +e; "$godot" --headless --path "$project" --script res://tests/runtime/seamless/sm0/test_sm0_p9_process_boundary.gd 2>&1 | tee "$scenario_log"; scenario_code=${PIPESTATUS[0]}; set -e
if [[ $scenario_code -ne 0 ]]; then echo "P9 process-isolated scenario failed with exit code $scenario_code" >&2; exit "$scenario_code"; fi
grep -Fq 'SM0 P9 process-isolated boundary: PASS (55 assertions)' "$scenario_log"
for pid in "$pid_a" "$pid_c" "$pid_ship"; do for _ in {1..100}; do if ! kill -0 "$pid" 2>/dev/null; then break; fi; sleep 0.05; done; if kill -0 "$pid" 2>/dev/null; then echo "P9 authority process $pid did not shut down." >&2; exit 1; fi; done; pids=()
for log in "$log_a" "$log_c" "$log_ship" "$scenario_log"; do if grep -E 'SCRIPT ERROR|Parse Error|Failed to load script|SM0_INVARIANT_VIOLATION' "$log" >/dev/null 2>&1; then echo "Fatal marker in $log" >&2; exit 1; fi; done
grep -Fq '"event":"SM0_P9_TRANSFER_SOURCE_RETIRED"' "$log_a"; grep -Fq '"event":"SM0_P9_TRANSFER_TARGET_COMMITTED"' "$log_ship"; grep -Fq '"event":"SM0_P9_TRANSFER_SOURCE_RETIRED"' "$log_ship"; grep -Fq '"event":"SM0_P9_TRANSFER_TARGET_COMMITTED"' "$log_c"; grep -Fq '"event":"SM0_P9_TRANSFER_SOURCE_ROLLED_BACK"' "$log_c"; grep -Fq '"event":"SM0_P9_TRANSFER_TARGET_ABORTED"' "$log_ship"
cleanup_new_uids; status_after="$(git -C "$project" status --porcelain 2>/dev/null || true)"; if [[ "$status_after" != "$status_before" ]]; then echo "P9 gate modified the source worktree." >&2; git -C "$project" status --short >&2; exit 1; fi
trap - EXIT
echo; echo "SM0-P9 foreign item/interactions boundary: PASS"; echo "  focused   : P9 103 assertions"; echo "  process   : P9 55 assertions / 3 distinct Godot authority processes"; echo "  inherited : P8 96 assertions"; echo "  authority : direct foreign mutation forbidden; interaction routed to current owner"; echo "  transfer  : WORLD -> SHIP -> current WORLD owner, stable item id"; echo "  safety    : source frozen during PREPARE; exact replay idempotent; failure replay deterministic"; echo "  rollback  : target commit failure restores source and aborts target shadow"; echo "  logs      : $log_root"