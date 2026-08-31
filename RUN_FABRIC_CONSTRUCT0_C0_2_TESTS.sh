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

if [[ -f "$repo_root/RUN_FABRIC_CONSTRUCT0_C0_1_TESTS.sh" ]]; then
    GODOT_BIN="$godot_bin" bash "$repo_root/RUN_FABRIC_CONSTRUCT0_C0_1_TESTS.sh"
fi
"$godot_bin" --headless --path "$repo_root" --script res://tests/research/fabric_construct0/fabric_construct0_c0_2_acceptance.gd
