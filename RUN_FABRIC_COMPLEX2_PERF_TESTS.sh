#!/usr/bin/env bash
set -euo pipefail
GODOT_BIN="${GODOT_BIN:-godot}"
"$GODOT_BIN" --headless --path "$(cd "$(dirname "$0")" && pwd)" --script res://tests/research/fabric_bake0/fabric_bake_complex2_perf_scaling_acceptance.gd
