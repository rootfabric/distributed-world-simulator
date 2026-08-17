#!/usr/bin/env bash
(
set -Eeuo pipefail

expected_version="4.7.1.stable.double.custom_build.a13da4feb"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
godot_bin="${1:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
temp_root="$(mktemp -d /tmp/dws-eco-vis2-2d-lab-XXXXXXXX)"

cleanup() {
    rm -rf "$temp_root"
}
trap cleanup EXIT

test -x "$godot_bin" || {
    echo "Godot executable not found or not executable: $godot_bin"
    exit 1
}

version="$("$godot_bin" --version)"
echo "$version"
[[ "$version" == *"$expected_version"* ]] || {
    echo "ECO VIS2.2-D requires exact Godot $expected_version"
    exit 1
}

cat > "$temp_root/project.godot" <<'EOF'
[application]
config/name="ECO VIS2.2-D Integrated Replicated Observatory Ubuntu Lab"
run/main_scene="res://scenes/labs/ecology/eco_vis2_2_integrated_observatory_lab.tscn"

[display]
window/size/viewport_width=1440
window/size/viewport_height=900
window/size/window_width_override=1440
window/size/window_height_override=900

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
EOF

mkdir -p \
    "$temp_root/scripts/labs" \
    "$temp_root/scripts/research" \
    "$temp_root/scenes/labs"

cp -a "$repo_root/scripts/labs/ecology" "$temp_root/scripts/labs/"
cp -a "$repo_root/scripts/research/ecology" "$temp_root/scripts/research/"
cp -a "$repo_root/scenes/labs/ecology" "$temp_root/scenes/labs/"

echo "=== ECO VIS2.2-D Ubuntu graphical final-repair lab ==="
echo "exact_engine=$expected_version"
echo "F          fork replicated experiment"
echo "Right      next generation"
echo "Left       bounded rewind; clamps at common rolling-cache floor"
echo "Space      play/pause"
echo "R          restart from immutable fork"
echo "[ / ]      select visible Treatment replicate (presentation-only)"
echo "2/3/4/5    DROUGHT/FLOOD/NUTRIENT_PULSE/SHADE"
echo "- / +      Treatment intensity"
echo
echo "Final repair graphical check:"
echo "1. Fork with F and advance >64 generations (Space is fastest)."
echo "2. Pause and press Left repeatedly. Generation must decrease until the common cache floor, then clamp there."
echo "3. Aggregate panel must truncate to the same visible generation."
echo "4. Exactly one Treatment field remains visible; selection with [/] must not advance/replay simulation."
echo "5. At the rewound generation choose a different Treatment; the new effect starts at next generation."
echo "6. Close the Godot window to return to shell."

echo
BREAKPOINT_RUNTIME_DISABLED=1 "$godot_bin" \
    --path "$temp_root" \
    res://scenes/labs/ecology/eco_vis2_2_integrated_observatory_lab.tscn
)
