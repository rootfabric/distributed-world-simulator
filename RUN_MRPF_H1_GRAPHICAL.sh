#!/usr/bin/env bash
set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_EXE="${GODOT_EXE:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"

export BREAKPOINT_RUNTIME_DISABLED=1
exec "$GODOT_EXE" \
    --headless \
    --path "$PROJECT_ROOT" \
    --script res://tests/runtime/seamless/mrpf/test_mrpf_h1_space_earth_process.gd \
    -- \
    --graphical-client=true \
    --phase-hold-ms=1500
