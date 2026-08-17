#!/usr/bin/env bash
(
set -Eeuo pipefail

expected_version="4.7.1.stable.double.custom_build.a13da4feb"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
godot_bin="${1:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
artifacts="$repo_root/artifacts/runtime/eco-vis2-2d-ubuntu"
temp_root="$(mktemp -d /tmp/dws-eco-vis2-2d-XXXXXXXX)"

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
        exit 1
    fi
}

mkdir -p "$artifacts"

echo "=== ECO VIS2.2-D Ubuntu focused gate ==="
echo "repo_root=$repo_root"
echo "godot=$godot_bin"

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

echo ">> ECO VIS2.2-D parser preflight"
if BREAKPOINT_RUNTIME_DISABLED=1 "$godot_bin" \
    --headless \
    --path "$temp_root" \
    --check-only \
    --script res://tests/research/ecology/test_eco_vis2_2_integrated_observatory_lab.gd \
    2>&1 | tee "$artifacts/parser.log"; then
    parser_result=0
else
    parser_result=${PIPESTATUS[0]}
fi

if [ "$parser_result" -ne 0 ]; then
    echo "ECO.VIS2.2-D parser preflight failed with exit code $parser_result"
    exit "$parser_result"
fi
fail_if_diagnostics "$artifacts/parser.log"
echo "ECO.VIS2.2-D parser preflight: PASS"

echo "ECO.VIS2.2-D shutdown leak gate: STRICT (ObjectDB + RID + resources + StringName + verbose smoke)"
echo ">> ECO VIS2.2-D integrated observatory smoke"
if BREAKPOINT_RUNTIME_DISABLED=1 "$godot_bin" \
    --verbose \
    --headless \
    --path "$temp_root" \
    --script res://tests/research/ecology/test_eco_vis2_2_integrated_observatory_lab.gd \
    2>&1 | tee "$artifacts/runtime.log"; then
    runtime_result=0
else
    runtime_result=${PIPESTATUS[0]}
fi

if [ "$runtime_result" -ne 0 ]; then
    echo "ECO.VIS2.2-D runtime smoke failed with exit code $runtime_result"
    exit "$runtime_result"
fi

fail_if_diagnostics "$artifacts/runtime.log"

grep -q 'ECO.VIS2.2-D integrated observatory lab: PASS' "$artifacts/runtime.log" || {
    echo "ECO.VIS2.2-D PASS marker missing"
    exit 1
}

echo "ECO.VIS2.2-D Ubuntu focused gate: PASS"
echo "parser_log=$artifacts/parser.log"
echo "runtime_log=$artifacts/runtime.log"
)
