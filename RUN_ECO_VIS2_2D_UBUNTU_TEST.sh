#!/usr/bin/env bash
(
set -Eeuo pipefail

expected_version="4.7.1.stable.double.custom_build.a13da4feb"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
godot_bin="${1:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
artifacts="$repo_root/artifacts/runtime/eco-vis2-2d-ubuntu"
temp_root="$(mktemp -d /tmp/dws-eco-vis2-2d-XXXXXXXX)"
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
        echo "ECO.VIS2.2-D strict diagnostics gate: FAIL"
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

echo "=== ECO VIS2.2-D Ubuntu focused gate ==="
echo "repo_root=$repo_root"
echo "godot=$godot_bin"

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
    echo "ECO.VIS2.2-D requires exact Godot $expected_version"
    exit 1
}
echo "ECO.VIS2.2-D exact Godot identity: PASS"

cat > "$temp_root/project.godot" <<'EOF'
[application]
config/name="ECO VIS2.2-D Integrated Replicated Observatory Ubuntu Gate"

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
cp \
    "$repo_root/tests/research/ecology/test_eco_vis2_2_integrated_observatory_lab.gd" \
    "$temp_root/tests/research/ecology/"

echo "ECO.VIS2.2-D isolated ecology dependency graph: PASS"

run_godot \
    "ECO VIS2.2-D parser preflight" \
    300 \
    "$artifacts/parser.log" \
    "" \
    --headless \
    --path "$temp_root" \
    --check-only \
    --script res://tests/research/ecology/test_eco_vis2_2_integrated_observatory_lab.gd

echo "ECO.VIS2.2-D parser preflight: PASS"
echo "ECO.VIS2.2-D shutdown leak gate: STRICT (ObjectDB + RID + resources + StringName + verbose smoke + timeout)"

run_godot \
    "ECO VIS2.2-D integrated observatory smoke" \
    900 \
    "$artifacts/runtime.log" \
    "ECO.VIS2.2-D integrated observatory lab: PASS" \
    --verbose \
    --headless \
    --path "$temp_root" \
    --script res://tests/research/ecology/test_eco_vis2_2_integrated_observatory_lab.gd

echo "ECO.VIS2.2-D Ubuntu focused gate: PASS"
echo "parser_log=$artifacts/parser.log"
echo "runtime_log=$artifacts/runtime.log"
)
