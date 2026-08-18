#!/usr/bin/env bash
set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_EXE="${GODOT_EXE:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
EXPECTED_VERSION="4.7.1.stable.double.custom_build.a13da4feb"

if [ ! -x "$GODOT_EXE" ]; then
    echo "Godot executable not found: $GODOT_EXE" >&2
    exit 2
fi

actual_version="$($GODOT_EXE --version | head -n 1 | tr -d '\r')"
if [ "$actual_version" != "$EXPECTED_VERSION" ]; then
    echo "Unexpected Godot version: $actual_version" >&2
    echo "Expected: $EXPECTED_VERSION" >&2
    exit 2
fi

export BREAKPOINT_RUNTIME_DISABLED=1
exec "$GODOT_EXE" \
    --headless \
    --path "$PROJECT_ROOT" \
    --script res://tests/runtime/seamless/mrpf/test_mrpf_h1_space_earth_process.gd
