#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
godot_bin="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
expected_version="4.7.1.stable.double.custom_build.a13da4feb"

if [[ ! -x "$godot_bin" ]]; then
    echo "Godot binary not found or not executable: $godot_bin" >&2
    exit 2
fi

actual_version="$("$godot_bin" --version | head -n 1 | tr -d '\r')"
if [[ "$actual_version" != "$expected_version" ]]; then
    echo "Unexpected Godot version: $actual_version" >&2
    echo "Expected: $expected_version" >&2
    exit 3
fi

run_script() {
    local script_path="$1"
    "$godot_bin" --headless --path "$repo_root" --script "$script_path"
}

run_script res://tests/research/fabric_bake0/fabric_bake_b0_0_acceptance.gd
run_script res://tests/research/fabric_bake0/fabric_bake_b0_1_acceptance.gd
run_script res://tests/research/fabric_bake0/fabric_bake_b0_1_playground.gd
run_script res://tests/research/fabric_bake0/fabric_bake_b0_2_ab_acceptance.gd
run_script res://tests/research/fabric_bake0/fabric_bake_b0_2_ab_playground.gd
