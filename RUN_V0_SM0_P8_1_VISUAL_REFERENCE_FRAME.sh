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
[[ -x "$godot_bin" ]] || { echo "Godot 4.7.1 double binary missing/executable bit absent: $godot_bin" >&2; exit 2; }
[[ "$visual_hold_seconds" =~ ^[0-9]+$ ]] || { echo "visual hold seconds must be an integer >= 0" >&2; exit 2; }

version="$($godot_bin --version | head -n1)"
[[ "$version" == *"4.7.1.stable.double.custom_build.a13da4feb"* ]] || {
    echo "Unexpected Godot version: $version" >&2
    exit 2
}

head_sha="$(git -C "$project_root" rev-parse HEAD)"
status_before="$(git -C "$project_root" status --short)"
if [[ -n "$status_before" && "$allow_dirty" -ne 1 ]]; then
    echo "P8.1 gate requires a clean worktree:" >&2
    printf '%s\n' "$status_before" >&2
    exit 2
fi

mapfile -t uid_before < <(git -C "$project_root" ls-files --others --exclude-standard -- ':(glob)**/*.uid')
declare -A uid_before_set=()
for relative_uid in "${uid_before[@]}"; do
    uid_before_set["$relative_uid"]=1
done

remove_generated_uid_sidecars() {
    local -a uid_after=()
    local relative_uid
    mapfile -t uid_after < <(git -C "$project_root" ls-files --others --exclude-standard -- ':(glob)**/*.uid')
    for relative_uid in "${uid_after[@]}"; do
        if [[ -z "${uid_before_set[$relative_uid]+x}" ]]; then
            rm -f -- "$project_root/$relative_uid"
            echo "[SM0-P8.1] Removed run-generated UID sidecar: $relative_uid"
        fi
    done
}

export BREAKPOINT_RUNTIME_DISABLED=1
run_id="$(date +%Y%m%d-%H%M%S)-$$"
log_root="$project_root/artifacts/runtime/sm0-p8-1-$run_id"
mkdir -p "$log_root"

log_observer="$log_root/observer.log"
log_nested="$log_root/nested.log"
log_a="$log_root/a.log"
log_b="$log_root/b.log"
log_c="$log_root/c.log"
start_file="$log_root/start.flag"
stop_file="$log_root/stop.flag"

pids=()
cleanup() {
    touch "$stop_file" 2>/dev/null || true
    for pid in "${pids[@]:-}"; do
        [[ -n "$pid" ]] || continue
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    remove_generated_uid_sidecars || true
}
trap cleanup EXIT

wait_for_marker() {
    local file="$1"
    local marker="$2"
    local label="$3"
    local pid="$4"
    local i
    for i in $(seq 1 400); do
        if [[ -f "$file" ]] && grep -Fq "$marker" "$file"; then
            return 0
        fi
        if [[ -f "$file" ]] && grep -Eq 'SCRIPT ERROR|Parse Error|Failed to load script|setup_failed|SM0_INVARIANT_VIOLATION' "$file"; then
            echo "Fatal marker in $label ($file)" >&2
            tail -n 120 "$file" >&2 || true
            return 1
        fi
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "$label exited before marker: $marker" >&2
            tail -n 120 "$file" >&2 || true
            return 1
        fi
        sleep 0.05
    done
    echo "Timeout waiting for $label marker: $marker" >&2
    tail -n 120 "$file" >&2 || true
    return 1
}

run_focused() {
    local script="$1"
    local marker="$2"
    local log="$3"
    "$godot_bin" --headless --path "$project_root" --script "$script" 2>&1 | tee "$log"
    local result=${PIPESTATUS[0]}
    [[ "$result" -eq 0 ]] || return "$result"
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

run_focused \
    res://tests/runtime/seamless/sm0/test_sm0_p8_moving_nested_island.gd \
    'SM0 P8 moving nested authority island: PASS (96 assertions)' \
    "$log_root/p8-focused.log"

run_focused \
    res://tests/runtime/seamless/sm0/test_sm0_p8_1_visual_reference_frame.gd \
    'SM0 P8.1 visual reference-frame repair: PASS (33 assertions)' \
    "$log_root/p8-1-focused.log"

observer_args=(
    --path "$project_root"
    --log-file "$log_observer"
    --script res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_observer_process.gd
    --
    --listen-port=26524
    --visual-response-hz=14.0
    --stop-file="$stop_file"
)
if [[ "$visual" -eq 0 ]]; then
    "$godot_bin" --headless "${observer_args[@]}" >"$log_root/observer.stdout.log" 2>&1 &
else
    "$godot_bin" "${observer_args[@]}" >"$log_root/observer.stdout.log" 2>&1 &
fi
observer=$!; pids+,=("$observer")

"$godot_bin" --headless --path "$project_root" --log-file "$log_nested" \
    --script res://scripts/runtime/seamless/sm0/sm0_p8_nested_authority_process.gd -- \
    --anchor-port=26523 --view-port=26524 --stop-file="$stop_file" \
    >"$log_root/nested.stdout.log" 2>&1 &
nested=$!; pids+=("$nested")

"$godot_bin" --headless --path "$project_root" --log-file "$log_b" \
    --script res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_outer_process.gd -- \
    --authority-id=authority/sm0/b --listen-port=26521 \
    --neighbor-a-port=26520 --neighbor-c-port=26522 --stop-file="$stop_file" \
    >"$log_root/b.stdout.log" 2>&1 &
b=$!; pids+=("$b")

"$godot_bin" --headless --path "$project_root" --log-file "$log_c" \
    --script res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_outer_process.gd -- \
    --authority-id=authority/sm0/c --listen-port=26522 \
    --neighbor-b-port=26521 --anchor-port=26523 --initial-writer=false \
    --auto-return-target=authority/sm0/a --stop-file="$stop_file" \
    >"$log_root/c.stdout.log" 2>&1 &
c=$!; pids+=("$c")

"$godot_bin" --headless --path "$project_root" --log-file "$log_a" \
    --script res://scripts/runtime/seamless/sm0/sm0_p8_moving_island_outer_process.gd -- \
    --authority-id=authority/sm0/a --listen-port=26520 \
    --neighbor-b-port=26521 --anchor-port=26523 --initial-writer=true \
    --initial-x=-1.0 --velocity-x=0.8 --velocity-z=0.1 --angular-velocity-yaw=0.2 \
    --auto-start-target=authority/sm0/c --start-file="$start_file" --stop-file="$stop_file" \
    >"$log_root/a.stdout.log" 2>&1 &
a=$!; pids+=("$a")

echo "[SM0-P8.1] Five-process proof:"
echo "  A        PID=$a"
echo "  B        PID=$b"
echo "  C        PID=$c"
echo "  nested   PID=$nested"
echo "  observer PID=$observer"

wait_for_marker "$log_observer" '"event":"SM0_P8_VISUAL_READY"' observer "$observer"
wait_for_marker "$log_observer" '"reference_frame_parented":true' observer-frame-contract "$observer"
wait_for_marker "$log_nested" '"event":"SM0_P8_NESTED_READY"' nested "$nested"
wait_for_marker "$log_a" '"event":"SM0_P8_OUTER_READY"' outer-a "$a"
wait_for_marker "$log_b" '"event":"SM0_P8_OUTER_READY"' transit-b "$b"
wait_for_marker "$log_c" '"event":"SM0_P8_OUTER_READY"' outer-c "$c"
wait_for_marker "$log_nested" '"event":"SM0_P8_ANCHOR_ACCEPTED"' nested-anchor "$nested"

touch "$start_file"
wait_for_marker "$log_a" '"event":"SM0_P8_SOURCE_RETIRED"' outer-a "$a"
wait_for_marker "$log_c" '"event":"SM0_P8_TARGET_COMMITTED"' outer-c "$c"
wait_for_marker "$log_a" '"event":"SM0_P8_TRANSFER_COMPLETED"' outer-a "$a"
wait_for_marker "$log_c" '"event":"SM0_P8_SOURCE_RETIRED"' outer-c "$c"
wait_for_marker "$log_a" '"event":"SM0_P8_TARGET_COMMITTED"' outer-a "$a"
wait_for_marker "$log_c" '"event":"SM0_P8_TRANSFER_COMPLETED"' outer-c "$c"
wait_for_marker "$log_observer" '"outer_authority_epoch":3' observer-final "$observer"

nested_changes="$(grep -Fc '"event":"SM0_P8_OUTER_OWNER_CHANGED"' "$log_nested" || true)"
observer_changes="$(grep -Fc '"event":"SM0_P8_VISUAL_OUTER_OWNER_CHANGED"' "$log_observer" || true)"
b_forwards="$(grep -Fc '"event":"SM0_P8_ROUTE_FORWARDED"' "$log_b" || true)"
[[ "$nested_changes" -ge 2 ]] || { echo "nested saw only $nested_changes outer-owner changes" >&2; exit 1; }
[[ "$observer_changes" -ge 2 ]] || { echo "observer saw only $observer_changes outer-owner changes" >&2; exit 1; }
[[ "$b_forwards" -ge 8 ]] || { echo "transit B forwarded only $b_forwards phases" >&2; exit 1; }

grep -Fq '"player_entity_id":"player/a"' "$log_nested"
grep -Fq '"inner_authority_epoch":1' "$log_nested"
grep -Fq '"outer_authority_epoch":2' "$log_c"
grep -Fq '"outer_authority_epoch":3' "$log_a"

root_id_count="$(grep -o '"ship_root_instance_id":[0-9][0-9]*' "$log_observer" | cut -d: -f2 | sort -u | wc -l | tr -d ' ')"
ship_id_count="$(grep -o '"ship_visual_instance_id":[0-9][0-9]*' "$log_observer" | cut -d: -f2 | sort -u | wc -l | tr -d ' ')"
player_id_count="$(grep -o '"player_visual_instance_id":[0-9][0-9]*' "$log_observer" | cut -d: -f2 | sort -u | wc -l | tr -d ' ')"
R[[ "$root_id_count" -eq 1 ]] || { echo "ShipRoot visual identity changed" >&2; exit 1; }
[[ "$ship_id_count" -eq 1 ]] || { echo "ship visual identity changed" >&2; exit 1; }
[[ "$player_id_count" -eq 1 ]] || { echo "player visual identity changed" >&2; exit 1; }

for file in "$log_observer" "$log_nested" "$log_a" "$log_b" "$log_c"; do
    if grep -Eq 'SCRIPT ERROR|Parse Error|Failed to load script|SMP0_INVARIANT_VIOLATION' "$file"; then
        echo "Fatal marker in $file" >&2
        tail -n 120 "$file" >&2
        exit 1
    fi
done

if [[ "$visual" -eq 1 && "$visual_hold_seconds" -gt 0 ]]; then
    echo "[SM0-P8.1] Visual proof holding ${visual_hold_seconds}s. WHITE=A, GREEN=C, YELLOW=player/a inside ShipRoot."
    sleep "$visual_hold_seconds"
fi

touch "$stop_file"
wait "$a"
wait "$b"
wait "$c"
wait "$nested"
wait "$observer"
pids=()

remove_generated_uid_sidecars
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
echo "  frame     : persistent ShipRoot parents ship + player"
echo "  yaw       : -world_yaw matches canonical P8 composition"
echo "  process   : A -> C -> A / B forwarded $b_forwards phases"
echo "  identities: ShipRoot + ship + player persistent"
echo "  visual    : $visual"
echo "  logs      : $log_root"
