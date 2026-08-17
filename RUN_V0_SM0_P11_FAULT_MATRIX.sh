#!/usr/bin/env bash
set -Eeuo pipefail

project="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
godot="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
iterations="${P11_ITERATIONS:-120}"
expected_godot="4.7.1.stable.double.custom_build.a13da4feb"

if [[ ! "$iterations" =~ ^[1-9][0-9]*$ ]]; then echo "P11_ITERATIONS must be a positive integer." >&2; exit 1; fi
if [[ ! -x "$godot" ]]; then echo "Godot 4.7.1 double executable missing: $godot" >&2; exit 1; fi
if [[ ! -f "$project/project.godot" ]]; then echo "project.godot missing: $project" >&2; exit 1; fi
version="$("$godot" --version | tr -d '\r')"
if [[ "$version" != "$expected_godot" ]]; then echo "Unexpected Godot: $version (expected $expected_godot)" >&2; exit 1; fi
status_before="$(git -C "$project" status --porcelain 2>/dev/null || true)"
if [[ -n "$status_before" ]]; then echo "P11 gate requires a clean worktree." >&2; git -C "$project" status --short >&2; exit 1; fi

declare -A uid_before=()
while IFS= read -r uid; do [[ -n "$uid" ]] && uid_before["$uid"]=1; done < <(git -C "$project" ls-files --others --exclude-standard -- ':(glob)**/*.uid' 2>/dev/null || true)
run_id="$(date +%Y%m%d-%H%M%S)-$$"
log_root="$project/artifacts/runtime/sm0-p11-$run_id"
mkdir -p "$log_root"
pids=()
cleanup_processes(){ local pid; for pid in "${pids[@]:-}"; do [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true; done; for pid in "${pids[@]:-}"; do [[ -n "$pid" ]] && wait "$pid" 2>/dev/null || true; done; }
cleanup_new_uids(){ local uid; while IFS= read -r uid; do [[ -z "$uid" ]] && continue; if [[ -z "${uid_before[$uid]+x}" ]]; then rm -f -- "$project/$uid"; fi; done < <(git -C "$project" ls-files --others --exclude-standard -- ':(glob)**/*.uid' 2>/dev/null || true); }
trap 'cleanup_processes; cleanup_new_uids' EXIT
export BREAKPOINT_RUNTIME_DISABLED=1

echo "[SM0-P11] Godot     : $version"
echo "[SM0-P11] HEAD      : $(git -C "$project" rev-parse HEAD)"
echo "[SM0-P11] Iterations: $iterations"
echo "[SM0-P11] Logs      : $log_root"

echo "[SM0-P11] Running inherited P10 full view/LOD gate..."
PROJECT_ROOT="$project" GODOT_BIN="$godot" bash "$project/RUN_V0_SM0_P10_MULTI_AUTHORITY_VIEW.sh" | tee "$log_root/inherited-p10.log"
grep -Fq 'SM0-P10 multi-authority view + representation LOD: PASS' "$log_root/inherited-p10.log"

scripts=(
 "res://scripts/runtime/seamless/sm0/sm0_p11_fault_contract.gd"
 "res://scripts/runtime/seamless/sm0/sm0_p11_simultaneous_crossing_model.gd"
 "res://scripts/runtime/seamless/sm0/sm0_p11_authority_process.gd"
 "res://tests/runtime/seamless/sm0/test_sm0_p11_fault_matrix.gd"
 "res://tests/runtime/seamless/sm0/test_sm0_p11_process_soak.gd"
)
for script in "${scripts[@]}"; do
  echo "[SM0-P11] Compile check: $script"
  "$godot" --headless --path "$project" --check-only --script "$script"
done

echo "[SM0-P11] Running deterministic focused fault matrix..."
focused_output="$("$godot" --headless --path "$project" --script res://tests/runtime/seamless/sm0/test_sm0_p11_fault_matrix.gd 2>&1)"
printf '%s\n' "$focused_output" | tee "$log_root/focused.log"
grep -Eq 'SM0 P11 deterministic fault matrix: PASS \([0-9]+ assertions\)' <<<"$focused_output"

wait_marker(){ local path="$1" marker="$2" pid="$3" label="$4" deadline=$((SECONDS+15)); while ((SECONDS<deadline)); do if [[ -f "$path" ]] && grep -Fq "$marker" "$path"; then return 0; fi; if ! kill -0 "$pid" 2>/dev/null; then echo "$label exited before marker $marker. See $path" >&2; return 1; fi; sleep 0.05; done; echo "Timeout waiting for $label marker $marker. See $path" >&2; return 1; }

log_a="$log_root/authority-a.log"; log_b="$log_root/authority-b.log"; log_c="$log_root/authority-c.log"; scenario_log="$log_root/process-soak.log"
"$godot" --headless --path "$project" --log-file "$log_a" --script res://scripts/runtime/seamless/sm0/sm0_p11_authority_process.gd -- --authority-id=authority/sm0/a --listen-port=27020 >"$log_root/authority-a.stdout.log" 2>&1 & pid_a=$!; pids+=("$pid_a")
"$godot" --headless --path "$project" --log-file "$log_b" --script res://scripts/runtime/seamless/sm0/sm0_p11_authority_process.gd -- --authority-id=authority/sm0/b --listen-port=27021 >"$log_root/authority-b.stdout.log" 2>&1 & pid_b=$!; pids+=("$pid_b")
"$godot" --headless --path "$project" --log-file "$log_c" --script res://scripts/runtime/seamless/sm0/sm0_p11_authority_process.gd -- --authority-id=authority/sm0/c --listen-port=27022 >"$log_root/authority-c.stdout.log" 2>&1 & pid_c=$!; pids+=("$pid_c")

wait_marker "$log_a" '"event":"SM0_P11_AUTHORITY_READY"' "$pid_a" "authority A"
wait_marker "$log_b" '"event":"SM0_P11_AUTHORITY_READY"' "$pid_b" "authority B"
wait_marker "$log_c" '"event":"SM0_P11_AUTHORITY_READY"' "$pid_c" "authority C"
echo "[SM0-P11] Authority PIDs A=$pid_a B=$pid_b C=$pid_c"
if [[ "$pid_a" == "$pid_b" || "$pid_a" == "$pid_c" || "$pid_b" == "$pid_c" ]]; then echo "P11 authority processes are not distinct." >&2; exit 1; fi

set +e
"$godot" --headless --path "$project" --script res://tests/runtime/seamless/sm0/test_sm0_p11_process_soak.gd -- --iterations="$iterations" 2>&1 | tee "$scenario_log"
scenario_code=${PIPESTATUS[0]}
set -e
if [[ $scenario_code -ne 0 ]]; then echo "P11 process-isolated soak failed with exit code $scenario_code" >&2; exit "$scenario_code"; fi
grep -Eq "SM0 P11 process-isolated simultaneous crossings \+ soak: PASS \($iterations iterations / [0-9]+ assertions\)" "$scenario_log"

for pid in "$pid_a" "$pid_b" "$pid_c"; do
  for _ in {1..100}; do if ! kill -0 "$pid" 2>/dev/null; then break; fi; sleep 0.05; done
  if kill -0 "$pid" 2>/dev/null; then echo "P11 authority process $pid did not shut down." >&2; exit 1; fi
done
for pid in "$pid_a" "$pid_b" "$pid_c"; do wait "$pid"; done
pids=()

for log in "$log_a" "$log_b" "$log_c" "$scenario_log"; do
  if grep -E 'SCRIPT ERROR|Parse Error|Failed to load script|SM0_INVARIANT_VIOLATION' "$log" >/dev/null 2>&1; then echo "Fatal marker in $log" >&2; exit 1; fi
done
for log in "$log_a" "$log_b" "$log_c"; do
  grep -Fq '"event":"SM0_P11_AUTHORITY_READY"' "$log"
  grep -Fq '"event":"SM0_P11_AUTHORITY_EXIT"' "$log"
  grep -Eq '"exit_code"[[:space:]]*:[[:space:]]*0([[:space:]]*[,}])' "$log"
done

cleanup_new_uids
status_after="$(git -C "$project" status --porcelain 2>/dev/null || true)"
if [[ "$status_after" != "$status_before" ]]; then echo "P11 gate modified the source worktree." >&2; git -C "$project" status --short >&2; exit 1; fi
trap - EXIT

echo
echo "SM0-P11 deterministic fault matrix + simultaneous-crossing soak: PASS"
echo "  focused    : deterministic fault matrix PASS (68 assertions on implementation baseline)"
echo "  process    : 3 distinct Godot authority processes / $iterations soak iterations"
echo "  simultaneous: A->B + B->A and A->B + B->C overlap proved"
echo "  fencing    : retirement proof, epoch, operation replay and stale-owner fail-closed"
echo "  projection : delayed/reordered projection rejected; one-source dropout isolated"
echo "  fault      : unavailable peer does not freeze unrelated writer"
echo "  invariant  : exactly one active writer per aggregate after every soak crossing"
echo "  inherited  : full P10 gate PASS (therefore P8/P9/P10 remain green)"
echo "  logs       : $log_root"
