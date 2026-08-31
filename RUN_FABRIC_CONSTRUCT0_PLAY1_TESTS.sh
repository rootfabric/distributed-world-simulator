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

if [[ -f "$repo_root/RUN_FABRIC_CONSTRUCT0_C0_3_TESTS.sh" ]]; then
    GODOT_BIN="$godot_bin" bash "$repo_root/RUN_FABRIC_CONSTRUCT0_C0_3_TESTS.sh"
fi

play1_log="$(mktemp)"
set +e
"$godot_bin" --headless --path "$repo_root" --script res://tests/research/fabric_construct0/fabric_construct0_play1_acceptance.gd 2>&1 | tee "$play1_log"
play1_status=${PIPESTATUS[0]}
set -e
if [[ "$play1_status" -ne 0 ]]; then
    rm -f "$play1_log"
    exit "$play1_status"
fi
if grep -Eq 'SCRIPT ERROR:|ERROR: Failed to load script' "$play1_log"; then
    echo "PLAY1 fatal script marker detected" >&2
    rm -f "$play1_log"
    exit 4
fi
rm -f "$play1_log"
