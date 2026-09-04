#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
GODOT_BIN="${GODOT_BIN:-$HOME/.local/opt/godot-double-4.7.1-a13da4f/godot.linuxbsd.editor.double.x86_64}"
export GODOT_BIN

bash ./RUN_FABRIC_BAKE_B0_5_P0_TESTS.sh
bash ./RUN_FABRIC_BAKE_B0_5_A_TESTS.sh

echo "FABRIC-BAKE B0.5-A closure chain: PASS"
