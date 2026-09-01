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

if [[ -x "$repo_root/RUN_FABRIC_BAKE_B0_4_A_TESTS.sh" ]]; then
    GODOT_BIN="$godot_bin" "$repo_root/RUN_FABRIC_BAKE_B0_4_A_TESTS.sh"
fi

run_script() {
    local script="$1"
    local log
    log="$(mktemp)"
    set +e
    "$godot_bin" --headless --path "$repo_root" --script "$script" 2>&1 | tee "$log"
    local status=${PIPESTATUS[0]}
    set -e
    if [[ "$status" -ne 0 ]]; then
        rm -f "$log"
        exit "$status"
    fi
    if grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script' "$log"; then
        echo "B0.4-B fatal Godot script marker detected: $script" >&2
        rm -f "$log"
        exit 4
    fi
    rm -f "$log"
}

run_script res://tests/research/fabric_bake0/fabric_bake_b0_4_b_acceptance.gd
run_script res://tests/research/fabric_bake0/fabric_bake_b0_4_b_playground.gd
