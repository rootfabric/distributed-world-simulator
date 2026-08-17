#!/usr/bin/env bash
set -Eeuo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
godot_bin="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
visual=0
visual_hold_seconds=15
allow_dirty=0

for arg in "$@"; do
  case "$arg" in
    --visual) visual=1 ;;
    --allow-dirty) allow_dirty=1 ;;
    --visual-hold-seconds=*) visual_hold_seconds="${arg#*=}" ;;
    --project-root=*) project_root="${arg#*=}" ;;
    --godot-bin=*) godot_bin="${arg#*=}" ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

project_root="$(cd "$project_root" && pwd)"
[[ -f "$project_root/project.godot" ]] || { echo "project.godot missing: $project_root" >&2; exit 2; }
[[ -x "$godot_bin" ]] || { echo "Godot binary missing: $godot_bin" >&2; exit 2; }
[[ "$visual_hold_seconds" =~ ^[0-9]+$ ]] || { echo "visual hold seconds must be >= 0" >&2; exit 2; }

version="$($godot_bin --version | head -n1)"
[[ "$version" == *"4.7.1.stable.double.custom_build.a13da4feb"* ]] || { echo "Unexpected Godot: $version" >&2; exit 2; }
head_sha="$(git -C "$project_root" rev-parse HEAD)"
status_before="$(git -C "$project_root" status --short)"
if [[ -n "$status_before" && "$allow_dirty" -ne 1 ]]; then
  echo "P8.1 gate requires a clean worktree:" >&2
  printf '%s\n' "$status_before" >&2
  exit 2
fi

mapfile -t uid_before < <(git -C "$project_root" ls-files --others --exclude-standard -- ':(glob)**/*.uid')
declare -A uid_before_set=()
for f in "${uid_before[@]}"; do uid_before_set["$f"]=1; done
cleanup_uids() {
  local -a after=()
  local f
  mapfile -t after < <(git -C "$project_root" ls-files --others --exclude-standard -- ':(glob)**/*.uid')
  for f in "${after[@]}"; do
    if [[ -z "${uid_before_set[$f]+x}" ]]; then rm -f -- "$project_root/$f"; fi
  done
}

export BREAKPOINT_RUNTIME_DISABLED=1
run_id="$(date +%Y%m%d-%H%M%S)-$$"
log_root="$project_root/artifacts/runtime/sm0-p8-1-$run_id"
mkdir -p "$log_root"
start_file="$log_root/start.flag"
stop_file="$log_root/stop.flag"
pids=()
cleanup() {
  touch "$stop_file" 2>/dev/null || true
  for pid in "${pids[@]:-}"; do
    [[ -n "$pid" ]] || continue
    kill "$pid" 2>/dev/null || true
  done
  cleanup_uids || true
}
trap cleanup EXIT

wait_marker() {
  local file="$1" marker="$2" label="$3" pid="$4"
  local i
  for i in $(seq 1 400); do
    if [[ -f "$file" ]] && grep -Fq "$marker" "$file"; then return 0; fi
    if [[ -f "$file" ]] && grep -Eq 'SCRIPT ERROR|Parse Error|Failed to load script|setup_failed|SM0_INVARIANT_VIOLATION' "$file"; then
      echo "Fatal marker in $label" >&2; tail -n 120 "$file" >&2 || true; return 1
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "$label exited before marker $marker" >&2; tail -n 120 "$file" >&2 || true; return 1
    fi
    sleep 0.05
  done
  echo "Timeout waiting for $label: $marker" >&2; tail -n 120 "$file" >&2 || true; return 1
}

run_focused() {
  local script="$1" marker="$2" log="$3"
  "$godot_bin" --headless --path "$project_root" --script "$script" 2>&1 | tee "$log"
  local rc=${PIPESTATUS[0]}
  [[ "$rc" -eq 0 ]] || return "$rc"
  grep -Fq "$marker" "$log"
}

echo "[SM0-P8.1] Godot: $version"
echo "[SM0-P8.1] HEAD : $head_sha"
echo "[SM0-P8.1] Logs : $log_root"

for script in \
  res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_observer.gd \
  res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_observer_process.gd \
  res://tests/runtime/seamless/sm0/test_sm0_p8_1_visual_reference_frame.gd
do
  echo "[SM0-P8.1] Compile check: $script"
  "$godot_bin" --headless --path "$project_root" --check-only --script "$script"
done

run_focused res://tests/runtime/seamless/sm0/test_sm0_p8_moving_nested_island.gd \
  'SM0 P8 moving nested authority island: PASS (96 assertions)' "$log_root/p8-focused.log"
run_focused res://tests/runtime/seamless/sm0/test_sm0_p8_1_visual_reference_frame.gd \
  'SM0 P8.1 visual reference-frame repair: PASS (33 assertions)' "$log_root/p8-1-focused.log"

observer_log="$log_root/observer.log"; nested_log="$log_root/nested.log"; a_log="$log_root/a.log"; b_log="$log_root/b.log"; c_log="$log_root/c.log"
observer_args=(--path "$project_root" --log-file "$observer_log" --script res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_observer_process.gd -- --listen-port=26524 --visual-response-hz=14.0 --stop-file="$stop_file")
if [[ "$visual" -eq 1 ]]; then
  "$godot_bin" "${observer_args[@]}" >"$log_root/observer.stdout.log" 2>&1 &
else
  "$godot_bin" --headless "${observer_args[@]}" >"$log_root/observer.stdout.log" 2>&1 &
fi
observer=$!; pids+=("$observer")

"$godot_bin" --headless --path "$project_root" --log-file "$nested_log" --script res://scripts/runtime/seamless/sm0/sm0_p8_nested_authority_process.gd -- --anchor-port=26523 --view-port=26524 --stop-file="$stop_file" >"$log_root/nested.stdout.log" 2>&1 &
nested=$!; pids+=("$nested")
"$godot_bin" --headless --path "$project_root" --log-file "$b_log" --script res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_outer_process.gd -- --authority-id=authority/sm0/b --listen-port=26521 --neighbor-a-port=26520 --neighbor-c-port=26522 --stop-file="$stop_file" >"$log_root/b.stdout.log" 2>&1 &
b=$!; pids+=("$b")
"$godot_bin" --headless --path "$project_root" --log-file "$c_log" --script res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_outer_process.gd -- --authority-id=authority/sm0/c --listen-port=26522 --neighbor-b-port=26521 --anchor-port=26523 --initial-writer=false --auto-return-target=authority/sm0/a --stop-file="$stop_file" >"$log_root/c.stdout.log" 2>&1 &
c=$!; pids+=("$c")
"$godot_bin" --headless --path "$project_root" --log-file "$a_log" --script res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_outer_process.gd -- --authority-id=authority/sm0/a --listen-port=26520 --neighbor-b-port=26521 --anchor-port=26523 --initial-writer=true --initial-x=-1.0 --velocity-x=0.8 --velocity-z=0.1 --angular-velocity-yaw=0.2 --auto-start-target=authority/sm0/c --start-file="$start_file" --stop-file="$stop_file" >"$log_root/a.stdout.log" 2>&1 &
a=$!; pids+=("$a")

echo "[SM0-P8.1] PIDs A=$a B=$b C=$c nested=$nested observer=$observer"
wait_marker "$observer_log" '"event":"SM0_P8_VISUAL_READY"' observer "$observer"
wait_marker "$observer_log" '"reference_frame_parented":true' observer-frame "$observer"
wait_marker "$nested_log" '"event":"SM0_P8_NESTED_READY"' nested "$nested"
wait_marker "$a_log" '"event":"SM0_P8_OUTER_READY"' A "$a"
wait_marker "$b_log" '"event":"SM0_P8_OUTER_READY"' B "$b"
wait_marker "$c_log" '"event":"SM0_P8_OUTER_READY"' C "$c"
wait_marker "$nested_log" '"event":"SM0_P8_ANCHOR_ACCEPTED"' nested-anchor "$nested"

touch "$start_file"
wait_marker "$c_log" '"event":"SM0_P8_TARGET_COMMITTED"' C-commit "$c"
wait_marker "$a_log" '"event":"SM0_P8_TRANSFER_COMPLETED"' A-complete "$a"
wait_marker "$a_log" '"event":"SM0_P8_TARGET_COMMITTED"' A-return "$a"
wait_marker "$c_log" '"event":"SM0_P8_TRANSFER_COMPLETED"' C-complete "$c"
wait_marker "$observer_log" '"outer_authority_epoch":3' observer-final "$observer"

b_forwards="$(grep -Fc '"event":"SM0_P8_ROUTE_FORWARDED"' "$b_log" || true)"
[[ "$b_forwards" -ge 8 ]] || { echo "B forwarded only $b_forwards phases" >&2; exit 1; }
grep -Fq '"player_entity_id":"player/a"' "$nested_log"
grep -Fq '"inner_authority_epoch":1' "$nested_log"

root_ids="$(grep -o '"ship_root_instance_id":[0-9][0-9]*' "$observer_log" | cut -d: -f2 | sort -u | wc -l | tr -d ' ')"
ship_ids="$(grep -o '"ship_visual_instance_id":[0-9][0-9]*' "$observer_log" | cut -d: -f2 | sort -u | wc -l | tr -d ' ')"
player_ids="$(grep -o '"player_visual_instance_id":[0-9][0-9]*' "$observer_log" | cut -d: -f2 | sort -u | wc -l | tr -d ' ')"
[[ "$root_ids" -eq 1 && "$ship_ids" -eq 1 && "$player_ids" -eq 1 ]] || { echo "Visual identity changed" >&2; exit 1; }

if [[ "$visual" -eq 1 && "$visual_hold_seconds" -gt 0 ]]; then
  echo "[SM0-P8.1] Visual proof holding ${visual_hold_seconds}s."
  sleep "$visual_hold_seconds"
fi

touch "$stop_file"
wait "$a"; wait "$b"; wait "$c"; wait "$nested"; wait "$observer"
pids=()
cleanup_uids
status_after="$(git -C "$project_root" status --short)"
if [[ "$allow_dirty" -ne 1 && "$status_after" != "$status_before" ]]; then
  echo "P8.1 gate modified source worktree" >&2
  printf 'before:\n%s\nafter:\n%s\n' "$status_before" "$status_after" >&2
  exit 1
fi
trap - EXIT

echo
echo "SM0-P8.1 visual/reference-frame repair: PASS"
echo "  HEAD      : $head_sha"
echo "  focused   : P8 96 assertions + P8.1 33 assertions"
echo "  process   : A -> C -> A / B forwarded $b_forwards phases"
echo "  visual    : $visual"
echo "  logs      : $log_root"
