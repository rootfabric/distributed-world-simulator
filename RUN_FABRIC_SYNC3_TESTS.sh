#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

GODOT_BIN="${GODOT_BIN:-${GODOT:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}}"
export GODOT_BIN

bash ./RUN_FABRIC_BAKE_B0_4_D_TESTS.sh
bash ./RUN_FABRIC_BAKE_B0_5_P0_TESTS.sh

"$GODOT_BIN" --headless --path . --script res://tests/research/fabric_bake0/fabric_sync3_b0_4_b0_5_p0_acceptance.gd

echo "FABRIC.SYNC3 focused synchronization chain: PASS"
