#!/usr/bin/env bash
(
set -Eeuo pipefail

expected_version="4.7.1.stable.double.custom_build.a13da4feb"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
godot_bin="${1:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
artifacts="$repo_root/artifacts/runtime/eco-vis2-2-full-ubuntu"
temp_root="$(mktemp -d /tmp/dws-eco-vis2-2-full-XXXXXXXX)"
timeout_bin="$(command -v timeout || true)"

cleanup() {
    rm -rf "$temp_root"
}
trap cleanup EXIT

fail_if_diagnostics() {
    local log_file="$1"
    if grep -Eiq \
'(^SCRIPT ERROR:|^ERROR:|Parse Error|ObjectDB instances? (was|were) leaked at exit|Leaked instance:|[0-9]+ RID(s| allocations)? of type .* (was|were) leaked|Resource still in use:|resources? still in use at exit|Orphan StringName:|StringName: [0-9]+ unclaimed string names at exit|^WARNING:.*(leak|leaked|leaks|leaking|still in use))' \
        "$log_file"; then
        echo "Strict Godot diagnostics gate: FAIL ($log_file)"
        grep -Ein \
'(^SCRIPT ERROR:|^ERROR:|Parse Error|ObjectDB instances? (was|were) leaked at exit|Leaked instance:|[0-9]+ RID(s| allocations)? of type .* (was|were) leaked|Resource still in use:|resources? still in use at exit|Orphan StringName:|StringName: [0-9]+ unclaimed string names at exit|^WARNING:.*(leak|leaked|leaks|leaking|still in use))' \
            "$log_file" || true
        return 1
    fi
}

run_godot() {
    local label="$1"
    local timeout_seconds="$2"
    local log_file="$3"
    local pass_marker="$4"
    shift 4

    echo ">> $label"
    local result=0
    if "$timeout_bin" --foreground --signal=TERM --kill-after=10s "${timeout_seconds}s" \
        env BREAKPOINT_RUNTIME_DISABLED=1 "$godot_bin" "$@" 2>&1 | tee "$log_file"; then
        result=0
    else
        result=${PIPESTATUS[0]}
    fi

    if [ "$result" -eq 124 ] || [ "$result" -eq 137 ]; then
        echo "$label timed out after ${timeout_seconds}s"
        return 1
    fi
    if [ "$result" -ne 0 ]; then
        echo "$label failed with exit code $result"
        return "$result"
    fi

    fail_if_diagnostics "$log_file" || return 1

    if [ -n "$pass_marker" ]; then
        grep -Fq "$pass_marker" "$log_file" || {
            echo "$label PASS marker missing: $pass_marker"
            return 1
        }
    fi
}

mkdir -p "$artifacts"

echo "=== ECO VIS2.2 FULL Ubuntu acceptance gate ==="
echo "repo_root=$repo_root"
echo "godot=$godot_bin"
echo "temp_root=$temp_root"

[ -n "$timeout_bin" ] || {
    echo "GNU timeout command is required"
    exit 1
}

test -x "$godot_bin" || {
    echo "Godot executable not found or not executable: $godot_bin"
    exit 1
}

version="$("$godot_bin" --version)"
echo "$version"
[[ "$version" == *"$expected_version"* ]] || {
    echo "ECO VIS2.2 requires exact Godot $expected_version"
    exit 1
}
echo "ECO.VIS2.2 exact Godot identity: PASS"

superseded_paths=(
    "RUN_ECO_VIS2_2B_TESTS.ps1"
    "RUN_ECO_VIS2_2B_R1_TESTS.ps1"
    "tests/research/ecology/test_eco_vis2_2_aggregate_effect_model.gd"
    "tests/research/ecology/test_eco_vis2_2_aggregate_effect_model_r1.gd"
)
for stale_path in "${superseded_paths[@]}"; do
    if [ -e "$repo_root/$stale_path" ]; then
        echo "Superseded active test surface still exists: $stale_path"
        exit 1
    fi
done
echo "ECO.VIS2.2 superseded red test surface: ABSENT"

cat > "$temp_root/project.godot" <<'EOF'
[application]
config/name="ECO VIS2.2 Full Ubuntu Acceptance Gate"

[display]
window/size/viewport_width=1440
window/size/viewport_height=900

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
EOF

mkdir -p \
    "$temp_root/scripts/labs" \
    "$temp_root/scripts/research" \
    "$temp_root/scenes/labs" \
    "$temp_root/tests/research/ecology"

cp -a "$repo_root/scripts/labs/ecology" "$temp_root/scripts/labs/"
cp -a "$repo_root/scripts/research/ecology" "$temp_root/scripts/research/"
cp -a "$repo_root/scenes/labs/ecology" "$temp_root/scenes/labs/"

test_specs=(
    "test_eco_vis2_1_control_branch_runner.gd|ECO.VIS2.1-C control branch runner: PASS|300"
    "test_eco_vis2_1_treatment_branch_runner.gd|ECO.VIS2.1-T treatment branch runner R1: PASS|300"
    "test_eco_vis2_1_comparison_model.gd|ECO.VIS2.1 comparison model: PASS|300"
    "test_eco_vis1_8b_continuous_population_field.gd|ECO.VIS1.8B headless scene smoke: PASS|300"
    "test_eco_vis1_9_evolution_observatory.gd|ECO.VIS1.9 headless scene smoke: PASS|300"
    "test_eco_vis2_0_evolution_experiment_lab.gd|ECO.VIS2.0 headless scene smoke: PASS|300"
    "test_eco_vis2_1_control_vs_treatment_lab.gd|ECO.VIS2.1 control-vs-treatment integration: PASS|900"
    "test_eco_vis2_1v_treatment_realtime_lod_lab.gd|ECO.VIS2.1-V Treatment realtime LOD: PASS|600"
    "test_eco_vis2_2_replicate_pair_set.gd|ECO.VIS2.2-A replicated causal runner set: PASS|600"
    "test_eco_vis2_2_aggregate_effect_model_r2.gd|ECO.VIS2.2-B R2 canonical aggregate effect model: PASS|600"
    "test_eco_vis2_2_observatory_panel.gd|ECO.VIS2.2-C observatory panel: PASS|300"
    "test_eco_vis2_2_integrated_observatory_lab.gd|ECO.VIS2.2-D integrated observatory lab: PASS|900"
)

for spec in "${test_specs[@]}"; do
    IFS='|' read -r test_name pass_marker timeout_seconds <<< "$spec"
    test -f "$repo_root/tests/research/ecology/$test_name" || {
        echo "Required test missing: $test_name"
        exit 1
    }
    cp "$repo_root/tests/research/ecology/$test_name" "$temp_root/tests/research/ecology/"
done

echo "ECO.VIS2.2 isolated full ecology dependency graph: PASS"

echo
echo "=== Parser preflight chain ==="
for spec in "${test_specs[@]}"; do
    IFS='|' read -r test_name pass_marker timeout_seconds <<< "$spec"
    stem="${test_name%.gd}"
    run_godot \
        "parser $test_name" \
        300 \
        "$artifacts/${stem}.parser.log" \
        "" \
        --headless \
        --path "$temp_root" \
        --check-only \
        --script "res://tests/research/ecology/$test_name"
done
echo "ECO.VIS2.2 full parser preflight chain: PASS"

echo
echo "=== Runtime regression chain ==="
for spec in "${test_specs[@]}"; do
    IFS='|' read -r test_name pass_marker timeout_seconds <<< "$spec"
    stem="${test_name%.gd}"
    run_godot \
        "runtime $test_name" \
        "$timeout_seconds" \
        "$artifacts/${stem}.runtime.log" \
        "$pass_marker" \
        --verbose \
        --headless \
        --path "$temp_root" \
        --script "res://tests/research/ecology/$test_name"
done

echo
echo "ECO.VIS2.2 full Ubuntu acceptance gate: PASS"
echo "Exact engine: $expected_version"
echo "Tests: ${#test_specs[@]} parser + ${#test_specs[@]} runtime"
echo "Logs: $artifacts"
)
