#!/usr/bin/env bash
set -euo pipefail
PROJECT_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
GODOT_EXE="${GODOT_EXE:-godot}"
EXPECTED_VERSION="4.7.1.stable.double.custom_build.a13da4feb"
ACTUAL_VERSION="$($GODOT_EXE --version | tr -d '\r')"
if [[ "$ACTUAL_VERSION" != "$EXPECTED_VERSION" ]]; then
  echo "MRPF-H0: Godot version mismatch: expected $EXPECTED_VERSION, got $ACTUAL_VERSION" >&2
  exit 2
fi
exec "$GODOT_EXE" --headless --path "$PROJECT_ROOT" --script res://tests/runtime/seamless/mrpf/test_mrpf_h0_hierarchical_projection.gd
